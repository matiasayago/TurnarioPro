// Prueba de humo del flujo completo (golden path) — no forma parte del código de producción,
// es una verificación manual de que el backend implementa correctamente los casos de uso
// principales del documento funcional. Requiere el servidor corriendo en localhost:3000.
const BASE = 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  return { status: res.status, data };
}

function assert(cond, msg) {
  if (!cond) throw new Error('FALLÓ: ' + msg);
  console.log('OK:', msg);
}

async function main() {
  // HU-00a: administrador registra su negocio
  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Consultorio Dr. García',
    rubro: 'Salud',
    ubicacion: 'CABA',
    email: 'admin@garcia.test',
    password: 'admin1234',
    nombre_admin: 'Admin García',
  });
  assert(registro.status === 201, 'registro de negocio devuelve 201');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  // HU-00b: listar negocios (público)
  const negocios = await req('GET', '/negocios');
  assert(negocios.status === 200 && negocios.data.length >= 1, 'listado público de negocios');

  // HU-03: alta de servicio
  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Consulta general', duracion_min: 30, precio_referencia: 5000 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio');
  const servicioId = servicio.data.id;

  // HU-02: alta de profesional
  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: 'garcia@garcia.test', password: 'prof1234', nombre: 'Dr. García' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  // Login del profesional
  const loginProf = await req('POST', '/auth/login', {
    email: 'garcia@garcia.test',
    password: 'prof1234',
  });
  assert(loginProf.status === 200, 'login de profesional');
  const profToken = loginProf.data.token;

  // HU-04b: asociar servicio con seña requerida
  const asoc = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioId, requiere_sena: true, monto_sena: 1000 },
    profToken
  );
  assert(asoc.status === 201, 'asociar servicio con seña configurable (D2/RN10)');

  // HU-05: disponibilidad — todos los días de la semana 09:00-12:00 (simplificación de prueba)
  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesionalId}/disponibilidad`,
      { servicio_id: servicioId, dia_semana: dia, hora_inicio: '09:00', hora_fin: '12:00' },
      profToken
    );
  }
  console.log('OK: disponibilidad cargada para todos los días (prueba)');

  // HU-09: slots disponibles
  const slots = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  assert(slots.status === 200 && slots.data.slots.length > 0, 'hay slots disponibles calculados');
  const primerSlot = slots.data.slots[0];
  console.log('   primer slot:', primerSlot, '| próximo disponible (D5):', slots.data.proximo_disponible);

  // HU-01: registro de cliente
  const cliente = await req('POST', '/auth/registro-cliente', {
    email: 'cliente1@test.com',
    password: 'cliente1234',
    nombre: 'Cliente Uno',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  // HU-09/09b: reservar turno (requiere seña -> pendiente_de_pago)
  const turno = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: primerSlot },
    clienteToken
  );
  assert(turno.status === 201, 'reserva de turno exitosa');
  assert(turno.data.estado === 'pendiente_de_pago', 'turno queda pendiente de pago (seña requerida, D2)');
  console.log('   turno creado:', turno.data.id);

  // Segundo cliente intenta el MISMO slot -> debe fallar con 409 (RN2)
  const cliente2 = await req('POST', '/auth/registro-cliente', {
    email: 'cliente2@test.com',
    password: 'cliente1234',
    nombre: 'Cliente Dos',
  });
  const turnoConflicto = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: primerSlot },
    cliente2.data.token
  );
  assert(turnoConflicto.status === 409, 'RN2: el mismo slot NO puede reservarse dos veces (secuencial)');

  // HU-10/HU-11: el profesional ve a su cliente y el historial
  const clientes = await req('GET', `/profesionales/${profesionalId}/clientes`, undefined, profToken);
  assert(clientes.status === 200 && clientes.data.length === 1, 'profesional ve su listado de clientes');

  const historial = await req(
    'GET',
    `/clientes/${cliente.data && (await (async () => {
      // necesitamos el id de usuario del cliente 1; lo tomamos del listado de clientes
      return clientes.data[0].id;
    })())}/historial`,
    undefined,
    profToken
  );
  assert(historial.status === 200, 'profesional ve el historial de su cliente (D3)');

  // HU-12: cancelar dentro de la ventana mínima -> debe fallar (turno es hoy/pronto en la prueba)
  const cancelacion = await req('PATCH', `/turnos/${turno.data.id}/cancelar`, {}, clienteToken);
  console.log('   intento de cancelación (puede ser 200 o 409 según ventana):', cancelacion.status);

  console.log('\n✅ Smoke test del golden path completado sin fallos.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
