import { db, nowIso, withTransaction } from '../db';

/**
 * Ver documento-arquitectura.md §3 (máquina de estados del turno): un turno
 * `pendiente_de_pago` debe expirar automáticamente si Mercado Pago no confirma el pago
 * dentro de la ventana configurada, liberando el slot (vuelve a estar disponible porque el
 * índice único parcial `uq_turno_slot_activo` solo cubre pendiente_de_pago/confirmado).
 */
const EXPIRACION_PAGO_MIN = Number(process.env.EXPIRACION_PAGO_MIN ?? 15);

export function expirarPagosPendientesVencidos(): number {
  const limite = new Date(Date.now() - EXPIRACION_PAGO_MIN * 60_000).toISOString();

  const vencidos = db
    .prepare("SELECT id FROM turno WHERE estado = 'pendiente_de_pago' AND creado_en < ?")
    .all(limite) as { id: string }[];

  if (vencidos.length === 0) return 0;

  const ts = nowIso();
  withTransaction(() => {
    for (const { id } of vencidos) {
      db.prepare("UPDATE turno SET estado = 'cancelado', modificado_en = ? WHERE id = ?").run(ts, id);
      db.prepare("UPDATE pago SET estado = 'expirado' WHERE turno_id = ? AND estado = 'pendiente'").run(id);
    }
  });

  return vencidos.length;
}

/** Arranca el job periódico. Se detiene con clearInterval(handle) si hace falta (tests). */
export function iniciarJobExpiracionPagos(intervaloMs = 60_000): NodeJS.Timeout {
  return setInterval(() => {
    const cantidad = expirarPagosPendientesVencidos();
    if (cantidad > 0) {
      // eslint-disable-next-line no-console
      console.log(`[jobs] Expiraron ${cantidad} turno(s) pendiente_de_pago (>${EXPIRACION_PAGO_MIN} min sin pago).`);
    }
  }, intervaloMs);
}
