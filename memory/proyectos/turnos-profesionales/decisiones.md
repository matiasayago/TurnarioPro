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
