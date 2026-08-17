# Backend — Turnos Profesionales

Modular monolito (ver `../../03-arquitectura/documento-arquitectura.md`). Node.js + TypeScript
+ Express. Persistencia de desarrollo con **`node:sqlite`** (built-in de Node ≥22.5, sin
compilación nativa); producción apunta a **PostgreSQL** (ver
`../database/migrations/001_init.sql`, DBA).

> `better-sqlite3` (elección original) requiere compilar un addon nativo vía node-gyp, y este
> entorno no tiene Visual Studio Build Tools instalado. Se optó por `node:sqlite` para no
> bloquear el desarrollo — es un cambio de driver, no de diseño; el esquema y la lógica de
> negocio son los mismos que se documentaron para Postgres.

## Cómo correr

```bash
npm install
npm run dev        # http://localhost:3000, recrea dev.sqlite3 desde las migraciones
```

`npm run dev` setea `ENABLE_DEV_ROUTES=true` automáticamente (ver sección "Fase 5" más abajo) —
si corrés el servidor de otra forma (`node dist/src/index.js`, `ts-node src/index.ts`, etc.) y
necesitás `/dev/seed` / `web-preview/`, seteá esa variable a mano.

## Pruebas manuales (smoke tests)

Con el servidor corriendo:

```bash
npm run test:smoke          # flujo completo: alta de negocio -> servicio -> profesional ->
                             # disponibilidad -> slots -> reserva -> conflicto secuencial ->
                             # clientes/historial -> cancelación
npm run test:concurrencia   # dispara 2 reservas SIMULTÁNEAS al mismo slot (Promise.all) y
                             # verifica que solo una tenga éxito (RN2) — correr después de
                             # test:smoke, sobre la misma DB
node scripts/test-reprogramacion-y-expiracion.mjs   # HU-13 + expiración automática — correr
                             # el server con EXPIRACION_PAGO_MIN=0 VENTANA_CANCELACION_MIN=0
```

Los tres scripts corrieron exitosamente durante el desarrollo, incluida la prueba de
concurrencia real (no solo secuencial) y la reprogramación con conflicto de slot.

Preview interactiva en el navegador: con el servidor corriendo, abrir `http://localhost:3000`
(sirve `web-preview/`, solo fuera de `NODE_ENV=production`) — permite sembrar datos de
ejemplo (`POST /dev/seed`), loguearse, navegar el flujo de Cliente/Profesional y disparar la
prueba de concurrencia desde la UI, sin instalar Flutter.

## Implementado en este slice

- Auth: registro de negocio+administrador, registro de cliente, login (JWT con
  `rol`/`negocio_id`/`profesional_id`), login/registro con Google (HU-35 — ver sección dedicada
  más abajo), recuperación de contraseña (HU-37 — ver sección dedicada más abajo).
- Negocios: alta, listado público, alta de servicios y profesionales (RN9 — scoping por
  `negocio_id` del JWT, nunca por parámetro).
- Profesionales: asociar servicio con seña configurable (D2/RN10), disponibilidad,
  excepciones (RN5/RN6), cálculo de slots con "próximo disponible" (D5), listado de clientes.
- Turnos: reserva con garantía anti-doble-reserva a nivel de base de datos (RN2, índice único
  parcial), cancelación con ventana mínima (RN8/A3), **reprogramación (HU-13)** reutilizando la
  misma garantía anti-doble-reserva y conservando el estado de pago, listado de turnos propios.
- Clientes: historial de visitas filtrado por profesional (D3/RN7).
- Pagos y Notificaciones: **interfaces + Mock** (`src/integraciones/`) — no se creó ninguna
  cuenta de Mercado Pago ni de Firebase (fuera del alcance permitido de un agente de IA);
  Integraciones debe reemplazar el Mock por el proveedor real cuando el CEO provea credenciales.
- **Expiración automática** de turnos `pendiente_de_pago` (`src/jobs/expirarPagosPendientes.ts`,
  cada 60s, ventana configurable con `EXPIRACION_PAGO_MIN`) — libera el slot si Mercado Pago no
  confirma el pago a tiempo.
- Endpoints `/dev/*` (seed + forzar expiración) solo activos fuera de `NODE_ENV=production`.
- **Configuración del lado Profesional** (Perfil, Privacidad, Consultorio, Pagos, Reportes — ver
  sección dedicada más abajo): `GET/PATCH /usuario/perfil`, `GET/PATCH /usuario/privacidad`,
  `GET/PATCH /negocios/:id`, `GET /profesionales/:id/servicios`,
  `PATCH /profesionales/:id/servicios/:servicioId`, `GET /profesionales/:id/reportes`.
- **E15 fast-follow — pausar/reactivar profesional y eliminar servicio** (ver sección dedicada más
  abajo): `PATCH /negocios/:id/profesionales/:profesionalId`,
  `DELETE /negocios/:id/servicios/:servicioId`.

## Row Level Security (Postgres)

Implementada en `../database/migrations/001_init.sql` (ver
`../../03-arquitectura/modelo-datos.md` §5) — **no verificable en este entorno** (sin
psql/Docker). El backend actual (`node:sqlite`) no necesita `SET LOCAL app.*` porque el
aislamiento multi-tenant ya se aplica en cada route handler; cuando el backend pase a
Postgres, hay que agregar `SET LOCAL app.negocio_id` / `app.usuario_id` al inicio de cada
transacción autenticada para que las políticas RLS tengan efecto.

## Pendiente (fuera de este slice)

- Frontend/Mobile — ver `../mobile/` (Flutter) y las pantallas de `04-diseno/mapa-pantallas.md`.
- Revisión de Security y despliegue de DevOps (fases 5 y 6 del proyecto).
- Conectar `SET LOCAL app.*` cuando el backend migre de `node:sqlite` a Postgres real.

## Fase 5 — remediación de hallazgos (Security + QA)

Ver `../../07-seguridad/informe-seguridad.md` y `../../06-qa/reporte-qa.md` para el detalle
completo de cada hallazgo. Resumen de lo corregido en este ciclo:

- **[CRITICAL-1] Login de administrador cross-tenant (rompía RN9).** El esquema ahora persiste
  `negocio.admin_usuario_id` (DBA, ver `migrations/001_init.sqlite.sql` y
  `../database/migrations/001_init.sql`). `POST /auth/login` resuelve el negocio del
  administrador con `SELECT id FROM negocio WHERE admin_usuario_id = ?` en vez de la query sin
  correlación anterior. `POST /auth/registro-negocio` (y `POST /dev/seed`) ahora crean el
  `usuario` administrador ANTES que el `negocio`, en la misma transacción. Test de regresión
  dedicado: `scripts/test-critical1-aislamiento-admin.mjs` (registra 3 negocios, loguea cada
  administrador por separado y verifica que el `negocio_id` del JWT es siempre el propio).
- **[DEF-01/RN1 y DEF-02] `POST /turnos` no validaba disponibilidad publicada ni solapamiento
  con `inicio` distinto.** El cálculo de slots (antes inline y duplicado en
  `GET /profesionales/:id/slots`) se extrajo a `src/dominio/disponibilidad.ts`
  (`calcularSlotsDisponibles`), compartido por ambos endpoints. `POST /turnos` ahora exige que
  `inicio` sea exactamente un slot de esa grilla: si no está alineado a ningún bloque de
  disponibilidad → `400` (RN1); si está alineado pero ya lo ocupa otro turno/excepción → `409`
  (RN2, mismo código que ya usaba el índice único ante una reserva duplicada exacta). Ver el
  comentario largo en `disponibilidad.ts` sobre por qué esto requirió una opción
  `ignorarOcupacion` para no convertir una reserva duplicada exacta en un `400` en vez de `409`.
- **[DEF-03/RN4] `POST /turnos` no validaba la asociación profesional↔servicio.** Si no existe
  fila en `profesional_servicio`, responde `404` "Este profesional no ofrece este servicio
  (RN4)" antes de calcular `requiere_sena` o insertar el turno.
- **[DEF-04] Fechas mal formadas producían `500`.** `inicio`/`nuevo_inicio` se validan con
  `isNaN(new Date(x).getTime())` antes de usarse, en `POST /turnos` y
  `PATCH /turnos/:id/reprogramar` (`400` limpio). `dia_semana` en
  `POST /profesionales/:id/disponibilidad` se valida como entero 0-6 en el handler en vez de
  dejar que el `CHECK` de la base tire una excepción sin capturar.
- **[HIGH-1] Rate limiting en `/auth/login` y `/auth/registro-*`.** Nuevo
  `src/middleware/rateLimit.ts` con `express-rate-limit`. `loginLimiter` cuenta solo intentos
  FALLIDOS (`skipSuccessfulRequests`, protege contra fuerza bruta sin penalizar tráfico legítimo
  de login); `registroLimiter` cuenta todos los intentos (protege contra alta masiva de
  cuentas). Default: 10 intentos / 15 min por IP (recomendación de Security), configurable vía
  `RATE_LIMIT_LOGIN_MAX`, `RATE_LIMIT_LOGIN_WINDOW_MIN`, `RATE_LIMIT_REGISTRO_MAX`,
  `RATE_LIMIT_REGISTRO_WINDOW_MIN` — subir estos valores fue necesario para correr la batería
  completa de scripts de prueba contra un único servidor (todos comparten la IP de loopback),
  sin tocar el default de producción.
- **[HIGH-2] Stack traces expuestos.** Middleware de manejo de errores centralizado (4
  argumentos, al final de `app.ts`): loguea el error completo server-side (`console.error`) y
  devuelve siempre `{"error":"Error interno"}` con `500`, sin stack trace, en todos los entornos.
- **[HIGH-3] `JWT_SECRET` con fallback hardcodeado.** `src/auth.ts` ahora falla al arrancar
  (`throw`, el proceso termina con código de salida distinto de 0) si `NODE_ENV=production` y
  `JWT_SECRET` no está seteado. El fallback (`dev-secret-not-for-production`) se mantiene solo
  para desarrollo/test.
- **[HIGH-4] `/dev/*` y `web-preview/` gateados solo por `NODE_ENV`.** Ahora es opt-in explícito:
  se montan únicamente si `process.env.ENABLE_DEV_ROUTES === 'true'` (sin importar `NODE_ENV`).
  `npm run dev` lo setea automáticamente vía `cross-env` (nueva dependencia de desarrollo); en
  cualquier otro modo de arranque hay que setearlo a mano a sabiendas de que se expone un
  endpoint de seed sin autenticación.

**No abordado en este ciclo (fuera del alcance que priorizó el Director General IA para esta
remediación):** los hallazgos Medium/Low de Security (política de contraseñas, cabeceras
`helmet`, validación de esquema tipo zod/joi más allá de fechas/`dia_semana`, política CORS) y
la nota informativa sobre el webhook de Mercado Pago (Integraciones). Quedan documentados en
`../../07-seguridad/informe-seguridad.md` para un ciclo posterior.

### Ciclo 2 — cierre de hallazgos Medium/Low (Security)

Ver `../../07-seguridad/informe-seguridad.md` para el detalle completo. Resumen de lo corregido:

- **[MEDIUM-1] Sin política de fortaleza de contraseñas.** Longitud mínima de 8 caracteres
  (`src/dominio/validacion.ts`, `passwordSchema`), aplicada de forma consistente en los 3 puntos
  donde se crea una contraseña: `POST /auth/registro-cliente`, `POST /auth/registro-negocio`
  (`src/routes/auth.ts`) y `POST /negocios/:id/profesionales` (`src/routes/negocios.ts`, como
  parte del schema de zod de ese endpoint). Responde `400` con mensaje claro si no cumple. No se
  agregó chequeo contra contraseñas filtradas (HaveIBeenPwned) — fuera de alcance de este ciclo.
- **[MEDIUM-2] Faltan cabeceras de seguridad HTTP.** `helmet` agregado como dependencia y
  montado en `app.ts` (`app.use(helmet())`) antes de las rutas. Verificado con `curl -D -`: ya no
  aparece `X-Powered-By` y sí aparecen `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, etc. No se configuró `Strict-Transport-Security` a mano (helmet la agrega
  por defecto; la terminación TLS real sigue siendo responsabilidad de DevOps en el reverse
  proxy).
- **[MEDIUM-3] Validación de entrada insuficiente.** `zod` agregado como dependencia; nuevo
  módulo `src/dominio/validacion.ts` con schemas reutilizables (`uuidSchema`, `fechaIsoSchema`,
  `diaSemanaSchema`, `horaSchema`, `montoPositivoSchema`, `passwordSchema`) y un helper
  `respuestaValidacionFallida` que responde `400` con el detalle campo-por-campo de zod (nunca un
  mensaje genérico). Aplicado al INICIO de los handlers, antes de tocar la base de datos, en:
  `POST /turnos`, `PATCH /turnos/:id/reprogramar` (`src/routes/turnos.ts`);
  `POST /profesionales/:id/disponibilidad`, `POST /profesionales/:id/excepciones`,
  `POST /profesionales/:id/servicios` (`src/routes/profesionales.ts`); `POST /negocios/:id/servicios`,
  `POST /negocios/:id/profesionales` (`src/routes/negocios.ts`). `negocio_id`/`servicio_id`/
  `profesional_id`/`turno_id` recibidos por parámetro o body ahora se validan como UUID bien
  formado, las fechas como ISO-8601 válido (misma semántica de aceptación que el chequeo
  `isNaN(new Date(x))` que ya existía — no se volvió ni más permisivo ni más estricto),
  `dia_semana` como entero 0-6, y `duracion_min`/montos como números positivos. Reemplaza (sin
  dejar huecos) las validaciones puntuales de fecha y `dia_semana` que ya existían de un ciclo
  anterior (DEF-04).
- **[LOW-1] Sin política CORS explícita.** No se instaló el paquete `cors` (Security lo marcó
  como no explotable hoy — consumo desde app mobile nativa + web-preview same-origin). Ver nota
  explícita más abajo en "Pendiente" sobre qué hacer antes de sumar un cliente web.
- **[LOW-2]** Ya subsumido por el gating `ENABLE_DEV_ROUTES` del ciclo anterior — sin acción
  adicional.

**Nota importante para cuando se sume un frontend web:** hoy no hay middleware `cors` instalado
(el consumo actual es desde una app mobile nativa, donde CORS no aplica, y desde `web-preview/`,
que es same-origin). Antes de que cualquier frontend web consuma esta API desde otro origen, hay
que configurar `cors` con una **allowlist explícita de orígenes permitidos — nunca wildcard
(`*`)**, dado que la autenticación es JWT Bearer (un wildcard combinado con credenciales
ampliaría innecesariamente la superficie de ataque).

Batería de tests re-corrida completa tras estos cambios sin fallos: `smoke-test.mjs`,
`test-concurrent-booking.mjs`, `test-reprogramacion-y-expiracion.mjs`,
`test-rn1-disponibilidad-y-solapamiento.mjs`, `test-rn4-servicio-no-asociado.mjs`,
`test-turno-sin-sena.mjs`, `test-validaciones-campos.mjs`, `test-autorizacion-cruzada.mjs`,
`test-critical1-aislamiento-admin.mjs` y `test-rn8-ventana-cancelacion.mjs` (este último contra
un servidor limpio con la ventana default, sin pisar `VENTANA_CANCELACION_MIN`). Ninguno requirió
ajustes: las aserciones ya validaban códigos de estado (`400`/`4xx`), no el texto exacto de los
mensajes de error.

### Scripts de prueba (actualizado)

- Nuevo: `scripts/test-critical1-aislamiento-admin.mjs` (regresión CRITICAL-1).
- `scripts/test-validaciones-campos.mjs` (de QA) se ajustó mínimamente: el setup ahora publica
  disponibilidad para el profesional/servicio de prueba y el "turno de setup" usado para probar
  `reprogramar` se reserva sobre un slot real obtenido de `GET /profesionales/:id/slots` en vez
  de un timestamp arbitrario — necesario porque, antes del fix de RN1, `POST /turnos` no exigía
  que `inicio` estuviera alineado a ningún bloque de disponibilidad publicado.
- Por las ventanas de configuración que necesita cada uno, correr la batería completa requiere
  al menos dos arranques del servidor:
  1. `EXPIRACION_PAGO_MIN=0 VENTANA_CANCELACION_MIN=0 ENABLE_DEV_ROUTES=true` (DB limpia): en
     ese orden, `smoke-test.mjs` → `test-concurrent-booking.mjs` (reutiliza la data del
     anterior) → el resto de los scripts (`test-reprogramacion-y-expiracion.mjs`, `test-rn1-*`,
     `test-rn4-*`, `test-turno-sin-sena.mjs`, `test-validaciones-campos.mjs`,
     `test-autorizacion-cruzada.mjs`, `test-critical1-aislamiento-admin.mjs`).
  2. Servidor limpio SIN pisar `VENTANA_CANCELACION_MIN` (usa el default de 120 min):
     `test-rn8-ventana-cancelacion.mjs` (está diseñado explícitamente para la ventana default).
- `scripts/test-multinegocio.mjs` (ver sección "Generalización 1:1 → N:M" más abajo) no depende
  de ninguna ventana especial — puede correr en cualquiera de los dos arranques de arriba.

## Generalización 1:1 → N:M (multi-negocio)

Ver `../../03-arquitectura/modelo-datos.md` §2ter (DBA) para el diseño completo. Un mismo
administrador o profesional ahora puede pertenecer a más de un negocio (ej. un entrenador que
atiende en dos gimnasios, o un dueño con varias sucursales). Las columnas 1:1
`negocio.admin_usuario_id` y `profesional.negocio_id` (ver CRITICAL-1 más arriba) fueron
reemplazadas por las tablas de asociación `negocio_administrador` / `negocio_profesional` (esta
última con `activo`, para pausar/reanudar una membresía sin perder el vínculo). Esto **no
reabre CRITICAL-1**: la corrección seguía siendo "correlacionar contra una relación persistida
real", que se mantiene — solo cambia la cardinalidad de esa relación, de 0/1 a 0..N.

- **JWT: "vista activa" (una de 3 opciones que dejó evaluadas DBA; esta es la elegida).** El
  token sigue llevando un único `negocio_id` (o ninguno) — nunca un array — para no tener que
  tocar la autorización existente (`req.auth.negocio_id !== req.params.id` en
  `negocios.ts`/`profesionales.ts`).
  - `POST /auth/login` (rol profesional/administrador) resuelve la membresía activa real. Si
    hay **exactamente 1** negocio, firma el token con ese `negocio_id` directo — igual que
    siempre, cero cambio de experiencia en el caso común de un solo negocio. Si hay **0 o 2+**,
    el token sale **sin** `negocio_id` y el body agrega `negocios: [{negocio_id, nombre, rol},
    ...]` (pensado para el ícono "cambiar de vista", HU-27) para que el cliente elija.
  - **`POST /auth/entrar-a-negocio`** (endpoint nuevo; body `{ negocio_id }`; requiere estar
    autenticado con cualquier rol vía `requireAuth()` sin roles — clientes también pueden
    llamarlo, pero nunca tienen membresía real así que caen al `403` por default): valida que
    exista una fila de membresía ACTIVA real para `(negocio_id, usuario_id o profesional_id
    según el rol)` — si no, `403` — y reemite el JWT con ese `negocio_id` fijado, conservando
    `sub`/`rol`/`profesional_id` del token original. Es el endpoint que llama la UI de "cambiar
    de vista" una vez que el usuario eligió uno de los `negocios` que devolvió el login.
  - Cualquier endpoint que ya comparaba el `negocio_id` del token contra `:id` sigue funcionando
    igual sin cambios: con el claim ausente (0 o 2+ negocios sin "entrar" a ninguno todavía), la
    comparación falla y devuelve `403` por defecto — sin necesidad de un caso especial.
- **`POST /negocios/:id/profesionales` (HU-02) reusa identidades en vez de duplicar.** Si el
  email ya pertenece a un profesional existente (dado de alta antes por otro negocio), se reusa
  esa fila de `profesional` por `usuario_id` — nunca se duplica ni se pisan sus credenciales
  (`password`/`nombre` del body se ignoran en ese caso, para que un segundo negocio no pueda
  "tomar" la cuenta de un profesional que ya trabaja en otro lado) — y solo se agrega el vínculo
  nuevo en `negocio_profesional`. Re-dar de alta a alguien que ya es miembro activo del MISMO
  negocio responde `409`; si la membresía estaba pausada (`activo=0`), se reanuda.
- **`turno.negocio_id` ahora sale de `servicio.negocio_id`**, no del profesional (que ya no
  tiene un negocio fijo propio) — un servicio sigue siendo 1:1 con su negocio, así que es
  inequívoco sin importar en cuántos negocios trabaje el profesional elegido.
- **Validación de integridad nueva** (antes imposible de violar bajo el esquema 1:1, ahora sí
  posible si no se valida): tanto `POST /profesionales/:id/servicios` como `POST /turnos`
  confirman que exista una fila `negocio_profesional` con `activo=1` para `(negocio del
  servicio, profesional)` antes de insertar — si no, responden `403`/`404` respectivamente.

Test dedicado: `scripts/test-multinegocio.mjs` — alta del mismo profesional (mismo email) en 2
negocios sin duplicar identidad ni pisar credenciales, login con 2 negocios activos (token sin
`negocio_id`, body con `negocios`), `POST /auth/entrar-a-negocio` (negocio propio y negocio
ajeno), caso simple de 1 solo negocio sin pasos extra, y `turno.negocio_id` resuelto por el
servicio reservado — verificado leyendo el campo directamente desde `GET /turnos/mios` (que
usa `SELECT *` y expone `negocio_id` tal cual quedó persistido), no solo de forma indirecta.

## Duración de cita configurable por el profesional (D10)

Ver `../../03-arquitectura/modelo-datos.md` §2quater (DBA) y `../../01-requisitos/documento-funcional.md`
D10 (amenda RN3). El profesional puede configurar su propia duración general de cita
(`profesional.duracion_cita_min`, columna nullable agregada por DBA). Cuando está seteada,
**reemplaza siempre** `servicio.duracion_min` para calcular sus turnos — en TODOS sus
servicios, sin excepción. `NULL` (default, sin configurar) preserva el comportamiento de
siempre: se sigue usando la duración del servicio.

- **Endpoint nuevo: `PATCH /profesionales/:id/configuracion`** (`requireAuth('profesional')` +
  `esPropioProfesional`, mismo patrón de autorización que el resto de `profesionales.ts`). Body:
  `{ duracion_cita_min: number | null }`, validado con `zod` — entero positivo o `null`
  EXPLÍCITO (el campo es obligatorio, no `.optional()`, para forzar una decisión consciente;
  `null` es la forma de volver a usar la duración del servicio si el profesional se arrepiente).
- **Un solo lugar decide el fallback, dos endpoints lo heredan gratis.**
  `calcularSlotsDisponibles` (`src/dominio/disponibilidad.ts`) ahora también lee
  `profesional.duracion_cita_min` y usa `profesional?.duracion_cita_min ?? servicio.duracion_min`
  para el tamaño de paso de la grilla — alcanza para corregir tanto `GET /profesionales/:id/slots`
  como la validación RN1/RN2 de `POST /turnos`, que reutiliza la misma función.
- **`POST /turnos`** calcula `finDate` reusando `slotsLibres.duracionMin` (el valor que ya
  devolvió `calcularSlotsDisponibles` con el fallback aplicado) en vez de recalcular a partir de
  `servicio.duracion_min` — evita una segunda fuente de verdad que se pueda desincronizar del
  slot realmente validado.
- **`PATCH /turnos/:id/reprogramar` tenía el mismo gap de forma independiente** (calculaba
  `nuevoFinDate` directo desde `servicio.duracion_min`, sin mirar el override del profesional) —
  corregido en el mismo ciclo: ahora consulta `profesional.duracion_cita_min` y aplica el mismo
  fallback, para que reprogramar conserve la duración con la que se reservó originalmente.

Test dedicado: `scripts/test-duracion-configurable.mjs` — caso de control (sin override
configurado, se sigue usando la duración del servicio), override configurado vía el endpoint
nuevo (los slots calculados y el turno reservado usan la nueva duración, no la del servicio),
reprogramación de ese turno con el mismo override activo, y reversibilidad (volver a `null`
restaura la duración del servicio, no solo queda probado que el override funciona) — más
autorización (un profesional no puede configurar la duración de otro) y validación
(negativo, cero, campo faltante).

## Login con Google (HU-35)

Ver `../../02-backlog/backlog.md` (HU-35) para el backlog aprobado por el CEO y la regla de
vinculación de cuentas cerrada por Security, y `../../07-seguridad/informe-seguridad.md`
(Adenda 2026-08-10, parte A) para el razonamiento completo de esa regla;
`../../03-arquitectura/modelo-datos.md` §2sexies para el modelado de datos (DBA —
`usuario.password_hash` nullable + `usuario.google_id`). Alternativo al login/registro por
contraseña (`POST /auth/login`, `POST /auth/registro-cliente`, `POST /auth/registro-negocio`),
que sigue funcionando exactamente igual, sin cambios, para quien no usa Google.

- **`POST /auth/google`** — body `{ "id_token": string }` (el ID token JWT que devuelve el SDK
  de Google Sign-In del lado del cliente; no confundir con un access token). Se verifica con
  `google-auth-library` contra `GOOGLE_CLIENT_ID` (ver `.env.example`) — si esa variable no
  está seteada, responde `503` en vez de romper el arranque de la app (mismo criterio de opt-in
  explícito que `ENABLE_DEV_ROUTES`).
  - Cuenta ya vinculada (`google_id` coincide, login recurrente): `200 { token }` o
    `200 { token, negocios }` — mismo shape/claims que `POST /auth/login`.
  - Sin cuenta previa con ese email: alta nueva (rol `cliente`, igual que
    `POST /auth/registro-cliente`) solo si el token trae `email_verified: true` → `201 { token }`;
    si viene `false`, `403`.
  - Ya existe una cuenta creada por contraseña con ese email: la vinculación automática está
    PROHIBIDA (regla de Security, HU-35, ni siquiera con `email_verified: true` — riesgo de
    account takeover vía email reciclado/cuenta Google comprometida). Responde
    `409 { error, requiere_confirmacion_password: true }` — el cliente debe confirmar la
    contraseña existente reenviando ese mismo `id_token` a `POST /auth/login` (ver abajo).
- **`POST /auth/login`** acepta ahora, además de `email`/`password`, un `id_token` opcional del
  mismo tipo — es el paso de confirmación de la vinculación de arriba: si la contraseña es
  correcta y el `id_token` es válido y corresponde al mismo email de la cuenta, persiste
  `usuario.google_id` (solo si todavía no estaba vinculada) y responde el login normalmente.
  Reutiliza el mismo `loginLimiter` (HIGH-1) que ya protege el login por contraseña, en vez de
  abrir un endpoint nuevo de superficie de fuerza bruta.
- `usuario.password_hash` ahora es nullable (cuenta dada de alta 100% por Google) —
  `POST /auth/login` valida explícitamente que no sea `NULL` antes de comparar contra bcrypt
  (una cuenta sin contraseña propia responde `401`, igual que una contraseña incorrecta).

No probado end-to-end: todavía no existe un `GOOGLE_CLIENT_ID` real (DevOps está resolviendo el
alta de credenciales OAuth en Google Cloud Console, ver backlog.md HU-35). Verificado con
`npx tsc --noEmit` (sin errores).

## Recuperación de contraseña (HU-37)

Ver `../../02-backlog/backlog.md` (HU-37, épica E4) para los criterios de aceptación completos
aprobados por el CEO, y `../../03-arquitectura/modelo-datos.md` §2decies/§5octies (DBA) para el
modelado de `token_recuperacion_password` y por qué esa tabla deliberadamente NO tiene Row Level
Security. Flujo funcional en 2 pasos, sin deep-linking (no hay deep-linking configurado en el
proyecto): el usuario pide la recuperación por email, recibe un token, y lo copia/pega junto con
la nueva contraseña en una segunda pantalla — el token es la ÚNICA prueba de identidad de ese
segundo paso.

- **`POST /auth/recuperar-password`** — body `{ "email": string }`. Genera un token de un solo
  uso, aleatorio (`crypto.randomBytes(32)`) y de un solo uso, lo guarda hasheado (SHA-256, no
  bcrypt — el token ya es de alta entropía, no necesita costo adaptativo) con expiración de 30
  minutos (`RECUPERACION_PASSWORD_TTL_MIN`, configurable solo para pruebas). Invalida cualquier
  token pendiente anterior del mismo usuario antes de insertar el nuevo (a lo sumo 1 token
  pendiente por usuario, garantizado por un índice único parcial). "Envía" el email vía
  `EmailProvider` (`src/integraciones/email.ts` — interfaz + `MockEmailProvider`, mismo patrón que
  `pagos.ts`; el envío real queda pendiente de que el CEO provea una cuenta de un proveedor real,
  SendGrid/Resend/AWS SES).
  - **Respuesta siempre `200` con el mismo mensaje genérico** (`{ "ok": true, "mensaje": "Si el
    email está registrado, vas a recibir instrucciones para recuperar tu contraseña." }`), exista
    o no la cuenta, y también si la cuenta existe pero fue dada de alta 100% por Google
    (`password_hash IS NULL`, HU-35 — no tiene contraseña que restablecer). Mitigación de
    enumeración de usuarios — pendiente de validación de Security (criterio explícito de HU-37).
  - **Solo con `ENABLE_DEV_ROUTES=true`** (mismo gate que `src/routes/dev.ts`), y solo cuando sí
    se generó un token, la respuesta suma `token_dev` (el token en texto plano) — no hay
    proveedor de email real todavía; es la forma de poder probar el flujo de punta a punta en
    desarrollo, además del log que emite `MockEmailProvider` bajo el mismo gate. Nunca presente en
    producción (`ENABLE_DEV_ROUTES` queda en `false` en Render, ver `render.yaml`).
  - `400` si falta `email`.
- **`POST /auth/reset-password`** — body `{ "token": string, "password": string }` (nunca
  `usuario_id` ni `email` — el token es la única prueba de identidad). `password` se valida con la
  misma política mínima del resto del proyecto (`passwordSchema`, 8 caracteres). Busca el hash del
  token recibido, exige que exista, no esté usado y no haya expirado; si no, `400 { "error":
  "Token inválido o vencido" }` (mismo mensaje para "nunca existió"/"vencido"/"ya usado", sin
  distinguir cuál). Si es válido, actualiza `usuario.password_hash` (bcrypt, igual que
  login/registro) y marca el token usado en la misma transacción — si una carrera de doble-submit
  hace que otro request ya lo haya canjeado en el medio, aborta sin aplicar el cambio de
  contraseña y responde el mismo `400`.
- Ambos endpoints comparten un rate limiter dedicado (`recuperacionPasswordLimiter`,
  `src/middleware/rateLimit.ts`, configurable vía `RATE_LIMIT_RECUPERACION_MAX`/
  `RATE_LIMIT_RECUPERACION_WINDOW_MIN`) — no reusa `loginLimiter` (que solo cuenta intentos
  fallidos y por eso no protegería `/recuperar-password`, que siempre responde `200`).

Verificado de punta a punta contra un Postgres real (instancia local efímera, ver
`memory/proyectos/turnos-profesionales/decisiones.md`): `npx tsc --noEmit` limpio y
`scripts/test-recuperacion-password.mjs` corrido en verde (caso feliz, token de un solo uso,
no-enumeración para email inexistente y cuenta 100%-Google, invalidación de tokens anteriores,
password inválida, token vencido, token con formato inválido, campos faltantes), más la batería
de regresión existente (`smoke-test.mjs`, `test-validaciones-campos.mjs`,
`test-autorizacion-cruzada.mjs`) sin fallos. **Pendiente:** proveedor de email real (bloqueante de
lanzamiento, no de desarrollo — ver nota operativa en `02-backlog/backlog.md`), pantallas Mobile
("Olvidé mi contraseña"/"Nueva contraseña", sin wireframe todavía) y aplicar
`../database/migrations/008_recuperacion_password.sql` contra Render.

## Notificaciones — bandeja + configuración granular (HU-14b/HU-25/HU-26)

Ver `../database/migrations/001_init.sql` (bloques "Bandeja de notificaciones" y "Preferencias
de notificación", DBA) y `004_notificaciones.sql` (delta aplicado a mano contra Render) para el
modelo de datos completo: `notificacion` gana `destinatario_usuario_id` / `leido` /
`modificado_en` y `tipo` pasa a ENUM (`tipo_notificacion`); tabla nueva
`usuario_preferencias_notificacion` (7 booleanos). Router nuevo `src/routes/notificaciones.ts`,
montado en `/notificaciones` — ver la nota de diseño al inicio de ese archivo sobre por qué no
`/usuario/notificaciones` (`src/routes/usuario.ts` no existe en esta rama; lo crea en paralelo
`feature/configuracion-profesional`, todavía no mergeada, con otro contenido).

- **3 INSERT completados/agregados en `src/routes/turnos.ts`** (gap que DBA dejó documentado en
  `001_init.sql`, bloque "Bandeja de notificaciones", como recomendación para Backend):
  `POST /turnos` y `PATCH /turnos/:id/reprogramar` ahora completan `destinatario_usuario_id` (el
  profesional del turno) en el INSERT de `notificacion` que ya existía; `PATCH
  /turnos/:id/cancelar` no insertaba ninguna notificación — se agrega, `tipo='cancelacion'`,
  mismo destinatario. Ninguno de los 3 necesita cambiar de identidad de RLS (a diferencia del
  alta de `paciente` en `POST /turnos`): los 3 corren autenticados como `cliente`, y la policy
  `notificacion_insert_evento_turno` (`004_notificaciones.sql`) ya contempla que el cliente
  inserte con destinatario = el profesional del turno.
- **`GET /notificaciones`** — bandeja del usuario autenticado (cualquier rol, sobre sí mismo),
  `[{ id, tipo, leido, creado_en, turno_id, mensaje }, ...]`, más nuevas primero. `mensaje` es el
  texto en español ya armado (`src/dominio/notificaciones.ts`, `armarMensajeNotificacion` — JOIN
  `turno` + `usuario` (cliente) + `profesional` + `usuario` (profesional); sin texto congelado en
  la fila, mismo criterio documentado por DBA). **No agrupa "Hoy"/"Ayer"** (mapa-pantallas.md
  §5.15): devuelve una lista plana ordenada por `creado_en DESC`, mismo criterio ya establecido
  en este backend para listas similares (`GET /turnos/mios`, `GET /clientes/:id/historial`).
  "Hoy"/"Ayer" es relativo a la zona horaria del dispositivo, que el backend no conoce (no viaja
  en el JWT) — agrupar acá asumiría una zona horaria fija; Mobile agrupa con su propio reloj
  local sobre `creado_en` (ISO-8601 completo).
- **`PATCH /notificaciones/:id/leer`** — marca una notificación propia como leída. `404` uniforme
  si no existe o no es propia (no se distingue: acá no hay ningún caso de uso que necesite
  diferenciar 403/404, a diferencia de `turnos.ts`).
- **`PATCH /notificaciones/leer-todas`** — marca todas las no leídas del usuario autenticado,
  responde `{ actualizadas: number }`.
- **`GET /notificaciones/configuracion` / `PATCH /notificaciones/configuracion`** (HU-26,
  mapa-pantallas.md §5.14) — mismo patrón lazy-upsert que `GET`/`PATCH /usuario/privacidad`
  (HU-32, `feature/configuracion-profesional`): el GET devuelve los 7 defaults de fábrica si la
  cuenta nunca guardó nada (nunca `404`); el PATCH hace `INSERT ... ON CONFLICT (usuario_id) DO
  UPDATE` con el objeto de 7 booleanos completo (mismo criterio de "reenviar el formulario
  entero" que el resto de los PATCH de configuración de este backend).
- **Job nuevo: `src/jobs/recordarTurnosProximos.ts`**, mismo mecanismo que
  `expirarPagosPendientes.ts` (`setInterval`, default 60s). Inserta `tipo='recordatorio'` para
  turnos `pendiente_de_pago`/`confirmado` que arrancan dentro de la próxima hora
  (`VENTANA_RECORDATORIO_MIN`, default 60 — ver `.env.example`) y todavía no tienen un
  recordatorio insertado para ese turno.
  - **Hallazgo de RLS encontrado al implementarlo, corregido en el propio job (no con una
    migración nueva — cambio de esquema, fuera del alcance de Backend):** `notificacion` no tiene
    ninguna policy de `SELECT` que reconozca `app.job_sistema` (solo la de `INSERT`,
    `notificacion_insert_job_sistema`) — a diferencia de `turno`, que sí tiene una policy de
    SELECT pública (`turno_select_publico`). Un `NOT EXISTS` contra `notificacion` corriendo solo
    con `jobSistema: true` vería siempre 0 filas y duplicaría el recordatorio en cada corrida,
    sin ningún error visible (RLS deniega en silencio). Se resuelve con la misma técnica que ya
    usa `POST /turnos` para un problema análogo (cambiar `app.usuario_id` a mitad de
    transacción): el job impersona al destinatario puntual de cada turno candidato justo antes de
    su propio `INSERT ... WHERE NOT EXISTS`; bajo esa identidad, `notificacion_select_propia` sí
    deja ver sus recordatorios ya existentes. Ver el comentario completo en el propio archivo.
  - **Recomendación para DBA/Director General IA** (no implementada acá): una policy de SELECT
    dedicada para `app.job_sistema` en `notificacion` (análoga a `turno_acceso_job_expiracion`)
    sería más directa a nivel de esquema que esta impersonación por fila.
  - **Recomendación para QA/Security:** este gap no lo detecta ningún test HTTP existente (RLS
    deniega leyendo 0 filas, no tira error) — vale la pena agregar este escenario a
    `../database/scripts/verificar_rls_postgres.sql` cuando exista.
  - **`POST /dev/forzar-recordatorios`** (mismo criterio que el ya existente
    `POST /dev/forzar-expiracion`, solo activo con `ENABLE_DEV_ROUTES=true`): corre el job ya
    mismo, sin esperar el intervalo real, para poder probarlo a mano.
- `notificacionProvider.enviar` (`src/integraciones/notificaciones.ts`) sigue sin invocarse desde
  ningún endpoint, a propósito: sigue siendo un stub que solo loguea (D4 no resolvió todavía qué
  proveedor de push real se usa) — conectar el "envío" real queda como decisión de un ciclo
  futuro, no de este (que pedía bandeja + configuración + recordatorio, no delivery real).

Verificado end-to-end contra Render (Director General IA): reserva de turno → notificación de
confirmación con mensaje real; cancelación → notificación nueva; marcar leída (individual y en
lote); configuración con persistencia confirmada vía `GET` después de `PATCH`. Confirmado también
visualmente en el navegador con la app Flutter real.

## Configuración del lado Profesional (Perfil, Privacidad, Consultorio, Pagos, Reportes)

Completa 5 pantallas de Configuración que hasta este ciclo eran placeholder "Próximamente"
(ver `../04-diseno/mapa-pantallas.md` §5.11/§5.11bis). Antes de escribir código se relevó qué ya
existía — 2 de los 5 bloques reusan/extienden endpoints ya existentes en vez de crear todo de
cero (ver el detalle de cada uno).

- **Editar Perfil** — `GET/PATCH /usuario/perfil`. Router nuevo, `src/routes/usuario.ts`, montado
  en `/usuario` (ver ese archivo para el razonamiento completo de nombre/ubicación — no existía
  ningún endpoint genérico de "mi perfil" antes). Cualquier rol autenticado, siempre sobre uno
  mismo. Campos editables: `nombre`, `telefono` (columna ya existente en `usuario`). `email` es
  de **solo lectura** en este ciclo — es el identificador único de login; cambiarlo implica
  validar colisión de unicidad y, para cuentas vinculadas a Google (HU-35), desincronización con
  el email real de esa cuenta — fuera de alcance de esta ronda. `usuario` no tiene RLS (gap ya
  documentado, preexistente) — mismo patrón que auth.ts: `pool.query` directo, sin transacción.
- **Privacidad** — `GET/PATCH /usuario/privacidad` (mismo router). Opera sobre
  `usuario_preferencias` (HU-32, DBA — ver `001_init.sql`/`003_privacidad_usuario.sql`). La fila
  puede no existir para una cuenta creada antes de este ciclo (DBA no puso alta automática): el
  GET devuelve los defaults de la tabla (`publico`/`true`/`true`) en vez de `404`; el PATCH es
  upsert (`INSERT ... ON CONFLICT (usuario_id) DO UPDATE`), mismo patrón que
  `PATCH /profesionales/:id/pacientes/:pacienteId`. `usuario_preferencias` SÍ tiene RLS FORCE — a
  diferencia de Perfil, tanto el GET como el PATCH van con `withTransaction` y contexto
  (`usuarioId`): sin `app.usuario_id` seteado, la policy devolvería 0 filas siempre, incluso para
  una cuenta que ya personalizó su privacidad.
- **Configuración de Consultorio** — `PATCH /negocios/:id` (nuevo) + `GET /negocios/:id` (nuevo,
  público — no existía un detalle de negocio puntual, solo el listado `GET /negocios`; se agregó
  para que Mobile pueda prefillear el formulario sin traer la lista completa). Edita
  `nombre`/`rubro`/`ubicacion` (ya existentes en `negocio`) y, desde 2026-08-17 (HU-31, ver sección
  dedicada más abajo), también `horario_atencion`/`direccion`/`telefono`/`logo_url`. Solo
  `administrador`, y solo sobre su propio negocio (`req.auth.negocio_id`, mismo patrón RN9 que el
  resto de `negocios.ts`). `es_rubro_salud` queda explícitamente fuera de este PATCH (no estaba en
  el alcance del ciclo, y cambiarlo tiene implicancias de producto que exceden un campo más de un
  formulario descriptivo).
- **Configuración de Pagos (Precios y Señas)** — `GET /profesionales/:id/servicios` (nuevo — no
  existía un listado de "mis servicios asociados con su seña actual") +
  `PATCH /profesionales/:id/servicios/:servicioId` (nuevo). El alta de la primera asociación
  sigue siendo `POST /profesionales/:id/servicios` (sin cambios — ya era upsert-friendly, `ON
  CONFLICT ... DO UPDATE`, así que técnicamente ya soportaba editar; el PATCH nuevo es más angosto
  a propósito: no re-verifica membresía del negocio en cada edición y responde `404` en vez de
  crear si la asociación no existe todavía).
- **Reportes y Estadísticas** — `GET /profesionales/:id/reportes` (nuevo). HU-28/E10, v1
  simplificada, **lado Profesional únicamente en este ciclo** (no se construye la vista de
  negocio/administrador, HU-28 la pide pero la consigna de este ciclo la difiere explícitamente).
  Devuelve `turnos_totales`, `turnos_completados`, `turnos_cancelados`, `monto_facturado`,
  filtrables por período (`desde`/`hasta` sobre `turno.inicio`) y `servicio_id` — los 3 criterios
  de aceptación básicos que ya cerró HU-28 (`02-backlog/backlog.md`). Fuera de esta v1 (documentado
  en el propio código, no un olvido): exportar y métricas avanzadas (ambos explícitamente fuera de
  alcance en HU-28), y el filtro "por profesional" (no aplica — el endpoint ya está scopeado a
  uno). `turnos_completados`/`monto_facturado` reusan la misma derivación que ya recomienda DBA
  para "Completadas" en HU-21 (`estado = 'confirmado' AND fin < now()` — `estado_turno` no tiene
  un valor `'completado'` propio); `turnos_totales` excluye `estado = 'reprogramado'` (decisión
  propia, no explícita en HU-28: la fila vieja de un turno reprogramado no debe contarse junto a
  la fila nueva que representa la misma cita real).

Contrato completo de cada endpoint (verbo, ruta, body, response, códigos de error) documentado en
los comentarios de `src/routes/usuario.ts`, `src/routes/negocios.ts` y
`src/routes/profesionales.ts`, junto a cada handler.

Verificado con `npx tsc --noEmit` y `npm run build` (sin errores). **No verificado end-to-end
contra un servidor real en este ciclo**: la única base disponible para pruebas manuales
(`DATABASE_URL` de Render en `.env`) no fue alcanzable por red desde este entorno de desarrollo
(`ECONNRESET` en cada intento de conexión, confirmado con una prueba de conectividad directa
aislada del código de la app — no es un bug de este código, es una restricción de red del
entorno). Pendiente para quien corra esto en un entorno con salida de red real: correr
`npm run dev` y ejercitar los 6 endpoints de arriba (o el smoke test manual que se haya armado)
antes de dar por buena la integración end-to-end.

**Actualización (Director General IA, 2026-08-12):** verificado end-to-end contra Render — las 5
pantallas recorridas en el navegador con la app Flutter real (cuenta demo), reflejando
exactamente los datos cargados antes por API en cada una (perfil, privacidad, seña, reportes).

## E15 fast-follow — pausar/reactivar un profesional y eliminar (soft-delete) un servicio

Completa el gap que dejaba documentado explícitamente el backlog (`../02-backlog/backlog.md`, E15
"Fuera de alcance de v1-Administrador": *"Baja/pausa de un profesional del negocio, o remoción de
un servicio. Ninguno de los dos tiene endpoint (negocios.ts solo tiene alta para ambos
recursos)"*). **Sin migración nueva** — el modelo de datos ya soportaba ambas operaciones desde
Fase 3 (`negocio_profesional.activo` / `servicio.eliminado_en`, ver
`../database/migrations/001_init.sql`), solo faltaban los endpoints.

- **`PATCH /negocios/:id/profesionales/:profesionalId`**, body `{ activo: boolean }` -> 200
  `{ id, activo }` | 400 | 402 (solo reactivando, ver HU-29 abajo) | 403 | 404 (sin membresía en
  este negocio). Actualiza ÚNICAMENTE la membresía (`negocio_profesional.activo`), nunca la
  identidad (`profesional`/`usuario`, que puede seguir activa en otros negocios — N:M).
  Investigado contra el código real (no asumido) qué implica pausar para el resto del sistema —
  detalle completo en el comentario del propio handler, `src/routes/negocios.ts`:
  - **Ya bloqueado de punta a punta, sin tocar nada más**: HU-08
    (`GET /:id/servicios/:servicioId/profesionales`) ya filtraba `activo = true`; `POST /turnos` y
    `POST /profesionales/:id/turnos` ya exigían membresía activa antes de aceptar un turno nuevo
    (doble barrera oferta+reserva preexistente).
  - **El roster del administrador (`GET /:id/profesionales`) ya estaba pensado para esto**: sigue
    listando al profesional pausado, marcado `activo:false` — nunca desaparece de la lista.
  - **Login**: la cuenta/password no se tocan — el profesional pausado sigue pudiendo loguearse,
    pero deja de ver este negocio entre los suyos (o pierde `negocio_id` directo del token si era
    su único negocio) y no puede volver a seleccionarlo como vista activa
    (`POST /auth/entrar-a-negocio` ya revalida `activo=true` contra la tabla real).
  - **HU-29 (Turnario Pro)**: reactivar (`activo:true`) pasa por el MISMO chequeo del límite "1
    profesional activo" del plan gratis que ya exigía `POST /negocios/:id/profesionales` en su
    propia rama de reactivación — sin este chequeo, el PATCH nuevo habría sido una segunda vía
    para saltearse ese límite. Se evalúa solo en la transición real inactivo→activo (no bloquea
    reconfirmar `activo:true` sobre una membresía que ya lo estaba).
  - **Turnos ya existentes (pasados o futuros) con este profesional**: sin cambios — el endpoint
    nunca toca `turno`. Cancelarlos en cadena queda fuera de este alcance a propósito (decisión de
    producto de notificar/reembolsar que no corresponde asumir acá).
  - **2 hallazgos documentados en el propio código, confirmados EN VIVO por el script de
    verificación, y NO corregidos en este ciclo** (ninguno habilita reservar, que era el riesgo
    real a evitar): `GET /profesionales/:id/slots` no filtra por `negocio_profesional.activo`
    (sigue devolviendo horarios "disponibles" para un profesional pausado); un JWT ya emitido
    antes de pausar sigue siendo válido hasta que expira (2h) para lo que ya autorizaba (esta API
    no tiene revocación de sesión).
- **`DELETE /negocios/:id/servicios/:servicioId`** -> 200 `{ id, eliminado: true }` | 400 | 403 |
  404 (no existe, ya eliminado, o de otro negocio). Soft-delete
  (`servicio.eliminado_en = now()`), nunca `DELETE` físico — la FK `turno.servicio_id` es `NOT
  NULL`, no se puede romper el historial.
  - Revisada, una por una, cada query de `servicio` de todo `src/` (pedido explícito de la
    consigna) — detalle completo en el comentario del handler, `src/routes/negocios.ts`:
    - Ya filtraban `eliminado_en IS NULL` (sin cambios): el catálogo público
      (`GET /negocios/:id/servicios`) y "mis servicios" del profesional
      (`GET /profesionales/:id/servicios`).
    - **Bug real encontrado y corregido en este mismo cambio** (no solo documentado): `POST
      /turnos` (turnos.ts) y `POST /profesionales/:id/turnos` (profesionales.ts) NO filtraban
      `eliminado_en` en su lookup de `servicio` — un servicio dado de baja seguía siendo
      RESERVABLE si se conocía su id. Se agregó `AND eliminado_en IS NULL` a ambos `SELECT` (cae
      al mismo 404 "no encontrado" que ya existía para "no existe" — ningún contrato nuevo).
    - 3 lecturas que NO filtran y quedan sin tocar, documentadas como hallazgo (ninguna permite
      reservar por sí sola, así que no eran el riesgo real): `GET /:id/servicios/:servicioId/
      profesionales` (HU-08), `POST /profesionales/:id/servicios` (auto-asociación del
      profesional) y `GET /profesionales/:id/slots` (mismo motivo que el hallazgo análogo de
      arriba — comparten `calcularSlotsDisponibles`, que tampoco filtra). `PATCH /turnos/:id/
      reprogramar` A PROPÓSITO tampoco filtra: un turno vigente para un servicio ya discontinuado
      se tiene que poder seguir reprogramando/cancelando.
    - Reportes (`GET /negocios/:id/reportes`, `GET /profesionales/:id/reportes`) e historial
      (`GET /clientes/:id/historial`) A PROPÓSITO nunca filtran por `eliminado_en` — tienen que
      seguir mostrando turnos históricos de servicios ya eliminados (facturación pasada real).

Contrato completo de ambos endpoints documentado en los comentarios de `src/routes/negocios.ts`,
junto a cada handler.

**Verificado end-to-end contra Render real** con un script nuevo,
`scripts/test-baja-profesional-y-eliminacion-servicio.mjs`: pausar/reactivar (incluido el límite
de plan gratis aplicado a la reactivación, HU-29), eliminar un servicio (con un turno reservado
ANTES de eliminarlo confirmado como legible después — "mis turnos" del cliente, historial del
profesional y reportes de ambos lados, todos sin romperse), los 4 casos negativos de autorización
(401 sin token / 403 rol equivocado / 403 negocio ajeno / 404 cross-negocio y 404 inexistente)
para cada endpoint, y los 2 hallazgos documentados arriba confirmados EN VIVO (no solo leídos en
el código: se pidieron slots reales para un profesional pausado y para un servicio eliminado, y
ambos efectivamente los devolvieron). Se re-corrió además, contra el mismo servidor, una batería
de 8 scripts preexistentes sin relación directa con este cambio (`test-validaciones-campos`,
`test-multinegocio`, `test-autorizacion-cruzada`, `test-critical1-aislamiento-admin`,
`test-rn1-disponibilidad-y-solapamiento`, `test-rn4-servicio-no-asociado`,
`test-duracion-configurable`, `test-turno-sin-sena`) para confirmar que el fix de `eliminado_en`
en `POST /turnos`/`POST /profesionales/:id/turnos` no rompió ningún camino existente de reserva —
los 8 en verde. `smoke-test.mjs` falló, por un motivo confirmado NO relacionado con este cambio:
usa el email fijo `admin@garcia.test`, ya registrado en esta base de Render desde una ronda
anterior (2026-08-10, confirmado consultando la fila directo) — ese script está pensado para una
base efímera/recién migrada, no para esta base compartida persistente que reusan las rondas de
verificación de este proyecto.

## HU-31 — Datos operativos del negocio (horario, dirección, teléfono, logo)

Cierra la mitad de Backend del gap que dejó documentado explícitamente DBA
(`../03-arquitectura/modelo-datos.md` §2undecies, 2026-08-17): HU-31 pide "horario general de
atención, dirección detallada, teléfono/contacto, logo o imagen" además de nombre/rubro/ubicación,
pero la ronda "Modo Administrador v1" (E15) había conectado `PATCH /negocios/:id` únicamente a los
3 campos que ya tenían columna. DBA agregó 4 columnas nuevas `TEXT` nullable en `negocio`
(`horario_atencion`, `direccion`, `telefono`, `logo_url` — ver esa misma sección para el porqué de
cada una, en particular por qué `direccion` es una columna nueva y no una ampliación de
`ubicacion`); este cambio extiende el endpoint para aceptarlas y persistirlas.

- **`actualizarNegocioSchema`** (`src/routes/negocios.ts`) suma los 4 campos, mismo patrón EXACTO
  que `rubro`/`ubicacion`: `z.string().nullable()`, nunca `.optional()` — hay que poder mandar
  `null` explícito para vaciar un campo ya cargado, no alcanza con omitirlo del body (el body sigue
  siendo el formulario COMPLETO, no un patch parcial). `logo_url` suma `.url(...)` — recomendación
  explícita de DBA, `negocio` no tiene ningún `CHECK` de formato de URL a nivel de base.
- **`PATCH /negocios/:id`** — contrato actualizado: body `{ nombre, rubro, ubicacion,
  horario_atencion, direccion, telefono, logo_url }` (los 3 últimos y `rubro`/`ubicacion` aceptan
  `null`) -> 200 con las 9 columnas de `negocio` (incluye `id`/`es_rubro_salud`) | 400 datos
  inválidos (incluye `logo_url` con formato de URL inválido, o cualquiera de los 7 campos ausente
  del body) | 403 rol distinto de administrador o negocio ajeno | 404 negocio inexistente/
  eliminado. El `UPDATE`/`RETURNING` sigue siendo un `SET` fijo (no dinámico) — mismo estilo que ya
  tenía el endpoint, solo con 4 columnas más en la misma lista de placeholders.
- **`GET /negocios/:id`** suma las 4 columnas nuevas al `SELECT` — es el endpoint de "perfil
  completo de un negocio ya elegido" que pide la propia HU-31. **`GET /negocios` (listado) NO las
  suma, a propósito** — decisión de diseño de Backend (DBA la dejó explícitamente abierta): estos
  4 campos son datos de perfil completo, no de descubrimiento; `buscar_negocios_screen.dart`
  (Mobile, HU-00b) arma el subtítulo de cada card con `rubro`/`ubicacion` únicamente. Razonamiento
  completo en el comentario junto a `GET /` en `negocios.ts`.
- **Confirmado contra el código real (no asumido)** que no hace falta tocar `POST
  /auth/registro-negocio` (`src/routes/auth.ts`) ni `POST /dev/seed` (`src/routes/dev.ts`): ambos
  siguen insertando `negocio` con únicamente `(id, nombre, rubro, ubicacion, creado_en)` — HU-31
  define estos 4 campos como datos que se completan "más allá del alta inicial", no en el registro.

**Verificado de punta a punta contra un Postgres local propio, NUNCA contra Render** (la migración
incremental `009_negocio_datos_operativos.sql` de DBA todavía no está aplicada ahí — ver
`../database/migrations/001_init.sql` y ese archivo — y esta ronda tenía instrucción explícita de
no tocar ningún ambiente compartido). Se levantó un cluster de Postgres 18 efímero, aislado, en un
directorio temporal fuera del repo (nunca el servicio nativo de Postgres del sistema ni el volumen
de `docker-compose.yml`, ninguno de los dos disponibles/tocados en esta ronda) y se arrancó el
backend contra él en un puerto propio; al ser una base migrada desde cero, `runMigrations()`
aplicó `migrations/001_init.sql` completo — que ya incluye las 4 columnas nuevas — sin necesitar
correr `009_negocio_datos_operativos.sql` por separado (ese delta incremental solo hace falta
contra una base YA migrada antes de este ciclo, como Render). Script dedicado,
`scripts/test-datos-operativos-negocio.mjs`: carga de los 4 campos nuevos, vaciado con `null`
explícito (releído con un `GET /:id` aparte, no solo confiando en la respuesta del propio PATCH),
`logo_url` con formato inválido -> 400 (y confirmado que NO modifica el valor ya cargado), omitir
un campo nuevo del body -> 400 (confirma que no son `.optional()`), un admin de otro negocio no
puede tocar estos campos -> 403 (chequeo de ownership ya existente, sin cambios), y `GET /negocios`
(listado) confirmado que NO trae las 4 columnas nuevas — **todas verificadas, 100% en verde**. Se
re-corrieron además, contra ese mismo Postgres local (créditos de red-teaming propio: 5 scripts
preexistentes que ejercitan `negocios.ts` con volumen — `smoke-test`, `test-multinegocio`,
`test-validaciones-campos`, `test-critical1-aislamiento-admin`, `test-autorizacion-cruzada` —
retargeteados **temporalmente** a ese puerto local y revertidos con `git checkout` apenas
terminaron, sin dejar ningún cambio permanente) para confirmar que este cambio no rompió ningún
flujo existente — los 5 en verde. `npx tsc --noEmit` limpio.
