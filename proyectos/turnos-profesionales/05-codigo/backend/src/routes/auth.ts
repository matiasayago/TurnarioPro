import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { signToken } from '../auth';

export const authRouter = Router();

// HU-00a: administrador registra su negocio (multi-tenant, D1) y queda autenticado.
authRouter.post('/registro-negocio', (req, res) => {
  const { nombre_negocio, rubro, ubicacion, email, password, nombre_admin } = req.body;
  if (!nombre_negocio || !email || !password || !nombre_admin) {
    return res.status(400).json({ error: 'nombre_negocio, email, password y nombre_admin son requeridos' });
  }
  const existente = db.prepare('SELECT id FROM usuario WHERE email = ?').get(email);
  if (existente) return res.status(409).json({ error: 'Email ya registrado' });

  const negocioId = uuid();
  const usuarioId = uuid();
  const ts = nowIso();

  withTransaction(() => {
    db.prepare(
      'INSERT INTO negocio (id, nombre, rubro, ubicacion, creado_en) VALUES (?, ?, ?, ?, ?)'
    ).run(negocioId, nombre_negocio, rubro ?? null, ubicacion ?? null, ts);

    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(usuarioId, email, bcrypt.hashSync(password, 10), nombre_admin, 'administrador', ts);
  });

  const token = signToken({ sub: usuarioId, rol: 'administrador', negocio_id: negocioId });
  res.status(201).json({ token, negocio_id: negocioId });
});

// Login genérico para cliente, profesional o administrador.
authRouter.post('/login', (req, res) => {
  const { email, password } = req.body;
  const usuario = db.prepare('SELECT * FROM usuario WHERE email = ?').get(email) as any;
  if (!usuario || !bcrypt.compareSync(password ?? '', usuario.password_hash)) {
    return res.status(401).json({ error: 'Credenciales inválidas' });
  }

  if (usuario.rol === 'cliente') {
    const token = signToken({ sub: usuario.id, rol: 'cliente' });
    return res.json({ token });
  }

  const profesional = db
    .prepare('SELECT * FROM profesional WHERE usuario_id = ?')
    .get(usuario.id) as any;

  if (usuario.rol === 'profesional' && profesional) {
    const token = signToken({
      sub: usuario.id,
      rol: 'profesional',
      negocio_id: profesional.negocio_id,
      profesional_id: profesional.id,
    });
    return res.json({ token });
  }

  if (usuario.rol === 'administrador') {
    // El negocio del administrador se resuelve por ser el único que registró (MVP: 1 admin = 1 negocio).
    const negocio = db
      .prepare(
        `SELECT n.id FROM negocio n
         JOIN usuario u ON u.id = ? WHERE u.rol = 'administrador' LIMIT 1`
      )
      .get(usuario.id) as any;
    const token = signToken({ sub: usuario.id, rol: 'administrador', negocio_id: negocio?.id });
    return res.json({ token });
  }

  res.status(500).json({ error: 'Rol de usuario inconsistente' });
});

// HU-01: registro de cliente.
authRouter.post('/registro-cliente', (req, res) => {
  const { email, password, nombre } = req.body;
  if (!email || !password || !nombre) {
    return res.status(400).json({ error: 'email, password y nombre son requeridos' });
  }
  const existente = db.prepare('SELECT id FROM usuario WHERE email = ?').get(email);
  if (existente) return res.status(409).json({ error: 'Email ya registrado' });

  const usuarioId = uuid();
  db.prepare(
    'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(usuarioId, email, bcrypt.hashSync(password, 10), nombre, 'cliente', nowIso());

  const token = signToken({ sub: usuarioId, rol: 'cliente' });
  res.status(201).json({ token });
});
