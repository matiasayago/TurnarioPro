import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';

export const turnosRouter = Router();

// RN8: ventana mínima de cancelación/reprogramación (parametrizable, propuesta 2 horas — A3).
const VENTANA_MIN_MINUTOS = Number(process.env.VENTANA_CANCELACION_MIN ?? 120);

function dentroDeVentanaMinima(inicioTurno: string): boolean {
  const minutosParaElTurno = (new Date(inicioTurno).getTime() - Date.now()) / 60_000;
  return minutosParaElTurno < VENTANA_MIN_MINUTOS;
}

// HU-09 / HU-09b: reservar un turno. Ver documento-arquitectura.md §4 — la garantía
// anti-doble-reserva (RN2) vive en el índice único parcial `uq_turno_slot_activo`, no en un
// SELECT previo. Si dos clientes piden el mismo (profesional_id, inicio) al mismo tiempo,
// SQLite/Postgres solo deja pasar un INSERT; el segundo lanza SQLITE_CONSTRAINT_UNIQUE / 23505.
turnosRouter.post('/', requireAuth('cliente'), (req: AuthedRequest, res) => {
  const { profesional_id, servicio_id, inicio } = req.body;
  if (!profesional_id || !servicio_id || !inicio) {
    return res.status(400).json({ error: 'profesional_id, servicio_id e inicio son requeridos' });
  }

  const profesional = db
    .prepare('SELECT negocio_id FROM profesional WHERE id = ?')
    .get(profesional_id) as { negocio_id: string } | undefined;
  const servicio = db
    .prepare('SELECT duracion_min FROM servicio WHERE id = ?')
    .get(servicio_id) as { duracion_min: number } | undefined;
  if (!profesional || !servicio) {
    return res.status(404).json({ error: 'Profesional o servicio no encontrado' });
  }

  const relacion = db
    .prepare(
      'SELECT requiere_sena, monto_sena FROM profesional_servicio WHERE profesional_id = ? AND servicio_id = ?'
    )
    .get(profesional_id, servicio_id) as { requiere_sena: number; monto_sena: number | null } | undefined;

  const inicioDate = new Date(inicio);
  const finDate = new Date(inicioDate.getTime() + servicio.duracion_min * 60_000);
  const requiereSena = !!relacion?.requiere_sena; // D2/RN10 — configurable por profesional+servicio
  const estadoInicial = requiereSena ? 'pendiente_de_pago' : 'confirmado';
  const turnoId = uuid();
  const ts = nowIso();

  try {
    withTransaction(() => {
      db.prepare(
        `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(
        turnoId,
        profesional.negocio_id,
        profesional_id,
        servicio_id,
        req.auth!.sub,
        inicioDate.toISOString(),
        finDate.toISOString(),
        estadoInicial,
        ts
      );

      if (requiereSena) {
        db.prepare(
          'INSERT INTO pago (id, turno_id, monto, estado, creado_en) VALUES (?, ?, ?, ?, ?)'
        ).run(uuid(), turnoId, relacion?.monto_sena ?? 0, 'pendiente', ts);
      }

      db.prepare(
        'INSERT INTO notificacion (id, turno_id, tipo, creado_en) VALUES (?, ?, ?, ?)'
      ).run(uuid(), turnoId, 'confirmacion', ts); // D4 — el envío real lo hace el proveedor de notificaciones (stub, ver notificaciones.ts)
    });
  } catch (err: any) {
    // node:sqlite (dev): code ERR_SQLITE_ERROR + "UNIQUE constraint failed".
    // Postgres (prod, ver database/migrations/001_init.sql): code 23505 unique_violation.
    if (String(err.message).includes('UNIQUE') || err.code === '23505') {
      return res.status(409).json({
        error: 'Ese horario ya no está disponible — alguien más lo reservó primero (RN2).',
      });
    }
    throw err;
  }

  res.status(201).json({
    id: turnoId,
    estado: estadoInicial,
    requiere_pago: requiereSena,
    monto_sena: relacion?.monto_sena ?? null,
  });
});

// HU-12: cancelar un turno propio.
turnosRouter.patch('/:id/cancelar', requireAuth('cliente'), (req: AuthedRequest, res) => {
  const turno = db.prepare('SELECT * FROM turno WHERE id = ?').get(req.params.id) as any;
  if (!turno) return res.status(404).json({ error: 'Turno no encontrado' });
  if (turno.cliente_id !== req.auth!.sub) {
    return res.status(403).json({ error: 'No podés cancelar un turno que no es tuyo' });
  }
  if (dentroDeVentanaMinima(turno.inicio)) {
    return res.status(409).json({
      error: `Fuera de la ventana mínima de cancelación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
    });
  }
  db.prepare("UPDATE turno SET estado = 'cancelado', modificado_en = ? WHERE id = ?").run(
    nowIso(),
    req.params.id
  );
  res.json({ ok: true });
});

// HU-13: reprogramar un turno propio a otro horario del MISMO profesional/servicio (CU5).
// Reutiliza la misma garantía anti-doble-reserva del alta (índice único parcial, ver §4 de
// documento-arquitectura.md): el turno viejo se marca 'reprogramado' (sale del índice, que
// solo cubre pendiente_de_pago/confirmado) y el nuevo se inserta con el nuevo horario; si ese
// horario ya lo tomó otro cliente, el INSERT falla con 409 igual que en POST /turnos.
turnosRouter.patch('/:id/reprogramar', requireAuth('cliente'), (req: AuthedRequest, res) => {
  const { nuevo_inicio } = req.body;
  if (!nuevo_inicio) return res.status(400).json({ error: 'nuevo_inicio es requerido' });

  const turno = db.prepare('SELECT * FROM turno WHERE id = ?').get(req.params.id) as any;
  if (!turno) return res.status(404).json({ error: 'Turno no encontrado' });
  if (turno.cliente_id !== req.auth!.sub) {
    return res.status(403).json({ error: 'No podés reprogramar un turno que no es tuyo' });
  }
  if (!['pendiente_de_pago', 'confirmado'].includes(turno.estado)) {
    return res.status(409).json({ error: `No se puede reprogramar un turno en estado '${turno.estado}'` });
  }
  if (dentroDeVentanaMinima(turno.inicio)) {
    return res.status(409).json({
      error: `Fuera de la ventana mínima de reprogramación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
    });
  }

  const servicio = db.prepare('SELECT duracion_min FROM servicio WHERE id = ?').get(turno.servicio_id) as
    | { duracion_min: number }
    | undefined;
  const nuevoInicioDate = new Date(nuevo_inicio);
  const nuevoFinDate = new Date(nuevoInicioDate.getTime() + servicio!.duracion_min * 60_000);
  const nuevoTurnoId = uuid();
  const ts = nowIso();

  try {
    withTransaction(() => {
      db.prepare("UPDATE turno SET estado = 'reprogramado', modificado_en = ? WHERE id = ?").run(ts, turno.id);

      db.prepare(
        `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(
        nuevoTurnoId,
        turno.negocio_id,
        turno.profesional_id,
        turno.servicio_id,
        turno.cliente_id,
        nuevoInicioDate.toISOString(),
        nuevoFinDate.toISOString(),
        turno.estado === 'confirmado' ? 'confirmado' : 'pendiente_de_pago', // conserva el estado de pago (D2)
        ts
      );

      // El pago (si existe) sigue al turno reprogramado — no se le vuelve a cobrar la seña.
      db.prepare('UPDATE pago SET turno_id = ? WHERE turno_id = ?').run(nuevoTurnoId, turno.id);

      db.prepare(
        'INSERT INTO notificacion (id, turno_id, tipo, creado_en) VALUES (?, ?, ?, ?)'
      ).run(uuid(), nuevoTurnoId, 'confirmacion', ts);
    });
  } catch (err: any) {
    if (String(err.message).includes('UNIQUE') || err.code === '23505') {
      return res.status(409).json({
        error: 'Ese nuevo horario ya no está disponible — alguien más lo reservó primero (RN2).',
      });
    }
    throw err;
  }

  res.json({ id: nuevoTurnoId, estado: turno.estado === 'confirmado' ? 'confirmado' : 'pendiente_de_pago' });
});

// Mis turnos (cliente autenticado).
turnosRouter.get('/mios', requireAuth('cliente'), (req: AuthedRequest, res) => {
  const turnos = db
    .prepare('SELECT * FROM turno WHERE cliente_id = ? ORDER BY inicio DESC')
    .all(req.auth!.sub);
  res.json(turnos);
});
