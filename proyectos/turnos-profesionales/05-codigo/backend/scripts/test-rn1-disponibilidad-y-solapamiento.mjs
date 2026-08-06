// Verifica RN1 (un turno solo puede reservarse dentro de un bloque de disponibilidad
// publicado por el profesional para ese servicio) y, de yapa, si RN2 ("dos turnos del mismo
// profesional no pueden solaparse en el tiempo") se sostiene también cuando dos turnos NO
// comparten el mismo instante exacto de inicio (la garantía de BD documentada en
// documento-arquitectura.md §4 es un índice único sobre (profesional_id, inicio) exacto, que
// no cubre solapamientos con horarios de inicio distintos).
// Requiere el servidor corriendo. No depende de otros scripts ni de una DB limpia (usa
// emails únicos por timestamp).
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
    nombre_negocio: 'Negocio RN1',
    email: `admin-rn1-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin RN1',
  });
  assert(registro.status === 201, 'registro de negocio');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio RN1', duracion_min: 60, precio_referencia: 1000 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio (60 min)');
  const servicioId = servicio.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-rn1-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional RN1' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', { email: `prof-rn1-${sello}@test.com`, password: 'prof1234' });
  const profToken = loginProf.data.token;

  const asoc = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioId, requiere_sena: false },
    profToken
  );
  assert(asoc.status === 201, 'asociar servicio al profesional (sin seña)');

  // Publicamos disponibilidad SOLO para un día de la semana puntual, 09:00-11:00 (2 slots de 60 min).
  const diaConDisponibilidad = (new Date().getDay() + 2) % 7; // pasado mañana en día de semana, evita bordes de "hoy"
  const dispo = await req(
    'POST',
    `/profesionales/${profesionalId}/disponibilidad`,
    { servicio_id: servicioId, dia_semana: diaConDisponibilidad, hora_inicio: '09:00', hora_fin: '11:00' },
    profToken
  );
  assert(dispo.status === 201, 'publicar disponibilidad (un solo día de la semana, 09:00-11:00)');

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-rn1-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente RN1',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  const slots = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=14`);
  assert(slots.status === 200 && slots.data.slots.length > 0, 'hay slots calculados dentro de la disponibilidad publicada');
  const slotValido = slots.data.slots[0];

  // --- Control positivo: reservar DENTRO de la disponibilidad publicada debe funcionar ---
  const turnoValido = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: slotValido },
    clienteToken
  );
  ok(turnoValido.status === 201, 'RN1 (control): reservar un slot DENTRO de la disponibilidad publicada es aceptado (201)');

  // --- Negativo 1: mismo horario (09:00) pero un día de la semana SIN disponibilidad publicada ---
  const inicioOtroDia = new Date(new Date(slotValido).getTime() + 24 * 3600_000).toISOString();
  const turnoOtroDia = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: inicioOtroDia },
    clienteToken
  );
  ok(
    turnoOtroDia.status >= 400 && turnoOtroDia.status < 500,
    `RN1: reservar un turno un día de la semana SIN disponibilidad publicada debe rechazarse (4xx) — se obtuvo ${turnoOtroDia.status} ${JSON.stringify(turnoOtroDia.data)}`
  );

  // --- Negativo 2: mismo día de la semana válido, pero horario FUERA del bloque 09:00-11:00 (probamos 15:00) ---
  const inicioFueraDeHorario = new Date(new Date(slotValido).getTime() + 6 * 3600_000).toISOString();
  const turnoFueraDeHorario = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: inicioFueraDeHorario },
    clienteToken
  );
  ok(
    turnoFueraDeHorario.status >= 400 && turnoFueraDeHorario.status < 500,
    `RN1: reservar un turno en un horario fuera del bloque de disponibilidad publicado (mismo día) debe rechazarse (4xx) — se obtuvo ${turnoFueraDeHorario.status} ${JSON.stringify(turnoFueraDeHorario.data)}`
  );

  // --- Bonus RN2: solapamiento con un inicio DISTINTO al de un turno ya activo (mismo profesional) ---
  // turnoValido ya ocupa slotValido..slotValido+60min. Probamos 30 min después del inicio original
  // (se superpone con el turno existente aunque el `inicio` exacto sea distinto).
  const inicioSolapado = new Date(new Date(slotValido).getTime() + 30 * 60_000).toISOString();
  const turnoSolapado = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: inicioSolapado },
    clienteToken
  );
  ok(
    turnoSolapado.status >= 400 && turnoSolapado.status < 500,
    `RN2: dos turnos del mismo profesional que se solapan en el tiempo (distinto inicio exacto) deben rechazarse (4xx) — se obtuvo ${turnoSolapado.status} ${JSON.stringify(turnoSolapado.data)}`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de RN1/RN2 fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ RN1 (disponibilidad publicada) y solapamiento fino de RN2 verificados.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
