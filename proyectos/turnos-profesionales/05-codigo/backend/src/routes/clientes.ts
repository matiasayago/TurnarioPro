import { Router } from 'express';
import { db } from '../db';
import { requireAuth, AuthedRequest } from '../auth';

export const clientesRouter = Router();

// HU-11: historial de visitas de un cliente — D3/RN7: SOLO lo ve el profesional que atendió
// cada turno. No se filtra en el cliente (UI), se filtra acá, en la query.
clientesRouter.get('/:id/historial', requireAuth('profesional'), (req: AuthedRequest, res) => {
  const historial = db
    .prepare(
      `SELECT t.id, t.inicio, t.estado, s.nombre AS servicio
       FROM turno t
       JOIN servicio s ON s.id = t.servicio_id
       WHERE t.cliente_id = ? AND t.profesional_id = ?
       ORDER BY t.inicio DESC`
    )
    .all(req.params.id, req.auth!.profesional_id!);
  res.json(historial);
});
