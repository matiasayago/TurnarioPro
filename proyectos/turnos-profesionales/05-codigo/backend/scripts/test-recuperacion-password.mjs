// Verifica HU-37 (02-backlog/backlog.md, extiende E4) de punta a punta contra un servidor real:
// recuperación de contraseña con token de un solo uso (POST /auth/recuperar-password +
// POST /auth/reset-password, src/routes/auth.ts). Requiere el servidor corriendo.
//
// A diferencia del resto de los scripts de esta carpeta, este SÍ abre una conexión propia a
// Postgres (paquete `pg`, ya dependencia de producción del backend — sin instalar nada nuevo)
// por 2 motivos puntuales, no reemplazables por HTTP en este entorno:
//   1. El caso "cuenta dada de alta 100% por Google" (`password_hash IS NULL`, HU-35) no se
//      puede armar por HTTP acá: `POST /auth/google` exige un ID token real verificado contra
//      `GOOGLE_CLIENT_ID`, y este entorno no tiene credenciales reales de Google (ver
//      README.md, sección "Login con Google"). Se inserta la fila directo, respetando
//      `ck_usuario_password_o_google` (password_hash NULL + google_id no-NULL).
//   2. Confirmar a nivel de fila (no solo por el código HTTP) que "varias recuperaciones
//      seguidas" invalida los tokens pendientes anteriores (modelo-datos.md §2decies) y que la
//      cuenta solo-Google nunca llega a tener ninguna fila en `token_recuperacion_password`.
//
// Variables de entorno:
//   BASE_URL                       default http://localhost:3000
//   DATABASE_URL                   OBLIGATORIA — misma base que usa el servidor bajo prueba
//   DATABASE_SSL                   poné "true" si esa base exige TLS (Render u otro Postgres
//                                  gestionado) — mismo criterio que resolveSsl() en src/db.ts;
//                                  sin esto, la conexión propia de este script (ver arriba)
//                                  falla con ECONNRESET contra ese tipo de host.
//   RECUPERACION_PASSWORD_TTL_MIN  opcional; si el servidor corre con un valor bajo (ej. 0.1 =
//                                  6s, ver .env.example) Y este script se corre con el MISMO
//                                  valor, se ejercita también el caso "token vencido" (si no,
//                                  se salta ese caso puntual con un aviso — esperar 30 minutos
//                                  reales no es práctico para un script de verificación).
//
// IMPORTANTE — rate limiting (`recuperacionPasswordLimiter`, src/middleware/rateLimit.ts): esta
// batería hace ~15 requests contra los 2 endpoints nuevos, que COMPARTEN un mismo limiter (10
// intentos / 15 min por IP, default de la aplicación). Con el default, esta misma corrida agota
// el límite a mitad de camino y el resto falla con 429 en cascada (verificado corriéndolo así:
// falla justo en el request #11, "el token del pedido ANTERIOR quedó invalidado..."). Arrancar
// el SERVIDOR (no este script) con `RATE_LIMIT_RECUPERACION_MAX` alto (ej. 100) para que la
// batería completa quepa dentro del límite — el propio rate limiting en sí ya se ejercita aparte
// en scripts/test-validaciones-campos.mjs (u otro que cubra `registroLimiter`/`loginLimiter`),
// no hace falta que esta batería puntual también lo cubra.
//
// Ejemplo de uso (PowerShell/bash), servidor ya corriendo en otra terminal con
// ENABLE_DEV_ROUTES=true, RECUPERACION_PASSWORD_TTL_MIN=0.1 y RATE_LIMIT_RECUPERACION_MAX=100:
//   BASE_URL=http://localhost:3057 DATABASE_URL=postgresql://... DATABASE_SSL=true \
//     RECUPERACION_PASSWORD_TTL_MIN=0.1 node scripts/test-recuperacion-password.mjs

import pg from 'pg';

const BASE = process.env.BASE_URL || 'http://localhost:3000';
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error(
    'Falta DATABASE_URL — este script necesita leer la base directamente para el caso "cuenta solo-Google" (ver encabezado del archivo).'
  );
  process.exit(1);
}

// Mismo criterio que resolveSsl() en src/db.ts: contra Render (u otro Postgres gestionado que
// exige TLS con un certificado que Node no valida por default) hace falta el override explícito
// — sin esto, conectar directo con `pg.Client` contra ese tipo de host falla con ECONNRESET.
const sslOverride = process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined;
const db = new pg.Client({ connectionString: dbUrl, ...(sslOverride ? { ssl: sslOverride } : {}) });

async function req(method, path, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => null) };
}

let fallas = 0;
function ok(cond, msg) {
  if (cond) console.log('OK:', msg);
  else {
    fallas++;
    console.log('FALLA:', msg);
  }
}
function assert(cond, msg) {
  if (!cond) throw new Error('Setup falló: ' + msg);
  console.log('OK (setup):', msg);
}

async function main() {
  await db.connect();
  const sello = Date.now();

  // ---------- Setup: usuario real de prueba (email + contraseña) ----------
  const email = `recuperacion-${sello}@test.com`;
  const passwordVieja = 'clave-vieja-123';
  const registro = await req('POST', '/auth/registro-cliente', {
    email,
    password: passwordVieja,
    nombre: 'Cliente Recuperación',
  });
  assert(registro.status === 201, 'registro de cliente de prueba (setup)');

  // ========== Caso feliz: solicitar -> canjear -> la vieja password deja de servir ==========
  const pedido1 = await req('POST', '/auth/recuperar-password', { email });
  ok(pedido1.status === 200, `recuperar-password (cuenta con password) responde 200 (obtuvo ${pedido1.status})`);
  ok(typeof pedido1.data?.mensaje === 'string' && pedido1.data.mensaje.length > 0, 'recuperar-password responde con un mensaje genérico');
  assert(
    typeof pedido1.data?.token_dev === 'string' && pedido1.data.token_dev.length > 0,
    'recuperar-password expone token_dev (requiere ENABLE_DEV_ROUTES=true en el servidor)'
  );
  const tokenFeliz = pedido1.data.token_dev;

  const passwordNueva = 'clave-nueva-456';
  const canje1 = await req('POST', '/auth/reset-password', { token: tokenFeliz, password: passwordNueva });
  ok(canje1.status === 200, `reset-password con token válido responde 200 (obtuvo ${canje1.status})`);

  const loginViejaFalla = await req('POST', '/auth/login', { email, password: passwordVieja });
  ok(loginViejaFalla.status === 401, `login con la contraseña VIEJA ya no funciona (401 esperado, obtuvo ${loginViejaFalla.status})`);

  const loginNuevaFunciona = await req('POST', '/auth/login', { email, password: passwordNueva });
  ok(
    loginNuevaFunciona.status === 200 && typeof loginNuevaFunciona.data?.token === 'string',
    `login con la contraseña NUEVA funciona (obtuvo ${loginNuevaFunciona.status})`
  );

  // ========== Token de un solo uso: reintentar el mismo token ya canjeado ==========
  const reintento = await req('POST', '/auth/reset-password', { token: tokenFeliz, password: 'otra-clave-789' });
  ok(reintento.status === 400, `reusar un token ya canjeado responde 400 (obtuvo ${reintento.status})`);

  // ========== No-enumeración: email inexistente responde EXACTAMENTE igual que uno existente ==========
  const pedidoInexistente = await req('POST', '/auth/recuperar-password', { email: `no-existe-${sello}@test.com` });
  ok(
    pedidoInexistente.status === pedido1.status,
    `email inexistente responde el mismo status (${pedidoInexistente.status}) que uno existente (${pedido1.status})`
  );
  ok(pedidoInexistente.data?.mensaje === pedido1.data?.mensaje, 'email inexistente responde el mismo mensaje genérico que uno existente');
  ok(pedidoInexistente.data?.token_dev === undefined, 'email inexistente NO expone token_dev (no se generó ningún token)');

  // ========== No-enumeración: cuenta solo-Google (password_hash IS NULL) responde igual ==========
  // Armada por INSERT directo (ver encabezado): no hay forma de crear esta cuenta por HTTP sin
  // GOOGLE_CLIENT_ID real en este entorno.
  const emailGoogle = `google-only-${sello}@test.com`;
  const idUsuarioGoogle = (
    await db.query(
      `INSERT INTO usuario (email, password_hash, google_id, nombre, rol)
       VALUES ($1, NULL, $2, $3, 'cliente') RETURNING id`,
      [emailGoogle, `google-fake-id-${sello}`, 'Cliente Solo Google']
    )
  ).rows[0].id;

  const pedidoGoogle = await req('POST', '/auth/recuperar-password', { email: emailGoogle });
  ok(
    pedidoGoogle.status === pedido1.status,
    `cuenta solo-Google responde el mismo status (${pedidoGoogle.status}) que una cuenta con password (${pedido1.status})`
  );
  ok(pedidoGoogle.data?.mensaje === pedido1.data?.mensaje, 'cuenta solo-Google responde el mismo mensaje genérico');
  ok(pedidoGoogle.data?.token_dev === undefined, 'cuenta solo-Google NO expone token_dev (no se generó ningún token)');

  const filasTokenGoogle = await db.query(
    'SELECT count(*)::int AS n FROM token_recuperacion_password WHERE usuario_id = $1',
    [idUsuarioGoogle]
  );
  ok(filasTokenGoogle.rows[0].n === 0, 'cuenta solo-Google: no se insertó ninguna fila en token_recuperacion_password (a nivel de base)');

  // ========== Password que no cumple el mínimo (passwordSchema, PASSWORD_MIN_LENGTH=8) ==========
  const pedido2 = await req('POST', '/auth/recuperar-password', { email });
  assert(typeof pedido2.data?.token_dev === 'string', 'segundo pedido de recuperación expone token_dev (setup)');
  const tokenParaValidacion = pedido2.data.token_dev;

  const resetCorto = await req('POST', '/auth/reset-password', { token: tokenParaValidacion, password: '123' });
  ok(resetCorto.status === 400, `reset-password con password corta (< 8) responde 400 (obtuvo ${resetCorto.status})`);

  // La validación de zod corre ANTES de tocar la base — el token no debería "quemarse" por un
  // intento con datos inválidos. Lo confirmamos canjeándolo después con una password válida.
  const canjeConPasswordValida = await req('POST', '/auth/reset-password', {
    token: tokenParaValidacion,
    password: 'clave-valida-999',
  });
  ok(
    canjeConPasswordValida.status === 200,
    `el mismo token sigue vigente después de un intento con password inválida (obtuvo ${canjeConPasswordValida.status})`
  );

  // ========== "Varias recuperaciones seguidas" invalida las anteriores (modelo-datos.md §2decies) ==========
  const previo = await req('POST', '/auth/recuperar-password', { email });
  assert(typeof previo.data?.token_dev === 'string', 'pedido "previo" expone token_dev (setup)');
  const tokenPrevio = previo.data.token_dev;

  const siguiente = await req('POST', '/auth/recuperar-password', { email });
  assert(typeof siguiente.data?.token_dev === 'string', 'pedido "siguiente" expone token_dev (setup)');
  const tokenSiguiente = siguiente.data.token_dev;

  ok(tokenPrevio !== tokenSiguiente, 'dos pedidos de recuperación seguidos generan tokens distintos');

  const canjeTokenPrevio = await req('POST', '/auth/reset-password', { token: tokenPrevio, password: 'clave-old-000' });
  ok(
    canjeTokenPrevio.status === 400,
    `el token del pedido ANTERIOR quedó invalidado por el pedido más nuevo (400 esperado, obtuvo ${canjeTokenPrevio.status})`
  );

  const canjeTokenSiguiente = await req('POST', '/auth/reset-password', { token: tokenSiguiente, password: 'clave-new-111' });
  ok(canjeTokenSiguiente.status === 200, `el token del pedido MÁS NUEVO sigue funcionando (obtuvo ${canjeTokenSiguiente.status})`);

  // A lo sumo 1 token pendiente por usuario en todo momento (índice único parcial
  // `uq_token_recuperacion_password_usuario_pendiente`) — en este punto, 0 (el único pendiente
  // que quedaba ya se canjeó arriba).
  const idUsuario = (await db.query('SELECT id FROM usuario WHERE email = $1', [email])).rows[0].id;
  const pendientesRestantes = await db.query(
    'SELECT count(*)::int AS n FROM token_recuperacion_password WHERE usuario_id = $1 AND usado_en IS NULL',
    [idUsuario]
  );
  ok(pendientesRestantes.rows[0].n === 0, 'no queda ningún token pendiente para este usuario después de canjear el último (chequeo a nivel de base)');

  // ========== Token vencido — solo si el servidor corre con un TTL bajo (ver encabezado) ==========
  const ttlMin = Number(process.env.RECUPERACION_PASSWORD_TTL_MIN ?? 30);
  if (ttlMin > 0 && ttlMin <= 1) {
    const pedidoParaVencer = await req('POST', '/auth/recuperar-password', { email });
    assert(typeof pedidoParaVencer.data?.token_dev === 'string', 'pedido "para vencer" expone token_dev (setup)');
    const tokenParaVencer = pedidoParaVencer.data.token_dev;

    const esperaMs = Math.ceil(ttlMin * 60_000) + 2000;
    console.log(`Esperando ${esperaMs}ms a que venza el token (RECUPERACION_PASSWORD_TTL_MIN=${ttlMin})...`);
    await new Promise((resolve) => setTimeout(resolve, esperaMs));

    const canjeVencido = await req('POST', '/auth/reset-password', { token: tokenParaVencer, password: 'clave-tardia-222' });
    ok(canjeVencido.status === 400, `token vencido responde 400 (obtuvo ${canjeVencido.status})`);
  } else {
    console.log(
      'SKIP: "token vencido" no se ejercita en esta corrida — correr el servidor y este script con RECUPERACION_PASSWORD_TTL_MIN=0.1 (6s) para ejercitarlo (esperar 30 minutos reales no es práctico).'
    );
  }

  // ========== Token con formato inválido / que nunca existió ==========
  const tokenBasura = await req('POST', '/auth/reset-password', { token: 'esto-no-es-un-token-real', password: 'clave-cualquiera-333' });
  ok(tokenBasura.status === 400, `token inexistente/con formato inválido responde 400 (obtuvo ${tokenBasura.status})`);

  // ========== Campos faltantes ==========
  const sinEmail = await req('POST', '/auth/recuperar-password', {});
  ok(sinEmail.status === 400, `recuperar-password sin email responde 400 (obtuvo ${sinEmail.status})`);

  const sinToken = await req('POST', '/auth/reset-password', { password: 'clave-cualquiera-444' });
  ok(sinToken.status === 400, `reset-password sin token responde 400 (obtuvo ${sinToken.status})`);

  const sinPassword = await req('POST', '/auth/reset-password', { token: 'x' });
  ok(sinPassword.status === 400, `reset-password sin password responde 400 (obtuvo ${sinPassword.status})`);

  await db.end();

  if (fallas > 0) {
    console.log(`\n${fallas} verificación(es) de HU-37 (recuperación de contraseña) fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\nHU-37 (recuperación de contraseña) verificada de punta a punta.');
}

main().catch((err) => {
  console.error('\n', err);
  process.exit(1);
});
