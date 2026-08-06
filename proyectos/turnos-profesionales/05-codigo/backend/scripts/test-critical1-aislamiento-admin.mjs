// Test de regresión CRITICAL-1 (ver ../../07-seguridad/informe-seguridad.md) — pedido
// explícitamente por Security: sin este script no había forma de confirmar que el fix es real.
//
// El bug vivía en POST /auth/login (NO en /auth/registro-negocio, que ya firmaba el token
// correcto porque el negocio se acaba de crear en la misma request): la query que resolvía el
// negocio_id del administrador no correlacionaba en absoluto con el usuario que se logueaba, y
// devolvía el negocio_id del PRIMER negocio de toda la tabla. Con un solo negocio en la base el
// bug es invisible ("el primero de la tabla" coincide por casualidad con el propio) — por eso
// este script registra 3 negocios distintos ANTES de loguear a ningún administrador.
//
// Requiere el servidor corriendo. No depende de otros scripts (emails únicos por timestamp).
const BASE = 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => null) };
}

function decodeJwt(token) {
  return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
}

let fallas = 0;
function ok(cond, msg) {
  if (cond) console.log('OK:', msg);
  else { fallas++; console.log('FALLA:', msg); }
}
function assert(cond, msg) {
  if (!cond) throw new Error('Setup falló: ' + msg);
  console.log('OK (setup):', msg);
}

async function registrarNegocio(nombre, sello) {
  const email = `admin-critical1-${nombre}-${sello}@test.com`;
  const password = 'admin1234';
  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: `Negocio ${nombre} (CRITICAL-1)`,
    email,
    password,
    nombre_admin: `Admin ${nombre}`,
  });
  assert(registro.status === 201, `registro de negocio ${nombre}`);
  return { email, password, negocioId: registro.data.negocio_id, tokenRegistro: registro.data.token };
}

async function main() {
  const sello = Date.now();

  // Registramos 3 negocios (2+ requerido explícitamente por Security en su remediación
  // sugerida) ANTES de loguear a ninguno, para que el "primer negocio de la tabla" nunca
  // coincida por casualidad con el propio de ningún administrador que loguee después.
  const negA = await registrarNegocio('A', sello);
  const negB = await registrarNegocio('B', sello);
  const negC = await registrarNegocio('C', sello);

  ok(
    negA.negocioId !== negB.negocioId && negB.negocioId !== negC.negocioId && negA.negocioId !== negC.negocioId,
    'precondición: los 3 negocios registrados tienen negocio_id distintos entre sí'
  );

  // Control positivo: el registro YA firmaba el token correcto (no es donde vivía el bug).
  const claimsRegistroA = decodeJwt(negA.tokenRegistro);
  ok(
    claimsRegistroA.negocio_id === negA.negocioId,
    'control: el token devuelto por /auth/registro-negocio de A lleva el negocio_id PROPIO de A'
  );

  // --- El bug vivía específicamente en LOGIN — logueamos cada admin por separado ---
  const loginA = await req('POST', '/auth/login', { email: negA.email, password: negA.password });
  assert(loginA.status === 200, 'login del administrador A');
  const claimsLoginA = decodeJwt(loginA.data.token);

  const loginB = await req('POST', '/auth/login', { email: negB.email, password: negB.password });
  assert(loginB.status === 200, 'login del administrador B');
  const claimsLoginB = decodeJwt(loginB.data.token);

  const loginC = await req('POST', '/auth/login', { email: negC.email, password: negC.password });
  assert(loginC.status === 200, 'login del administrador C');
  const claimsLoginC = decodeJwt(loginC.data.token);

  ok(
    claimsLoginA.negocio_id === negA.negocioId,
    `CRITICAL-1: el login del admin A debe llevar el negocio_id PROPIO (${negA.negocioId}) — obtuvo ${claimsLoginA.negocio_id}`
  );
  ok(
    claimsLoginB.negocio_id === negB.negocioId,
    `CRITICAL-1: el login del admin B debe llevar el negocio_id PROPIO (${negB.negocioId}) — obtuvo ${claimsLoginB.negocio_id}`
  );
  ok(
    claimsLoginC.negocio_id === negC.negocioId,
    `CRITICAL-1: el login del admin C debe llevar el negocio_id PROPIO (${negC.negocioId}) — obtuvo ${claimsLoginC.negocio_id}`
  );
  ok(
    claimsLoginA.negocio_id !== negB.negocioId && claimsLoginA.negocio_id !== negC.negocioId,
    'CRITICAL-1: el negocio_id del login de A NO coincide con el de B ni con el de C'
  );
  ok(
    claimsLoginB.negocio_id !== negA.negocioId && claimsLoginB.negocio_id !== negC.negocioId,
    'CRITICAL-1: el negocio_id del login de B NO coincide con el de A ni con el de C'
  );

  // --- Verificación funcional end-to-end (repite el PoC de Security con el fix aplicado): con
  // el token de LOGIN (no el de registro), cada administrador solo puede administrar SU
  // PROPIO negocio, nunca uno ajeno (RN9). Esto es justo lo que le permitió al PoC de Security
  // inyectar un servicio en un negocio ajeno antes del fix. ---
  const altaEnPropio = await req(
    'POST',
    `/negocios/${negA.negocioId}/servicios`,
    { nombre: 'Servicio propio de A', duracion_min: 30 },
    loginA.data.token
  );
  ok(altaEnPropio.status === 201, 'con el token de LOGIN, el admin A puede administrar SU PROPIO negocio (201)');

  const altaCruzada = await req(
    'POST',
    `/negocios/${negB.negocioId}/servicios`,
    { nombre: 'SERVICIO-INYECTADO-POR-A', duracion_min: 30 },
    loginA.data.token
  );
  ok(
    altaCruzada.status === 403,
    `RN9: con el token de LOGIN, el admin A NO debe poder administrar el negocio B (403 esperado, obtuvo ${altaCruzada.status} ${JSON.stringify(altaCruzada.data)})`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de CRITICAL-1 fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ CRITICAL-1 (aislamiento multi-tenant en login de administrador) verificado con 3 negocios.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
