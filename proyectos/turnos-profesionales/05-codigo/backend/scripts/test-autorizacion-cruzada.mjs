// Verifica controles de autorización cruzada: un profesional intentando ver/modificar
// recursos de OTRO profesional (D3/RN7/RN9), un cliente intentando cancelar/reprogramar el
// turno de otro cliente, y un administrador intentando administrar recursos de otro negocio.
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

  // ---------- Negocio A, con profesional A y cliente A ----------
  const registroA = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio A (autorización)',
    email: `admin-a-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin A',
  });
  assert(registroA.status === 201, 'registro de negocio A');
  const adminTokenA = registroA.data.token;
  const negocioAId = registroA.data.negocio_id;

  const servicioA = await req(
    'POST',
    `/negocios/${negocioAId}/servicios`,
    { nombre: 'Servicio A', duracion_min: 30, precio_referencia: 500 },
    adminTokenA
  );
  assert(servicioA.status === 201, 'alta de servicio A');
  const servicioAId = servicioA.data.id;

  const profARes = await req(
    'POST',
    `/negocios/${negocioAId}/profesionales`,
    { email: `prof-a-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional A' },
    adminTokenA
  );
  assert(profARes.status === 201, 'alta de profesional A');
  const profesionalAId = profARes.data.id;
  const loginProfA = await req('POST', '/auth/login', { email: `prof-a-${sello}@test.com`, password: 'prof1234' });
  const profTokenA = loginProfA.data.token;

  await req('POST', `/profesionales/${profesionalAId}/servicios`, { servicio_id: servicioAId, requiere_sena: false }, profTokenA);
  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesionalAId}/disponibilidad`,
      { servicio_id: servicioAId, dia_semana: dia, hora_inicio: '08:00', hora_fin: '20:00' },
      profTokenA
    );
  }

  const clienteA = await req('POST', '/auth/registro-cliente', {
    email: `cliente-a-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente A',
  });
  assert(clienteA.status === 201, 'registro de cliente A');
  const clienteTokenA = clienteA.data.token;

  const slotsA = await req('GET', `/profesionales/${profesionalAId}/slots?servicio_id=${servicioAId}`);
  assert(slotsA.status === 200 && slotsA.data.slots.length > 0, 'hay slots para profesional A');
  const turnoDeA = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalAId, servicio_id: servicioAId, inicio: slotsA.data.slots[0] },
    clienteTokenA
  );
  assert(turnoDeA.status === 201, 'cliente A reserva un turno con profesional A');

  // ---------- Negocio B, con profesional B y cliente B (independientes) ----------
  const registroB = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio B (autorización)',
    email: `admin-b-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin B',
  });
  assert(registroB.status === 201, 'registro de negocio B');
  const adminTokenB = registroB.data.token;
  const negocioBId = registroB.data.negocio_id;

  const servicioB = await req(
    'POST',
    `/negocios/${negocioBId}/servicios`,
    { nombre: 'Servicio B', duracion_min: 30, precio_referencia: 500 },
    adminTokenB
  );
  assert(servicioB.status === 201, 'alta de servicio B');
  const servicioBId = servicioB.data.id;

  const profBRes = await req(
    'POST',
    `/negocios/${negocioBId}/profesionales`,
    { email: `prof-b-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional B' },
    adminTokenB
  );
  assert(profBRes.status === 201, 'alta de profesional B');
  const profesionalBId = profBRes.data.id;
  const loginProfB = await req('POST', '/auth/login', { email: `prof-b-${sello}@test.com`, password: 'prof1234' });
  const profTokenB = loginProfB.data.token;

  const clienteB = await req('POST', '/auth/registro-cliente', {
    email: `cliente-b-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente B',
  });
  assert(clienteB.status === 201, 'registro de cliente B');
  const clienteTokenB = clienteB.data.token;

  // ================= Profesional B (o A) intentando acceder a recursos de OTRO profesional =================
  const clientesDeOtro = await req('GET', `/profesionales/${profesionalAId}/clientes`, undefined, profTokenB);
  ok(clientesDeOtro.status === 403, `profesional B no puede ver el listado de clientes de profesional A (403 esperado, obtuvo ${clientesDeOtro.status})`);

  const agendaDeOtro = await req('GET', `/profesionales/${profesionalAId}/turnos`, undefined, profTokenB);
  ok(agendaDeOtro.status === 403, `profesional B no puede ver la agenda de profesional A (403 esperado, obtuvo ${agendaDeOtro.status})`);

  const configurarServicioDeOtro = await req(
    'POST',
    `/profesionales/${profesionalAId}/servicios`,
    { servicio_id: servicioAId, requiere_sena: true, monto_sena: 999 },
    profTokenB
  );
  ok(
    configurarServicioDeOtro.status === 403,
    `profesional B no puede configurar servicios de profesional A (403 esperado, obtuvo ${configurarServicioDeOtro.status})`
  );

  const definirDisponibilidadDeOtro = await req(
    'POST',
    `/profesionales/${profesionalAId}/disponibilidad`,
    { servicio_id: servicioAId, dia_semana: 1, hora_inicio: '10:00', hora_fin: '11:00' },
    profTokenB
  );
  ok(
    definirDisponibilidadDeOtro.status === 403,
    `profesional B no puede definir disponibilidad de profesional A (403 esperado, obtuvo ${definirDisponibilidadDeOtro.status})`
  );

  const bloquearAgendaDeOtro = await req(
    'POST',
    `/profesionales/${profesionalAId}/excepciones`,
    { inicio: new Date().toISOString(), fin: new Date(Date.now() + 3600_000).toISOString() },
    profTokenB
  );
  ok(
    bloquearAgendaDeOtro.status === 403,
    `profesional B no puede bloquear la agenda de profesional A (403 esperado, obtuvo ${bloquearAgendaDeOtro.status})`
  );

  // ================= D3/RN7: historial privado por profesional =================
  // El cliente A tiene un turno con el profesional A. El profesional B (que nunca lo atendió)
  // no debe ver ese historial — la API lo filtra devolviendo una lista VACÍA (200), no un error,
  // porque la query ya está acotada por el profesional_id del JWT (ver clientes.ts).
  const clienteAUsuarioId = (
    await req('GET', `/profesionales/${profesionalAId}/clientes`, undefined, profTokenA)
  ).data?.[0]?.id;
  ok(!!clienteAUsuarioId, 'precondición: profesional A puede ver a cliente A en su propio listado de clientes');

  if (clienteAUsuarioId) {
    const historialParaOtroProfesional = await req(
      'GET',
      `/clientes/${clienteAUsuarioId}/historial`,
      undefined,
      profTokenB
    );
    ok(
      historialParaOtroProfesional.status === 200 && Array.isArray(historialParaOtroProfesional.data) && historialParaOtroProfesional.data.length === 0,
      `D3/RN7: profesional B NO debe ver historial de un cliente atendido solo por profesional A (200 + lista vacía esperado, obtuvo ${historialParaOtroProfesional.status} ${JSON.stringify(historialParaOtroProfesional.data)})`
    );

    const historialParaProfesionalCorrecto = await req(
      'GET',
      `/clientes/${clienteAUsuarioId}/historial`,
      undefined,
      profTokenA
    );
    ok(
      historialParaProfesionalCorrecto.status === 200 && historialParaProfesionalCorrecto.data.length >= 1,
      'D3/RN7 (control): profesional A SÍ ve el historial del cliente que él mismo atendió'
    );
  }

  // ================= Cliente B intentando cancelar/reprogramar el turno de Cliente A =================
  const cancelarTurnoAjeno = await req('PATCH', `/turnos/${turnoDeA.data.id}/cancelar`, {}, clienteTokenB);
  ok(
    cancelarTurnoAjeno.status === 403,
    `cliente B no puede cancelar un turno de cliente A (403 esperado, obtuvo ${cancelarTurnoAjeno.status})`
  );

  const reprogramarTurnoAjeno = await req(
    'PATCH',
    `/turnos/${turnoDeA.data.id}/reprogramar`,
    { nuevo_inicio: new Date(Date.now() + 48 * 3600_000).toISOString() },
    clienteTokenB
  );
  ok(
    reprogramarTurnoAjeno.status === 403,
    `cliente B no puede reprogramar un turno de cliente A (403 esperado, obtuvo ${reprogramarTurnoAjeno.status})`
  );

  // ================= Administrador de Negocio A intentando administrar recursos de Negocio B =================
  const altaServicioEnOtroNegocio = await req(
    'POST',
    `/negocios/${negocioBId}/servicios`,
    { nombre: 'Intruso', duracion_min: 30 },
    adminTokenA
  );
  ok(
    altaServicioEnOtroNegocio.status === 403,
    `admin de negocio A no puede dar de alta un servicio en negocio B (403 esperado, obtuvo ${altaServicioEnOtroNegocio.status})`
  );

  const altaProfesionalEnOtroNegocio = await req(
    'POST',
    `/negocios/${negocioBId}/profesionales`,
    { email: `intruso-${sello}@test.com`, password: 'x12345678', nombre: 'Intruso' },
    adminTokenA
  );
  ok(
    altaProfesionalEnOtroNegocio.status === 403,
    `admin de negocio A no puede dar de alta un profesional en negocio B (403 esperado, obtuvo ${altaProfesionalEnOtroNegocio.status})`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de autorización cruzada fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ Controles de autorización cruzada (profesional↔profesional, cliente↔cliente, negocio↔negocio, D3/RN7) verificados.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
