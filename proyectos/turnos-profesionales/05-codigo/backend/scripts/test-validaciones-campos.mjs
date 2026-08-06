// Verifica validaciones de campos faltantes/mal formados en los endpoints principales
// (deben responder 400, no aceptar el pedido ni romper con un 500), y casos básicos de
// autenticación mal formada (sin token / token basura / rol equivocado).
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

  // ---------- Setup mínimo para poder probar validaciones de endpoints autenticados ----------
  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio Validaciones',
    email: `admin-val-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin Validaciones',
  });
  assert(registro.status === 201, 'registro de negocio (setup)');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio Validaciones', duracion_min: 30, precio_referencia: 500 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio (setup)');
  const servicioId = servicio.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-val-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional Validaciones' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional (setup)');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', { email: `prof-val-${sello}@test.com`, password: 'prof1234' });
  const profToken = loginProf.data.token;

  await req('POST', `/profesionales/${profesionalId}/servicios`, { servicio_id: servicioId, requiere_sena: false }, profToken);

  // Disponibilidad amplia todos los días (necesaria para que la reserva de "turno de setup"
  // usada más abajo, para probar reprogramar con campos inválidos, caiga dentro de un slot
  // válido — desde el fix de RN1/DEF-01, POST /turnos exige que `inicio` esté alineado a la
  // grilla de disponibilidad publicada, ver turnos.ts).
  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesionalId}/disponibilidad`,
      { servicio_id: servicioId, dia_semana: dia, hora_inicio: '00:00', hora_fin: '23:30' },
      profToken
    );
  }

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-val-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente Validaciones',
  });
  assert(cliente.status === 201, 'registro de cliente (setup)');
  const clienteToken = cliente.data.token;

  // ---------- Auth: registro-negocio con campos faltantes ----------
  const rn1 = await req('POST', '/auth/registro-negocio', { email: `x-${sello}@test.com`, password: 'x', nombre_admin: 'X' });
  ok(rn1.status === 400, `registro-negocio sin nombre_negocio debe responder 400 (obtuvo ${rn1.status})`);

  const rn2 = await req('POST', '/auth/registro-negocio', { nombre_negocio: 'X', password: 'x', nombre_admin: 'X' });
  ok(rn2.status === 400, `registro-negocio sin email debe responder 400 (obtuvo ${rn2.status})`);

  // ---------- Auth: registro-cliente con campos faltantes ----------
  const rc1 = await req('POST', '/auth/registro-cliente', { password: 'cliente1234', nombre: 'X' });
  ok(rc1.status === 400, `registro-cliente sin email debe responder 400 (obtuvo ${rc1.status})`);

  const rc2 = await req('POST', '/auth/registro-cliente', { email: `y-${sello}@test.com`, nombre: 'X' });
  ok(rc2.status === 400, `registro-cliente sin password debe responder 400 (obtuvo ${rc2.status})`);

  // ---------- Auth: login con credenciales incompletas/incorrectas ----------
  const loginSinPassword = await req('POST', '/auth/login', { email: `cliente-val-${sello}@test.com` });
  ok(
    loginSinPassword.status === 401,
    `login sin password no debe autenticar (401 esperado, sin 500) — obtuvo ${loginSinPassword.status}`
  );

  const loginInexistente = await req('POST', '/auth/login', { email: 'no-existe@test.com', password: 'x' });
  ok(loginInexistente.status === 401, `login con email inexistente debe responder 401 (obtuvo ${loginInexistente.status})`);

  // ---------- Negocios: alta de servicio/profesional con campos faltantes ----------
  const servSinNombre = await req('POST', `/negocios/${negocioId}/servicios`, { duracion_min: 30 }, adminToken);
  ok(servSinNombre.status === 400, `alta de servicio sin nombre debe responder 400 (obtuvo ${servSinNombre.status})`);

  const servSinDuracion = await req('POST', `/negocios/${negocioId}/servicios`, { nombre: 'Y' }, adminToken);
  ok(servSinDuracion.status === 400, `alta de servicio sin duracion_min debe responder 400 (obtuvo ${servSinDuracion.status})`);

  const profSinEmail = await req('POST', `/negocios/${negocioId}/profesionales`, { password: 'x', nombre: 'Y' }, adminToken);
  ok(profSinEmail.status === 400, `alta de profesional sin email debe responder 400 (obtuvo ${profSinEmail.status})`);

  // ---------- Profesionales: servicios/disponibilidad/excepciones con campos faltantes ----------
  const asocSinServicio = await req('POST', `/profesionales/${profesionalId}/servicios`, {}, profToken);
  ok(asocSinServicio.status === 400, `asociar servicio sin servicio_id debe responder 400 (obtuvo ${asocSinServicio.status})`);

  const dispoSinHoras = await req(
    'POST',
    `/profesionales/${profesionalId}/disponibilidad`,
    { servicio_id: servicioId, dia_semana: 1 },
    profToken
  );
  ok(dispoSinHoras.status === 400, `disponibilidad sin hora_inicio/hora_fin debe responder 400 (obtuvo ${dispoSinHoras.status})`);

  const excepcionSinFechas = await req('POST', `/profesionales/${profesionalId}/excepciones`, {}, profToken);
  ok(excepcionSinFechas.status === 400, `excepción sin inicio/fin debe responder 400 (obtuvo ${excepcionSinFechas.status})`);

  // ---------- Slots: sin servicio_id ----------
  const slotsSinServicio = await req('GET', `/profesionales/${profesionalId}/slots`);
  ok(slotsSinServicio.status === 400, `/slots sin servicio_id debe responder 400 (obtuvo ${slotsSinServicio.status})`);

  // ---------- Turnos: campos faltantes ----------
  const turnoSinCampos = await req('POST', '/turnos', {}, clienteToken);
  ok(turnoSinCampos.status === 400, `POST /turnos sin campos debe responder 400 (obtuvo ${turnoSinCampos.status})`);

  const turnoSinInicio = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId },
    clienteToken
  );
  ok(turnoSinInicio.status === 400, `POST /turnos sin inicio debe responder 400 (obtuvo ${turnoSinInicio.status})`);

  // ---------- Turnos: inicio MAL FORMADO (no es una fecha válida) ----------
  const turnoFechaInvalida = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: 'esto-no-es-una-fecha' },
    clienteToken
  );
  ok(
    turnoFechaInvalida.status >= 400 && turnoFechaInvalida.status < 500,
    `POST /turnos con 'inicio' mal formado debe responder 4xx (validación), NO 500 — se obtuvo ${turnoFechaInvalida.status} ${JSON.stringify(turnoFechaInvalida.data)}`
  );

  // ---------- Reprogramar: sin nuevo_inicio, y con nuevo_inicio mal formado ----------
  // El `inicio` tiene que ser un slot REAL de la grilla (desde el fix de RN1/DEF-01, POST
  // /turnos exige alineación exacta a la disponibilidad publicada, ver turnos.ts) — se pide
  // vía /slots en vez de calcular un timestamp arbitrario "a mano".
  const slotsParaSetup = await req(
    'GET',
    `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&desde=${encodeURIComponent(new Date(Date.now() + 6 * 3600_000).toISOString())}&dias=2`
  );
  const inicioValido = slotsParaSetup.data?.slots?.[0];
  const turnoValido = inicioValido
    ? await req(
        'POST',
        '/turnos',
        { profesional_id: profesionalId, servicio_id: servicioId, inicio: inicioValido },
        clienteToken
      )
    : { status: 0, data: null };
  if (turnoValido.status === 201) {
    const reprogSinNuevoInicio = await req('PATCH', `/turnos/${turnoValido.data.id}/reprogramar`, {}, clienteToken);
    ok(
      reprogSinNuevoInicio.status === 400,
      `reprogramar sin nuevo_inicio debe responder 400 (obtuvo ${reprogSinNuevoInicio.status})`
    );

    const reprogFechaInvalida = await req(
      'PATCH',
      `/turnos/${turnoValido.data.id}/reprogramar`,
      { nuevo_inicio: 'tampoco-es-una-fecha' },
      clienteToken
    );
    ok(
      reprogFechaInvalida.status >= 400 && reprogFechaInvalida.status < 500,
      `reprogramar con nuevo_inicio mal formado debe responder 4xx, NO 500 — se obtuvo ${reprogFechaInvalida.status} ${JSON.stringify(reprogFechaInvalida.data)}`
    );
  } else {
    fallas++;
    console.log('FALLA: no se pudo crear el turno de setup para probar reprogramar con campos inválidos');
  }

  // ---------- Autenticación mal formada ----------
  const sinToken = await req('GET', '/turnos/mios');
  ok(sinToken.status === 401, `endpoint autenticado sin token debe responder 401 (obtuvo ${sinToken.status})`);

  const tokenBasura = await req('GET', '/turnos/mios', undefined, 'esto-no-es-un-jwt');
  ok(tokenBasura.status === 401, `token mal formado/garbage debe responder 401 (obtuvo ${tokenBasura.status})`);

  const rolEquivocadoCliente = await req('GET', `/profesionales/${profesionalId}/clientes`, undefined, clienteToken);
  ok(
    rolEquivocadoCliente.status === 403,
    `un cliente no puede acceder a un endpoint solo-profesional (403 esperado, obtuvo ${rolEquivocadoCliente.status})`
  );

  const rolEquivocadoProfesional = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: new Date(Date.now() + 7 * 3600_000).toISOString() },
    profToken
  );
  ok(
    rolEquivocadoProfesional.status === 403,
    `un profesional no puede reservar un turno (endpoint solo-cliente, 403 esperado, obtuvo ${rolEquivocadoProfesional.status})`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de validación de campos fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ Validaciones de campos y autenticación mal formada verificadas.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
