import { Router, Response } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { signToken, requireAuth, AuthedRequest, JwtClaims } from '../auth';
import { loginLimiter, registroLimiter } from '../middleware/rateLimit';
import { passwordSchema, uuidSchema, respuestaValidacionFallida } from '../dominio/validacion';

export const authRouter = Router();

const entrarANegocioSchema = z.object({ negocio_id: uuidSchema });

// HU-00a: administrador registra su negocio (multi-tenant, D1) y queda autenticado.
// Fix CRITICAL-1 (ver 07-seguridad/informe-seguridad.md), generalizado a N:M (ver
// modelo-datos.md §2ter): `negocio.admin_usuario_id` (columna 1:1 original) fue reemplazada por
// la tabla de asociación `negocio_administrador`. El usuario administrador se crea PRIMERO
// (igual que antes, la FK de la asociación referencia un `usuario` que ya existe), después el
// negocio (que ya no lleva ninguna referencia al admin en la propia fila) y por último la fila
// de `negocio_administrador` que vincula a ambos — las 3 inserciones en la misma transacción.
// Como esta alta siempre resulta en exactamente 1 negocio para este administrador recién
// creado, el token se firma directo con ese negocio_id (mismo comportamiento que antes de la
// generalización — no hace falta resolver membresías para un negocio que se acaba de crear).
authRouter.post('/registro-negocio', registroLimiter, (req, res) => {
  const { nombre_negocio, rubro, ubicacion, email, password, nombre_admin } = req.body;
  if (!nombre_negocio || !email || !password || !nombre_admin) {
    return res.status(400).json({ error: 'nombre_negocio, email, password y nombre_admin son requeridos' });
  }
  // MEDIUM-1 (ver 07-seguridad/informe-seguridad.md): longitud mínima de contraseña, aplicada
  // de forma consistente en los 3 puntos donde se crea una contraseña nueva.
  const passwordCheck = passwordSchema.safeParse(password);
  if (!passwordCheck.success) {
    return res.status(400).json({ error: passwordCheck.error.issues[0].message });
  }
  const existente = db.prepare('SELECT id FROM usuario WHERE email = ?').get(email);
  if (existente) return res.status(409).json({ error: 'Email ya registrado' });

  const negocioId = uuid();
  const usuarioId = uuid();
  const ts = nowIso();

  withTransaction(() => {
    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(usuarioId, email, bcrypt.hashSync(password, 10), nombre_admin, 'administrador', ts);

    db.prepare(
      'INSERT INTO negocio (id, nombre, rubro, ubicacion, creado_en) VALUES (?, ?, ?, ?, ?)'
    ).run(negocioId, nombre_negocio, rubro ?? null, ubicacion ?? null, ts);

    db.prepare(
      'INSERT INTO negocio_administrador (negocio_id, usuario_id, creado_en) VALUES (?, ?, ?)'
    ).run(negocioId, usuarioId, ts);
  });

  const token = signToken({ sub: usuarioId, rol: 'administrador', negocio_id: negocioId });
  res.status(201).json({ token, negocio_id: negocioId });
});

/**
 * Resuelve la respuesta de login para profesional/administrador bajo la generalización N:M
 * (ver modelo-datos.md §2ter, opción 3 "vista activa" — decisión ya tomada, no una alternativa
 * entre varias): el JWT sigue llevando UN solo `negocio_id` (nunca un array), para que toda la
 * autorización existente (`req.auth.negocio_id !== req.params.id` en negocios.ts/profesionales.ts)
 * siga funcionando sin cambios.
 *
 * - Exactamente 1 negocio con membresía activa → se firma directo con ese negocio_id, cero
 *   cambio de experiencia respecto de antes de esta generalización (caso común, un solo negocio).
 * - 0 o 2+ → el token sale SIN negocio_id (cualquier chequeo de autorización acotado a negocio
 *   deniega por default con el claim ausente, comportamiento correcto sin caso especial) y el
 *   body devuelve `negocios` con la lista completa para que el cliente arme el selector
 *   ("cambiar de vista", HU-27) y llame a `POST /auth/entrar-a-negocio`.
 */
function responderLoginConNegocios(
  res: Response,
  claimsBase: Omit<JwtClaims, 'negocio_id'>,
  negocios: { negocio_id: string; nombre: string }[]
) {
  if (negocios.length === 1) {
    const token = signToken({ ...claimsBase, negocio_id: negocios[0].negocio_id });
    return res.json({ token });
  }
  const token = signToken({ ...claimsBase });
  return res.json({
    token,
    negocios: negocios.map((n) => ({ negocio_id: n.negocio_id, nombre: n.nombre, rol: claimsBase.rol })),
  });
}

// Login genérico para cliente, profesional o administrador.
authRouter.post('/login', loginLimiter, (req, res) => {
  const { email, password } = req.body;
  const usuario = db.prepare('SELECT * FROM usuario WHERE email = ?').get(email) as any;
  if (!usuario || !bcrypt.compareSync(password ?? '', usuario.password_hash)) {
    return res.status(401).json({ error: 'Credenciales inválidas' });
  }

  if (usuario.rol === 'cliente') {
    const token = signToken({ sub: usuario.id, rol: 'cliente' });
    return res.json({ token });
  }

  if (usuario.rol === 'profesional') {
    const profesional = db
      .prepare('SELECT id FROM profesional WHERE usuario_id = ?')
      .get(usuario.id) as { id: string } | undefined;
    if (!profesional) {
      // No debería poder pasar: todo usuario con rol='profesional' se crea junto con su fila
      // `profesional` en la misma transacción (POST /negocios/:id/profesionales).
      return res.status(500).json({ error: 'No se pudo resolver la identidad profesional del usuario' });
    }
    // `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — la membresía
    // real vive en `negocio_profesional`, 0..N filas con `activo = 1`.
    const negocios = db
      .prepare(
        `SELECT np.negocio_id AS negocio_id, n.nombre AS nombre
         FROM negocio_profesional np
         JOIN negocio n ON n.id = np.negocio_id
         WHERE np.profesional_id = ? AND np.activo = 1 AND n.eliminado_en IS NULL`
      )
      .all(profesional.id) as { negocio_id: string; nombre: string }[];

    return responderLoginConNegocios(
      res,
      { sub: usuario.id, rol: 'profesional', profesional_id: profesional.id },
      negocios
    );
  }

  if (usuario.rol === 'administrador') {
    // Fix CRITICAL-1 (ver 07-seguridad/informe-seguridad.md), generalizado a N:M: la query
    // original de la corrección (`SELECT id FROM negocio WHERE admin_usuario_id = ?`, columna
    // 1:1) sigue resolviendo por una relación PERSISTIDA (no reabre CRITICAL-1, ver
    // modelo-datos.md §2ter), ahora contra `negocio_administrador`, que puede devolver 0..N filas.
    const negocios = db
      .prepare(
        `SELECT na.negocio_id AS negocio_id, n.nombre AS nombre
         FROM negocio_administrador na
         JOIN negocio n ON n.id = na.negocio_id
         WHERE na.usuario_id = ? AND n.eliminado_en IS NULL`
      )
      .all(usuario.id) as { negocio_id: string; nombre: string }[];

    return responderLoginConNegocios(res, { sub: usuario.id, rol: 'administrador' }, negocios);
  }

  res.status(500).json({ error: 'Rol de usuario inconsistente' });
});

// Endpoint nuevo (ver modelo-datos.md §2ter, opción 3 "vista activa" — HU-27 "cambiar de
// vista"): reemite el JWT con un `negocio_id` concreto una vez que el cliente ya sabe (por la
// lista `negocios` que devolvió `POST /auth/login`) a cuál de sus negocios quiere entrar.
// Requiere estar autenticado con CUALQUIER rol (`requireAuth()` sin roles — aplica tanto a
// profesional como a administrador; un cliente también puede llamarlo, pero nunca tiene
// membresía real así que cae al 403 por default, sin necesidad de un chequeo de rol aparte).
// Vuelve a validar la membresía activa contra la tabla real en el momento de reemitir — nunca
// confía en que el `negocio_id` pedido sea uno de los que el login devolvió hace rato (evita el
// mismo patrón de riesgo de CRITICAL-1: nunca confiar en un valor sin re-derivarlo).
authRouter.post('/entrar-a-negocio', requireAuth(), (req: AuthedRequest, res) => {
  const bodyParsed = entrarANegocioSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { negocio_id } = bodyParsed.data;
  const { sub, rol, profesional_id } = req.auth!;

  let pertenece = false;
  if (rol === 'administrador') {
    pertenece = !!db
      .prepare(
        `SELECT 1 FROM negocio_administrador na
         JOIN negocio n ON n.id = na.negocio_id
         WHERE na.negocio_id = ? AND na.usuario_id = ? AND n.eliminado_en IS NULL`
      )
      .get(negocio_id, sub);
  } else if (rol === 'profesional' && profesional_id) {
    pertenece = !!db
      .prepare(
        `SELECT 1 FROM negocio_profesional np
         JOIN negocio n ON n.id = np.negocio_id
         WHERE np.negocio_id = ? AND np.profesional_id = ? AND np.activo = 1 AND n.eliminado_en IS NULL`
      )
      .get(negocio_id, profesional_id);
  }

  if (!pertenece) {
    return res.status(403).json({ error: 'No pertenecés a ese negocio (o la membresía no está activa)' });
  }

  const token = signToken({
    sub,
    rol,
    negocio_id,
    ...(profesional_id ? { profesional_id } : {}),
  });
  res.json({ token, negocio_id });
});

// HU-01: registro de cliente.
authRouter.post('/registro-cliente', registroLimiter, (req, res) => {
  const { email, password, nombre } = req.body;
  if (!email || !password || !nombre) {
    return res.status(400).json({ error: 'email, password y nombre son requeridos' });
  }
  // MEDIUM-1 (ver 07-seguridad/informe-seguridad.md): longitud mínima de contraseña, aplicada
  // de forma consistente en los 3 puntos donde se crea una contraseña nueva.
  const passwordCheck = passwordSchema.safeParse(password);
  if (!passwordCheck.success) {
    return res.status(400).json({ error: passwordCheck.error.issues[0].message });
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
