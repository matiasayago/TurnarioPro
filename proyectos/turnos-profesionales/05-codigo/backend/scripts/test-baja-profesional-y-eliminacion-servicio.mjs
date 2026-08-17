// Verifica el fast-follow de E15 (02-backlog/backlog.md, "Fuera de alcance de v1-Administrador":
// "Baja/pausa de un profesional del negocio, o remoción de un servicio... Ninguno de los dos
// tiene endpoint (negocios.ts solo tiene alta para ambos recursos)" — ver src/routes/negocios.ts,
// PATCH /:id/profesionales/:profesionalId y DELETE /:id/servicios/:servicioId, agregados en este
// mismo ciclo) de punta a punta contra un servidor real:
//
//  0) HU-29 (Turnario Pro): reactivar una membresía pausada cuando el negocio (plan gratis) ya
//     tiene 1 profesional activo -> 402 (el nuevo PATCH no puede ser una segunda vía para
//     saltearse el límite que ya exige POST /negocios/:id/profesionales en su propia rama de
//     reactivación).
//  1) Pausar un profesional (PATCH activo:false): casos negativos de autorización, y efecto en
//     HU-08 (deja de ofrecerse como opción de reserva), en el roster del administrador (sigue
//     apareciendo, marcado activo:false — no desaparece), en login/"vista activa", y en la
//     reserva de turnos nuevos (bloqueada, tanto por el cliente como por carga manual del propio
//     profesional — incluso con un token viejo emitido ANTES de la pausa, confirmando que esos 2
//     endpoints re-validan la membresía contra la base en cada request, no confían en el JWT).
//  2) Reactivar (PATCH activo:true): idempotencia, y que los 3 efectos de arriba se revierten.
//  3) Eliminar (soft-delete) un servicio: casos negativos de autorización, y efecto en el
//     catálogo público / "mis servicios" del profesional / reserva de turnos nuevos (bloqueada) —
//     pero un turno YA reservado contra ese servicio antes de eliminarlo se sigue pudiendo leer
//     con normalidad (mis turnos del cliente, historial del profesional, reportes de ambos
//     lados) — "no romper turnos/historial existentes" verificado en vivo, no solo en el código.
//  4) 2 hallazgos que el propio código de negocios.ts deja documentados como NO corregidos en
//     este ciclo (no habilitan reservar, así que no eran el riesgo real señalado) — confirmados
//     acá EN VIVO, no solo en teoría: `GET /profesionales/:id/slots` sigue devolviendo horarios
//     para un profesional pausado, y `GET /negocios/:id/servicios/:servicioId/profesionales`
//     sigue listando profesionales para un servicio ya eliminado si se pide directo.
//
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

function decodeJwt(token) {
  return JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
}

/** Datetime ISO alineado a la grilla de disponibilidad de este script (bloques 08:00-20:00,
 *  TODOS los días de la semana, servicios de 30 min — ver setup) — `diasDesdeHoy` días en el
 *  futuro para evitar cualquier duda de ventana de cancelación/solapamiento con otros turnos que
 *  ya haya creado el propio script. */
function horarioAlineado(diasDesdeHoy, hora) {
  const d = new Date();
  d.setDate(d.getDate() + diasDesdeHoy);
  d.setHours(hora, 0, 0, 0);
  return d.toISOString();
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

  // ================= Setup =================
  const registroA = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio A (baja-profesional-servicio)',
    email: `admin-a-baja-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin A',
  });
  assert(registroA.status === 201, 'registro de negocio A');
  const adminTokenA = registroA.data.token;
  const negocioAId = registroA.data.negocio_id;

  const registroB = await req('POST', '/auth/registro-negocio', {
    nombre_negocio: 'Negocio B (baja-profesional-servicio)',
    email: `admin-b-baja-${sello}@test.com`,
    password: 'admin1234',
    nombre_admin: 'Admin B',
  });
  assert(registroB.status === 201, 'registro de negocio B');
  const adminTokenB = registroB.data.token;
  const negocioBId = registroB.data.negocio_id;

  // Servicio + profesional de negocio B — usados SOLO para los casos negativos cross-negocio.
  const servicioB = await req(
    'POST',
    `/negocios/${negocioBId}/servicios`,
    { nombre: 'Servicio B', duracion_min: 30, precio_referencia: 100 },
    adminTokenB
  );
  assert(servicioB.status === 201, 'alta de servicio B (setup cross-negocio)');
  const servicioBId = servicioB.data.id;

  const profB = await req(
    'POST',
    `/negocios/${negocioBId}/profesionales`,
    { email: `prof-b-baja-${sello}@test.com`, password: 'prof12345', nombre: 'Profesional B' },
    adminTokenB
  );
  assert(profB.status === 201, 'alta de profesional B (setup cross-negocio)');
  const profesionalBId = profB.data.id;

  // Profesional 2 primero, dado de alta y pausado DE ENTRADA — deja libre el cupo de "1 activo"
  // del plan gratis para que profesional 1 (el protagonista del resto del script) pueda darse de
  // alta ya activo. Si el orden fuera al revés, el alta de profesional 2 chocaría con el límite
  // (402) antes de poder pausarlo.
  const emailProf2 = `prof2-baja-${sello}@test.com`;
  const altaProf2 = await req(
    'POST',
    `/negocios/${negocioAId}/profesionales`,
    { email: emailProf2, password: 'prof12345', nombre: 'Profesional 2 (para límite)' },
    adminTokenA
  );
  assert(altaProf2.status === 201, 'alta de profesional 2 en negocio A (setup, cuenta como el único activo por ahora)');
  const profesional2Id = altaProf2.data.id;

  const pausaInicialProf2 = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional2Id}`,
    { activo: false },
    adminTokenA
  );
  assert(
    pausaInicialProf2.status === 200 && pausaInicialProf2.data.activo === false,
    'pausar profesional 2 de entrada (deja el cupo del plan gratis libre para profesional 1)'
  );

  const emailProf1 = `prof1-baja-${sello}@test.com`;
  const altaProf1 = await req(
    'POST',
    `/negocios/${negocioAId}/profesionales`,
    { email: emailProf1, password: 'prof12345', nombre: 'Profesional 1' },
    adminTokenA
  );
  assert(altaProf1.status === 201, 'alta de profesional 1 en negocio A (setup, queda como el único activo)');
  const profesional1Id = altaProf1.data.id;

  const servicio1 = await req(
    'POST',
    `/negocios/${negocioAId}/servicios`,
    { nombre: 'Servicio 1 (no se borra)', duracion_min: 30, precio_referencia: 1000 },
    adminTokenA
  );
  assert(servicio1.status === 201, 'alta de servicio 1 en negocio A (control — nunca se elimina en este script)');
  const servicio1Id = servicio1.data.id;

  const servicioABorrar = await req(
    'POST',
    `/negocios/${negocioAId}/servicios`,
    { nombre: 'Servicio a eliminar', duracion_min: 30, precio_referencia: 800 },
    adminTokenA
  );
  assert(servicioABorrar.status === 201, 'alta del servicio que se va a eliminar más abajo');
  const servicioABorrarId = servicioABorrar.data.id;

  const loginProf1Inicial = await req('POST', '/auth/login', { email: emailProf1, password: 'prof12345' });
  assert(loginProf1Inicial.status === 200, 'login de profesional 1 (setup)');
  const profToken1Inicial = loginProf1Inicial.data.token;

  await req('POST', `/profesionales/${profesional1Id}/servicios`, { servicio_id: servicio1Id, requiere_sena: false }, profToken1Inicial);
  await req('POST', `/profesionales/${profesional1Id}/servicios`, { servicio_id: servicioABorrarId, requiere_sena: false }, profToken1Inicial);
  for (let dia = 0; dia <= 6; dia++) {
    await req(
      'POST',
      `/profesionales/${profesional1Id}/disponibilidad`,
      { servicio_id: servicio1Id, dia_semana: dia, hora_inicio: '08:00', hora_fin: '20:00' },
      profToken1Inicial
    );
    await req(
      'POST',
      `/profesionales/${profesional1Id}/disponibilidad`,
      { servicio_id: servicioABorrarId, dia_semana: dia, hora_inicio: '08:00', hora_fin: '20:00' },
      profToken1Inicial
    );
  }

  const cliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente-baja-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente',
  });
  assert(cliente.status === 201, 'registro de cliente (setup)');
  const clienteToken = cliente.data.token;
  const clienteId = decodeJwt(clienteToken).sub;

  const otroCliente = await req('POST', '/auth/registro-cliente', {
    email: `cliente2-baja-${sello}@test.com`,
    password: 'cliente1234',
    nombre: 'Cliente 2',
  });
  assert(otroCliente.status === 201, 'registro de un 2do cliente (setup)');
  const otroClienteToken = otroCliente.data.token;
  const otroClienteId = decodeJwt(otroClienteToken).sub;

  // Turno YA existente contra el servicio que se va a eliminar más abajo — para confirmar que
  // sigue siendo legible (mis turnos / historial / reportes) DESPUÉS de eliminarlo.
  const turnoViejo = await req(
    'POST',
    '/turnos',
    { profesional_id: profesional1Id, servicio_id: servicioABorrarId, inicio: horarioAlineado(2, 9) },
    clienteToken
  );
  assert(turnoViejo.status === 201, 'cliente reserva un turno ANTES de eliminar el servicio (setup)');

  console.log('\n===== 0) HU-29 — reactivar una membresía pausada con el negocio ya en el límite (plan gratis) =====');

  // En este punto, negocio A tiene EXACTAMENTE 1 profesional activo (profesional 1) y 1 pausado
  // (profesional 2) — reactivar a profesional 2 ahora debe chocar con el límite de 1 activo.
  const reactivarProf2ConLimite = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional2Id}`,
    { activo: true },
    adminTokenA
  );
  ok(
    reactivarProf2ConLimite.status === 402 && reactivarProf2ConLimite.data?.requiere_turnario_pro === true,
    `reactivar profesional 2 cuando el negocio (plan gratis) ya tiene 1 profesional activo -> 402 requiere_turnario_pro (obtuvo ${reactivarProf2ConLimite.status} ${JSON.stringify(reactivarProf2ConLimite.data)})`
  );

  console.log('\n===== 1) PATCH /negocios/:id/profesionales/:profesionalId — pausar =====');

  const sinToken = await req('PATCH', `/negocios/${negocioAId}/profesionales/${profesional1Id}`, { activo: false });
  ok(sinToken.status === 401, `sin token -> 401 (obtuvo ${sinToken.status})`);

  const rolEquivocado = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: false },
    clienteToken
  );
  ok(rolEquivocado.status === 403, `token de cliente (rol equivocado) -> 403 (obtuvo ${rolEquivocado.status})`);

  const negocioAjeno = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: false },
    adminTokenB
  );
  ok(negocioAjeno.status === 403, `admin de OTRO negocio (B) actuando sobre la URL de negocio A -> 403 (obtuvo ${negocioAjeno.status})`);

  const membresiaCruzada = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesionalBId}`,
    { activo: false },
    adminTokenA
  );
  ok(
    membresiaCruzada.status === 404,
    `admin A pausando un profesional que solo pertenece a negocio B -> 404 cross-negocio esperado (obtuvo ${membresiaCruzada.status})`
  );

  const idInexistente = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/00000000-0000-0000-0000-000000000000`,
    { activo: false },
    adminTokenA
  );
  ok(idInexistente.status === 404, `:profesionalId inexistente -> 404 (obtuvo ${idInexistente.status})`);

  const bodyInvalido = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: 'no-es-boolean' },
    adminTokenA
  );
  ok(bodyInvalido.status === 400, `body inválido (activo no-boolean) -> 400 (obtuvo ${bodyInvalido.status})`);

  const oferentesAntesDePausar = await req('GET', `/negocios/${negocioAId}/servicios/${servicio1Id}/profesionales`);
  ok(
    oferentesAntesDePausar.status === 200 && oferentesAntesDePausar.data.some((p) => p.id === profesional1Id),
    'precondición: profesional 1 (activo) aparece como oferente del servicio 1 antes de pausar (HU-08)'
  );

  const pausar = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: false },
    adminTokenA
  );
  ok(
    pausar.status === 200 && pausar.data.activo === false && pausar.data.id === profesional1Id,
    `pausar profesional 1 -> 200 { id, activo:false } (obtuvo ${pausar.status} ${JSON.stringify(pausar.data)})`
  );

  const oferentesDespuesDePausar = await req('GET', `/negocios/${negocioAId}/servicios/${servicio1Id}/profesionales`);
  ok(
    oferentesDespuesDePausar.status === 200 && !oferentesDespuesDePausar.data.some((p) => p.id === profesional1Id),
    'efecto: profesional 1 pausado YA NO aparece como oferente del servicio 1 (HU-08)'
  );

  const roster = await req('GET', `/negocios/${negocioAId}/profesionales`, undefined, adminTokenA);
  const filaProf1Pausado = roster.data?.find((p) => p.id === profesional1Id);
  ok(
    roster.status === 200 && !!filaProf1Pausado && filaProf1Pausado.activo === false && filaProf1Pausado.nombre === 'Profesional 1',
    `efecto: profesional 1 SIGUE en el roster del administrador (no desaparece), marcado activo:false (obtuvo ${JSON.stringify(filaProf1Pausado)})`
  );

  const loginProf1Pausado = await req('POST', '/auth/login', { email: emailProf1, password: 'prof12345' });
  ok(loginProf1Pausado.status === 200, `efecto: profesional 1 pausado SIGUE pudiendo loguearse (cuenta/password intactas) (obtuvo ${loginProf1Pausado.status})`);
  const claimsPausado = loginProf1Pausado.data?.token ? decodeJwt(loginProf1Pausado.data.token) : {};
  ok(claimsPausado.negocio_id === undefined, `efecto: el token emitido NO lleva negocio_id (su único negocio está pausado, obtuvo ${claimsPausado.negocio_id})`);
  ok(
    Array.isArray(loginProf1Pausado.data?.negocios) && loginProf1Pausado.data.negocios.length === 0,
    `efecto: el body de login devuelve "negocios": [] (obtuvo ${JSON.stringify(loginProf1Pausado.data?.negocios)})`
  );

  const entrarNegocioPausado = await req(
    'POST',
    '/auth/entrar-a-negocio',
    { negocio_id: negocioAId },
    loginProf1Pausado.data.token
  );
  ok(
    entrarNegocioPausado.status === 403,
    `efecto: entrar-a-negocio al negocio donde está pausado -> 403 (obtuvo ${entrarNegocioPausado.status})`
  );

  // HALLAZGO documentado en negocios.ts (PATCH /:id/profesionales/:profesionalId), confirmado en
  // vivo acá: GET /profesionales/:id/slots NO filtra por negocio_profesional.activo — sigue
  // devolviendo horarios "disponibles" para un profesional pausado.
  const slotsServicio1Pausado = await req('GET', `/profesionales/${profesional1Id}/slots?servicio_id=${servicio1Id}&dias=14`);
  ok(
    slotsServicio1Pausado.status === 200 && slotsServicio1Pausado.data.slots.length > 0,
    `HALLAZGO documentado (negocios.ts): GET /profesionales/:id/slots sigue devolviendo horarios para un profesional PAUSADO (confirmado en vivo, obtuvo ${slotsServicio1Pausado.status}, ${slotsServicio1Pausado.data?.slots?.length} slots)`
  );

  // ...pero la reserva efectiva sigue bloqueada, tanto para un cliente nuevo como para la carga
  // manual del propio profesional — este último probado a propósito con un token EMITIDO ANTES DE
  // LA PAUSA (`profToken1Inicial`, todavía con negocio_id) para confirmar que el chequeo revalida
  // contra la base en cada request, no confía en el claim del JWT.
  const slotPausado = slotsServicio1Pausado.data.slots[0];
  const reservarConPausado = await req(
    'POST',
    '/turnos',
    { profesional_id: profesional1Id, servicio_id: servicio1Id, inicio: slotPausado },
    otroClienteToken
  );
  ok(
    reservarConPausado.status === 404,
    `pero POST /turnos con ese profesional pausado sigue bloqueado (404 esperado, obtuvo ${reservarConPausado.status} ${JSON.stringify(reservarConPausado.data)})`
  );

  const cargaManualConTokenViejo = await req(
    'POST',
    `/profesionales/${profesional1Id}/turnos`,
    { paciente_id: otroClienteId, servicio_id: servicio1Id, inicio: slotPausado, cobrar_sena: false },
    profToken1Inicial
  );
  ok(
    cargaManualConTokenViejo.status === 404,
    `carga manual del propio profesional pausado, con un token viejo (emitido ANTES de la pausa) -> 404 igual, revalida contra la base (obtuvo ${cargaManualConTokenViejo.status} ${JSON.stringify(cargaManualConTokenViejo.data)})`
  );

  console.log('\n===== 2) PATCH /negocios/:id/profesionales/:profesionalId — reactivar =====');

  const reactivar = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: true },
    adminTokenA
  );
  ok(
    reactivar.status === 200 && reactivar.data.activo === true,
    `reactivar profesional 1 -> 200 { activo:true } (obtuvo ${reactivar.status} ${JSON.stringify(reactivar.data)})`
  );

  const reactivarDeNuevo = await req(
    'PATCH',
    `/negocios/${negocioAId}/profesionales/${profesional1Id}`,
    { activo: true },
    adminTokenA
  );
  ok(
    reactivarDeNuevo.status === 200 && reactivarDeNuevo.data.activo === true,
    `reactivar de nuevo (ya estaba activo) es idempotente, no falla (obtuvo ${reactivarDeNuevo.status})`
  );

  const oferentesDespuesDeReactivar = await req('GET', `/negocios/${negocioAId}/servicios/${servicio1Id}/profesionales`);
  ok(
    oferentesDespuesDeReactivar.status === 200 && oferentesDespuesDeReactivar.data.some((p) => p.id === profesional1Id),
    'efecto: profesional 1 reactivado vuelve a aparecer como oferente del servicio 1 (HU-08)'
  );

  const loginProf1Reactivado = await req('POST', '/auth/login', { email: emailProf1, password: 'prof12345' });
  assert(loginProf1Reactivado.status === 200, 'login de profesional 1 reactivado (setup del resto del script)');
  const claimsReactivado = decodeJwt(loginProf1Reactivado.data.token);
  ok(
    claimsReactivado.negocio_id === negocioAId,
    `efecto: reactivado, el login vuelve a traer negocio_id directo (single negocio otra vez, obtuvo ${claimsReactivado.negocio_id})`
  );
  const profToken1 = loginProf1Reactivado.data.token;

  const reservarConReactivado = await req(
    'POST',
    '/turnos',
    { profesional_id: profesional1Id, servicio_id: servicio1Id, inicio: slotPausado },
    otroClienteToken
  );
  ok(
    reservarConReactivado.status === 201,
    `efecto: reactivado, la reserva vuelve a funcionar con normalidad (201 esperado, obtuvo ${reservarConReactivado.status} ${JSON.stringify(reservarConReactivado.data)})`
  );

  console.log('\n===== 3) DELETE /negocios/:id/servicios/:servicioId =====');

  const delSinToken = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioABorrarId}`);
  ok(delSinToken.status === 401, `sin token -> 401 (obtuvo ${delSinToken.status})`);

  const delRolEquivocado = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioABorrarId}`, undefined, clienteToken);
  ok(delRolEquivocado.status === 403, `token de cliente (rol equivocado) -> 403 (obtuvo ${delRolEquivocado.status})`);

  const delNegocioAjeno = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioABorrarId}`, undefined, adminTokenB);
  ok(delNegocioAjeno.status === 403, `admin de OTRO negocio (B) actuando sobre la URL de negocio A -> 403 (obtuvo ${delNegocioAjeno.status})`);

  const delServicioCruzado = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioBId}`, undefined, adminTokenA);
  ok(
    delServicioCruzado.status === 404,
    `admin A eliminando un servicio que pertenece a negocio B -> 404 cross-negocio esperado (obtuvo ${delServicioCruzado.status})`
  );

  const delInexistente = await req(
    'DELETE',
    `/negocios/${negocioAId}/servicios/00000000-0000-0000-0000-000000000000`,
    undefined,
    adminTokenA
  );
  ok(delInexistente.status === 404, `:servicioId inexistente -> 404 (obtuvo ${delInexistente.status})`);

  const catalogoAntes = await req('GET', `/negocios/${negocioAId}/servicios`);
  ok(
    catalogoAntes.status === 200 && catalogoAntes.data.some((s) => s.id === servicioABorrarId),
    'precondición: el servicio a eliminar todavía aparece en el catálogo público'
  );

  const eliminar = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioABorrarId}`, undefined, adminTokenA);
  ok(
    eliminar.status === 200 && eliminar.data?.id === servicioABorrarId && eliminar.data?.eliminado === true,
    `eliminar servicio -> 200 { id, eliminado:true } (obtuvo ${eliminar.status} ${JSON.stringify(eliminar.data)})`
  );

  const eliminarDeNuevo = await req('DELETE', `/negocios/${negocioAId}/servicios/${servicioABorrarId}`, undefined, adminTokenA);
  ok(eliminarDeNuevo.status === 404, `eliminar de nuevo el mismo servicio (ya eliminado) -> 404 (obtuvo ${eliminarDeNuevo.status})`);

  const catalogoDespues = await req('GET', `/negocios/${negocioAId}/servicios`);
  ok(
    catalogoDespues.status === 200 && !catalogoDespues.data.some((s) => s.id === servicioABorrarId),
    'efecto: el servicio eliminado YA NO aparece en el catálogo público (GET /negocios/:id/servicios)'
  );

  const misServiciosProfesional = await req('GET', `/profesionales/${profesional1Id}/servicios`, undefined, profToken1);
  ok(
    misServiciosProfesional.status === 200 &&
      !misServiciosProfesional.data.some((s) => s.servicio_id === servicioABorrarId) &&
      misServiciosProfesional.data.some((s) => s.servicio_id === servicio1Id),
    `efecto: el servicio eliminado YA NO aparece en "mis servicios" del profesional, pero el que no se tocó (servicio 1) sigue (obtuvo ${JSON.stringify(misServiciosProfesional.data)})`
  );

  // HALLAZGO documentado en negocios.ts (DELETE /:id/servicios/:servicioId), confirmado en vivo:
  // HU-08 sigue listando profesionales para un servicio_id ya eliminado si se pide directo (no
  // llegando ahí navegando desde el catálogo, que ya lo excluye).
  const oferentesServicioEliminado = await req('GET', `/negocios/${negocioAId}/servicios/${servicioABorrarId}/profesionales`);
  ok(
    oferentesServicioEliminado.status === 200 && oferentesServicioEliminado.data.some((p) => p.id === profesional1Id),
    `HALLAZGO documentado (negocios.ts): GET /negocios/:id/servicios/:servicioId/profesionales sigue listando profesionales para un servicio YA ELIMINADO pedido directo (confirmado en vivo, obtuvo ${oferentesServicioEliminado.status} ${JSON.stringify(oferentesServicioEliminado.data)})`
  );

  const reservarServicioEliminado = await req(
    'POST',
    '/turnos',
    { profesional_id: profesional1Id, servicio_id: servicioABorrarId, inicio: horarioAlineado(6, 10) },
    otroClienteToken
  );
  ok(
    reservarServicioEliminado.status === 404,
    `POST /turnos contra un servicio eliminado -> 404 (obtuvo ${reservarServicioEliminado.status} ${JSON.stringify(reservarServicioEliminado.data)})`
  );

  const cargaManualServicioEliminado = await req(
    'POST',
    `/profesionales/${profesional1Id}/turnos`,
    { paciente_id: otroClienteId, servicio_id: servicioABorrarId, inicio: horarioAlineado(6, 11), cobrar_sena: false },
    profToken1
  );
  ok(
    cargaManualServicioEliminado.status === 404,
    `carga manual del profesional contra un servicio eliminado -> 404 (obtuvo ${cargaManualServicioEliminado.status} ${JSON.stringify(cargaManualServicioEliminado.data)})`
  );

  // Turno YA EXISTENTE (reservado ANTES de eliminar el servicio) — tiene que seguir siendo
  // legible con total normalidad: ni desaparece, ni rompe ningún endpoint de lectura.
  const misTurnosCliente = await req('GET', '/turnos/mios', undefined, clienteToken);
  const turnoViejoEnListado = misTurnosCliente.data?.find((t) => t.id === turnoViejo.data.id);
  ok(
    misTurnosCliente.status === 200 && !!turnoViejoEnListado,
    `efecto: el turno reservado ANTES de eliminar el servicio se sigue viendo con normalidad en "mis turnos" del cliente (obtuvo ${JSON.stringify(turnoViejoEnListado)})`
  );

  const historialProfesional = await req('GET', `/clientes/${clienteId}/historial`, undefined, profToken1);
  ok(
    historialProfesional.status === 200 &&
      historialProfesional.data.some((t) => t.id === turnoViejo.data.id && t.servicio === 'Servicio a eliminar'),
    `efecto: el historial del profesional sigue mostrando el turno viejo, con el NOMBRE del servicio eliminado (obtuvo ${JSON.stringify(historialProfesional.data)})`
  );

  const reportesProfesional = await req('GET', `/profesionales/${profesional1Id}/reportes`, undefined, profToken1);
  ok(
    reportesProfesional.status === 200 && reportesProfesional.data.turnos_totales >= 1,
    `efecto: GET /profesionales/:id/reportes no se rompe y sigue contando el turno del servicio eliminado (obtuvo ${reportesProfesional.status} ${JSON.stringify(reportesProfesional.data)})`
  );

  const reportesNegocio = await req('GET', `/negocios/${negocioAId}/reportes`, undefined, adminTokenA);
  ok(
    reportesNegocio.status === 200 && reportesNegocio.data.turnos_totales >= 1,
    `efecto: GET /negocios/:id/reportes no se rompe y sigue contando el turno del servicio eliminado (obtuvo ${reportesNegocio.status} ${JSON.stringify(reportesNegocio.data)})`
  );

  if (fallas > 0) {
    console.log(`\n❌ ${fallas} verificación(es) fallaron — ver detalle arriba.`);
    process.exit(1);
  }
  console.log(
    '\n✅ Pausar/reactivar profesional (con el límite de plan gratis aplicado también a la reactivación) y eliminar (soft-delete) un servicio (sin romper turnos/reportes/historial ya existentes) — E15 fast-follow — verificados de punta a punta.'
  );
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
