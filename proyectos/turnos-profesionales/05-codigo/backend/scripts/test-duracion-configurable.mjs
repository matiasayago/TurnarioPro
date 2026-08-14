// Verifica D10 (amenda RN3 — ver modelo-datos.md §2quater / documento-funcional.md D10): la
// duración general que el profesional configura (`profesional.duracion_cita_min`) reemplaza
// SIEMPRE la duración del servicio para calcular sus turnos — en la grilla de slots
// (GET /profesionales/:id/slots), al reservar (POST /turnos) y al reprogramar
// (PATCH /turnos/:id/reprogramar, mismo gap encontrado por DBA en el otro lugar del código) —
// y que el fallback es reversible: `duracion_cita_min: null` vuelve a usar la duración del
// servicio, no solo que el override funcione.
// Requiere el servidor corriendo. No depende de otros scripts (emails únicos por timestamp).
const BASE = 'http://localhost:3000';

async function req(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
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

/** Paso mínimo (minutos) entre slots consecutivos de la grilla devuelta. El salto entre dos
 *  posiciones del MISMO bloque de disponibilidad es siempre exactamente la duración efectiva
 *  usada para calcularlo; los saltos entre días son de varias horas. Tomar el mínimo entre TODOS
 *  los pares consecutivos (ordenados) identifica el paso real sin asumir en qué posición del
 *  array cae el límite de un día — robusto sin importar la hora en que corra este script. */
function pasoMinimoEntreSlots(slotsIso) {
  const tiempos = slotsIso.map((s) => new Date(s).getTime()).sort((a, b) => a - b);
  let minDelta = Infinity;
  for (let i = 1; i < tiempos.length; i++) {
    const delta = (tiempos[i] - tiempos[i - 1]) / 60_000;
    if (delta > 0 && delta < minDelta) minDelta = delta;
  }
  return minDelta;
}

/** Duración real (minutos) de un turno persistido, a partir de sus columnas `inicio`/`fin`. */
function minutosDuracion(turno) {
  return (new Date(turno.fin).getTime() - new Date(turno.inicio).getTime()) / 60_000;
}

async function main() {
  const sello = Date.now();

  // --- Setup: negocio, servicio de 30 min, profesional, cliente ---
  const registro = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio Duración Configurable',
    email: `admin-dur-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin Duración',
  });
  assert(registro.status === 201, 'registro de negocio');
  const adminToken = registro.data.token;
  const negocioId = registro.data.negocio_id;

  const servicio = await req(
    'POST',
    `/negocios/${negocioId}/servicios`,
    { nombre: 'Servicio 30min', duracion_min: 30, precio_referencia: 1000 },
    adminToken
  );
  assert(servicio.status === 201, 'alta de servicio (30 min)');
  const servicioId = servicio.data.id;

  const profResp = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-dur-${sello}@test.com`, password: 'prof1234', nombre: 'Profesional Duración' },
    adminToken
  );
  assert(profResp.status === 201, 'alta de profesional');
  const profesionalId = profResp.data.id;

  const loginProf = await req('POST', '/auth/login', { email: `prof-dur-${sello}@test.com`, password: 'prof1234' });
  assert(loginProf.status === 200, 'login de profesional');
  const profToken = loginProf.data.token;

  const asoc = await req(
    'POST',
    `/profesionales/${profesionalId}/servicios`,
    { servicio_id: servicioId, requiere_sena: false },
    profToken
  );
  assert(asoc.status === 201, 'asociar servicio al profesional (sin seña, para simplificar)');

  // Bloque 09:00-12:00 (180 min) todos los días: divide exacto tanto para 30 min (6 slots/día)
  // como para 45 min (4 slots/día), sin dejar resto de grilla desperdiciado en ninguno de los dos casos.
  for (let dia = 0; dia <= 6; dia++) {
    const dispo = await req(
      'POST',
      `/profesionales/${profesionalId}/disponibilidad`,
      { servicio_id: servicioId, dia_semana: dia, hora_inicio: '09:00', hora_fin: '12:00' },
      profToken
    );
    assert(dispo.status === 201, `publicar disponibilidad día ${dia}`);
  }

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-dur-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente Duración',
  });
  assert(cliente.status === 201, 'registro de cliente');
  const clienteToken = cliente.data.token;

  // --- Caso 1 (control): SIN duracion_cita_min configurada -> se usa la duración del servicio ---
  const slots1 = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=14`);
  assert(slots1.status === 200 && slots1.data.slots.length >= 2, 'hay slots calculados (control, sin override)');
  const paso1 = pasoMinimoEntreSlots(slots1.data.slots);
  ok(
    paso1 === 30,
    `control: sin duracion_cita_min configurada, la grilla usa la duración del servicio (30 min) — paso obtenido: ${paso1}`
  );

  const turno1 = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: slots1.data.slots[0] },
    clienteToken
  );
  assert(turno1.status === 201, 'control: reserva de turno sin override');
  const misTurnos1 = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turno1Persistido = misTurnos1.data.find((t) => t.id === turno1.data.id);
  ok(
    !!turno1Persistido && minutosDuracion(turno1Persistido) === 30,
    `control: el turno persistido dura 30 min (duración del servicio) — obtuvo ${turno1Persistido && minutosDuracion(turno1Persistido)}`
  );

  // --- Caso 2: el profesional configura duracion_cita_min = 45 (D10, vía el endpoint nuevo) ---
  const config45 = await req(
    'PATCH',
    `/profesionales/${profesionalId}/configuracion`,
    { duracion_cita_min: 45 },
    profToken
  );
  ok(
    config45.status === 200 && config45.data.duracion_cita_min === 45,
    `configurar duracion_cita_min=45 responde 200 con el valor guardado — obtuvo ${config45.status} ${JSON.stringify(config45.data)}`
  );

  const slots2 = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=14`);
  assert(slots2.status === 200 && slots2.data.slots.length >= 2, 'hay slots calculados (con override de 45 min)');
  const paso2 = pasoMinimoEntreSlots(slots2.data.slots);
  ok(
    paso2 === 45,
    `D10: con duracion_cita_min=45 configurada, la grilla usa 45 min (NO los 30 min del servicio) — paso obtenido: ${paso2}`
  );

  const turno2 = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: slots2.data.slots[0] },
    clienteToken
  );
  assert(turno2.status === 201, 'reserva de turno (servicio de 30 min) con override de 45 min activo');
  const misTurnos2 = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turno2Persistido = misTurnos2.data.find((t) => t.id === turno2.data.id);
  ok(
    !!turno2Persistido && minutosDuracion(turno2Persistido) === 45,
    `D10: el turno reservado con un servicio de 30 min persiste con 45 min (duración del profesional) — obtuvo ${turno2Persistido && minutosDuracion(turno2Persistido)}`
  );

  // --- Caso 3: reprogramar ese turno también debe usar los 45 min (mismo override, no la duración del servicio) ---
  const slotsParaReprogramar = await req(
    'GET',
    `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=14`
  );
  assert(
    slotsParaReprogramar.status === 200 && slotsParaReprogramar.data.slots.length >= 1,
    'hay un slot libre distinto disponible para reprogramar'
  );
  const nuevoSlot = slotsParaReprogramar.data.slots[0];
  const reprog = await req(
    'PATCH',
    `/turnos/${turno2.data.id}/reprogramar`,
    { nuevo_inicio: nuevoSlot },
    clienteToken
  );
  ok(
    reprog.status === 200,
    `reprogramar el turno con override de 45 min activo responde 200 — obtuvo ${reprog.status} ${JSON.stringify(reprog.data)}`
  );
  const misTurnos3 = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turnoReprogramado = misTurnos3.data.find((t) => t.id === reprog.data.id);
  ok(
    !!turnoReprogramado && minutosDuracion(turnoReprogramado) === 45,
    `D10 (hallazgo DBA — mismo gap en PATCH /:id/reprogramar): el turno reprogramado también usa los 45 min del profesional, no los 30 del servicio — obtuvo ${turnoReprogramado && minutosDuracion(turnoReprogramado)}`
  );

  // --- Caso 4: el profesional revierte a null -> vuelve a usar la duración del servicio (30 min) ---
  const configNull = await req(
    'PATCH',
    `/profesionales/${profesionalId}/configuracion`,
    { duracion_cita_min: null },
    profToken
  );
  ok(
    configNull.status === 200 && configNull.data.duracion_cita_min === null,
    `revertir duracion_cita_min a null responde 200 — obtuvo ${configNull.status} ${JSON.stringify(configNull.data)}`
  );

  const slots4 = await req('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}&dias=14`);
  assert(slots4.status === 200 && slots4.data.slots.length >= 2, 'hay slots calculados tras revertir el override');
  const paso4 = pasoMinimoEntreSlots(slots4.data.slots);
  ok(
    paso4 === 30,
    `D10 (reversibilidad): tras volver a duracion_cita_min=null, la grilla vuelve a usar los 30 min del servicio — paso obtenido: ${paso4}`
  );

  const turno4 = await req(
    'POST',
    '/turnos',
    { profesional_id: profesionalId, servicio_id: servicioId, inicio: slots4.data.slots[0] },
    clienteToken
  );
  assert(turno4.status === 201, 'reserva de turno tras revertir el override');
  const misTurnos4 = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turno4Persistido = misTurnos4.data.find((t) => t.id === turno4.data.id);
  ok(
    !!turno4Persistido && minutosDuracion(turno4Persistido) === 30,
    `D10 (reversibilidad): el turno reservado tras el reset persiste con 30 min otra vez — confirma que el fallback no es solo el override, sino también la vuelta atrás — obtuvo ${turno4Persistido && minutosDuracion(turno4Persistido)}`
  );

  // --- De yapa: autorización y validación del endpoint nuevo (PATCH /profesionales/:id/configuracion) ---
  // HU-29 (Turnario Pro, 2026-08-14): el plan gratis limita 1 profesional ACTIVO por negocio —
  // este negocio ya tiene 1 (el de arriba), así que dar de alta un segundo profesional acá
  // (irrelevante para D10, solo hace falta para el control de autorización cruzada de abajo)
  // necesita que el negocio tenga Turnario Pro activo, o el alta se bloquea con 402 (ver
  // dominio/suscripciones.ts). Activación simulada (mock, mismo endpoint que usa Mobile) — no
  // se prueba nada de HU-29 en sí acá, solo se evita el bloqueo para no acoplar este script,
  // preexistente, a esa historia.
  const activarPro = await req('POST', `/negocios/${negocioId}/suscripcion`, { periodo: 'mensual' }, adminToken);
  assert(activarPro.status === 200, 'activar Turnario Pro (mock) para poder sumar un segundo profesional');

  const otroProf = await req(
    'POST',
    `/negocios/${negocioId}/profesionales`,
    { email: `prof-dur-otro-${sello}@test.com`, password: 'prof1234', nombre: 'Otro Profesional' },
    adminToken
  );
  assert(otroProf.status === 201, 'alta de un segundo profesional (para el control de autorización)');
  const loginOtroProf = await req('POST', '/auth/login', {
    email: `prof-dur-otro-${sello}@test.com`,
    password: 'prof1234',
  });
  const otroProfToken = loginOtroProf.data.token;

  const configCruzada = await req(
    'PATCH',
    `/profesionales/${profesionalId}/configuracion`,
    { duracion_cita_min: 60 },
    otroProfToken
  );
  ok(
    configCruzada.status === 403,
    `un profesional no puede configurar la duración de OTRO profesional (403 esperado) — obtuvo ${configCruzada.status}`
  );

  const configInvalidaNegativa = await req(
    'PATCH',
    `/profesionales/${profesionalId}/configuracion`,
    { duracion_cita_min: -10 },
    profToken
  );
  ok(
    configInvalidaNegativa.status === 400,
    `duracion_cita_min negativa debe rechazarse (400 esperado) — obtuvo ${configInvalidaNegativa.status}`
  );

  const configInvalidaCero = await req(
    'PATCH',
    `/profesionales/${profesionalId}/configuracion`,
    { duracion_cita_min: 0 },
    profToken
  );
  ok(
    configInvalidaCero.status === 400,
    `duracion_cita_min = 0 debe rechazarse (400 esperado — tiene que ser > 0) — obtuvo ${configInvalidaCero.status}`
  );

  const configSinCampo = await req('PATCH', `/profesionales/${profesionalId}/configuracion`, {}, profToken);
  ok(
    configSinCampo.status === 400,
    `body sin duracion_cita_min debe rechazarse (400 esperado — el campo es obligatorio, aunque sea null) — obtuvo ${configSinCampo.status}`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) de duración configurable (D10) fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log('\n✅ D10 (duración de cita configurable por el profesional, con fallback reversible) verificada.');
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
