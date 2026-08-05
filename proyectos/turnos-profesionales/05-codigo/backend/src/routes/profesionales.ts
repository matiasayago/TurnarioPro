import { Router } from 'express';
import { v4 as uuid } from 'uuid';
import { db, nowIso } from '../db';
import { requireAuth, AuthedRequest } from '../auth';

export const profesionalesRouter = Router();

function esPropioProfesional(req: AuthedRequest): boolean {
  return req.auth!.rol === 'profesional' && req.auth!.profesional_id === req.params.id;
}

// HU-04 / HU-04b: el profesional asocia un servicio a su agenda y configura si requiere seña.
profesionalesRouter.post('/:id/servicios', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés configurar tus propios servicios' });
  }
  const { servicio_id, requiere_sena, monto_sena } = req.body;
  if (!servicio_id) return res.status(400).json({ error: 'servicio_id es requerido' });

  db.prepare(
    `INSERT INTO profesional_servicio (profesional_id, servicio_id, requiere_sena, monto_sena)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(profesional_id, servicio_id) DO UPDATE SET requiere_sena = excluded.requiere_sena, monto_sena = excluded.monto_sena`
  ).run(req.params.id, servicio_id, requiere_sena ? 1 : 0, monto_sena ?? null);

  res.status(201).json({ ok: true });
});

// HU-05: el profesional define un bloque de disponibilidad recurrente.
profesionalesRouter.post('/:id/disponibilidad', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés definir tu propia disponibilidad' });
  }
  const { servicio_id, dia_semana, hora_inicio, hora_fin } = req.body;
  if (servicio_id === undefined || dia_semana === undefined || !hora_inicio || !hora_fin) {
    return res.status(400).json({ error: 'servicio_id, dia_semana, hora_inicio y hora_fin son requeridos' });
  }
  const id = uuid();
  db.prepare(
    `INSERT INTO disponibilidad (id, profesional_id, servicio_id, dia_semana, hora_inicio, hora_fin, creado_en)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(id, req.params.id, servicio_id, dia_semana, hora_inicio, hora_fin, nowIso());
  res.status(201).json({ id });
});

// HU-15: excepción puntual (feriado/licencia) — RN5/RN6.
profesionalesRouter.post('/:id/excepciones', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés bloquear tu propia agenda' });
  }
  const { inicio, fin, motivo } = req.body;
  if (!inicio || !fin) return res.status(400).json({ error: 'inicio y fin son requeridos' });

  const turnosAfectados = db
    .prepare(
      `SELECT id FROM turno WHERE profesional_id = ? AND estado IN ('pendiente_de_pago','confirmado')
       AND inicio < ? AND fin > ?`
    )
    .all(req.params.id, fin, inicio);

  const id = uuid();
  db.prepare(
    'INSERT INTO excepcion_disponibilidad (id, profesional_id, inicio, fin, motivo, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(id, req.params.id, inicio, fin, motivo ?? null, nowIso());

  res.status(201).json({
    id,
    turnos_afectados: turnosAfectados.length,
    aviso: turnosAfectados.length > 0
      ? 'RN6: hay turnos ya reservados en este rango — gestioná su reprogramación antes de confirmar el bloqueo definitivo.'
      : undefined,
  });
});

// HU-09: slots disponibles de un profesional para un servicio (motor de disponibilidad — CU1/CU4).
// Implementación simplificada para este slice: calcula slots de los próximos N días a partir
// de los bloques de `disponibilidad`, descuenta turnos activos y excepciones, y si no hay nada
// en el rango pedido devuelve el próximo disponible (D5, sin lista de espera).
profesionalesRouter.get('/:id/slots', (req, res) => {
  const { servicio_id, desde, dias } = req.query as { servicio_id?: string; desde?: string; dias?: string };
  if (!servicio_id) return res.status(400).json({ error: 'servicio_id es requerido' });

  const servicio = db.prepare('SELECT duracion_min FROM servicio WHERE id = ?').get(servicio_id) as
    | { duracion_min: number }
    | undefined;
  if (!servicio) return res.status(404).json({ error: 'Servicio no encontrado' });

  const bloques = db
    .prepare('SELECT * FROM disponibilidad WHERE profesional_id = ? AND servicio_id = ?')
    .all(req.params.id, servicio_id) as any[];

  const inicioBusqueda = desde ? new Date(desde) : new Date();
  const ventanaDias = Number(dias ?? 14);
  const duracionMs = servicio.duracion_min * 60_000;

  const turnosActivos = db
    .prepare(
      `SELECT inicio, fin FROM turno WHERE profesional_id = ? AND estado IN ('pendiente_de_pago','confirmado')`
    )
    .all(req.params.id) as { inicio: string; fin: string }[];

  const excepciones = db
    .prepare('SELECT inicio, fin FROM excepcion_disponibilidad WHERE profesional_id = ?')
    .all(req.params.id) as { inicio: string; fin: string }[];

  const ocupado = (ini: Date, fin: Date) =>
    [...turnosActivos, ...excepciones].some(
      (o) => ini < new Date(o.fin) && fin > new Date(o.inicio)
    );

  const slots: string[] = [];
  for (let d = 0; d < ventanaDias && slots.length < 20; d++) {
    const dia = new Date(inicioBusqueda);
    dia.setDate(dia.getDate() + d);
    const bloqueDelDia = bloques.find((b) => b.dia_semana === dia.getDay());
    if (!bloqueDelDia) continue;

    const [hIni, mIni] = bloqueDelDia.hora_inicio.split(':').map(Number);
    const [hFin, mFin] = bloqueDelDia.hora_fin.split(':').map(Number);
    let cursor = new Date(dia);
    cursor.setHours(hIni, mIni, 0, 0);
    const finBloque = new Date(dia);
    finBloque.setHours(hFin, mFin, 0, 0);

    while (cursor.getTime() + duracionMs <= finBloque.getTime() && slots.length < 20) {
      const finSlot = new Date(cursor.getTime() + duracionMs);
      if (cursor > inicioBusqueda && !ocupado(cursor, finSlot)) {
        slots.push(cursor.toISOString());
      }
      cursor = finSlot;
    }
  }

  res.json({
    slots,
    proximo_disponible: slots[0] ?? null, // D5
  });
});

// HU-06: agenda del profesional autenticado (turnos propios, para la pantalla de Agenda).
profesionalesRouter.get('/:id/turnos', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés ver tu propia agenda' });
  }
  const turnos = db
    .prepare(
      `SELECT t.id, t.inicio, t.fin, t.estado, s.nombre AS servicio, u.nombre AS cliente
       FROM turno t
       JOIN servicio s ON s.id = t.servicio_id
       JOIN usuario u ON u.id = t.cliente_id
       WHERE t.profesional_id = ? AND t.estado IN ('pendiente_de_pago','confirmado')
       ORDER BY t.inicio ASC`
    )
    .all(req.params.id);
  res.json(turnos);
});

// HU-10: listado de clientes atendidos por el profesional autenticado.
profesionalesRouter.get('/:id/clientes', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés ver tus propios clientes' });
  }
  const clientes = db
    .prepare(
      `SELECT DISTINCT u.id, u.nombre, u.email FROM turno t
       JOIN usuario u ON u.id = t.cliente_id
       WHERE t.profesional_id = ?`
    )
    .all(req.params.id);
  res.json(clientes);
});
