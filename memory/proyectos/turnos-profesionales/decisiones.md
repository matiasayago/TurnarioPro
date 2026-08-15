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
