// Verifica el camino SIN seña de D2/RN10 (HU-09b, criterio de aceptación 1): si el
// profesional NO requiere seña para un servicio, el turno debe confirmarse DIRECTAMENTE
// (estado 'confirmado'), sin pasar por 'pendiente_de_pago'. Los scripts existentes
// (smoke-test.mjs, test-reprogramacion-y-expiracion.mjs) solo ejercitan el caso CON seña.
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
    nombre_negocio: 'Negocio Sin Seña',
    email: `admin-sinsena-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin Sin Seña',
  });
  assert(registro.status === 201, 'registro de negocio');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio sin seña', duracion_min: 45, precio_referencia: 800 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio');
  const servicioId = servicio.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-sinsena-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional Sin Seña' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', {
    email: `prof-sinsena-${sello}@test.com`,
    password: 'prof1234',
  });
  const profToken = loginProf.data.token;

  // Asociación EXPLÍCITA con requiere_sena: false (D2/RN10 — configurable por profesional+servicio).
  const asoc = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioId, requiere_sena: false },
    profToken
  );
  assert(asoc.status === 201, 'asociar servicio SIN seña requerida');

  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesionalId}/disponibilidad`,
      { servicio_id: servicioId, dia_semana: dia, hora_inicio: '08:00', hora_fin: '20:00' },
      profToken
    );
  }

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-sinsena-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente Sin Seña',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  const slots = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  assert(slots.status === 200 && slots.data.slots.length > 0, 'hay slots disponibles');
  const slot = slots.data.slots[0];

  const turno = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: slot },
    clienteToken
  );
  ok(turno.status === 201, 'HU-09b: la reserva sin seña responde 201');
  ok(
    turno.data?.estado === 'confirmado',
    `HU-09b/D2: el turno queda 'confirmado' DIRECTAMENTE cuando el servicio no requiere seña — estado recibido: '${turno.data?.estado}'`
  );
  ok(turno.data?.requiere_pago === false, 'HU-09b: requiere_pago es false cuando no hace falta seña');
  ok(turno.data?.monto_sena === null, 'HU-09b: monto_sena es null cuando no hace falta seña');

  const misTurnos = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turnoGuardado = misTurnos.data?.find((t) => t.id === turno.data?.id);
  ok(
    turnoGuardado?.estado === 'confirmado',
    "el turno persistido en 'mis turnos' figura como 'confirmado', no 'pendiente_de_pago'"
  );

  // El slot recién confirmado no debe seguir apareciendo como libre (el filtro de /slots
  // considera activos tanto 'pendiente_de_pago' como 'confirmado').
  const slotsDespues = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  ok(
    !slotsDespues.data.slots.includes(slot),
    'el slot recién reservado (confirmado) ya no aparece como disponible'
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) del camino sin seña fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ Camino SIN seña (D2/RN10/HU-09b) verificado: confirmación directa sin pendiente_de_pago.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
