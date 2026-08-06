# Plan de Lanzamiento a Producción — Turnos Profesionales (TURNOS-2026-001)

**Rol:** CTO IA (gobierno técnico)
**Fecha:** 2026-08-05
**Encargo:** el CEO pidió "estudiar la forma de salir a producción" — este documento es la
consolidación de ese pedido en un plan priorizado, no una tarea técnica puntual.
**Fase del proyecto:** entre Fase 5 (Calidad, ver nota de gobierno §2) y Fase 6 (Despliegue),
según el ciclo de vida de `docs/04-manual-operativo.md` §3.

**Entradas revisadas:** `00-resumen.md`; `03-arquitectura/documento-arquitectura.md`,
`modelo-datos.md`, `lineamientos-tecnicos.md` (propios, Fase 3); `05-codigo/backend/README.md`
+ código fuente (`package.json`, `src/app.ts`, `src/db.ts`, `src/integraciones/pagos.ts`,
`src/routes/turnos.ts`); `05-codigo/mobile/README.md` + `pubspec.yaml`; `06-qa/reporte-qa.md`;
`07-seguridad/informe-seguridad.md`; `02-backlog/backlog.md`; `01-requisitos/documento-funcional.md`;
`memory/proyectos/turnos-profesionales/decisiones.md`. No se modificó ningún archivo de código
ni entregable ya aprobado para escribir este plan.

**Coordinación con DevOps (no duplicado acá):** al momento de escribir este documento,
`08-despliegue/` todavía no tiene contenido — DevOps está armando Dockerfile/docker-compose/CI
en paralelo. Este plan no prescribe esos artefactos; donde hace falta coordinación (ver §5 y §7)
se señala explícitamente qué necesita ajustarse en ese trabajo, sin rehacerlo. Antes de ejecutar
cualquier ítem de este plan que toque despliegue, revisar si `08-despliegue/README.md` ya existe
y qué dice.

---

## 1. Resumen ejecutivo

El backend (E0–E8, incluye lo planeado para V1 y V2 del roadmap de producto) está
**funcionalmente completo y probado de punta a punta** contra su propia base de datos de
desarrollo. Ninguno de los obstáculos reales para salir a producción es una sorpresa de diseño
ni requiere rehacer arquitectura — todos estaban señalizados de antemano por los mismos roles
que hicieron el trabajo (Backend, DBA, Mobile, Security). Son, en esencia, tres familias de
pendientes:

1. **Infraestructura real:** el backend nunca habló con PostgreSQL (solo con `node:sqlite`,
   elegido para no bloquear el desarrollo en un entorno sin Visual Studio Build Tools), Row
   Level Security nunca se conectó, y no hay hosting elegido ni aprovisionado.
2. **Integraciones externas reales:** Mercado Pago y Firebase Cloud Messaging son Mocks; nadie
   creó las cuentas reales porque eso excede lo que un agente de IA puede/debe hacer.
3. **Verificación pendiente:** la app Flutter se escribió y se revisó a mano, pero **nunca se
   compiló** (este entorno no tiene el SDK de Flutter) — es la mayor incógnita real del proyecto,
   porque es la única pieza sin ninguna evidencia de ejecución.

A esto se suman dos pendientes que dependen 100% de una acción del CEO fuera del alcance de
cualquier agente (cuentas de tiendas de apps) y un punto de proceso que hay que cerrar antes de
dar la Fase 5 por definitivamente aprobada (§2).

**Ninguno de estos puntos es indefinidamente postergable, pero tampoco todos pesan lo mismo.**
La sección §4 separa bloqueantes reales de mejoras postergables con esa vara.

---

## 2. Punto de gobierno a cerrar antes de dar la Fase 5 por aprobada

Encontré una discrepancia que corresponde señalar como CTO antes de seguir: `06-qa/reporte-qa.md`
y `07-seguridad/informe-seguridad.md` (los informes firmados por QA y Security) concluyen
explícitamente **"NO listo para pasar a Security/DevOps"** y documentan 1 hallazgo Critical y 8
High/Medium sin resolver (CRITICAL-1 cross-tenant, HIGH-1 a HIGH-4, MEDIUM-1 a MEDIUM-3). Pero
`05-codigo/backend/README.md` (Backend) documenta que todos esos hallazgos **ya se remediaron**
en dos ciclos posteriores, con scripts de regresión nuevos para cada uno
(`test-critical1-aislamiento-admin.mjs`, `test-rn1-*`, `test-rn4-*`, `test-rn8-*`,
`test-validaciones-campos.mjs`, `test-autorizacion-cruzada.mjs`, `test-turno-sin-sena.mjs`), y el
código (`src/app.ts`, `package.json`) confirma que `helmet`, `express-rate-limit`, `zod` y el
manejador de errores centralizado efectivamente están instalados y montados.

El problema no es que falte trabajo — es que **quien remedió los hallazgos fue Backend, no
quien los encontró (QA/Security)**. Los informes en disco nunca se actualizaron para confirmar
"remediado y re-verificado". Es una brecha de evidencia, no de código.

**Recomendación:** antes de considerar Fase 5 formalmente cerrada, pedirle a QA y a Security una
**re-validación corta** (no una auditoría nueva completa): re-correr la batería de scripts que ya
existe contra el código actual y confirmar por escrito que CRITICAL-1 y los HIGH ya no
reproducen (el propio PoC de Security en su informe es reproducible en minutos). Esto es barato
— los scripts ya están escritos y, según Backend, ya pasan — pero es la diferencia entre
"Backend dice que está arreglado" y "QA/Security confirmaron que está arreglado", que es
justamente la separación de responsabilidades que exige el gobierno técnico de la Factory.

---

## 3. Decisión previa a todo lo demás: alcance del lanzamiento v1

El backend implementado cubre las épicas **E0–E8** (descubrimiento de negocio, catálogo,
disponibilidad, reservas + seña, autenticación, historial, cancelación/reprogramación,
excepciones) — esto es más de lo que el roadmap original definía como V1/MVP (`02-backlog/backlog.md`
marcaba E0–E4/E7 como V1 y E5/E6/E8 como V2; Backend entregó ambas de una vez).

En paralelo, Product Manager/Business Analyst están formalizando un rediseño (V4:
`02-backlog/backlog.md` E9–E14) que incluye ficha de paciente extendida con datos de
salud/sensibles (D7/RN12: fecha de nacimiento, alergias, contacto de emergencia), historial
clínico (D8/RN13) y la suscripción paga "Turnario Pro" (E11). **Verifiqué el código fuente
completo del backend y no existe ninguna columna, endpoint ni dependencia de facturación
relacionada con V4** — no es que esté a medio hacer, directamente no se empezó, y el propio
backlog ya lo marca como "bloqueada, pendiente definición de negocio".

Esto es una buena noticia para el lanzamiento, **pero solo si el CEO confirma que v1 = el
alcance ya construido (E0–E8), y V4 queda para una release posterior.** Si en cambio el CEO
espera que Turnario Pro o la ficha de paciente extendida vayan en el mismo lanzamiento, eso
agrega bloqueantes reales y no contemplados en este plan (revisión legal de datos de salud,
integración de Google Play Billing/StoreKit, y las 6 preguntas de negocio que el propio backlog
deja abiertas para E11/E9-E14). Ver pregunta abierta §9.1 — el resto de este plan asume
**lanzamiento del alcance E0–E8 ya construido**, con V4 como fast-follow.

---

## 4. Bloqueantes reales (sin esto, no hay lanzamiento posible)

Criterio usado: un ítem es "bloqueante real" si su ausencia produce pérdida de datos, una
brecha de seguridad conocida, incumplimiento de un requisito impuesto por un tercero (tiendas de
apps, ley), o si el producto directamente no puede operar sin él. Todo lo demás está en §5.

| # | Bloqueante | Rol que lo resuelve | Qué necesita del CEO | Tamaño* |
|---|---|---|---|---|
| B1 | Migrar el backend de `node:sqlite` a PostgreSQL real (driver `pg`) **y**, en la misma decisión, conectar Row Level Security (`SET LOCAL app.negocio_id`/`app.usuario_id` por transacción) | Backend + DBA | Nada nuevo — es la arquitectura ya aprobada en Fase 3; solo falta ejecutarla contra un Postgres real | M |
| B2 | Re-validación de QA/Security sobre el código ya remediado (§2) | QA + Security | Nada — gate interno | P |
| B3 | Verificar que la app Flutter compila y corre (`flutter pub get && flutter analyze && flutter run`) | Mobile | Aprobar que se use CI (GitHub Actions con el SDK oficial de Flutter, gratis) ya que este entorno no tiene el SDK instalado | P–M (desconocido hasta probarlo) |
| B4 | Elegir y aprovisionar hosting para backend + PostgreSQL | DevOps | Aprobar proveedor y presupuesto mensual (ver §6) + método de pago | M |
| B5 | Gestión de secretos en el hosting elegido (`JWT_SECRET`, credenciales de DB, luego MP/FCM) — ninguno en el repo | DevOps | Nada adicional a B4 | P |
| B6 | Backups automáticos mínimos de la base de datos de producción | DevOps | Aprobar si se usa un tier de hosting con backup incluido o se scriptea aparte (ver §6) | P–M |
| B7 | Reemplazar el Mock de Mercado Pago por integración real | Integraciones | Crear la cuenta de Mercado Pago (KYC/CUIT/cuenta bancaria) y proveer `MP_ACCESS_TOKEN` — **ver matiz abajo** | M en agente + lead time externo variable (KYC) |
| B8 | Reemplazar el Mock de FCM por integración real | Integraciones | Crear un proyecto de Firebase (gratis, solo cuenta Google) y proveer credenciales — **ver matiz abajo** | P en agente + lead time externo corto |
| B9 | Política de privacidad publicada (URL pública) | Technical Writer + CEO | Revisar/aprobar el texto final (no reemplaza asesoría legal) | P |
| B10 | Cuentas de tienda: Google Play Console y, si aplica, Apple Developer Program | — (ningún agente puede crearlas) | Crearlas y pagarlas: **USD 25 único** (Google Play) / **USD 99 anual** (Apple, más D-U-N-S si es cuenta de organización) | 100% CEO |

*P = Pequeño, M = Mediano, G = Grande, en esfuerzo de agente — no comparable 1:1 a días-persona;
ver nota sobre camino crítico en §7.

### Detalle y matices de los bloqueantes no obvios

**B1 — por qué no alcanza con "ya probamos toda la lógica de negocio".** Los ~77 chequeos
automatizados (`06-qa/reporte-qa.md`) validan reglas de negocio (RN1-RN10), no comportamiento
específico de Postgres. Dos cosas concretas a re-verificar, no asumir:
- El `catch` que detecta conflicto de unicidad en `src/routes/turnos.ts` (RN2, anti-doble-reserva)
  **ya contempla ambos drivers** (`err.code === '23505'` para Postgres, además del mensaje de
  `node:sqlite`) — buena señal de que Backend ya pensó en la migración, pero nunca se ejecutó
  contra Postgres real, así que `npm run test:concurrencia` debe re-correrse ahí antes de confiar
  en el resultado.
- RLS y la migración de driver están acopladas, no son dos tareas independientes: el DDL ya
  escrito (`05-codigo/database/migrations/001_init.sql`) habilita RLS a nivel de tabla. Si se
  aplica tal cual sin que el backend setee `SET LOCAL app.*`, **las políticas de escritura
  deniegan todo por defecto** (fail-closed, ya documentado en `modelo-datos.md` §5) — es decir,
  aplicar ese DDL sin el fix de backend no es "menos seguro", directamente **rompe la
  aplicación**. Backend/DBA deben decidir conscientemente: conectar `SET LOCAL app.*` en el mismo
  cambio, o aplicar el DDL sin forzar RLS todavía y conectar en un fast-follow — cualquiera de
  las dos es válida, lo que no es válido es que sea accidental.
- Por qué esto es bloqueante y no postergable: `node:sqlite` es un archivo único de un solo
  proceso — no está pensado para múltiples réplicas del backend, ni para el tooling de
  backup/restore que cualquier proveedor de hosting ofrece nativamente sobre Postgres, y **RLS
  como defensa en profundidad no existe fuera de Postgres** (se pierde la segunda barrera de
  aislamiento multi-tenant permanentemente, no solo temporalmente). Fue una decisión consciente
  de *desarrollo*, documentada como tal por DBA/Backend — nunca se propuso como arquitectura de
  producción.

**B3 — la mayor incógnita real.** Es la única pieza del proyecto con **cero evidencia de
ejecución** (ni siquiera se instalaron las dependencias con `flutter pub get`). La revisión
manual ya encontró y corrigió un bug real (casteo de `Future` en `ApiClient`), lo cual es una
señal de que revisión manual sola no alcanza. Recomiendo agregarlo como un job más en el mismo
pipeline de CI que DevOps ya está armando para el backend (GitHub Actions tiene una acción
oficial para instalar el SDK de Flutter, sin costo en minutos para un repo de este tamaño) en
vez de esperar a que alguien consiga una máquina con Flutter instalado a mano.

**B7/B8 — friction real distinta entre ambas integraciones.** Firebase (FCM) solo necesita una
cuenta de Google y es gratis — el CEO puede desbloquearlo en minutos. Mercado Pago necesita
verificación de identidad/cuenta bancaria (KYC) — tiene un lead time real que no está bajo
control de la Factory. Dado que RN10/D2 ya soporta un camino "sin seña" (probado,
`test-turno-sin-sena.mjs` pasa), existe una salida operativa válida si el CEO quiere lanzar
antes de que Mercado Pago esté habilitado: configurar temporalmente todos los servicios sin
seña requerida, y sumar el cobro real de seña como fast-follow. Es una decisión del CEO (afecta
el modelo de negocio, no algo que yo deba decidir por criterio técnico) — ver pregunta §9.3.
Notificaciones (FCM) sí estaba comprometida como parte del alcance de v1 (D4, épica E7 = P0);
recomiendo cerrarla antes de lanzar dado lo bajo de la fricción, pero si hay presión de tiempo
extrema, el producto sigue siendo utilizable sin push (el usuario ve sus turnos dentro de la
app) — de nuevo, decisión del CEO, no un default silencioso de mi parte.

**B9 — hallazgo propio, no estaba en la lista de pendientes conocidos.** Tanto Google Play como
Apple **exigen una URL de política de privacidad** para publicar cualquier app, sin importar si
se manejan datos de salud o no (eso es un requisito aparte, ver §8). Con datos básicos de
contacto (nombre/email/teléfono) ya alcanza para que ambas tiendas la exijan. Es barato de
producir pero bloquea la publicación si falta.

---

## 5. Recomendado pero postergable (se puede lanzar sin esto)

| Ítem | Por qué no es bloqueante hoy | Cuándo revisarlo |
|---|---|---|
| Política CORS explícita | Hoy el único consumidor es la app mobile nativa (CORS no aplica) + `web-preview/` same-origin (dev-only). Security ya lo marcó Low/no explotable. | Antes de sumar cualquier cliente web (ej. un panel del CEO) — configurar con allowlist explícita, nunca wildcard, dado que la auth es JWT Bearer. |
| Observabilidad avanzada (logs centralizados, dashboards, alerting granular) | El mínimo viable (backups + un health-check de uptime) ya está en B6/§6. Lo demás es mejora de madurez operativa, no requisito de lanzamiento. | Cuando haya usuarios reales generando volumen — priorizar según qué incidentes realmente ocurran. |
| Refresh tokens / revocación de JWT | Documentado como brecha diseño-vs-implementación por Security, pero un JWT de 2 hs sin refresh es un trade-off aceptable y común para un v1. | Si se detectan sesiones que necesitan durar más sin re-login, o si se requiere poder revocar sesiones (ej. robo de dispositivo). |
| Chequeo de contraseñas filtradas (HaveIBeenPwned) | La política de longitud mínima (8 caracteres) ya está. Es un endurecimiento adicional, no un hueco crítico. | Mejora de seguridad de bajo costo para un ciclo posterior. |
| E10 (reportes/analítica), V3 (medios de pago adicionales, panel admin avanzado) | Fuera del alcance ya construido y no comprometido para v1. | Roadmap de producto, no de este plan. |
| V4 completo (dashboard, ficha de paciente extendida, Turnario Pro, WhatsApp) | Ver §3 — condicionado a la decisión de alcance del CEO. Si se confirma que v1 no lo incluye, todo este bloque pasa a backlog de la próxima release, con sus propios bloqueantes (revisión legal, Play Billing/StoreKit). | Tras confirmar §9.1, y con las 6 preguntas de negocio que ya deja abiertas `02-backlog/backlog.md` §7 resueltas. |

---

## 6. Hosting: comparación y recomendación

Contexto de dimensionamiento: un backend Node modular monolito + PostgreSQL chico, tráfico
esperado de un MVP (no miles de usuarios concurrentes desde el día uno). No corresponde una
arquitectura enterprise para este volumen.

| Opción | Modelo | Costo aprox./mes* | Complejidad operativa | Backups/TLS | Notas |
|---|---|---|---|---|---|
| **Render** | PaaS, deploy directo desde el Dockerfile que ya arma DevOps | ~USD 13–20 (web Starter ~USD 7 + Postgres Basic desde ~USD 6) | Baja | TLS automático incluido; Postgres con backups en planes pagos (el free tier expira a los 30 días — presupuestar desde el día 1) | Buen ajuste directo con el artefacto Docker existente; precios por escalón fijo, fáciles de presupuestar |
| **Railway** | PaaS, deploy desde Dockerfile o repo | ~USD 15–25 (base ~USD 5 + consumo variable; Postgres gestionado ~USD 10+ según tamaño) | Baja | Sí, Postgres gestionado con backups | DX muy simple; el costo varía algo más con el uso real que Render, un poco menos predecible para presupuestar a ciegas |
| **Fly.io** | Contenedores cerca del usuario ("edge"), más control | ~USD 15–25 reales todo incluido (el número de marketing de ~USD 2 no cubre app + Postgres + egress reales) | Media | TLS automático; backups de Postgres opcionales, con costo aparte | Interesante si importa latencia baja en varias regiones; requiere más manejo manual (`flyctl`, volúmenes) que Render/Railway |
| **VPS propio** (ej. Hetzner CX23/CPX22) | IaaS — DevOps administra todo corriendo el mismo `docker-compose` | ~USD 6–10 de servidor | Alta — parches de SO, TLS con Caddy/certbot, backups con cron propio, todo a cargo de DevOps | No incluidos — hay que armarlos | La factura más barata, pero el costo real se traslada a tiempo de mantenimiento sostenido; razonable solo si DevOps puede sostenerlo en el tiempo |
| AWS / GCP / Azure | IaaS/PaaS de nivel enterprise | ~USD 20–40+ como piso (RDS + compute), con curva de aprendizaje | Alta | Sí, pero hay que configurarlo (IAM, VPC, RDS backups) | Sobredimensionado para este tamaño de MVP hoy; reconsiderar solo si el CEO ya tiene créditos disponibles o un plan de escala concreto que lo justifique |

*Costos de referencia investigados en agosto 2026, aproximados y sujetos a cambio — confirmar en
el sitio de cada proveedor al momento de contratar. No incluyen dominio (~USD 10–15/año, costo
aparte y menor).

**Recomendación:** **Render o Railway** como primera opción — ambos aceptan el Dockerfile que
DevOps ya está armando, incluyen Postgres gestionado con backups (resuelve B6 casi gratis) y TLS
automático (sin trabajo adicional de DevOps), a un costo previsible para un MVP. La elección
entre ambos es de bajo riesgo y reversible; puede decidirla DevOps según cuál probar primero.
**VPS (Hetzner)** es una alternativa válida si minimizar el costo mensual pesa más que el tiempo
de DevOps en mantenimiento continuo — lo dejo como opción, no como recomendación principal,
porque el ahorro (~USD 10/mes) es chico frente al riesgo operativo de un primer lanzamiento sin
backups/TLS/parches gestionados. **No recomiendo AWS/GCP/Azure en esta etapa** — es complejidad
que este volumen no necesita todavía.

**Secretos:** con cualquiera de las opciones de PaaS (Render/Railway/Fly.io), usar el gestor de
variables de entorno nativo del proveedor (Render Environment Groups / Railway Variables / Fly
Secrets) alcanza y es apropiado para este tamaño — evita sobre-ingeniería (un Vault/Secrets
Manager dedicado no se justifica todavía). Si se opta por VPS, un archivo `.env` fuera del
control de versiones, con permisos restringidos, es suficiente en esta etapa.

---

## 7. Orden recomendado y estimación de esfuerzo

**Nota importante sobre el "camino crítico" real:** el trabajo que hacen los agentes de la
Factory (migrar el driver, conectar RLS, armar Docker, ajustar el backend) es rápido en términos
de calendario. Lo que **no se puede acelerar** es el tiempo de las acciones que dependen
exclusivamente del CEO o de terceros: verificación de identidad de Google Play/Apple, KYC de
Mercado Pago, aprobación de presupuesto de hosting. **El cuello de botella del lanzamiento es
casi seguro ese tiempo externo, no el trabajo técnico** — por eso conviene arrancar ya, en
paralelo, todo lo que dependa del CEO (§9), aunque la ejecución técnica de otros ítems todavía
no haya terminado.

Orden de dependencias (no estrictamente secuencial — varios ítems corren en paralelo):

1. **Ahora, en paralelo, sin dependencias entre sí:**
   - CEO confirma alcance de v1 (§3) — desbloquea saber si V4 aplica a este lanzamiento.
   - CEO inicia trámites de cuenta de Google Play / Apple Developer / Mercado Pago (lead time
     externo largo — arrancar ya no cuesta nada y acorta el camino crítico total).
   - QA/Security re-validan Fase 5 (§2) — barato, scripts ya existen.
   - Mobile corre `flutter pub get && flutter analyze && flutter run` en CI (B3) — no depende de
     nada del resto de este plan.
   - DevOps sigue armando Dockerfile/CI (ya en curso) — construir la imagen no depende de qué
     driver de base de datos use el backend.
2. **Backend + DBA:** migración a PostgreSQL + conexión de RLS (B1) — es la base de todo lo que
   sigue con datos reales. Al terminar, avisar a DevOps: el `docker-compose`/variables de entorno
   van a necesitar `DATABASE_URL` en vez de `DB_PATH`, y probablemente un servicio Postgres (o
   apuntar a la instancia gestionada del hosting elegido en el paso 3).
3. **CEO + DevOps:** elegir y aprovisionar hosting (B4, ver §6), una vez que el paso 1 (Docker) y
   el paso 2 (Postgres) están listos para conectarse entre sí.
4. **Integraciones:** conectar FCM real (B8, rápido) y Mercado Pago real (B7, condicionado al
   lead time de KYC — puede arrancar en paralelo desde el paso 1, pero probablemente termine
   después).
5. **Post-despliegue, antes de anunciar el lanzamiento:** re-correr la batería de smoke tests
   existente (`scripts/smoke-test.mjs` y el resto) contra la URL real de producción, no solo
   contra `localhost`. Ajuste menor necesario: estos scripts hoy tienen `BASE` hardcodeado a
   `http://localhost:3000` — cambiarlo a `process.env.BASE_URL || 'http://localhost:3000'` es un
   cambio de una línea, no un desarrollo nuevo, y deja lista una batería de regresión reutilizable
   para cada despliegue futuro.
6. **Al final, no antes:** publicar en las tiendas (B10 + B9) — necesita una app ya compilada
   (paso 1) apuntando a un backend ya desplegado y estable (pasos 2–5), no al revés.

---

## 8. Publicación en tiendas de apps (para que el CEO lo gestione — ningún agente puede hacerlo)

| Ítem | Costo | Notas |
|---|---|---|
| Google Play Console | **USD 25, pago único** | Sin renovación anual. Desde 2026 Google exige además una verificación de identidad del desarrollador antes de poder publicar. |
| Apple Developer Program | **USD 99/año** | Se renueva cada año. Si la cuenta es de organización (no individual), Apple pide verificación vía número D-U-N-S, que puede sumar días de trámite adicional. |

Recomiendo evaluar si conviene lanzar primero solo en Android (Google Play): trámite más simple,
costo único más bajo, y permite validar el producto con usuarios reales mientras se resuelve la
verificación de Apple en paralelo si se decide sumar iOS. Esto es una sugerencia de secuencia, no
una decisión de producto que me corresponda tomar — depende de dónde estén los usuarios objetivo
del CEO.

---

## 9. Datos personales y de salud — señal de alerta, no asesoría legal

El rediseño en curso (D7/RN12/RN13, ver §3) agrega datos de salud/sensibles (fecha de
nacimiento, alergias, notas médicas). En Argentina, la **Ley 25.326** de Protección de Datos
Personales clasifica los datos de salud como "datos sensibles": nadie puede ser obligado a
proveerlos, requieren medidas de seguridad reforzadas, y no pueden transferirse a terceros sin
consentimiento previo, expreso e informado del titular. Si la Factory opera con usuarios en
otros países, puede haber normativa adicional aplicable (ej. reglamentos de protección de datos
locales) que no investigué en detalle porque excede el alcance de este plan.

Esto **no aplica hoy** al backend ya construido (E0-E8) — ningún dato de salud existe en el
esquema actual (verificado en el código). Aplica únicamente si el CEO confirma que V4 (ficha de
paciente extendida) va en el mismo lanzamiento o en uno cercano (§3). No es un bloqueante que yo
deba o pueda resolver — es una señal para que el CEO consulte a un abogado antes de habilitar
esos campos en producción, tal como el propio Business Analyst ya dejó anotado en
`01-requisitos/documento-funcional.md` (D7).

---

## 10. Preguntas abiertas para el CEO

1. **Alcance de v1:** ¿lanzamos con el backend ya construido (E0–E8, sin Turnario Pro ni ficha de
   paciente extendida), dejando V4 para una release posterior, o esperamos a incluir V4 en el
   mismo lanzamiento? Esto determina si los puntos de datos de salud (§9) y suscripción paga
   aplican a este ciclo o al siguiente.
2. **Hosting:** ¿aprobás Render o Railway (~USD 15–25/mes) como proveedor, o preferís la opción
   más económica pero más manual de un VPS (~USD 6–10/mes + mantenimiento de DevOps)? ¿Qué tope
   de gasto mensual aprobás?
3. **Mercado Pago:** ¿ya tenés o podés gestionar en un plazo corto una cuenta de Mercado Pago
   habilitada para cobrar (CUIT/cuenta bancaria)? Si el trámite va a demorar, ¿preferís lanzar la
   primera versión con todos los servicios configurados "sin seña" mientras se tramita, en vez de
   esperar a tener Mercado Pago para lanzar?
4. **Tiendas de apps:** ¿podés iniciar ya el alta de Google Play Console (USD 25) y, si aplica,
   Apple Developer Program (USD 99/año) dado el tiempo de verificación de identidad? ¿Lanzamos
   primero solo Android, o Android e iOS a la vez?
5. **Datos de salud (solo si la respuesta a la pregunta 1 incluye V4):** ¿corresponde consultar a
   un abogado sobre la Ley 25.326 antes de habilitar los campos de salud/sensibles, dado que la
   plataforma es multi-rubro y no todos los negocios son de salud (pregunta que además ya dejó
   abierta Business Analyst en el propio backlog)?
6. **CI para Mobile:** ¿autorizás que Mobile/DevOps usen GitHub Actions con el SDK oficial de
   Flutter (gratis, dentro de los minutos incluidos de un repo de este tamaño) para verificar la
   compilación, en vez de depender de conseguir una máquina con Flutter instalado a mano?
