import { Router, Request } from 'express';
import { nowIso, withTransaction } from '../db';
import { asyncHandler } from '../middleware/asyncHandler';
import { uuidSchema } from '../dominio/validacion';
import { pagoProvider, obtenerPagoMercadoPago, PagoConfirmado } from '../integraciones/pagos';
import { verificarLimiteTurnosConfirmadosDelMes } from '../dominio/suscripciones';

export const webhooksRouter = Router();

/**
 * Extrae el id del pago (`dataId`) y el tipo de notificación de un request de Mercado Pago —
 * documento-arquitectura.md §1/§5 ya anticipaba esta ruta (`POST /webhooks/mercadopago`, "Pagos
 * Module... escucha el webhook de confirmación"); este helper resuelve el primer paso: entender
 * QUÉ mandó Mercado Pago, sea cual sea el formato de notificación que use.
 *
 * Mercado Pago manda esto por query string y/o body según la versión de la notificación — se
 * soportan ambas fuentes y los 2 formatos documentados públicamente:
 *  - "Webhooks" (formato nuevo): query `?data.id=<id>&type=payment` y/o body
 *    `{ type: 'payment', data: { id: '<id>' } }`.
 *  - "IPN" (formato legado, todavía en uso en paralelo): query `?id=<id>&topic=payment`.
 * `type`/`topic` se tratan como equivalentes (mismo significado, nombre distinto por formato).
 */
function extraerNotificacion(req: Request): { paymentId: string | null; tipo: string | null } {
  const query = req.query as Record<string, unknown>;
  const body = req.body as { type?: unknown; topic?: unknown; id?: unknown; data?: { id?: unknown } } | undefined;

  const paymentId =
    (typeof query['data.id'] === 'string' ? query['data.id'] : undefined) ??
    (body?.data?.id !== undefined ? String(body.data.id) : undefined) ??
    (typeof query['id'] === 'string' ? query['id'] : undefined) ??
    (body?.id !== undefined ? String(body.id) : undefined) ??
    null;

  const tipo =
    (typeof query['type'] === 'string' ? query['type'] : undefined) ??
    (typeof body?.type === 'string' ? body.type : undefined) ??
    (typeof query['topic'] === 'string' ? query['topic'] : undefined) ??
    (typeof body?.topic === 'string' ? body.topic : undefined) ??
    null;

  return { paymentId, tipo };
}

// HU-29/RN10 (2026-08-17) — cierre del gap documentado en integraciones/pagos.ts (HALLAZGO
// 2026-08-14): este webhook es el ÚNICO lugar del backend donde un turno 'pendiente_de_pago'
// transiciona a 'confirmado' por un pago real confirmado — hasta este cambio, ese turno solo
// podía expirar a 'cancelado' (src/jobs/expirarPagosPendientes.ts) o quedar colgado para siempre.
//
// Sin `requireAuth`, a propósito: no lo llama un usuario de la app, lo llama el servidor de
// Mercado Pago — la autenticación acá ES la validación de firma (paso (b) más abajo), no un JWT.
webhooksRouter.post(
  '/mercadopago',
  asyncHandler(async (req, res) => {
    // (a) Filtrar notificaciones que no son de pago (ej. `merchant_order`, que Mercado Pago
    // también manda) — no es un error, simplemente no es relevante para este backend.
    const { paymentId, tipo } = extraerNotificacion(req);
    if (tipo !== 'payment') {
      return res.status(200).json({ ok: true });
    }
    if (!paymentId) {
      // No debería pasar en un flujo normal (mismo espíritu que (d) más abajo): un `type` de pago
      // sin ningún id de pago extraíble indica una notificación ajena o corrupta, no un caso real
      // de Mercado Pago — se loguea server-side (mismo estilo que expirarPagosPendientes.ts) para
      // poder investigar si se repite.
      // eslint-disable-next-line no-console
      console.error('[webhooks] Notificación de Mercado Pago tipo "payment" sin id de pago extraíble:', {
        query: req.query,
        body: req.body,
      });
      return res.status(400).json({ error: 'Notificación inválida' });
    }

    // (b) La autenticación de este endpoint ES esto: sin JWT (nadie autenticado llama a un
    // webhook), la única prueba de que la notificación viene realmente de Mercado Pago es su
    // firma (documento-arquitectura.md §5: "Webhook de Mercado Pago validado por firma, no solo
    // por IP de origen"). Si no valida, 401 inmediato — SIN tocar la base de datos: no hay
    // ninguna garantía todavía de que `paymentId` corresponda a un pago real de este negocio.
    const firmaValida = pagoProvider.validarWebhook(
      { dataId: paymentId, requestId: req.header('x-request-id') },
      req.header('x-signature')
    );
    if (!firmaValida) {
      return res.status(401).json({ error: 'Firma inválida' });
    }

    // (c) Firma OK — recién acá se confía en `paymentId` lo suficiente como para preguntarle a
    // Mercado Pago por el pago real (status + external_reference + monto). Mismo criterio que
    // GOOGLE_CLIENT_ID ausente en auth.ts (ver verificarIdTokenGoogle) y que `POST /turnos/:id/pago`
    // (turnos.ts): sin MP_ACCESS_TOKEN configurado, esto tira recién al invocarse (nunca al
    // importar el módulo, ver integraciones/pagos.ts) — se atrapa acá y se responde 503 en vez de
    // dejar que el error handler genérico de app.ts lo convierta en un 500 opaco.
    let pagoMp: PagoConfirmado;
    try {
      pagoMp = await obtenerPagoMercadoPago(paymentId);
    } catch (err) {
      // [INFORMATIVO-1, revisión de Security 2026-08-17] Este catch cubre tanto "falta
      // MP_ACCESS_TOKEN" (esperable, no accionable) como una falla real de red/API de Mercado
      // Pago (sí accionable) — sin loguear, la segunda quedaba invisible salvo por reportes de
      // usuarios. Mismo estilo que expirarPagosPendientes.ts.
      // eslint-disable-next-line no-console
      console.error('[webhooks] Error consultando el pago en Mercado Pago:', paymentId, err);
      return res.status(503).json({ error: 'Mercado Pago no está disponible/configurado en este entorno' });
    }

    // (d) `external_reference` (turnoId) sale de Mercado Pago, no de un valor que este backend ya
    // validó — mismo criterio de "nunca confiar en un valor sin re-derivarlo/validarlo" que ya usa
    // este backend (ver auth.ts, POST /auth/entrar-a-negocio). No debería pasar en un flujo normal
    // (todo pago se crea con `crearIntencion(turno.id, ...)`, ver POST /turnos/:id/pago en
    // turnos.ts, que manda el propio `turno.id` como referencia) — indicaría una notificación
    // ajena a este backend o corrupta.
    const turnoIdParsed = uuidSchema.safeParse(pagoMp.turnoId);
    if (!turnoIdParsed.success) {
      // eslint-disable-next-line no-console
      console.error('[webhooks] Pago de Mercado Pago con external_reference ausente o no-UUID:', pagoMp);
      return res.status(400).json({ error: 'Notificación inválida' });
    }
    const turnoId = turnoIdParsed.data;

    // (e) Mismo mecanismo EXACTO que src/jobs/expirarPagosPendientes.ts (ver ese archivo): este
    // handler no tiene ningún usuario autenticado (nadie seteó app.usuario_id/app.negocio_id), así
    // que corre con `jobSistema: true` — la única policy de UPDATE sobre `turno` que no depende de
    // esa identidad es `turno_acceso_job_expiracion` (database/migrations/001_init.sql ~línea
    // 1108), acotada SOLO a `current_setting('app.job_sistema', true) = 'true'`, sin restringir a
    // qué valor de `estado` se puede escribir — sirve tal cual para este UPDATE también, no hace
    // falta ninguna policy nueva de DBA. `pago` no tiene RLS habilitada, así que su UPDATE no
    // depende de esto — pero se mantiene todo en la MISMA transacción de todos modos, mismo
    // criterio que ese job.
    const resultado = await withTransaction(
      async (client) => {
        // `FOR UPDATE`: Mercado Pago puede reintentar la misma notificación más de una vez — esto
        // evita que 2 entregas concurrentes de la misma notificación se pisen.
        const turnoResult = await client.query(
          `SELECT t.*, p.id AS pago_id, p.estado AS pago_estado
           FROM turno t
           JOIN pago p ON p.turno_id = t.id
           WHERE t.id = $1
           FOR UPDATE`,
          [turnoId]
        );
        const fila = turnoResult.rows[0] as
          | {
              id: string;
              negocio_id: string;
              inicio: string;
              estado: string;
              pago_id: string;
              pago_estado: string;
            }
          | undefined;
        if (!fila) return { tipo: 'no_encontrado' as const };

        // Idempotencia: Mercado Pago reintenta notificaciones — este webhook tiene que poder
        // recibir la misma notificación más de una vez sin duplicar efectos (ni volver a evaluar
        // el límite de HU-29 más abajo, que en un reintento posterior podría dar un resultado
        // distinto del que ya se aplicó la primera vez).
        if (fila.pago_estado === 'acreditado') return { tipo: 'ya_procesado' as const };

        // Todavía no hay nada que confirmar (pending/in_process/rejected/etc.) — Mercado Pago va a
        // mandar otra notificación cuando el pago cambie de estado.
        if (pagoMp.estadoPago !== 'approved') return { tipo: 'no_aprobado' as const };

        const ts = nowIso();
        await client.query(
          `UPDATE pago SET estado = 'acreditado', referencia_externa = $1, modificado_en = $2 WHERE id = $3`,
          [pagoMp.paymentId, ts, fila.pago_id]
        );

        // [ALTO-1, revisión de Security 2026-08-17] Espejo del fix aplicado el mismo día en
        // expirarPagosPendientes.ts: ese fix evita que el JOB pise una confirmación que este
        // webhook ya hizo (agregando `AND estado = 'pendiente_de_pago'` a SU update); esto evita
        // el sentido contrario — que ESTE webhook pise un turno que ya salió de
        // 'pendiente_de_pago' por otra vía mientras la notificación de Mercado Pago viajaba
        // (el propio job de expiración, si la entrega del webhook se demoró más de
        // EXPIRACION_PAGO_MIN, o el cliente cancelando/reprogramando explícitamente antes de que
        // llegara). Sin esto, una notificación de pago aprobado legítima pero demorada podía
        // "resucitar" en silencio un turno que el propio sistema (o el cliente) ya había dado por
        // cancelado. `fila.estado` es seguro de usar acá (a diferencia de un `WHERE` en el UPDATE
        // de abajo, que sería redundante): viene del mismo `SELECT ... FOR UPDATE` de arriba, y
        // ningún `await` de esta transacción suelta ese lock de fila antes de este punto — ninguna
        // otra transacción pudo haber cambiado `turno.estado` mientras tanto.
        //
        // `pago.estado = 'acreditado'` ya quedó escrito arriba a propósito, incondicional: el
        // dinero SÍ se cobró, es un hecho real que tiene que quedar registrado sin importar qué
        // pasó con el turno después — lo único que se saltea acá es la transición de
        // `turno.estado` (y, de paso, el chequeo de límite de HU-29 de abajo, que no tiene sentido
        // evaluar si de todos modos no se va a confirmar nada).
        if (fila.estado !== 'pendiente_de_pago') {
          return {
            tipo: 'turno_no_pendiente' as const,
            estadoTurno: fila.estado,
            negocioId: fila.negocio_id,
            pagoId: fila.pago_id,
          };
        }

        // HU-29 (Turnario Pro) — a propósito la variante `verificarLimiteTurnosConfirmadosDelMes`
        // (DEVUELVE `{ permitido, motivo }`), NO `exigirLimiteTurnosConfirmadosDelMes` (la que
        // LANZA) que sí usan `POST /turnos` y `POST /profesionales/:id/turnos` (ver esos
        // comentarios en turnos.ts/profesionales.ts): ahí un límite alcanzado tiene que abortar
        // TODA la transacción — el turno nunca llegó a existir, así que un ROLLBACK completo es
        // correcto y deseable. Acá es exactamente al revés: Mercado Pago YA CAPTURÓ el pago del
        // cliente ANTES de que este webhook corra — no hay ningún ROLLBACK de este lado que pueda
        // deshacer eso. Si se usara la variante que lanza acá, un límite alcanzado tiraría la
        // excepción, `withTransaction` haría ROLLBACK de TODA la transacción — incluyendo el
        // UPDATE de `pago` de arriba, que es un hecho real (el dinero ya se cobró) y tiene que
        // quedar registrado sí o sí, límite alcanzado o no.
        const chequeo = await verificarLimiteTurnosConfirmadosDelMes(client, fila.negocio_id, new Date(fila.inicio));
        if (!chequeo.permitido) {
          // Pago acreditado pero `turno.estado` se queda en 'pendiente_de_pago' — un estado
          // inconsistente de NEGOCIO, no de datos (el cliente pagó, el negocio está al tope del
          // plan gratis). Resolverlo (reembolso o upgrade de plan manual) queda fuera de alcance
          // de este cambio — lo importante es que quede visible en los logs (más abajo, fuera de
          // la transacción), no silencioso.
          return {
            tipo: 'limite_alcanzado' as const,
            motivo: chequeo.motivo!,
            negocioId: fila.negocio_id,
            pagoId: fila.pago_id,
          };
        }

        await client.query(`UPDATE turno SET estado = 'confirmado', modificado_en = $1 WHERE id = $2`, [
          ts,
          fila.id,
        ]);
        return { tipo: 'confirmado' as const };
      },
      { jobSistema: true }
    );

    // Se responde 200 en TODOS los casos de acá para abajo salvo 'no_encontrado' — incluido
    // 'limite_alcanzado': devolver un error donde el único problema es de negocio (no una falla
    // transitoria de este servidor) solo lograría que Mercado Pago reintente indefinidamente algo
    // que un reintento no puede arreglar.
    switch (resultado.tipo) {
      case 'no_encontrado':
        // eslint-disable-next-line no-console
        console.error('[webhooks] Notificación de Mercado Pago para un turno/pago inexistente:', {
          turnoId,
          paymentId: pagoMp.paymentId,
        });
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'ya_procesado':
      case 'no_aprobado':
      case 'confirmado':
        return res.status(200).json({ ok: true });
      case 'limite_alcanzado':
        // eslint-disable-next-line no-console
        console.error(
          '[webhooks] Pago acreditado pero el negocio alcanzó el límite de turnos confirmados del plan ' +
            'gratis (HU-29) — requiere seguimiento manual (reembolso o upgrade a Turnario Pro):',
          {
            turnoId,
            negocioId: resultado.negocioId,
            pagoId: resultado.pagoId,
            motivo: resultado.motivo,
          }
        );
        return res.status(200).json({ ok: true });
      case 'turno_no_pendiente':
        // [ALTO-1] Ver el comentario junto a este `tipo` más arriba — pago acreditado pero el
        // turno ya no estaba 'pendiente_de_pago' (se canceló/reprogramó/expiró antes de que
        // llegara esta notificación). Mismo criterio que 'limite_alcanzado': requiere seguimiento
        // manual (reembolso, o re-crear el turno si el cliente todavía lo quiere), se loguea para
        // que sea descubrible en vez de quedar en silencio.
        // eslint-disable-next-line no-console
        console.error(
          '[webhooks] Pago acreditado pero el turno ya no estaba pendiente_de_pago (cancelado/' +
            'reprogramado/expirado antes de que llegara esta notificación) — requiere seguimiento manual:',
          {
            turnoId,
            estadoTurno: resultado.estadoTurno,
            negocioId: resultado.negocioId,
            pagoId: resultado.pagoId,
          }
        );
        return res.status(200).json({ ok: true });
    }
  })
);
