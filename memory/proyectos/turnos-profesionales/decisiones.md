# Memoria de decisiones — Turnos Profesionales (TURNOS-2026-001)

## Decisiones de negocio (CEO, Fase 2)
- D1: plataforma multi-negocio (multi-tenant), no un solo consultorio.
- D2: seña/pago al reservar es configurable por profesional+servicio, no una regla global.
- D3: historial de visitas del cliente es privado por profesional, no compartido en el negocio.
- D4: notificaciones (confirmación + recordatorio) están en el alcance del MVP.
- D5: sin lista de espera — se muestra el próximo horario disponible.

## Decisiones técnicas (CTO IA/Arquitecto/DBA, Fase 3)
- Stack: Flutter (mobile único, dos modos Cliente/Profesional), backend modular monolito
  (Node/NestJS o .NET), PostgreSQL, JWT+OAuth2, FCM para push, Mercado Pago para seña.
- Multi-tenancy: base de datos compartida + `negocio_id` en toda tabla de alcance de negocio +
  Row Level Security como defensa en profundidad.
- No-doble-reserva (RN2): índice único parcial `(profesional_id, inicio)` filtrado por estado
  activo — la garantía vive en la base de datos, no solo en lógica de aplicación.
- Turno "pendiente_de_pago" expira a los 15 min si Mercado Pago no confirma el pago.
- Microservicios completos (catálogo de `docs/05-arquitectura-microservicios.md`) son para la
  plataforma interna de la AI Software Factory, no un requisito para productos de cliente —
  se evaluará dividir el monolito (empezando por Reservas y Pagos) si el volumen lo justifica.

## Decisiones de Fase 4 (Backend/Mobile)
- `better-sqlite3` requiere compilar un addon nativo (node-gyp + Visual Studio Build Tools);
  este entorno de desarrollo no los tiene. Se reemplazó por **`node:sqlite`** (built-in de
  Node ≥22.5) solo para la base de datos de desarrollo/pruebas — el diseño y el DDL de
  producción (PostgreSQL, ver `03-arquitectura/modelo-datos.md`) no cambiaron.
- Backend probado end-to-end con scripts de humo (`05-codigo/backend/scripts/`), incluida una
  prueba de concurrencia REAL (`Promise.all` con 2 requests simultáneas) que confirmó la
  garantía anti-doble-reserva (RN2) funcionando, no solo en teoría.
- Mobile (Flutter) se escribió sin poder compilar/correr — este entorno no tiene el SDK de
  Flutter ni Dart standalone instalado. Requiere verificación (`flutter analyze` + `flutter
  run`) antes de considerarse funcional. Se encontró y corrigió en revisión manual un bug de
  casteo de `Future` en el cliente HTTP (ver `05-codigo/mobile/README.md`).

## Decisiones de cierre de Fase 4 (pendientes implementados)
- HU-13 (reprogramación) implementada y probada: reutiliza el mismo índice único que el alta
  (el turno viejo pasa a estado `reprogramado`, sale del índice, y el nuevo INSERT reusa la
  garantía anti-doble-reserva sin código nuevo). El pago (si existe) se retarget al turno nuevo
  — no se vuelve a cobrar la seña en una reprogramación.
- Job de expiración de `pendiente_de_pago` implementado como `setInterval` en el proceso del
  backend (cada 60s, configurable) + endpoint `/dev/forzar-expiracion` para poder probarlo sin
  esperar los 15 min reales. Probado end-to-end.
- RLS de Postgres implementado en el DDL con un diseño no trivial: `profesional`/`servicio`
  necesitan lectura pública (catálogo) pero escritura acotada a `negocio_id`; `turno` necesita
  un OR entre scope de negocio (staff) y scope de cliente (`cliente_id`), porque un cliente
  reserva en múltiples negocios y su JWT no lleva `negocio_id`. **No verificado contra Postgres
  real** — este entorno no tiene psql/Docker. Falta conectar `SET LOCAL app.negocio_id` /
  `app.usuario_id` en el backend cuando deje de usar `node:sqlite` y pase a Postgres.

## Ampliación de backlog — Product Manager (2026-08-05)

- El CEO compartió (por chat, sin archivos en el repo) capturas de otra app propia de
  turnos/citas, ya construida y sin producción todavía, y autorizó tomar estilo visual y
  funcionalidades para este proyecto. El Product Manager transcribió el contenido y actualizó
  `01-requisitos/documento-funcional.md` (decisiones D6–D9, RN11–RN14, CU6, glosario) y
  `02-backlog/backlog.md` (épicas E9–E14 nuevas; extensiones HU-16 a HU-32 sobre E0/E2/E5/E7).
- Es alcance **adicional** sobre el MVP ya construido (E0–E8) — no reemplaza ni bloquea nada
  ya aprobado en Fases 1–4.
- Quedan **11 preguntas abiertas para el CEO** antes de que Arquitecto/UX/UI/DBA diseñen esta
  ampliación (ver `01-requisitos/documento-funcional.md` §7). Las de mayor impacto técnico:
  - Precedencia de duración de cita configurable por profesional vs. duración por servicio
    (RN3) — afecta el cálculo de slots ya implementado.
  - Si el ícono "cambiar de vista" implica que un profesional/administrador puede pertenecer a
    más de un negocio, contradice RN9 tal como está modelado hoy (`admin_usuario_id` 1:1 en
    `negocio`, ver `03-arquitectura/modelo-datos.md` §2bis) — requeriría rediseño de esa parte
    del esquema, no un ajuste menor.
  - Tratamiento y Nota médica son entidades nuevas (hoy el historial es una consulta sobre
    `Turno`, sin tabla propia) — a modelar por DBA si el CEO confirma avanzar.
  - Datos de salud en la ficha de paciente (alergias, contacto de emergencia) requieren
    revisión de Security antes de producción, y su aplicabilidad a rubros no médicos (la
    plataforma es multi-rubro, D1) está abierta.

## Decisiones de Fase 6 (DevOps) — 2026-08-05

- Contenerización con build multi-stage (`05-codigo/backend/Dockerfile`), imagen base
  `node:22-slim` en ambos stages — restricción real, no arbitraria: `src/db.ts` usa
  `node:sqlite`, que exige Node >=22.5. Stage de runtime corre como usuario no-root
  (`node`), sin `scripts/` ni `web-preview/` (no hacen falta para servir la API y es una
  capa extra de defensa sobre el gating `ENABLE_DEV_ROUTES` que ya implementó Security).
- **Hallazgo nuevo de este ciclo:** `package.json` (`main`/`start`) apunta a
  `dist/index.js`, pero `tsconfig.json` compila con `rootDir: "."` y el JS real queda en
  `dist/src/index.js` — `npm start` está roto hoy (nunca se había ejercitado; el flujo de
  desarrollo usa `ts-node-dev`, no `dist/`). Verificado corriendo ambas rutas con Node
  real. No se corrigió `package.json` (entregable de Backend ya aprobado por QA/Security);
  el `Dockerfile` usa la ruta real en su `CMD`. Reportado como pendiente para Backend en
  `08-despliegue/README.md` §2.
- Por el mismo desfase de `__dirname` en runtime, `migrations/` se copia dentro de
  `dist/migrations` en la imagen (no en la raíz de `/app`) para que
  `runMigrations()` la encuentre — `src/db.ts` no se modificó.
- `DB_PATH` (variable ya soportada por `src/db.ts`, no documentada antes en el README del
  backend) se fija a `/data/dev.sqlite3` en la imagen; `docker-compose.yml` monta ahí un
  volumen nombrado para persistir el sqlite entre reinicios — sin esto, cada
  recreación del contenedor perdería los datos.
- `docker-compose.yml` (desarrollo/staging local) **no incluye un servicio de
  PostgreSQL** — agregarlo sería un espejismo, ver el punto siguiente.
- **Gap arquitectónico confirmado y documentado como bloqueante explícito** (no ignorado):
  el backend solo sabe hablar con `node:sqlite`; la migración a PostgreSQL (driver, pool,
  adaptar queries, conectar `SET LOCAL app.negocio_id`/`app.usuario_id` para que la RLS ya
  diseñada tenga efecto) es trabajo de Backend, pendiente antes de cualquier despliegue
  real. Detalle completo en `08-despliegue/README.md` §7.
- CI (`.github/workflows/turnos-backend-ci.yml`, raíz del repo) en dos jobs: (1)
  `npm ci`/`tsc --noEmit`/`npm run build` + los 10 scripts de `scripts/*.mjs` vía
  `ts-node`; (2) `docker-build-smoke`, que construye la imagen real y corre
  `smoke-test.mjs` contra un contenedor en config tipo producción — los runners de GitHub
  Actions sí traen Docker preinstalado, a diferencia de este entorno de desarrollo, así que
  es el único lugar donde el Dockerfile se valida de verdad en este ciclo.
- **Confirmado (no asumido) que la batería de `scripts/*.mjs` necesita dos arranques del
  servidor:** se reprodujo activamente que `test-rn8-ventana-cancelacion.mjs` falla si se
  lo corre con `VENTANA_CANCELACION_MIN=0` (necesita la ventana default de 120 min) — de
  ahí que el job de CI levante el servidor dos veces en vez de una sola vez con todas las
  env vars de test juntas.
- Verificado con Node real en este entorno (sin Docker, que no está instalado acá): `npm
  run build && node dist/src/index.js` arranca y pasa `scripts/smoke-test.mjs` completo.
  El Dockerfile/`.dockerignore`/`docker-compose.yml` en sí **no se verificaron con un build
  real** — mitigado por el job `docker-build-smoke` de CI (ver arriba).

## Cierre del hallazgo de `package.json` (Director General IA, 2026-08-06)
- El agente de DevOps se cortó por límite de sesión justo antes de reportar (el archivo de
  memoria y todos los entregables ya habían quedado escritos correctamente). Se verificó
  el trabajo de forma independiente: `npm run build` compila limpio y el Dockerfile usa
  correctamente `dist/src/index.js` (no `dist/index.js`).
- Se corrigió directamente el hallazgo que DevOps había documentado como pendiente para
  Backend: `package.json` (`main`/`start`) ahora apunta a `dist/src/index.js`, y se agregó
  un script `postbuild` (`fs.cpSync` de `migrations/` a `dist/migrations/`) para que
  `npm run build && npm start` funcione standalone sin Docker, igual que ya funcionaba
  dentro del Dockerfile. Verificado de punta a punta: build + `npm start` + smoke test
  completo, sin fallos.

## Reutilizable para futuros proyectos de la Factory
- El patrón "modular monolito primero, extraer servicios cuando el volumen lo justifique" es
  candidato a plantilla en `knowledge-base/patrones-arquitectonicos/`.
- El patrón de índice único parcial para evitar doble-reserva bajo concurrencia es reutilizable
  en cualquier proyecto con lógica de scheduling/booking — candidato a
  `knowledge-base/patrones-arquitectonicos/`.
- `node:sqlite` como reemplazo de `better-sqlite3` para desarrollo local en entornos Windows
  sin Build Tools es reutilizable en cualquier proyecto backend Node — candidato a
  `knowledge-base/estandares/`.
- Nunca asumir Flutter/Dart/Docker/psql instalados en el entorno de ejecución de un agente —
  verificar con `--version` antes de planificar el alcance de un slice de desarrollo.

## Decisiones de planificación de producción (CTO IA, previo a Fase 6)

Detalle completo y justificación en `03-arquitectura/plan-produccion.md`. Resumen para reutilizar:

- **Migración a PostgreSQL y conexión de RLS se tratan como una sola decisión, no dos tareas
  independientes:** el DDL ya escrito habilita RLS a nivel de tabla; si se aplica sin que el
  backend setee `SET LOCAL app.*`, las políticas de escritura deniegan todo por defecto
  (fail-closed) y la aplicación se rompe, no solo "queda menos segura". Backend/DBA deben decidir
  explícitamente si conectan `SET LOCAL app.*` en el mismo cambio o aplican el DDL sin forzar RLS
  todavía como paso intermedio consciente.
- **Hallazgo de proceso:** `06-qa/reporte-qa.md` y `07-seguridad/informe-seguridad.md` quedaron
  con su conclusión original ("NO listo") aunque `05-codigo/backend/README.md` documenta que
  Backend remedió todos los hallazgos Critical/High en ciclos posteriores. Antes de dar Fase 5
  por cerrada, QA/Security deben re-validar por escrito (re-correr los scripts de regresión ya
  existentes) — la auto-remediación de quien escribió el código no sustituye la verificación
  independiente de quien encontró el hallazgo.
- **Alcance de v1 vs. V4 (ficha de paciente extendida, Turnario Pro):** verificado en código que
  V4 no tiene ninguna implementación todavía (ni columnas, ni endpoints, ni facturación) — el
  lanzamiento puede proceder con el alcance E0–E8 ya construido sin que los pendientes de V4
  (revisión legal Ley 25.326 por datos de salud, Google Play Billing/StoreKit) sean bloqueantes,
  siempre que el CEO confirme explícitamente que V4 queda para una release posterior.
- **Recomendación de hosting para MVP de este tamaño:** Render o Railway (PaaS con Postgres
  gestionado + backups + TLS incluidos, deploy directo desde Dockerfile, ~USD 15–25/mes) por
  encima de un VPS propio (más barato, ~USD 6–10/mes, pero traslada backups/TLS/parches a
  mantenimiento manual de DevOps) y muy por encima de AWS/GCP/Azure (sobredimensionado para este
  volumen hoy). Candidato a lineamiento reutilizable en `knowledge-base/` para el próximo
  proyecto de tamaño similar que no tenga ya una decisión de cloud provider heredada.
- El catch de conflicto de unicidad en `src/routes/turnos.ts` (RN2) ya contempla tanto el shape
  de error de `node:sqlite` como el código `23505` de Postgres — buena práctica de Backend
  anticipando la migración; patrón reutilizable al migrar cualquier backend de SQLite a Postgres
  con constraints únicos como mecanismo de concurrencia.

## Generalización de esquema 1:1 → N:M (administrador/profesional en varios negocios) — DBA (2026-08-06)

Detalle completo, razonamiento columna por columna y recomendaciones para Backend en
`03-arquitectura/modelo-datos.md` §2ter (sección nueva). Resumen para reutilizar:

- El CEO confirmó un cambio de alcance: un mismo administrador o profesional puede pertenecer a
  más de un negocio (resuelve la pregunta abierta sobre el ícono "cambiar de vista" que ya había
  registrado Product Manager, ver entrada "Ampliación de backlog" arriba en este mismo archivo).
- Se verificó activamente (no se asumió) el estado de partida: `grep` sobre el código confirmó
  que `negocio_administrador`/`negocio_profesional` **no existían todavía** — un intento anterior
  de este mismo trabajo había quedado interrumpido antes de escribir esquema.
- `negocio.admin_usuario_id` (columna 1:1 que resolvía CRITICAL-1, ver §2bis del mismo doc) se
  reemplaza por la tabla de asociación `negocio_administrador(negocio_id, usuario_id, creado_en)`
  con PK compuesta. `profesional.negocio_id` (1:1) se reemplaza por
  `negocio_profesional(negocio_id, profesional_id, activo, creado_en)`, también PK compuesta —
  `profesional` pasa a ser una identidad profesional pura (como `usuario`), sin negocio fijo
  propio. Ambas tablas nuevas siguen el mismo criterio de PK compuesta sin GUID propio que ya
  tenía `profesional_servicio` (tablas de asociación pura, precedente ya aprobado en Fase 3).
- Ninguna de las dos generalizaciones reabre CRITICAL-1: la corrección de fondo (una relación
  persistida real contra la cual correlacionar el login, en vez de una query sin correlación) se
  mantiene intacta; lo único que cambia es la cardinalidad de esa relación (de exactamente 1 fila
  a 0..N filas).
- Se confirmó con un **smoke test funcional real** (`node:sqlite`, no solo análisis teórico —
  ver script en el historial de esta sesión) que `negocio_profesional` **NO es redundante** con
  `profesional_servicio`: se insertó un profesional con membresía activa en 2 negocios y 0 filas
  en `profesional_servicio`, confirmando que un profesional recién dado de alta por el
  administrador (HU-02) puede pertenecer a un negocio antes de configurar ningún servicio propio
  (HU-04/HU-04b es un paso posterior y separado). Ambas tablas responden preguntas distintas:
  membresía/autorización vs. catálogo/configuración operativa.
- Recomendación para Backend: `turno.negocio_id` debe resolverse desde `servicio.negocio_id`
  (relación 1:1 servicio→negocio, que NO cambió con esta generalización) en vez de desde
  `profesional.negocio_id` (columna eliminada) — `turnos.ts` ya consulta `servicio` para la
  duración, alcanza con agregar `negocio_id` a esa misma query. Lista concreta de
  endpoints/queries de `auth.ts`/`negocios.ts`/`profesionales.ts`/`turnos.ts`/`dev.ts` a revisar
  (archivo y línea aproximada) en `modelo-datos.md` §2ter, incluida la recomendación de que
  Backend valide membresía activa (`negocio_profesional.activo`) antes de aceptar un turno, y 3
  opciones evaluadas (no una decisión cerrada por DBA) para la forma del claim `negocio_id` en el
  JWT, que deja de poder ser un único valor con esta generalización.
- RLS de Postgres (todavía no conectada al backend — ver entradas anteriores) se rediseñó para no
  depender de `current_setting('app.negocio_id')` como único valor de sesión: las políticas de
  escritura pasan de comparar por igualdad a usar `EXISTS` contra
  `negocio_administrador`/`negocio_profesional` anclado en `app.usuario_id`, re-derivando la
  autorización desde la relación persistida en cada chequeo de fila en vez de confiar en un claim
  de sesión cacheado — mismo principio de fondo que evitó CRITICAL-1, aplicado ahora también a la
  capa de RLS.
- Aplicado en ambas migraciones (`05-codigo/database/migrations/001_init.sql` y
  `05-codigo/backend/migrations/001_init.sqlite.sql`), verificado con un smoke test end-to-end
  contra `node:sqlite` real en este entorno (admin con 2 negocios, profesional con 2 negocios sin
  servicios configurados, resolución de `turno.negocio_id` vía `servicio`, e integridad
  referencial + rechazo de duplicados por PK compuesta) — **no verificado contra Postgres real**
  (este entorno sigue sin `psql`/Docker, mismo caveat ya documentado para el resto del DDL).
- Nota operativa: a diferencia del fix de CRITICAL-1 (que solo agregaba una columna), este cambio
  **elimina columnas** de `negocio` y `profesional` — un `dev.sqlite3` ya generado con el esquema
  anterior necesita borrarse/recrearse, porque `CREATE TABLE IF NOT EXISTS` no altera una tabla
  existente. Verificado que no aplicaba hoy (no había ningún `dev.sqlite3` generado todavía en
  este entorno).
- Fuera de alcance de DBA en este ciclo (no tocado): código de `src/routes/` (Backend lo
  reconstruye en el próximo ciclo sobre este esquema) y `01-requisitos/documento-funcional.md`/
  `02-backlog/backlog.md` — RN9 (`documento-funcional.md` §3) quedó con texto desactualizado
  ("un profesional... pertenece a un único negocio"); su corrección de texto le corresponde a
  Business Analyst.

## Resolución de las 16 decisiones del CEO — Business Analyst (2026-08-06)

El CEO respondió, una por una, las 11 preguntas abiertas de
`01-requisitos/documento-funcional.md` §7 más 5 preguntas relacionadas del plan de producción de
CTO IA con implicancia funcional (`03-arquitectura/plan-produccion.md` §10). Product Manager
aplicó en paralelo las mismas 16 decisiones a `02-backlog/backlog.md` (no se coordinó edición de
archivos entre ambos — cada uno tocó solo el propio). Detalle completo, con el texto de cada
decisión, en `01-requisitos/documento-funcional.md` §1 (D10–D21) y §3 (RN15–RN20). Resumen:

- **D10 (la de mayor impacto técnico pendiente): "el profesional manda siempre".** La duración
  general configurada por el profesional reemplaza la del servicio (RN3) para todos sus turnos.
  Amenda RN3 directamente y **es un cambio de comportamiento sobre lógica ya implementada y
  probada**, no una definición nueva: `calcularSlotsDisponibles`
  (`05-codigo/backend/src/dominio/disponibilidad.ts`) hoy calcula la duración de cada slot
  únicamente desde `servicio.duracion_min`. Implementarlo requiere: campo nuevo en el modelo de
  datos (DBA, no existe hoy), cambio de esa función (Backend), y revisión de los tests que
  validan la regla vieja (`scripts/test-rn1-disponibilidad-y-solapamiento.mjs`, entre otros). No
  implementado en este ciclo — queda para Backend/DBA.
- **D11.** Los campos de salud de la ficha de paciente (D7/RN12) aplican solo a negocios de
  rubro salud, no a todos los rubros (RN15 nueva). Dos condiciones quedan explícitas: (a)
  pregunta de implementación abierta para DBA — falta un criterio determinístico para "rubro de
  salud" (lista cerrada vs. flag booleano en `negocio`), no resuelta por Business Analyst; (b)
  gate legal — el CEO va a consultar a un abogado sobre la Ley 25.326 antes de habilitar estos
  campos en producción con datos reales (se puede diseñar/construir antes de esa confirmación).
- **D12.** "Autorizaciones Médicas" = documentos adjuntos por paciente (estudios, órdenes
  médicas, autorizaciones de obra social escaneadas), sin firma digital ni consentimiento (RN16
  nueva). Queda una pregunta nueva, no resuelta por el CEO en esta tanda: si estos documentos
  son privados por profesional (como el historial, RN7) o compartidos en el negocio.
- **D13.** WhatsApp es canal adicional (no reemplaza push/email, D4); cada negocio gestiona y
  paga su propia cuenta de WhatsApp Business API — dato nuevo a nivel negocio para DBA (RN17
  nueva).
- **D14/D15.** Suscripción "Turnario Pro": freemium por límite de uso (valores exactos a cargo
  de Product Manager en el backlog); lanzamiento solo Android (Google Play) por ahora, tanto
  para la app en general como para la suscripción — iOS queda para una release posterior.
- **D16.** Excepción explícita a RN10 (RN18 nueva): cuando el profesional agenda un turno
  manualmente (CU6), puede omitir la seña caso por caso, a diferencia de la autoreserva del
  cliente (CU4) donde RN10 aplica siempre. CU6 actualizado con el paso nuevo.
- **D17.** Import/export de pacientes en CSV/Excel genérico, ambos sentidos, con plantilla
  descargable para el import.
- **D18.** Reportes: turnos totales/completados/cancelados y monto facturado por período,
  desglosado por profesional y servicio. Configuración de pagos del negocio: solo la cuenta de
  Mercado Pago.
- **D19.** Los toggles de notificación "Mensajes"/"Reseñas y Calificaciones"/"Promociones y
  Ofertas" son placeholder visual (RN19 nueva) — guardan preferencia, no activan nada real
  todavía; documentado explícitamente para que QA no lo marque como defecto.
- **D20.** Estado activo/inactivo del paciente es manual, lo marca el profesional (RN20 nueva).
- **D21.** El CEO confirmó explícitamente que el alcance de v1 SÍ incluye lo que el plan de
  producción de CTO IA llamaba "V4" (ficha de paciente extendida + Turnario Pro) — no queda
  diferido a una release posterior.
- **RN9 corregida (sin D nuevo):** el punto sobre el ícono "cambiar de vista" ya había sido
  confirmado por el CEO antes de esta tanda, directamente con DBA, y ya está implementado
  (`03-arquitectura/modelo-datos.md` §2ter, generalización N:M). Business Analyst solo formalizó
  la corrección de texto que DBA había dejado pendiente: RN9 (§3), actores (§2) y glosario (§5,
  entrada "Profesional") ya no dicen que un profesional/administrador pertenece a un único
  negocio.
- **Mercado Pago (nota de contexto, no genera D nueva):** el CEO va a lanzar con todos los
  servicios en "sin seña" mientras tramita la cuenta habilitada — RN10 ya lo permite
  (`requiere_sena = false`).
- Además de RN15–RN20 (nuevas), se ajustó el texto de RN11 (D6) para quitar la mención de
  "precedencia pendiente de definir", ahora resuelta por D10/RN3, y se agregaron notas de
  resolución en D6/D7 (§1) apuntando a D10/D11 — para no dejar contradicciones dentro del mismo
  documento.
- Dos preguntas nuevas quedaron registradas en `documento-funcional.md` §7 ("Preguntas nuevas,
  no bloqueantes"): (1) para DBA, el criterio de "rubro de salud" (D11); (2) para el CEO, la
  visibilidad de "Documento de paciente" (D12) — ninguna de las dos bloquea el diseño básico de
  las funcionalidades correspondientes.
- No se tocó `02-backlog/backlog.md` (Product Manager, en paralelo) ni código de `05-codigo/`
  (la implementación del cambio de RN3 queda para un ciclo posterior de Backend/DBA).

## Aplicación de las 15 decisiones del CEO al backlog — Product Manager (2026-08-06)

El CEO respondió, una por una, las preguntas abiertas que condicionaban las épicas E9–E14 y las
extensiones HU-16 a HU-32 de `02-backlog/backlog.md`. Se aplicaron directamente sobre las HU y
épicas ya existentes (sin duplicar historias) — detalle completo en cada HU del backlog mismo.
Business Analyst formalizó las mismas decisiones en paralelo en
`01-requisitos/documento-funcional.md` (D10–D21, RN15–RN20, ver sección anterior en este mismo
archivo); no se coordinó edición de archivos entre ambos roles, cada uno tocó solo el propio.

Resumen de lo aplicado en el backlog:

- **HU-16/HU-09 (duración de cita):** el profesional configura una duración general que
  **reemplaza** a la del servicio (RN3) para todos sus turnos — no es un default sugerido.
  Marcado explícitamente en HU-16, con nota cruzada en HU-09, como "modificación de Backend
  sobre lógica ya implementada y probada" (coincide con el hallazgo técnico de Business Analyst:
  `calcularSlotsDisponibles` en `disponibilidad.ts` hoy solo usa `servicio.duracion_min`) — no se
  mezcló con las historias nuevas de alcance limpio de esta misma ampliación.
- **HU-20 (ficha extendida):** acotada a negocios de rubro salud, no a todos los rubros. Se
  agregó nota de riesgo de **lanzamiento** (no de desarrollo): el CEO va a consultar a un
  abogado sobre la Ley 25.326 antes de habilitar datos reales de salud en producción —
  bloqueante de Fase 6 (Despliegue), no de Fases 3–5.
- **HU-33 (nueva, E5, P2):** resuelve "Autorizaciones Médicas" como documentos adjuntos por
  paciente (subir/ver archivos), sin firma digital ni consentimiento. Al cruzar con el trabajo
  de Business Analyst se detectó que ninguno de los dos debía asumir si son privados por
  profesional o compartidos en el negocio — quedó documentado como pregunta abierta en ambos
  entregables en vez de asumir un default silenciosamente distinto en cada uno.
- **HU-24 (WhatsApp) + HU-34 (nueva, E13, P2):** WhatsApp es canal adicional, no reemplaza push/
  email. Cada negocio carga sus propias credenciales de WhatsApp Business API (HU-34) antes de
  poder activar el canal (HU-24).
- **E11/HU-29 (Turnario Pro) — propuesta de freemium (valores concretos, a cargo de Product
  Manager por pedido explícito del CEO, sujeta a ajuste):** plan gratis = 1 profesional + 60
  turnos confirmados/mes por negocio; Turnario Pro = límites ilimitados + reportes (E10) +
  WhatsApp (HU-24) + plantillas de horario recurrente (HU-17) + import/export de pacientes
  (HU-22). Suscripción por negocio (no por profesional individual), ~USD 9/mes con 20% de
  descuento pagando anual, cobrada vía Google Play Billing — **solo Android en v1**, iOS queda
  como épica futura sin HU activa.
- **HU-27 (ícono "cambiar de vista"):** ya no aparece como pregunta abierta — se actualizó su
  estado a "implementada en Backend, falta Mobile", en línea con la generalización N:M que DBA
  ya había documentado en `03-arquitectura/modelo-datos.md` §2ter (ver sección de DBA más arriba
  en este mismo archivo).
- **HU-23 (seña omitible en alta manual):** el profesional puede decidir no cobrar seña al
  cargar un turno manualmente aunque el servicio la tenga configurada (RN10/HU-04b). La otra
  pregunta abierta de esta misma historia (si el campo "Hora" acepta varios horarios en una sola
  carga) sigue sin resolver — no formaba parte de las decisiones que respondió el CEO en esta
  ronda, se dejó explícitamente diferenciada de la que sí se resolvió.
- **HU-22 (import/export de pacientes):** CSV y Excel, ambos sentidos (import y export), con
  plantilla descargable.
- **HU-28/E10 (Reportes) y HU-30/E12 (Configuración de pagos):** alcance básico concreto —
  reportes: turnos totales/completados/cancelados y monto facturado, filtrable por período/
  profesional/servicio; pagos: solo datos de la cuenta de Mercado Pago del negocio.
- **HU-26 (toggles sin funcionalidad real):** documentado explícitamente que "Mensajes"/"Reseñas
  y Calificaciones"/"Promociones y Ofertas" son placeholder visual (guardan preferencia, sin
  efecto funcional) para que QA no lo reporte como defecto.
- **HU-19 (activo/inactivo de paciente):** manual, cargado por el profesional — ya no requiere
  un job de cálculo automático por antigüedad, lo que simplifica su alcance.
- **Repriorización por alcance de v1 confirmado (el CEO confirmó que v1 incluye todo lo que
  antes era "V4" — E9–E14 completas, sin diferir nada a una release posterior):** se
  repriorizaron de P2 a P1 las épicas **E10** (alcance ahora básico y chico), **E11** (nombrada
  explícitamente por el CEO junto con la ficha extendida; única fuente de monetización definida
  hoy) y **E12** (alcance chico y ligado funcionalmente a E3/HU-09b, que es P0). **E13 y E14
  quedan en P2** (alcance sin cambios, no nombradas explícitamente, no bloquean el flujo core de
  reserva/cobro) — justificación completa en `02-backlog/backlog.md`, sección "Ampliación del
  backlog".
- **Roadmap de producto:** se retiró la separación V1(MVP)/V2/V3/V4 (ya no reflejaba el alcance
  real); se reemplazó por "v1 (alcance completo E0–E14, solo Android/Google Play)" +
  "fast-follow" (iOS/App Store, medios de pago adicionales a Mercado Pago, analítica más
  avanzada que el alcance básico de E10, las funcionalidades hoy placeholder de HU-26 si el CEO
  decide construirlas). Se agregaron como notas operativas (no como HU nuevas, por pedido
  explícito del CEO): rollout de Mercado Pago "sin seña" mientras se tramita la cuenta (RN10 ya
  lo soporta) y el gate legal de HU-20 antes de producción.

No se tocó `01-requisitos/documento-funcional.md` (Business Analyst, en paralelo) ni código de
`05-codigo/`.

## Campo `profesional.duracion_cita_min` — D10 amenda RN3 — DBA (2026-08-06)

Detalle completo, razonamiento de ubicación y recomendaciones para Backend en
`03-arquitectura/modelo-datos.md` §2quater (sección nueva). Resumen para reutilizar:

- El CEO resolvió D10 (`documento-funcional.md` §1/§3): la duración de turno que configura el
  profesional reemplaza SIEMPRE la duración del servicio (RN3 original), para todos sus turnos,
  sin importar el servicio — eligió esta opción por ser la más simple, descartando
  explícitamente la alternativa más granular por combinación profesional+servicio que se le
  había sugerido (al estilo `profesional_servicio.monto_sena`).
- Campo agregado: `profesional.duracion_cita_min INTEGER` nullable, con
  `CHECK (duracion_cita_min IS NULL OR duracion_cita_min > 0)` (mismo criterio "duración > 0" que
  `servicio.duracion_min`, pero acá nullable). `NULL` = sin override, se sigue usando
  `servicio.duracion_min` sin ningún cambio — no hace falta un booleano aparte, a diferencia de
  `requiere_sena`/`monto_sena`.
- Se evaluaron y descartaron explícitamente dos alternativas de ubicación antes de confirmar
  `profesional`: `negocio_profesional` (variaría por negocio, no pedido) y `profesional_servicio`
  (exactamente la alternativa granular que el CEO descartó). `profesional` es la ubicación
  correcta por ser la identidad profesional pura (ya sin negocio fijo desde la generalización N:M
  de §2ter) — el valor debe aplicar igual sin importar negocio o servicio, que es justo lo que
  pide D10.
- Aplicado en ambas migraciones (`05-codigo/database/migrations/001_init.sql` y
  `05-codigo/backend/migrations/001_init.sqlite.sql`), dentro del mismo `001_init` (no se creó una
  migración incremental nueva — el proyecto todavía no tiene Postgres desplegado). Cambio aditivo
  y reversible sin necesidad de script de rollback separado.
- **`dev.sqlite3` ya existe en este entorno** (`05-codigo/backend/dev.sqlite3`, verificado) — a
  diferencia del ciclo de la generalización N:M (donde en ese momento no existía todavía), esta
  vez SÍ aplica la nota operativa: hay que borrarlo/recrearlo (o correr un `ALTER TABLE` manual)
  para que tome la columna nueva, porque `CREATE TABLE IF NOT EXISTS` no altera una tabla ya
  creada.
- Recomendación concreta para Backend (no implementada, fuera de alcance de DBA), con archivo y
  línea aproximada: `src/dominio/disponibilidad.ts:57-60,69,107` (agregar el fallback
  `profesional?.duracion_cita_min ?? servicio.duracion_min` al calcular `duracionMs` y al
  devolver `duracionMin` — arregla de paso `GET /profesionales/:id/slots`, que solo llama a esta
  función) y `src/routes/turnos.ts:122` (recalcula `finDate` sin pasar por
  `calcularSlotsDisponibles` — dos alternativas evaluadas, ninguna cerrada por DBA: reusar
  `slotsLibres.duracionMin` ya calculado en la línea 114, o extender la consulta de `profesional`
  que ya existe en la línea 51). Hallazgo adicional detectado de paso, fuera de lo pedido
  explícitamente: `src/routes/turnos.ts:226-230` (`PATCH /:id/reprogramar`) tiene el mismo gap —
  se dejó documentado igual.
- **Gap de RLS detectado y documentado, no resuelto en este slice:** la policy `UPDATE` de
  `profesional` (§5 de `modelo-datos.md`) solo permite escribir a un administrador del negocio, no
  al propio profesional — pero RN11 dice que el profesional configura `duracion_cita_min` él
  mismo. Bajo RLS activa (todavía no conectada al backend), ese `UPDATE` quedaría denegado por
  defecto (fail-closed). No bloquea nada hoy; queda como pendiente explícito para antes de
  conectar RLS a Postgres, con dos alternativas evaluadas (policy acotada al propio `usuario_id` +
  validación de columnas a nivel de aplicación, o función `SECURITY DEFINER`), ninguna
  implementada todavía.
- No se tocó `src/` ni `01-requisitos/documento-funcional.md` ni `02-backlog/backlog.md` (ya
  actualizados por Business Analyst y Product Manager en este mismo ciclo) — alcance de DBA
  limitado a esquema, migraciones y documentación del modelo de datos.

## Primera verificación real de compilación de Mobile — CI en GitHub Actions (2026-08-06)

El CEO autorizó usar GitHub Actions (SDK oficial de Flutter, dentro de los minutos gratis
incluidos) para conseguir, por primera vez, verificación real del código Flutter de
`05-codigo/mobile` — hasta ahora solo se había revisado a mano (ver entrada de Fase 4 más
arriba). Resultado: **verde** —
[run 31110105801](https://github.com/matiasayago/TurnarioPro/actions/runs/31110105801),
`.github/workflows/turnos-mobile-ci.yml`. Detalle:

- **Hallazgo de partida (no documentado antes):** `05-codigo/mobile` nunca tuvo carpetas
  nativas por plataforma (`android/`, `ios/`) — se escribió a mano (`lib/` + `pubspec.yaml`)
  sin correr nunca `flutter create`. Confirmado también por el `.gitignore` del directorio,
  que no tiene ninguna de las entradas que el propio Flutter genera. Sin `android/`,
  `flutter build apk` no tiene nada que compilar. El workflow lo resuelve generando
  `android/` al vuelo (`flutter create --platforms=android .`, mecanismo oficial de Flutter
  para agregar soporte de plataforma a un proyecto existente — no pisa `pubspec.yaml` ni
  `lib/`) **dentro del runner de CI, sin commitear esa carpeta al repo**. Pendiente real para
  un ciclo futuro: generarla de forma permanente (`flutter create --platforms=android,ios .`
  desde una máquina con el SDK) para que `flutter run` funcione localmente — ver
  `05-codigo/mobile/README.md`.
- `flutter create` también completa, si faltan, `analysis_options.yaml` y
  `test/widget_test.dart` con la plantilla genérica de contra-app ("MyApp") — el workflow los
  elimina antes de `flutter analyze` a propósito: el test genérico no compila contra este
  `main.dart` (rompería el análisis por una razón ajena al código real) y activar
  `flutter_lints` de golpe sobre código nunca linteado habría tapado con ruido de estilo los
  errores reales que se buscaba encontrar.
- **Primer intento con código real: falló** — `flutter analyze` encontró 2 deprecaciones
  reales del SDK de Flutter (no bugs de lógica, `flutter build apk --debug` nunca llegó a
  correr por el fail-fast del job): `DropdownButtonFormField.value` (deprecado desde Flutter
  3.33, reemplazo `initialValue`) en `definir_disponibilidad_screen.dart`, y
  `Color.withOpacity()` (deprecado por pérdida de precisión, reemplazo `withValues(alpha:)`)
  en `excepciones_screen.dart`. Corregidos ambos (2 líneas). **Segundo intento (con las
  carpetas nativas al vuelo + esos 2 fixes): verde** — `flutter analyze` y
  `flutter build apk --debug` pasaron los dos.
- **Bloqueo operativo encontrado y resuelto sin necesitar credenciales nuevas:** la API de
  descarga de logs de Actions (`GET .../actions/jobs/{id}/logs`) devuelve 403 ("Must have
  admin rights to Repository") aun sin autenticar contra un repo público — este entorno no
  tiene un token de GitHub disponible para autenticar esa llamada (se intentó leer la
  credencial ya configurada para `git push` vía `git credential fill` para reutilizarla en
  llamadas de solo lectura a la API, y el propio sistema lo bloqueó por política — no se
  insistió). El workflow ahora incluye un paso de diagnóstico (`permissions: contents:
  write` + `GITHUB_TOKEN` que Actions provee automáticamente, sin secretos nuevos) que
  publica la salida de `flutter analyze`/`build` como comentario del commit cuando el job
  falla — esos comentarios sí son legibles después vía la API pública sin autenticación.
  Quedó como capacidad permanente del workflow (no se retiró tras resolver este ciclo),
  reutilizable para cualquier falla futura de este mismo pipeline.
- La lista de corridas de este ciclo (para trazabilidad): commit `2d51954` (workflow inicial)
  → falló en `flutter analyze`, sin visibilidad del log; commit `cb20d12` (agrega el paso de
  diagnóstico) → mismo fallo, ahora con el log visible vía comentario del commit; commit
  `4d85c71` (los 2 fixes de deprecación) → **verde**, incluido `flutter build apk --debug`.
- **No verificado en este ciclo (fuera de lo que `analyze`/`build apk` pueden detectar):**
  ejecución real de la app (`flutter run`) contra el backend — flujos de login, reservas,
  etc. Ver gap de `android/`/`ios/` arriba y detalle en `05-codigo/mobile/README.md`.

## Reutilizable para futuros proyectos de la Factory (continuación)
- Verificar con la API de GitHub (`GET /repos/{owner}/{repo}/actions/runs/...`) es viable sin
  autenticación para metadata pública (estado/conclusión de un run), pero **la descarga de
  logs/artefactos exige un token aun en repos públicos** — para cualquier CI nuevo en un
  entorno sin token disponible, conviene planificar de entrada un mecanismo alternativo de
  diagnóstico (comentario de commit vía `GITHUB_TOKEN` del propio workflow, como se hizo acá)
  en vez de asumir que los logs van a poder leerse directo.
- La API pública sin autenticar de GitHub tiene un límite bajo (60 req/hora) que un polling
  frecuente agota rápido — para esperar un run de CI, conviene espaciar los chequeos (o
  hacerlos una sola vez tras una espera) en vez de consultar cada pocos segundos.

## Primera corrida real del CI de Backend — falla y fix (Director General IA + Backend, 2026-08-06)

El CI de Backend (`.github/workflows/turnos-backend-ci.yml`) corrió por primera vez de verdad al
pushear el merge inicial y **falló** en el job `build-and-test`, paso "Fase 2/2 - correr
test-rn8-ventana-cancelacion" ([run 31108620102](https://github.com/matiasayago/TurnarioPro/actions/runs/31108620102),
commit `66fccfc`). El Director General IA investigó primero por su cuenta (sin poder reproducir el
fallo ni acceder a los logs crudos) y planteó una hipótesis de trabajo; delegó en Backend
confirmarla o refutarla con evidencia y aplicar el fix real.

**Hipótesis inicial (Director General IA) — investigada y REFUTADA con evidencia, no descartada a
ciegas:** que `scripts/test-rn8-ventana-cancelacion.mjs` pidiera "slots cercanos" con `dias=1`
(ventana de un solo día calendario, ver `src/dominio/disponibilidad.ts`) y pudiera quedarse con
menos de 2 slots si el paso corría en la última hora antes de medianoche del huso horario del
proceso del servidor (los runners de GitHub Actions corren en UTC). Se refutó consultando la
propia API pública de GitHub **sin necesitar login** (`GET /repos/.../actions/runs/{id}/jobs`,
que sí expone `started_at`/`completed_at` por step sin autenticación, a diferencia de la descarga
de logs crudos): el paso que falló corrió a las **14:00 UTC**, pleno día, lejos de cualquier
medianoche — la hipótesis no podía ser la causa de ESE fallo puntual.

**Causa raíz real, confirmada por reproducción directa y contrastada en local (no por inspección
de código únicamente):** el paso "Fase 1/2 - arrancar servidor" arrancaba el servidor con
`npx ts-node --transpile-only src/index.ts &` y guardaba `$!` en `server.pid` para matarlo más
tarde, en "Fase 1/2 - detener servidor". `npx` **siempre** hace `spawn` de un proceso hijo real
para correr un binario ya instalado localmente (nunca reemplaza su propio proceso vía `exec`,
a diferencia del shim `node_modules/.bin/ts-node`, que sí usa `exec` de principio a fin) — así
que `$!` capturaba el PID del *wrapper* de `npx`, no el del proceso de Node que realmente
terminaba bindeando el puerto 3000. Matar solo ese wrapper dejaba el servidor real de Fase 1
(arrancado con `VENTANA_CANCELACION_MIN=0`) **huérfano y vivo**, todavía escuchando en :3000.
Cuando "Fase 2/2 - arrancar servidor limpio" intentaba arrancar OTRO servidor en el mismo puerto
milisegundos después, el proceso nuevo (el que debía tener la ventana DEFAULT de 120 min)
**crasheaba al bindear con `EADDRINUSE`** — pero el healthcheck del mismo paso igual respondía
`200 OK`, porque en realidad seguía contestando el servidor huérfano de Fase 1. `test-rn8-
ventana-cancelacion.mjs` terminaba corriendo, sin que nada lo indicara, contra la ventana 0 en
vez de la default, y sus aserciones de rechazo (409 esperado al cancelar/reprogramar DENTRO de
la ventana) fallaban con 200 — exactamente el síntoma real observado. Es un bug determinístico
(no una carrera rara dependiente del timing), consistente con que haya fallado ya en su primera
corrida y sin necesidad de mala suerte de horario.

Evidencia de confirmación (no solo razonamiento): se reprodujo la secuencia exacta del workflow
en local dos veces de forma contrastada — (1) arrancando con `npx ts-node ...` y matando el PID
de `$!`: el servidor seguía respondiendo 5+ segundos después, con procesos `node` huérfanos
todavía vivos (confirmado con `tasklist`/`Get-CimInstance` inspeccionando línea de comando); (2)
arrancando con el binario de `node_modules/.bin/ts-node` directo (sin `npx`) y matando el mismo
`$!`: el servidor moría limpio en ~1 segundo, sin huérfanos. Además, se forzó a propósito que dos
instancias del servidor compitieran por el puerto 3000 (una viva, otra arrancando encima): la
instancia nueva crashea con `EADDRINUSE` en su log pero `/health` sigue respondiendo `200 OK` —
mecanismo confirmado end-to-end, no solo plausible.

**Fix aplicado en `.github/workflows/turnos-backend-ci.yml` (commit `dc44aea`):**
- Arrancar el servidor invocando `node_modules/.bin/ts-node` **directo**, no `npx ts-node`, en
  los dos arranques del job `build-and-test` — elimina la causa raíz (el shim de npm usa `exec`,
  así que `$!` pasa a capturar el PID real del servidor).
- Al detener el servidor, esperar activamente (poll de `kill -0`, hasta 10s, con `SIGKILL` de
  respaldo) a que el proceso realmente termine antes de seguir, en vez de asumirlo tras el
  `kill` — defensa adicional, ya no es el fix principal, pero protege contra cierres lentos.
- Los tres pasos que corren scripts (`Fase 1/2` batería completa, `Fase 2/2` rn8, y el smoke
  test del job `docker-build-smoke`) ahora capturan su salida a un archivo (`scripts-fase1.log`,
  `scripts-fase2-rn8.log`, `smoke-test.log`) y lo vuelcan igual al log del step — no cambia el
  comportamiento visible, pero deja los logs disponibles como archivo para el paso siguiente.
- **Nuevo paso de diagnóstico en ambos jobs** (`permissions: contents: write` +
  `GITHUB_TOKEN`, mismo patrón ya usado en `turnos-mobile-ci.yml`, commit `cb20d12`): si el job
  falla, publica los logs capturados como comentario del commit — se confirmó activamente que
  este entorno vuelve a chocar con el mismo bloqueo de siempre (`GET .../actions/jobs/{id}/logs`
  → 403 sin login, aun en repo público) al intentar diagnosticar el run 31108620102, así que se
  aplicó el mismo workaround de forma preventiva en vez de esperar a necesitarlo de nuevo.
- **Adicional, no la causa de este incidente puntual (investigada y descartada como tal, ver
  arriba) pero sí una fragilidad real por separado:** en
  `scripts/test-rn8-ventana-cancelacion.mjs`, la consulta de "slots cercanos" pasó de `dias=1` a
  `dias=2` — con `dias=1` la ventana de disponibilidad consultada no cruza nunca un límite de día
  calendario, así que en la última hora antes de medianoche (huso del proceso) podía devolver
  menos de 2 slots. Se revisaron con `grep` los demás `scripts/*.mjs`: **ningún otro script tiene
  este patrón** — todos usan `dias=14` (explícito o el default de
  `calcularSlotsDisponibles`) o combinan un `desde` desplazado con `dias=2`, ambos ya robustos
  ante cualquier hora de corrida.

**Verificación:** batería completa de los 12 `scripts/*.mjs` re-corrida en local simulando la
secuencia EXACTA del workflow arreglado (dos arranques de servidor sobre el mismo puerto, en
procesos `bash` separados por step, igual que hace Actions) — limpia, sin fallos.
[Run 31115744124](https://github.com/matiasayago/TurnarioPro/actions/runs/31115744124) (commit
`dc44aea`, el primero con el fix): el job `build-and-test` — el que falló originalmente —
**terminó en verde, incluido el paso de `test-rn8-ventana-cancelacion`**, confirmando el fix en
el ambiente real de Actions. El job `docker-build-smoke` falló en ese mismo run, pero por una
causa no relacionada: el paso interno "Set up job" (provisto por GitHub, no por este workflow)
falló con anotaciones `"Failed to resolve action download info."` / `"Internal Server Error"` —
un hiccup transitorio de la infraestructura de Actions al resolver `actions/checkout@v4` (la
anotación ni siquiera ata a una línea real del YAML de este workflow), no un defecto de código.

## Cierre del gap de ownership de RLS + ratificación de 3 policies de Backend — DBA (2026-08-09)

Detalle completo, razonamiento columna por columna y secuencia de adopción en
`03-arquitectura/modelo-datos.md` §5bis (sección nueva). Resumen para reutilizar:

- **Contexto:** Backend migró el driver de `node:sqlite` a `pg` (PostgreSQL real) y, al conectar
  RLS a un Postgres real por primera vez, encontró que `runMigrations()` (`src/db.ts`) corre el
  DDL con el mismo rol/`pool` que sirve todo el tráfico de la app — ese rol se vuelve owner de las
  tablas (por correr `CREATE TABLE`), y Postgres ignora RLS para el owner salvo
  `FORCE ROW LEVEL SECURITY` (mecanismo que el diseño original de RLS, Fase 3, nunca implementó).
  Backend también agregó 3 policies nuevas (marcadas pendientes de ratificación) para que 2
  endpoints ya probados (`PATCH /profesionales/:id/configuracion`, `GET /profesionales/:id/slots`
  + la distinción 403/404 de cancelar/reprogramar) siguieran funcionando bajo RLS real.
- **Hallazgo propio de DBA, verificado contra el código real, no solo aceptado del reporte de
  Backend:** el gap de ownership es más grave de lo reportado — en `docker-compose.yml` y en el
  service container de CI, el rol de conexión (creado vía `POSTGRES_USER` de la imagen oficial
  `postgres:16-alpine`) es **superusuario del cluster**, y un superusuario bypassea RLS siempre,
  `FORCE ROW LEVEL SECURITY` incluido — agregar solo `FORCE` no cierra el gap en esos 2 de los 3
  ambientes del proyecto. Además, `calcularSlotsDisponibles` lee `turno` por `pool` directo (sin
  contexto RLS) en **dos** call sites, no solo en el endpoint público de slots — también dentro de
  la propia validación RN1/RN2 de `POST /turnos` — así que sin la policy pública de `turno`, el
  propio flujo de reserva (no solo la navegación anónima) quedaría en riesgo de aceptar
  solapamientos.
- **Arreglo aplicado (en `05-codigo/database/migrations/001_init.sql`, con copia idéntica en
  `05-codigo/backend/migrations/001_init.sql`):** `FORCE ROW LEVEL SECURITY` en las 5 tablas con
  RLS habilitada (cierra el gap donde el rol de conexión no sea superusuario/BYPASSRLS — a
  confirmar en Render, no verificado contra una cuenta real) + documentación exacta para DevOps de
  cómo separar un rol de MIGRACIÓN de uno de RUNTIME (única capa que garantiza RLS real en los 3
  ambientes) sin necesitar ningún cambio de código en `runMigrations()`.
- **Las 3 policies de Backend:** `profesional_update_propio_duracion_cita` y
  `turno_acceso_job_expiracion` ratificadas tal cual, sin cambios, verificadas contra el código
  real de cada endpoint. `turno_select_publico` (la más sensible — SELECT público sin ninguna
  restricción sobre `turno`) ratificada **con reserva, explícitamente transitoria**: necesaria hoy
  (confirmado, incluido el hallazgo adicional sobre `POST /turnos` de arriba), pero no debe quedar
  como diseño permanente — se agregaron 2 funciones `SECURITY DEFINER` de reemplazo
  (`turno_ocupacion_publica`, `turno_propio_para_gestion`) preparadas pero NO adoptadas todavía
  (requiere que Backend deje de leer `turno` por `pool`/`SELECT *` suelto, fuera del alcance de
  este ciclo) — la policy se retira recién cuando Backend adopte esas funciones, en el mismo
  cambio, para no romper nada por una secuencia mal coordinada.
- **Revisión en paralelo de Security (mismo patrón que Fase 5):** coincidió de forma independiente
  en el hallazgo de superusuario en docker-compose/CI, confirmó que el gap de ownership y
  `turno_select_publico` están acoplados (arreglar uno sin el otro en el mismo cambio rompe
  `GET /profesionales/:id/slots` y `scripts/test-autorizacion-cruzada.mjs`), coincidió en no dejar
  esa policy como diseño permanente, y pidió un test de RLS a nivel de base de datos (ningún test
  HTTP existente puede detectar este tipo de gap, porque la autorización de aplicación cubre el
  mismo terreno y lo esconde). Las 2 primeras correcciones (Security terminó su revisión antes que
  DBA) se incorporaron a la propuesta ANTES de cerrarla, no como un parche separado posterior —
  quedó como pauta reutilizable: cuando dos revisiones independientes (DBA/Security) tocan el
  mismo archivo en la misma ventana, coordinar en un único cambio, no en cambios secuenciales que
  puedan pisarse.
- **2 scripts nuevos en `05-codigo/database/scripts/` (no existía el directorio antes de este
  ciclo):**
  - `provisionar_roles_postgres.sql` — GRANTs exactos y secuencia completa para que DevOps separe
    los 2 roles en los 3 ambientes (docker-compose.yml/turnos-backend-ci.yml/render.yaml —
    ninguno de los 3 tocado por DBA en este ciclo, tarea de seguimiento explícita).
  - `verificar_rls_postgres.sql` — test de RLS a nivel de base de datos pedido por Security:
    siembra 2 tenants y verifica con `SET ROLE`/aserciones que el aislamiento cross-tenant y el
    cierre del gap de ownership funcionan de verdad, sin pasar por la app.
  - Ninguno de los 2 se ejecutó en este ciclo (este entorno sigue sin `psql`/Docker, mismo caveat
    de siempre) — quedan listos para la primera vez que exista un ambiente con Postgres real.
- **Fuera de alcance en este ciclo (no tocado):** código de Backend (`src/routes/`, `src/dominio/`,
  `db.ts`) — instrucción explícita del Director General IA de no tocar rutas/`db.ts`, solo
  migraciones SQL y documentación. `docker-compose.yml`/CI/`render.yaml` — tarea de DevOps.
  `pago`/`notificacion` sin RLS — gap preexistente ya documentado en §5, no ampliado.

## Reutilizable para futuros proyectos de la Factory (continuación 2)
- **En cualquier CI que arranque un proceso en segundo plano con `npx <binario-local> ... &` y
  necesite matarlo más tarde por PID, usar el binario de `node_modules/.bin/<binario>` directo en
  su lugar.** `npx` siempre hace `spawn` de un hijo real para ejecutar un binario ya instalado
  (nunca `exec`), así que `$!` termina apuntando al wrapper de `npx`, no al proceso real — matar
  ese PID deja el proceso real huérfano y vivo, ocupando el puerto/recurso que el siguiente paso
  cree que liberó. Los shims que genera npm en `node_modules/.bin/` sí usan `exec` de punta a
  punta, así que invocarlos directo hace que `$!` sea confiable. Aplica a cualquier lenguaje/CLI
  empaquetado como paquete npm con un `bin` propio, no solo a `ts-node`.
- Ante una hipótesis de causa raíz para un fallo de CI, conviene primero buscar evidencia barata
  que la confirme o refute ANTES de reproducir nada costoso: la API pública de jobs de GitHub
  Actions expone `started_at`/`completed_at` por step sin necesitar login — alcanza para descartar
  o confirmar rápido cualquier hipótesis que dependa del horario en que corrió un paso.
- Un job de un workflow puede fallar en el paso interno "Set up job" (antes de que corra
  cualquier step propio) por una falla transitoria de la infraestructura de Actions al resolver
  una action (`"Failed to resolve action download info."` / `"Internal Server Error"`, sin atar a
  ninguna línea real del YAML) — no confundir con un defecto de configuración: se distingue
  revisando las annotations del check-run (`GET /repos/.../check-runs/{id}/annotations`, también
  sin login) antes de tocar nada del workflow por esa causa.

## Resolución de HU-19/HU-20/HU-22 y reconciliación de alcance v1 — Product Manager (2026-08-10)

El Director General IA pidió resolver, antes de que DBA/Backend/Mobile arranquen la tanda de
Gestión de Pacientes/Ficha de Paciente/Historial/Configuración, 4 preguntas que UX/UI había
dejado abiertas en `04-diseno/mapa-pantallas.md`. Detalle completo y justificación de cada una
en `02-backlog/backlog.md`, mismo estilo que la justificación ya usada para HU-35. Resumen:

- **HU-19 (Activos/Inactivos/Recientes, §5.8):** el estado Activo/Inactivo ya estaba resuelto
  como manual desde el 2026-08-06 (CEO) — `mapa-pantallas.md` §5.8/§5.8bis quedó desactualizado
  sin sincronizarse con esa decisión (la verificación contra capturas reales es del 2026-08-07,
  posterior a la decisión, pero no la cruzó). Se formalizó esa reconciliación en el backlog. Lo
  genuinamente nuevo: se definió el criterio calculado que faltaba para "Nuevo" (alta en la
  cartera del profesional, últimos 30 días) y "Reciente" (último turno completado, últimos 30
  días) — ambas independientes del estado manual, calculadas al consultar (sin job ni columna
  propia). 30 días es una propuesta de Product Manager, sujeta a ajuste, mismo criterio que otros
  valores numéricos de esta ampliación (ej. HU-29).
- **HU-20 (ficha extendida por rubro, §5.9):** también ya estaba resuelto desde el 2026-08-06
  (D11/RN15) — mismo patrón de documentación desactualizada en `mapa-pantallas.md` §5.9, ahora
  reconciliado en el backlog. Se formalizó explícitamente para DBA/Mobile: los campos de salud
  son condicionales (ocultos por completo para rubros no-salud, no solo "opcionales pero
  visibles"), sobre una única entidad `Cliente` compartida entre rubros (columnas nullable, sin
  entidad separada por rubro). Se marcó como dependencia bloqueante de esta tanda la pregunta de
  implementación que ya tenía DBA pendiente (criterio determinístico de "rubro salud" — catálogo
  cerrado vs. flag booleano); no resuelta por Product Manager (es diseño técnico), sí escalada
  como bloqueante ahora que Mobile va a construir la pantalla que la necesita.
- **HU-22 (import/export en lote, §5.8):** marcada formalmente como **diferida, bloqueada para
  desarrollo**, por decisión del Director General IA (no de Product Manager) — UX/UI ya había
  pedido revisión de Security antes de implementar, por PII en lote. Sigue siendo parte del
  alcance de v1 (E0–E14); solo se resecuencia cuándo se construye, no si se construye. Ninguna
  otra historia de la tanda depende de HU-22.
- **Reconciliación del alcance v1** (`02-backlog/backlog.md`, nota de la tabla de épicas):
  verificado que la nota ya reflejaba, desde el 2026-08-06, que E9–E14 forman parte de v1 — no
  había una contradicción de negocio real, solo faltaba una conclusión explícita para quien
  leyera únicamente esa tabla sin cruzar con la sección "Roadmap de producto". Se agregó esa
  conclusión explícita, con la salvedad de la nueva diferida de HU-22.

No se tocó `04-diseno/mapa-pantallas.md` (UX/UI, entregable de otro rol) ni código de `05-codigo/`
— se documentó en el backlog la desactualización detectada en ese documento para que el Director
General IA decida si corresponde pedirle a UX/UI que lo sincronice.

## Modelado de Ficha de Paciente extendida (HU-20), historial clínico (HU-21) y login con Google (HU-35) — DBA (2026-08-10)

Detalle completo, razonamiento columna por columna y RLS en `03-arquitectura/modelo-datos.md`
§2quinquies/§2sexies/§5ter. Resumen para reutilizar:

- **HU-20/HU-21 — corrige un supuesto previo de este mismo archivo.** La entrada anterior
  ("Resolución de HU-19/HU-20/HU-22...", 2026-08-10, Product Manager, más arriba) asumía "una
  única entidad `Cliente` compartida entre rubros (columnas nullable, sin entidad separada por
  rubro)". Verificado contra el texto explícito de RN7/RN13/D3 (`documento-funcional.md` §3) y de
  HU-19/HU-22 (`backlog.md`) — "visible únicamente para el profesional que lo atendió/registró...
  no se comparte entre profesionales del mismo negocio", extendido EXPLÍCITAMENTE por HU-19 a la
  ficha completa, no solo al historial — esa cardinalidad no alcanza: no es 1:1 con `usuario`
  (no existe una tabla `Cliente`; el rol "cliente" es un valor de `usuario.rol`). Se modela una
  tabla `paciente` nueva, 1 fila por `(negocio_id, profesional_id, cliente_id)` — la ficha es
  propiedad del profesional que la lleva, aislada además por negocio (D1/RN9), no de la persona en
  sí. Dos entidades nuevas más, `tratamiento`/`nota_medica` (HU-21/D8/RN13), referencian
  únicamente `paciente_id`.
- **`negocio.es_rubro_salud` (D11/RN15)** — la pregunta de implementación que este mismo archivo ya
  tenía escalada como bloqueante (entrada de Product Manager de más arriba): se eligió un flag
  booleano dedicado (opción que la propia D11 sugería) sobre una lista cerrada de rubros, para no
  arriesgar invalidar los valores de `rubro` (texto libre) ya en uso. Gatea a nivel de aplicación
  (Backend/Mobile consultan la columna), no vía `CHECK` de base de datos (no se puede validar
  contra otra tabla sin trigger).
- **HU-35 — login con Google.** `usuario.password_hash` pasa a nullable + se agrega `google_id
  TEXT UNIQUE` (el claim `sub` de Google) + `CHECK (password_hash IS NOT NULL OR google_id IS NOT
  NULL)`. Se descartó un hash placeholder (caso especial invisible en el esquema) y una columna
  "proveedor_auth" separada (redundante, puede desincronizarse) — la combinación de las 2 columnas
  nullable ya deriva el/los métodos de login disponibles, con el `CHECK` garantizando que ninguna
  cuenta quede sin ningún método válido. De paso se agregó `usuario.telefono` (brecha real: dato
  documentado como básico desde el origen del proyecto pero nunca agregado como columna).
- **Hallazgo operativo — Render producción ya está migrado.** Es el primer ciclo de este proyecto
  en que editar `001_init.sql` directamente NO alcanza para que los cambios lleguen a la base real:
  `runMigrations()` (`backend/src/db.ts`) corre ese archivo una sola vez por base, gateado por
  "¿ya existe `usuario`?" — Render ya migró en el ciclo anterior (§Cierre del gap de ownership...,
  2026-08-09) y sigue corriendo (confirmado con un smoke test real contra
  `https://turnos-profesionales-backend.onrender.com`). Se actualizó `001_init.sql` igual (ambas
  copias, sigue siendo correcto para ambientes que migren desde cero) y además se creó
  `05-codigo/database/migrations/002_pacientes_historial_auth_google.sql`, el delta para aplicar a
  mano (`psql $DATABASE_URL -f ...`) contra Render u otro ambiente ya migrado — no se ejecuta
  solo, `runMigrations()` no lo conoce. Pendiente real para Backend/DevOps: correrlo contra Render,
  y considerar (recomendación, no implementada) que `runMigrations()` pase a soportar una
  secuencia de migraciones numeradas en vez de un único script "todo o nada".
- **RLS de las 3 tablas nuevas** — `FORCE ROW LEVEL SECURITY` desde el primer commit (lección
  directa del hallazgo de 2026-08-09), con un criterio MÁS estricto que `turno`/`servicio`: solo
  el profesional dueño de la fila pasa la policy, ni el administrador del negocio ni otro
  profesional del mismo negocio — coincide con el default ya documentado en
  `documento-funcional.md` §6 (administrador sin acceso al historial por defecto), que sigue sin
  cerrarse en este ciclo.
- **No verificado contra un Postgres real** (mismo caveat que casi todo el resto de este proyecto —
  Docker no está disponible en este entorno de desarrollo). SQL revisado manualmente con cuidado
  (balance de paréntesis verificado programáticamente, referencias entre tablas revisadas en
  orden). Prioridad para quien retome Backend: correr `002_pacientes_historial_auth_google.sql`
  contra un ambiente de prueba antes que contra Render producción directamente.
- **CORRECCIÓN (encontrada por el propio DBA al revisar el estado final, no reportada por
  terceros):** Security revisó HU-35/HU-20 en paralelo, en la misma ventana
  (`07-seguridad/informe-seguridad.md`, Adenda 2026-08-10) y sin coordinación directa conmigo.
  Coincidieron independientemente en el punto central de HU-20 (scope por profesional, no solo
  por negocio — validación cruzada útil, ver `modelo-datos.md` §5ter). Pero mi primer borrador del
  comentario de `usuario` en `001_init.sql` recomendaba a Backend vincular una cuenta Google
  automáticamente por coincidencia de email verificado — exactamente la alternativa que Security
  evaluó y descartó explícitamente por riesgo de account takeover (email reciclado/cuenta Google
  comprometida/Workspace). Corregido en el mismo ciclo, antes de cerrar la tarea, en
  `001_init.sql` (ambas copias) y `modelo-datos.md` §2sexies, para que ninguna de las dos fuentes
  quede contradiciendo la regla real ya aprobada (backlog.md HU-35: nunca autovincular, exigir
  confirmación de contraseña). Se deja registrado como recuerdo operativo: cuando dos roles
  modelan/revisan el mismo cambio en paralelo sin coordinación explícita, hay que releer el
  resultado del otro antes de dar el propio por cerrado — no alcanza con no haber tenido el
  hallazgo del otro disponible al momento de escribir la primera versión.

## Credenciales OAuth de Google para HU-35 (login con Google) — DevOps, con Arquitecto (2026-08-11)

Plan completo en `proyectos/turnos-profesionales/08-despliegue/google-oauth.md` — resuelve la
tercera y última pregunta abierta de HU-35 (`02-backlog/backlog.md`, ahora marcada como resuelta
ahí mismo, mismo patrón que ya usaron DBA/Security para las suyas). Resumen para reutilizar:

- **Enfoque técnico confirmado, sin alternativa mejor:** `google-auth-library`
  (`OAuth2Client.verifyIdToken`) del lado del backend, verificando el ID token que entrega el SDK
  de Google Sign-In del cliente (Mobile) — sin flujo de redirect, sin `client_secret`, sin
  reemplazar el JWT propio del proyecto (`05-codigo/backend/src/auth.ts`), que sigue siendo la
  única fuente de sesión de la app. Ya era el estándar de la empresa
  (`03-arquitectura/lineamientos-tecnicos.md`, "Autenticación: OAuth2/OIDC + JWT") desde antes de
  que existiera HU-35.
- **Una sola variable nueva, `GOOGLE_CLIENT_ID`** (Client ID de tipo "Web application" de Google
  Cloud Console) — mismo valor en todos los entornos (a diferencia de `JWT_SECRET`). **No hace
  falta `GOOGLE_CLIENT_SECRET`** — confirmado, ese flujo no lo usa. El Client ID de tipo
  "Android" (necesario igual, ver abajo) no se referencia en ningún código ni variable de
  entorno — Google lo matchea solo por nombre de paquete + SHA-1 de firma.
- **Gestión por entorno:** local (`.env`, ya gitignorado, `.env.example` actualizado), CI
  (deliberadamente ausente — el endpoint responde 503 sin mockear nada, HU-35 no bloquea el
  resto del backlog), Render (`05-codigo/backend/render.yaml`, entrada `GOOGLE_CLIENT_ID` con
  `sync: false`, mismo patrón que un secreto — el CEO la carga a mano en el dashboard cuando
  tenga el valor real).
- **Gateo mientras no existan credenciales reales:** el endpoint se construye igual, siempre
  montado, pero responde 503 con un mensaje claro si `GOOGLE_CLIENT_ID` no está seteada — no
  crashea el arranque (a diferencia de `JWT_SECRET`) ni se oculta con 404 (a diferencia de
  `ENABLE_DEV_ROUTES`, patrón que no encaja acá porque un 404 no distingue "no configurado
  todavía" de "no existe"). Backend/Mobile pueden construir ya, en paralelo, sin esperar al CEO.
- **Bloqueo real, no de este ciclo pero encontrado acá:** el Client ID de tipo Android necesita
  un nombre de paquete Android definitivo y un SHA-1 de un keystore de firma — ninguno de los
  dos existe todavía en este proyecto (`05-codigo/mobile` nunca fijó una organización propia ni
  generó un keystore, ver su README.md). Pendiente de Arquitecto/Mobile, no resuelto acá. El
  Client ID Web no depende de esto y se puede crear ya.
- **D15 (`01-requisitos/documento-funcional.md`, ya confirmada por el CEO) responde directamente
  si hace falta Client ID iOS: no todavía** ("solo Android por ahora... iOS/App Store queda para
  una release posterior") — se deja sin crear a propósito, no es un olvido.
- **Ninguna credencial real se creó en este ciclo** — ningún agente de IA puede crear el proyecto
  de Google Cloud (mismo tipo de límite que las cuentas de Render/Google Play/Apple Developer, ya
  documentado en ciclos anteriores de DevOps).
- **Concurrencia detectada durante este ciclo, nota operativa:** al crear la rama de este ciclo
  (`feature/google-oauth-plan`) se encontró al agente de Backend trabajando en paralelo, en vivo,
  sobre el mismo directorio de trabajo compartido (implementando el endpoint real de HU-35 en su
  propia rama, `feature/google-oauth-backend`) — coincide con lo esperado
  (`02-backlog/backlog.md`, HU-35: DevOps resuelve el plan de credenciales, Backend construye el
  endpoint en paralelo). Para no interferir con ese proceso, este ciclo se completó en un git
  worktree aislado en vez de en el directorio de trabajo principal — ver
  `08-despliegue/google-oauth.md` para el detalle; se deja anotado acá por si vuelve a pasar en un
  ciclo futuro.

## Configuración del lado Profesional (Perfil, Privacidad, Consultorio, Pagos, Reportes) — Backend (2026-08-12)

Completa 5 pantallas de Configuración que eran placeholder "Próximamente" (rama
`feature/configuracion-profesional`, sobre la tabla `usuario_preferencias` que DBA ya había
modelado y commiteado, HU-32). Detalle completo del contrato de cada endpoint en los comentarios
de `05-codigo/backend/src/routes/usuario.ts` (nuevo) / `negocios.ts` / `profesionales.ts`, y
resumen en `05-codigo/backend/README.md` ("Configuración del lado Profesional..."). Resumen para
reutilizar:

- **Se investigó antes de escribir código, como pedía la consigna** — 2 de los 5 bloques
  reutilizan/extienden algo que ya existía en vez de crearse de cero:
  `POST /profesionales/:id/servicios` (HU-04b) ya era upsert (`ON CONFLICT ... DO UPDATE`), así
  que el bloque de Precios y Señas solo necesitó un GET nuevo (listado con la seña actual) y un
  PATCH más angosto para edición explícita, sin duplicar la lógica de alta.
- **Router nuevo `usuario.ts`, montado en `/usuario`** (Perfil + Privacidad) — no existía ningún
  endpoint de "mi propio perfil" antes de este ciclo. Decisión de nombre documentada en el propio
  archivo: prefijo singular `usuario` (no `usuarios` plural, porque nunca opera sobre un tercero
  ni expone un listado — los routers plurales existentes sí exponen colecciones) y NO `cuenta`
  (pese a que `mapa-pantallas.md` agrupa Perfil+Privacidad bajo un menú de UI llamado "Cuenta") —
  se prioriza que el prefijo identifique la tabla sin ambigüedad, mismo criterio que
  negocios/profesionales/turnos.
- **Privacidad (`usuario_preferencias`) — cuidado explícito con RLS también en el GET, no solo en
  el PATCH.** La tabla tiene RLS FORCE con policy `usuario_id = app.usuario_id`; un `pool.query`
  directo en el GET habría devuelto 0 filas SIEMPRE (sin `app.usuario_id` seteado), mintiendo
  "está en default de fábrica" para una cuenta que en realidad ya personalizó su privacidad. Los
  dos hándlers van con `withTransaction` + contexto, no solo el de escritura.
- **Reportes (HU-28/E10) — v1 explícitamente acotada al lado Profesional este ciclo** (la
  consigna difirió a propósito la vista de negocio/administrador que también pide HU-28). 3
  definiciones elegidas, no dichas letra por letra en el backlog, documentadas en el propio
  código: (1) "completado"/"monto facturado" reusan la misma derivación que ya recomendó DBA para
  HU-21 (`estado = 'confirmado' AND fin < now()`, ver `001_init.sql`) — `estado_turno` no tiene
  un valor `'completado'` propio; (2) "monto facturado" = suma de `servicio.precio_referencia`
  (el precio del servicio, tal cual pide el backlog), no la seña; (3) `turnos_totales` excluye
  `estado = 'reprogramado'` (decisión propia): la fila vieja de un turno reprogramado (HU-13) no
  debe contarse junto con la fila nueva que representa la misma cita real, o se duplicaría.
- **Bug evitado por revisión de precedente, no por prueba:** Postgres devuelve `COUNT(*)` como
  `bigint`, que el driver `pg` de este proyecto parsea como STRING salvo un type parser custom
  que `db.ts` no tiene para ese OID — un SQL `COUNT`/`SUM` agregado habría devuelto
  `turnos_totales: "3"` en vez de `3` en el JSON. Se evitó por completo: siguiendo el mismo
  patrón que ya usa HU-21 en este archivo (empujar el booleano/comparación a SQL vía `now()`,
  agregar en JS con `.filter()`/`.reduce()`), no se escribió ningún `COUNT`/`SUM` en SQL.
- **`GET /negocios/:id` nuevo** (no existía detalle de un negocio puntual, solo el listado
  completo `GET /negocios`) — público, mismos datos que ya expone el listado, para que
  Configuración de Consultorio pueda prefillear sin traer todo el listado y filtrar del lado
  cliente.
- **`negocio`/`profesional_servicio` verificados en el DDL real antes de asumir RLS** (instrucción
  explícita de la consigna): ninguna de las dos tablas tiene `ALTER TABLE ... ENABLE ROW LEVEL
  SECURITY` en `001_init.sql` — a diferencia de `usuario_preferencias`. Los 3 endpoints que las
  escriben (`PATCH /negocios/:id`, `PATCH /profesionales/:id/servicios/:servicioId`) igual pasan
  por `withTransaction` con contexto, no por necesidad de RLS sino por consistencia con el resto
  de cada archivo (`negocios.ts`/`profesionales.ts` ya envuelven TODA escritura así, incluso
  antes de este ciclo, sobre tablas que tampoco siempre tienen RLS) — documentado explícitamente
  en el código para que quede claro que es una elección de estilo/forward-compat, no un
  malentendido sobre qué protege RLS hoy.
- **No verificado end-to-end en este ciclo — causa raíz distinta a la de ciclos anteriores.**
  Ciclos previos de DBA no podían verificar contra Postgres real por falta de Docker/psql en el
  entorno; este ciclo SÍ tenía acceso a un Postgres real ya migrado (`DATABASE_URL` de Render en
  `.env`, confirmado que ya corrió la migración de `usuario_preferencias`), pero **la conexión de
  red desde este entorno hacia ese host se resetea siempre** (`ECONNRESET`, confirmado con una
  prueba de conectividad aislada de 3 intentos directos con el driver `pg`, sin pasar por la app
  — no fue un hallazgo teórico ni una única falla transitoria) — dos intentos de arrancar el
  servidor local contra esa base también murieron por lo mismo (excepción no controlada dentro de
  `runMigrations()`, que `createApp()` invoca sin `await` ni `.catch()` — fragilidad preexistente
  de `src/app.ts`/`src/db.ts`, no introducida ni corregida en este ciclo, fuera del alcance
  autorizado). Mitigado con revisión estática exhaustiva (compilación limpia con `tsc --noEmit` +
  `npm run build`, y cada query/patrón contrastado línea por línea contra un equivalente ya
  probado en este mismo código — upsert, RLS-con-contexto, derivación de "completado", etc.).
  **Pendiente real para quien retome esto con salida de red disponible:** correr `npm run dev`
  (o el próximo intento del mismo entorno, si la restricción de red era puntual de esta sesión) y
  ejercitar los 6 endpoints nuevos de punta a punta antes de darlos por definitivos — no se
  agregó ningún script nuevo a `scripts/*.mjs` por el mismo motivo (no se puede commitear un test
  que nunca se corrió ni una sola vez).
- **No tocado:** `mapa-pantallas.md` (UX/UI) ni `05-codigo/mobile/` (instrucción explícita de la
  consigna — Mobile construye después sobre esto, en paralelo con otro agente).

## Configuración del lado Profesional (Perfil, Privacidad, Consultorio, Pagos, Reportes) — Mobile (2026-08-12)

Consume los 9 endpoints del bloque de Backend de arriba desde `configuracion_screen.dart`
(`05-codigo/mobile/lib/screens/profesional/`), conectando 6 ítems del menú a datos reales y
agregando 2 pantallas estáticas — detalle completo en el doc comment de `ConfiguracionScreen` y
en cada pantalla nueva. Resumen para reutilizar:

- **6 pantallas nuevas:** `editar_perfil_screen.dart`, `privacidad_screen.dart`,
  `configuracion_consultorio_screen.dart`, `precios_senas_screen.dart`, `reportes_screen.dart`,
  más las 2 estáticas `ayuda_soporte_screen.dart`/`acerca_de_screen.dart`.
- **"Configuración de Pagos" (Panel Profesional) y "Pagos y Señas" (su propia sección) apuntan a
  la MISMA pantalla** (`precios_senas_screen.dart`) — son, en los hechos, el mismo backend de
  seña por servicio (HU-04b); no hay contrato para los otros sub-ítems que muestra
  `mapa-pantallas.md` §5.11bis bajo "Pagos y Señas" (toggle "Reservas online con seña" a nivel
  negocio, "Historial de Señas"), así que esos quedan sin construir.
- **Configuración de Consultorio queda DE SOLO LECTURA a propósito** (no un recorte por tiempo):
  `PATCH /negocios/:id` exige rol `administrador`, y esta pantalla solo es alcanzable desde
  `ProfesionalShell` (siempre JWT de rol `profesional` → 403 garantizado). Documentado en el doc
  comment de la clase para quien retome esto cuando exista un shell de Administrador en la app
  (`main.dart` hoy cae a `LoginScreen` como placeholder para ese rol) — el backend ya soporta la
  edición completa, solo falta la UI del lado correcto.
- **Precios y Señas: guardado por fila**, no un botón general único — cada servicio es una
  edición independiente contra `PATCH /profesionales/:id/servicios/:servicioId` (no hay PATCH en
  lote), y un botón general obligaría a definir qué hacer si falla un servicio y otro no.
- **Reportes y Estadísticas (pantalla nueva) incluye un selector de período** (Todo/7 días/Mes/Año,
  `SegmentedButton`) calculado en el cliente sobre `DateTime.now()` y enviado como `desde`/`hasta`
  en UTC ISO-8601 — mejora sobre el mínimo pedido (que solo exigía que la versión sin filtros
  anduviera), agregada porque el costo era bajo (sin date picker, solo aritmética de fechas).
- **`RadioListTile.groupValue`/`.onChanged` (Privacidad, visibilidad de perfil) se migraron a
  `RadioGroup<String>`** — la API vieja está deprecada desde Flutter 3.32 (el SDK de este entorno
  es 3.44.9) y `flutter analyze` la marca como `deprecated_member_use`; no es una preferencia de
  estilo.
- **`flutter analyze` corrido localmente y limpio** (SDK disponible en este entorno, a diferencia
  de rondas de Backend anteriores): único hallazgo, el mismo `info` preexistente ya documentado en
  `dashboard_screen.dart:270`, ajeno a este cambio.
- **No tocado:** `05-codigo/backend/` ni `mapa-pantallas.md` (instrucción explícita de la
  consigna). Tampoco se tocó `lib/screens/profesional/configuracion_servicios_screen.dart` (una
  pantalla previa, más simple, ya huérfana de navegación desde antes de este ciclo — ver
  `05-codigo/mobile/README.md` — no confundir con `precios_senas_screen.dart`, la nueva).

## Modelado de bandeja de notificaciones + preferencias de notificación (HU-14b/HU-25/HU-26) — DBA (2026-08-12)

Rama `feature/notificaciones`, parada sobre `main` (previa a `feature/configuracion-profesional`,
ver nota de coordinación entre ramas más abajo). Detalle completo en
`03-arquitectura/modelo-datos.md` §2octies/§5quinquies. Resumen para reutilizar:

- **Investigación previa contra el código real (no asumida) — el hallazgo central del ciclo.**
  `notificacion` existía desde la Fase 3 original como un LOG (`turno_id`, `tipo`, `enviado_en`,
  `creado_en`), sin destinatario ni estado de leído. Verificado contra `backend/src/`: solo 2 call
  sites insertan hoy (`POST /turnos`, `PATCH /:id/reprogramar`, los 2 con `tipo = 'confirmacion'`
  literal); `PATCH /:id/cancelar` NO inserta nada; no existe ningún job de recordatorio
  (`src/jobs/` solo tiene `expirarPagosPendientes.ts`, que expira pagos, no envía avisos); y la
  interfaz `NotificacionProvider.enviar(destinatarioUsuarioId, tipo, mensaje)` de
  `integraciones/notificaciones.ts` nunca se invoca desde ningún endpoint. El wireframe
  (`mapa-pantallas.md` §5.15) confirma que las filas `confirmacion` existentes son, hoy, avisos
  para el PROFESIONAL del turno (redactadas en 3ra persona sobre la acción del cliente) — se
  backfillean así en `004_notificaciones.sql`.
- **Bandeja — se extiende `notificacion` (no tabla nueva).** Se agregan
  `destinatario_usuario_id` (UUID, **nullable a propósito** — mismo motivo que
  `usuario.telefono`/`google_id`: los 2 call sites existentes no se tocan en este ciclo y no van a
  pasar esa columna; NOT NULL sin default habría roto esos 2 INSERT, hoy funcionando, en
  CUALQUIER ambiente apenas corriera la migración), `leido` (BOOLEAN, default `false`) y
  `modificado_en`. `tipo` pasa de `TEXT` libre a ENUM `tipo_notificacion` (se agregan
  `'cancelacion'`/`'reprogramacion'`, sin renombrar `'confirmacion'` para no romper código
  existente). Deliberadamente NO se guarda texto armado — se deriva vía `turno_id` en Backend.
- **RLS de `notificacion` por primera vez** — la tabla nunca la tuvo, y la propia
  `modelo-datos.md` §5 ya lo dejaba anotado como pendiente ("necesitaría una política basada en
  subquery, no incluida en este slice"). La policy de INSERT tuvo que diseñarse alrededor del
  código existente, no al revés: verificado que `POST /turnos` inserta la notificación con
  `app.usuario_id` = el CLIENTE (nunca cambia a la identidad del profesional para esa sentencia,
  a diferencia de lo que sí hace para `paciente` más abajo en el mismo handler) — la policy de
  INSERT permite que cualquier participante del turno (cliente o staff) notifique a cualquier
  OTRO participante del MISMO turno, y acepta explícitamente `destinatario_usuario_id IS NULL`
  para no bloquear los 2 INSERT existentes.
- **Preferencias de notificación (HU-26) — tabla NUEVA, `usuario_preferencias_notificacion`, NO
  columnas en `usuario_preferencias`.** Se evaluó extender (mismo patrón que Privacidad/HU-32,
  y `usuario_preferencias` ya tiene nombre genérico) pero se decidió tabla propia por 2 motivos:
  (1) lógico — evitar que `usuario_preferencias*` degrade en un "cajón de sastre" a medida que
  Configuración suma pantallas; (2) **operativo, el que decide en la práctica** —
  `usuario_preferencias` la creó DBA en `feature/configuracion-profesional` (HU-32, commit
  7a106e8), rama todavía no mergeada a `main` al momento de este ciclo, así que esa tabla NO
  EXISTE en `feature/notificaciones`. Depender de ella habría acoplado esta migración al orden y
  éxito de un merge ajeno en curso. La tabla nueva comparte el prefijo (`usuario_preferencias_`)
  a propósito — misma familia conceptual, sin dependencia estructural entre ambas.
- **Nota de coordinación entre ramas (relevante para quien mergee `feature/notificaciones` y
  `feature/configuracion-profesional`, en cualquier orden):** ninguna de las 2 tablas nuevas de
  este ciclo referencia `usuario_preferencias` (HU-32) — 100% autocontenidas, sin importar el
  orden del merge. La migración incremental de este ciclo se numeró **`004_notificaciones.sql`**
  (no `003_*`, que ya lo usa HU-32 en la otra rama) para que ambas ramas no registren un mismo
  número al mergear. Si en un ciclo futuro conviene consolidar `usuario_preferencias` y
  `usuario_preferencias_notificacion` en una sola tabla, queda a criterio del Director General
  IA/DBA — no se resuelve acá.
- **Recomendación para Backend — 3 INSERT concretos que faltan para que la bandeja tenga
  contenido real** (no implementado en este ciclo, fuera de alcance de DBA): 1) `PATCH
  /:id/cancelar` (turnos.ts) — agregar `INSERT INTO notificacion` con `tipo = 'cancelacion'` y
  `destinatario_usuario_id` resuelto vía `turno.profesional_id -> profesional.usuario_id`; 2)
  `POST /turnos`/`PATCH /:id/reprogramar` — agregar `destinatario_usuario_id` al INSERT que ya
  existe (mismo JOIN); 3) job de recordatorio nuevo (no existe archivo todavía) — recorrer turnos
  próximos a iniciar e insertar `tipo = 'recordatorio'`, corriendo con
  `withTransaction(fn, { jobSistema: true })` (mismo patrón que `expirarPagosPendientes.ts`) — la
  policy `notificacion_insert_job_sistema` ya está lista para ese caso.
- **No verificado contra un Postgres real** (mismo caveat de siempre — sin `psql`/Docker en este
  entorno). SQL revisado con cuidado (balance de paréntesis verificado programáticamente sobre
  las líneas de código, excluyendo comentarios). Prioridad para quien retome Backend: correr
  `004_notificaciones.sql` contra un ambiente de prueba antes que Render, con foco en confirmar
  empíricamente que la policy de INSERT deja pasar los 2 call sites existentes tal como están hoy
  (sin `destinatario_usuario_id`).

## Notificaciones — bandeja + configuración + job de recordatorio (HU-14b/HU-25/HU-26) — Backend (2026-08-12)

Rama `feature/notificaciones`, sobre el modelado de DBA (commit `9d7204d`, ver entrada anterior en
este mismo archivo; `004_notificaciones.sql` ya aplicado a mano contra Render por el CEO — no se
corrió desde este ciclo). Detalle completo (contratos exactos, comentarios línea por línea) en
`05-codigo/backend/README.md`, sección "Notificaciones — bandeja + configuración granular". Resumen
para reutilizar:

- **Los 3 INSERT que DBA dejó documentados como recomendación se completaron/agregaron**, sin
  necesitar ningún cambio de identidad de RLS: `POST /turnos` y `PATCH /:id/reprogramar` agregan
  `destinatario_usuario_id` (el profesional del turno) al INSERT existente; `PATCH /:id/cancelar`
  agrega el INSERT que no existía, `tipo='cancelacion'`. Los 3 corren autenticados como cliente y
  la policy `notificacion_insert_evento_turno` (`004_notificaciones.sql`) ya contemplaba
  exactamente este caso (cliente inserta con destinatario = el profesional del mismo turno) —
  verificado leyendo la policy con cuidado antes de escribir código, no asumido.
- **Decisión tomada, no explícita en el pedido:** `PATCH /:id/reprogramar` sigue insertando
  `tipo='confirmacion'` (no `'reprogramacion'`, aunque DBA dejó ese label disponible en el ENUM) —
  el pedido de este ciclo fue completar el destinatario, no cambiar el tipo; queda documentado en
  el propio código para quien retome esta decisión.
- **Bandeja (`GET /notificaciones`):** texto armado en español en `src/dominio/notificaciones.ts`
  (`armarMensajeNotificacion`), derivado en cada lectura vía JOIN turno+usuario(cliente)+
  profesional+usuario(profesional) — nunca persistido, mismo criterio que dejó DBA. **No agrupa
  "Hoy"/"Ayer"** — decisión explícita: el backend no tiene ninguna noción confiable de la zona
  horaria del dispositivo, así que agrupar server-side asumiría una fija y podría mostrar "Ayer"
  en vez de "Hoy" cerca de la medianoche para un usuario en otro huso; devuelve lista plana
  ordenada por `creado_en DESC` (mismo patrón que `GET /turnos/mios`/`GET /clientes/:id/historial`
  ya establecido en este backend) y Mobile agrupa con su propio reloj local.
- **Router nuevo `src/routes/notificaciones.ts` en `/notificaciones`** (bandeja + `PATCH
  /:id/leer` + `PATCH /leer-todas` + `GET`/`PATCH /configuracion` para HU-26, mismo patrón
  lazy-upsert que `GET`/`PATCH /usuario/privacidad` de HU-32) — **no** `/usuario/notificaciones`:
  `src/routes/usuario.ts` no existe en esta rama (lo crea, con otro contenido, HU-32 en
  `feature/configuracion-profesional`, todavía no mergeada) — crearlo en paralelo acá habría
  producido el mismo archivo nuevo con historia divergente en 2 ramas, conflicto de merge
  garantizado. Queda como decisión a revisar en un ciclo futuro, después de mergear ambas ramas,
  si conviene reubicar `/notificaciones/configuracion` bajo `/usuario/*` para uniformar.
- **Hallazgo de RLS real, encontrado y corregido durante la implementación (no con una migración
  nueva — cambio de esquema, fuera del alcance de Backend):** el job de recordatorio
  (`src/jobs/recordarTurnosProximos.ts`) necesita chequear, antes de insertar, si un turno YA
  tiene un recordatorio — pero `notificacion` no tiene ninguna policy de SELECT que reconozca
  `app.job_sistema` (solo la de INSERT), a diferencia de `turno` (que sí tiene SELECT público,
  `turno_select_publico`). Un `NOT EXISTS` corriendo solo con `jobSistema: true` vería siempre 0
  filas y el job duplicaría el recordatorio en cada corrida, sin ningún error visible (RLS
  deniega leyendo 0 filas, no tira excepción — mismo patrón de riesgo silencioso que Security ya
  señaló para RLS en general). Se resolvió con la misma técnica que ya usa `POST /turnos` para un
  problema análogo: impersonar (`set_config('app.usuario_id', ...)`) al destinatario puntual de
  cada turno candidato justo antes de su propio `INSERT ... WHERE NOT EXISTS`, dentro de la misma
  transacción `jobSistema: true`. **Recomendación para DBA:** una policy de SELECT dedicada para
  `app.job_sistema` en `notificacion` (análoga a `turno_acceso_job_expiracion`) sería más directa
  a nivel de esquema. **Recomendación para QA/Security:** agregar este escenario a
  `database/scripts/verificar_rls_postgres.sql` cuando exista — ningún test HTTP existente lo
  detecta (RLS deniega en silencio).
- **`notificacionProvider.enviar` (`integraciones/notificaciones.ts`) sigue sin invocarse** desde
  ningún endpoint, a propósito — sigue siendo un stub que solo loguea (D4 no resolvió todavía qué
  proveedor de push real se usa); conectar el "envío" real queda para un ciclo futuro.
- No probado end-to-end contra Render (sin acceso de red desde este entorno — mismo caveat que
  ciclos anteriores). Verificado con `npx tsc --noEmit` (sin errores).

## Plan de credenciales de Google Play Billing para "Turnario Pro" (HU-29/E11) — DevOps (2026-08-14)

El CEO confirmó avanzar con HU-29. Plan completo en
`proyectos/turnos-profesionales/08-despliegue/google-play-billing.md`, mismo formato/nivel de
detalle que `08-despliegue/google-oauth.md` (HU-35). Resumen para reutilizar:

- **A diferencia del ciclo de OAuth, acá no hay ningún código de HU-29 todavía** (verificado: cero
  referencias en `03-arquitectura/modelo-datos.md` ni en `05-codigo/backend/src/`) — este
  documento es el primer paso de la cadena, no uno más en paralelo a Backend ya construyendo. Por
  eso este ciclo, a propósito, **no tocó `.env.example`/`render.yaml`/`backlog.md`** (nada del
  lado de código consume todavía esas variables) — la lista de variables futuras queda planteada
  en el documento (§7) para el próximo ciclo de DevOps, cuando Backend arranque la implementación
  real.
- **Secuencia real (mayormente secuencial, no paralela):** cuenta de Google Play Developer (CEO,
  USD 25 único + verificación de identidad) → generar `android/` de forma permanente en
  `05-codigo/mobile` (hoy solo existe `web/`, ver su README.md "Gap conocido") → confirmar
  `applicationId` → keystore de firma (Play App Signing recomendado) → crear la app en Play
  Console y subir un build firmado a Internal testing + configurar monetización (cuenta de pagos
  de Google) → recién ahí se puede crear el producto de suscripción real → cuenta de servicio para
  que Backend verifique compras server-side.
- **`applicationId` recomendado, pendiente de confirmación del CEO, NO aplicado:**
  `com.turnariopro.app` (coherente con el branding ya integrado en Mobile, todo en minúsculas).
  Resolver esto desbloquea dos cosas a la vez: generar `android/` correctamente desde el inicio, y
  el Client ID Android de OAuth que `google-oauth.md` §2 Paso 4 ya tenía pendiente por el mismo
  motivo (mismo dato, dos consumidores).
- **Precios exactos calculados (valores ya decididos por el CEO en `backlog.md`, solo se derivó el
  número):** mensual USD 9.00; anual USD 86.40 (=9×12×0.80), equivalente a USD 7.20/mes, ahorro de
  USD 21.60/año.
- **Modelo vigente de Play Console (a verificar al ejecutar):** ya no son "2 SKU" independientes —
  es 1 producto de suscripción (`turnario_pro`) con 2 "planes base" adentro (`mensual`/`anual`).
  Combinados como `turnario_pro_mensual`/`turnario_pro_anual` para uso interno en código.
- **Verificación server-side (Backend, no implementado en este ciclo):** mismo principio ya
  aplicado en este proyecto (nunca confiar un valor sin re-derivarlo del servidor). Paralelo
  directo con el flujo de HU-35: Mobile manda un `purchaseToken` (en vez de un ID token) a
  Backend, que lo valida contra la Android Publisher API de Google usando una cuenta de servicio
  propia (a diferencia de OAuth, que no necesita ninguna credencial de servidor). Recomendación
  técnica: reusar `google-auth-library` (ya es dependencia del backend por HU-35) en vez de sumar
  el paquete completo `googleapis` — mismo criterio ya aplicado en `google-oauth.md` §1.
- **Ninguna cuenta, pago, keystore ni producto real se creó en este ciclo** — ningún agente de IA
  puede crear la cuenta de Google Play Developer ni pagar los USD 25 (mismo tipo de límite ya
  documentado para Render/Google Cloud/Apple Developer). Generar `android/` y la keystore de firma
  sí son tareas técnicas delegables a un agente, pero tampoco se ejecutaron en este ciclo — la
  consigna pedía únicamente el plan, no la ejecución.

### Corrección el mismo día — cuenta y `applicationId` YA EXISTÍAN (Director General IA, 2026-08-14)

El CEO compartió una captura real de su Google Play Console: la cuenta de Google Play Developer
(Personal, "Matias Sayago") **ya existe** — el pago de los USD 25 y la decisión Personal/
Organización de arriba ya están resueltos, no son un paso pendiente. Además, ya hay una app
cargada con nombre "Turnario", paquete **`com.turnariopro.app`** (coincide con la recomendación
de arriba, pero no por casualidad de que DevOps la haya "adivinado" — es un valor que ya existía),
estado Borrador, 0 usuarios — confirmado por el CEO: es la **app hermana ya construida** (otro
código, la que sirvió de inspiración visual para el rediseño de este proyecto). El CEO decidió
explícitamente reusar ese mismo paquete para este proyecto en vez de crear uno nuevo. Detalle
completo y el nuevo ítem detectado (deadline de verificación de desarrolladores de Android,
30/09/2026) en `08-despliegue/google-play-billing.md` §1bis (agregado ahí, no se reescribió el
resto del documento). Consecuencia práctica: el paso de generar `android/` (delegado a Mobile este
mismo ciclo) ya puede usar `com.turnariopro.app` como valor definitivo, sin esperar ninguna otra
confirmación del CEO.

## Modelado de suscripción "Turnario Pro" (HU-29/E11) — DBA (2026-08-14)

Rama `feature/configuracion-profesional` (continúa sobre el commit de HU-32, `7a106e8`). Modela el
soporte de datos para el freemium por negocio de HU-29 — no toca Backend ni Mobile (ronda aparte).
Detalle completo en `03-arquitectura/modelo-datos.md` §2novies/§5sexies. Resumen para reutilizar:

- **Contexto verificado antes de modelar:** leído el plan de DevOps del mismo día
  (`08-despliegue/google-play-billing.md`, ver entrada anterior en este archivo) — confirma que
  `turnario_pro` es el ID de producto recomendado para Play Console con 2 "planes base"
  (`mensual`/`anual`), que la verificación real usará `purchaseToken` contra la Android Publisher
  API (no implementada por nadie todavía), y que el patrón esperado para este ciclo es
  "diseñar/mockear en paralelo, sin esperar" (mismo criterio que `MockPagoProvider`) — sin
  contradicciones con la consigna de este ciclo: ambos documentos usan el mismo vocabulario
  (`mensual`/`anual`, `turnario_pro`) de forma independiente.
- **Tabla nueva `suscripcion_negocio`, no columna `negocio.plan` sola.** Evaluadas ambas; se
  descarta la columna porque el plan pago necesita 3 atributos más (`periodo`/`vencimiento`/
  `estado`) que el gratis no usa — una columna sola de todos modos habría necesitado sumarlos ahí,
  ensanchando `negocio` (identidad) con un concern de facturación ajeno. Tabla separada, 1:1 con
  `negocio` vía `negocio_id UNIQUE` — mismo patrón estructural que `profesional`/`pago`/
  `usuario_preferencias` (GUID propio, no `negocio_id` como PK directamente).
- **3 ENUM nuevos, valores elegidos para coincidir literalmente con Play Console** (confirmado
  contra `google-play-billing.md`, no una coincidencia): `plan_negocio` ('gratis'/'turnario_pro'),
  `periodo_suscripcion` ('mensual'/'anual'), `estado_suscripcion_negocio`
  ('activa'/'vencida'/'cancelada'). CHECK nuevo
  (`ck_suscripcion_negocio_periodo_vencimiento_segun_plan`, mismo patrón que
  `ck_usuario_password_o_google`) fuerza `periodo`/`vencimiento` NULL si y solo si
  `plan = 'gratis'` — a nivel de base de datos, no solo documentado.
- **Con `creado_por`/`modificado_por`, a diferencia de `usuario_preferencias*`.** El "dueño" es
  `negocio_id`, pero `negocio_administrador` es N:M (puede haber más de 1 administrador) — quién
  activó/canceló la suscripción no es deducible de `negocio_id` solo, y es una pregunta de
  auditoría legítima para un dato de facturación. Mismo criterio que `negocio`/`paciente`.
- **Decisión explícita de NO modelar el `purchaseToken`/precio todavía — la parte más deliberada
  de este ciclo.** `pago.referencia_externa TEXT` (Fase 3 original) parece un precedente directo
  para anticipar una columna "por si hace falta" — pero, verificado contra `backend/src/` (grep,
  no asumido), esa columna NO tiene ningún consumidor real hoy, ni siquiera el propio
  `MockPagoProvider` la escribe. Se decide no repetir ese patrón: la activación simulada de este
  ciclo no produce ningún dato externo real que guardar. Cuando la verificación real de Google
  Play exista (`google-play-billing.md` §6), agregar la columna en una migración incremental
  futura — no antes. Tampoco se modela precio/monto (USD 9/USD 86.40 son configuración de
  producto, no un hecho transaccional mientras la activación sea simulada).
- **Default 'gratis' para negocios existentes — con backfill explícito, no solo convención.** A
  diferencia de `usuario_preferencias` (donde "sin fila = default" alcanza porque el efecto de una
  fila faltante es inerte), acá el concern puede BLOQUEAR una acción — se prefirió no depender de
  que Backend recuerde tratar "sin fila" como 'gratis' en cada lectura. `001_init.sql` resuelve
  los negocios NUEVOS solo con el `DEFAULT` de columna (no necesita backfill: una base nueva no
  tiene negocios todavía). `005_suscripcion_negocio.sql` agrega el backfill real para Render
  (`INSERT ... SELECT id FROM negocio ON CONFLICT DO NOTHING`), corrido ANTES de habilitar RLS en
  la misma transacción (mismo orden que el backfill de `004_notificaciones.sql`) para no depender
  de qué policy exista ni de los privilegios del rol que aplique el script. Regla general nueva,
  agregada a `modelo-datos.md` §1, para reutilizar en futuros concerns con efecto restrictivo.
- **RLS — 3 policies asimétricas, no una única simétrica.** Pedido explícito de esta ronda: lectura
  para administrador Y profesional del negocio (para mostrar "gratis: 42/60 turnos este mes" en
  Mobile), escritura solo para administrador. SELECT con el mismo criterio `EXISTS`/`OR` que
  `turno_acceso_negocio_o_cliente` (sin la rama de cliente); INSERT/UPDATE con el mismo criterio
  que `servicio_insert_admin_del_negocio`/`servicio_update_admin_del_negocio`; sin policy de
  DELETE (ningún endpoint la necesita, fail-closed por default). FORCE desde el primer commit,
  mismo criterio que toda tabla nueva desde §5bis.
- **Índice nuevo sobre `turno` existente, no solo sobre la tabla nueva.** El límite de 60 turnos
  confirmados/mes es, en la práctica, la query más caliente de todo HU-29 (corre en cada intento
  de reserva de un negocio gratis) — se agrega `idx_turno_negocio_confirmado_inicio`, parcial
  (`WHERE estado = 'confirmado'`) sobre `(negocio_id, inicio)`, mismo patrón que
  `uq_turno_slot_activo`. Supuesto NO verificado, señalado para Backend: indexa por `inicio` (fecha
  del turno), no `creado_en` — interpretación más consistente con "60, ~2/día" del backlog, pero
  reversible en una sola línea si Backend/Product Manager deciden lo contrario. El otro límite ("1
  profesional por negocio") no necesita índice nuevo — ya cubierto por la PK de
  `negocio_profesional`.
- **Alcance de este ciclo, por instrucción explícita: NO se tocó `backend/migrations/001_init.sql`**
  (la copia operativa que sí lee `runMigrations()`), a diferencia del patrón habitual de este
  proyecto de mantener ambas copias byte-idénticas en el mismo commit (ver el propio header de
  `database/migrations/001_init.sql`, líneas 11-20). Las 2 copias quedan divergentes hasta que
  Backend las sincronice en su próxima ronda — no bloquea Render (que de todos modos ignora
  `001_init.sql` una vez migrada) pero sí a cualquier ambiente nuevo que arranque desde la copia
  operativa. Documentado en el propio `005_suscripcion_negocio.sql` y en `modelo-datos.md` §4.
- **No aplicado contra Render** (a diferencia de `003`/`004`, que sí lo fueron por el Director
  General IA) — `005_suscripcion_negocio.sql` queda listo para revisión y aplicación manual, no
  ejecutado en este ciclo por instrucción explícita ("dejalo listo nomás"). No verificado contra
  un Postgres real por el mismo motivo de siempre (sin `psql`/Docker en este entorno) — balance de
  paréntesis de ambos archivos SQL revisado programáticamente antes de entregar.

## HU-29 "Turnario Pro" — cierre de ciclo: PR #11 mergeado y desplegado a Render (2026-08-14)

- **Migraciones 005 y 006 aplicadas contra Render** por el Director General IA (con aprobación
  explícita del CEO en cada una, vía `AskUserQuestion`) — no por DBA ni Backend, mismo patrón que
  `003`/`004`. Verificadas con impersonación de rol vía `set_config('app.usuario_id'/'app.negocio_id', ...)`
  en transacciones de solo lectura (`ROLLBACK` al final, nunca `COMMIT` en scripts de verificación).
- **PR #11 tuvo una regresión real en CI**, encontrada y corregida por el Director General IA (no
  por Backend): `scripts/test-duracion-configurable.mjs` fallaba al dar de alta un segundo
  profesional (paso de su propio setup, no relacionado a HU-29) porque el nuevo límite de 1
  profesional activo por negocio gratis lo bloqueaba. Fix: activar Turnario Pro (mock) para ese
  negocio de test antes de ese paso. Confirmado que ningún otro script de `scripts/` tenía el
  mismo patrón antes de dar el fix por bueno.
- **Desplegado a Render** (`2d8ffa5`, manual deploy vía dashboard, aprobado explícitamente por el
  CEO) y verificado en vivo contra `https://turnos-profesionales-backend.onrender.com`:
  `GET /negocios/:id/plan` responde 200 con la forma esperada (plan/periodo/vencimiento/estado/
  acceso_turnario_pro/turnos_confirmados_mes/profesionales_activos); `POST /negocios/:id/suscripcion`
  y `PATCH /negocios/:id/suscripcion/cancelar` devuelven 401 sin auth y 403 para un `profesional`
  (ambos son admin-only) — autorización confirmada correcta en producción, no solo local.
- **Pendiente, fuera de alcance de este ciclo**: conectar el flujo real de confirmación de pago de
  Mercado Pago (nunca estuvo conectado a ningún endpoint — hallazgo de Backend, documentado en
  `pagos.ts`) — a futuro debe llamar `exigirLimiteTurnosConfirmadosDelMes` en el mismo punto de
  transición `pendiente_de_pago` → `confirmado`. Además: no existe UI real para el rol
  `administrador` (activar/cancelar Turnario Pro hoy solo tiene endpoint, no pantalla Mobile).

## E15 "Modo Administrador v1" — shell + 5 pantallas Mobile (2026-08-15)

- **Origen**: el rol `administrador` tenía 6 endpoints backend admin-only sin ningún consumidor
  Mobile — `main.dart` mandaba cualquier cuenta con ese rol directo a `LoginScreen`, igual que un
  usuario no autenticado. Product Manager consolidó el alcance de una v1 en `02-backlog/backlog.md`
  (épica E15) antes de tocar código, priorizando lo que Backend ya soportaba sin cambios.
- **Decisiones de producto del CEO, ambas resueltas en el momento (no bloquearon la ronda):**
  (1) "No puede ser los dos" — un usuario NUNCA es Profesional y Administrador a la vez, confirma
  la restricción ya existente del modelo de datos (`usuario.rol` es un único valor) como regla de
  producto definitiva, no una limitación a resolver a futuro. (2) Acceso del administrador al
  historial de pacientes: el CEO pidió **acceso completo** (no el default conservador que proponía
  Product Manager) — pero al no tener backend hoy (choca con una regla de negocio ya documentada,
  D3/RN7: "el historial de un paciente SOLO lo ve el profesional que lo atendió"), el CEO aceptó
  la recomendación de secuenciarlo como **fast-follow aparte** (DBA+Backend+Mobile en otra ronda),
  no meterlo en esta.
- **Único gap de backend de toda la épica**: `GET /negocios/:id/profesionales` (roster del negocio
  — el alta ya existía, faltaba el listado). Agregado, verificado por el Director General IA de
  forma independiente contra Render real (roster vacío → con datos tras alta real, `id` correcto,
  401/403 de autorización), sin necesitar ninguna migración nueva (las 3 tablas del JOIN ya eran
  legibles bajo el contexto RLS de un administrador).
- **Bug real encontrado y corregido durante la revisión** (no introducido por esta ronda, preexistía
  desde HU-29): `tieneAccesoTurnarioPro` (`dominio/suscripciones.ts`) exigía `estado === 'activa'`
  a secas, lo que cortaba el acceso a Turnario Pro apenas se cancelaba la suscripción — contradice
  tanto el comentario del propio endpoint `PATCH /:id/suscripcion/cancelar` como la nota original
  de DBA sobre 'cancelada' ("conserva el acceso hasta que venza lo ya pagado, patrón común de
  SaaS"). Fix: `estado !== 'vencida'` en vez de `estado === 'activa'` — verificado en vivo contra
  Render real (activar → cancelar → `acceso_turnario_pro` sigue `true` hasta el vencimiento).
- **Mobile**: shell nuevo (`AdministradorShell`, hub simple sin bottom nav) + 4 pantallas nuevas
  (`administrador/`: Servicios, Profesionales, Turnario Pro) + 1 pantalla existente reutilizada en
  modo edición (`configuracion_consultorio_screen.dart`, antes de solo lectura para todo rol —
  ahora edita si la sesión es `administrador`, sigue de solo lectura si es `profesional`, mismo
  archivo/mismo `State` para ambos roles). Multi-negocio reusa el mecanismo ya construido para
  HU-27 (`elegirNegocio`/`entrarANegocio`), sin selector nuevo. Verificado de punta a punta por el
  Director General IA contra Render real: alta+listado de servicios y profesionales, el 402 del
  límite del plan gratis con su acceso directo a Turnario Pro, y activar/cancelar Turnario Pro.
- **Sigue fuera de alcance** (documentado en el backlog, no de esta ronda): reportes agregados de
  negocio (HU-28, sin backend), Mercado Pago (HU-30), acceso a historial de pacientes (fast-follow
  recién acordado arriba), baja/pausa de profesional o remoción de servicio (sin endpoint), pantalla
  de registro de negocio (HU-00a, gap ya documentado desde antes de esta ronda), resto de HU-31
  (horario general, dirección detallada, teléfono, logo).

## RLS de administrador — acceso de solo lectura al historial de pacientes (fast-follow de E15) — DBA (2026-08-15)

Detalle completo, razonamiento y verificación contra el código real de Backend en
`03-arquitectura/modelo-datos.md` §5septies (sección nueva). Resumen para reutilizar:

- **Contexto:** cierra el fast-follow que la entrada anterior de este archivo ("E15 'Modo
  Administrador v1'") dejó acordado: el CEO pidió "acceso completo" al historial de pacientes de
  su negocio para el rol `administrador` (rechazando el default conservador — sin acceso — que
  proponía Product Manager en `02-backlog/backlog.md`), y se secuenció como una ronda separada de
  DBA primero, Backend/Mobile después, en vez de meterlo en la ronda de E15.
- **Decisión de alcance, evaluada explícitamente por DBA, no asumida:** SOLO LECTURA (`SELECT`),
  no escritura. "Acceso completo" se interpretó como "el historial ENTERO visible" (ficha +
  tratamientos + notas, sin recortes), no como "con permiso de edición incluido" — nada en el
  pedido del CEO ni en ninguna HU/backlog pide que el administrador edite o borre un registro
  clínico ajeno, y RN7/RN13/D3 siguen íntegramente vigentes para la escritura (autoría clínica del
  profesional que atendió, con implicancia médico-legal). Mismo criterio de mínimo privilegio ya
  aplicado en otras decisiones de este proyecto ante instrucciones ambiguas: implementar la
  lectura más angosta que satisface lo pedido, dejar la más amplia como extensión futura aditiva
  si se llega a pedir explícitamente.
- **Diseño técnico:** 3 policies `FOR SELECT` nuevas (`paciente_select_admin_del_negocio`,
  `tratamiento_select_admin_del_negocio`, `nota_medica_select_admin_del_negocio`); ninguna de las
  3 policies `FOR ALL` ya existentes se modifica ni se separa. Se evaluó separar cada `FOR ALL` en
  `SELECT`/resto (tal como sugería un comentario ya existente en el DDL) y se descartó por
  innecesario: Postgres combina con OR, por comando, todas las policies `PERMISSIVE` que aplican a
  ese comando — sumar una `FOR SELECT` nueva ya amplía la lectura sin tocar las 3 policies `FOR
  ALL` originales (que siguen gobernando en exclusiva INSERT/UPDATE/DELETE). Menor superficie de
  cambio, mismo resultado, sin riesgo de regresión sobre policies ya en producción.
- **Verificado contra el código real de Backend** (`05-codigo/backend/src/routes/
  profesionales.ts`) antes de decidir que el agregado es inofensivo: las únicas rutas que hoy leen
  o escriben `paciente`/`tratamiento`/`nota_medica` exigen `requireAuth('profesional')` +
  `esPropioProfesional(req)` y fijan `app.usuario_id` al propio profesional — ningún código
  depende de que estas tablas tengan una única policy `FOR ALL`, así que el agregado no cambia el
  comportamiento de ninguna ruta existente.
- **Migración:** `05-codigo/database/migrations/007_paciente_historial_acceso_administrador.sql`
  (delta para Render, puramente aditivo, sin DDL de esquema ni backfill, 3 `CREATE POLICY`
  envueltos en un bloque `DO` con guard contra `pg_policy`, mismo patrón que `005`). A diferencia
  del ciclo de `005_suscripcion_negocio.sql`, esta vez **sí se sincronizaron ambas copias** de
  `001_init.sql` (`database/migrations/` y `backend/migrations/`), verificadas byte-idénticas.
- **No aplicado contra Render** — queda listo para revisión y aplicación manual del Director
  General IA, con aprobación del CEO, mismo flujo que las migraciones anteriores. No verificado
  contra un Postgres real por el mismo motivo de siempre (sin `psql`/Docker en este entorno) —
  balance de paréntesis de `001_init.sql` (ambas copias) y de `007_...sql` revisado
  programáticamente antes de entregar.
- **Fuera de alcance de este ciclo, por instrucción explícita:** código de Backend/Mobile (queda
  para una ronda posterior sobre este mismo diseño) y `01-requisitos/documento-funcional.md`
  (D3/RN7/§6)/`02-backlog/backlog.md` (E15) — la actualización formal de esos 2 documentos con la
  resolución del CEO le corresponde a Business Analyst/Product Manager, no a DBA.

## Fast-follow de acceso a historial de pacientes — cierre completo: Backend + Mobile (2026-08-15)

Continuación directa de la entrada anterior (DBA). Migración 007 aplicada contra Render por el
Director General IA (aprobación explícita del CEO) y verificada con datos reales: se creó una
ficha de paciente real (turno + `PATCH /profesionales/:id/pacientes/:pacienteId`) y se confirmó,
impersonando distintas identidades vía `set_config('app.usuario_id', ...)`, que (1) la
administradora dueña del negocio ve paciente+tratamiento+nota_medica, (2) el profesional dueño de
la ficha los sigue viendo igual que antes, y (3) un administrador de otro negocio no ve nada — los
3 casos dentro de una transacción con `ROLLBACK` final (sin dejar los tratamiento/nota_medica de
prueba, insertados a mano por no existir todavía un endpoint de alta para esas 2 tablas).

- **Backend**: 3 endpoints nuevos en `negocios.ts`, todos `requireAuth('administrador')` y de
  SOLO LECTURA — `GET /:id/pacientes` (listado, una fila por FICHA, no por persona — la misma
  persona atendida por 2 profesionales del negocio aparece 2 veces, sin fusionar), `GET
  /:id/pacientes/:fichaId` (detalle) y `GET /:id/pacientes/:fichaId/historial`
  (turnos/tratamientos/notas). Hallazgo de seguridad propio, no pedido explícitamente pero
  detectado y corregido en el mismo commit: como la policy RLS de DBA autoriza por
  `app.usuario_id` solo (sin `app.negocio_id`, porque un mismo administrador puede operar 2+
  negocios), cada query filtra ADEMÁS por `negocio_id = :id` en el propio SQL — sin ese filtro
  explícito, un administrador de los negocios A y B podría pedir la ficha de B bajo la URL de A y
  recibirla igual (la RLS lo autorizaría, es admin de B), rompiendo el aislamiento por negocio que
  el resto de la API sí respeta. El subagente de Backend se cortó por límite de sesión justo antes
  de correr sus propias pruebas — el Director General IA verificó personalmente el build y los 3
  endpoints (+ 401/403 de autorización) contra Render real antes de dar la ronda por buena.
- **Mobile**: 2 pantallas nuevas en `screens/administrador/` (`PacientesNegocioScreen` +
  `FichaPacienteNegocioScreen`, esta última combina ficha+historial en una sola pantalla con
  scroll — a diferencia de las 2 pantallas separadas del lado profesional, que existen por la
  necesidad de alternar a modo edición, algo que acá no aplica) + un 5to ítem "Pacientes" en el
  menú "Mi negocio" de `AdministradorShell`. Sin ningún botón de alta/edición, confirmado por el
  Director General IA leyendo el código Y verificando visualmente en el Browser pane contra datos
  reales de Render (ficha completa con alergias/notas médicas/contacto de emergencia, turno real
  en el historial, estados vacíos de tratamientos/notas correctos).
- Con esto, el fast-follow queda completo y desplegable — pendiente el mismo flujo de siempre
  (PR → CI → aprobación del CEO → merge → deploy a Render).

## Mobile: pantalla de registro de negocio (HU-00a) — PR #16 (2026-08-16)

Tercera ronda de "modo Administrador" tras historial de pacientes (PR #14) y reportes agregados
(PR #15) — esta vez elegida por el CEO entre 4 gaps ofrecidos (baja/pausa de profesional, resto de
HU-31, Mercado Pago real, y esta). Solo Mobile: el endpoint `POST /auth/registro-negocio` ya
existía en producción desde antes (`auth.ts`), sin ninguna UI que lo consumiera.

- **Mobile**: pantalla nueva `screens/registro_negocio_screen.dart`, pre-autenticación, accesible
  desde un link nuevo en `login_screen.dart` ("¿Todavía no tenés tu negocio en la app?
  Registralo"). Alta única de negocio+administrador (nunca devuelve `negocios` array — un negocio
  recién creado es por definición el único del admin nuevo — así que se salta el selector de
  negocio de HU-27 y hace `sesion.iniciarSesion` directo, mismo patrón que el login con Google).
  Validación de password client-side (mínimo 8, mismo mensaje que el backend) y manejo específico
  del 409 (email ya registrado) con mensaje propio en vez del genérico.
- **Verificado visualmente contra un negocio real, de punta a punta** (Director General IA, no
  solo lectura de código): registro completo con datos nuevos → auto-login → aterriza directo en
  `AdministradorShell` sin quedar tapado por la pantalla de registro (el `popUntil((route) =>
  route.isFirst)` funciona) → estado inicial correcto de un negocio recién creado (Plan Gratis,
  0/60 turnos, 0/1 profesionales) → los datos cargados en "Datos del Negocio" coinciden
  exactamente con lo tipeado. Repetido registrando con el mismo email: banner rojo con el mensaje
  específico esperado ("Ya existe una cuenta registrada con ese email..."), no el genérico.
- Sin cambios de Backend ni DBA en este round — PR solo con los 3 archivos de Mobile
  (`registro_negocio_screen.dart` nuevo, `login_screen.dart` + `README.md` con diffs mínimos).
  No requiere deploy a Render (nada de backend cambió).

## Recuperación de contraseña — modelo de datos (token de un solo uso) — DBA (2026-08-16)

Pedido del CEO, prioridad alta. Verificado por grep antes de modelar (no asumido): no existía nada
de este mecanismo ni en el esquema ni en el código — `usuario` solo tenía `password_hash`/
`google_id` para login normal (HU-35), sin ningún camino de reset. Alcance de la ronda (token
distinto del JWT de sesión, siempre hasheado, expiración corta, invalidable tras un solo uso o al
expirar) ya venía decidido por el Director General IA — este ciclo es solo el modelado de datos;
Backend implementa los endpoints en una ronda posterior. Detalle completo, razonamiento columna por
columna y RLS en `03-arquitectura/modelo-datos.md` §2decies/§5octies. Resumen para reutilizar:

- **Tabla nueva `token_recuperacion_password`** (no columnas en `usuario`: acá la cardinalidad SÍ
  fuerza tabla separada, 0..N tokens por usuario a lo largo del tiempo, no 1:1). Sin prefijo
  `usuario_` a propósito — ese prefijo se reserva para la familia `usuario_preferencias*`
  (preferencias planas 1:1), y esto no lo es. Columnas: `usuario_id` (FK), `token_hash` (NOT NULL
  UNIQUE — nunca el token en texto plano, mismo criterio que `password_hash`; se recomienda a
  Backend un hash rápido no adaptativo tipo SHA-256, no bcrypt, porque el token ya es de alta
  entropía y bcrypt sumaría costo de CPU por validación sin ganar nada), `expira_en` (NOT NULL, sin
  default — Backend lo calcula), `usado_en` (TIMESTAMPTZ nullable — NULL = vigente; con valor = ya
  no sirve, sea porque se usó o porque quedó invalidado por un pedido más nuevo del mismo usuario,
  misma columna cubre ambos motivos a propósito), `creado_en`. Sin `creado_por`/`modificado_por`
  (no por la regla de "auditoría reducida" de `usuario_preferencias` — acá NUNCA hay actor
  autenticado en ninguna escritura, ni siquiera indirectamente). Sin soft delete (nada referencia
  esta tabla).
- **Decisión propia de esta ronda, no solo "seguir la plantilla" de tablas anteriores — invalidar
  tokens anteriores del mismo usuario al pedir uno nuevo** (en vez de dejarlos expirar solos):
  reduce la cantidad de secretos vigentes simultáneos si el usuario reintenta varias veces seguidas
  ("no me llegó el mail"), sin perjudicar ese mismo caso de reintento (el link más reciente sigue
  funcionando). Garantizado a nivel de base de datos, no solo por convención: índice único parcial
  `uq_token_recuperacion_password_usuario_pendiente` sobre `(usuario_id) WHERE usado_en IS NULL` —
  a lo sumo 1 token pendiente por usuario, Backend queda obligado a invalidar antes de insertar uno
  nuevo o el INSERT falla por unicidad (23505).
- **Decisión más relevante del ciclo — esta tabla NO lleva Row Level Security**, a diferencia de
  las últimas 5 tablas nuevas del esquema (todas con `FORCE ROW LEVEL SECURITY` desde el primer
  commit). Verificado contra `backend/src/db.ts`/`src/routes/auth.ts` antes de decidir (no
  asumido): el patrón de RLS de este esquema depende de `current_setting('app.usuario_id')`,
  seteado siempre a partir de un actor YA AUTENTICADO — y ningún acceso a esta tabla tiene eso
  disponible en ningún momento de su ciclo de vida. Pedir la recuperación es anónimo (por email,
  sin sesión, mismo caso que `POST /auth/registro-cliente` sobre `usuario`, que tampoco corre con
  contexto RLS). Canjear el token es peor todavía que "no autenticado": es estructuralmente
  imposible saber `usuario_id` ANTES de la consulta `WHERE token_hash = ?` que es, precisamente, la
  que lo descubre — una policy `usuario_id = app.usuario_id` exigiría conocer de antemano el valor
  que la propia consulta todavía tiene que resolver. La protección real de esta tabla no es RLS —
  es alta entropía del token + hash + expiración corta + un solo uso + el índice único parcial de
  arriba, mismo principio de fondo que ya explica por qué `usuario.password_hash` tampoco depende
  de RLS en el login. Se evaluó y descartó agregar RLS con una policy permisiva transitoria (mismo
  patrón que `turno_select_publico`) por no sumar protección real y sí una falsa sensación de
  seguridad a quien lea el esquema.
- **Migraciones:** `05-codigo/database/migrations/001_init.sql` y
  `05-codigo/backend/migrations/001_init.sql` actualizados con la tabla nueva y verificados
  byte-idénticos (`git diff --no-index` sin salida). Delta incremental
  `05-codigo/database/migrations/008_recuperacion_password.sql` (puramente aditivo, sin backfill,
  idempotente vía `CREATE TABLE`/`CREATE UNIQUE INDEX ... IF NOT EXISTS`, reversible — bloque
  ROLLBACK comentado al final). **A diferencia de `002`–`007`, este archivo 008 NO se duplicó en
  `05-codigo/backend/migrations/`** — verificado contra `db.ts` que `runMigrations()` lee
  únicamente el nombre de archivo hardcodeado `"001_init.sql"` (nunca hace glob de la carpeta), y
  confirmado que ninguno de los 5 incrementales anteriores tiene copia ahí tampoco (ese directorio
  solo tiene `001_init.sql`) — se sigue el patrón ya establecido en los ciclos anteriores en vez de
  duplicar un archivo que `runMigrations()` nunca va a ejecutar.
- **No implementado en este ciclo, fuera de alcance de DBA:** código de Backend (2 endpoints
  nuevos, hashing del token, envío del email — recomendaciones detalladas dejadas en
  `001_init.sql`/`modelo-datos.md` §2decies) ni Mobile (pantallas "Olvidé mi contraseña"/"Nueva
  contraseña"). No aplicado contra Render — pendiente de revisión del Director General IA y
  aprobación del CEO, mismo flujo que las migraciones anteriores.

## Recuperación de contraseña — endpoints de Backend (HU-37) — Backend (2026-08-16)

Continúa el ciclo de DBA (entrada anterior) — implementa "casi al pie de la letra" la
"Recomendación para Backend" que ya había dejado escrita DBA en `001_init.sql`/`modelo-datos.md`
§2decies/§5octies, sin reabrir ninguna de esas decisiones (tabla, nombre, algoritmo de hash,
ausencia de RLS). Detalle completo en los comentarios de
`05-codigo/backend/src/routes/auth.ts`. Resumen para reutilizar:

- **`src/integraciones/email.ts` (nuevo)** — `EmailProvider`/`MockEmailProvider`, mismo patrón
  que `pagos.ts` (`PagoProvider`/`MockPagoProvider`). El Mock no envía nada real; el token en
  texto plano solo se loguea a consola si `ENABLE_DEV_ROUTES === 'true'` (mismo gate que
  `src/routes/dev.ts`) — nunca deja rastro del secreto fuera de ese modo.
- **`POST /auth/recuperar-password` / `POST /auth/reset-password`** (`src/routes/auth.ts`):
  SHA-256 (no bcrypt) para `token_hash`, por la razón que ya dejó DBA (token de alta entropía, no
  necesita costo adaptativo). TTL de 30 min configurable vía `RECUPERACION_PASSWORD_TTL_MIN` (el
  default de la app siempre es 30 — la variable existe únicamente para poder simular "token
  vencido" en pruebas sin esperar 30 minutos reales). Orden invalidar-pendiente-luego-insertar
  respetado tal cual lo exige el índice único parcial. La carrera de doble-submit en el canje
  (`UPDATE token_recuperacion_password ... WHERE id = $1 AND usado_en IS NULL`, `rowCount === 0`)
  se resuelve lanzando una excepción propia (`CanjeTokenEnCarreraError`) DENTRO de la transacción
  para forzar `ROLLBACK` del `UPDATE usuario` que ya había corrido antes en esa misma
  transacción — un simple `return` ahí habría dejado que `withTransaction` hiciera `COMMIT` igual
  y persistiera un cambio de contraseña que debía abortarse.
- **Rate limiting — limiter dedicado nuevo (`recuperacionPasswordLimiter`), no se reusó
  `loginLimiter` tal cual** (`src/middleware/rateLimit.ts`): `loginLimiter` cuenta solo intentos
  FALLIDOS (`skipSuccessfulRequests`), pero `POST /auth/recuperar-password` responde 200 SIEMPRE
  (criterio de no-enumeración) — con `skipSuccessfulRequests` ese límite nunca contaría nada,
  dejando el endpoint sin protección real contra spam de emails. El limiter nuevo cuenta TODOS los
  intentos (mismo patrón que `registroLimiter`) y se reusa, misma instancia, en ambos endpoints
  nuevos.
- **Decisión propia de esta ronda, dentro de una opción que el propio contrato ya dejaba abierta**
  ("el token debe quedar visible... ej. en un log del servidor, O en la respuesta del endpoint
  bajo el mismo gateo de `ENABLE_DEV_ROUTES`", `001_init.sql`/`modelo-datos.md` §2decies): además
  del log, la respuesta de `POST /auth/recuperar-password` expone un campo `token_dev` (nombre
  inequívoco, nunca presente si `ENABLE_DEV_ROUTES` no está activo) cuando sí se generó un token.
  Permite un script de verificación 100% HTTP, sin depender de leer stdout de un proceso servidor
  externo.
- **Verificación end-to-end contra Postgres real, no solo `tsc --noEmit`:** este entorno no tiene
  Docker instalado, y el único Postgres nativo ya presente (servicio de Windows,
  `postgresql-x64-18`) exige `scram-sha-256` sin credenciales conocidas — no se intentó adivinar
  contraseñas (bloqueado explícitamente por el propio sistema de permisos al primer intento, y de
  todos modos no hubiera sido un camino razonable). En cambio se inicializó una instancia Postgres
  18 **efímera y aislada** con `initdb`/`pg_ctl` propios (puerto 5433, autenticación `trust` solo
  para esa instancia descartable, datos en el directorio temporal de la sesión, nunca en el repo),
  se arrancó el backend apuntándole (`runMigrations()` corrió `001_init.sql` completo desde cero,
  confirmado con `\d token_recuperacion_password`), y se la borró por completo al terminar. No se
  tocó en ningún momento el `DATABASE_URL` de Render que ya estaba en `backend/.env` (apunta a la
  base real del proyecto, sin la tabla nueva porque el gate de `runMigrations()` salta el script
  completo en una base ya migrada — correrle scripts de prueba hubiera sido, además, un riesgo
  innecesario sobre datos que no son descartables).
- **Script nuevo `scripts/test-recuperacion-password.mjs`, corrido en verde**: caso feliz completo
  (pedir → canjear → la password vieja deja de funcionar → la nueva sí), reintento de un token ya
  canjeado (400), no-enumeración verificada por status+contenido en 2 casos (email inexistente Y
  cuenta 100%-Google responden exactamente igual, sin `token_dev`), invalidación de tokens
  anteriores al pedir uno nuevo (confirmado también a nivel de fila, no solo por HTTP), password
  corta rechazada sin "quemar" el token (zod corre antes de tocar la base), token vencido
  (corrida con `RECUPERACION_PASSWORD_TTL_MIN=0.1` para no esperar 30 minutos reales), token con
  formato inválido, campos faltantes. Para el caso "cuenta 100%-Google" (`password_hash IS NULL`)
  el script abre su propia conexión a Postgres (paquete `pg`, ya dependencia de producción del
  backend) e inserta la fila directo — es el único script de la carpeta que lo hace, documentado
  en su propio encabezado, porque `POST /auth/google` exige un ID token real y este entorno no
  tiene `GOOGLE_CLIENT_ID` configurado.
- **Regresión confirmada, no solo asumida:** `smoke-test.mjs`, `test-validaciones-campos.mjs` y
  `test-autorizacion-cruzada.mjs` corridos contra el mismo servidor (auth.ts/rateLimit.ts son
  archivos compartidos con el resto del backend) — los tres en verde, sin ajustes.
- **No implementado / pendiente, fuera de alcance de este ciclo:** proveedor de email real
  (bloqueante de LANZAMIENTO, no de desarrollo — ver nota operativa en `02-backlog/backlog.md`);
  pantallas Mobile ("Olvidé mi contraseña"/"Nueva contraseña", sin wireframe todavía, pendiente de
  UX/UI); aplicar `008_recuperacion_password.sql` contra Render (pendiente de aprobación del CEO,
  mismo flujo que las migraciones anteriores); revisión de Security del criterio de
  no-enumeración y de la invalidación de sesiones JWT ya emitidas al resetear la contraseña (
  ambos ya señalados como pendientes explícitos por HU-37/Product Manager, no nuevos de este
  ciclo).

## Verificación independiente de HU-37 contra Render real + 2 hallazgos propios — Director General IA (2026-08-16)

Continuación directa de la entrada anterior (Backend). Revisión de código (diffs completos de
`auth.ts`/`email.ts`/`rateLimit.ts`, incluida la confirmación de que `withTransaction` (`db.ts`)
hace `ROLLBACK` real ante cualquier excepción — clave para validar que `CanjeTokenEnCarreraError`
efectivamente revierte el `UPDATE usuario.password_hash` cuando pierde la carrera de doble-submit)
+ `tsc --noEmit` propio (limpio) + aplicación de `008_recuperacion_password.sql` contra Render
(aprobación explícita del CEO, aplicada vía script Node con `pg` — sin `psql` en este entorno,
mismo mecanismo ya usado para migraciones anteriores) + verificación end-to-end propia corriendo
`test-recuperacion-password.mjs` contra el backend local apuntando a Render real (no solo contra la
instancia efímera de Backend).

- **Migración 008 aplicada y verificada a nivel de esquema real**: `information_schema.columns` +
  `pg_indexes` contra Render confirmaron las 6 columnas y los 3 índices esperados
  (`_pkey`/`token_hash` UNIQUE/el parcial `uq_..._usuario_pendiente`) antes de correr ningún test
  funcional encima.
- **2 hallazgos propios en el script de verificación de Backend, corregidos en el momento (no
  relanzado un agente para esto, cambio mecánico y acotado):**
  1. `test-recuperacion-password.mjs` abre su propia conexión `pg.Client` sin manejar TLS — contra
     Render falla con `ECONNRESET` (mismo síntoma ya documentado antes en esta sesión para el
     backend en sí). Backend nunca lo detectó porque probó únicamente contra su instancia Postgres
     efímera local (sin TLS). Fix: mismo criterio que `resolveSsl()` de `db.ts`, leer
     `DATABASE_SSL=true` y pasar `{ rejectUnauthorized: false }`.
  2. La batería completa (~15 requests) comparte `recuperacionPasswordLimiter` entre
     `/recuperar-password` y `/reset-password` — con el default de la aplicación (10/15min) el
     propio script se topa con su propio rate limit a mitad de camino (falló, reproducido,
     exactamente en el request #11) y el resto de los casos fallan en cascada con 429 en vez de
     los códigos esperados. No es un bug del rate limiter (protege el endpoint correctamente) sino
     del script, que no lo tenía en cuenta. Backend tampoco lo topó en su propia corrida — no
     quedó documentado cómo evitó el límite en su ambiente. Fix: documentado en el propio
     encabezado del script (arrancar el SERVIDOR, no el script, con `RATE_LIMIT_RECUPERACION_MAX`
     alto para verificación), mismo criterio que ya usaba el header para `RECUPERACION_PASSWORD_TTL_MIN`.
- **Verificación end-to-end propia, en verde, contra Render real** (backend local con
  `DATABASE_URL`/`DATABASE_SSL=true` de Render, `RECUPERACION_PASSWORD_TTL_MIN=0.1`,
  `RATE_LIMIT_RECUPERACION_MAX=100`): los 27 checks del script pasaron, incluido el caso "token
  vencido" (espera real de ~8s). Backend local detenido al terminar; los usuarios de prueba
  (`recuperacion-*@test.com`, `google-only-*@test.com`) quedaron en Render, mismo criterio ya
  aplicado a los fixtures de prueba de rondas anteriores (no se limpian).
- Con esto, Backend de HU-37 queda verificado de punta a punta contra producción real, no solo
  contra el reporte del agente — pendiente Mobile (pantallas) y, después, el mismo flujo de
  siempre (PR → CI → aprobación del CEO → merge → deploy, esta vez si con deploy porque sí hay
  cambios de Backend).

## Mobile: pantallas de recuperación de contraseña (HU-37) — 2026-08-16

Cierra el lado Mobile de HU-37, sobre el contrato de Backend ya verificado de punta a punta contra
Render real en la entrada anterior (mismo día) — no se reabrió ninguna decisión de Backend/DBA de
esas dos rondas (nombre de campos, mensajes exactos, criterio de no-enumeración, TTL, `token_dev`).
Detalle completo en el doc-comment de cada pantalla nueva
(`05-codigo/mobile/lib/screens/recuperar_password_screen.dart`/`canjear_token_password_screen.dart`)
y en `05-codigo/mobile/README.md` (sección "🆕 Recuperación de contraseña"). Resumen para reutilizar:

- **2 pantallas nuevas + 1 link**, mismo patrón pre-autenticación que `registro_negocio_screen.dart`
  (HU-00a): `recuperar_password_screen.dart` (paso 1, pide email → `POST /auth/recuperar-password`)
  y `canjear_token_password_screen.dart` (paso 2, pide token + contraseña nueva + confirmación →
  `POST /auth/reset-password`), encadenadas con `Navigator.push` (nunca `pushReplacement`, para
  poder volver atrás). `login_screen.dart` suma un `TextButton` ("¿Olvidaste tu contraseña?") entre
  "Ingresar" y el botón de Google — decisión de UX propia (la consigna dejaba la ubicación exacta a
  criterio): cerca de "Ingresar" porque resuelve el mismo caso de uso, antes del login con Google y
  del registro de negocio (flujos sin relación con "olvidé mi contraseña").
- **Sin auto-login, a diferencia de HU-00a — la diferencia central de este flujo respecto a la
  plantilla que ya existía:** `POST /auth/reset-password` no firma ningún JWT nuevo, así que el 200
  del paso 2 no llama nunca `sesion.iniciarSesion`; solo hace
  `Navigator.popUntil((route) => route.isFirst)`. Alcanza sin ningún caso especial porque `_Router`
  (`main.dart`) reacciona al estado de `Sesion` (nunca autenticada en este flujo) y sigue mostrando
  `LoginScreen` en esa misma ruta raíz — mismo mecanismo de navegación que HU-00a, resultado distinto
  por construcción, no por un branch nuevo.
- **Mensaje genérico del backend (paso 1) y mensaje de éxito (paso 2) se muestran por `SnackBar`, no
  por el banner de feedback de la pantalla — decisión basada en un patrón ya existente en el código,
  no inventada:** se verificó que `registro_negocio_screen.dart`/`editar_perfil_screen.dart` ya
  usan ese mismo criterio (banner solo para error persistente; éxito transitorio por
  `ScaffoldMessenger`, que en este proyecto es global a nivel de `MaterialApp` y sigue visible aunque
  ya se haya navegado a la pantalla siguiente). El texto que se muestra es literalmente
  `resp['mensaje']` tal como lo manda el backend, nunca una copia hardcodeada en el cliente.
- **Campo de token multilínea + monoespaciado** (`minLines: 2, maxLines: 4`,
  `AppTypography.body(context).copyWith(fontFamily: 'monospace')`) — el token real son 64
  caracteres hexadecimales, ilegibles forzados a una sola línea. `token_dev` (campo que el backend
  agrega a la respuesta del paso 1 solo con `ENABLE_DEV_ROUTES=true`) se ignora a propósito: el
  campo de token arranca vacío siempre, igual que se comportaría contra producción real.
- **Validación client-side igual de estricta que HU-00a:** contraseña mínimo 8 caracteres, mismo
  mensaje exacto que `passwordSchema` (`'La contraseña debe tener al menos 8 caracteres'`, sin
  punto final, para que coincida literal); agregado nuevo de esta ronda — comparación contra
  "confirmar contraseña" antes de enviar, ya que el paso 2 no existía en ningún flujo anterior de
  esta app. El 400 del backend (`"Token inválido o vencido"`, mismo mensaje para las 3 causas
  posibles) se muestra tal cual, sin intentar distinguirlas del lado del cliente tampoco.
- **Hallazgo de entorno, reutilizable:** el `README.md` de rondas anteriores documentaba "este
  entorno no tiene el SDK de Flutter" para varias rondas de Backend, y por otro lado, para rondas de
  Mobile más recientes, que sí lo tenía en el PATH. En esta sesión puntual `flutter`/`dart` no
  resolvían en el PATH de la shell (`which flutter` fallaba), pero el SDK sí seguía instalado en
  `C:\flutter` — invocando el binario por ruta completa (`/c/flutter/bin/flutter.bat`) se pudo
  correr `flutter pub get` + `flutter analyze` + `flutter build web` con normalidad. Mismo
  lineamiento ya registrado más arriba en este archivo ("nunca asumir Flutter/Dart/Docker/psql
  instalados... verificar con `--version`"), con un matiz nuevo: tampoco asumir que no está
  instalado solo porque no resuelve en el PATH por defecto de la shell — vale la pena revisar
  ubicaciones conocidas (`C:\flutter`) antes de descartar la verificación real.
- **Verificado:** `flutter analyze` limpio (único hallazgo: el mismo `prefer_const_constructors`
  preexistente y ajeno a este cambio, `dashboard_screen.dart:383`, mismo baseline que rondas
  anteriores) y `flutter build web` (`√ Built build\web`, sin errores) — ambos corridos sobre los 3
  archivos tocados/nuevos de este cambio. `flutter doctor` confirma que este entorno sigue sin
  Android SDK ni Visual Studio (sin cambios respecto de lo ya documentado) — Web sigue siendo el
  único target verificable acá; no se intentó `flutter build apk`. No se corrió la app contra un
  backend real ni se probó visualmente en un browser — queda para verificación aparte del Director
  General IA, mismo criterio ya usado en rondas anteriores de Mobile sin entorno de ejecución
  interactivo.
- **No tocado:** `05-codigo/backend/` ni `05-codigo/database/` (contrato ya cerrado y verificado en
  las 3 entradas anteriores de este mismo archivo — Backend/DBA/Director General IA, todas
  2026-08-16). Tampoco `04-diseno/mapa-pantallas.md` (UX/UI dejó explícitamente sin wireframe este
  flujo por falta de evidencia — HU-37 fija el comportamiento funcional, no el layout).

## PR #17 — organización de rama + fallo real de CI + fix — Director General IA (2026-08-16)

Dos hallazgos propios en el cierre de esta historia, ninguno de los dos "solo re-lanzar el CI":

- **Todo el trabajo de HU-37 se había hecho sobre `feature/registro-negocio-mobile` (la rama del
  PR #16, todavía sin mergear)** en vez de una rama propia — un descuido de organización, no un
  problema de código. Se separó correctamente: `git stash push -u`, `git checkout main` (limpio,
  sin HU-00a), rama nueva `feature/recuperacion-password` desde ahí, `git stash pop` (con 3
  conflictos reales — `decisiones.md`/`mobile/README.md`/`login_screen.dart`, los 3 archivos que
  ambas rondas tocaron — resueltos a mano quedándose solo con el contenido de HU-37, verificado
  con `flutter analyze`/`tsc --noEmit` limpios después de resolver). 5 commits separados por rol
  (Product Manager/DBA/Backend/Mobile/memoria), PR #17 contra `main` real, "Able to merge" sin
  conflictos.
- **El CI de Backend falló de verdad en el primer push (run 31965043406) — investigado con logs
  reales, no asumido como flaky.** El paso de diagnóstico del workflow (mismo mecanismo ya
  documentado en esta sesión: comentario del commit vía `GITHUB_TOKEN`, necesario porque la
  descarga directa de logs sigue devolviendo 403 sin login) mostró la causa exacta: la fase de
  roles/RLS terminó en verde ("OK FINAL"), pero `scripts/test-recuperacion-password.mjs` (dentro de
  "Fase 1/2 - correr todos los scripts") falló en el request #11 con 429 — exactamente el MISMO
  hallazgo de rate limiting que ya se había encontrado y corregido en el propio script para
  verificación local (ver entrada "Verificación independiente de HU-37..." más arriba), pero que
  nadie había propagado al workflow de CI: `.github/workflows/turnos-backend-ci.yml` ya seteaba
  `RATE_LIMIT_LOGIN_MAX`/`RATE_LIMIT_REGISTRO_MAX` en alto para sus propios arranques de servidor,
  pero nunca se agregó `RATE_LIMIT_RECUPERACION_MAX` (variable nueva de esta misma historia) a esa
  misma lista.
- **Fix aplicado (commit `a9da987`):** `RATE_LIMIT_RECUPERACION_MAX: "1000"` agregado en los 2
  arranques de servidor del job (`Fase 1/2` y `Fase 2/2`, mismo patrón que las 2 variables ya
  existentes) — no se tocó ningún código de aplicación, el rate limiter en sí funciona
  correctamente (es exactamente lo que debe hacer contra tráfico real); el gap estaba solo en la
  configuración del entorno de CI.
- Reutilizable: cuando se agrega una variable de rate limiting nueva a un endpoint, revisar si
  algún script de `scripts/*.mjs` la ejercita con volumen suficiente como para necesitar el mismo
  override que ya reciben `RATE_LIMIT_LOGIN_MAX`/`RATE_LIMIT_REGISTRO_MAX` en el CI — no alcanza
  con que el script pase localmente con el límite manualmente elevado si el workflow no hace lo
  mismo.
- **Después del fix de rate limit, el re-run (run 31965450421) mostró un fallo DISTINTO** —
  `test-recuperacion-password.mjs` esta vez pasó completo (las 27 verificaciones en verde,
  confirmando que el fix funcionó), pero `test-rn8-ventana-cancelacion.mjs` (Fase 2/2) falló en
  "Setup falló: turno lejano #1 creado". Mismo protocolo ya establecido en esta sesión (ver
  entrada "Primera corrida real del CI de Backend" más arriba, y task #35 de antes de esta sesión
  — este script tiene flakiness ya documentada): se reprodujo el script EXACTO, con el código
  exacto de este PR (rama `feature/recuperacion-password`), contra Render real, arrancando el
  backend local sin override de `VENTANA_CANCELACION_MIN` (para que use el default de 120 min,
  igual que la Fase 2 del CI) — **pasó limpio, las 2 direcciones (rechazo dentro de la ventana,
  aceptación fuera de la ventana) verificadas sin fallos**. Confirma que no es una regresión real
  (ninguno de los cambios de este PR toca turnos/disponibilidad/cancelación) sino la misma
  fragilidad de entorno de CI ya conocida para este script puntual. Se usó "Re-run failed jobs"
  desde la UI de GitHub (mismo mecanismo ya usado antes en esta sesión) en vez de pushear ningún
  cambio de código — no había nada que arreglar en el repo.
- **Lección de proceso, propia:** un push de memoria (commit `60b6677`) hecho DESPUÉS de confirmar
  "All checks have passed" volvió a disparar el evento `pull_request: synchronize` (el filtro de
  paths de `push` no matchea `memory/`, pero `pull_request` re-evalúa el PR completo en cada sync,
  sin importar qué toque el commit puntual — ver la entrada anterior sobre por qué `push` y
  `pull_request` se comportan distinto acá) y `test-rn8` volvió a fallar, esta vez en un punto
  DISTINTO ("turno cercano #2" en vez de "turno lejano #1") — la firma clásica de flakiness no
  determinística, no de una regresión (un bug real fallaría siempre en el mismo lugar). Segundo
  "Re-run failed jobs", verde. Para la próxima: evitar pushear commits triviales (memoria/docs)
  después de que un PR ya quedó en verde y lo único que falta es aprobación de merge — cada push
  reinicia la ventana de exposición a la flakiness del CI.
- **PR #17 mergeado** (commit `2ce4bb1` a `main`, aprobación explícita del CEO) y **desplegado a
  Render** (aprobación explícita separada): Render no tiene auto-deploy configurado en este
  proyecto (confirmado — los últimos 12 deploys del servicio son todos `TRIGGER: Manual`), se
  disparó "Deploy latest commit" a mano desde el dashboard. Verificado en producción real tras el
  build (polling de `POST /auth/recuperar-password` hasta dejar de dar 404): la respuesta es
  exactamente `{"ok":true,"mensaje":"..."}` **sin `token_dev`** (confirma `ENABLE_DEV_ROUTES=false`
  en Render, tal como se esperaba — el secreto nunca se filtra en el ambiente real) y
  `POST /auth/reset-password` con un token inválido responde `400 {"error":"Token inválido o
  vencido"}` correctamente. HU-37 queda completa: diseñada, implementada, verificada de punta a
  punta contra Render real, mergeada y desplegada — pendiente solo el proveedor de email real
  (bloqueante de que el flujo sirva de verdad a un usuario final, no de que el código funcione) y
  la revisión de Security ya señalada como pendiente explícito.

## Datos operativos del negocio — horario, dirección, teléfono, logo (HU-31) — DBA (2026-08-17)

Cierra la mitad de DBA del gap que la ronda "Modo Administrador v1" (E15, 2026-08-15) había dejado
documentado explícitamente: HU-31 (`02-backlog/backlog.md`, épica E13) pide "horario general de
atención, dirección detallada, teléfono/contacto, logo o imagen" además de nombre/rubro/ubicación,
pero esa ronda conectó `PATCH /negocios/:id` a una pantalla real acotada a los 3 campos que ya
tenían columna, dejando el resto anotado como "requiere DBA + Backend antes de poder construirse".
Verificado el esquema actual de `negocio` antes de modelar (no asumido): confirmado que hoy solo
tiene `id, nombre, rubro, es_rubro_salud, ubicacion, creado_en, creado_por, modificado_en,
modificado_por, eliminado_en`. Detalle completo, columna por columna, en
`03-arquitectura/modelo-datos.md` §2undecies. Resumen para reutilizar:

- **4 columnas nuevas en `negocio`, todas `TEXT` nullable, sin `DEFAULT`:** `horario_atencion`,
  `direccion`, `telefono`, `logo_url`. Sin backfill posible ni con sentido (a diferencia de
  `suscripcion_negocio` en HU-29, que sí backfillea un plan por defecto) — son datos que solo cada
  administrador conoce de su propio negocio; un negocio existente queda sin ninguna cargada hasta
  que las complete desde Configuración de Consultorio.
- **`horario_atencion`** — texto libre, deliberadamente NO estructurado por día. Puramente
  informativo para el perfil del negocio; NO participa en el cálculo de disponibilidad real, que
  sigue resuelto enteramente por `disponibilidad`/`excepcion_disponibilidad` (por profesional, ya
  mucho más granular) — modelarlo estructurado hubiera duplicado esa lógica y arriesgado que ambas
  fuentes queden inconsistentes entre sí.
- **`direccion` — columna NUEVA, distinta de `ubicacion` (que no se toca).** Decisión tomada tras
  investigar el uso real de `ubicacion` en el código (no asumida): hoy es pública en
  `GET /negocios`/`GET /negocios/:id` y Mobile la muestra como referencia CORTA de zona/ciudad,
  concatenada con `rubro` en el subtítulo de cada card del listado de "Buscar Negocios" (HU-00b,
  `buscar_negocios_screen.dart`). HU-31 pide algo con propósito distinto y posterior en el embudo
  — la dirección postal completa (calle, altura, piso) para alguien que ya decidió ir a ESE
  negocio puntual —, algo que no tiene sentido amontonado en una lista de descubrimiento y que,
  además, redefiniría en silencio el significado de datos ya cargados por negocios existentes si
  se reusara `ubicacion` para ambos propósitos. `ubicacion` sigue exactamente igual; `direccion` es
  un campo nuevo que coexiste con ella.
- **`telefono`** — texto simple sin `CHECK` de formato, mismo criterio ya aplicado a
  `usuario.telefono`/`paciente.contacto_emergencia_telefono` (ninguna columna de teléfono de este
  esquema valida formato a nivel de base de datos).
- **`logo_url`** — URL de una imagen YA alojada en otro lado, NO un upload de archivo real: este
  esquema no tiene (ni este ciclo agrega) ningún servicio de almacenamiento de objetos, y un
  agente de IA no puede aprovisionar por su cuenta credenciales nuevas para uno — mismo criterio ya
  aplicado en esta Factory para no depender de infraestructura de storage nueva. Sin `CHECK` de
  formato de URL a nivel de base de datos (mismo criterio que `usuario.email`, tampoco validado en
  el DDL) — recomendado a Backend `z.string().url()` en `actualizarNegocioSchema` y a Mobile la
  misma validación client-side antes de "Guardar"; no se recomienda validar que la URL sea
  efectivamente una imagen (solo se confirma cargándola — `Image.network` con `errorBuilder` de
  fallback del lado de Mobile).
- **Sin cambios de Row Level Security ni índices nuevos.** `negocio` sigue sin tener RLS habilitada
  en ningún punto del esquema (confirmado contra el código real, incluido el propio comentario de
  `PATCH /negocios/:id` en `negocios.ts`). Ninguna consulta filtra por las 4 columnas nuevas — son
  campos de despliegue, cubiertos por el índice implícito de la PK.
- **Migraciones:** `05-codigo/database/migrations/001_init.sql` y
  `05-codigo/backend/migrations/001_init.sql` actualizados con las 4 columnas dentro del
  `CREATE TABLE negocio` existente y verificados byte-idénticos (`diff` sin salida). Delta
  incremental nuevo `05-codigo/database/migrations/009_negocio_datos_operativos.sql` (puramente
  aditivo, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` × 4, sin backfill, reversible — bloque
  ROLLBACK comentado al final). Mismo patrón que `008`: este archivo 009 NO se duplica en
  `05-codigo/backend/migrations/` — confirmado contra `backend/src/db.ts` que `runMigrations()`
  lee únicamente el nombre de archivo hardcodeado `"001_init.sql"` (nunca hace glob del
  directorio), y que ninguno de los 7 incrementales anteriores (002–008) tiene copia ahí tampoco.
- **No implementado en este ciclo, fuera de alcance de DBA:** `PATCH /negocios/:id` sigue
  aceptando únicamente `nombre`/`rubro`/`ubicacion` — recomendación completa de archivo y línea
  aproximada para extenderlo (`actualizarNegocioSchema`, el `UPDATE`/`RETURNING`, y los 2 `SELECT`
  públicos, todos en `src/routes/negocios.ts`) en `modelo-datos.md` §2undecies. Tampoco se tocó
  Mobile (`configuracion_consultorio_screen.dart` sigue con los 3 `TextEditingController` de
  siempre). No aplicado contra Render — pendiente de revisión del Director General IA y aprobación
  del CEO, mismo flujo que las migraciones anteriores.

## E15 fast-follow — pausar/reactivar un profesional y eliminar un servicio (HU-02/HU-03) — Backend (2026-08-17)

Cierra la OTRA mitad del mismo gap de E15 que dejó documentado el backlog (`02-backlog/backlog.md`,
"Fuera de alcance de v1-Administrador": *"Baja/pausa de un profesional del negocio, o remoción de
un servicio. Ninguno de los dos tiene endpoint (negocios.ts solo tiene alta para ambos
recursos)"*) — complementa, sin relación de dependencia, la entrada de DBA de arriba (esa es sobre
datos operativos de `negocio`; esta es sobre `negocio_profesional`/`servicio`, ya modelados desde
Fase 3). Detalle completo del contrato y del razonamiento en los comentarios de
`05-codigo/backend/src/routes/negocios.ts` (junto a cada handler) y en
`05-codigo/backend/README.md` (sección "E15 fast-follow..."). Resumen para reutilizar:

- **Sin migración nueva, confirmado antes de escribir código (no asumido):** `negocio_profesional`
  ya tenía `activo BOOLEAN NOT NULL DEFAULT true` y `servicio` ya tenía `eliminado_en
  TIMESTAMPTZ`, ambas desde Fase 3 — el gap era 100% de endpoint, no de modelo. Las 2 RLS policies
  de `UPDATE` que hacían falta también ya existían (`negocio_profesional_update_admin_del_negocio`
  / `servicio_update_admin_del_negocio`, `database/migrations/001_init.sql`) — DBA ya las había
  dejado listas "para activar/desactivar (ej. licencia o baja)" sin que nada las usara todavía.
- **`PATCH /negocios/:id/profesionales/:profesionalId`**, body `{ activo: boolean }`. Antes de
  escribir el endpoint se investigó contra el código real (pedido explícito de la consigna) qué
  implica pausar un profesional para el resto del sistema, en vez de asumir:
  - La reserva de turnos nuevos YA estaba bloqueada de punta a punta sin tocar nada más (HU-08 ya
    filtraba `activo=true`; `POST /turnos` y `POST /profesionales/:id/turnos` ya exigían membresía
    activa).
  - El roster del administrador (`GET /:id/profesionales`) ya estaba diseñado para este caso
    exacto — sigue mostrando al profesional pausado, marcado `activo:false`, en vez de
    desaparecer (confirmado leyendo su propio comentario, escrito en una ronda anterior).
  - Login/"vista activa" ya revalidaban `activo=true` contra la tabla real (no contra el JWT) en 2
    puntos (`emitirLoginParaUsuario`, `POST /auth/entrar-a-negocio`) — un profesional pausado sigue
    pudiendo loguearse (su cuenta no se toca) pero pierde el acceso a operar bajo ESE negocio.
  - **Hallazgo propio, evaluado y corregido dentro del mismo endpoint (no solo documentado):**
    reactivar (`activo:true`) una membresía pausada por esta vía NO pasaba por el chequeo del
    límite "1 profesional activo" del plan gratis (HU-29) que sí exige `POST
    /negocios/:id/profesionales` en su propia rama de reactivación — sin corregirlo, el PATCH
    nuevo habría sido una segunda vía para saltear ese límite. Se agregó el mismo chequeo
    (`verificarLimiteProfesionalesActivos`), aplicado solo en la transición real inactivo→activo.
  - **Hallazgo NO corregido, documentado en el código:** `GET /profesionales/:id/slots` no filtra
    por `negocio_profesional.activo` (no habilita reservar por sí solo, así que no era el riesgo
    real) — señalado para una ronda futura de Backend, no se tocó `calcularSlotsDisponibles` sin
    confirmar alcance primero.
- **`DELETE /negocios/:id/servicios/:servicioId`** — soft-delete (`eliminado_en = now()`), nunca
  `DELETE` físico. Se revisó, query por query, cada lectura de `servicio` en `src/` (pedido
  explícito de la consigna):
  - **Bug real encontrado y corregido en el mismo cambio** (no solo un hallazgo documentado):
    `POST /turnos` (turnos.ts) y `POST /profesionales/:id/turnos` (profesionales.ts) NO filtraban
    `servicio.eliminado_en` — un servicio dado de baja por el administrador seguía siendo
    RESERVABLE si se conocía su id, exactamente el riesgo que anticipó la consigna. Corregido
    agregando `AND eliminado_en IS NULL` a los 2 `SELECT` (mismo 404 que ya existía para "no
    existe" — no es un contrato nuevo).
  - 3 lecturas que NO filtran y se dejaron sin tocar, documentadas como hallazgo porque ninguna
    habilita reservar por sí sola: `GET /:id/servicios/:servicioId/profesionales` (HU-08),
    `POST /profesionales/:id/servicios` (auto-asociación del profesional) y
    `GET /profesionales/:id/slots` (mismo `calcularSlotsDisponibles` del hallazgo de arriba, ahora
    confirmado que tampoco filtra `eliminado_en`, no solo `activo`). `PATCH /turnos/:id/
    reprogramar` a propósito tampoco filtra — un turno vigente para un servicio ya discontinuado
    tiene que poder seguir reprogramándose/cancelándose.
  - Reportes e historial (`GET /negocios/:id/reportes`, `GET /profesionales/:id/reportes`,
    `GET /clientes/:id/historial`) confirmados SIN cambios, a propósito — turnos ya existentes de
    un servicio eliminado se tienen que poder seguir leyendo (facturación pasada real).
- **Verificado de punta a punta contra Render real** (mismo `DATABASE_URL` de `.env` de rondas
  anteriores; esta vez la conexión SÍ fue alcanzable desde este entorno con `DATABASE_SSL=true`,
  sin el `ECONNRESET` que bloqueó una ronda anterior) con un script nuevo,
  `scripts/test-baja-profesional-y-eliminacion-servicio.mjs`: los 2 endpoints, sus 4 tipos de caso
  negativo (401/403 rol/403 negocio ajeno/404 cross-negocio/404 inexistente/400 body inválido), el
  límite de HU-29 aplicado a la reactivación, y los 2 hallazgos de arriba confirmados EN VIVO (se
  pidieron slots reales para un profesional pausado y para un servicio eliminado, y ambos
  efectivamente los devolvieron) — **40/40 verificaciones (`ok()`) en verde**, más las 15
precondiciones de setup (`assert()`) también satisfechas. Se re-corrió además, contra
  el mismo servidor, una batería de 8 scripts preexistentes sin relación directa con este cambio
  (`test-validaciones-campos`, `test-multinegocio`, `test-autorizacion-cruzada`,
  `test-critical1-aislamiento-admin`, `test-rn1-disponibilidad-y-solapamiento`,
  `test-rn4-servicio-no-asociado`, `test-duracion-configurable`, `test-turno-sin-sena`) para
  confirmar que el fix de `eliminado_en` en las 2 rutas de alta de turno no rompió ningún camino de
  reserva ya existente — los 8 en verde. `smoke-test.mjs` falló, investigado y confirmado NO
  relacionado con este cambio: usa el email fijo `admin@garcia.test`, ya registrado en esta base de
  Render desde una ronda anterior (2026-08-10 — confirmado consultando la fila directo con una
  query aislada antes de descartarlo como causa) — ese script asume una base efímera/recién
  migrada, no la base compartida persistente que reusan las rondas de verificación de este
  proyecto; no se tocó (no es un defecto de este cambio).
- **Hallazgo de proceso propio, no de código:** este servidor de prueba se levantó con
  `node --env-file=.env dist/src/index.js` (Node 26, `--env-file` nativo) en vez de `dotenv`
  (no es dependencia de este backend) — `--env-file` no pisa variables ya seteadas en el proceso
  que lo invoca, así que `DATABASE_SSL=true`/`ENABLE_DEV_ROUTES=true`/límites de rate limiting
  elevados se pasaron como variables de entorno del propio comando, combinadas sin conflicto con
  `DATABASE_URL`/`JWT_SECRET` que sí vienen de `.env`. Reutilizable para la próxima ronda que
  necesite un servidor local contra Render sin querer editar `.env`.
- Se confirmó además (verificado, no asumido) que un cambio concurrente de DBA en este mismo commit
  de trabajo (ver la entrada inmediatamente anterior, columnas nuevas de `negocio`) no afecta nada
  de lo implementado acá: las 2 tablas involucradas (`servicio`/`negocio_profesional`) y sus 2
  policies de `UPDATE` quedaron byte-idénticas antes y después de ese cambio (solo se desplazaron
  de línea) en ambas copias de `001_init.sql`, que siguen siendo idénticas entre sí.
- No se tocó Mobile (fuera del alcance de este ciclo — el CEO no pidió pantallas nuevas, solo
  cerrar el gap de Backend) ni ningún entregable ya aprobado de otro rol.

## HU-31 — extender PATCH /negocios/:id con datos operativos del negocio — Backend (2026-08-17)

Cierra la mitad de Backend del gap que dejó documentado DBA en la entrada inmediatamente anterior
de este mismo archivo (columnas nuevas de `negocio`) y en `03-arquitectura/modelo-datos.md`
§2undecies, que ya dejaba una recomendación de archivo/línea para este mismo PATCH. Detalle
completo del contrato en los comentarios de `src/routes/negocios.ts` (junto a cada handler) y en
`05-codigo/backend/README.md` (sección "HU-31 — Datos operativos del negocio"). Resumen para
reutilizar:

- **`src/routes/negocios.ts`** — 3 puntos tocados, todos siguiendo el patrón EXACTO que ya tenían
  `nombre`/`rubro`/`ubicacion` (el endpoint no arma el `UPDATE` de forma dinámica, así que sumar
  columnas fue directo, sin necesidad de rediseñar nada):
  1. `actualizarNegocioSchema` suma `horario_atencion`/`direccion`/`telefono` como
     `z.string().nullable()` (NO `.optional()` — hace falta poder mandar `null` explícito para
     vaciar un campo ya cargado) y `logo_url` con `z.string().url(...)` (recomendación explícita
     de DBA: `negocio` no tiene `CHECK` de formato de URL a nivel de base).
  2. El `UPDATE ... RETURNING` de `PATCH /:id` suma las 4 columnas al mismo `SET` fijo y al mismo
     `RETURNING` que ya tenían las 3 originales.
  3. `GET /negocios/:id` suma las 4 columnas al `SELECT` (endpoint de "perfil completo de un
     negocio ya elegido", que es exactamente lo que pide HU-31). `GET /negocios` (listado) NO las
     suma — decisión de diseño de Backend, no cerrada por DBA (la dejó explícitamente abierta):
     son datos de perfil, no de descubrimiento, y hoy ningún consumidor (Mobile no se tocó) los
     renderiza en el listado; razonamiento completo en el comentario del propio handler.
- **Confirmado contra el código real, no asumido**, que `POST /auth/registro-negocio`
  (`src/routes/auth.ts`) y `POST /dev/seed` (`src/routes/dev.ts`) no necesitaban cambios: ambos
  siguen insertando `negocio` con únicamente `(id, nombre, rubro, ubicacion, creado_en)`.
- **Verificación — NUNCA contra Render, instrucción explícita de este ciclo** (la migración
  `009_negocio_datos_operativos.sql` de DBA sigue sin aplicarse ahí, pendiente de aprobación
  separada del Director General IA/CEO). Sin Docker ni el servicio nativo de Postgres del sistema
  disponibles/usados para esto: se levantó un cluster de PostgreSQL 18 **efímero y aislado**, con
  los binarios ya instalados en el sistema (`initdb`/`pg_ctl` de `C:\Program Files\PostgreSQL\18\
  bin`) pero un `PGDATA` propio en un directorio temporal fuera del repo y un puerto propio
  (5433, el servicio nativo del sistema sigue en 5432 sin tocarse), nunca usado por ningún otro
  proceso. Al ser una base migrada desde cero, `runMigrations()` (`src/db.ts`) corrió
  `migrations/001_init.sql` completo — que YA incluye las 4 columnas nuevas (DBA ya lo había
  actualizado) — sin necesitar aplicar `009_negocio_datos_operativos.sql` por separado (ese delta
  incremental es solo para una base YA migrada antes de este ciclo, como Render; una base nueva no
  lo necesita). Backend arrancado con `node dist/src/index.js` y `DATABASE_URL` apuntando a ese
  cluster efímero, pasado como variable de entorno del propio comando (nunca se tocó `.env`, que
  sigue apuntando a Render sin cambios). Script nuevo, `scripts/test-datos-operativos-negocio.mjs`:
  carga de los 4 campos, vaciado con `null` explícito (confirmado releyendo con `GET /:id` aparte,
  no solo el response del propio PATCH), `logo_url` con formato inválido -> 400 (y que NO modifica
  el valor ya cargado), omitir un campo nuevo del body -> 400 (confirma que no son `.optional()`),
  admin de otro negocio no puede tocar estos campos -> 403 (chequeo de ownership existente, sin
  cambios), y `GET /negocios` confirmado que NO trae las 4 columnas — **100% en verde**. `npx tsc
  --noEmit` limpio.
- **Hallazgo de proceso propio, no de código — bug real en la regresión, no en el feature.**
  5 scripts preexistentes de `scripts/` (`smoke-test`, `test-multinegocio`,
  `test-validaciones-campos`, `test-critical1-aislamiento-admin`, `test-autorizacion-cruzada`)
  tienen `const BASE = 'http://localhost:3000'` **hardcodeado**, a diferencia de
  `test-recuperacion-password.mjs` (único precedente que sí soporta `BASE_URL` de entorno) — al
  correrlos con `BASE_URL=http://localhost:3002` (el puerto de mi servidor local) asumiendo que
  todos lo respetaban, en realidad siguieron apuntando a :3000, donde YA había otro proceso
  `ts-node-dev` corriendo (ajeno a esta sesión, no arrancado acá) conectado a una base con 44
  negocios históricos de rondas anteriores. Investigado antes de asumir nada: un intento de
  confirmar por `psql` directo si esa base era Render fue bloqueado por el clasificador de permisos
  de la sesión (conectar a Render no está autorizado en este ciclo) — evidencia circunstancial
  fuerte igual (nombres de negocio como "Demo Verificacion Visual", coincidente con una
  verificación contra Render ya documentada en este archivo el 2026-08-12) apunta a que es Render o
  una base compartida persistente equivalente, no un entorno descartable. **Efecto real, acotado**:
  2 de esos 5 scripts (`test-multinegocio`, `test-baja-profesional-y-eliminacion-servicio`, este
  último con el mismo problema) llegaron a correr una vez completa contra ese destino equivocado
  ANTES de detectar el problema, creando ahí un puñado de filas de prueba aditivas (negocios/
  profesionales/servicios/clientes/turnos, emails únicos por timestamp, mismo patrón que ya usa
  toda la batería de este proyecto) — ninguna acción destructiva, ningún dato preexistente tocado,
  y **ninguna de las 4 columnas nuevas de HU-31 involucrada** (esos 2 scripts no las ejercitan, y
  aunque lo hicieran, esa base no las tiene todavía). Los otros 3 fallaron directo en el primer
  `registro-negocio` (muy probablemente por el rate limiter de ESE proceso ajeno, ya cerca de su
  límite tras los primeros intentos — no una regresión de este cambio). Corregido para el resto de
  esta ronda: cada uno de los 5 scripts se editó **temporalmente** (`const BASE` apuntando a :3002),
  se corrió contra mi cluster efímero propio (los 5 en verde, confirmando que este cambio no rompe
  nada existente), y se revirtió con `git checkout -- <archivo>` antes de seguir — confirmado con
  `git status` que el working tree quedó exactamente igual que antes de esas ediciones. **Ningún
  archivo de `scripts/` quedó modificado por esta ronda** más allá del nuevo
  `test-datos-operativos-negocio.mjs`. Recomendación de seguimiento, no aplicada acá (fuera de
  alcance de esta ronda puntual): sumar el mismo soporte de `BASE_URL` de entorno (con default
  `http://localhost:3000`, sin cambiar el comportamiento actual de nadie) a estos 5 scripts, mismo
  patrón que `test-recuperacion-password.mjs`, para que una futura sesión no repita este mismo
  error de suposición.
- Cluster de Postgres efímero y proceso de servidor local detenidos al cerrar esta ronda (no queda
  ningún proceso propio corriendo en background); el `PGDATA` temporal queda en el scratchpad de la
  sesión, fuera del repositorio, sin ningún efecto sobre el entorno del CEO.
- No se tocó Mobile, ni `negocio_profesional`/`servicio` (ya cerrado en la entrada anterior), ni se
  aplicó `009_negocio_datos_operativos.sql` contra Render — esa aprobación queda, como en todos los
  ciclos anteriores, para el Director General IA/CEO.

## E15 fast-follow (Mobile) — datos operativos del negocio + pausar profesional + desactivar servicio (2026-08-17)

Cierra el lado Mobile de las 2 entradas de Backend inmediatamente anteriores en este mismo archivo
(HU-31 extendido y "pausar/reactivar profesional + eliminar servicio") — 3 pantallas tocadas, sin
tocar Backend/DBA ni ningún entregable ya aprobado de otro rol. Detalle completo en los doc comments
de cada pantalla. Resumen para reutilizar:

- **`configuracion_consultorio_screen.dart` (HU-31) — 4 campos nuevos en los dos modos** (edición
  Administrador / solo lectura Profesional), mismo patrón exacto que los 3 ya existentes
  (`TextEditingController` + `_vacioANull` para mandar `null` explícito al vaciar):
  - **Agrupación deliberada, no al final sin criterio:** `Dirección` se ubicó justo después de
    `Ubicación` (son fáciles de confundir — se agregó además una caption propia distinguiéndolas:
    "la ubicación es una referencia corta... la dirección es el domicilio completo") y `Teléfono`/
    `Horario de atención` después, antes del campo de solo lectura `Rubro de salud` que ya cerraba
    la card. `Logo` se separó en su PROPIA card ("Logo del negocio"), arriba de "Datos del negocio",
    con la vista previa de la imagen justo encima del campo de URL — mejor jerarquía visual que
    mezclarlo como un campo de texto más entre los demás.
  - **`horario_atencion`:** `TextField` multilínea (`minLines: 2, maxLines: 4`,
    `alignLabelWithHint: true`) en vez de una sola línea, como pidió la consigna — texto libre
    potencialmente largo.
  - **`telefono`:** `keyboardType: TextInputType.phone`, sin validación de formato adicional del
    lado del cliente — mismo criterio que ya usan `editar_perfil_screen.dart`/
    `ficha_paciente_screen.dart` para este mismo tipo de campo en esta app (ninguno valida formato,
    el backend tampoco lo hace para ninguna columna de teléfono de este esquema).
  - **`logo_url`:** `keyboardType: TextInputType.url` + validación client-side propia antes de
    "Guardar" (`_errorLogoUrl`, vía `Uri.tryParse` + chequeo de esquema http/https) — feedback
    inmediato sin esperar el viaje de ida y vuelta al 400 que igual devuelve el backend
    (`z.string().url()`, ya documentado por Backend). No valida que la URL sea efectivamente una
    imagen (tampoco lo hace el backend) — eso lo maneja la vista previa con `errorBuilder`.
  - **Vista previa del logo (`_logoPreview`, widget privado nuevo de esta pantalla — se revisó
    `lib/widgets/` primero y no había ningún componente de avatar/imagen reusable):** recuadro
    72×72 con el mismo radio/paleta que el resto de las cards (`AppRadius.card`,
    `colors.neutral.background`/`colors.border`), `Icons.storefront_outlined` como placeholder sin
    URL cargada, `Image.network` con `errorBuilder` (`Icons.broken_image_outlined`) y
    `loadingBuilder` (spinner chico) con URL cargada. En el modo Administrador es REACTIVA
    (`AnimatedBuilder` escuchando `_logoUrlCtrl` directo — un `TextEditingController` ya es
    `Listenable`, no hace falta un `ValueListenableBuilder` aparte) para previsualizar mientras se
    tipea, antes de guardar.
  - Doc comment de la clase actualizado (contrato completo de 7 campos, distinción
    `ubicacion`/`direccion`, criterio de `logo_url`) — ya no dice "3 campos editables".
- **`profesionales_negocio_screen.dart` (fast-follow de HU-02) — Pausar/Reactivar por fila:**
  - `_ProfesionalCard` pasó de `StatelessWidget` a `StatefulWidget` (flag `_procesando` propio,
    deshabilita la acción y muestra un spinner chico mientras el PATCH está en vuelo — sin impacto
    en el caso feliz, donde la card se descarta igual apenas `_refrescar()` reemplaza la lista).
    Acción de fila nueva, `_AccionProfesional` (duplicada localmente, mismo patrón visual que
    `_AccionPaciente` de `gestion_pacientes_screen.dart` — `TextButton.icon` chico —, pero con
    color semántico según la acción: `warning` para "Pausar", `success` para "Reactivar", en vez
    del `primary` fijo de `_AccionPaciente`, mismo criterio que ya separa `WarningButton`/
    `SuccessButton` en el sistema de diseño).
  - `_cambiarEstado` (State) llama `PATCH /negocios/:id/profesionales/:profesionalId` con
    `{ activo }`. **Pausar pide confirmación (`AlertDialog` nativo — no hay helper reusable en
    `lib/widgets/`, se siguió el mismo patrón ya usado en `login_screen.dart`,
    `_pedirPasswordParaVincular`), Reactivar no** — decisión propia siguiendo la sugerencia de la
    consigna, consistente además con que "Cerrar Sesión" en esta misma app tampoco pide
    confirmación pese a ser una acción de alto impacto.
  - 402 (reactivar con el plan gratis en el límite) → `SnackBar` con `SnackBarAction` ("Ver
    Turnario Pro") en vez de un diálogo nuevo — alcanza según la consigna, y evita duplicar el
    patrón de acceso directo a `TurnarioProScreen` que ya usa `_AltaProfesionalSheetState` en este
    mismo archivo.
  - Doc comment del archivo corregido (ya no dice "sin baja/pausa... negocios.ts no expone ningún
    endpoint").
- **`servicios_negocio_screen.dart` (fast-follow de HU-03) — Desactivar por fila:**
  - `lib/api_client.dart` ganó `delete(String path)` (no existía) — mismo patrón exacto que
    `patch`, con `http.delete` y reusando `_decode`.
  - `_ServicioCard` mismo tratamiento que `_ProfesionalCard` (pasa a `StatefulWidget` por
    `_procesando`). Acción nueva: `IconButton` (`Icons.delete_outline`, color `danger`) en vez de
    un `TextButton.icon` con label — a diferencia del roster de profesionales, acá hay una ÚNICA
    acción posible por card (no alterna entre 2 estados), así que el ícono solo ya es inequívoco y
    un label fijo habría sido redundante con el propio diálogo de confirmación.
  - `_eliminarServicio` llama `DELETE /negocios/:id/servicios/:servicioId`, **siempre** con
    confirmación previa (a diferencia de Pausar, acá no hay rama sin confirmar: la acción es más
    seria — sin endpoint de "reactivar" — así que se confirma sin excepción). El texto del diálogo
    aclara explícitamente que los turnos ya agendados contra el servicio NO se tocan (pedido
    explícito de la consigna, para que el administrador entienda que no rompe historial). El botón
    de confirmar es un `TextButton` con `foregroundColor: colors.danger.base` (no un botón sólido)
    — se siguió a propósito la nota ya documentada en `DestructiveButton`
    (`widgets/buttons.dart`: "no usar [el sólido] para eliminar una fila de lista, donde una
    variante outline podría ser más apropiada"), interpretada acá como "sin relleno" dentro de un
    `AlertDialog` nativo.
  - Doc comment del archivo corregido (ya no dice "cada servicio... es de solo lectura").
- **`flutter analyze` corrido localmente:** limpio — único hallazgo, el mismo `info` preexistente
  y ajeno a este cambio de siempre (`prefer_const_constructors`, `dashboard_screen.dart:383`).
- **Verificación de punta a punta, contra un backend local real** (mismo mecanismo que rondas
  anteriores de Backend/DBA en este archivo: `node --env-file=.env dist/src/index.js`,
  `DATABASE_SSL=true`, apuntando al `DATABASE_URL` de Render de `.env`, puerto 3002 para no chocar
  con otro proceso) — se sembró un negocio/administrador/profesional/servicio de prueba nuevos
  (vía `POST /auth/registro-negocio` + los propios endpoints de alta) en vez de reusar negocios de
  rondas anteriores, para no interferir con datos de otras verificaciones:
  - **Interacción real (tap → diálogo → request real → feedback), probada con un widget test
    temporal** (`test/verificacion_e15_temporal_test.dart`, borrado al cerrar la ronda) contra el
    backend local: tocar "Pausar" abre el diálogo con el texto correcto, confirmar dispara
    `sesion.api.patch(...)` real y muestra el `SnackBar` de éxito; tocar el ícono de servicio abre
    el diálogo con el texto de "no se modifican ni se cancelan", confirmar dispara
    `sesion.api.delete(...)` real y muestra su `SnackBar`. Confirmado con `curl` aparte que ambas
    mutaciones efectivamente persistieron en la base. **Limitación de la herramienta, no de la
    app, documentada y no perseguida más allá de lo razonable:** `flutter_test` bloquea HTTP real
    por defecto (hace falta pisar `HttpOverrides.global`, hecho solo en el archivo temporal) y
    `pumpAndSettle` no sirve con un `CircularProgressIndicator` indeterminado en pantalla (nunca
    "asienta" solo); con esos dos ajustes la primera request real y el PATCH/DELETE de la acción
    se observaron sin problema, pero la actualización automática de la lista tras `_refrescar()`
    (una 2da request real encadenada dentro del mismo `runAsync`) no llegó a observarse de forma
    confiable ni con un poll de 60s reales — se confirmó por separado con `curl` (PATCH + GET
    inmediato, ~3s totales) que el backend responde y persiste correctamente, y que `_refrescar()`
    reusa sin cambios el mismo mecanismo (`FutureBuilder`+`setState`) que ya usaba `_abrirAlta()`
    para "Agregar Profesional"/"Agregar Servicio" en estas mismas pantallas — se lo atribuye al
    harness, no se seteó como bloqueante.
  - **Verificación visual en un navegador real** (Chrome headless,
    `--virtual-time-budget`+`--run-all-compositor-stages-before-draw` para dar tiempo a que
    resuelva la request real antes de capturar), sirviendo `flutter build web` de un entrypoint de
    debug temporal (`lib/main_debug_verificacion.dart`, mismo criterio que `main_debug_hu27.dart`
    de una ronda anterior — sesión sembrada con un JWT real vía query param, sin pasar por el login
    interactivo) contra ese mismo backend local: confirmados visualmente los 7 campos del modo
    Administrador (agrupación, multilínea de horario, vista previa del logo cargando la imagen
    real), el modo solo-lectura del Profesional (mismos 7 campos + fallback del logo con una URL
    que no es imagen, ícono roto correcto), la acción "Pausar" (ícono+color warning) en el roster
    de profesionales, y el ícono de desactivar (rojo) en la lista de servicios.
  - Backend local, servidor estático y entrypoint/test temporales dados de baja al cerrar la
    ronda — `git status` confirma que el working tree de Mobile solo tiene los 4 archivos
    reales de este cambio (`api_client.dart`,
    `screens/administrador/profesionales_negocio_screen.dart`,
    `screens/administrador/servicios_negocio_screen.dart`,
    `screens/profesional/configuracion_consultorio_screen.dart`).
- No se tocó `main.dart` ni ningún archivo de configuración de forma permanente, ni Backend/DBA, ni
  se aplicó ninguna migración — alcance 100% Mobile sobre contrato ya cerrado y verificado por
  Backend en las 2 entradas anteriores de este mismo archivo.

## Catálogo fijo de "Rubro" en Mobile — Director General IA (2026-08-17)

Pedido explícito del CEO tras probar la app en vivo: el campo "Rubro" del negocio
(`negocio.rubro`, columna `TEXT` libre, sin `CHECK` ni enum en el backend) generaba datos
inconsistentes al cargarse como texto libre — confirmado contra los negocios reales de Render que
"Estética" y "Estetica" (sin tilde) convivían como si fueran dos rubros distintos, siendo el mismo
con un typo. Se reemplazó el texto libre por un catálogo fijo en las 2 pantallas donde `rubro` es
editable, sin tocar Backend/DBA (sigue siendo `TEXT` libre sin validación de enum del lado del
servidor, a propósito — la restricción es solo de UX en Mobile, para no bloquear negocios ya
cargados con un valor fuera de este catálogo).

- **Catálogo** (`lib/dominio/catalogo_rubros.dart`, constante nueva `catalogoRubros`): Salud,
  Estética, Peluquería y Barbería, Spa y Bienestar, Gimnasio y Entrenamiento, Veterinaria, Legal y
  Contable, Otro (`rubroOtro`, última opción — usada tal cual la lista que dio el CEO, sin
  reformular redacción). Ningún archivo de `lib/` tenía antes una carpeta de "dominio" — se creó
  esta a propósito para datos de negocio puros sin UI ni estado, distintos de `theme/`
  (tokens visuales), `state/` (sesión) y `widgets/` (componentes).
- **Widget nuevo reusable, `CampoRubro`** (`lib/widgets/campo_rubro.dart`, exportado desde
  `lib/widgets/widgets.dart`): `DropdownButtonFormField<String>` (mismo `InputDecoration` que el
  resto de los `TextField` de la app, estilado por el `inputDecorationTheme` global — consistente
  sin necesidad de estilos propios) + `TextField` secundario condicional. Lógica de arranque a
  partir de `valorInicial` (el `rubro` ya cargado, o vacío/`null` en un alta nueva):
  - Coincide EXACTO (sensible a mayúsculas/tildes, a propósito — es la razón de ser del catálogo:
    un valor viejo tipo "Estetica" NUNCA se autocorrige en silencio a "Estética") con una opción
    del catálogo → arranca en esa opción, sin campo secundario.
  - Vacío/`null` (alta nueva sin nada tipeado, o un negocio existente sin `rubro` cargado) →
    arranca SIN selección (con hint "Seleccionar rubro...") en vez de forzar "Otro" como default
    — decisión propia (la consigna solo pedía este comportamiento explícitamente para el alta,
    "usá tu criterio de UX"; se extendió al mismo caso en Configuración de Consultorio por
    consistencia, ya que forzar "Otro" con un campo vacío debajo se leería como dato faltante en
    ambas pantallas por igual, no solo en el alta).
  - Cualquier otro valor no vacío (typo viejo, o cualquier texto libre cargado antes de este
    catálogo) → arranca en "Otro" + campo de texto secundario precargado con ese valor tal cual
    estaba, sin perderlo.
  - Al emitir (`onChanged`, `String?`): la opción elegida tal cual, excepto "Otro", que manda el
    contenido del campo secundario con el mismo criterio "vacío es null" que ya usaba
    `_vacioANull` en ambas pantallas (replicado en `registro_negocio_screen.dart`, que no lo tenía
    para `rubro` porque antes era el único campo de esa pantalla sin ese tratamiento).
- **Integración** en `lib/screens/registro_negocio_screen.dart` (alta pre-auth, HU-00a — rubro
  opcional, `valorInicial: null` así que arranca sin selección por diseño de `CampoRubro`, sin
  caso especial en el caller) y `lib/screens/profesional/configuracion_consultorio_screen.dart`
  (`_vistaEditar`, rol administrador únicamente — `_vistaVer`, de solo lectura para el rol
  profesional, NO cambia: se ajustó a leer del nuevo campo `String? _rubro` en vez de
  `_rubroCtrl.text` — mismo texto mostrado, sin dropdown). En ambas pantallas, `_rubroCtrl`
  (`TextEditingController`) se reemplazó por un campo `String? _rubro` de estado plano, poblado
  por el `onChanged` de `CampoRubro` y usado tal cual en el body del POST/PATCH.
- **`flutter analyze` limpio** — único hallazgo, el mismo `info` preexistente y ajeno a este
  cambio (`prefer_const_constructors`, `dashboard_screen.dart:383`).
- **Verificado de punta a punta contra Render real**, backend local propio en el puerto 3002
  (`DATABASE_SSL=true`, `.env` con el `DATABASE_URL` de Render) — a propósito NO en el puerto 3000
  ni el 8090, que en el momento de esta ronda tenían un backend/servidor estático propios
  corriendo en paralelo para una verificación en vivo del CEO ("Verificacion Visual E15"); no se
  tocaron esos procesos, solo los propios (3002 + un servidor estático propio en 8091, ambos
  dados de baja al cerrar la ronda):
  - **4 widget tests temporales con HTTP real** (`test/verificacion_rubro_temporal_test.dart`,
    borrado al cerrar la ronda — mismo mecanismo ya usado en la ronda anterior de este archivo
    para `test/verificacion_e15_temporal_test.dart`: pisar `HttpOverrides.global`, y esperar con
    `tester.runAsync` en vez de `pumpAndSettle` mientras hay un `CircularProgressIndicator`
    indeterminado en pantalla): (1) alta con tap real sobre el dropdown eligiendo "Salud" del
    catálogo, negocio creado, `rubro` confirmado con un `GET /negocios/:id` aparte; (2) alta
    eligiendo "Otro" + texto libre, mismo `GET` de confirmación; (3) Configuración de Consultorio
    como administrador de un negocio sembrado con `rubro: 'Salud'` — confirmado que arranca
    seleccionado, editado a "Veterinaria" y guardado, confirmado con `GET` aparte; (4) mismo flujo
    con un negocio sembrado con `rubro: 'Estetica'` (sin tilde, el typo real que ya existe en
    Render) — confirmado que arranca en "Otro" con "Estetica" visible en el campo secundario,
    guardado SIN tocar nada (confirma que no se pierde ni se autocorrige), y editado a un texto
    nuevo, ambos guardados confirmados con `GET` aparte. **Hallazgo de la herramienta, no de la
    app, corregido en el propio test:** `RegistroNegocioScreen._registrar()` nunca resetea
    `_enviando` en el camino de éxito (a propósito — la app real navega lejos apenas `Sesion`
    notifica el alta); en un arnés de test sin `_Router` que reaccione a `Sesion`, la pantalla
    queda montada con el spinner del botón girando para siempre, así que esperar con
    `pumpAndSettle`/por-desaparición-del-spinner cuelga — se resolvió esperando por la condición
    de negocio real (`sesion.autenticado`) en esos 2 tests en vez de por el spinner.
  - **Verificación visual en un navegador real** (Chrome headless,
    `--virtual-time-budget`+`--run-all-compositor-stages-before-draw`), sirviendo
    `flutter build web -t lib/main_debug_verificacion_rubro.dart` (entrypoint de debug temporal,
    mismo criterio que `main_debug_verificacion.dart`/`main_debug_hu27.dart` de rondas
    anteriores — nunca se tocó `lib/main.dart` real; este archivo aparte apunta directo al
    backend local propio y renderiza la pantalla pedida por query param, sembrando la sesión con
    un JWT real cuando hace falta, sin pasar por login interactivo) contra ese mismo backend
    local: confirmados visualmente los 3 casos — alta sin selección con el hint "Seleccionar
    rubro...", Configuración de Consultorio con "Salud" ya seleccionado (negocio sembrado con ese
    valor), Configuración de Consultorio con "Otro" seleccionado + "Estetica" visible en el campo
    secundario (negocio sembrado con ese valor).
  - Backend local, servidor estático, entrypoint de debug y test temporales dados de baja/
    borrados al cerrar la ronda — `git status` confirma que el working tree de Mobile solo tiene
    los archivos reales de este cambio (`lib/dominio/catalogo_rubros.dart`,
    `lib/widgets/campo_rubro.dart`, `lib/widgets/widgets.dart`,
    `lib/screens/registro_negocio_screen.dart`,
    `lib/screens/profesional/configuracion_consultorio_screen.dart`), sin interferir con los
    demás archivos ya modificados por otras rondas en paralelo en este mismo working tree
    compartido (Backend/Mobile de HU-31 y E15, ninguno tocado).
- No se tocó Backend ni DBA, ni `es_rubro_salud` (columna totalmente independiente de `rubro`, no
  editable desde ninguna de las 2 pantallas), ni se aplicó ninguna migración.

## HU-01 — Pantalla de registro de cliente (alta por email/contraseña) — Mobile (2026-08-17)

Cerraba el gap más grande que quedaba del lado Cliente: hasta esta ronda, un cliente nuevo solo
podía entrar con el botón "Iniciar sesión con Google" del login (HU-35) — no existía ningún
formulario de alta con email/contraseña para clientes, a diferencia de los negocios (HU-00a,
`registro_negocio_screen.dart`). El backend (`POST /auth/registro-cliente`,
`../backend/src/routes/auth.ts`) ya estaba completo y en producción desde antes de esta ronda; no
se tocó Backend ni DBA.

- **`lib/screens/registro_cliente_screen.dart` (nuevo)** — mismo patrón exacto que
  `RegistroNegocioScreen` (mismo `AppHeader`, mismo manejo del 409, misma validación client-side de
  contraseña ≥8 caracteres antes del viaje de red con el mismo mensaje que el backend, mismo
  `sesion.iniciarSesion(...)` + `Navigator.popUntil((route) => route.isFirst)` al terminar — la
  respuesta de este endpoint tampoco trae nunca `negocios`, mismo motivo que la de negocio), mucho
  más simple: un único formulario/sección ("Tus datos") con 3 campos — Nombre, Email, Contraseña —
  en vez de las 2 secciones separadas de la pantalla de negocio. Header "Crear tu Cuenta" (emoji
  📝, mismo que el de negocio, por ser también una pantalla de alta), botón de footer "Crear
  Cuenta".
- **`lib/screens/login_screen.dart`** — se agregó un segundo link al pie, DESPUÉS del ya existente
  de negocio ("¿Todavía no tenés tu negocio en la app? Registralo"), separado de ese por
  `AppSpacing.md` (12dp, mismo criterio de espaciado "chico entre elementos relacionados" que ya
  usa el resto de la pantalla) sin tocar el `AppSpacing.xl` que separa el botón de Google del
  primer link ni reordenar/modificar ningún otro elemento ya existente arriba (espaciado validado
  en una ronda anterior contra una imagen de referencia del CEO). Texto final: **"¿Sos cliente y
  todavía no tenés cuenta? Registrate"** — se sumó "todavía" al texto sugerido en la consigna para
  que sonara a la misma voz que el link de negocio ("¿Todavía no tenés..."), manteniendo "cliente"
  explícito en la primera palabra para que quede inconfundible con ese otro link (un cliente no
  puede terminar por error en el alta de negocio). Se actualizó también el doc-comment de la clase,
  que hasta ahora documentaba el registro de cliente como gap pendiente.
- **`flutter analyze` limpio** — único hallazgo, el mismo `info` preexistente y ajeno a este cambio
  (`prefer_const_constructors`, `dashboard_screen.dart:383`).
- **Verificado de punta a punta contra Render real**, backend local propio en el puerto 3002
  (`DATABASE_SSL=true`, `.env` con el `DATABASE_URL` de Render, `ENABLE_DEV_ROUTES=true` solo para
  las cabeceras CORS que necesita un cliente web servido desde otro origen — ver `src/app.ts`),
  sin tocar el proceso ajeno que ya estaba corriendo en el puerto 3000:
  - Smoke test directo con `curl` contra `/auth/registro-cliente` (201 alta nueva, 409 email
    duplicado, 400 contraseña corta con el mensaje exacto) antes de tocar Mobile, para confirmar
    el contrato documentado en la consigna.
  - **4 widget tests temporales con HTTP real** (`test/verificacion_registro_cliente_temporal_test.dart`,
    borrado al cerrar la ronda — mismo mecanismo ya usado en rondas anteriores de este archivo:
    pisar `HttpOverrides.global`): login muestra los 2 links y el nuevo navega a
    `RegistroClienteScreen`; contraseña corta valida client-side sin request; alta exitosa termina
    con `Sesion.autenticado`/`rol`/`email` reflejando el JWT real que devolvió Render; email ya
    registrado responde 409 con el mensaje esperado. **2 hallazgos de la herramienta, no de la
    app, documentados para reutilizar en próximas rondas:** (1) `HttpOverrides.global` hay que
    asignarlo dentro de `setUp()` (antes de CADA test), no una sola vez arriba de todo —
    `TestWidgetsFlutterBinding` instala su propio override recién cuando arranca a correr el
    primer test, después de que termina de registrarse toda la suite, y pisa cualquier asignación
    previa (mensaje real visto en la primera corrida: "all HTTP requests will return status code
    400, and no network request will actually be made"); (2) un `tap()` que dispara una request
    real hecho AFUERA de `tester.runAsync`, con una espera real recién DESPUÉS, no alcanza para
    que esa request progrese (queda atada a la zona fake-async en la que nació, confirmado
    reproduciendo el bloqueo y comparando contra la corrección) — hay que envolver el `tap()` y la
    espera JUNTOS dentro del mismo `runAsync`. Por el mismo motivo de fondo se evitó pumpear hasta
    `ClienteShell` dentro del test de alta exitosa (`BuscarNegociosScreen` dispara su propio fetch
    real que queda con un timer pendiente para siempre y el binding rechaza cerrar el test con un
    timer real pendiente) — esa confirmación puntual se hizo aparte, con el navegador real.
  - **Verificación visual e interactiva en un navegador real** (Chrome headless vía Puppeteer,
    instalado aparte en el directorio de scratchpad — no se agregó como dependencia del proyecto;
    viewport 390x844, un tamaño de teléfono realista: el canvas por default de `flutter_test`,
    800x600, no alcanza a mostrar todo el login sin overflow, artefacto del harness sin relación
    con ningún problema real de la pantalla), sirviendo `flutter build web` con un override
    temporal de `ApiClient.baseUrl` en `main.dart` (revertido al terminar, `git diff` confirmado en
    cero) contra ese mismo backend local: el login se ve exactamente igual que antes arriba del
    nuevo link (sin overflow, con margen de sobra debajo en un viewport realista), los 2 links
    quedan uno debajo del otro con espaciado proporcionado; clic real sobre el link nuevo navega a
    `RegistroClienteScreen`; formulario completado y enviado con clics y tipeo reales termina en
    `ClienteShell` (pestaña "Buscar", listando negocios reales de la base de Render); reintentar
    con un email ya registrado muestra el banner "Ya existe una cuenta registrada con ese email.
    Si es tuya, iniciá sesión en vez de registrarte de nuevo."; contraseña corta muestra "La
    contraseña debe tener al menos 8 caracteres" sin viaje de red.
  - Backend local y servidor estático dados de baja, build web y test temporal borrados al cerrar
    la ronda — `git status` confirma que el working tree de Mobile solo tiene los 2 archivos reales
    de este cambio (`lib/screens/registro_cliente_screen.dart` nuevo,
    `lib/screens/login_screen.dart` modificado).
- No se tocó Backend ni DBA (el endpoint ya estaba completo y en producción) ni el resto de
  `login_screen.dart` más allá de agregar el link nuevo al final.

## Notificaciones y Configuración del lado Cliente — Mobile (2026-08-18)

Cerraba los 2 últimos tabs de `ClienteShell` que seguían como `ProximamenteScreen` desde que se
construyó ese shell: Notificaciones y Configuración. Ninguno de los dos necesitó cambios de
Backend ni DBA — el backend de notificaciones (`routes/notificaciones.ts`) ya es genérico por rol
(`requireAuth()` sin restricción, en los 5 endpoints) y `usuario.ts` documenta él mismo
`/usuario/perfil`/`/usuario/privacidad` como "transversal a cualquier rol autenticado
(cliente/profesional/administrador)".

- **Notificaciones: reusa `NotificacionesScreen` (`screens/profesional/notificaciones_screen.dart`)
  TAL CUAL**, import cross-carpeta — mismo criterio que ya usa esta app para
  `ConfiguracionConsultorioScreen` (compartida entre Profesional y Administrador,
  `administrador_shell.dart`). Confirmado leyendo el archivo completo: no tiene ninguna referencia
  a rol adentro, solo consume los 3 endpoints genéricos de arriba — cero riesgo de mostrarle a un
  cliente algo pensado para Profesional.
- **`lib/screens/cliente/configuracion_cliente_screen.dart` (nuevo)** — mismo patrón visual exacto
  que `ConfiguracionScreen` (Profesional): `_PerfilHeader`/`_MenuSection`/`_MenuTile`/
  `_SelectorTema` duplicados en el archivo nuevo en vez de compartidos, mismo criterio que ya usa
  el resto de la app para estas pantallas de menú (esos 2 widgets ya estaban triplicados entre
  `profesional/configuracion_screen.dart` y `administrador/administrador_shell.dart` antes de esta
  ronda). Diferencias intencionales contra la versión Profesional, todas documentadas en el
  doc-comment de la clase:
  - Sin los callbacks `onIrAHorarios`/`onIrAPacientes` (no hay pestañas equivalentes en
    `ClienteShell`) ni las secciones "Panel Profesional" y "Pagos y Señas" (ningún cliente
    gestiona un negocio propio).
  - **Se sacó el ítem "Turnario Pro · Suscripción" por completo (ni siquiera como
    `ProximamenteScreen`)** — a diferencia de "Idioma", que sí se mantuvo como placeholder por ser
    un ajuste genérico de app que algún día va a aplicar a cualquier rol. Turnario Pro es,
    estructuralmente, la suscripción de UN NEGOCIO (`GET/POST /negocios/:id/plan|suscripcion`,
    `requireAuth('administrador', 'profesional')`, ver `administrador/turnario_pro_screen.dart`;
    del lado Administrador vive en la sección "Mi negocio", no en "Cuenta") atada a `negocio_id` —
    una sesión Cliente nunca tiene `negocio_id` (`Sesion.negocioId` solo se resuelve para
    profesional/administrador). Mostrarlo igual como "Próximamente" hubiera prometido una función
    que esta cuenta nunca va a poder usar.
  - Header (`_PerfilHeader`) con "Cliente" fijo en vez de "Profesional", SIN el `FutureBuilder` de
    rubro de negocio (`GET /negocios` + buscar el propio `negocioId`) — por eso alcanza con
    `StatelessWidget`, a diferencia del `StatefulWidget` que sí necesita la versión Profesional.
- **Hallazgo al confirmar `EditarPerfilScreen`/`PrivacidadScreen`/`AyudaSoporteScreen`/
  `AcercaDeScreen` (pedido explícito de la consigna, no asumir sin revisar):** las primeras 2 son
  100% genéricas (reusadas tal cual, `editar_perfil_screen.dart`/`privacidad_screen.dart`, mismo
  import cross-carpeta) pero **`AyudaSoporteScreen` y `AcercaDeScreen` sí tenían contenido
  hardcodeado específico de Profesional** pese a no tener ninguna rama de lógica por rol:
  - `AyudaSoporteScreen`: 3 de sus 4 FAQ apuntaban a ítems que solo existen en el menú de
    Profesional ("Configurar Disponibilidad", "Configuración de Pagos" con activación de seña,
    "Reportes y Estadísticas... dentro de Panel Profesional") — nada de eso existe en el menú de
    Cliente de arriba.
  - `AcercaDeScreen`: la bajada fija decía "Gestioná turnos, **pacientes** y tu **agenda
    profesional**..." — un cliente no gestiona pacientes ni una agenda propia, reserva turnos con
    profesionales de terceros.
  - **Resuelto creando copias propias** (`ayuda_soporte_cliente_screen.dart`/
    `acerca_de_cliente_screen.dart`, mismo armado visual — `_sectionCard`/`_FaqItem` duplicados
    igual que el resto de esta app) en vez de (a) reusar tal cual con contenido incorrecto para el
    rol, o (b) meterle una rama de rol adentro de los archivos de Profesional ya aprobados: se
    prefirió NO tocar ningún archivo de `profesional/` para este hallazgo, cero riesgo de
    regresión sobre pantallas ya entregadas. Las 4 FAQ nuevas de Cliente se verificaron contra el
    código real (`buscar_negocios_screen.dart`/`mis_turnos_screen.dart`) para no inventar
    funcionalidad: reservar turno (tab Buscar), editar perfil, cancelar/reprogramar turno (botones
    reales de "Mis Turnos"), ver estado de turnos. La bajada de "Acerca de" pasó a "Reservá turnos
    con tus profesionales de confianza desde un solo lugar."; nombre de app/ícono/versión
    (`0.1.0`, igual que `pubspec.yaml`) quedaron iguales.
  - "Notificaciones" (ítem de Cuenta) SÍ apunta directo a `ConfiguracionNotificacionesScreen`
    (`profesional/configuracion_notificaciones_screen.dart`) tal cual, sin copia — mismo motivo que
    `NotificacionesScreen`: 100% genérica, sin contenido de rol adentro.
- **`cliente_shell.dart`**: los 2 `ProximamenteScreen` se reemplazaron por `NotificacionesScreen()`/
  `ConfiguracionClienteScreen()` en la lista `screens`, y se reescribió el doc-comment de la clase
  (ya no era cierto que ambos tabs quedaban como placeholder).
- **`flutter analyze` limpio** — único hallazgo, el mismo `info` preexistente y ajeno a este cambio
  (`prefer_const_constructors`, `dashboard_screen.dart:383`).
- **Verificado de punta a punta contra Render real**, backend local propio en el puerto 3002
  (`DATABASE_SSL=true`, `ENABLE_DEV_ROUTES=true` para las cabeceras CORS que necesita un cliente
  web servido desde otro origen, `DATABASE_URL`/`JWT_SECRET` del `.env` ya existente en
  `05-codigo/backend/`), sin tocar ningún proceso ajeno (nada más estaba escuchando en 3002/8092 al
  arrancar):
  - Smoke test con `curl` contra `POST /auth/registro-cliente` (cliente nuevo) y contra
    `GET /notificaciones`, `GET /usuario/perfil`, `GET /usuario/privacidad`,
    `GET /notificaciones/configuracion` con el token resultante — los 4 devuelven 200 con el shape
    esperado para rol `cliente` antes de tocar el navegador.
  - **Verificación visual e interactiva en un navegador real** (Chrome headless vía Puppeteer,
    instalado aparte en el directorio de scratchpad — no se agregó como dependencia del proyecto;
    viewport 390x844), sirviendo `flutter build web` con un override temporal de
    `ApiClient.baseUrl` en `main.dart` (revertido al terminar, `git diff` confirmado en cero)
    contra ese backend local: login con el cliente recién registrado; tab Notificaciones carga
    ("Todavía no tenés notificaciones.", sin error, para una cuenta nueva sin notificaciones); el
    ícono ⚙ de esa pantalla Y el ítem "Notificaciones" del menú de Configuración abren la misma
    `ConfiguracionNotificacionesScreen` con datos reales (Push/Email/WhatsApp, Citas y
    recordatorios, Promociones, Sonido/Vibración); tab Configuración muestra el header "Cliente"
    (sin rubro), las secciones "Cuenta"/"Aplicación" completas y SIN "Panel Profesional" ni "Pagos
    y Señas" ni "Turnario Pro · Suscripción"; "Editar Perfil" (nombre/email de solo lectura/
    teléfono reales), "Privacidad y Seguridad" (radio + 2 switches reales) y las 2 pantallas
    nuevas "Ayuda y Soporte"/"Acerca de" (contenido adaptado a Cliente, confirmado en pantalla)
    navegan sin errores; el selector de Tema cambia Claro/Oscuro al instante; "Cerrar Sesión"
    vuelve al login limpio.
  - Backend local, servidor estático y Chrome headless dados de baja, `build/web` borrado
    (gitignorado igual) al cerrar la ronda — `git status` confirma que el working tree de Mobile
    solo tiene los archivos reales de este cambio (`lib/screens/cliente/cliente_shell.dart`
    modificado; `configuracion_cliente_screen.dart`, `ayuda_soporte_cliente_screen.dart`,
    `acerca_de_cliente_screen.dart` nuevos).
- No se tocó Backend ni DBA, ni ningún archivo de `screens/profesional/` (`configuracion_screen.dart`
  incluido, instrucción explícita — pero tampoco `notificaciones_screen.dart`,
  `editar_perfil_screen.dart`, `privacidad_screen.dart`, `configuracion_notificaciones_screen.dart`,
  `ayuda_soporte_screen.dart` ni `acerca_de_screen.dart`).

## Notificaciones por email a ambas partes (Resend) — Backend (2026-08-18, PR #24)

Pedido explícito del CEO: hasta esta ronda, cada uno de los 5 eventos que generan una
notificación (reservar, cancelar, reprogramar, turno manual, recordatorio automático)
avisaba a UNA sola parte — siempre la contraparte de quien actuó, nunca a ambas (decisión
original de DBA, "es la bandeja del PROFESIONAL", ver 001_init.sql). Se cierran 2 gaps a la
vez: (a) notificar a AMBAS partes en los 5 productores, y (b) reenviar cada notificación por
correo real vía Resend, no solo dejarla en la bandeja in-app.

- `dominio/notificaciones.ts`: `armarAsuntoNotificacion(tipo)` (mapeo fijo, no depende de
  `destinatarioEsCliente` a diferencia del cuerpo) y `obtenerDatosNotificacionTurno(db, turnoId)`
  (nombre+email de ambas partes de un turno, sin RLS especial — mismo criterio que el primer
  SELECT de `POST /turnos`).
- `integraciones/email.ts`: `EmailProvider` generalizado con `enviarNotificacion(destinatarioEmail,
  asunto, cuerpo)` (antes solo tenía `enviarRecuperacionPassword`, HU-37). `ResendEmailProvider`
  nuevo, API REST directa vía `fetch` (sin agregar el paquete npm `resend`) — selección
  condicional al final del archivo según `RESEND_API_KEY` esté seteada o no, mismo patrón que
  `pagoProvider`/`MP_ACCESS_TOKEN`. Remitente por default el dominio de pruebas de Resend
  (`onboarding@resend.dev`, limitado a la cuenta que lo creó hasta que el CEO verifique un
  dominio propio vía `RESEND_FROM_EMAIL`). `RESEND_API_KEY`/`RESEND_FROM_EMAIL` declaradas en
  `render.yaml` (`sync: false`, sin valor) y documentadas en `.env.example` — ninguna cuenta de
  Resend creada, ninguna credencial real cargada.
- `routes/turnos.ts` (x3: POST /, PATCH /:id/cancelar, PATCH /:id/reprogramar) y
  `routes/profesionales.ts` (POST /:id/turnos, HU-23): segundo `INSERT INTO notificacion` por
  evento (el destinatario que faltaba) + disparo del email a ambas partes.
- `jobs/recordarTurnosProximos.ts`: el query de candidatos ahora trae también `cliente_id`: el
  loop impersona y hace INSERT una vez por cada uno de los 2 destinatarios (mismo `WHERE NOT
  EXISTS`, sin tocar su SQL — cada impersonación por RLS solo ve sus propias filas). Solo dispara
  email para los que realmente insertaron fila nueva en esa corrida (evita reenviar el mismo
  recordatorio en cada tick del intervalo).
- Diseño: el envío de email es best-effort y corre SIEMPRE fuera de la transacción de DB que
  insertó la notificación — un email que falla o tarda no puede demorar ni arriesgar el
  COMMIT/ROLLBACK de crear/cancelar/reprogramar un turno. `enviarRecuperacionPassword` (HU-37)
  no se tocó.

### Incidente de CI: fallo intermitente en `test-rn8-ventana-cancelacion.mjs`, no reproducible en local

El PR #23 (verificación previa) mergeó limpio, pero el PR #24 falló 2/2 veces en el mismo punto
del CI (`Fase 2/2 - correr test-rn8-ventana-cancelacion`, GitHub Actions): al crear el 3er turno
de la corrida (`turno lejano #1`), el log del servidor se cortaba limpiamente sin ningún stack
trace ni excepción — compatible con un timeout/cuelgue de esa request puntual, no con un crash
del proceso completo (los otros jobs del mismo run seguían sirviendo).

Se investigó a fondo antes de tocar código (mismo criterio que toda esta sesión: nunca asumir
sin verificar):
- El log de `server-fase1.log` confirmaba que TODOS los otros 9 scripts de Fase 1 (con volúmenes
  similares o mayores de turnos, incluidos varios seguidos con las 2 notificaciones dobles ya
  funcionando) pasaron sin ningún problema — descarta un bug sistemático de "crashea con
  volumen".
- Reproducido 3 veces en local sin lograr fallar NUNCA: (1) contra la base real de Render (con
  meses de datos acumulados) vía `ts-node-dev --respawn`; (2) mismo backend, pero forzando
  explícitamente Node 22.18.0 (descargado portable, sin nvm disponible) + `ts-node` PLANO sin
  `--respawn` — replicando exactamente el comando y la versión de Node que usa
  `turnos-backend-ci.yml` (`NODE_VERSION: "22"`). Las 3 corridas: 100% verde, incluido el turno
  lejano que fallaba en CI. Esto descartó tanto "volumen de datos" como "diferencia de versión
  de Node" como causa.
- El propio `test-rn8-ventana-cancelacion.mjs` ya tiene historial de flakiness documentado en
  este proyecto (Task #35, causa distinta y ya resuelta entonces — franja horaria de
  `dias=1`).
- Diferencias que quedaron sin descartar por no ser reproducibles sin un esfuerzo
  desproporcionado: Postgres EFÍMERO recién migrado del runner (vs. Render gestionado) +
  recursos de CPU/IO compartidos y limitados del runner + el estado EXACTO que dejan los 9
  scripts de Fase 1 antes de RN8 — cualquiera de estos, combinado con que cada `POST /turnos`
  ahora hace más trabajo asíncrono antes de responder (2 INSERT + 1 SELECT post-transacción + el
  envío de 2 emails, todo esperado con `await` en la versión original de este PR), es la
  hipótesis más plausible para un timing/race condition que no se manifiesta en una máquina más
  rápida con menos contención.
- **Decisión del CEO** (sin invertir más tiempo en aislar la causa exacta en el runner): hacer el
  envío de notificaciones (bandeja + email) NO bloqueante — se saca el `await` de los 4 call
  sites HTTP (`void enviarEmailsNotificacionTurno(...)`, con comentario explícito de que es
  intencional, no un `await` olvidado) para que ninguna respuesta HTTP de reservar/cancelar/
  reprogramar/turno-manual tenga que esperar a que terminen 2 emails que de todos modos ya nunca
  pueden hacerla fallar (mismo try/catch interno de antes, sin cambios). El loop de
  `jobs/recordarTurnosProximos.ts` NO se tocó (no bloquea ninguna respuesta HTTP, no era la causa
  del incidente).
- No se identificó la causa raíz exacta del timing en el runner — queda documentado acá por si
  reaparece en un contexto distinto (mismo criterio que Task #103, Render/Mercado Pago: escalado
  y anotado, no reintentado desde cero sin evidencia nueva).

## Dominio propio verificado en Resend + envío real de emails (2026-08-19)

PR #24 mergeado a `main` (commit `cf72fa1`) y desplegado a Render. El CEO cargó
`RESEND_API_KEY` en el entorno de Render (con un error de tipeo inicial —`RESEND_API` en vez de
`RESEND_API_KEY`— detectado comparando el ancho del campo contra las demás variables y corregido
en un segundo intento). Con la key sola, Resend solo permite entregar al email de la propia
cuenta (`matiasayago@gmail.com`) — confirmado con un turno de prueba real contra producción: los
2 intentos de notificación (cliente con alias `+resendtest`, profesional con email @test.com)
fueron rechazados por Resend con 403 `validation_error`, mensaje que sin embargo confirmó que la
key autentica correctamente (no es un 401) y reveló el email exacto de la cuenta.

Para desbloquear el envío a clientes/profesionales reales, se verificó un dominio propio:
`turnarioapp.com.ar` (ya era propiedad del CEO, registrado en NIC Argentina).

- **NIC Argentina no ofrece gestión de Zona DNS propia** para dominios `.com.ar` no delegados —
  el panel "Trámites a Distancia" (TAD) solo permite Transferir o Delegar el dominio, sin
  registros TXT/MX personalizables. Para cargar los registros que pide Resend (DKIM, MX+SPF,
  DMARC) hubo que delegar el dominio a un proveedor de DNS externo.
- **Proveedor elegido: Cloudflare** (plan Free) — estándar de la industria, gratis, sin downside
  para este caso de uso. El dominio se agregó en Cloudflare, se cargaron los 4 registros DNS que
  pide Resend, y se delegó el dominio desde NIC.ar a los 2 nameservers de Cloudflare
  (`aria.ns.cloudflare.com`, `dexter.ns.cloudflare.com`).
- **El primer intento de delegación en NIC.ar no tomó** — el CEO confirmó "ya lo hice" pero la
  columna "Delegado" seguía en "NO" y una consulta NS directa contra los servidores autoritativos
  del TLD `.ar` (`e.dns.ar`, no un resolver cacheado) seguía devolviendo NXDOMAIN. Reintentar el
  mismo trámite en NIC.ar sí lo aplicó (columna pasó a "SI", propagación visible en `.ar` unos
  segundos después). Lección: en NIC.ar, verificar el resultado del trámite de delegación en la
  lista de "Mis dominios" tras guardarlo — no asumir que "lo hice" implica que se guardó.
- **Verificación en Resend**: una vez propagado el DNS, Resend detectó los registros y verificó
  el dominio en un par de minutos (estado `Verified`, no las "unas horas" que advierte el mensaje
  genérico — ese mensaje es conservador para el caso de DNS todavía no propagado).
- `RESEND_FROM_EMAIL` configurado en Render como `Turnario <notificaciones@turnarioapp.com.ar>`.
  Cargado por el Director General IA directamente (no es una credencial sensible, a diferencia
  de `RESEND_API_KEY`).
- **Verificación end-to-end final**: turno de prueba nuevo contra producción → en el dashboard de
  Resend (`/emails`), el envío al cliente figura `delivered` y el envío al profesional (dirección
  `@test.com` ficticia) figura `sent` (aceptado, sin el 403 de antes) → el CEO confirmó
  recepción real en su bandeja de Gmail, remitente y contenido correctos. Sistema de
  notificaciones por email confirmado funcionando de punta a punta en producción real.

### Nota técnica: bug de compositing en el Browser pane durante esta sesión

Durante gran parte de esta ronda, el Browser pane dejó de compositar frames visualmente
(`screenshot` fallaba con timeout, y los `ref` de `read_page` reportaban bounding rects en
`(0,0)` aunque el DOM real seguía accesible). `read_page`, `get_page_text` y `javascript_tool`
siguieron funcionando con normalidad durante todo el incidente. Workaround aplicado en Resend y
Render: en vez de `computer.click()` por coordenadas, usar `javascript_tool` para setear valores
de inputs controlados por React vía el native property setter (`Object.getOwnPropertyDescriptor
(HTMLInputElement.prototype, 'value').set` + `dispatchEvent(new Event('input'/'change'))`) y
disparar el submit con `form.requestSubmit()` cuando el botón está dentro de un `<form>`, o con
`button.click()` cuando no lo está (funciona pese al bug, porque no depende de la geometría del
elemento). Mismo patrón ya documentado en esta sesión como alternativa a Puppeteer para cuando el
Browser pane falla por compositing — agregado acá el detalle concreto de qué hacer con
formularios de apps React/Next modernas (Resend, Render) en vez de sitios estáticos simples.

## Notificaciones: agregar fecha completa y negocio al texto (2026-08-19)

Pedido explícito del CEO tras revisar en Gmail el email real de confirmación de turno de la
ronda anterior: el texto solo decía con qué profesional y a qué HORA (ej. "Tu turno con X de las
11:00 fue confirmado") — nunca la fecha (día/mes) ni el negocio/consultorio.

- `dominio/notificaciones.ts`: nueva `formatearFechaHoraLocal` (día de semana + día + mes vía
  `Intl.DateTimeFormat('es-AR', ...)`, nativo de Node — sin agregar date-fns/luxon/moment como
  dependencia nueva) reemplaza a `formatearHoraLocal` en los 8 casos de `armarMensajeNotificacion`
  (2 perspectivas × 4 tipos). `DatosMensajeNotificacion`/`DatosNotificacionTurno` ganan
  `negocioNombre: string`. `obtenerDatosNotificacionTurno` amplía su SQL con
  `JOIN negocio ng ON ng.id = t.negocio_id` (`turno.negocio_id` es columna propia, `NOT NULL` —
  no hace falta pasar por el N:M profesional↔negocio; `negocio` no tiene RLS, INNER JOIN seguro).
- 4 call sites actualizados para pasar `negocioNombre`: `routes/turnos.ts`,
  `routes/profesionales.ts`, `routes/notificaciones.ts` (bandeja in-app — su propio SELECT
  también ganó el JOIN a `negocio`, alias `neg` para no chocar con el alias `n` de la tabla
  `notificacion`), y `jobs/recordarTurnosProximos.ts` (este último NO necesitó ampliar su SELECT
  de "candidatos" — ese solo alimenta el INSERT de la bandeja sin columnas de texto; el cuerpo del
  email de recordatorio ya se arma con una lectura propia de `obtenerDatosNotificacionTurno` por
  turno, así que `negocioNombre` le llegó gratis con el cambio del paso anterior).
- Ejemplo real de texto resultante: "Tu turno con María Pérez en Clínica Vida el martes 25 de
  agosto a las 11:00 fue confirmado".

## Selector real de servicio en Gestión de Horarios + "Servicios que brindo" en Editar Perfil (2026-08-19)

Durante una demo en vivo del rol Profesional (pedida por el CEO: "tres demos, una de cada
perfil"), se encontró que "Gestión de Horarios" pedía pegar a mano el UUID del servicio en un
`TextField` de texto libre — limitación ya documentada como "simplificación temporal" desde que
se creó esa pantalla, nunca resuelta. El CEO pidió sacarla, y de paso poder gestionar "qué
servicio brindo" desde "Editar Perfil".

No hizo falta backend nuevo — `GET /profesionales/:id/servicios` (servicios ya asociados),
`GET /negocios/:id/servicios` (catálogo del negocio) y `POST /profesionales/:id/servicios` ya
existían y estaban probados en otros flujos.

- `gestion_horarios_screen.dart`: el `TextField` se reemplaza por un selector resuelto contra
  `GET /profesionales/:id/servicios` en `initState` — 0 servicios: guardado deshabilitado con un
  mensaje que manda a "Editar Perfil"; 1 servicio: autoseleccionado, sin mostrar ningún control
  ("Horarios para: X"); 2+: chips de selección (mismo patrón `_ToggleChip` que "Replicar en
  semanas/meses" en la misma pantalla).
- `editar_perfil_screen.dart`: sección nueva "Servicios que brindo", condicionada a
  `Rol.profesional` (esta pantalla también la abren Cliente y Administrador, para quienes la
  sección no aplica — mismo criterio que `configuracion_consultorio_screen.dart`). Lista el
  catálogo completo del negocio; cada servicio ya asociado queda fijo ("Ya asociado", sin
  control — no existe ningún DELETE en `profesionales.ts` para desasociar); los no asociados
  tienen un botón "Agregar" que dispara el POST.
- **Verificación end-to-end real bloqueada por CORS de producción** (`ENABLE_DEV_ROUTES=false` en
  Render, a propósito — ver el comentario en `app.ts`: CORS solo se habilita en ese modo dev, así
  que servir el build de Flutter Web desde `localhost:8092` y loguear contra
  `https://turnos-profesionales-backend.onrender.com` directo falla con
  "blocked by CORS policy", no es un bug). Resuelto sin tocar producción: el propio
  `static-server.js` del scratchpad (el que sirve `build/web`) se amplió con un proxy transparente
  — cualquier request a un prefijo de ruta conocido de la API (`/auth`, `/turnos`, `/negocios`,
  etc.) se reenvía server-to-server a Render en vez de servirse como archivo estático, así el
  navegador ve un único origen (`localhost:8092`) para todo, sin preflight. `ApiClient.baseUrl` se
  overrideó temporalmente a `http://localhost:8092` en `main.dart` (mismo patrón ya usado y
  revertido en rondas anteriores, ver Task #47) — revertido de nuevo antes de commitear.
- Confirmado visualmente en producción real, logueado como el profesional de la demo: Gestión de
  Horarios muestra "🧰 Servicio — Horarios para: Consulta General" (sin campo de UUID) y el
  guardado de horarios funcionó ("Guardado: 10 bloque(s) de horario..."); Editar Perfil muestra
  "Servicios que brindo — Consulta General, 30 min · $8000, ✅ Ya asociado".

## Bottom nav persistente en Cliente — Navigator anidado por pestaña — Arquitecto (2026-08-22)

Task #115 (CEO): "los botones de navegacion deben estar visibles en todas las pantallas". Diseño
completo, diagramas y pseudocódigo en
`03-arquitectura/bottom-nav-persistente-cliente.md` — **no se tocó código en este ciclo**, es
diseño puro a cargo de Arquitecto. Resumen para reutilizar:

- **Causa raíz verificada (no solo el síntoma reportado):** `ClienteShell` pone la bottom nav en
  el `Scaffold` que envuelve su `IndexedStack`, pero todo `Navigator.push` de este código apila
  sobre el **único** Navigator raíz de la app (`MaterialApp.home: _Router()`) — por encima de ese
  mismo `Scaffold`, no dentro de él. Por grep sistemático sobre `screens/cliente/` se confirmó que
  son **13 pantallas afectadas en 4 puntos de entrada**, no solo los 2 flujos que mencionaba el
  encargo: (1) el flujo de reserva de 4 pantallas (Buscar), (2) Reprogramar Turno (Mis Turnos), (3)
  el ícono ⚙ de `NotificacionesScreen` que abre `ConfiguracionNotificacionesScreen` (pestaña
  Notificaciones — hallazgo nuevo, no estaba en el encargo original), y (4) las 6 pantallas de
  Configuración.
- **Recomendación: Navigator anidado por pestaña** (un `Navigator` propio con
  `GlobalKey<NavigatorState>` dentro de cada entrada del `IndexedStack`, más `NavigatorPopHandler`
  para el botón atrás del sistema) **sobre `go_router`/`StatefulShellRoute`** — ambas opciones
  evaluadas con criterio explícito, no solo la primera aceptable. La recomendada usa únicamente
  SDK de Flutter (sin dependencia nueva a `pubspec.yaml`), dos archivos tocados
  (`cliente_shell.dart` + `confirmar_turno_screen.dart`), y las 13 pantallas hoja siguen
  funcionando sin ningún cambio (`Navigator.of(context)` ya usado en todas resuelve solo al
  ancestro más cercano, que pasa a ser el anidado de su pestaña). `go_router` es la solución de
  fondo a mediano plazo, pero implica reescribir la navegación de Cliente **y** Profesional **y**
  Administrador (30+ archivos, mismo patrón de fondo confirmado por grep en los 3 shells) más una
  dependencia nueva — queda fuera de este ciclo, marcada como pendiente de validación de CTO IA
  antes de iniciarse (regla de gobierno: nueva tecnología requiere ese paso), no autorizada ni
  descartada por este documento.
- **Pieza nueva que Flutter no resuelve solo:** cambiar de pestaña desde una pantalla empujada 4
  niveles adentro de OTRA pestaña (el caso real: `ConfirmarTurnoScreen`, al confirmar con éxito,
  hoy salta a "Mis Turnos" con un hack — `pushAndRemoveUntil` + una segunda instancia de
  `MisTurnosScreen` — que **también** pierde la bottom nav hoy y quedaría roto si solo se
  "envuelve" el resto sin migrarlo). Se diseñó `ClienteTabController`, expuesto vía `Provider`
  (paquete ya usado en el proyecto para `Sesion`/`ThemeController`, sin dependencia nueva) desde
  `ClienteShell` a todo su subárbol, con un único método de intención (`irAMisTurnos()`) para no
  filtrar el índice de pestaña fuera de `cliente_shell.dart`.
- **Hallazgo adicional, no pedido explícitamente, encontrado al auditar el mismo archivo que ya
  había que tocar:** el diálogo "Seña requerida" de `ConfirmarTurnoScreen` es el único `showDialog`
  de las 7 pantallas de esta app que lo usan que NO sigue el patrón ya establecido en las otras 6
  (`login_screen.dart` y 5 más — todas nombran el `BuildContext` propio del diálogo, `builder:
  (dialogContext) => ...`, y hacen `Navigator.of(dialogContext).pop(...)`); esta pantalla descarta
  ese contexto (`builder: (_) => ...`) y reusa el `context` exterior de la pantalla para el pop del
  botón "Entendido". Funciona hoy solo porque hay un único Navigator en toda la app — con Navigator
  anidado, el pop apuntaría a la pestaña "Buscar" en vez de al diálogo (que vive en el Navigator
  raíz por diseño, `showDialog` usa `useRootNavigator: true` por default, correcto para un modal).
  Fix de una línea, incluido en el contrato de archivos de este mismo diseño (no abre un archivo
  nuevo).
- **Riesgo más importante para QA, no cosmético:** sin `NavigatorPopHandler` envolviendo cada
  Navigator anidado, el botón/gesto atrás **del sistema operativo** (Android) cerraría/minimizaría
  la app en vez de retroceder un paso apenas la pestaña activa tuviera algo pusheado — distinto del
  botón "volver" del `AppHeader` (`Navigator.maybePop(context)`, ya funciona y sigue funcionando
  sin cambios). QA debe probar explícitamente el botón/gesto atrás nativo, no solo el de la UI.
- **Confirmado por grep, fuera de alcance de Task #115 (acotada a Cliente por el CEO) pero
  dejado explícito como riesgo/fast-follow:** `ProfesionalShell` y `AdministradorShell` tienen el
  mismo bug de fondo (`administrador_shell.dart`, `pacientes_negocio_screen.dart`,
  `profesionales_negocio_screen.dart`, `agenda_screen.dart`, `configuracion_screen.dart`,
  `dashboard_screen.dart`, `gestion_pacientes_screen.dart`, `mis_clientes_screen.dart`,
  `notificaciones_screen.dart` todos empujan pantallas fuera de su propio shell) — mismo patrón de
  solución aplicaría 1:1 si se decide replicarlo.
- **No verificado con el SDK de Flutter real** (mismo caveat de siempre en este proyecto — este
  entorno no tiene Flutter/Dart instalado): la firma exacta de `NavigatorPopHandler` se citó desde
  conocimiento de entrenamiento, no contra la versión `stable` real que usa `turnos-mobile-ci.yml`
  — Mobile debe confirmarla al implementar. Ningún archivo `.dart` fue modificado en este ciclo.
- Reutilizable para futuros proyectos de la Factory: "Navigator anidado por pestaña +
  `NavigatorPopHandler` + controller expuesto vía Provider para saltos cross-tab desde pantallas
  profundas" es candidato a `knowledge-base/patrones-arquitectonicos/` una vez implementado y
  probado — no creado todavía (no hay código real corrido que lo respalde).

## GOOGLE_CLIENT_ID en Render — confirmado ya cargado y funcionando, no era un pendiente real — DevOps (2026-08-22)

Task #116 (Director General IA): "cargar GOOGLE_CLIENT_ID en Render", con la premisa de que la
variable todavía no estaba cargada (`../../../proyectos/turnos-profesionales/08-despliegue/google-oauth.md`,
§4.3, quedaba con ese paso "a confirmar"). **Antes de repetir el paso del dashboard, se verificó el
estado real primero — la premisa del ticket estaba desactualizada:** la variable ya estaba cargada
y funcionando desde una sesión anterior, sin fecha exacta documentada (`project_turnos_profesionales_infra.md`,
memoria de usuario, ya lo mencionaba de paso al narrar el bug no relacionado de
`MP_ACCESS_TOKEN`/`MP_WEBHOOK_SECRET` del 2026-08-17, sin que ningún ciclo de DevOps lo hubiera
registrado en `memory/` del repo hasta ahora).

- **Verificación propia contra `https://turnos-profesionales-backend.onrender.com`:**
  `POST /auth/google` con `{"id_token":"test"}` (nombre de campo real, `src/routes/auth.ts` línea
  266 — el ticket sugería `idToken`, camelCase, que da 400 por campo faltante, no por lo que
  realmente hace falta probar) → **401 "Token de Google inválido"**. Ese 401 (no 503) es prueba
  directa de que `process.env.GOOGLE_CLIENT_ID` está seteada en el proceso real: por
  `verificarIdTokenGoogle` (líneas 230-256), el único camino a 401 pasa primero por el chequeo
  `if (!clientId)` de la línea 231-234, que devuelve 503 de inmediato si falta.
- **Sin acceso a Render en este entorno** (sin navegador, sin `RENDER_API_KEY`/CLI — reconfirmado en
  este ciclo, mismo tipo de límite ya documentado para Docker/Render en ciclos anteriores de DevOps):
  no se pudo entrar al dashboard a leer el valor cargado ni sus logs — el test HTTP de arriba es la
  evidencia disponible, más directa que un log para esta pregunta puntual, pero no confirma que el
  valor cargado sea el Client ID real de Google (solo que algo no vacío está seteado) ni si la
  Pantalla de Consentimiento OAuth ya pasó a "In production" (ninguna de las dos cosas es
  observable desde el comportamiento HTTP del backend).
- **No se modificó `render.yaml`** (ya declaraba `GOOGLE_CLIENT_ID` con `sync: false`, sin valor —
  ese es el estado final correcto, nada que corregir) ni se disparó ningún redeploy (no hacía
  falta, el servicio ya respondía con la variable cargada).
- Documentación actualizada en el propio plan (`08-despliegue/google-oauth.md` §6/§7/§9 nueva) para
  que quede el cierre registrado con evidencia, en vez de dejar ese plan con el punto "a confirmar"
  desactualizado indefinidamente.
- **Lección operativa para reutilizar:** un ticket que describe una acción pendiente puede estar
  basado en información vieja — verificar el estado real contra el sistema real (acá: un curl al
  endpoint real) antes de ejecutar la acción pedida, en vez de asumir el premise del encargo. Mismo
  criterio que ya aplicó Director General IA al refutar su propia hipótesis con evidencia en la
  entrada "Primera corrida real del CI de Backend" (2026-08-06, más arriba en este archivo).
