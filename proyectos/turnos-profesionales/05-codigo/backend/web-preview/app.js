// Preview de prueba del backend real, con el sistema de diseño de
// 04-diseno/sistema-diseno.md aplicado (UX/UI) — mismos endpoints que consumiría la app
// Flutter (ver ../../mobile/lib/api_client.dart). Rutas relativas: se sirve desde el mismo
// origen que la API (mismo Express, ver ../src/app.ts), sin problemas de CORS.

let token = null;
let claims = null; // { sub, rol, negocio_id, profesional_id }
let ultimoSeed = null;
let duracionConfigurada = null; // cache local del stepper de Configuración (profesional)

const $ = (id) => document.getElementById(id);

function decodificarJwt(t) {
  const payload = t.split('.')[1];
  return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw Object.assign(new Error(data?.error || 'Error desconocido'), { status: res.status, data });
  return data;
}

function fmt(iso) {
  return new Date(iso).toLocaleString('es-AR', { hour12: false });
}

// StatusPill (sistema-diseno.md §7.2 / §3.4) — nunca solo color, siempre texto.
const ESTADO_TURNO_PILL = {
  pendiente_de_pago: ['pill-warning', 'Por confirmar'],
  confirmado: ['pill-success', 'Confirmado'],
  cancelado: ['pill-danger', 'Cancelado'],
  reprogramado: ['pill-neutral', 'Reprogramado'],
};
function statusPill(estado) {
  const [cls, label] = ESTADO_TURNO_PILL[estado] || ['pill-neutral', estado];
  return `<span class="pill ${cls}">${label}</span>`;
}

// ---------- 1. Seed (pre-login) ----------
$('btnSeed').addEventListener('click', async () => {
  $('btnSeed').disabled = true;
  try {
    const data = await api('POST', '/dev/seed');
    ultimoSeed = data;
    $('seedResultado').innerHTML = `
      <div class="card static">
        <b>${data.negocio.nombre}</b> — servicio <b>${data.servicio.nombre}</b>
        (${data.servicio.duracion_min ?? 30} min, seña $${data.servicio.monto_sena})
        <div style="margin-top:8px; display:flex; gap:6px; flex-wrap:wrap;">
          <span class="pill pill-neutral">Cliente: ${data.cliente.email} / ${data.cliente.password}</span>
          <span class="pill pill-neutral">Profesional: ${data.profesional.email} / ${data.profesional.password}</span>
        </div>
      </div>`;
    $('loginSection').style.display = 'block';
    $('concurrenciaSection').style.display = 'block';
    $('loginEmail').value = data.cliente.email;
    $('loginPassword').value = data.cliente.password;
  } catch (e) {
    $('seedResultado').innerHTML = `<p class="error">${e.message}</p>`;
  } finally {
    $('btnSeed').disabled = false;
  }
});

// ---------- 2. Login ----------
$('btnLogin').addEventListener('click', async () => {
  $('loginError').textContent = '';
  try {
    const data = await api('POST', '/auth/login', {
      email: $('loginEmail').value.trim(),
      password: $('loginPassword').value,
    });
    token = data.token;
    claims = decodificarJwt(token);
    entrarAlShell();
  } catch (e) {
    $('loginError').textContent = e.message;
  }
});

$('btnLogout').addEventListener('click', () => {
  token = null;
  claims = null;
  $('appShell').style.display = 'none';
  $('preLoginWrap').style.display = 'block';
});

// ---------- App shell: header + bottom nav + screens ----------
const NAV_CLIENTE = [
  { id: 'buscar', icon: '🔎', label: 'Buscar' },
  { id: 'misTurnos', icon: '📅', label: 'Mis Turnos' },
  { id: 'notificaciones', icon: '🔔', label: 'Notificaciones' },
  { id: 'config', icon: '⚙️', label: 'Configuración' },
];
const NAV_PROFESIONAL = [
  { id: 'dashboard', icon: '🏠', label: 'Dashboard' },
  { id: 'pacientes', icon: '🏥', label: 'Pacientes' },
  { id: 'horarios', icon: '⏰', label: 'Horarios' },
  { id: 'config', icon: '⚙️', label: 'Configuración' },
];

function entrarAlShell() {
  $('preLoginWrap').style.display = 'none';
  $('appShell').style.display = 'block';
  const items = claims.rol === 'cliente' ? NAV_CLIENTE : NAV_PROFESIONAL;
  $('bottomNav').innerHTML = items
    .map((it) => `<button data-screen="${it.id}"><span class="ic">${it.icon}</span>${it.label}</button>`)
    .join('');
  $('screensWrap').innerHTML = items.map((it) => `<div class="screen" id="screen-${it.id}"></div>`).join('');
  document.querySelectorAll('#bottomNav button').forEach((btn) =>
    btn.addEventListener('click', () => irA(btn.dataset.screen))
  );
  irA(items[0].id);
}

function irA(screenId) {
  document.querySelectorAll('#bottomNav button').forEach((b) => b.classList.toggle('active', b.dataset.screen === screenId));
  document.querySelectorAll('.screen').forEach((s) => s.classList.toggle('active', s.id === `screen-${screenId}`));
  const rutas = {
    buscar: ['Buscar', 'Elegí un negocio para reservar un turno', cargarNegocios],
    misTurnos: ['Mis Turnos', null, cargarMisTurnos],
    notificaciones: ['Notificaciones', null, renderEmptyNotificaciones],
    dashboard: ['Dashboard', `¡Hola, ${claims.rol === 'profesional' ? 'Dr/a.' : ''}!`, cargarDashboardProfesional],
    pacientes: ['Pacientes', 'Tus clientes atendidos', cargarPacientes],
    horarios: ['Horarios', null, renderHorariosStub],
    config: ['Configuración', null, claims.rol === 'profesional' ? cargarConfigProfesional : renderConfigCliente],
  };
  const [titulo, subtitulo, cargar] = rutas[screenId];
  $('headerTitle').textContent = titulo;
  $('headerSubtitle').textContent = subtitulo || '';
  cargar();
}

// ---------- Cliente: Buscar (negocios → servicios → profesionales → slots → reservar) ----------
function breadcrumb(pasos) {
  return `<div class="breadcrumb">${pasos
    .map((p, i) => (i < pasos.length - 1 ? `<span onclick="(${p.onClick})()">${p.label}</span> › ` : p.label))
    .join('')}</div>`;
}

async function cargarNegocios() {
  const el = $('screen-buscar');
  const negocios = await api('GET', '/negocios');
  el.innerHTML = negocios
    .map((n) => `<div class="card" data-id="${n.id}" data-nombre="${n.nombre}">
        <b>${n.nombre}</b><br><span class="caption">${[n.rubro, n.ubicacion].filter(Boolean).join(' · ')}</span>
      </div>`)
    .join('') || '<p class="caption">No hay negocios cargados.</p>';
  el.querySelectorAll('.card[data-id]').forEach((c) =>
    c.addEventListener('click', () => cargarServicios(c.dataset.id, c.dataset.nombre))
  );
}

async function cargarServicios(negocioId, negocioNombre) {
  const el = $('screen-buscar');
  const servicios = await api('GET', `/negocios/${negocioId}/servicios`);
  el.innerHTML =
    breadcrumb([{ label: 'Negocios', onClick: 'cargarNegocios' }, { label: negocioNombre }]) +
    (servicios
      .map((s) => `<div class="card" data-id="${s.id}" data-nombre="${s.nombre}">
        <b>${s.nombre}</b><br><span class="caption">${s.duracion_min} min · $${s.precio_referencia ?? '-'}</span>
      </div>`)
      .join('') || '<p class="caption">Este negocio no cargó servicios.</p>');
  el.querySelectorAll('.card[data-id]').forEach((c) =>
    c.addEventListener('click', () => cargarProfesionales(negocioId, negocioNombre, c.dataset.id, c.dataset.nombre))
  );
}

async function cargarProfesionales(negocioId, negocioNombre, servicioId, servicioNombre) {
  const el = $('screen-buscar');
  const profesionales = await api('GET', `/negocios/${negocioId}/servicios/${servicioId}/profesionales`);
  el.innerHTML =
    breadcrumb([
      { label: 'Negocios', onClick: 'cargarNegocios' },
      { label: negocioNombre, onClick: `() => cargarServicios('${negocioId}','${negocioNombre}')` },
      { label: servicioNombre },
    ]) +
    (profesionales
      .map((p) => `<div class="card" data-id="${p.id}" data-nombre="${p.nombre}">👤 <b>${p.nombre}</b></div>`)
      .join('') || '<p class="caption">Nadie ofrece este servicio todavía.</p>');
  el.querySelectorAll('.card[data-id]').forEach((c) =>
    c.addEventListener('click', () => cargarSlots(servicioId, servicioNombre, c.dataset.id, c.dataset.nombre))
  );
}

async function cargarSlots(servicioId, servicioNombre, profesionalId, profesionalNombre) {
  const el = $('screen-buscar');
  const { slots, proximo_disponible } = await api('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  el.innerHTML =
    `<h2 class="section-title">${profesionalNombre}</h2>` +
    (proximo_disponible ? `<p class="caption">Próximo disponible: ${fmt(proximo_disponible)}</p>` : '') +
    (slots.map((s) => `<div class="card" data-inicio="${s}">🕐 ${fmt(s)}</div>`).join('') ||
      '<p class="caption">Sin horarios disponibles.</p>');
  el.querySelectorAll('.card[data-inicio]').forEach((c) =>
    c.addEventListener('click', () => confirmarTurno(profesionalId, servicioId, c.dataset.inicio))
  );
}

async function confirmarTurno(profesionalId, servicioId, inicio) {
  try {
    const turno = await api('POST', '/turnos', { profesional_id: profesionalId, servicio_id: servicioId, inicio });
    alert(
      turno.requiere_pago
        ? `Turno creado (pendiente de pago, seña $${turno.monto_sena}). Estado: ${turno.estado}`
        : `Turno confirmado. Estado: ${turno.estado}`
    );
  } catch (e) {
    alert(e.status === 409 ? '⛔ ' + e.message + ' (RN2)' : e.message);
  }
  irA('misTurnos');
}

// ---------- Cliente: Mis Turnos ----------
async function cargarMisTurnos() {
  const el = $('screen-misTurnos');
  const turnos = await api('GET', '/turnos/mios');
  el.innerHTML = turnos.length
    ? turnos
        .map((t) => {
          const gestionable = ['pendiente_de_pago', 'confirmado'].includes(t.estado);
          return `<div class="card static" data-turno-id="${t.id}">
            <b>${fmt(t.inicio)}</b> ${statusPill(t.estado)}
            ${gestionable ? `<div class="btn-row"><button class="btn btn-outline" data-accion="reprogramar">Reprogramar</button><button class="btn btn-outline" data-accion="cancelar">Cancelar</button></div>` : ''}
          </div>`;
        })
        .join('')
    : '<p class="caption">Sin turnos todavía — reservá uno desde "Buscar".</p>';

  el.querySelectorAll('[data-accion="cancelar"]').forEach((btn) =>
    btn.addEventListener('click', async (e) => {
      const id = e.target.closest('[data-turno-id]').dataset.turnoId;
      try {
        await api('PATCH', `/turnos/${id}/cancelar`);
      } catch (err) {
        alert(err.message);
      }
      cargarMisTurnos();
    })
  );
  el.querySelectorAll('[data-accion="reprogramar"]').forEach((btn) =>
    btn.addEventListener('click', async (e) => {
      const id = e.target.closest('[data-turno-id]').dataset.turnoId;
      const nuevo = prompt('Nuevo horario (ISO, ej. 2026-08-10T14:00:00.000Z):');
      if (!nuevo) return;
      try {
        await api('PATCH', `/turnos/${id}/reprogramar`, { nuevo_inicio: new Date(nuevo).toISOString() });
      } catch (err) {
        alert(err.message);
      }
      cargarMisTurnos();
    })
  );
}

function renderEmptyNotificaciones() {
  $('screen-notificaciones').innerHTML = `
    <div class="card static" style="text-align:center; padding:32px 16px;">
      <div style="font-size:32px;">🔔</div>
      <b>Sin notificaciones</b>
      <p class="caption">Los recordatorios y confirmaciones de turno van a aparecer acá (D4).</p>
    </div>`;
}

function renderConfigCliente() {
  $('screen-config').innerHTML = `
    <div class="card static">
      <b>${claims.rol}</b>
      <p class="caption">Sesión iniciada. Usá "Salir" en el encabezado para cerrar sesión.</p>
    </div>`;
}

// ---------- Profesional: Dashboard (StatCards + agenda, §7.3) ----------
async function cargarDashboardProfesional() {
  const el = $('screen-dashboard');
  const [turnos, clientes] = await Promise.all([
    api('GET', `/profesionales/${claims.profesional_id}/turnos`),
    api('GET', `/profesionales/${claims.profesional_id}/clientes`),
  ]);
  el.innerHTML = `
    <div class="stat-grid">
      <div class="stat-card"><span class="num">${turnos.length}</span><span class="label">Turnos activos</span></div>
      <div class="stat-card"><span class="num">${clientes.length}</span><span class="label">Pacientes</span></div>
      <div class="stat-card"><span class="num">${turnos.filter((t) => t.estado === 'pendiente_de_pago').length}</span><span class="label">Por confirmar</span></div>
    </div>
    <h2 class="section-title">Próximos turnos</h2>
    ${
      turnos
        .map(
          (t) => `<div class="card static">
            <b>${fmt(t.inicio)}</b> ${statusPill(t.estado)}<br>
            <span class="caption">${t.servicio} con ${t.cliente}</span>
          </div>`
        )
        .join('') || '<p class="caption">Sin turnos próximos.</p>'
    }`;
}

// ---------- Profesional: Pacientes (lista + historial, §7.10) ----------
async function cargarPacientes() {
  const el = $('screen-pacientes');
  const clientes = await api('GET', `/profesionales/${claims.profesional_id}/clientes`);
  el.innerHTML =
    clientes
      .map(
        (c) => `<div class="card" data-id="${c.id}" data-nombre="${c.nombre}">
          👤 <b>${c.nombre}</b><br><span class="caption">${c.email}</span>
        </div>`
      )
      .join('') || '<p class="caption">Sin pacientes atendidos todavía.</p>';
  el.querySelectorAll('.card[data-id]').forEach((c) =>
    c.addEventListener('click', () => cargarHistorialPaciente(c.dataset.id, c.dataset.nombre))
  );
}

async function cargarHistorialPaciente(clienteId, nombre) {
  const el = $('screen-pacientes');
  const historial = await api('GET', `/clientes/${clienteId}/historial`);
  el.innerHTML =
    breadcrumb([{ label: 'Pacientes', onClick: 'cargarPacientes' }, { label: nombre }]) +
    `<h2 class="section-title">Historial de ${nombre}</h2>` +
    (historial
      .map((v) => `<div class="card static">${fmt(v.inicio)} — ${v.servicio} ${statusPill(v.estado)}</div>`)
      .join('') || '<p class="caption">Sin visitas registradas.</p>');
}

function renderHorariosStub() {
  $('screen-horarios').innerHTML = `
    <div class="card static" style="text-align:center; padding:32px 16px;">
      <div style="font-size:32px;">⏰</div>
      <b>Gestión de Horarios</b>
      <p class="caption">Calendario y plantillas recurrentes (HU-17/HU-18) — sin implementar todavía en este preview. La disponibilidad se carga hoy vía API directa (ver README del backend).</p>
    </div>`;
}

// ---------- Profesional: Configuración — NumericStepperField real (D10/RN3) ----------
async function cargarConfigProfesional() {
  const el = $('screen-config');
  const prof = await api('GET', `/profesionales/${claims.profesional_id}/clientes`).catch(() => null); // no-op warmup
  // No hay GET de "mi perfil" propio expuesto — partimos de null (= usa duración del servicio)
  // salvo que ya se haya seteado en esta sesión.
  if (duracionConfigurada === null) duracionConfigurada = null;
  renderStepperConfig(el);
}

function renderStepperConfig(el) {
  const usaOverride = duracionConfigurada !== null;
  el.innerHTML = `
    <div class="card static">
      <b>Duración de cita (D10)</b>
      <p class="caption">Si la configurás, reemplaza SIEMPRE la duración del servicio (RN3) para todos tus turnos. Dejala en "usar la del servicio" para volver al comportamiento por defecto.</p>
      <div class="stepper">
        <button id="stepperMenos" ${!usaOverride ? 'disabled' : ''}>−</button>
        <span class="value" id="stepperValor">${usaOverride ? duracionConfigurada + ' min' : 'Del servicio'}</span>
        <button id="stepperMas">+</button>
      </div>
      <div class="btn-row" style="justify-content:center">
        <button class="btn btn-outline" id="btnUsarServicio" ${!usaOverride ? 'disabled' : ''}>Usar la del servicio</button>
        <button class="btn btn-primary" id="btnGuardarDuracion">Guardar</button>
      </div>
      <p class="caption" id="configFeedback"></p>
    </div>
    <div class="card static">
      <b>Cuenta</b>
      <p class="caption">Rol: ${claims.rol} · negocio activo: ${claims.negocio_id ? claims.negocio_id.slice(0, 8) : '(ninguno seleccionado)'}</p>
    </div>`;

  $('stepperMas').addEventListener('click', () => {
    duracionConfigurada = usaOverride ? Math.min(duracionConfigurada + 5, 240) : 30;
    renderStepperConfig(el);
  });
  $('stepperMenos').addEventListener('click', () => {
    if (!usaOverride) return;
    duracionConfigurada = Math.max(duracionConfigurada - 5, 5);
    renderStepperConfig(el);
  });
  $('btnUsarServicio').addEventListener('click', () => {
    duracionConfigurada = null;
    renderStepperConfig(el);
  });
  $('btnGuardarDuracion').addEventListener('click', async () => {
    try {
      await api('PATCH', `/profesionales/${claims.profesional_id}/configuracion`, {
        duracion_cita_min: duracionConfigurada,
      });
      $('configFeedback').textContent = '✅ Guardado — se aplica desde ahora a tus próximos turnos.';
    } catch (e) {
      $('configFeedback').textContent = '⛔ ' + e.message;
    }
  });
}

// ---------- 3. Prueba de concurrencia (pre-login, contra el negocio sembrado) ----------
$('btnConcurrencia').addEventListener('click', async () => {
  if (!ultimoSeed) return;
  $('btnConcurrencia').disabled = true;
  $('resultadoConcurrencia').innerHTML = 'Disparando...';
  try {
    const { profesional, servicio } = ultimoSeed;
    const { slots } = await api('GET', `/profesionales/${profesional.id}/slots?servicio_id=${servicio.id}`);
    const slotLibre = slots[0];
    if (!slotLibre) {
      $('resultadoConcurrencia').innerHTML = '<p class="error">No quedan slots libres — sembrá datos de nuevo.</p>';
      return;
    }
    const crearClienteEfimero = async (sufijo) => {
      const email = `concurrencia-${sufijo}-${Date.now()}@test.com`;
      const r = await api('POST', '/auth/registro-cliente', { email, password: 'x12345678', nombre: 'Cliente ' + sufijo });
      return r.token;
    };
    const [tokenA, tokenB] = await Promise.all([crearClienteEfimero('A'), crearClienteEfimero('B')]);
    const reservar = async (t) => {
      const res = await fetch('/turnos', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}` },
        body: JSON.stringify({ profesional_id: profesional.id, servicio_id: servicio.id, inicio: slotLibre }),
      });
      return { status: res.status, data: await res.json() };
    };
    const [rA, rB] = await Promise.all([reservar(tokenA), reservar(tokenB)]);
    const render = (r, nombre) => `<div class="card static">
        <b>Cliente ${nombre}</b><br>
        <span class="pill ${r.status === 201 ? 'pill-success' : 'pill-warning'}">HTTP ${r.status}</span>
        <pre>${JSON.stringify(r.data, null, 2)}</pre>
      </div>`;
    $('resultadoConcurrencia').innerHTML = render(rA, 'A') + render(rB, 'B');
    const exitosas = [rA, rB].filter((r) => r.status === 201).length;
    $('resultadoConcurrencia').innerHTML +=
      exitosas === 1
        ? '<p class="caption">✅ <b>RN2 verificada:</b> exactamente 1 reserva exitosa sobre el mismo horario.</p>'
        : `<p class="error">⚠️ Se esperaba 1 reserva exitosa y hubo ${exitosas}.</p>`;
  } catch (e) {
    $('resultadoConcurrencia').innerHTML = `<p class="error">${e.message}</p>`;
  } finally {
    $('btnConcurrencia').disabled = false;
  }
});
