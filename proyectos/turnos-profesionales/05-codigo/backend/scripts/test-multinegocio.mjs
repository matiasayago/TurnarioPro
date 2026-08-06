// Verifica la generalización 1:1 -> N:M (ver ../../03-arquitectura/modelo-datos.md §2ter): un
// mismo profesional puede pertenecer a más de un negocio. Cubre, en un solo flujo:
//  1) Alta del MISMO profesional (mismo email) en 2 negocios distintos por sus respectivos
//     administradores -> se reusa la identidad profesional existente (no se duplica, no falla),
//     y re-invitarlo a un negocio del que YA es miembro activo responde 409.
//  2) POST /auth/login con 2 negocios activos -> token SIN negocio_id, body con `negocios`
//     (2 entradas); la password ORIGINAL del profesional (fijada en el primer alta) sigue
//     siendo la válida, aunque el segundo alta haya mandado una password distinta (nunca se
//     pisa una credencial existente).
//  3) POST /auth/entrar-a-negocio con un negocio propio -> token nuevo con ese negocio_id,
//     utilizable para operar en ese negocio (ver agenda propia).
//  4) POST /auth/entrar-a-negocio con un negocio ajeno -> 403.
//  5) Un profesional con UN SOLO negocio activo sigue logueando con negocio_id directo, sin
//     pasos extra (caso simple sin cambios de forma respecto de antes de esta generalización).
//  6) turno.negocio_id sale del NEGOCIO DEL SERVICIO reservado, no de ningún negocio "por
//     defecto" del profesional (que pertenece a 2) — verificado DIRECTAMENTE leyendo el campo
//     negocio_id que devuelve GET /turnos/mios (usa `SELECT *`, lo expone tal cual).
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

async function registrarNegocioConServicio(nombre, sello) {
  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: `Negocio ${nombre} (multinegocio)`,
    email: `admin-multi-${nombre}-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: `Admin ${nombre}`,
  });
  assert(registro.status === 201, `registro de negocio ${nombre}`);
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: `Servicio ${nombre}`, duracion_min: 30, precio_referencia: 500 },
    adminToken
  );
  assert(servicio.status === 201, `alta de servicio en negocio ${nombre}`);

  return { adminToken, negocioId, servicioId: servicio.data.id };
}

async function main() {
  const sello = Date.now();

  // ---------- Negocios A y B, cada uno con su propio admin y servicio ----------
  const negA = await registrarNegocioConServicio('A', sello);
  const negB = await registrarNegocioConServicio('B', sello);

  // ================= 1) Un mismo profesional (mismo email) dado de alta en A y en B =================
  const emailProfesional = `prof-multi-${sello}@test.com`;
  const altaEnA = await req(
    'POST',
    `/negocios/${negA.negocioId}/profesionales`,
    { email: emailProfesional, password: 'password-original1', nombre: 'Profesional Multi' },
    negA.adminToken
  );
  assert(altaEnA.status === 201, 'alta del profesional en negocio A (identidad nueva)');
  const profesionalId = altaEnA.data.id;

  const altaEnB = await req(
    'POST',
    `/negocios/${negB.negocioId}/profesionales`,
    { email: emailProfesional, password: 'password-distinta-debe-ser-ignorada', nombre: 'Nombre que debe ser ignorado' },
    negB.adminToken
  );
  ok(
    altaEnB.status === 201,
    `alta del MISMO profesional (por email) en negocio B responde 201 (reuso, no duplica) — obtuvo ${altaEnB.status} ${JSON.stringify(altaEnB.data)}`
  );
  ok(
    altaEnB.data?.id === profesionalId,
    `alta en negocio B reusa la MISMA identidad profesional (id ${profesionalId}) en vez de crear una nueva — obtuvo ${altaEnB.data?.id}`
  );

  // Re-dar de alta en A (ya es miembro activo) -> 409, no duplica el vínculo.
  const altaDuplicadaEnA = await req(
    'POST',
    `/negocios/${negA.negocioId}/profesionales`,
    { email: emailProfesional, password: 'otra-password-ignorada', nombre: 'Otro nombre ignorado' },
    negA.adminToken
  );
  ok(
    altaDuplicadaEnA.status === 409,
    `re-dar de alta al mismo profesional en un negocio del que YA es miembro activo responde 409 (obtuvo ${altaDuplicadaEnA.status})`
  );

  // ================= 2) Login con 2 negocios activos =================
  const loginPasswordOriginal = await req('POST', '/auth/login', { email: emailProfesional, password: 'password-original1' });
  ok(
    loginPasswordOriginal.status === 200,
    `la password ORIGINAL (fijada en el alta de negocio A) sigue siendo válida tras el alta en B — el segundo alta NO pisó la credencial (obtuvo ${loginPasswordOriginal.status})`
  );

  const login2Negocios = loginPasswordOriginal;
  assert(login2Negocios.status === 200, 'login del profesional con 2 negocios');
  const claims2Negocios = decodeJwt(login2Negocios.data.token);
  ok(
    claims2Negocios.negocio_id === undefined,
    `login con 2+ negocios activos: el token NO lleva negocio_id (obtuvo ${claims2Negocios.negocio_id})`
  );
  ok(!!claims2Negocios.profesional_id, 'login con 2+ negocios activos: el token SÍ lleva profesional_id (identidad propia)');
  ok(
    Array.isArray(login2Negocios.data.negocios) && login2Negocios.data.negocios.length === 2,
    `login con 2+ negocios activos: el body devuelve 'negocios' con 2 entradas (obtuvo ${JSON.stringify(login2Negocios.data.negocios)})`
  );
  const idsDevueltos = (login2Negocios.data.negocios ?? []).map((n) => n.negocio_id).sort();
  const idsEsperados = [negA.negocioId, negB.negocioId].sort();
  ok(
    JSON.stringify(idsDevueltos) === JSON.stringify(idsEsperados),
    `login: los negocio_id devueltos son exactamente A y B (obtuvo ${JSON.stringify(idsDevueltos)}, esperado ${JSON.stringify(idsEsperados)})`
  );
  ok(
    (login2Negocios.data.negocios ?? []).every((n) => n.rol === 'profesional' && typeof n.nombre === 'string'),
    'login: cada entrada de "negocios" incluye rol=profesional y nombre del negocio'
  );

  // ================= 3) POST /auth/entrar-a-negocio con un negocio PROPIO =================
  const entrarA = await req('POST', '/auth/entrar-a-negocio', { negocio_id: negA.negocioId }, login2Negocios.data.token);
  ok(entrarA.status === 200, `entrar-a-negocio con un negocio propio (A) responde 200 (obtuvo ${entrarA.status} ${JSON.stringify(entrarA.data)})`);
  const claimsEntrarA = entrarA.data?.token ? decodeJwt(entrarA.data.token) : {};
  ok(claimsEntrarA.negocio_id === negA.negocioId, `el token reemitido lleva negocio_id = A (obtuvo ${claimsEntrarA.negocio_id})`);
  ok(claimsEntrarA.profesional_id === profesionalId, 'el token reemitido conserva el profesional_id original');
  ok(claimsEntrarA.sub === claims2Negocios.sub, 'el token reemitido conserva el sub (usuario_id) original');

  // Con ese token, puede operar en el negocio A: ver su propia agenda.
  const agendaEnA = await req('GET', `/profesionales/${profesionalId}/turnos`, undefined, entrarA.data.token);
  ok(agendaEnA.status === 200, `con el token de la vista A, el profesional puede ver su propia agenda (obtuvo ${agendaEnA.status})`);

  // ================= 4) POST /auth/entrar-a-negocio con un negocio AJENO =================
  const negC = await registrarNegocioConServicio('C-ajeno', sello); // sin ningún vínculo con este profesional
  const entrarNegocioAjeno = await req('POST', '/auth/entrar-a-negocio', { negocio_id: negC.negocioId }, login2Negocios.data.token);
  ok(
    entrarNegocioAjeno.status === 403,
    `entrar-a-negocio con un negocio_id al que NO pertenece responde 403 (obtuvo ${entrarNegocioAjeno.status})`
  );

  // ================= 5) Caso simple: profesional con UN SOLO negocio =================
  const negD = await registrarNegocioConServicio('D-simple', sello);
  const emailSimple = `prof-simple-${sello}@test.com`;
  const altaSimple = await req(
    'POST',
    `/negocios/${negD.negocioId}/profesionales`,
    { email: emailSimple, password: 'prof12345', nombre: 'Profesional Simple' },
    negD.adminToken
  );
  assert(altaSimple.status === 201, 'alta de profesional con un solo negocio (setup)');
  const loginSimple = await req('POST', '/auth/login', { email: emailSimple, password: 'prof12345' });
  assert(loginSimple.status === 200, 'login del profesional con un solo negocio');
  const claimsSimple = decodeJwt(loginSimple.data.token);
  ok(
    claimsSimple.negocio_id === negD.negocioId,
    `login con UN SOLO negocio activo: el token lleva negocio_id DIRECTO, sin pasos extra (obtuvo ${claimsSimple.negocio_id}, esperado ${negD.negocioId})`
  );
  ok(
    loginSimple.data.negocios === undefined,
    `login con UN SOLO negocio activo: el body NO lleva la clave 'negocios' (caso simple sin cambio de forma) — obtuvo ${JSON.stringify(loginSimple.data)}`
  );

  // ================= 6) turno.negocio_id sale del SERVICIO, no de un negocio "default" =================
  // El profesional multi-negocio (miembro de A y B) se asocia al servicio de NEGOCIO B, publica
  // disponibilidad y un cliente reserva un turno con él para ESE servicio, usando la vista B.
  const entrarB = await req('POST', '/auth/entrar-a-negocio', { negocio_id: negB.negocioId }, login2Negocios.data.token);
  assert(entrarB.status === 200, 'entrar a la vista del negocio B (setup)');
  ok(entrarB.data?.negocio_id === negB.negocioId, 'entrar-a-negocio también devuelve negocio_id en el body, por comodidad');
  const profTokenB = entrarB.data.token;

  const asociarServicioB = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: negB.servicioId, requiere_sena: false },
    profTokenB
  );
  assert(asociarServicioB.status === 201, 'el profesional multi-negocio asocia el servicio de NEGOCIO B (setup)');

  const diaDispo = (new Date().getDay() + 2) % 7;
  await req(
    'POST',
    `/profesionales/${profesionalId}/disponibilidad`,
    { servicio_id: negB.servicioId, dia_semana: diaDispo, hora_inicio: '09:00', hora_fin: '18:00' },
    profTokenB
  );

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-multi-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente Multi',
  });
  assert(cliente.status === 201, 'registro de cliente (setup)');

  const slotsB = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${negB.servicioId}&dias=14`);
  const slotB = slotsB.data?.slots?.[0];
  assert(!!slotB, 'hay slots calculados para el servicio de negocio B (setup)');

  const turnoEnB = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: negB.servicioId, inicio: slotB },
    cliente.data.token
  );
  ok(
    turnoEnB.status === 201,
    `reserva de turno con el profesional multi-negocio, servicio de NEGOCIO B, responde 201 (obtuvo ${turnoEnB.status} ${JSON.stringify(turnoEnB.data)})`
  );

  // Verificación DIRECTA (no solo indirecta): GET /turnos/mios usa `SELECT *`, así que expone
  // negocio_id tal cual quedó persistido en la fila del turno.
  const misTurnos = await req('GET', '/turnos/mios', undefined, cliente.data.token);
  assert(misTurnos.status === 200, 'cliente puede ver sus propios turnos (setup)');
  const turnoGuardado = (misTurnos.data ?? []).find((t) => t.id === turnoEnB.data?.id);
  ok(!!turnoGuardado, 'el turno reservado aparece en "mis turnos" del cliente');
  ok(
    turnoGuardado?.negocio_id === negB.negocioId,
    `turno.negocio_id corresponde al negocio del SERVICIO reservado (B: ${negB.negocioId}) — obtuvo ${turnoGuardado?.negocio_id}`
  );
  ok(
    turnoGuardado?.negocio_id !== negA.negocioId,
    'turno.negocio_id NO es el negocio A: aunque el profesional también pertenece a A (y fue dado de alta ahí PRIMERO), el turno reservado fue para el servicio de B, no hay negocio "por defecto"'
  );

  // Confirmación adicional (indirecta, vía descubrimiento HU-08): el profesional aparece como
  // oferente del servicio de B en el contexto de negocio B.
  const profesionalesDeServicioB = await req(
    'GET',
    `/negocios/${negB.negocioId}/servicios/${negB.servicioId}/profesionales`
  );
  ok(
    profesionalesDeServicioB.status === 200 && profesionalesDeServicioB.data.some((p) => p.id === profesionalId),
    'el profesional aparece como oferente del servicio de NEGOCIO B (confirma la asociación N:M correcta)'
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) del caso multi-negocio (N:M) fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log(
    '\n✅ Generalización N:M (multi-negocio) verificada: alta reusando identidad sin duplicar, login con "vista activa", POST /auth/entrar-a-negocio, y turno.negocio_id resuelto por el SERVICIO reservado, no por un negocio "default" del profesional.'
  );
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
