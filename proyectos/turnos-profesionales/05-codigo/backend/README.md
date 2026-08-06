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
  `rol`/`negocio_id`/`profesional_id`).
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
