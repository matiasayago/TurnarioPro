// Preview de prueba del backend real — vanilla JS, sin build step. Mismos endpoints que
// consume la app Flutter (ver ../../mobile/lib/api_client.dart). Rutas relativas: se sirve
// desde el mismo origen que la API (mismo Express, ver ../src/app.ts), sin problemas de CORS.

let token = null;
let claims = null; // { sub, rol, negocio_id, profesional_id }
let ultimoSeed = null; // guarda ids/credenciales del último seed para el test de concurrencia

const $ = (id) => document.getElementById(id);

function decodificarJwt(t) {
  const payload = t.split('.')[1];
  return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw Object.assign(new Error(data?.error || 'Error desconocido'), { status: res.status, data });
  return data;
}

// ---------- 1. Seed ----------
$('btnSeed').addEventListener('click', async () => {
  $('btnSeed').disabled = true;
  try {
    const data = await api('POST', '/dev/seed');
    ultimoSeed = data;
    $('seedResultado').innerHTML = `
      <div class="card static">
        <b>${data.negocio.nombre}</b> — servicio <b>${data.servicio.nombre}</b>
        (${data.servicio.duracion_min ?? 30} min, seña $${data.servicio.monto_sena})
        <div class="row">
          <span class="pill">Cliente: <code>${data.cliente.email}</code> / <code>${data.cliente.password}</code></span>
          <span class="pill">Profesional: <code>${data.profesional.email}</code> / <code>${data.profesional.password}</code></span>
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
    $('loginSection').style.display = 'none';
    $('appSection').style.display = 'block';
    $('sesionInfo').textContent = `${claims.rol}${claims.negocio_id ? ' · negocio ' + claims.negocio_id.slice(0, 8) : ''}`;
    if (claims.rol === 'cliente') {
      $('vistaCliente').style.display = 'block';
      cargarNegocios();
    } else if (claims.rol === 'profesional') {
      $('vistaProfesional').style.display = 'block';
      cargarAgenda();
    }
  } catch (e) {
    $('loginError').textContent = e.message;
  }
});

$('btnLogout').addEventListener('click', () => {
  token = null;
  claims = null;
  $('appSection').style.display = 'none';
  $('vistaCliente').innerHTML = '';
  $('vistaProfesional').innerHTML = '';
  $('loginSection').style.display = 'block';
});

// ---------- Flujo Cliente ----------
function breadcrumb(pasos) {
  return `<div class="breadcrumb">${pasos
    .map((p, i) => (i < pasos.length - 1 ? `<span onclick="(${p.onClick})()">${p.label}</span> › ` : p.label))
    .join('')}</div>`;
}

async function cargarNegocios() {
  const negocios = await api('GET', '/negocios');
  $('vistaCliente').innerHTML = `
    <h2>Negocios</h2>
    ${negocios.map((n) => `<div class="card" data-id="${n.id}" data-nombre="${n.nombre}">
        <b>${n.nombre}</b><br><small>${[n.rubro, n.ubicacion].filter(Boolean).join(' · ')}</small>
      </div>`).join('') || '<p>No hay negocios cargados.</p>'}
    <h2>Mis turnos</h2>
    <div id="misTurnos">Cargando…</div>`;
  document.querySelectorAll('#vistaCliente .card[data-id]').forEach((el) =>
    el.addEventListener('click', () => cargarServicios(el.dataset.id, el.dataset.nombre))
  );
  cargarMisTurnos();
}

async function cargarServicios(negocioId, negocioNombre) {
  const servicios = await api('GET', `/negocios/${negocioId}/servicios`);
  $('vistaCliente').innerHTML = `
    ${breadcrumb([{ label: 'Negocios', onClick: 'cargarNegocios' }, { label: negocioNombre }])}
    <h2>${negocioNombre} — Servicios</h2>
    ${servicios.map((s) => `<div class="card" data-id="${s.id}" data-nombre="${s.nombre}">
        <b>${s.nombre}</b><br><small>${s.duracion_min} min · $${s.precio_referencia ?? '-'}</small>
      </div>`).join('') || '<p>Este negocio no cargó servicios.</p>'}`;
  document.querySelectorAll('#vistaCliente .card[data-id]').forEach((el) =>
    el.addEventListener('click', () => cargarProfesionales(negocioId, negocioNombre, el.dataset.id, el.dataset.nombre))
  );
}

async function cargarProfesionales(negocioId, negocioNombre, servicioId, servicioNombre) {
  const profesionales = await api('GET', `/negocios/${negocioId}/servicios/${servicioId}/profesionales`);
  $('vistaCliente').innerHTML = `
    ${breadcrumb([
      { label: 'Negocios', onClick: 'cargarNegocios' },
      { label: negocioNombre, onClick: `() => cargarServicios('${negocioId}','${negocioNombre}')` },
      { label: servicioNombre },
    ])}
    <h2>${servicioNombre} — Profesionales</h2>
    ${profesionales.map((p) => `<div class="card" data-id="${p.id}" data-nombre="${p.nombre}">
        👤 <b>${p.nombre}</b>
      </div>`).join('') || '<p>Nadie ofrece este servicio todavía.</p>'}`;
  document.querySelectorAll('#vistaCliente .card[data-id]').forEach((el) =>
    el.addEventListener('click', () => cargarSlots(servicioId, servicioNombre, el.dataset.id, el.dataset.nombre))
  );
}

async function cargarSlots(servicioId, servicioNombre, profesionalId, profesionalNombre) {
  const { slots, proximo_disponible } = await api('GET', `/profesionales/${profesionalId}/slots?servicio_id=${servicioId}`);
  $('vistaCliente').innerHTML = `
    <h2>${profesionalNombre} — Horarios</h2>
    ${proximo_disponible ? `<p><small>Próximo disponible: ${new Date(proximo_disponible).toLocaleString('es-AR', { hour12: false })}</small></p>` : ''}
    ${slots.map((s) => `<div class="card" data-inicio="${s}">🕐 ${new Date(s).toLocaleString('es-AR', { hour12: false })}</div>`).join('') || '<p>Sin horarios disponibles.</p>'}`;
  document.querySelectorAll('#vistaCliente .card[data-inicio]').forEach((el) =>
    el.addEventListener('click', () => confirmarTurno(profesionalId, servicioId, el.dataset.inicio))
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
  cargarNegocios();
}

async function cargarMisTurnos() {
  const turnos = await api('GET', '/turnos/mios');
  $('misTurnos').innerHTML = turnos.length
    ? turnos.map((t) => {
        const gestionable = ['pendiente_de_pago', 'confirmado'].includes(t.estado);
        return `<div class="card static" data-turno-id="${t.id}">
          ${new Date(t.inicio).toLocaleString('es-AR', { hour12: false })}
          <span class="pill ${t.estado === 'confirmado' ? 'ok' : t.estado === 'cancelado' ? '' : 'warn'}">${t.estado}</span>
          ${gestionable ? `<button data-id="${t.id}" data-prof="${t.profesional_id}" data-serv="${t.servicio_id}" class="btnReprogramar">Reprogramar</button>` : ''}
          ${gestionable ? `<button data-id="${t.id}" class="btnCancelar">Cancelar</button>` : ''}
          <div class="slotsReprogramar" id="slotsReprogramar-${t.id}"></div>
        </div>`;
      }).join('')
    : '<p><small>Sin turnos todavía.</small></p>';

  document.querySelectorAll('.btnCancelar').forEach((btn) =>
    btn.addEventListener('click', async () => {
      try {
        await api('PATCH', `/turnos/${btn.dataset.id}/cancelar`);
      } catch (e) {
        alert(e.message);
      }
      cargarMisTurnos();
    })
  );

  // HU-13: reprogramar — muestra los horarios del mismo profesional/servicio inline.
  document.querySelectorAll('.btnReprogramar').forEach((btn) =>
    btn.addEventListener('click', async () => {
      const { slots } = await api('GET', `/profesionales/${btn.dataset.prof}/slots?servicio_id=${btn.dataset.serv}`);
      const contenedor = $(`slotsReprogramar-${btn.dataset.id}`);
      contenedor.innerHTML = slots.length
        ? slots.map((s) => `<div class="card" data-nuevo-inicio="${s}">🕐 ${new Date(s).toLocaleString('es-AR', { hour12: false })}</div>`).join('')
        : '<p><small>No hay otros horarios disponibles.</small></p>';
      contenedor.querySelectorAll('[data-nuevo-inicio]').forEach((slotEl) =>
        slotEl.addEventListener('click', async () => {
          try {
            await api('PATCH', `/turnos/${btn.dataset.id}/reprogramar`, { nuevo_inicio: slotEl.dataset.nuevoInicio });
          } catch (e) {
            alert(e.status === 409 ? '⛔ ' + e.message + ' (RN2)' : e.message);
          }
          cargarMisTurnos();
        })
      );
    })
  );
}

// ---------- Flujo Profesional ----------
async function cargarAgenda() {
  const [turnos, clientes] = await Promise.all([
    api('GET', `/profesionales/${claims.profesional_id}/turnos`),
    api('GET', `/profesionales/${claims.profesional_id}/clientes`),
  ]);
  $('vistaProfesional').innerHTML = `
    <h2>Mi agenda</h2>
    ${turnos.map((t) => `<div class="card static">
        ${new Date(t.inicio).toLocaleString('es-AR', { hour12: false })} — ${t.servicio} con ${t.cliente}
        <span class="pill ${t.estado === 'confirmado' ? 'ok' : 'warn'}">${t.estado}</span>
      </div>`).join('') || '<p><small>Sin turnos próximos.</small></p>'}
    <h2>Mis clientes</h2>
    ${clientes.map((c) => `<div class="card" data-id="${c.id}" data-nombre="${c.nombre}">👤 ${c.nombre} — <small>${c.email}</small></div>`).join('') || '<p><small>Sin clientes atendidos todavía.</small></p>'}
    <div id="historialCliente"></div>`;
  document.querySelectorAll('#vistaProfesional .card[data-id]').forEach((el) =>
    el.addEventListener('click', () => cargarHistorial(el.dataset.id, el.dataset.nombre))
  );
}

async function cargarHistorial(clienteId, clienteNombre) {
  const historial = await api('GET', `/clientes/${clienteId}/historial`);
  $('historialCliente').innerHTML = `
    <h2>Historial de ${clienteNombre}</h2>
    ${historial.map((v) => `<div class="card static">${new Date(v.inicio).toLocaleString('es-AR', { hour12: false })} — ${v.servicio} <span class="pill">${v.estado}</span></div>`).join('') || '<p><small>Sin visitas.</small></p>'}`;
}

// ---------- 3. Prueba de concurrencia ----------
$('btnConcurrencia').addEventListener('click', async () => {
  if (!ultimoSeed) return;
  $('btnConcurrencia').disabled = true;
  $('resultadoConcurrencia').innerHTML = 'Disparando...';
  try {
    const { profesional, servicio } = ultimoSeed;
    const { slots } = await api('GET', `/profesionales/${profesional.id}/slots?servicio_id=${servicio.id || ultimoSeed.servicio.id}`);
    const slotLibre = slots[0];
    if (!slotLibre) {
      $('resultadoConcurrencia').innerHTML = '<p class="error">No quedan slots libres — sembrá datos de nuevo.</p>';
      return;
    }

    // Dos clientes efímeros, uno por cada intento, para no chocar con el flujo de login manual.
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
        body: JSON.stringify({ profesional_id: profesional.id, servicio_id: servicio.id || ultimoSeed.servicio.id, inicio: slotLibre }),
      });
      return { status: res.status, data: await res.json() };
    };

    const [rA, rB] = await Promise.all([reservar(tokenA), reservar(tokenB)]);
    const render = (r, nombre) => `<div>
        <b>Cliente ${nombre}</b><br>
        <span class="pill ${r.status === 201 ? 'ok' : 'warn'}">HTTP ${r.status}</span>
        <pre style="white-space:pre-wrap">${JSON.stringify(r.data, null, 2)}</pre>
      </div>`;
    $('resultadoConcurrencia').innerHTML = render(rA, 'A') + render(rB, 'B');

    const exitosas = [rA, rB].filter((r) => r.status === 201).length;
    if (exitosas === 1) {
      $('resultadoConcurrencia').innerHTML += '<p>✅ <b>RN2 verificada:</b> exactamente 1 reserva exitosa sobre el mismo horario, la otra fue rechazada por conflicto.</p>';
    } else {
      $('resultadoConcurrencia').innerHTML += `<p class="error">⚠️ Se esperaba 1 reserva exitosa y hubo ${exitosas}.</p>`;
    }
  } catch (e) {
    $('resultadoConcurrencia').innerHTML = `<p class="error">${e.message}</p>`;
  } finally {
    $('btnConcurrencia').disabled = false;
  }
});
