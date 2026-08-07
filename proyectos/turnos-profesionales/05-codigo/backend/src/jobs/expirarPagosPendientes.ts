import { nowIso, withTransaction } from '../db';

/**
 * Ver documento-arquitectura.md §3 (máquina de estados del turno): un turno
 * `pendiente_de_pago` debe expirar automáticamente si Mercado Pago no confirma el pago
 * dentro de la ventana configurada, liberando el slot (vuelve a estar disponible porque el
 * índice único parcial `uq_turno_slot_activo` solo cubre pendiente_de_pago/confirmado).
 */
const EXPIRACION_PAGO_MIN = Number(process.env.EXPIRACION_PAGO_MIN ?? 15);

/**
 * Este es el caso de uso real de `contexto.jobSistema = true` (ver ContextoRls en src/db.ts):
 * este job barre turnos de CUALQUIER cliente/negocio en una misma pasada — no actúa "como"
 * ningún usuario puntual, así que ninguna combinación de usuarioId/negocioId lo habilitaría
 * bajo las policies pensadas para requests HTTP autenticados. La policy `turno_acceso_job_expiracion`
 * (agregada por Backend en migrations/001_init.sql, ver esa policy para el detalle) es la única
 * que reconoce `app.job_sistema` y habilita el UPDATE de este job sobre CUALQUIER fila de `turno`.
 *
 * Tanto el SELECT que localiza los turnos vencidos como los UPDATE que los expiran corren sobre
 * el MISMO client de una sola transacción (a diferencia de la versión síncrona anterior, que
 * hacía el SELECT suelto antes de abrir la transacción — inofensivo con node:sqlite, que no
 * tenía RLS, pero necesario ahora: sin `app.job_sistema` seteado, el SELECT tampoco vería turnos
 * de otros clientes bajo la policy `turno_acceso_negocio_o_cliente`/`turno_select_publico`... en
 * este caso puntual el SELECT igual sería visible vía `turno_select_publico`, pero se mantiene
 * todo dentro de la misma transacción por consistencia y porque el UPDATE sí lo necesita).
 */
export async function expirarPagosPendientesVencidos(): Promise<number> {
  const limite = new Date(Date.now() - EXPIRACION_PAGO_MIN * 60_000).toISOString();
  const ts = nowIso();

  return withTransaction(
    async (client) => {
      const vencidosResult = await client.query(
        "SELECT id FROM turno WHERE estado = 'pendiente_de_pago' AND creado_en < $1",
        [limite]
      );
      const vencidos = vencidosResult.rows as { id: string }[];

      for (const { id } of vencidos) {
        await client.query("UPDATE turno SET estado = 'cancelado', modificado_en = $1 WHERE id = $2", [
          ts,
          id,
        ]);
        await client.query(
          "UPDATE pago SET estado = 'expirado' WHERE turno_id = $1 AND estado = 'pendiente'",
          [id]
        );
      }

      return vencidos.length;
    },
    { jobSistema: true }
  );
}

/** Arranca el job periódico. Se detiene con clearInterval(handle) si hace falta (tests).
 *
 *  `setInterval` no puede `await` su callback — cada corrida se dispara "fire and forget" y
 *  cualquier error se loguea acá mismo (`.catch`) en vez de dejarlo escapar como una unhandled
 *  rejection del proceso (que node:sqlite nunca podía producir, al ser 100% síncrono; con
 *  `pg`/Postgres, cada corrida hace I/O real y puede rechazar). */
export function iniciarJobExpiracionPagos(intervaloMs = 60_000): NodeJS.Timeout {
  return setInterval(() => {
    expirarPagosPendientesVencidos()
      .then((cantidad) => {
        if (cantidad > 0) {
          // eslint-disable-next-line no-console
          console.log(
            `[jobs] Expiraron ${cantidad} turno(s) pendiente_de_pago (>${EXPIRACION_PAGO_MIN} min sin pago).`
          );
        }
      })
      .catch((err) => {
        // eslint-disable-next-line no-console
        console.error('[jobs] Error corriendo expirarPagosPendientesVencidos:', err);
      });
  }, intervaloMs);
}
