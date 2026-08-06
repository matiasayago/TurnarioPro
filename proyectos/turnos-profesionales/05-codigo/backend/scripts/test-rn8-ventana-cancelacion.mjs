// Verifica RN8 (cancelaciones y reprogramaciones DENTRO de la ventana mínima deben
// rechazarse — el flujo automático de la app solo las permite FUERA de esa ventana) en ambas
// direcciones y para ambas operaciones (cancelar y reprogramar). Los scripts existentes solo
// cubren el caso ambiguo (smoke-test.mjs, sin assert) o requieren arrancar el servidor con
// VENTANA_CANCELACION_MIN=0 (test-reprogramacion-y-expiracion.mjs) — este script funciona
// contra el servidor real corriendo con la ventana por DEFECTO (120 min, ver turnos.ts),
// controlando la cercanía de los slots vía el parámetro `desde` de /slots en lugar de
// depender de variables de entorno especiales.
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
    nombre_negocio: 'Negocio RN8',
    email: `admin-rn8-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin RN8',
  });
  assert(registro.status === 201, 'registro de negocio');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio RN8', duracion_min: 30, precio_referencia: 500 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio (30 min)');
  const servicioId = servicio.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-rn8-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional RN8' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', { email: `prof-rn8-${sello}@test.com`, password: 'prof1234' });
  const profToken = loginProf.data.token;

  const asoc = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioId, requiere_sena: false },
    profToken
  );
  assert(asoc.status === 201, 'asociar servicio (sin seña, para simplificar)');

  // Disponibilidad amplia (00:00-23:30) todos los días para poder obtener tanto un slot
  // "cercano" (dentro de la ventana mínima de 120 min por defecto) como uno "lejano"
  // (varios días después) sin depender de la hora del día en que corra este script.
  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesionalId}/disponibilidad`,
      { servicio_id: servicioId, dia_semana: dia, hora_inicio: '00:00', hora_fin: '23:30' },
      profToken
    );
  }

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-rn8-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente RN8',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  const slotsCercanos = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=1`);
  assert(slotsCercanos.status === 200 && slotsCercanos.data.slots.length >= 2, 'hay al menos 2 slots cercanos');
  const [nearSlot1, nearSlot2] = slotsCercanos.data.slots;

  const desdeLejos = new Date(Date.now() + 4 * 3600_000).toISOString(); // +4h, fuera de la ventana de 120 min
  const slotsLejanos = await req(
    'GET',
    `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&desde=${encodeURIComponent(desdeLejos)}&dias=3`
  );
  assert(slotsLejanos.status === 200 && slotsLejanos.data.slots.length >= 4, 'hay al menos 4 slots lejanos (+4h)');
  const [farSlot1, farSlot2, farSlot3, farSlot4] = slotsLejanos.data.slots;

  // --- Caso 1: cancelar DENTRO de la ventana mínima -> debe rechazarse (409) ---
  const turno1 = await req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: nearSlot1 }, clienteToken);
  assert(turno1.status === 201, 'turno cercano #1 creado (para probar cancelación rechazada)');
  const cancelCercano = await req('PATCH', `/turnos/${turno1.data.id}/cancelar`, {}, clienteToken);
  ok(
    cancelCercano.status === 409,
    `RN8: cancelar un turno DENTRO de la ventana mínima debe rechazarse (409) — se obtuvo ${cancelCercano.status} ${JSON.stringify(cancelCercano.data)}`
  );

  // --- Caso 2: reprogramar DENTRO de la ventana mínima -> debe rechazarse (409) ---
  const turno2 = await req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: nearSlot2 }, clienteToken);
  assert(turno2.status === 201, 'turno cercano #2 creado (para probar reprogramación rechazada)');
  const reprogCercano = await req('PATCH', `/turnos/${turno2.data.id}/reprogramar`, { nuevo_inicio: farSlot1 }, clienteToken);
  ok(
    reprogCercano.status === 409,
    `RN8: reprogramar un turno DENTRO de la ventana mínima debe rechazarse (409) — se obtuvo ${reprogCercano.status} ${JSON.stringify(reprogCercano.data)}`
  );

  // --- Caso 3: cancelar FUERA de la ventana mínima -> debe aceptarse (200) ---
  const turno3 = await req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: farSlot2 }, clienteToken);
  assert(turno3.status === 201, 'turno lejano #1 creado (para probar cancelación aceptada)');
  const cancelLejano = await req('PATCH', `/turnos/${turno3.data.id}/cancelar`, {}, clienteToken);
  ok(
    cancelLejano.status === 200,
    `RN8: cancelar un turno FUERA de la ventana mínima debe aceptarse (200) — se obtuvo ${cancelLejano.status} ${JSON.stringify(cancelLejano.data)}`
  );

  // --- Caso 4: reprogramar FUERA de la ventana mínima -> debe aceptarse (200) ---
  const turno4 = await req('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio: farSlot3 }, clienteToken);
  assert(turno4.status === 201, 'turno lejano #2 creado (para probar reprogramación aceptada)');
  const reprogLejano = await req('PATCH', `/turnos/${turno4.data.id}/reprogramar`, { nuevo_inicio: farSlot4 }, clienteToken);
  ok(
    reprogLejano.status === 200,
    `RN8: reprogramar un turno FUERA de la ventana mínima debe aceptarse (200) — se obtuvo ${reprogLejano.status} ${JSON.stringify(reprogLejano.data)}`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de RN8 fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ RN8 (ventana mínima de cancelación/reprogramación) verificada en ambas direcciones.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
