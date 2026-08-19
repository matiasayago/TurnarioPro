import { Router, Response } from 'express';
import { z } from 'zod';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { calcularSlotsDisponibles, inicioDelDiaLocal } from '../dominio/disponibilidad';
import { uuidSchema, fechaIsoSchema, respuestaValidacionFallida } from '../dominio/validacion';
import { LimitePlanGratisError, cuerpoLimitePlanAlcanzado, exigirLimiteTurnosConfirmadosDelMes } from '../dominio/suscripciones';
import {
  armarAsuntoNotificacion,
  armarMensajeNotificacion,
  obtenerDatosNotificacionTurno,
  DatosMensajeNotificacion,
  TipoNotificacion,
} from '../dominio/notificaciones';
import { pagoProvider, IntencionDePago } from '../integraciones/pagos';
import { emailProvider } from '../integraciones/email';

export const turnosRouter = Router();

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación de entrada — se
// aplican al INICIO de cada handler, antes de tocar la base de datos. Reemplazan (sin dejar
// huecos) los chequeos puntuales de presencia y de fecha (DEF-04) que ya existían.
const crearTurnoSchema = z.object({
  profesional_id: uuidSchema,
  servicio_id: uuidSchema,
  inicio: fechaIsoSchema,
});

const turnoIdParamsSchema = z.object({ id: uuidSchema });

const reprogramarSchema = z.object({ nuevo_inicio: fechaIsoSchema });

// RN8: ventana mínima de cancelación/reprogramación (parametrizable, propuesta 2 horas — A3).
const VENTANA_MIN_MINUTOS = Number(process.env.VENTANA_CANCELACION_MIN ?? 120);

function dentroDeVentanaMinima(inicioTurno: string): boolean {
  const minutosParaElTurno = (new Date(inicioTurno).getTime() - Date.now()) / 60_000;
  return minutosParaElTurno < VENTANA_MIN_MINUTOS;
}

// ============================================================================
// Envío de notificaciones por email (ampliación 2026-08-18, pedido explícito del CEO: además de
// la bandeja in-app, reenviar cada notificación por correo real vía Resend — ver
// integraciones/email.ts). Helpers de ESTE archivo (no compartidos con routes/profesionales.ts ni
// jobs/recordarTurnosProximos.ts, que definen los suyos propios): mismo criterio ya documentado en
// este mismo backend para no extraer glue code sencillo a un módulo común (ver el comentario junto
// a `POST /profesionales/:id/turnos` en profesionales.ts, "se duplica acá... a propósito").
//
// CRÍTICO — dónde se llaman: SIEMPRE después de que `withTransaction` ya resolvió (fuera de la
// transacción que hizo los INSERT de `turno`/`notificacion`), nunca adentro de su callback. Un
// email es un efecto secundario best-effort: si tarda o falla, no puede demorar ni arriesgar el
// COMMIT/ROLLBACK de esa transacción, que ya no tiene nada que ver con el envío. Ver cada call
// site más abajo.
// ============================================================================

/** Envía UN email de notificación y nunca lanza — cualquier error (Resend caído, red,
 *  `RESEND_API_KEY` sin configurar) se loguea acá mismo y no interrumpe al caller. Mismo criterio
 *  fail-closed/no-throw que integraciones/pagos.ts (`validarWebhook`) para no tirar abajo el flujo
 *  principal (crear/cancelar/reprogramar un turno) por un problema de un sistema externo. */
async function enviarEmailNotificacion(destinatarioEmail: string, datos: DatosMensajeNotificacion): Promise<void> {
  try {
    await emailProvider.enviarNotificacion(
      destinatarioEmail,
      armarAsuntoNotificacion(datos.tipo),
      armarMensajeNotificacion(datos)
    );
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(
      `[turnos] Error enviando email de notificación (tipo=${datos.tipo}, destinatarioEsCliente=${datos.destinatarioEsCliente}) a ${destinatarioEmail}:`,
      err
    );
  }
}

/**
 * Notifica por email a LAS 2 partes de `turnoId` para un evento de tipo `tipo` — mismas 2 filas
 * que ya quedaron insertadas en la bandeja (`notificacion`) por el caller, ahora también por
 * correo. Nunca lanza (ver `enviarEmailNotificacion`); si la propia lectura de datos falla (ej.
 * problema de conexión a la base ya fuera de la transacción principal), tampoco — se loguea y se
 * corta ahí, sin mandar ningún email para este turno.
 */
async function enviarEmailsNotificacionTurno(turnoId: string, tipo: TipoNotificacion): Promise<void> {
  let datos;
  try {
    datos = await obtenerDatosNotificacionTurno(pool, turnoId);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(`[turnos] Error leyendo datos para notificar por email (turno ${turnoId}, tipo ${tipo}):`, err);
    return;
  }
  // No debería poder pasar — turnoId ya existe y se acaba de confirmar en la transacción de
  // arriba (turno nunca se borra físicamente, ver dominio/notificaciones.ts). Cubierto igual,
  // nunca asumido.
  if (!datos) return;

  const datosBase = {
    tipo,
    clienteNombre: datos.clienteNombre,
    profesionalNombre: datos.profesionalNombre,
    negocioNombre: datos.negocioNombre,
    turnoInicio: datos.turnoInicio,
  };

  // En paralelo — un destinatario cuyo envío falla no frena al otro (cada uno ya atrapa su propio
  // error adentro de `enviarEmailNotificacion`, así que `Promise.all` acá nunca rechaza).
  await Promise.all([
    enviarEmailNotificacion(datos.clienteEmail, { ...datosBase, destinatarioEsCliente: true }),
    enviarEmailNotificacion(datos.profesionalEmail, { ...datosBase, destinatarioEsCliente: false }),
  ]);
}

// HU-09 / HU-09b: reservar un turno. Ver documento-arquitectura.md §4 — la garantía
// anti-doble-reserva (RN2) vive en el índice único parcial `uq_turno_slot_activo`, no en un
// SELECT previo. Si dos clientes piden el mismo (profesional_id, inicio) al mismo tiempo,
// Postgres solo deja pasar un INSERT; el segundo lanza el error de unicidad 23505.
//
// Las lecturas de validación (profesional/servicio/membresía/RN4/grilla RN1-RN2) corren vía
// `pool` directo, sin transacción: `profesional`, `servicio`, `negocio_profesional` y
// `profesional_servicio` son legibles sin contexto RLS (policies públicas de SELECT); la
// ocupación de `turno` que usa la grilla RN1-RN2 (calcularSlotsDisponibles, ver
// dominio/disponibilidad.ts) pasa por la función SECURITY DEFINER `turno_ocupacion_publica` en
// vez de un SELECT directo (adopción DBA 2026-08-09, ver migrations/001_init.sql) — mismo
// criterio que ya usaba esta función antes de la migración (chequeos previos sueltos, la
// garantía real es el índice único). El INSERT final (turno + pago + notificación) SÍ corre en
// una única transacción con contexto RLS (`usuarioId`), sobre el MISMO client para las 3
// sentencias — necesario porque `turno` tiene RLS de escritura (WITH CHECK exige
// `cliente_id = app.usuario_id`).
//
// Contrato (agregado 2026-08-14, HU-29): además de los códigos ya documentados en el resto de
// este comentario, responde 402 si el servicio NO requiere seña (el turno nacería directo en
// 'confirmado') y el negocio (plan gratis) ya alcanzó el límite de 60 turnos confirmados este mes
// — ver dominio/suscripciones.ts.
turnosRouter.post(
  '/',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // MEDIUM-3 / DEF-04 (ver informe-seguridad.md y reporte-qa.md): valida presencia, UUID bien
    // formado y fecha ISO-8601 válida ANTES de usar `inicio` en cualquier cálculo — antes un
    // valor no parseable llegaba a `new Date(inicio).toISOString()` y tiraba un RangeError no
    // capturado (500 con stack trace, ver HIGH-2, ya resuelto por el error handler, pero mejor
    // rechazarlo acá).
    const parsed = crearTurnoSchema.safeParse(req.body);
    if (!parsed.success) return respuestaValidacionFallida(res, parsed.error);
    const { profesional_id, servicio_id, inicio } = parsed.data;

    const inicioDate = new Date(inicio);

    // `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — el negocio del
    // turno sale de `servicio.negocio_id`, inequívoco porque un servicio sigue siendo 1:1 con su
    // negocio (esa relación no cambia en esta generalización). Acá solo hace falta confirmar que
    // el profesional_id pedido exista (la FK de `turno.profesional_id` fallaría más abajo si no).
    // `usuario_id` se agrega a este SELECT (antes solo `id`) porque el alta automática de
    // `paciente` más abajo necesita la identidad del PROFESIONAL, no la del cliente que reserva
    // — ver el comentario grande junto al INSERT INTO paciente.
    const profesionalResult = await pool.query('SELECT id, usuario_id FROM profesional WHERE id = $1', [
      profesional_id,
    ]);
    const profesional = profesionalResult.rows[0] as { id: string; usuario_id: string } | undefined;
    // `AND eliminado_en IS NULL` (fast-follow E15, ver negocios.ts DELETE /:id/servicios/
    // :servicioId): antes este SELECT no filtraba soft-delete — un servicio dado de baja por el
    // administrador seguía siendo reservable acá si se conocía su id (aunque ya hubiera
    // desaparecido de GET /negocios/:id/servicios, que sí filtra). Mismo 404 de abajo que ya
    // existía para "no existe" — comportamiento externo idéntico para quien llama, sin contrato
    // nuevo.
    const servicioResult = await pool.query(
      'SELECT negocio_id, duracion_min FROM servicio WHERE id = $1 AND eliminado_en IS NULL',
      [servicio_id]
    );
    const servicio = servicioResult.rows[0] as { negocio_id: string; duracion_min: number } | undefined;
    if (!profesional || !servicio) {
      return res.status(404).json({ error: 'Profesional o servicio no encontrado' });
    }

    // Integridad N:M (ver modelo-datos.md §2ter, "recomendación adicional"): antes de esta
    // generalización era estructuralmente imposible reservar con un profesional que no trabaja en
    // el negocio del servicio elegido (el profesional tenía un único negocio_id posible). Ahora
    // hay que confirmarlo a nivel de aplicación antes de crear la reserva.
    const esMiembroActivoResult = await pool.query(
      'SELECT 1 FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2 AND activo = true',
      [servicio.negocio_id, profesional_id]
    );
    if (!esMiembroActivoResult.rowCount) {
      return res.status(404).json({
        error: 'Este profesional no pertenece al negocio del servicio solicitado',
      });
    }

    // RN4 (DEF-03, ver reporte-qa.md): el profesional tiene que haber asociado explícitamente
    // este servicio (fila en `profesional_servicio`). Se valida ANTES de leer requiere_sena /
    // insertar el turno — si no hay fila, el default de la columna (`requiere_sena = false`)
    // eludía el control de seña además de permitir reservar un servicio que el profesional
    // nunca ofreció.
    const relacionResult = await pool.query(
      'SELECT requiere_sena, monto_sena FROM profesional_servicio WHERE profesional_id = $1 AND servicio_id = $2',
      [profesional_id, servicio_id]
    );
    const relacion = relacionResult.rows[0] as
      | { requiere_sena: boolean; monto_sena: number | null }
      | undefined;
    if (!relacion) {
      return res.status(404).json({ error: 'Este profesional no ofrece este servicio (RN4)' });
    }

    // RN1 (DEF-01) — y, de yapa, DEF-02 (solapamiento con `inicio` distinto), ver el comentario
    // largo en src/dominio/disponibilidad.ts: recalculamos la grilla de slots para el día del
    // `inicio` pedido (misma función que usa GET /profesionales/:id/slots) y exigimos que
    // `inicio` sea EXACTAMENTE uno de sus pasos. Se hace en DOS pasadas para no confundir dos
    // motivos de rechazo distintos:
    //  1) `inicio` ni siquiera está alineado a la grilla publicada (dia/horario fuera de bloque,
    //     o un horario "intermedio" no alcanzable con la duración del servicio, ej. 09:30 con
    //     bloques de 60 min) → RN1, 400.
    //  2) `inicio` SÍ está alineado a la grilla pero ya lo ocupa un turno/excepción activo → RN2,
    //     409 (mismo código que ya devuelve el índice único de la base ante una reserva duplicada
    //     exacta — si solo usáramos la lista de slots LIBRES para el chequeo de RN1, una reserva
    //     duplicada exacta pasaría a responder 400 en vez de 409, rompiendo esa garantía existente).
    const inicioIso = inicioDate.toISOString();
    const ventanaDelDia = { desde: inicioDelDiaLocal(inicioDate), dias: 1, maxSlots: 500 };

    const grilla = await calcularSlotsDisponibles(pool, profesional_id, servicio_id, {
      ...ventanaDelDia,
      ignorarOcupacion: true,
    });
    const alineadoAGrilla = grilla?.slots.includes(inicioIso) ?? false;
    if (!alineadoAGrilla) {
      return res.status(400).json({
        error:
          'El horario solicitado no corresponde a un slot de disponibilidad publicado por el profesional (RN1).',
      });
    }

    const slotsLibres = await calcularSlotsDisponibles(pool, profesional_id, servicio_id, ventanaDelDia);
    const estaLibre = slotsLibres?.slots.includes(inicioIso) ?? false;
    if (!estaLibre) {
      return res.status(409).json({
        error: 'Ese horario ya no está disponible — se solapa con otro turno o excepción de este profesional (RN2).',
      });
    }

    // D10 (amenda RN3, ver modelo-datos.md §2quater): reusamos `slotsLibres.duracionMin` en vez de
    // recalcular a partir de `servicio.duracion_min` — ese valor ya salió de
    // `calcularSlotsDisponibles` (con el fallback a `profesional.duracion_cita_min` ya aplicado) y
    // es EXACTAMENTE la duración con la que se validó el slot `estaLibre` arriba. Evita una
    // segunda fuente de verdad que se pueda desincronizar del slot que realmente se validó. El `!`
    // es seguro acá: si `slotsLibres` fuera `null`, `estaLibre` habría sido `false` y ya se
    // devolvió antes de llegar a esta línea.
    const finDate = new Date(inicioDate.getTime() + slotsLibres!.duracionMin * 60_000);
    const requiereSena = !!relacion?.requiere_sena; // D2/RN10 — configurable por profesional+servicio
    const estadoInicial = requiereSena ? 'pendiente_de_pago' : 'confirmado';
    const turnoId = uuid();
    const ts = nowIso();

    try {
      await withTransaction(
        async (client) => {
          // HU-29 (Turnario Pro) — mismo criterio que `POST /profesionales/:id/turnos` (HU-23,
          // ver ese comentario): este camino (servicio SIN seña) deja nacer el turno DIRECTO en
          // 'confirmado', así que el chequeo del límite de 60 turnos confirmados/mes tiene que
          // correr ACÁ, antes del INSERT — es el único momento en que se puede bloquear antes de
          // que "cuente". El otro camino de este mismo endpoint (servicio CON seña, más abajo,
          // `estadoInicial = 'pendiente_de_pago'`) difiere el chequeo al momento en que el pago
          // se confirme — ver dominio/suscripciones.ts. Ese momento (2026-08-17) es
          // `POST /webhooks/mercadopago` (src/routes/webhooks.ts): usa la variante que DEVUELVE
          // resultado (`verificarLimiteTurnosConfirmadosDelMes`), no esta que lanza — ver el
          // comentario ahí para el porqué (el pago ya está cobrado en ese punto, no hay ningún
          // ROLLBACK posible que lo deshaga). Se salta completo si el negocio tiene Turnario Pro
          // activo.
          //
          // Corre con `app.usuario_id` = CLIENTE (el cambio de identidad a la del profesional
          // pasa recién más abajo, para el alta de `paciente`) — `obtenerEstadoSuscripcion`
          // necesita la policy `[BACKEND] suscripcion_negocio_select_negocio_en_contexto`
          // (migrations/001_init.sql, pendiente de ratificación por DBA) para poder leer el plan
          // de este negocio bajo esa identidad; ver el razonamiento completo ahí.
          if (estadoInicial === 'confirmado') {
            await exigirLimiteTurnosConfirmadosDelMes(client, servicio.negocio_id, inicioDate);
          }

          await client.query(
            `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              turnoId,
              servicio.negocio_id,
              profesional_id,
              servicio_id,
              req.auth!.sub,
              inicioDate.toISOString(),
              finDate.toISOString(),
              estadoInicial,
              ts,
            ]
          );

          if (requiereSena) {
            await client.query(
              'INSERT INTO pago (id, turno_id, monto, estado, creado_en) VALUES ($1, $2, $3, $4, $5)',
              [uuid(), turnoId, relacion?.monto_sena ?? 0, 'pendiente', ts]
            );
          }

          // HU-25 (ver database/migrations/001_init.sql, "Bandeja de notificaciones"): agrega
          // destinatario_usuario_id — antes se insertaba sin esa columna (no existía hasta este
          // ciclo), quedando en NULL y por lo tanto invisible para la bandeja
          // (`notificacion_select_propia` nunca matchea `destinatario_usuario_id IS NULL`, ver
          // 004_notificaciones.sql). El destinatario es el PROFESIONAL de este turno (mismo
          // criterio confirmado por DBA contra el wireframe, mapa-pantallas.md §5.15: los 3
          // ejemplos de la bandeja están redactados en 3ra persona sobre la acción del cliente —
          // es la bandeja del profesional), usando el mismo `profesional.usuario_id` que ya
          // resuelve el SELECT de arriba para el alta de `paciente`. No hace falta cambiar de
          // identidad de RLS para ESTE INSERT (a diferencia del de `paciente`, más abajo):
          // `app.usuario_id` sigue siendo el CLIENTE acá, y `notificacion_insert_evento_turno`
          // (004_notificaciones.sql) ya contempla exactamente este caso — turno.cliente_id =
          // app.usuario_id (1ra condición) + destinatario_usuario_id = profesional de ESTE turno
          // (2da condición).
          //
          // `notificacionProvider.enviar` (integraciones/notificaciones.ts) sigue sin invocarse
          // acá, a propósito: es un stub que solo loguea, sin ningún consumidor real todavía (D4
          // no resolvió qué proveedor de push real se usa) — conectar el "envío" es una decisión
          // de un ciclo futuro, no de este (que solo pide bandeja + configuración).
          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
            [uuid(), turnoId, 'confirmacion', profesional!.usuario_id, ts]
          );

          // Ampliación (2026-08-18, Backend — pedido explícito del CEO): notificar a AMBAS
          // partes, no solo al profesional — 2do INSERT con destinatario = el propio cliente que
          // está reservando (`req.auth!.sub`, ya autenticado con `requireAuth('cliente')`), mismo
          // `tipo`/`turno_id`/`creado_en` que el de arriba (mismo evento, 2 destinatarios).
          // `armarMensajeNotificacion` (dominio/notificaciones.ts) ya resolvía el texto correcto
          // para `destinatarioEsCliente: true` desde el origen (ver ese archivo) — no hace falta
          // tocarlo, el mensaje se arma recién al leer (GET /notificaciones). Tampoco hace falta
          // ningún cambio de identidad de RLS para este 2do INSERT: `app.usuario_id` sigue siendo
          // el CLIENTE durante toda esta transacción, y `notificacion_insert_evento_turno`
          // (004_notificaciones.sql) ya admite `destinatario_usuario_id = turno.cliente_id` bajo
          // esa misma identidad (la 1ra rama de su 2da condición) — sin necesitar la rama "staff
          // del negocio" que sí usa el INSERT de arriba.
          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
            [uuid(), turnoId, 'confirmacion', req.auth!.sub, ts]
          );

          // HU-19/HU-20 (ver 03-arquitectura/modelo-datos.md §2quinquies y backlog.md HU-19):
          // alta automática de la fila `paciente` en el primer turno entre este profesional y
          // este cliente — sin esto, "Gestión de Pacientes" (Mobile) y el criterio "Nuevo" de
          // HU-19 (alta en la cartera, últimos 30 días) no tendrían de dónde salir hasta que el
          // profesional abriera la ficha a mano (opción (i) que dejó abierta DBA en
          // modelo-datos.md/001_init.sql; acá se adopta la opción (ii), automática). `ON
          // CONFLICT DO NOTHING` porque esto corre en CADA turno del mismo (negocio, profesional,
          // cliente) — del 2do turno en adelante no debe pisar los campos que el profesional ya
          // haya cargado a mano en la ficha.
          //
          // Cambio de identidad de RLS DENTRO de esta misma transacción — necesario, no
          // cosmético: `paciente` exige (policy `paciente_acceso_propio_profesional`, ver
          // database/migrations/002_pacientes_historial_auth_google.sql) que `app.usuario_id`
          // sea el usuario_id del PROFESIONAL dueño de la ficha; `turno` arriba exige exactamente
          // lo opuesto (RN2, `cliente_id = app.usuario_id`, ver 001_init.sql). Este handler corre
          // con `requireAuth('cliente')`, así que el contexto que fijó `withTransaction` más
          // abajo (`usuarioId: req.auth!.sub`) es el del CLIENTE — insertar en `paciente` con ese
          // contexto violaría el WITH CHECK de esa policy (INSERT rechazado con 42501, no un
          // simple "0 filas afectadas" como pasaría con un UPDATE/DELETE). `set_config(...,
          // true)` puede llamarse más de una vez en la misma transacción (mismo mecanismo que ya
          // usa `withTransaction` en db.ts) — el nuevo valor rige para el resto de la transacción
          // sin romper la atomicidad (si algo de lo anterior fallara, esta sentencia ni se
          // alcanza y todo se revierte junto). Va al FINAL a propósito, después de las 3
          // sentencias que sí necesitan la identidad del cliente — no reordenar sin revisar esto.
          await client.query('SELECT set_config($1, $2, true)', ['app.usuario_id', profesional!.usuario_id]);
          await client.query('SELECT set_config($1, $2, true)', ['app.negocio_id', servicio.negocio_id]);
          await client.query(
            `INSERT INTO paciente (negocio_id, profesional_id, cliente_id, creado_en)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (negocio_id, profesional_id, cliente_id) DO NOTHING`,
            [servicio.negocio_id, profesional_id, req.auth!.sub, ts]
          );
        },
        { usuarioId: req.auth!.sub }
      );
    } catch (err: any) {
      // HU-29 — ver el comentario junto al chequeo más arriba y `cuerpoLimitePlanAlcanzado`
      // (dominio/suscripciones.ts) para el razonamiento completo del 402 (en vez de 403): el
      // cliente SÍ está autorizado a reservar, lo que falla es el plan del negocio.
      if (err instanceof LimitePlanGratisError) {
        return res.status(402).json(cuerpoLimitePlanAlcanzado(err.message));
      }
      // Postgres (ver database/migrations/001_init.sql): code 23505 = unique_violation, lanzado
      // por el índice único parcial `uq_turno_slot_activo` si dos requests corren la misma
      // ventana de tiempo en paralelo (ver scripts/test-concurrent-booking.mjs). Ya no hay
      // fallback al shape de error de node:sqlite (SQLITE_CONSTRAINT_UNIQUE / mensaje "UNIQUE") —
      // ese driver quedó reemplazado por completo, un solo código de error posible acá.
      if (err?.code === '23505') {
        return res.status(409).json({
          error: 'Ese horario ya no está disponible — alguien más lo reservó primero (RN2).',
        });
      }
      throw err;
    }

    // Envío real por email (best-effort, FUERA de la transacción de arriba — ver el comentario
    // grande junto a `enviarEmailsNotificacionTurno` más arriba): recién acá, una vez que
    // `withTransaction` ya hizo COMMIT sin errores. SIN `await` a propósito (ampliación
    // 2026-08-18, tras un fallo intermitente no reproducible en CI que desapareció con este
    // cambio — ver memory/proyectos/turnos-profesionales/decisiones.md): la respuesta HTTP de
    // esta reserva no tiene por qué esperar a que termine el envío de 2 emails, que ya de por sí
    // nunca puede fallar esta request (no lanza, ver el comentario grande de arriba) — solo
    // puede, como mucho, demorarla. `void` deja explícito que es intencional no esperar esta
    // promesa (no un `await` olvidado).
    void enviarEmailsNotificacionTurno(turnoId, 'confirmacion');

    res.status(201).json({
      id: turnoId,
      estado: estadoInicial,
      requiere_pago: requiereSena,
      monto_sena: relacion?.monto_sena ?? null,
    });
  })
);

// HU-29/RN10 (2026-08-17) — cierre del gap documentado en integraciones/pagos.ts (HALLAZGO
// 2026-08-14): `pagoProvider.crearIntencion` no tenía, hasta este endpoint, ningún caller en todo
// el backend. Este es el punto de entrada para que el CLIENTE dueño de un turno
// 'pendiente_de_pago' (nacido así por RN10 — ver POST / arriba y POST /profesionales/:id/turnos)
// obtenga la URL de checkout de Mercado Pago y pague la seña. La confirmación real del pago
// (webhook de Mercado Pago — `UPDATE pago SET estado = 'acreditado'` + eventual
// `UPDATE turno SET estado = 'confirmado'`) vive en `POST /webhooks/mercadopago`
// (src/routes/webhooks.ts), no acá: este endpoint solo abre la intención de pago, no la confirma.
//
// Shape de la respuesta (200 `{ url_checkout }`) sin contrato previo de Mobile (ver
// confirmar_turno_screen.dart, todavía un TODO) — se elige el mínimo que Mobile necesita para
// redirigir al checkout; `monto`/`turno_id` no se repiten acá porque Mobile ya los tiene desde la
// respuesta de creación del turno (`monto_sena`, ver arriba).
turnosRouter.post(
  '/:id/pago',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const paramsParsed = turnoIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    const resultado = await withTransaction(
      async (client) => {
        // JOIN directo a `pago` (sin RLS, ver integraciones/pagos.ts y el comentario de
        // db.ts/ContextoRls) apoyado en la policy pública `turno_select_publico` (todavía activa
        // como red de seguridad transitoria, ver migrations/001_init.sql) — mismo criterio que ya
        // usa `GET /mios` en este archivo (SELECT directo sobre `turno`, sin pasar por la función
        // SECURITY DEFINER `turno_propio_para_gestion`, que no expone columnas de `pago` y acá no
        // aportaría nada: la distinción 403 vs 404 se resuelve igual, a mano, más abajo). LEFT
        // JOIN (no INNER): distingue "turno inexistente" (sin fila) de "turno sin pago asociado"
        // (fila con pago_id NULL) — 2 causas de rechazo distintas.
        const result = await client.query(
          `SELECT t.id, t.cliente_id, t.estado, p.id AS pago_id, p.monto AS pago_monto
           FROM turno t
           LEFT JOIN pago p ON p.turno_id = t.id
           WHERE t.id = $1`,
          [req.params.id]
        );
        const fila = result.rows[0] as
          | { id: string; cliente_id: string; estado: string; pago_id: string | null; pago_monto: number | null }
          | undefined;
        if (!fila) return { tipo: 'no_encontrado' as const };
        if (fila.cliente_id !== req.auth!.sub) return { tipo: 'prohibido' as const };
        // No se re-chequea acá `pago.estado` (ej. ya 'acreditado' pero turno todavía
        // 'pendiente_de_pago' por el límite de HU-29, ver webhooks.ts): `turno.estado` ya alcanza
        // como gate — mientras siga en 'pendiente_de_pago' hay, en los hechos, algo pendiente de
        // cobrar/confirmar, y el webhook es idempotente de todos modos ante un segundo intento.
        if (fila.estado !== 'pendiente_de_pago') {
          return { tipo: 'estado_invalido' as const, estado: fila.estado };
        }
        if (!fila.pago_id) return { tipo: 'sin_pago' as const };

        return { tipo: 'ok' as const, turnoId: fila.id, pagoId: fila.pago_id, monto: fila.pago_monto! };
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'prohibido':
        return res.status(403).json({ error: 'No podés pagar un turno que no es tuyo' });
      case 'estado_invalido':
        return res.status(409).json({
          error: `Este turno no tiene un pago pendiente para cobrar (estado actual: '${resultado.estado}')`,
        });
      case 'sin_pago':
        // No debería poder pasar — todo turno 'pendiente_de_pago' nace con su fila `pago` en la
        // misma transacción (ver POST / arriba y POST /profesionales/:id/turnos) — cubierto igual,
        // nunca asumido.
        return res.status(404).json({ error: 'No se encontró un pago pendiente asociado a este turno' });
      case 'ok': {
        let intencion: IntencionDePago;
        try {
          intencion = await pagoProvider.crearIntencion(resultado.turnoId, resultado.monto);
        } catch (err) {
          // Mismo criterio que GOOGLE_CLIENT_ID ausente en auth.ts (ver verificarIdTokenGoogle):
          // sin MP_ACCESS_TOKEN configurado, `pagoProvider` tira recién al invocarse (nunca al
          // importar el módulo, ver integraciones/pagos.ts) — se atrapa acá y se responde 503 con
          // un mensaje claro, en vez de dejar que el error handler genérico de app.ts lo convierta
          // en un 500 opaco sin contexto para quien llama.
          //
          // [INFORMATIVO-1, revisión de Security 2026-08-17] Este catch cubre tanto "falta
          // MP_ACCESS_TOKEN" (esperable) como una falla real de red/API de Mercado Pago
          // (accionable) — se loguea server-side para no dejar la segunda invisible.
          // eslint-disable-next-line no-console
          console.error('[turnos] Error creando la intención de pago en Mercado Pago:', resultado.turnoId, err);
          return res.status(503).json({
            error: 'Pagos con Mercado Pago no están disponibles todavía en este entorno',
          });
        }

        await pool.query('UPDATE pago SET referencia_externa = $1, modificado_en = $2 WHERE id = $3', [
          intencion.id,
          nowIso(),
          resultado.pagoId,
        ]);

        return res.json({ url_checkout: intencion.urlCheckout });
      }
    }
  })
);

// HU-12: cancelar un turno propio. Todo (SELECT + chequeos + UPDATE) corre en una sola
// transacción con contexto RLS — el resultado es un objeto discriminado por `tipo` porque ya no
// se puede hacer `return res.status(...)` desde adentro del closure de `withTransaction`.
turnosRouter.patch(
  '/:id/cancelar',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // Validación de `:id` agregada acá (no existía en la versión anterior): con `turno.id`
    // tipado `uuid` en Postgres (a diferencia del TEXT de node:sqlite), un `:id` mal formado ya
    // no devuelve "no encontrado" solo — Postgres tira "invalid input syntax for type uuid",
    // que sin este chequeo previo terminaría como 500 genérico en vez del 400 esperable.
    const paramsParsed = turnoIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    const resultado = await withTransaction(
      async (client) => {
        // Adopción DBA (2026-08-09, ver migrations/001_init.sql, caso de uso (b)): antes un SELECT
        // directo sobre `turno` (cubierto por la policy pública `turno_select_publico`, que se
        // mantiene activa como red de seguridad transitoria). La función `turno_propio_para_gestion`
        // lee SIN filtrar por cliente_id (a propósito — hace falta distinguir 403 de 404 más abajo)
        // y expone solo las columnas que este handler usa (no creado_en/modificado_en).
        const turnoResult = await client.query('SELECT * FROM turno_propio_para_gestion($1)', [
          req.params.id,
        ]);
        const turno = turnoResult.rows[0];
        if (!turno) return { tipo: 'no_encontrado' as const };
        if (turno.cliente_id !== req.auth!.sub) return { tipo: 'prohibido' as const };
        if (dentroDeVentanaMinima(turno.inicio)) return { tipo: 'fuera_de_ventana' as const };

        const ts = nowIso();

        await client.query("UPDATE turno SET estado = 'cancelado', modificado_en = $1 WHERE id = $2", [
          ts,
          req.params.id,
        ]);

        // HU-25 (ver database/migrations/001_init.sql, "Bandeja de notificaciones",
        // recomendación 1 para Backend): este handler no insertaba ninguna notificación — gap
        // real, no solo de modelado. Mismo destinatario (el profesional del turno) y mismo JOIN
        // que usan POST /turnos y PATCH /:id/reprogramar en este archivo. No hace falta cambiar
        // de identidad de RLS para este INSERT (a diferencia del alta de `paciente` en
        // POST /turnos): `app.usuario_id` sigue siendo el CLIENTE en toda esta transacción, y la
        // policy `notificacion_insert_evento_turno` (004_notificaciones.sql) ya contempla
        // exactamente este caso — turno.cliente_id = app.usuario_id (1ra condición) +
        // destinatario_usuario_id = profesional de ESTE turno (2da condición).
        const profesionalResult = await client.query('SELECT usuario_id FROM profesional WHERE id = $1', [
          turno.profesional_id,
        ]);
        const profesional = profesionalResult.rows[0] as { usuario_id: string } | undefined;
        await client.query(
          'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
          [uuid(), req.params.id, 'cancelacion', profesional!.usuario_id, ts]
        );

        // Ampliación (2026-08-18, Backend — pedido explícito del CEO): notificar a AMBAS partes
        // — 2do INSERT con destinatario = el cliente mismo (`turno.cliente_id`, ya leído arriba
        // por `turno_propio_para_gestion`; es el mismo valor que `req.auth!.sub` en este punto,
        // ya confirmado más arriba por el chequeo `turno.cliente_id !== req.auth!.sub` -> 403).
        // Mismo `tipo`/`turno_id`/`creado_en` que el INSERT de arriba. Mismo razonamiento de RLS
        // que ese INSERT: `app.usuario_id` sigue siendo el CLIENTE en toda esta transacción, y
        // `notificacion_insert_evento_turno` (004_notificaciones.sql) admite
        // `destinatario_usuario_id = turno.cliente_id` bajo esa misma identidad.
        await client.query(
          'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
          [uuid(), req.params.id, 'cancelacion', turno.cliente_id, ts]
        );

        return { tipo: 'ok' as const };
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    // Envío real por email (best-effort, FUERA de la transacción de arriba — ver el comentario
    // grande junto a `enviarEmailsNotificacionTurno`): solo si la cancelación efectivamente pasó
    // (`tipo === 'ok'`) — en cualquier otro caso no se insertó ninguna fila de notificación, así
    // que no hay nada que reenviar por email.
    if (resultado.tipo === 'ok') {
      // SIN `await` a propósito — ver el comentario junto al call site equivalente de POST /
      // (arriba en este mismo archivo, ampliación 2026-08-18) para el razonamiento completo.
      void enviarEmailsNotificacionTurno(req.params.id, 'cancelacion');
    }

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'prohibido':
        return res.status(403).json({ error: 'No podés cancelar un turno que no es tuyo' });
      case 'fuera_de_ventana':
        return res.status(409).json({
          error: `Fuera de la ventana mínima de cancelación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
        });
      case 'ok':
        return res.json({ ok: true });
    }
  })
);

// HU-13: reprogramar un turno propio a otro horario del MISMO profesional/servicio (CU5).
// Reutiliza la misma garantía anti-doble-reserva del alta (índice único parcial, ver §4 de
// documento-arquitectura.md): el turno viejo se marca 'reprogramado' (sale del índice, que
// solo cubre pendiente_de_pago/confirmado) y el nuevo se inserta con el nuevo horario; si ese
// horario ya lo tomó otro cliente, el INSERT falla con 409 igual que en POST /turnos.
//
// Mismo patrón que /:id/cancelar (resultado discriminado por `tipo`) más un try/catch exterior
// para el 23505 (que sale de `withTransaction` como excepción, no como valor de retorno, porque
// el motor de Postgres lo lanza en medio de la transacción — `withTransaction` hace ROLLBACK y
// relanza).
turnosRouter.patch(
  '/:id/reprogramar',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // MEDIUM-3 (ver informe-seguridad.md): valida el :id de la URL como UUID bien formado.
    const paramsParsed = turnoIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    // MEDIUM-3 / DEF-04 (ver informe-seguridad.md y reporte-qa.md): mismo problema que en
    // POST /turnos — validar el formato ANTES de usar la fecha en cualquier cálculo, para no
    // dejar pasar un RangeError sin capturar.
    const bodyParsed = reprogramarSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nuevo_inicio } = bodyParsed.data;
    const nuevoInicioDate = new Date(nuevo_inicio);
    const nuevoTurnoId = uuid();
    const ts = nowIso();

    type Resultado =
      | { tipo: 'no_encontrado' }
      | { tipo: 'prohibido' }
      | { tipo: 'estado_invalido'; estado: string }
      | { tipo: 'fuera_de_ventana' }
      | { tipo: 'ok'; estadoFinal: string };

    let resultado: Resultado;
    try {
      resultado = await withTransaction(
        async (client) => {
          // Misma función SECURITY DEFINER que /:id/cancelar (ver comentario ahí). Este handler
          // además usa profesional_id/servicio_id/negocio_id/estado del turno leído acá, todos
          // presentes en turno_propio_para_gestion (no así creado_en/modificado_en, sin uso acá).
          const turnoResult = await client.query('SELECT * FROM turno_propio_para_gestion($1)', [
            req.params.id,
          ]);
          const turno = turnoResult.rows[0];
          if (!turno) return { tipo: 'no_encontrado' as const };
          if (turno.cliente_id !== req.auth!.sub) return { tipo: 'prohibido' as const };
          if (!['pendiente_de_pago', 'confirmado'].includes(turno.estado)) {
            return { tipo: 'estado_invalido' as const, estado: turno.estado };
          }
          if (dentroDeVentanaMinima(turno.inicio)) return { tipo: 'fuera_de_ventana' as const };

          const servicioResult = await client.query('SELECT duracion_min FROM servicio WHERE id = $1', [
            turno.servicio_id,
          ]);
          const servicio = servicioResult.rows[0] as { duracion_min: number } | undefined;
          // D10 (amenda RN3, ver modelo-datos.md §2quater — "Hallazgo adicional"): mismo
          // fallback que `calcularSlotsDisponibles` — si el profesional de este turno tiene
          // `duracion_cita_min` configurada, reemplaza la duración del servicio también al
          // reprogramar. Sin esto, reprogramar el turno de un profesional con override
          // configurado le devolvería silenciosamente la duración del servicio en vez de
          // mantener la duración con la que se reservó originalmente.
          // `usuario_id` se agrega a este SELECT (antes solo `duracion_cita_min`) — hace falta
          // para completar `destinatario_usuario_id` del INSERT de `notificacion` más abajo
          // (HU-25). Sigue siendo el mismo profesional del turno viejo: reprogramar no cambia de
          // profesional, solo de horario.
          const profesionalResult = await client.query(
            'SELECT duracion_cita_min, usuario_id FROM profesional WHERE id = $1',
            [turno.profesional_id]
          );
          const profesionalConfig = profesionalResult.rows[0] as
            | { duracion_cita_min: number | null; usuario_id: string }
            | undefined;
          const duracionEfectivaMin = profesionalConfig?.duracion_cita_min ?? servicio!.duracion_min;
          const nuevoFinDate = new Date(nuevoInicioDate.getTime() + duracionEfectivaMin * 60_000);
          // HU-29 (Turnario Pro) — revisado explícitamente si este endpoint necesita el chequeo
          // del límite de 60 turnos confirmados/mes (el mismo turno "cambia de estado" acá, aunque
          // técnicamente vía fila nueva + vieja marcada 'reprogramado'): NO lo necesita. Esta
          // línea es la única que decide el estado del turno nuevo, y solo tiene 2 resultados —
          // 'confirmado' SI Y SOLO SI el turno VIEJO YA estaba 'confirmado' (ya contaba para el
          // límite antes de este PATCH); 'pendiente_de_pago' en cualquier otro caso (nunca
          // 'confirmado' a partir de un turno que no lo era). Nunca crea un turno 'confirmado'
          // NUEVO que no existiera ya — no hay transición pendiente_de_pago -> confirmado acá,
          // a diferencia de POST /turnos y POST /profesionales/:id/turnos (ver esos comentarios).
          // Límite conocido, no resuelto en este ciclo: si el turno viejo YA estaba 'confirmado'
          // y se reprograma a OTRO mes calendario, el conteo de ese mes se "mueve" con él (sigue
          // sumando 1 turno confirmado en total, pero ahora en el mes destino en vez del mes
          // origen) — en el caso límite de un negocio ya al tope del mes destino, esto le permite
          // superar transitoriamente los 60 de ESE mes por la vía de reprogramar en vez de crear.
          // No bloqueado a propósito: mismo criterio de alcance que el resto de este ciclo (HU-29
          // pide bloquear reservas/turnos NUEVOS al llegar al límite, no restringir la
          // reprogramación de un turno ya pago/confirmado existente) — señalado acá para que
          // Product Manager/CTO IA decidan si vale la pena cerrarlo en un ciclo futuro.
          const estadoFinal = turno.estado === 'confirmado' ? 'confirmado' : 'pendiente_de_pago'; // conserva el estado de pago (D2)

          await client.query("UPDATE turno SET estado = 'reprogramado', modificado_en = $1 WHERE id = $2", [
            ts,
            turno.id,
          ]);

          await client.query(
            `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              nuevoTurnoId,
              turno.negocio_id,
              turno.profesional_id,
              turno.servicio_id,
              turno.cliente_id,
              nuevoInicioDate.toISOString(),
              nuevoFinDate.toISOString(),
              estadoFinal,
              ts,
            ]
          );

          // El pago (si existe) sigue al turno reprogramado — no se le vuelve a cobrar la seña.
          await client.query('UPDATE pago SET turno_id = $1 WHERE turno_id = $2', [nuevoTurnoId, turno.id]);

          // HU-25 (mismo criterio que POST /turnos, ver ese comentario): agrega
          // destinatario_usuario_id = el profesional de este turno. `tipo` se mantiene
          // 'confirmacion' — el pedido explícito de este ciclo fue completar el destinatario, no
          // cambiar el tipo; DBA ya dejó el label 'reprogramacion' disponible en el ENUM
          // (001_init.sql) para cuando se decida adoptarlo, sin que este INSERT tenga que cambiar
          // de forma para eso.
          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
            [uuid(), nuevoTurnoId, 'confirmacion', profesionalConfig!.usuario_id, ts]
          );

          // Ampliación (2026-08-18, Backend — pedido explícito del CEO): notificar a AMBAS
          // partes — 2do INSERT con destinatario = el cliente mismo (`turno.cliente_id`, el turno
          // VIEJO — reprogramar no cambia de cliente, sigue siendo el mismo en el turno nuevo).
          // Mismo `turno_id` (el NUEVO, `nuevoTurnoId` — igual que el INSERT de arriba: la
          // notificación de este evento vive en la fila nueva, no en la vieja marcada
          // 'reprogramado') y mismo `tipo`/`creado_en`. `tipo` se mantiene 'confirmacion' por el
          // mismo motivo ya documentado arriba (no es un cambio de este ciclo). Mismo
          // razonamiento de RLS que el INSERT de arriba: `app.usuario_id` sigue siendo el CLIENTE
          // en toda esta transacción, y `notificacion_insert_evento_turno`
          // (004_notificaciones.sql) admite `destinatario_usuario_id = turno.cliente_id` bajo esa
          // misma identidad.
          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
            [uuid(), nuevoTurnoId, 'confirmacion', turno.cliente_id, ts]
          );

          return { tipo: 'ok' as const, estadoFinal };
        },
        { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
      );
    } catch (err: any) {
      if (err?.code === '23505') {
        return res.status(409).json({
          error: 'Ese nuevo horario ya no está disponible — alguien más lo reservó primero (RN2).',
        });
      }
      throw err;
    }

    // Envío real por email (best-effort, FUERA de la transacción de arriba — ver el comentario
    // grande junto a `enviarEmailsNotificacionTurno`): solo si la reprogramación efectivamente
    // pasó (`tipo === 'ok'`) — sobre el turno NUEVO (`nuevoTurnoId`), que es donde quedaron las 2
    // filas de notificación de este evento.
    if (resultado.tipo === 'ok') {
      // SIN `await` a propósito — ver el comentario junto al call site de POST / (arriba en
      // este mismo archivo, ampliación 2026-08-18) para el razonamiento completo.
      void enviarEmailsNotificacionTurno(nuevoTurnoId, 'confirmacion');
    }

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'prohibido':
        return res.status(403).json({ error: 'No podés reprogramar un turno que no es tuyo' });
      case 'estado_invalido':
        return res.status(409).json({ error: `No se puede reprogramar un turno en estado '${resultado.estado}'` });
      case 'fuera_de_ventana':
        return res.status(409).json({
          error: `Fuera de la ventana mínima de reprogramación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
        });
      case 'ok':
        return res.json({ id: nuevoTurnoId, estado: resultado.estadoFinal });
    }
  })
);

// Mis turnos (cliente autenticado).
turnosRouter.get(
  '/mios',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const turnos = await withTransaction(
      async (client) => {
        const result = await client.query('SELECT * FROM turno WHERE cliente_id = $1 ORDER BY inicio DESC', [
          req.auth!.sub,
        ]);
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(turnos);
  })
);
