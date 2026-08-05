// Verifica RN2 bajo concurrencia REAL (no secuencial): dos clientes piden el mismo slot al
// mismo tiempo con Promise.all — solo uno debe obtener 201, el otro debe recibir 409.
// Requiere el servidor corriendo y reutiliza el negocio/profesional/servicio creados por
// smoke-test.mjs (ejecutar smoke-test.mjs primero).
const BASE = 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => null) };
}

async function main() {
  const negocios = await req('GET', '/negocios');
  const negocioId = negocios.data[0].id;
  const servicios = await req('GET', `/negocios/${negocioId}/servicios`);
  const servicioId = servicios.data[0].id;

  // Necesitamos el profesional_id; lo obtenemos vía login del profesional de prueba.
  const login = await req('POST', '/auth/login', { email: 'garcia@garcia.test', password: 'prof1234' });
  const profesionalId = JSON.parse(Buffer.from(login.data.token.split('.')[1], 'base64url').toString()).profesional_id;

  const slots = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  const slotLibre = slots.data.slots.find(Boolean);
  if (!slotLibre) throw new Error('No hay slots libres para probar concurrencia — correr smoke-test.mjs primero en una DB limpia');

  const clienteA = await req('POST', '/auth/registro-cliente', {
    email: `concurrencia-a-${Date.now()}@test.com`,
    password: 'x12345678',
    nombre: 'Cliente Concurrente A',
  });
  const clienteB = await req('POST', '/auth/registro-cliente', {
    email: `concurrencia-b-${Date.now()}@test.com`,
    password: 'x12345678',
    nombre: 'Cliente Concurrente B',
  });

  console.log(`Disparando 2 reservas SIMULTÁNEAS al slot ${slotLibre} ...`);
  const [rA, rB] = await Promise.all([
    req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: slotLibre }, clienteA.data.token),
    req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: slotLibre }, clienteB.data.token),
  ]);

  console.log('Cliente A ->', rA.status, rA.data);
  console.log('Cliente B ->', rB.status, rB.data);

  const exitosas = [rA, rB].filter((r) => r.status === 201).length;
  const conflictos = [rA, rB].filter((r) => r.status === 409).length;

  if (exitosas === 1 && conflictos === 1) {
    console.log('\n✅ RN2 verificada bajo concurrencia real: exactamente 1 reserva exitosa, 1 rechazada por conflicto.');
  } else {
    console.error(`\n❌ FALLÓ la garantía anti-doble-reserva: ${exitosas} exitosas, ${conflictos} conflictos (se esperaba 1 y 1).`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
