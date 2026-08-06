// Verifica RN4 (un profesional puede ofrecer uno o más servicios; un servicio puede ser
// ofrecido por uno o más profesionales — relación N:M explícita vía `profesional_servicio`).
// En concreto: un profesional que NO tiene asociado un servicio (a) no debería aparecer en el
// listado de profesionales de ese servicio (HU-08, capa de descubrimiento) y (b) no debería
// poder recibir una reserva para ese servicio (capa de reserva).
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

  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio RN4',
    email: `admin-rn4-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin RN4',
  });
  assert(registro.status === 201, 'registro de negocio');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicioA = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio A (asociado)', duracion_min: 30, precio_referencia: 500 },
    adminToken
  );
  assert(servicioA.status === 201, 'alta de servicio A');
  const servicioAId = servicioA.data.id;

  const servicioB = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio B (NO asociado)', duracion_min: 30, precio_referencia: 500 },
    adminToken
  );
  assert(servicioB.status === 201, 'alta de servicio B');
  const servicioBId = servicioB.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-rn4-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional RN4' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', { email: `prof-rn4-${sello}@test.com`, password: 'prof1234' });
  const profToken = loginProf.data.token;

  // El profesional SOLO se asocia con el servicio A (RN4) — nunca con B.
  const asocA = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioAId, requiere_sena: false },
    profToken
  );
  assert(asocA.status === 201, 'asociar SOLO servicio A al profesional');

  // Publicamos disponibilidad para AMBOS servicios (para poder obtener horarios válidos vía
  // /slots y así aislar esta prueba del hallazgo de RN1 — ver
  // test-rn1-disponibilidad-y-solapamiento.mjs — el punto acá es la asociación profesional↔servicio,
  // no la disponibilidad horaria).
  const diaDispo = (new Date().getDay() + 3) % 7;
  await req(
    'POST',
    `/profesionales/${profesionalId}/disponibilidad`,
    { servicio_id: servicioAId, dia_semana: diaDispo, hora_inicio: '09:00', hora_fin: '12:00' },
    profToken
  );
  await req(
    'POST',
    `/profesionales/${profesionalId}/disponibilidad`,
    { servicio_id: servicioBId, dia_semana: diaDispo, hora_inicio: '09:00', hora_fin: '12:00' },
    profToken
  );

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-rn4-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente RN4',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  // --- Capa de descubrimiento (HU-08): el profesional NO debe listarse para el servicio B ---
  const profesionalesServicioB = await req('GET', `/negocios/${negocioId}/servicios/${servicioBId}/profesionales`);
  ok(
    profesionalesServicioB.status === 200 &&
      !profesionalesServicioB.data.some((p) => p.id === profesionalId),
    'RN4 (descubrimiento): el profesional NO aparece en el listado de profesionales del servicio B (no asociado)'
  );

  const profesionalesServicioA = await req('GET', `/negocios/${negocioId}/servicios/${servicioAId}/profesionales`);
  ok(
    profesionalesServicioA.status === 200 && profesionalesServicioA.data.some((p) => p.id === profesionalId),
    'RN4 (descubrimiento, control): el profesional SÍ aparece en el listado de profesionales del servicio A (asociado)'
  );

  // --- Capa de reserva: intentar reservar el servicio NO asociado (B) ---
  const slotsB = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioBId}&dias=14`);
  const slotB = slotsB.data?.slots?.[0];
  ok(!!slotB, 'hay slots calculados para el servicio B (precondición del siguiente check)');

  if (slotB) {
    const turnoServicioNoAsociado = await req(
      'POST',
      '/turnos',
      { profesional_id: profesionalId, servicio_id: servicioBId, inicio: slotB },
      clienteToken
    );
    ok(
      turnoServicioNoAsociado.status >= 400 && turnoServicioNoAsociado.status < 500,
      `RN4: no debe poder reservarse un turno para un servicio que el profesional NO tiene asociado — se obtuvo ${turnoServicioNoAsociado.status} ${JSON.stringify(turnoServicioNoAsociado.data)}`
    );
  }

  // --- Control positivo: reservar el servicio SÍ asociado (A) debe funcionar ---
  const slotsA = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioAId}&dias=14`);
  const slotA = slotsA.data?.slots?.[0];
  assert(!!slotA, 'hay slots calculados para el servicio A');
  const turnoServicioAsociado = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioAId, inicio: slotA },
    clienteToken
  );
  ok(
    turnoServicioAsociado.status === 201,
    'RN4 (control): reservar el servicio SÍ asociado al profesional funciona (201)'
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de RN4 fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ RN4 (asociación profesional↔servicio) verificada.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
