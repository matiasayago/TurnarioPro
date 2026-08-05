import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';

export const negociosRouter = Router();

// HU-00b: cliente descubre negocios (RN9 — no se filtra por negocio_id porque es cross-tenant por diseño).
negociosRouter.get('/', (_req, res) => {
  const negocios = db
    .prepare('SELECT id, nombre, rubro, ubicacion FROM negocio WHERE eliminado_en IS NULL')
    .all();
  res.json(negocios);
});

// HU-07: servicios de un negocio puntual (público, para que el cliente elija).
negociosRouter.get('/:id/servicios', (req, res) => {
  const servicios = db
    .prepare(
      'SELECT id, nombre, duracion_min, precio_referencia FROM servicio WHERE negocio_id = ? AND eliminado_en IS NULL'
    )
    .all(req.params.id);
  res.json(servicios);
});

// HU-08: profesionales del negocio que ofrecen un servicio puntual (público, para que el
// cliente elija profesional una vez que ya eligió el servicio — CU4 paso 2).
negociosRouter.get('/:id/servicios/:servicioId/profesionales', (req, res) => {
  const profesionales = db
    .prepare(
      `SELECT p.id, u.nombre
       FROM profesional p
       JOIN usuario u ON u.id = p.usuario_id
       JOIN profesional_servicio ps ON ps.profesional_id = p.id
       WHERE p.negocio_id = ? AND ps.servicio_id = ? AND p.eliminado_en IS NULL`
    )
    .all(req.params.id, req.params.servicioId);
  res.json(profesionales);
});

// HU-03: administrador carga un servicio de SU negocio (RN9 aplicado vía claim del JWT, no del parámetro).
negociosRouter.post('/:id/servicios', requireAuth('administrador'), (req: AuthedRequest, res) => {
  if (req.auth!.negocio_id !== req.params.id) {
    return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
  }
  const { nombre, duracion_min, precio_referencia } = req.body;
  if (!nombre || !duracion_min) {
    return res.status(400).json({ error: 'nombre y duracion_min son requeridos' });
  }
  const id = uuid();
  db.prepare(
    'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(id, req.params.id, nombre, duracion_min, precio_referencia ?? null, nowIso());
  res.status(201).json({ id });
});

// HU-02: administrador da de alta un profesional de SU negocio.
negociosRouter.post('/:id/profesionales', requireAuth('administrador'), (req: AuthedRequest, res) => {
  if (req.auth!.negocio_id !== req.params.id) {
    return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
  }
  const { email, password, nombre } = req.body;
  if (!email || !password || !nombre) {
    return res.status(400).json({ error: 'email, password y nombre son requeridos' });
  }
  const existente = db.prepare('SELECT id FROM usuario WHERE email = ?').get(email);
  if (existente) return res.status(409).json({ error: 'Email ya registrado' });

  const usuarioId = uuid();
  const profesionalId = uuid();
  const ts = nowIso();
  withTransaction(() => {
    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(usuarioId, email, bcrypt.hashSync(password, 10), nombre, 'profesional', ts);
    db.prepare(
      'INSERT INTO profesional (id, usuario_id, negocio_id, creado_en) VALUES (?, ?, ?, ?)'
    ).run(profesionalId, usuarioId, req.params.id, ts);
  });
  res.status(201).json({ id: profesionalId });
});
