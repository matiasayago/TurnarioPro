import { Router } from 'express';
import { withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';

export const clientesRouter = Router();

// HU-11: historial de visitas de un cliente — D3/RN7: SOLO lo ve el profesional que atendió
// cada turno. No se filtra en el cliente (UI), se filtra acá, en la query.
clientesRouter.get(
  '/:id/historial',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const historial = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT t.id, t.inicio, t.estado, s.nombre AS servicio
           FROM turno t
           JOIN servicio s ON s.id = t.servicio_id
           WHERE t.cliente_id = $1 AND t.profesional_id = $2
           ORDER BY t.inicio DESC`,
          [req.params.id, req.auth!.profesional_id!]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(historial);
  })
);
