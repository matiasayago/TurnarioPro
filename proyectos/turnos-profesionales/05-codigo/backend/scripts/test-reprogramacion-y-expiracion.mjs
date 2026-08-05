// Verifica HU-13 (reprogramación) y la expiración automática de pendiente_de_pago.
// Requiere el servidor corriendo con EXPIRACION_PAGO_MIN=0 (para no esperar 15 min reales) y
// VENTANA_CANCELACION_MIN=0 (para poder reprogramar turnos creados "ahora" en la prueba).
const BASE = 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, data: await res.json().catch(() => null) };
}

function assert(cond, msg) {
  if (!cond) throw new Error('FALLÓ: ' + msg);
  console.log('OK:', msg);
}

async function main() {
  const seed = await req('POST', '/dev/seed');
  assert(seed.status === 201, 'seed de datos de ejemplo');
  const { profesional, servicio, cliente } = seed.data;

  const login = await req('POST', '/auth/login', { email: cliente.email, password: cliente.password });
  const token = login.data.token;

  const slots1 = await req('GET', `/profesionales/${profesional.id}/slots?servicio_id=${servicio.id}`);
  const slotOriginal = slots1.data.slots[0];
  const slotNuevo = slots1.data.slots[1];

  // --- HU-13: reprogramación ---
  const turno = await req('POST', '/turnos', { profesional_id: profesional.id, servicio_id: servicio.id, inicio: slotOriginal }, token);
  assert(turno.status === 201, 'turno original creado');
  const turnoOriginalId = turno.data.id;

  const reprog = await req('PATCH', `/turnos/${turnoOriginalId}/reprogramar`, { nuevo_inicio: slotNuevo }, token);
  assert(reprog.status === 200, 'reprogramación exitosa (200)');
  assert(reprog.data.id !== turnoOriginalId, 'la reprogramación crea un turno nuevo (id distinto)');
  assert(reprog.data.estado === 'pendiente_de_pago', 'el turno reprogramado conserva el estado de pago (D2)');

  const misTurnos = await req('GET', '/turnos/mios', undefined, token);
  const original = misTurnos.data.find((t) => t.id === turnoOriginalId);
  assert(original.estado === 'reprogramado', 'el turno original queda marcado reprogramado, no desaparece (auditoría)');

  // El slot original debería estar libre de nuevo (el turno viejo salió del índice único).
  const slotsDespues = await req('GET', `/profesionales/${profesional.id}/slots?servicio_id=${servicio.id}`);
  assert(slotsDespues.data.slots.includes(slotOriginal), 'RN2: el slot original quedó libre tras reprogramar');

  // Reprogramar a un slot que otro cliente ya tomó -> 409.
  const cliente2 = await req('POST', '/auth/registro-cliente', { email: `otro-${Date.now()}@test.com`, password: 'x12345678', nombre: 'Otro' });
  const slotOcupado = reprog.data && slotNuevo; // el nuevo turno ya ocupa slotNuevo
  const turnoIntruso = await req('POST', '/turnos', { profesional_id: profesional.id, servicio_id: servicio.id, inicio: slots1.data.slots[2] }, cliente2.data.token);
  const reprogConflicto = await req('PATCH', `/turnos/${turnoIntruso.data.id}/reprogramar`, { nuevo_inicio: slotOcupado }, cliente2.data.token);
  assert(reprogConflicto.status === 409, 'RN2: no se puede reprogramar a un slot ya ocupado por otro turno');

  // --- Expiración automática ---
  const forzado = await req('POST', '/dev/forzar-expiracion');
  assert(forzado.status === 200, 'job de expiración corrido manualmente');
  console.log(`   turnos expirados por el job: ${forzado.data.turnos_expirados}`);
  assert(forzado.data.turnos_expirados >= 1, 'al menos el turno reprogramado (pendiente_de_pago) expiró');

  const misTurnosFinal = await req('GET', '/turnos/mios', undefined, token);
  const reprogramadoFinal = misTurnosFinal.data.find((t) => t.id === reprog.data.id);
  assert(reprogramadoFinal.estado === 'cancelado', 'el turno pendiente_de_pago expiró a cancelado automáticamente');

  console.log('\n✅ Reprogramación + expiración automática verificadas.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
