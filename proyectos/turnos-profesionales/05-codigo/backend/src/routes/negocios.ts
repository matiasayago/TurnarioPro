import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
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

// HU-00b: cliente descubre negocios (RN9 — no se filtra por negocio_id porque es cross-tenant
// por diseño). Público — pool.query directo, sin transacción ni contexto RLS.
negociosRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const result = await pool.query(
      'SELECT id, nombre, rubro, ubicacion, es_rubro_salud FROM negocio WHERE eliminado_en IS NULL'
    );
    res.json(result.rows);
  })
);

// HU-07: servicios de un negocio puntual (público, para que el cliente elija).
negociosRouter.get(
  '/:id/servicios',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      'SELECT id, nombre, duracion_min, precio_referencia FROM servicio WHERE negocio_id = $1 AND eliminado_en IS NULL',
      [req.params.id]
    );
    res.json(result.rows);
  })
);

// HU-08: profesionales del negocio que ofrecen un servicio puntual (público, para que el
// cliente elija profesional una vez que ya eligió el servicio — CU4 paso 2).
// `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — el JOIN pasa por
// `negocio_profesional`, que resuelve la membresía activa del profesional en ESTE negocio en
// particular (un mismo profesional puede pertenecer a otros negocios además de este).
negociosRouter.get(
  '/:id/servicios/:servicioId/profesionales',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT p.id, u.nombre
       FROM profesional p
       JOIN usuario u ON u.id = p.usuario_id
       JOIN profesional_servicio ps ON ps.profesional_id = p.id
       JOIN negocio_profesional np ON np.profesional_id = p.id AND np.negocio_id = $1 AND np.activo = true
       WHERE ps.servicio_id = $2 AND p.eliminado_en IS NULL`,
      [req.params.id, req.params.servicioId]
    );
    res.json(result.rows);
  })
);

// HU-03: administrador carga un servicio de SU negocio (RN9 aplicado vía claim del JWT, no del parámetro).
negociosRouter.post(
  '/:id/servicios',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
    }
    const bodyParsed = altaServicioSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nombre, duracion_min, precio_referencia } = bodyParsed.data;
    const id = uuid();

    await withTransaction(
      async (client) => {
        await client.query(
          'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [id, req.params.id, nombre, duracion_min, precio_referencia ?? null, nowIso()]
        );
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    res.status(201).json({ id });
  })
);

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
//
// Toda la lógica (lecturas + escrituras condicionales) corre en UNA sola transacción con
// contexto RLS fijo (usuarioId=admin, negocioId=req.params.id) — antes (versión a medio migrar)
// esto llamaba a `withTransaction(fn)` con un `fn` síncrono que ni siquiera recibía el `client`
// (no compilaba y, aunque hubiera compilado, nunca habría fijado el contexto RLS para los
// UPDATE/INSERT de `negocio_profesional`, que si tiene RLS). El resultado de la transacción es
// un objeto discriminado por `tipo` que el código de después usa para elegir status/body HTTP —
// necesario porque ya no se puede hacer `return res.status(...)` desde adentro del closure.
negociosRouter.post(
  '/:id/profesionales',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
    }
    const bodyParsed = altaProfesionalSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { email, password, nombre } = bodyParsed.data;

    const ts = nowIso();
    const usuarioIdNuevo = uuid();
    const profesionalIdNuevo = uuid();

    const resultado = await withTransaction(
      async (client) => {
        const existenteResult = await client.query('SELECT id, rol FROM usuario WHERE email = $1', [email]);
        const existente = existenteResult.rows[0] as { id: string; rol: string } | undefined;

        if (existente && existente.rol !== 'profesional') {
          // El email ya está tomado por una identidad de otro rol (cliente/administrador) — un
          // email es una única identidad con un único rol, no se puede reusar como profesional.
          return { tipo: 'email_tomado' as const };
        }

        if (existente) {
          const profesionalResult = await client.query('SELECT id FROM profesional WHERE usuario_id = $1', [
            existente.id,
          ]);
          const profesional = profesionalResult.rows[0] as { id: string } | undefined;
          if (!profesional) {
            // No debería poder pasar: todo usuario con rol='profesional' se crea junto con su
            // fila `profesional` en la misma transacción, en este mismo endpoint (ver rama de
            // alta nueva más abajo).
            return { tipo: 'inconsistencia' as const };
          }

          const membresiaResult = await client.query(
            'SELECT activo FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2',
            [req.params.id, profesional.id]
          );
          const membresia = membresiaResult.rows[0] as { activo: boolean } | undefined;

          if (membresia?.activo) {
            return { tipo: 'ya_activo' as const };
          }
          if (membresia) {
            // Ya había estado vinculado a este negocio pero la membresía estaba pausada
            // (activo=false) — se reanuda sin perder el vínculo/historial (ver diseño de
            // `activo` en modelo-datos.md).
            await client.query(
              'UPDATE negocio_profesional SET activo = true, modificado_en = $1 WHERE negocio_id = $2 AND profesional_id = $3',
              [ts, req.params.id, profesional.id]
            );
          } else {
            await client.query(
              'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES ($1, $2, true, $3)',
              [req.params.id, profesional.id, ts]
            );
          }
          return { tipo: 'ok' as const, id: profesional.id };
        }

        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [usuarioIdNuevo, email, bcrypt.hashSync(password, 10), nombre, 'profesional', ts]
        );
        await client.query('INSERT INTO profesional (id, usuario_id, creado_en) VALUES ($1, $2, $3)', [
          profesionalIdNuevo,
          usuarioIdNuevo,
          ts,
        ]);
        await client.query(
          'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES ($1, $2, true, $3)',
          [req.params.id, profesionalIdNuevo, ts]
        );
        return { tipo: 'ok' as const, id: profesionalIdNuevo };
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    switch (resultado.tipo) {
      case 'email_tomado':
        return res.status(409).json({ error: 'Email ya registrado' });
      case 'inconsistencia':
        return res.status(500).json({ error: 'No se pudo resolver la identidad profesional existente' });
      case 'ya_activo':
        return res.status(409).json({ error: 'Este profesional ya pertenece a este negocio' });
      case 'ok':
        return res.status(201).json({ id: resultado.id });
    }
  })
);
