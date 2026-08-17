import { Router, Response } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { v4 as uuid } from 'uuid';
import { OAuth2Client } from 'google-auth-library';
import { pool, nowIso, withTransaction } from '../db';
import { signToken, requireAuth, AuthedRequest, JwtClaims, Rol } from '../auth';
import { loginLimiter, registroLimiter, recuperacionPasswordLimiter } from '../middleware/rateLimit';
import { asyncHandler } from '../middleware/asyncHandler';
import { passwordSchema, uuidSchema, respuestaValidacionFallida } from '../dominio/validacion';
import { emailProvider } from '../integraciones/email';

export const authRouter = Router();

const entrarANegocioSchema = z.object({ negocio_id: uuidSchema });

/** Fila de `usuario` (columnas relevantes para login/vinculación de cuentas — ver
 *  migrations/001_init.sql). `password_hash`/`google_id` son nullable desde HU-35
 *  (02-backlog/backlog.md, "Resuelto (DBA, 2026-08-10)"): una cuenta tiene uno, el otro, o
 *  ambos — nunca ninguno (lo garantiza `ck_usuario_password_o_google` a nivel de base). */
interface UsuarioRow {
  id: string;
  email: string;
  password_hash: string | null;
  google_id: string | null;
  rol: Rol;
}

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
//
// Contexto RLS: todavía no hay JWT emitido en este punto — `usuarioId` es el UUID recién
// generado para la fila de `usuario` que se está por insertar (ver ContextoRls en src/db.ts).
// Confirmado contra la policy real (no asumido): `negocio_administrador_insert_propio` en
// migrations/001_init.sql exige `usuario_id = current_setting('app.usuario_id')::uuid` sobre la
// fila que se inserta — como esa fila es exactamente (negocioId, usuarioId), setear
// `app.usuario_id = usuarioId` es lo único que la satisface.
authRouter.post(
  '/registro-negocio',
  registroLimiter,
  asyncHandler(async (req, res) => {
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
    const existenteResult = await pool.query('SELECT id FROM usuario WHERE email = $1', [email]);
    if (existenteResult.rowCount) return res.status(409).json({ error: 'Email ya registrado' });

    const negocioId = uuid();
    const usuarioId = uuid();
    const ts = nowIso();

    await withTransaction(
      async (client) => {
        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [usuarioId, email, bcrypt.hashSync(password, 10), nombre_admin, 'administrador', ts]
        );

        await client.query(
          'INSERT INTO negocio (id, nombre, rubro, ubicacion, creado_en) VALUES ($1, $2, $3, $4, $5)',
          [negocioId, nombre_negocio, rubro ?? null, ubicacion ?? null, ts]
        );

        await client.query(
          'INSERT INTO negocio_administrador (negocio_id, usuario_id, creado_en) VALUES ($1, $2, $3)',
          [negocioId, usuarioId, ts]
        );
      },
      { usuarioId }
    );

    const token = signToken({ sub: usuarioId, rol: 'administrador', negocio_id: negocioId });
    res.status(201).json({ token, negocio_id: negocioId });
  })
);

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

/**
 * A partir de una fila `usuario` ya autenticada (por contraseña en `/login`, o por Google ya
 * vinculado en `/google` — ver HU-35, 02-backlog/backlog.md: "Google pasa a ser un método de
 * acceso adicional... el resto del sistema no debe distinguir cómo se autenticó alguien"),
 * arma y responde el JWT con el mismo shape/claims que ya emitía `POST /auth/login` antes de
 * esta historia: branch por rol, resolución de negocio(s) activos para profesional/
 * administrador (ver `responderLoginConNegocios` arriba). Extraída a función propia para que
 * `POST /auth/login` y `POST /auth/google` (rama de login recurrente ya vinculado) compartan
 * exactamente la misma lógica en vez de duplicarla.
 */
async function emitirLoginParaUsuario(res: Response, usuario: UsuarioRow) {
  if (usuario.rol === 'cliente') {
    const token = signToken({ sub: usuario.id, rol: 'cliente' });
    return res.json({ token });
  }

  if (usuario.rol === 'profesional') {
    // `profesional` tiene SELECT público (ver migrations/001_init.sql) — no hace falta
    // contexto RLS para esta lectura.
    const profesionalResult = await pool.query('SELECT id FROM profesional WHERE usuario_id = $1', [
      usuario.id,
    ]);
    const profesional = profesionalResult.rows[0] as { id: string } | undefined;
    if (!profesional) {
      // No debería poder pasar: todo usuario con rol='profesional' se crea junto con su fila
      // `profesional` en la misma transacción (POST /negocios/:id/profesionales).
      return res.status(500).json({ error: 'No se pudo resolver la identidad profesional del usuario' });
    }
    // `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — la membresía
    // real vive en `negocio_profesional`, 0..N filas con `activo = true`. Esa tabla también
    // tiene SELECT público, pero igual corremos esta lectura con contexto (usuarioId) por
    // consistencia con el resto de los handlers autenticados/semi-autenticados.
    const negocios = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT np.negocio_id AS negocio_id, n.nombre AS nombre
           FROM negocio_profesional np
           JOIN negocio n ON n.id = np.negocio_id
           WHERE np.profesional_id = $1 AND np.activo = true AND n.eliminado_en IS NULL`,
          [profesional.id]
        );
        return result.rows as { negocio_id: string; nombre: string }[];
      },
      { usuarioId: usuario.id }
    );

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
    //
    // Contexto RLS OBLIGATORIO acá (a diferencia de la rama `profesional` de arriba):
    // `negocio_administrador` NO tiene SELECT público (ver migrations/001_init.sql,
    // `negocio_administrador_select_propio` exige `usuario_id = current_setting('app.usuario_id')`)
    // — sin `usuarioId: usuario.id`, esta query devolvería 0 filas SIEMPRE, sin error, y todo
    // administrador vería su login como si no perteneciera a ningún negocio.
    const negocios = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT na.negocio_id AS negocio_id, n.nombre AS nombre
           FROM negocio_administrador na
           JOIN negocio n ON n.id = na.negocio_id
           WHERE na.usuario_id = $1 AND n.eliminado_en IS NULL`,
          [usuario.id]
        );
        return result.rows as { negocio_id: string; nombre: string }[];
      },
      { usuarioId: usuario.id }
    );

    return responderLoginConNegocios(res, { sub: usuario.id, rol: 'administrador' }, negocios);
  }

  return res.status(500).json({ error: 'Rol de usuario inconsistente' });
}

// HU-35 (02-backlog/backlog.md): login/registro con Google, además de email+contraseña. El
// cliente se construye UNA sola vez, sin `clientId` fijo en el constructor — `audience` se
// resuelve por request dentro de `verificarIdTokenGoogle` (abajo), recién cuando llega un
// request real. A propósito NO se lee/valida `process.env.GOOGLE_CLIENT_ID` acá arriba, a nivel
// de módulo: a diferencia de `JWT_SECRET` (src/auth.ts, HIGH-3 — ahí SÍ falta debe frenar el
// arranque del proceso), que Google no esté configurado es una opción válida en cualquier
// entorno que todavía no ofrezca este método (no hay credenciales reales todavía — ver
// backlog.md HU-35, pregunta abierta de DevOps sobre alta de credenciales OAuth). Mismo criterio
// de opt-in explícito que `ENABLE_DEV_ROUTES` en src/app.ts: nunca tirar abajo la app entera por
// esto — responder 503 recién al recibir un request a un endpoint que lo necesita.
const googleOAuthClient = new OAuth2Client();

type ResultadoGoogle =
  | { ok: true; googleId: string; email: string; emailVerified: boolean; nombre: string }
  | { ok: false; status: 503; error: string }
  | { ok: false; status: 401; error: string };

/**
 * Verifica un ID token de Google (firma, emisor y audiencia == `GOOGLE_CLIENT_ID`, vía
 * google-auth-library). Único punto que decide "Google no está configurado en este entorno"
 * (503) — usado tanto por `POST /auth/google` como por el paso de vinculación dentro de
 * `POST /auth/login` (ver más abajo), para no duplicar ese chequeo en 2 lugares.
 */
async function verificarIdTokenGoogle(idToken: string): Promise<ResultadoGoogle> {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  if (!clientId) {
    return { ok: false, status: 503, error: 'Login con Google no está configurado en este entorno' };
  }
  try {
    const ticket = await googleOAuthClient.verifyIdToken({ idToken, audience: clientId });
    const payload = ticket.getPayload();
    if (!payload?.email) {
      return { ok: false, status: 401, error: 'Token de Google inválido' };
    }
    return {
      ok: true,
      googleId: payload.sub,
      email: payload.email,
      // `email_verified` es opcional en el payload (google-auth-library) — tratar "ausente"
      // igual que "false" (fail-closed: regla 1 de Security/HU-35, nunca dar de alta sin
      // confirmación explícita de Google).
      emailVerified: payload.email_verified === true,
      nombre: payload.name ?? payload.email,
    };
  } catch {
    // Firma inválida, token expirado, `aud` que no coincide con GOOGLE_CLIENT_ID, etc. —
    // google-auth-library no expone un tipo de error propio explotable acá; todos se tratan
    // igual, como token inválido.
    return { ok: false, status: 401, error: 'Token de Google inválido' };
  }
}

function responderErrorGoogle(res: Response, resultado: { ok: false; status: 503 | 401; error: string }) {
  return res.status(resultado.status).json({ error: resultado.error });
}

// Reutilizado por el body completo de POST /auth/google (id_token obligatorio) y, envuelto de la
// misma forma, por el parámetro opcional del mismo nombre en POST /auth/login (ver HU-35 más
// abajo) — una sola definición de "qué es un id_token válido" para los 2 usos.
const googleBodySchema = z.object({ id_token: z.string().min(1, 'id_token es requerido') });

// Login genérico para cliente, profesional o administrador.
authRouter.post(
  '/login',
  loginLimiter,
  asyncHandler(async (req, res) => {
    const { email, password, id_token } = req.body;
    const usuarioResult = await pool.query('SELECT * FROM usuario WHERE email = $1', [email]);
    const usuario = usuarioResult.rows[0] as UsuarioRow | undefined;
    if (!usuario) {
      return res.status(401).json({ error: 'Credenciales inválidas' });
    }
    // Fix (HU-35, 02-backlog/backlog.md — ver también el comentario de DBA en
    // migrations/001_init.sql sobre esta misma corrección): `password_hash` ahora puede ser
    // NULL (cuenta dada de alta únicamente vía Google, sin contraseña propia). Chequeo
    // explícito ANTES de llamar a `bcrypt.compareSync`, que no maneja `null` de forma segura
    // como 2do argumento — sin esto, cualquier intento de login por contraseña contra una
    // cuenta 100% Google rompería acá en vez de responder 401 como cualquier otra credencial
    // inválida.
    if (!usuario.password_hash) {
      return res.status(401).json({ error: 'Credenciales inválidas' });
    }
    if (!bcrypt.compareSync(password ?? '', usuario.password_hash)) {
      return res.status(401).json({ error: 'Credenciales inválidas' });
    }

    // HU-35 (backlog.md, regla de Security 2026-08-10, puntos 2 y 4): si el body además manda
    // `id_token` de Google, es el paso de confirmación que exige la vinculación de cuentas —
    // "ya existe una cuenta con este email creada por contraseña, exigir que confirme esa
    // contraseña en el mismo flujo antes de persistir la vinculación". La contraseña ya se
    // validó arriba (mismo mecanismo, mismo `loginLimiter`/HIGH-1 — no se abre un endpoint
    // nuevo de fuerza bruta, tal cual pide el punto 4); acá solo falta verificar el id_token y
    // persistir `google_id` si todavía no estaba vinculado.
    if (id_token) {
      const idTokenCheck = googleBodySchema.safeParse({ id_token });
      if (!idTokenCheck.success) return respuestaValidacionFallida(res, idTokenCheck.error);

      const resultadoGoogle = await verificarIdTokenGoogle(idTokenCheck.data.id_token);
      if (!resultadoGoogle.ok) return responderErrorGoogle(res, resultadoGoogle);

      // Nunca confiar en que el id_token corresponde a esta cuenta solo porque vino en el mismo
      // request (mismo criterio que POST /auth/entrar-a-negocio: no confiar un valor sin
      // re-derivarlo) — el email del propio token YA verificado por Google es lo único que se
      // acepta como prueba de que corresponde a esta cuenta.
      if (resultadoGoogle.email !== usuario.email) {
        return res.status(409).json({ error: 'La cuenta de Google no corresponde al email de esta cuenta' });
      }

      // Si ya estaba vinculada (a este mismo google_id) no hay nada que persistir. Relincular a
      // un google_id DISTINTO del ya vinculado queda fuera de alcance de HU-35 (no lo pide el
      // backlog) y a propósito no se sobreescribe acá.
      if (!usuario.google_id) {
        try {
          await pool.query('UPDATE usuario SET google_id = $1, modificado_en = $2 WHERE id = $3', [
            resultadoGoogle.googleId,
            nowIso(),
            usuario.id,
          ]);
          usuario.google_id = resultadoGoogle.googleId;
        } catch (err: any) {
          // 23505 = unique_violation sobre `usuario_google_id_key` (mismo patrón ya usado para
          // la carrera de reserva de turnos, ver turnos.ts) — esta cuenta de Google ya está
          // vinculada a otro `usuario_id`.
          if (err?.code === '23505') {
            return res.status(409).json({ error: 'Esa cuenta de Google ya está vinculada a otro usuario' });
          }
          throw err;
        }
      }
    }

    return emitirLoginParaUsuario(res, usuario);
  })
);

// HU-35 (02-backlog/backlog.md): login/registro con la cuenta de Google del cliente o
// profesional, ALTERNATIVO al flujo de email+contraseña de arriba (que sigue funcionando
// exactamente igual, sin cambios, para quien no usa Google — ver "Es una opción ADICIONAL, no
// un reemplazo" en esa historia). Implementa tal cual las reglas que dejó cerradas Security
// (backlog.md HU-35, "Resuelto (Security, 2026-08-10)"; razonamiento completo en
// 07-seguridad/informe-seguridad.md, Adenda 2026-08-10, parte A):
//   1. Sin cuenta previa con ese email -> alta nueva SOLO si el ID token trae
//      `email_verified: true`; si viene `false`, se rechaza el alta.
//   2. Ya existe una cuenta previa por contraseña con ese email -> NUNCA vincular ni loguear
//      automático, sin importar `email_verified` (riesgo de account takeover vía email
//      reciclado/cuenta Google comprometida/Workspace — ver la adenda citada). Acá se responde
//      con 409 + `requiere_confirmacion_password`; el cliente confirma reenviando ese mismo
//      `id_token` a POST /auth/login junto con la contraseña existente (ver el comentario en ese
//      endpoint) — reutiliza su mismo rate limiting (HIGH-1) en vez de abrir un endpoint nuevo
//      de fuerza bruta (punto 4 de la regla de Security).
//   3. Una vez vinculada sigue existiendo una única fila `usuario` — Google pasa a ser un
//      método de acceso adicional de ese usuario_id, nunca un usuario nuevo.
authRouter.post(
  '/google',
  loginLimiter,
  asyncHandler(async (req, res) => {
    const bodyParsed = googleBodySchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);

    const resultado = await verificarIdTokenGoogle(bodyParsed.data.id_token);
    if (!resultado.ok) return responderErrorGoogle(res, resultado);
    const { googleId, email, emailVerified, nombre } = resultado;

    // Buscar primero por `google_id` (login recurrente, cuenta ya vinculada) — ver
    // recomendación de DBA en migrations/001_init.sql. Nunca se busca primero por email: eso es
    // exactamente el atajo que la regla 2 de arriba prohíbe.
    const porGoogleIdResult = await pool.query('SELECT * FROM usuario WHERE google_id = $1', [googleId]);
    const usuarioVinculado = porGoogleIdResult.rows[0] as UsuarioRow | undefined;
    if (usuarioVinculado) {
      return emitirLoginParaUsuario(res, usuarioVinculado);
    }

    const porEmailResult = await pool.query('SELECT * FROM usuario WHERE email = $1', [email]);
    const existentePorEmail = porEmailResult.rows[0] as UsuarioRow | undefined;

    if (!existentePorEmail) {
      // Regla 1: sin cuenta previa con este email, alta nueva solo si Google confirma el email.
      if (!emailVerified) {
        return res.status(403).json({
          error:
            'Tu cuenta de Google no tiene el email verificado — no se puede crear una cuenta con este método. Probá con otro método de registro.',
        });
      }
      // Alta nueva == mismo rol que POST /auth/registro-cliente (única alta pública sin admin
      // de por medio — profesionales/administradores no se autoregistran vía Google).
      const usuarioId = uuid();
      await pool.query(
        'INSERT INTO usuario (id, email, password_hash, google_id, nombre, rol, creado_en) VALUES ($1, $2, NULL, $3, $4, $5, $6)',
        [usuarioId, email, googleId, nombre, 'cliente', nowIso()]
      );
      const token = signToken({ sub: usuarioId, rol: 'cliente' });
      return res.status(201).json({ token });
    }

    // Regla 2: ya existe una cuenta con este email que no llegó acá por `google_id` (si ya
    // tuviera este mismo google_id vinculado, ya se habría resuelto arriba) -> PROHIBIDA la
    // vinculación/login automático, sin importar `email_verified`.
    return res.status(409).json({
      error: 'Ya existe una cuenta con este email — iniciá sesión con tu contraseña para vincular Google',
      requiere_confirmacion_password: true,
    });
  })
);

// Endpoint nuevo (ver modelo-datos.md §2ter, opción 3 "vista activa" — HU-27 "cambiar de
// vista"): reemite el JWT con un `negocio_id` concreto una vez que el cliente ya sabe (por la
// lista `negocios` que devolvió `POST /auth/login`) a cuál de sus negocios quiere entrar.
// Requiere estar autenticado con CUALQUIER rol (`requireAuth()` sin roles — aplica tanto a
// profesional como a administrador; un cliente también puede llamarlo, pero nunca tiene
// membresía real así que cae al 403 por default, sin necesidad de un chequeo de rol aparte).
// Vuelve a validar la membresía activa contra la tabla real en el momento de reemitir — nunca
// confía en que el `negocio_id` pedido sea uno de los que el login devolvió hace rato (evita el
// mismo patrón de riesgo de CRITICAL-1: nunca confiar en un valor sin re-derivarlo).
authRouter.post(
  '/entrar-a-negocio',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res) => {
    const bodyParsed = entrarANegocioSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { negocio_id } = bodyParsed.data;
    const { sub, rol, profesional_id } = req.auth!;

    const pertenece = await withTransaction(
      async (client) => {
        if (rol === 'administrador') {
          const result = await client.query(
            `SELECT 1 FROM negocio_administrador na
             JOIN negocio n ON n.id = na.negocio_id
             WHERE na.negocio_id = $1 AND na.usuario_id = $2 AND n.eliminado_en IS NULL`,
            [negocio_id, sub]
          );
          return !!result.rowCount;
        }
        if (rol === 'profesional' && profesional_id) {
          const result = await client.query(
            `SELECT 1 FROM negocio_profesional np
             JOIN negocio n ON n.id = np.negocio_id
             WHERE np.negocio_id = $1 AND np.profesional_id = $2 AND np.activo = true AND n.eliminado_en IS NULL`,
            [negocio_id, profesional_id]
          );
          return !!result.rowCount;
        }
        return false;
      },
      { usuarioId: sub, negocioId: req.auth!.negocio_id }
    );

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
  })
);

// HU-01: registro de cliente. `usuario` no tiene RLS (ver migrations/001_init.sql) — no hace
// falta pasar por una transacción con contexto, `pool.query` alcanza para las 2 sentencias
// sueltas (mismo shape que la versión anterior, que tampoco las agrupaba en una transacción).
authRouter.post(
  '/registro-cliente',
  registroLimiter,
  asyncHandler(async (req, res) => {
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
    const existenteResult = await pool.query('SELECT id FROM usuario WHERE email = $1', [email]);
    if (existenteResult.rowCount) return res.status(409).json({ error: 'Email ya registrado' });

    const usuarioId = uuid();
    await pool.query(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
      [usuarioId, email, bcrypt.hashSync(password, 10), nombre, 'cliente', nowIso()]
    );

    const token = signToken({ sub: usuarioId, rol: 'cliente' });
    res.status(201).json({ token });
  })
);

// ============================================================================
// HU-37 (02-backlog/backlog.md, extiende E4/HU-01/HU-35) — recuperación de contraseña.
// Implementa casi al pie de la letra la "Recomendación para Backend" que dejó DBA en
// 03-arquitectura/modelo-datos.md §2decies/§5octies y en el bloque "Recuperación de
// contraseña — token de un solo uso" de migrations/001_init.sql — ver esos documentos para el
// razonamiento completo (por qué tabla nueva, por qué SHA-256 y no bcrypt para `token_hash`,
// por qué esta tabla NO tiene RLS, por qué invalidar tokens anteriores antes de insertar uno
// nuevo). Contrato de alcance ya cerrado por Product Manager/DBA/Director General IA, no se
// reabre acá.
// ============================================================================

// Duración recomendada por Product Manager (HU-37): 30 minutos desde que se genera el token.
// Configurable a propósito (mismo criterio que EXPIRACION_PAGO_MIN/VENTANA_CANCELACION_MIN en
// turnos.ts) — únicamente para poder simular "token vencido" en pruebas automatizadas sin
// esperar 30 minutos reales; el default de la aplicación es siempre 30.
const RECUPERACION_PASSWORD_TTL_MIN = Number(process.env.RECUPERACION_PASSWORD_TTL_MIN ?? 30);

// 256 bits de entropía — alta a propósito (ver modelo-datos.md §2decies, columna `token_hash`):
// es lo que permite usar un hash rápido no adaptativo en vez de bcrypt sin abrir una superficie
// de fuerza bruta viable.
function generarTokenRecuperacion(): string {
  return crypto.randomBytes(32).toString('hex');
}

// SHA-256, NO bcrypt — recomendación explícita de DBA (ver modelo-datos.md §2decies): el token
// ya es de alta entropía (generado por el servidor, nunca elegido por una persona), así que no
// necesita el costo computacional adaptativo de bcrypt para resistir fuerza bruta; usar bcrypt
// acá solo sumaría (a) CPU innecesaria en cada intento de canje — spamear el endpoint de canje
// con hashes inválidos forzaría ese costo adaptativo en cada intento, una superficie de DoS
// barata que un hash rápido no abre — y (b) el límite de 72 bytes de entrada de bcrypt, sin
// ningún beneficio real a cambio.
function hashTokenRecuperacion(tokenPlano: string): string {
  return crypto.createHash('sha256').update(tokenPlano).digest('hex');
}

// Mitigación de enumeración de usuarios (criterio explícito de HU-37, pendiente de validación de
// Security): SIEMPRE el mismo mensaje genérico, con el mismo código 200, exista o no la cuenta —
// y también si la cuenta existe pero es 100% Google (`password_hash IS NULL`, HU-35): no tiene
// contraseña que restablecer, así que tampoco genera token, sin delatar esa diferencia acá.
const MENSAJE_GENERICO_RECUPERAR_PASSWORD = {
  ok: true,
  mensaje: 'Si el email está registrado, vas a recibir instrucciones para recuperar tu contraseña.',
};

// HU-37: paso 1 del flujo (backlog.md — "El usuario ingresa su email en una pantalla nueva de
// Mobile"). Body: `{ email }`.
authRouter.post(
  '/recuperar-password',
  recuperacionPasswordLimiter,
  asyncHandler(async (req, res) => {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ error: 'email es requerido' });
    }

    // `usuario` no tiene RLS (mismo patrón ya usado en /registro-cliente y /login sobre esta
    // misma tabla) — sin transacción ni contexto para esta lectura.
    const usuarioResult = await pool.query('SELECT id, password_hash FROM usuario WHERE email = $1', [
      email,
    ]);
    const usuario = usuarioResult.rows[0] as { id: string; password_hash: string | null } | undefined;

    // Fuera de alcance de esta historia (backlog.md, "Fuera de alcance... explícito"): una
    // cuenta solo-Google (`password_hash IS NULL`, `ck_usuario_password_o_google`) no tiene
    // contraseña que restablecer — no genera token real, y no delata esa diferencia (se cae
    // directo a la respuesta genérica de abajo, igual que "no existe la cuenta").
    if (usuario?.password_hash) {
      const tokenPlano = generarTokenRecuperacion();
      const tokenHash = hashTokenRecuperacion(tokenPlano);
      const expiraEn = new Date(Date.now() + RECUPERACION_PASSWORD_TTL_MIN * 60_000).toISOString();

      // Sin contexto RLS — esta tabla deliberadamente no lleva RLS (modelo-datos.md §5octies):
      // un pedido de recuperación es anónimo por email, no hay ningún actor autenticado que
      // setear como `app.usuario_id`. `withTransaction` acá solo aporta atomicidad BEGIN/COMMIT
      // entre las 2 sentencias, no contexto de policies.
      await withTransaction(async (client) => {
        // Invalidar cualquier token pendiente ANTES de insertar el nuevo — en ESE orden, por el
        // índice único parcial `uq_token_recuperacion_password_usuario_pendiente` (a lo sumo 1
        // token pendiente por usuario, ver modelo-datos.md §2decies "varias recuperaciones
        // seguidas"). Invertir el orden haría fallar el INSERT con 23505.
        await client.query(
          'UPDATE token_recuperacion_password SET usado_en = now() WHERE usuario_id = $1 AND usado_en IS NULL',
          [usuario.id]
        );
        await client.query(
          'INSERT INTO token_recuperacion_password (usuario_id, token_hash, expira_en) VALUES ($1, $2, $3)',
          [usuario.id, tokenHash, expiraEn]
        );
      });

      await emailProvider.enviarRecuperacionPassword(email, tokenPlano);

      // HU-37 (backlog.md) / modelo-datos.md §2decies: mientras el provider sea el Mock (no hay
      // proveedor de email real todavía), el token debe quedar visible para poder probar el
      // flujo de punta a punta — acá vía la propia respuesta del endpoint, bajo el
      // mismo gateo de ENABLE_DEV_ROUTES que ya usa src/routes/dev.ts (además del log de
      // MockEmailProvider, ver src/integraciones/email.ts). Un campo con nombre inequívoco
      // (`token_dev`), NUNCA presente si ENABLE_DEV_ROUTES no está activo explícitamente — en
      // Render queda en "false" (ver render.yaml), así que esto nunca sale así en producción.
      if (process.env.ENABLE_DEV_ROUTES === 'true') {
        return res.json({ ...MENSAJE_GENERICO_RECUPERAR_PASSWORD, token_dev: tokenPlano });
      }
    }

    return res.json(MENSAJE_GENERICO_RECUPERAR_PASSWORD);
  })
);

const resetPasswordSchema = z.object({
  token: z.string().min(1, 'token es requerido'),
  password: passwordSchema,
});

/**
 * Señal interna para forzar el ROLLBACK de la transacción de canje cuando el segundo UPDATE (ver
 * más abajo) pierde la carrera de un doble-submit — a diferencia de "token no encontrado" (que
 * no llega a mutar nada y se resuelve con un `return` normal dentro de la transacción), acá YA
 * corrió el UPDATE de `usuario.password_hash` en la misma transacción: hace falta LANZAR (no
 * `return`) para que `withTransaction` haga ROLLBACK en vez de COMMIT y ese cambio nunca se
 * persista. Mismo espíritu que el manejo de 23505 de `uq_turno_slot_activo` en turnos.ts, aunque
 * acá el motor no lanza ninguna excepción propia — el UPDATE simplemente no matchea ninguna fila.
 */
class CanjeTokenEnCarreraError extends Error {}

// HU-37: paso 2 del flujo (backlog.md — "el usuario recibe un token por email y lo copia/pega
// junto con la nueva contraseña en una segunda pantalla de la app"). Body: `{ token, password }`
// — el token es la ÚNICA prueba de identidad acá, nunca se recibe `usuario_id` ni email.
authRouter.post(
  '/reset-password',
  recuperacionPasswordLimiter,
  asyncHandler(async (req, res) => {
    const bodyParsed = resetPasswordSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { token, password } = bodyParsed.data;

    const tokenHash = hashTokenRecuperacion(token);

    let resultado: { valido: boolean };
    try {
      resultado = await withTransaction(async (client) => {
        const tokenResult = await client.query(
          `SELECT id, usuario_id FROM token_recuperacion_password
           WHERE token_hash = $1 AND usado_en IS NULL AND expira_en > now()`,
          [tokenHash]
        );
        const fila = tokenResult.rows[0] as { id: string; usuario_id: string } | undefined;
        if (!fila) {
          return { valido: false };
        }

        await client.query('UPDATE usuario SET password_hash = $1 WHERE id = $2', [
          bcrypt.hashSync(password, 10),
          fila.usuario_id,
        ]);

        // El `AND usado_en IS NULL` extra (ya filtrado también en el SELECT de arriba) cierra la
        // carrera de un doble submit concurrente con el mismo token: si otro request canjeó
        // este mismo token en el instante entre el SELECT y este UPDATE, acá `rowCount` da 0.
        const canjeResult = await client.query(
          'UPDATE token_recuperacion_password SET usado_en = now() WHERE id = $1 AND usado_en IS NULL',
          [fila.id]
        );
        if (!canjeResult.rowCount) {
          throw new CanjeTokenEnCarreraError();
        }

        return { valido: true };
      });
    } catch (err) {
      if (err instanceof CanjeTokenEnCarreraError) {
        resultado = { valido: false };
      } else {
        throw err;
      }
    }

    if (!resultado.valido) {
      // Mismo mensaje para "el token nunca existió", "ya venció" y "ya fue usado" (incluida la
      // carrera de arriba) — sin distinguir cuál de las razones (criterio explícito de HU-37: no
      // darle a un atacante información sobre si el token existió alguna vez).
      return res.status(400).json({ error: 'Token inválido o vencido' });
    }
    return res.json({ ok: true, mensaje: 'Contraseña actualizada correctamente.' });
  })
);
