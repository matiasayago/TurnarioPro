import { v4 as uuid } from 'uuid';
import { nowIso, withTransaction } from '../db';

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

  return withTransaction(
    async (client) => {
      // Solo toca `turno`/`profesional` (ambos con SELECT público, ver 001_init.sql) — no hace
      // falta impersonar nada para ESTA lectura. Turnos "vivos" (mismo criterio que
      // `uq_turno_slot_activo`) cuyo inicio cae estrictamente entre ahora y la ventana de aviso.
      // No se pre-filtran acá los que ya tienen recordatorio (ver comentario grande de arriba —
      // esa lectura necesita la impersonación por fila, no un filtro de conjunto): un turno que
      // ya lo tiene simplemente vuelve a aparecer como "candidato" en cada corrida mientras siga
      // dentro de la ventana, y el INSERT de más abajo no hace nada (WHERE NOT EXISTS) para él.
      const candidatosResult = await client.query(
        `SELECT t.id AS turno_id, p.usuario_id AS destinatario_usuario_id
         FROM turno t
         JOIN profesional p ON p.id = t.profesional_id
         WHERE t.estado IN ('pendiente_de_pago', 'confirmado')
           AND t.inicio > $1
           AND t.inicio <= $2`,
        [ahora.toISOString(), limite.toISOString()]
      );
      const candidatos = candidatosResult.rows as {
        turno_id: string;
        destinatario_usuario_id: string;
      }[];

      let insertados = 0;
      for (const { turno_id, destinatario_usuario_id } of candidatos) {
        // Impersona al destinatario de ESTE turno — ver comentario grande de arriba.
        await client.query('SELECT set_config($1, $2, true)', ['app.usuario_id', destinatario_usuario_id]);
        const insertResult = await client.query(
          `INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en)
           SELECT $1, $2, 'recordatorio', $3, $4
           WHERE NOT EXISTS (
             SELECT 1 FROM notificacion n WHERE n.turno_id = $2 AND n.tipo = 'recordatorio'
           )`,
          [uuid(), turno_id, destinatario_usuario_id, ts]
        );
        insertados += insertResult.rowCount ?? 0;
      }

      return insertados;
    },
    { jobSistema: true }
  );
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
