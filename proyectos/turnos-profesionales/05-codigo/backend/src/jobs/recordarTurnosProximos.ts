import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import {
  armarAsuntoNotificacion,
  armarMensajeNotificacion,
  obtenerDatosNotificacionTurno,
  DatosMensajeNotificacion,
} from '../dominio/notificaciones';
import { emailProvider } from '../integraciones/email';

/**
 * HU-14b/HU-25 (ver database/migrations/001_init.sql, bloque "Bandeja de notificaciones",
 * "Recomendación para Backend" punto 3): recordatorio automático para turnos que están por
 * empezar. Wireframe (mapa-pantallas.md §5.15) muestra el ejemplo "Recordatorio: turno con Juan
 * Ramírez en 1 hora" — ventana de aviso elegida acá: 60 minutos antes del inicio del turno
 * (configurable, mismo criterio que VENTANA_CANCELACION_MIN en routes/turnos.ts /
 * EXPIRACION_PAGO_MIN en jobs/expirarPagosPendientes.ts).
 */
const VENTANA_RECORDATORIO_MIN = Number(process.env.VENTANA_RECORDATORIO_MIN ?? 60);

/**
 * Mismo caso de uso que expirarPagosPendientesVencidos (ver ese archivo): corre con
 * `jobSistema: true`, barriendo turnos de CUALQUIER cliente/negocio en una sola pasada — no
 * actúa "como" ningún usuario puntual. La policy `notificacion_insert_job_sistema` (ver
 * database/migrations/004_notificaciones.sql) habilita el INSERT con solo
 * `app.job_sistema = 'true'`.
 *
 * ANTI-DUPLICADO — hallazgo de RLS encontrado al implementar esto, corregido acá (no con una
 * migración nueva, fuera del alcance de Backend): la forma obvia de evitar duplicar el
 * recordatorio de un turno que ya lo tiene — un `NOT EXISTS` contra `notificacion` corriendo
 * SOLO con `app.job_sistema` seteado — NO alcanza. A diferencia de `turno` (que tiene la policy
 * pública transitoria `turno_select_publico`, `USING (true)`), `notificacion` solo tiene UNA
 * policy de SELECT, `notificacion_select_propia`
 * (`destinatario_usuario_id = app.usuario_id`) — y ninguna policy de SELECT de `notificacion`
 * reconoce `app.job_sistema` (solo la de INSERT la reconoce, ver
 * `notificacion_insert_job_sistema` en 004_notificaciones.sql). Con `app.usuario_id` sin setear,
 * esa policy nunca matchea ninguna fila — un `NOT EXISTS` evaluado en ese contexto vería SIEMPRE
 * 0 filas, sin importar si el recordatorio ya existe, y el job lo duplicaría en cada corrida, sin
 * ningún error visible (RLS deniega en silencio, no tira excepción).
 *
 * Se resuelve con la MISMA técnica que ya usa `POST /turnos` (routes/turnos.ts) para un problema
 * análogo (ver ahí el comentario "Cambio de identidad de RLS DENTRO de esta misma transacción"):
 * antes del INSERT de CADA turno candidato, se impersona al DESTINATARIO puntual de ese turno
 * (`SELECT set_config('app.usuario_id', <profesional.usuario_id>, true)`) — bajo esa identidad,
 * `notificacion_select_propia` sí deja ver los recordatorios que ya existan para ese mismo
 * destinatario, así que el `NOT EXISTS` (embebido en el propio INSERT ... SELECT ... WHERE NOT
 * EXISTS, atómico) queda correcto. El INSERT sigue pasando igual por
 * `notificacion_insert_job_sistema` (permisiva, se combina por OR con el resto de policies de
 * INSERT — no hace falta que TAMBIÉN cumpla `notificacion_insert_evento_turno`).
 * `app.job_sistema` sigue en 'true' durante todo esto (seteado una sola vez por
 * `withTransaction`, nunca se pisa — solo se cambia `app.usuario_id`).
 *
 * AMPLIACIÓN (2026-08-18, Backend — pedido explícito del CEO): notificar a AMBAS partes del
 * turno, no solo al profesional. La técnica de impersonación de arriba sigue funcionando SIN
 * ningún cambio al propio texto del INSERT/`WHERE NOT EXISTS`: se corre una vez por CADA
 * destinatario (antes solo el profesional; ahora también el cliente), impersonando a cada uno por
 * turno antes de "su" INSERT. Bajo la identidad del cliente, `notificacion_select_propia` deja
 * ver ÚNICAMENTE los recordatorios cuyo `destinatario_usuario_id` sea ese cliente — nunca los del
 * profesional del mismo turno (fila con otro `destinatario_usuario_id`, invisible bajo esa
 * impersonación) — así que el `NOT EXISTS` de cada destinatario queda aislado del otro sin
 * modificar su SQL: el 2do INSERT de un turno (para el cliente) NO se salta solo porque el 1ro
 * (para el profesional) ya haya dejado una fila con ese mismo `turno_id`/`tipo`.
 *
 * Recomendación para DBA/Director General IA (no implementada acá — cambio de RLS, fuera del
 * alcance de Backend en este ciclo): una policy de SELECT dedicada para `app.job_sistema` en
 * `notificacion` (análoga a `turno_acceso_job_expiracion`) sería una alternativa más directa a
 * nivel de esquema que esta impersonación por fila. Recomendación para QA/Security: este gap no
 * lo detecta ningún test HTTP existente (RLS deniega leyendo 0 filas, no tira error — mismo
 * patrón que Security ya señaló para RLS en general, ver 001_init.sql) — vale la pena agregar
 * este escenario a `../../../database/scripts/verificar_rls_postgres.sql` cuando exista.
 */
export async function recordarTurnosProximos(): Promise<number> {
  const ahora = new Date();
  const limite = new Date(ahora.getTime() + VENTANA_RECORDATORIO_MIN * 60_000);
  const ts = nowIso();

  const { insertados, nuevosParaEmail } = await withTransaction(
    async (client) => {
      // Solo toca `turno`/`profesional` (ambos con SELECT público, ver 001_init.sql) — no hace
      // falta impersonar nada para ESTA lectura. Turnos "vivos" (mismo criterio que
      // `uq_turno_slot_activo`) cuyo inicio cae estrictamente entre ahora y la ventana de aviso.
      // No se pre-filtran acá los que ya tienen recordatorio (ver comentario grande de arriba —
      // esa lectura necesita la impersonación por fila, no un filtro de conjunto): un turno que
      // ya lo tiene simplemente vuelve a aparecer como "candidato" en cada corrida mientras siga
      // dentro de la ventana, y el INSERT de más abajo no hace nada (WHERE NOT EXISTS) para él.
      // `t.cliente_id AS cliente_usuario_id` (agregada en la ampliación 2026-08-18): antes este
      // SELECT solo traía el destinatario profesional — ahora trae los 2 usuario_id candidatos a
      // notificar por cada turno.
      const candidatosResult = await client.query(
        `SELECT t.id AS turno_id, p.usuario_id AS profesional_usuario_id, t.cliente_id AS cliente_usuario_id
         FROM turno t
         JOIN profesional p ON p.id = t.profesional_id
         WHERE t.estado IN ('pendiente_de_pago', 'confirmado')
           AND t.inicio > $1
           AND t.inicio <= $2`,
        [ahora.toISOString(), limite.toISOString()]
      );
      const candidatos = candidatosResult.rows as {
        turno_id: string;
        profesional_usuario_id: string;
        cliente_usuario_id: string;
      }[];

      let insertados = 0;
      // Turnos para los que ESTA corrida realmente insertó una fila nueva (no un no-op del
      // `WHERE NOT EXISTS`) — solo esos disparan un email más abajo, fuera de la transacción. Sin
      // este chequeo, un turno que sigue siendo "candidato" en cada corrida del job (ver
      // comentario de arriba) reenviaría el mismo recordatorio por email en cada tick del
      // intervalo (cada 60s por default, ver `iniciarJobRecordatorios`) mientras dure la ventana
      // de aviso — el INSERT ya es idempotente por destinatario, pero el envío de email no lo
      // sería si no se gatea igual acá.
      const nuevosParaEmail: { turnoId: string; esCliente: boolean }[] = [];

      for (const { turno_id, profesional_usuario_id, cliente_usuario_id } of candidatos) {
        // Un recordatorio por turno POR DESTINATARIO (ampliación 2026-08-18) — ver el bloque
        // "AMPLIACIÓN" del comentario grande de arriba: mismo mecanismo de impersonación,
        // corrido una vez por cada uno de los 2 destinatarios de este turno.
        for (const { destinatarioUsuarioId, esCliente } of [
          { destinatarioUsuarioId: profesional_usuario_id, esCliente: false },
          { destinatarioUsuarioId: cliente_usuario_id, esCliente: true },
        ]) {
          // Impersona al destinatario de ESTE turno — ver comentario grande de arriba.
          await client.query('SELECT set_config($1, $2, true)', ['app.usuario_id', destinatarioUsuarioId]);
          const insertResult = await client.query(
            `INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en)
             SELECT $1, $2, 'recordatorio', $3, $4
             WHERE NOT EXISTS (
               SELECT 1 FROM notificacion n WHERE n.turno_id = $2 AND n.tipo = 'recordatorio'
             )`,
            [uuid(), turno_id, destinatarioUsuarioId, ts]
          );
          const filasInsertadas = insertResult.rowCount ?? 0;
          insertados += filasInsertadas;
          if (filasInsertadas > 0) {
            nuevosParaEmail.push({ turnoId: turno_id, esCliente });
          }
        }
      }

      return { insertados, nuevosParaEmail };
    },
    { jobSistema: true }
  );

  // Envío real por email (ampliación 2026-08-18, pedido explícito del CEO — best-effort, SIEMPRE
  // fuera de la transacción de arriba, que ya terminó con COMMIT en este punto): a diferencia de
  // un request HTTP, este job corre en background sin nada que "responder" — el mismo criterio
  // aplica igual: un email que falla no frena el resto del loop (try/catch por destinatario,
  // adentro de `enviarEmailRecordatorio`, seguí con el resto).
  for (const { turnoId, esCliente } of nuevosParaEmail) {
    await enviarEmailRecordatorio(turnoId, esCliente);
  }

  return insertados;
}

/** Envía UN email de recordatorio y nunca lanza — ver el comentario equivalente en
 *  routes/turnos.ts (mismo criterio fail-closed/no-throw que integraciones/pagos.ts
 *  `validarWebhook`, para no frenar el resto del loop de `recordarTurnosProximos` por un problema
 *  de un sistema externo). Vuelve a leer `obtenerDatosNotificacionTurno` por cada llamado (en vez
 *  de cachear entre las 2 posibles llamadas del mismo turno) — este job barre, como mucho, los
 *  turnos que empiezan dentro de la próxima hora, un volumen chico que no justifica la
 *  complejidad extra de una caché por corrida. */
async function enviarEmailRecordatorio(turnoId: string, esCliente: boolean): Promise<void> {
  let datos;
  try {
    datos = await obtenerDatosNotificacionTurno(pool, turnoId);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(`[jobs] Error leyendo datos para notificar por email (turno ${turnoId}, recordatorio):`, err);
    return;
  }
  if (!datos) return;

  const datosMensaje: DatosMensajeNotificacion = {
    tipo: 'recordatorio',
    clienteNombre: datos.clienteNombre,
    profesionalNombre: datos.profesionalNombre,
    turnoInicio: datos.turnoInicio,
    destinatarioEsCliente: esCliente,
  };
  const destinatarioEmail = esCliente ? datos.clienteEmail : datos.profesionalEmail;

  try {
    await emailProvider.enviarNotificacion(
      destinatarioEmail,
      armarAsuntoNotificacion('recordatorio'),
      armarMensajeNotificacion(datosMensaje)
    );
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(
      `[jobs] Error enviando email de recordatorio (turno ${turnoId}, destinatarioEsCliente=${esCliente}) a ${destinatarioEmail}:`,
      err
    );
  }
}

/** Arranca el job periódico. Se detiene con clearInterval(handle) si hace falta (tests). Mismo
 *  patrón que iniciarJobExpiracionPagos (jobs/expirarPagosPendientes.ts) — `setInterval` no
 *  puede `await` su callback, cada corrida se dispara "fire and forget" y cualquier error se
 *  loguea acá mismo en vez de dejarlo escapar como una unhandled rejection del proceso. */
export function iniciarJobRecordatorios(intervaloMs = 60_000): NodeJS.Timeout {
  return setInterval(() => {
    recordarTurnosProximos()
      .then((cantidad) => {
        if (cantidad > 0) {
          // eslint-disable-next-line no-console
          console.log(`[jobs] Insertaron ${cantidad} recordatorio(s) de turnos próximos a comenzar.`);
        }
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[jobs] Error corriendo recordarTurnosProximos:', err);
      });
  }, intervaloMs);
}
