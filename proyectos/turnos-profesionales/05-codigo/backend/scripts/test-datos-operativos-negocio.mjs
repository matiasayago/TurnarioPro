// Verifica HU-31 (02-backlog/backlog.md, épica E13) — resto del alcance que la ronda "Modo
// Administrador v1"/E15 había dejado pendiente explícitamente de DBA+Backend: las 4 columnas
// nuevas de `negocio` (`horario_atencion`, `direccion`, `telefono`, `logo_url` — ver
// 03-arquitectura/modelo-datos.md §2undecies, DBA) extendidas en PATCH /negocios/:id y
// GET /negocios/:id (src/routes/negocios.ts, este mismo ciclo). Requiere el servidor corriendo,
// contra un Postgres que YA tenga estas 4 columnas (cualquier base migrada desde cero con
// runMigrations() las trae solas, porque 001_init.sql ya las incluye — ver el propio comentario
// de db.ts; una base más vieja necesita la migración incremental 009_negocio_datos_operativos.sql
// aplicada a mano primero). No depende de otros scripts (emails únicos por timestamp).
//
// Variables de entorno:
//   BASE_URL   default http://localhost:3000 (mismo criterio que test-recuperacion-password.mjs)
//
// Cubre, en orden:
//   1) GET /negocios/:id de un negocio recién registrado: las 4 columnas nuevas vienen `null`
//      (nullable sin DEFAULT/backfill, DBA) — no rompen el shape de la respuesta.
//   2) PATCH /negocios/:id con los 4 campos nuevos cargados (valores reales) -> 200, devueltos
//      tal cual, y persistidos (confirmado releyendo con GET /:id, no solo confiando en el
//      response del propio PATCH).
//   3) PATCH de nuevo, esta vez con los 4 campos en `null` explícito (vaciar un campo ya
//      cargado) -> 200, vuelven a `null` — confirma que el schema es `.nullable()` sin
//      `.optional()` (hay que poder mandar `null`, no alcanza con omitir el campo).
//   4) `logo_url` con un valor que NO es una URL válida -> 400 (validación de formato agregada
//      por este ciclo, recomendación explícita de DBA — `negocio` no tiene CHECK de formato a
//      nivel de base).
//   5) Omitir un campo nuevo del body por completo (en vez de mandar `null`) -> 400 — mismo
//      criterio que ya rige para `rubro`/`ubicacion` (NO son `.optional()`).
//   6) Admin de OTRO negocio (B) intentando este mismo PATCH sobre la URL de negocio A -> 403
//      (chequeo de ownership ya existente, RN9 vía claim del JWT — confirma que sigue cubriendo
//      los 4 campos nuevos sin necesitar ningún cambio adicional).
//   7) GET /negocios (listado): confirma la decisión de diseño documentada en el propio código
//      (negocios.ts) de NO sumar estas 4 columnas ahí — ninguna fila las trae.
const BASE = process.env.BASE_URL || 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => null) };
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

async function main() {
  const sello = Date.now();

  // ================= Setup =================
  const registroA = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio A (datos-operativos)',
    email: `admin-a-datosop-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin A',
  });
  assert(registroA.status === 201, 'registro de negocio A');
  const adminTokenA = registroA.data.token;
  const negocioAId = registroA.data.negocio_id;

  const registroB = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio B (datos-operativos)',
    email: `admin-b-datosop-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin B',
  });
  assert(registroB.status === 201, 'registro de negocio B');
  const adminTokenB = registroB.data.token;

  console.log('\n===== 1) GET /negocios/:id de un negocio recién registrado — las 4 columnas nuevas vienen null =====');

  const detalleInicial = await req('GET', `/negocios/${negocioAId}`);
  ok(
    detalleInicial.status === 200 &&
      detalleInicial.data.horario_atencion === null &&
      detalleInicial.data.direccion === null &&
      detalleInicial.data.telefono === null &&
      detalleInicial.data.logo_url === null,
    `negocio recién registrado -> las 4 columnas nuevas vienen null (obtuvo ${detalleInicial.status} ${JSON.stringify(detalleInicial.data)})`
  );

  console.log('\n===== 2) PATCH /negocios/:id — cargar los 4 campos nuevos =====');

  const bodyCompleto = {
    nombre: 'Negocio A (datos-operativos)',
    rubro: 'Estética',
    ubicacion: 'Palermo, CABA',
    horario_atencion: 'Lunes a Viernes 9 a 18hs, Sábados 9 a 13hs',
    direccion: 'Av. Santa Fe 1234, piso 3, depto B',
    telefono: '+54 9 11 5555-1234',
    logo_url: 'https://ejemplo.com/logos/negocio-a.png',
  };
  const patchCargar = await req('PATCH', `/negocios/${negocioAId}`, bodyCompleto, adminTokenA);
  ok(
    patchCargar.status === 200 &&
      patchCargar.data.horario_atencion === bodyCompleto.horario_atencion &&
      patchCargar.data.direccion === bodyCompleto.direccion &&
      patchCargar.data.telefono === bodyCompleto.telefono &&
      patchCargar.data.logo_url === bodyCompleto.logo_url,
    `PATCH con los 4 campos nuevos cargados -> 200, devueltos tal cual (obtuvo ${patchCargar.status} ${JSON.stringify(patchCargar.data)})`
  );

  const detalleDespuesDeCargar = await req('GET', `/negocios/${negocioAId}`);
  ok(
    detalleDespuesDeCargar.status === 200 &&
      detalleDespuesDeCargar.data.horario_atencion === bodyCompleto.horario_atencion &&
      detalleDespuesDeCargar.data.direccion === bodyCompleto.direccion &&
      detalleDespuesDeCargar.data.telefono === bodyCompleto.telefono &&
      detalleDespuesDeCargar.data.logo_url === bodyCompleto.logo_url,
    `efecto: GET /negocios/:id releído después del PATCH confirma los 4 campos persistidos (no solo el response del propio PATCH) (obtuvo ${JSON.stringify(detalleDespuesDeCargar.data)})`
  );

  console.log('\n===== 3) PATCH /negocios/:id — vaciar los 4 campos con null explícito =====');

  const bodyVaciar = { ...bodyCompleto, horario_atencion: null, direccion: null, telefono: null, logo_url: null };
  const patchVaciar = await req('PATCH', `/negocios/${negocioAId}`, bodyVaciar, adminTokenA);
  ok(
    patchVaciar.status === 200 &&
      patchVaciar.data.horario_atencion === null &&
      patchVaciar.data.direccion === null &&
      patchVaciar.data.telefono === null &&
      patchVaciar.data.logo_url === null,
    `PATCH con los 4 campos en null explícito -> 200, vuelven a null (obtuvo ${patchVaciar.status} ${JSON.stringify(patchVaciar.data)})`
  );

  const detalleDespuesDeVaciar = await req('GET', `/negocios/${negocioAId}`);
  ok(
    detalleDespuesDeVaciar.status === 200 &&
      detalleDespuesDeVaciar.data.horario_atencion === null &&
      detalleDespuesDeVaciar.data.direccion === null &&
      detalleDespuesDeVaciar.data.telefono === null &&
      detalleDespuesDeVaciar.data.logo_url === null,
    `efecto: GET /negocios/:id releído después del PATCH confirma los 4 campos vaciados de verdad en la base (obtuvo ${JSON.stringify(detalleDespuesDeVaciar.data)})`
  );

  // Re-cargar para los casos siguientes (queda un estado conocido, no null, para las próximas
  // aserciones de este script).
  const patchRecargar = await req('PATCH', `/negocios/${negocioAId}`, bodyCompleto, adminTokenA);
  assert(patchRecargar.status === 200, 'recargar los 4 campos (setup del resto del script)');

  console.log('\n===== 4) PATCH /negocios/:id — logo_url con formato inválido =====');

  const patchUrlInvalida = await req(
    'PATCH',
    `/negocios/${negocioAId}`,
    { ...bodyCompleto, logo_url: 'esto-no-es-una-url' },
    adminTokenA
  );
  ok(
    patchUrlInvalida.status === 400,
    `logo_url con formato inválido -> 400 (obtuvo ${patchUrlInvalida.status} ${JSON.stringify(patchUrlInvalida.data)})`
  );

  const detalleDespuesDeUrlInvalida = await req('GET', `/negocios/${negocioAId}`);
  ok(
    detalleDespuesDeUrlInvalida.status === 200 && detalleDespuesDeUrlInvalida.data.logo_url === bodyCompleto.logo_url,
    `efecto: el intento de PATCH con logo_url inválido NO modificó el valor ya cargado (rechazado antes de tocar la base) (obtuvo ${detalleDespuesDeUrlInvalida.data?.logo_url})`
  );

  console.log('\n===== 5) PATCH /negocios/:id — omitir un campo nuevo del body (no es .optional()) =====');

  const { horario_atencion: _omitido, ...bodySinHorario } = bodyCompleto;
  const patchSinHorario = await req('PATCH', `/negocios/${negocioAId}`, bodySinHorario, adminTokenA);
  ok(
    patchSinHorario.status === 400,
    `omitir horario_atencion del body (en vez de mandar null) -> 400, mismo criterio que rubro/ubicacion (obtuvo ${patchSinHorario.status} ${JSON.stringify(patchSinHorario.data)})`
  );

  console.log('\n===== 6) PATCH /negocios/:id — admin de OTRO negocio (B) sobre la URL de negocio A =====');

  const patchNegocioAjeno = await req('PATCH', `/negocios/${negocioAId}`, bodyCompleto, adminTokenB);
  ok(
    patchNegocioAjeno.status === 403,
    `admin de OTRO negocio (B) actuando sobre la URL de negocio A -> 403 (obtuvo ${patchNegocioAjeno.status})`
  );

  const detalleDespuesDeAjeno = await req('GET', `/negocios/${negocioAId}`);
  ok(
    detalleDespuesDeAjeno.status === 200 && detalleDespuesDeAjeno.data.telefono === bodyCompleto.telefono,
    `efecto: el intento cross-negocio NO modificó ningún dato de negocio A (obtuvo ${detalleDespuesDeAjeno.data?.telefono})`
  );

  console.log('\n===== 7) GET /negocios (listado) — decisión de diseño: NO suma las 4 columnas nuevas =====');

  const listado = await req('GET', '/negocios');
  const filaA = listado.data?.find((n) => n.id === negocioAId);
  ok(
    listado.status === 200 &&
      !!filaA &&
      !('horario_atencion' in filaA) &&
      !('direccion' in filaA) &&
      !('telefono' in filaA) &&
      !('logo_url' in filaA),
    `GET /negocios (listado): la fila de negocio A NO trae las 4 columnas nuevas, a propósito (obtuvo ${JSON.stringify(filaA)})`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log(
    '\n✅ Datos operativos del negocio (horario/dirección/teléfono/logo, HU-31) — carga, vaciado con null explícito, validación de formato de logo_url, aislamiento cross-negocio y exclusión deliberada del listado — verificados de punta a punta.'
  );
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
