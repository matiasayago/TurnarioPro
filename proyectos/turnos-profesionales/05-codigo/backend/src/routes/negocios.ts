import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import {
  uuidSchema,
  montoPositivoSchema,
  passwordSchema,
  respuestaValidacionFallida,
} from '../dominio/validacion';

export const negociosRouter = Router();

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación de entrada — se
// aplican al INICIO de cada handler, antes de tocar la base de datos.
const negocioIdParamsSchema = z.object({ id: uuidSchema });

const altaServicioSchema = z.object({
  nombre: z.string().min(1, 'nombre es requerido'),
  duracion_min: montoPositivoSchema,
  precio_referencia: montoPositivoSchema.nullable().optional(),
});

// MEDIUM-1 (ver 07-seguridad/informe-seguridad.md): misma política mínima de contraseña que
// registro-negocio/registro-cliente, aplicada acá también (alta de profesional por el admin).
const altaProfesionalSchema = z.object({
  email: z.string().email('email debe ser una dirección de correo válida'),
  password: passwordSchema,
  nombre: z.string().min(1, 'nombre es requerido'),
});

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
// `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — el JOIN pasa por
// `negocio_profesional`, que resuelve la membresía activa del profesional en ESTE negocio en
// particular (un mismo profesional puede pertenecer a otros negocios además de este).
negociosRouter.get('/:id/servicios/:servicioId/profesionales', (req, res) => {
  const profesionales = db
    .prepare(
      `SELECT p.id, u.nombre
       FROM profesional p
       JOIN usuario u ON u.id = p.usuario_id
       JOIN profesional_servicio ps ON ps.profesional_id = p.id
       JOIN negocio_profesional np ON np.profesional_id = p.id AND np.negocio_id = ? AND np.activo = 1
       WHERE ps.servicio_id = ? AND p.eliminado_en IS NULL`
    )
    .all(req.params.id, req.params.servicioId);
  res.json(profesionales);
});

// HU-03: administrador carga un servicio de SU negocio (RN9 aplicado vía claim del JWT, no del parámetro).
negociosRouter.post('/:id/servicios', requireAuth('administrador'), (req: AuthedRequest, res) => {
  const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
  if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
  if (req.auth!.negocio_id !== req.params.id) {
    return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
  }
  const bodyParsed = altaServicioSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { nombre, duracion_min, precio_referencia } = bodyParsed.data;
  const id = uuid();
  db.prepare(
    'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(id, req.params.id, nombre, duracion_min, precio_referencia ?? null, nowIso());
  res.status(201).json({ id });
});

// HU-02: administrador da de alta un profesional de SU negocio.
// Generalización N:M (ver modelo-datos.md §2ter): un mismo profesional puede trabajar en más
// de un negocio, así que un email que YA pertenece a una identidad profesional existente (dada
// de alta antes por OTRO negocio) no es un conflicto — hay que reusar esa fila de `profesional`
// (por `usuario_id`, que sigue siendo UNIQUE) e insertar solo el vínculo nuevo en
// `negocio_profesional`, nunca duplicar la identidad. `password`/`nombre` del body se IGNORAN a
// propósito en el caso de reuso: son necesarios en el schema porque el mismo endpoint también
// crea la cuenta cuando es la primera vez, pero pisar la contraseña de una identidad ya
// existente dejaría que un segundo negocio le "robe" el acceso a un profesional que ya trabaja
// en otro lado — solo el email correlaciona la identidad, nunca sus credenciales.
negociosRouter.post('/:id/profesionales', requireAuth('administrador'), (req: AuthedRequest, res) => {
  const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
  if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
  if (req.auth!.negocio_id !== req.params.id) {
    return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
  }
  const bodyParsed = altaProfesionalSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { email, password, nombre } = bodyParsed.data;

  const existente = db.prepare('SELECT id, rol FROM usuario WHERE email = ?').get(email) as
    | { id: string; rol: string }
    | undefined;

  if (existente && existente.rol !== 'profesional') {
    // El email ya está tomado por una identidad de otro rol (cliente/administrador) — un email
    // es una única identidad con un único rol, no se puede reusar como profesional.
    return res.status(409).json({ error: 'Email ya registrado' });
  }

  const ts = nowIso();

  if (existente) {
    const profesional = db
      .prepare('SELECT id FROM profesional WHERE usuario_id = ?')
      .get(existente.id) as { id: string } | undefined;
    if (!profesional) {
      // No debería poder pasar: todo usuario con rol='profesional' se crea junto con su fila
      // `profesional` en la misma transacción, en este mismo endpoint (ver rama de alta nueva).
      return res.status(500).json({ error: 'No se pudo resolver la identidad profesional existente' });
    }

    const membresia = db
      .prepare('SELECT activo FROM negocio_profesional WHERE negocio_id = ? AND profesional_id = ?')
      .get(req.params.id, profesional.id) as { activo: number } | undefined;

    if (membresia?.activo) {
      return res.status(409).json({ error: 'Este profesional ya pertenece a este negocio' });
    }
    if (membresia) {
      // Ya había estado vinculado a este negocio pero la membresía estaba pausada (activo=0)
      // — se reanuda sin perder el vínculo/historial (ver diseño de `activo` en modelo-datos.md).
      db.prepare(
        'UPDATE negocio_profesional SET activo = 1, modificado_en = ? WHERE negocio_id = ? AND profesional_id = ?'
      ).run(ts, req.params.id, profesional.id);
    } else {
      db.prepare(
        'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES (?, ?, 1, ?)'
      ).run(req.params.id, profesional.id, ts);
    }
    return res.status(201).json({ id: profesional.id });
  }

  const usuarioId = uuid();
  const profesionalId = uuid();
  withTransaction(() => {
    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(usuarioId, email, bcrypt.hashSync(password, 10), nombre, 'profesional', ts);
    db.prepare(
      'INSERT INTO profesional (id, usuario_id, creado_en) VALUES (?, ?, ?)'
    ).run(profesionalId, usuarioId, ts);
    db.prepare(
      'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES (?, ?, 1, ?)'
    ).run(req.params.id, profesionalId, ts);
  });
  res.status(201).json({ id: profesionalId });
});
