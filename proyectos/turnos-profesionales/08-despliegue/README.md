# Despliegue — Turnos Profesionales (TURNOS-2026-001)

**Rol:** DevOps
**Fase:** 6 — Despliegue
**Entradas:** QA (`../06-qa/reporte-qa.md`) y Security (`../07-seguridad/informe-seguridad.md`),
ambos cerrados, con los hallazgos bloqueantes ya remediados (ver
`../05-codigo/backend/README.md`, secciones "Fase 5" y "Ciclo 2").

## 0. Alcance de este ciclo

**Ciclo 1 (2026-08-05)** entregó **artefactos de contenerización y CI/CD** para el backend
tal como existía en ese momento (`node:sqlite`, ver §7 para el historial completo):
`../05-codigo/backend/Dockerfile`, `.dockerignore`, `docker-compose.yml`, `.env.example`, y
`../../../.github/workflows/turnos-backend-ci.yml`.

**Ciclo 2 (2026-08-07) — migración a PostgreSQL, coordinada con Backend.** El CEO aprobó
Render/Railway (PostgreSQL gestionado) para producción y, en paralelo a este ciclo, Backend
migró el driver de acceso a datos de `node:sqlite` a `pg` (variable de entorno
`DATABASE_URL`, convención estándar — la misma que Render inyecta solo al conectar su addon
de Postgres). Este ciclo actualiza la infraestructura para reflejar ese cambio:

- `../05-codigo/backend/Dockerfile` — saca el volumen/lógica de `dev.sqlite3` (ya no aplica).
- `../05-codigo/backend/.dockerignore` — comentario actualizado (mismo motivo).
- `../05-codigo/backend/docker-compose.yml` — nuevo servicio `postgres` (antes ausente a
  propósito, ver §7).
- `../05-codigo/backend/.env.example` — `DATABASE_URL` en vez de `DB_PATH`.
- `../../../.github/workflows/turnos-backend-ci.yml` — service container de Postgres en
  los dos jobs (`build-and-test` y `docker-build-smoke`).
- `../05-codigo/backend/render.yaml` — Blueprint de Render, nuevo (ver §10). Borrador no
  verificado contra una cuenta real (ver el propio archivo) — pensado para acelerar la
  primera conexión del repo, no para aplicarse a ciegas sin revisar.
- Este documento (§1, §3, §6, §7, §8, §9, §10).

**Sigue sin publicar ningún entorno real.** Nadie de la Factory tiene todavía credenciales
de Render/Railway ni aprovisionó un servicio real — este ciclo deja la infraestructura y el
instructivo listos para cuando el CEO/DevOps lo hagan, no ejecuta ese paso (ningún agente de
IA puede crear cuentas ni cargar métodos de pago). Y de todos modos, ningún cambio llega a
producción sin aprobación previa (principio operativo de la empresa, ver
`docs/04-manual-operativo.md`, y las reglas de actuación del rol DevOps).

Nota sobre el entorno de desarrollo de DevOps: **sigue sin tener Docker instalado** (ni en
el ciclo 1 ni en este). No se pudo correr `docker build`/`docker compose up` para verificar
ninguno de los cambios de este ciclo tampoco — mismo tipo de limitación que ya tenía DBA
para verificar Row Level Security contra un Postgres real (ver
`../03-arquitectura/modelo-datos.md` §5). La sección 5 de este documento detalla qué se
validó igual (con Node real, sin Docker, y validación sintáctica de YAML con un parser real)
y qué queda pendiente — la verificación real de este ciclo pasa por el primer run de
GitHub Actions en verde después de un push coordinado con Backend (ver §7 y §8).

## 1. Cómo buildear y correr con Docker

### Standalone

Requiere un PostgreSQL ya accesible (propio, o el de un proveedor) — a diferencia del ciclo
anterior, esta imagen ya no trae ninguna base de datos local embebida:

```bash
cd proyectos/turnos-profesionales/05-codigo/backend
docker build -t turnos-profesionales-backend:local .
docker run -d --name turnos-backend -p 3000:3000 \
  -e JWT_SECRET="$(openssl rand -base64 48)" \
  -e DATABASE_URL="postgresql://usuario:password@host:5432/basededatos" \
  turnos-profesionales-backend:local
curl http://localhost:3000/health
```

### Con docker-compose (recomendado para desarrollo/staging local)

```bash
cd proyectos/turnos-profesionales/05-codigo/backend
cp .env.example .env        # completar JWT_SECRET — ver los comentarios en ese archivo
docker compose up --build
```

`docker-compose.yml` **incluye un servicio `postgres`** (`postgres:16-alpine`, con volumen
nombrado `turnos_postgres_data` para persistir los datos entre reinicios/recreaciones y
`healthcheck` propio) — hasta el ciclo anterior no lo incluía a propósito, ver §7 para el
porqué de ese cambio. El servicio `backend` espera a que `postgres` esté `healthy`
(`depends_on: condition: service_healthy`) antes de arrancar, expone el puerto 3000
(configurable vía `PORT` en `.env`), y se conecta a `postgres` con una `DATABASE_URL` que
ya viene fijada en el propio `docker-compose.yml` (apunta al servicio por su nombre de red
interno de Compose, no a `localhost` — no hace falta, y no corresponde, completarla en
`.env`). El resto de la configuración se sigue leyendo desde `.env` (nunca commiteado — ver
`.gitignore`/`.dockerignore` del backend).

## 2. Build multi-stage (resumen del Dockerfile)

- **Stage `build`** (`node:22-slim`): `npm ci` (con devDependencies) → `npm run build`
  (compila TypeScript a `dist/`) → `npm prune --omit=dev` (saca `ts-node`, `typescript`,
  `@types/*`, `cross-env` del `node_modules` que se copia al stage final).
- **Stage `runtime`** (`node:22-slim`, imagen final): copia únicamente `node_modules` (ya
  podado), `dist/`, `package.json` y `migrations/`. **No incluye** `scripts/` (tests
  manuales) ni `web-preview/` (preview interactiva de desarrollo) — ninguno de los dos
  hace falta para servir la API, y omitirlos es una capa extra de defensa (ver hallazgo
  HIGH-4 de Security, retomado en §3). Corre como el usuario no-root `node` que ya trae la
  imagen oficial (no `root`).

### Hallazgo de este ciclo: el entrypoint real es `dist/src/index.js`, no `dist/index.js`

`package.json` declara `"main": "dist/index.js"` y `"start": "node dist/index.js"`, pero
`tsconfig.json` compila con `rootDir: "."`, así que el JavaScript compilado queda en
`dist/src/*.js`. Verificado en este ciclo, con Node real (v26.6, cumple `>=22.5`):

```
npm run build && node dist/index.js       →  Error: Cannot find module '.../dist/index.js'
npm run build && node dist/src/index.js   →  arranca correctamente (smoke test OK, ver §5)
```

Es un desajuste preexistente en `package.json` que nunca se había ejercitado: el flujo de
desarrollo usa `ts-node-dev` (no pasa por `dist/`), y ni QA ni Security llegaron a correr
`npm start` — el propio `README.md` del backend ya insinuaba esto de pasada ("si corrés el
servidor... `node dist/src/index.js`..."), pero `package.json` nunca se corrigió. El
`Dockerfile` de este ciclo usa la ruta real (`CMD ["node", "dist/src/index.js"]`), no la
que dice `package.json`.

**No corregí `package.json` yo mismo (en su momento, ciclo 1):** es un entregable de
Backend ya validado por QA/Security, y las reglas de actuación de DevOps piden no
modificar entregables aprobados sin autorización del Director General IA. Lo resolví
enteramente a nivel de imagen (Dockerfile), sin tocar código fuente, y quedó reportado como
defecto menor para un próximo ciclo.

**Actualización (2026-08-06):** el Director General IA corrigió directamente
`package.json` (`main`/`start` → `dist/src/index.js`, ver
`memory/proyectos/turnos-profesionales/decisiones.md`, "Cierre del hallazgo de
`package.json`") — el desajuste descripto en este §2 ya **no existe** en el código actual.
Se deja el resto de esta sección sin reescribir porque documenta correctamente el
diagnóstico original y por qué el `Dockerfile` usa la ruta explícita en el `CMD` de todos
modos (ver el párrafo siguiente) — eso no cambió.

Por el mismo desfase, `__dirname` en runtime apunta a `dist/src/`, no a `src/`, así que
`runMigrations()` (`src/db.ts`) resuelve `../migrations` como `dist/migrations` — de ahí
que el `Dockerfile` copie la carpeta `migrations/` ahí adentro (`COPY migrations
./dist/migrations`) y no en la raíz de `/app`. Documentado con detalle en los comentarios
del propio `Dockerfile` para que quien lo toque en el futuro no lo "simplifique" sin saber
por qué está así.

## 3. Variables de entorno

Ver también `../05-codigo/backend/.env.example` (plantilla completa y comentada) y
`../05-codigo/backend/README.md`.

| Variable | Requerida | Default de la app | Notas |
|---|---|---|---|
| `DATABASE_URL` | **Sí** | — (sin default; `src/db.ts` necesita un Postgres real) | Formato `postgresql://usuario:password@host:puerto/basededatos`. **En Render, la provee el proveedor solo** al conectar su addon de Postgres — nunca se arma a mano ahí (ver §10). **En docker-compose, ya viene fijada en `docker-compose.yml`** apuntando al servicio `postgres` por su nombre de red interno de Compose — no hace falta (ni corresponde) completarla en `.env` para ese flujo. Solo se completa a mano en `.env`/`docker run` para el modo standalone (§1) o para apuntar a un Postgres externo. |
| `JWT_SECRET` | **Sí, en producción** (`NODE_ENV=production`, ya fijado por el Dockerfile) | `dev-secret-not-for-production` (solo fuera de `NODE_ENV=production`) | El proceso **no arranca** en producción sin esto seteado (hallazgo HIGH-3, ya remediado en código). Nunca commitear el valor real — generarlo aparte (ej. `openssl rand -base64 48`, o dejar que Render lo genere solo vía `generateValue: true` en `render.yaml`, ver §10) y gestionarlo vía secretos del entorno real. |
| `PORT` | No | `3000` | También la usa `docker-compose.yml` para el mapeo de puertos host:contenedor. |
| `ENABLE_DEV_ROUTES` | No — **nunca en producción** | ausente (equivale a `false`) | Monta `/dev/seed` y `/dev/forzar-expiracion`, sin autenticación propia (hallazgo HIGH-4). La imagen nunca la setea; tampoco incluye `web-preview/` (defensa en profundidad). |
| `EXPIRACION_PAGO_MIN` | No | `15` | Minutos hasta expirar automáticamente un turno `pendiente_de_pago` sin confirmación de pago. |
| `VENTANA_CANCELACION_MIN` | No | `120` | Ventana mínima para cancelar/reprogramar sin contactar al negocio directamente (RN8/A3). |
| `RATE_LIMIT_LOGIN_MAX` / `RATE_LIMIT_LOGIN_WINDOW_MIN` | No | `10` / `15` | Fuerza bruta en `/auth/login` (HIGH-1) — cuenta solo intentos fallidos. |
| `RATE_LIMIT_REGISTRO_MAX` / `RATE_LIMIT_REGISTRO_WINDOW_MIN` | No | `10` / `15` | Alta masiva en `/auth/registro-*` — cuenta todos los intentos. |
| `NODE_ENV` | No (ya fijado por el Dockerfile) | `production` en esta imagen | Condiciona el fail-fast de `JWT_SECRET` de arriba — no se recomienda cambiarlo, ni siquiera en staging local. |

## 4. HEALTHCHECK

`GET /health` (`src/app.ts`) responde `{"ok": true}`, sin autenticación. El `Dockerfile`
declara:

```
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD [...]
```

implementado con un script Node inline (no `curl`/`wget`, que no están garantizados en
`node:22-slim`). `docker ps` expone el estado (`healthy` / `unhealthy` / `starting`) del
contenedor; `docker-compose.yml` no redefine este healthcheck — hereda el del Dockerfile a
propósito, para tener una sola fuente de verdad.

## 5. Verificación — qué se probó realmente en este ciclo vs. qué queda pendiente

**Esta sección documenta la verificación del ciclo 1 (2026-08-05, `node:sqlite`) tal cual
se hizo en su momento** — se mantiene sin reescribir porque sigue siendo la evidencia real
de esa verificación puntual. **No cubre la migración a PostgreSQL del ciclo 2
(2026-08-07):** ver §7 y §8 para qué se validó (YAML con parser real) y qué sigue sin
confirmarse (todo lo que necesita un Postgres real corriendo, bloqueado por la misma falta
de Docker que ya describe esta sección).

**No se pudo correr Docker** en este entorno (no está instalado) — el `Dockerfile`,
`.dockerignore` y `docker-compose.yml` **no se verificaron con un build real acá**. Sí se
revisaron línea por línea contra la documentación de Docker (sintaxis de multi-stage,
`HEALTHCHECK`, `USER`, exec-form de `CMD`, resolución de `.dockerignore`), y el YAML de
`docker-compose.yml` y del workflow de CI se validó **sintácticamente con un parser real**
(`js-yaml`, cargado temporalmente para este chequeo), no solo a simple vista.

Lo que **sí** se verificó de punta a punta en este ciclo, con Node real (v26.6, cumple
`>=22.5`):

- `npm run build` compila sin errores.
- `node dist/src/index.js` (el JavaScript ya compilado, no `ts-node`) arranca, corre
  `runMigrations()` contra un `dev.sqlite3` limpio y responde `GET /health` — replicando
  exactamente el layout que arma el Dockerfile (`migrations/` copiada junto al `dist/src/`
  compilado, `DB_PATH` apuntando afuera del árbol de build).
- `scripts/smoke-test.mjs` (flujo completo: alta de negocio → servicio → profesional →
  disponibilidad → slots → reserva → historial → cancelación) **pasó sin fallos** contra
  esa instancia compilada.
- Se reprodujo activamente — antes de escribir el workflow de CI, no solo leyendo el
  README — que la batería de `scripts/*.mjs` (10 scripts) necesita **dos arranques
  distintos del servidor**: `scripts/test-rn8-ventana-cancelacion.mjs` está diseñado
  contra la ventana de cancelación **default** (120 min) y **falla** si se lo corre con
  `VENTANA_CANCELACION_MIN=0` (que es justo lo que necesitan los otros 9 scripts para no
  depender de esperar minutos reales). El workflow de CI levanta el servidor dos veces por
  este motivo — ver los comentarios de
  `.github/workflows/turnos-backend-ci.yml`.

Pendiente de verificar (bloqueado por falta de Docker en este entorno de desarrollo):

- Que `docker build` de este `Dockerfile` efectivamente produzca una imagen.
- Que el contenedor arranque, pase el `HEALTHCHECK` y sirva tráfico real end-to-end.
- Que `docker compose up` levante el servicio con el volumen y las variables de entorno
  exactamente como se espera.

**Mitigación — no queda del todo sin verificar:** el job `docker-build-smoke` del
workflow de CI (ver §6) sí construye esta imagen y corre `scripts/smoke-test.mjs` contra
un contenedor real, porque los runners de GitHub Actions traen Docker preinstalado a
diferencia de este entorno de desarrollo. Es el primer lugar donde este `Dockerfile` se
valida de verdad — **revisar el resultado de ese job en GitHub Actions antes de confiar en
esta imagen para cualquier entorno real.** Desde el ciclo 2, ese mismo job es también el
primer lugar donde se valida la migración a Postgres del `Dockerfile` (conexión real a su
service container vía `--network host`, ver §6) — mismo criterio, mismo job.

## 6. CI (GitHub Actions)

`.github/workflows/turnos-backend-ci.yml` (raíz del repo) corre en push/PR que toquen
`proyectos/turnos-profesionales/05-codigo/backend/**`, en dos jobs:

1. **`build-and-test`** — `npm ci`, `npx tsc --noEmit`, `npm run build`, y la batería
   completa de `scripts/*.mjs` contra `ts-node` (feedback rápido sobre tipos y lógica de
   negocio/seguridad, en los dos arranques de servidor que describe §5). Usa Node 22
   (`actions/setup-node@v4`), coherente con el `Dockerfile`. Corre contra un **service
   container `postgres:16-alpine`** (credenciales de test fijas, no secretas —
   `DATABASE_URL=postgresql://turnos_ci:turnos_ci_password@localhost:5432/turnos_test`,
   ver comentarios del propio workflow) — GitHub Actions espera a que su healthcheck
   (`pg_isready`) esté en verde antes de dejar correr el primer step, así que no hace falta
   ningún paso propio de espera. No hay un paso separado que corra
   `database/migrations/001_init.sql` a mano: se apoya en que `runMigrations()` (Backend)
   corre automáticamente al arrancar el servidor, igual que ya hacía contra `node:sqlite`.
2. **`docker-build-smoke`** (corre después de que el anterior pase) — construye la imagen
   Docker real a partir de este mismo `Dockerfile` y corre `scripts/smoke-test.mjs` contra
   un contenedor levantado en config "tipo producción" (`NODE_ENV=production`, el default
   de la imagen, sin `ENABLE_DEV_ROUTES`) — la validación más representativa de un
   despliegue real que se puede hacer sin desplegar de verdad. También corre contra su
   propio service container `postgres:16-alpine` (mismas credenciales fijas que el job
   anterior, pero un Postgres efímero completamente independiente — cada job de Actions usa
   una máquina nueva). Como la app corre acá DENTRO de un contenedor levantado a mano
   (`docker run`, no un step directo del runner), ese contenedor se arranca con
   `--network host` para poder alcanzar el `localhost:5432` del Postgres del job — un
   `docker run` suelto no comparte por defecto la red donde Actions publica los service
   containers.

## 7. Gap `node:sqlite` → PostgreSQL: bloqueante desde el ciclo 1, cerrado en código en el ciclo 2 (pendiente de confirmar con CI en verde)

**Historial (ciclo 1, 2026-08-05).** El backend implementado usaba **`node:sqlite`**
(built-in de Node, sin dependencias nativas) para desarrollo — ver
`../05-codigo/backend/README.md` y `memory/proyectos/turnos-profesionales/decisiones.md`.
La arquitectura documentada siempre apuntó a **PostgreSQL** en producción
(`../05-codigo/database/migrations/001_init.sql`), con Row Level Security ya diseñada — ver
**[`../03-arquitectura/modelo-datos.md`, sección 5 ("Row Level Security (Postgres,
producción)")](../03-arquitectura/modelo-datos.md)** — pero, hasta ese ciclo, sin conectar:
`src/db.ts` importaba `node:sqlite` directamente y ninguna query pasaba por un driver de
Postgres. Ese ciclo documentó el gap explícitamente como **bloqueante** (el razonamiento
completo se mantiene vigente, ver más abajo) y dejó `docker-compose.yml` deliberadamente
**sin** un servicio `postgres:` — agregarlo en ese momento hubiera aparentado un soporte
que el código todavía no tenía.

**Ciclo 2 (2026-08-07) — qué cambió.** El CEO aprobó Render/Railway (PostgreSQL gestionado)
para producción y, en paralelo a este mismo ciclo de DevOps, Backend migró el driver de
`src/db.ts` de `node:sqlite` a `pg` (PostgreSQL real), leyendo la variable de entorno
`DATABASE_URL` — coordinado explícitamente con este ciclo, no un cambio independiente (ver
§0 y §8: ambas partes se juntan en el mismo push). Del lado de infraestructura, este ciclo
agregó lo necesario para que esa migración sea verificable y desplegable:

- Service container de Postgres en los dos jobs de `turnos-backend-ci.yml` (§6).
- Servicio `postgres` real en `docker-compose.yml`, con volumen nombrado y healthcheck (§1).
- El volumen/lógica de `dev.sqlite3` sacado por completo del `Dockerfile` (ya no aplica: con
  Postgres real, la imagen no persiste ningún archivo de base de datos local).
- `DATABASE_URL` documentada en `.env.example` (reemplazando a `DB_PATH`, §3) y en
  `render.yaml`/§10 para un despliegue real.

**Lo que este ciclo NO puede confirmar por sí solo.** Ninguno de estos cambios se verificó
contra un Postgres real en este entorno de desarrollo (sigue sin tener Docker instalado, ver
§0/§5) — la primera verificación real ocurre en el próximo run de GitHub Actions, sobre un
push que junte el driver nuevo de Backend con esta infraestructura. **Hasta que ese run no
esté en verde, este gap se considera cerrado en código pero NO confirmado** — no lo doy por
resuelto sin más solo porque las piezas ya están escritas.

**Tampoco puedo confirmar si el driver `pg` ya viene acompañado de la conexión de Row Level
Security** (`SET LOCAL app.negocio_id` / `app.usuario_id` por transacción autenticada — la
segunda mitad del gap original). Como ya señaló CTO IA (`memory/proyectos/turnos-profesionales/decisiones.md`,
"Decisiones de planificación de producción"), migrar el driver y conectar RLS son una sola
decisión, no dos tareas independientes: el DDL de
`../05-codigo/database/migrations/001_init.sql` se puede aplicar igual sin romper nada (las
políticas simplemente no tienen efecto todavía sin la variable de sesión seteada — fail
closed para escrituras si alguna vez se fuerza), pero si Backend migró el driver SIN
conectar `SET LOCAL app.*` todavía, la RLS diseñada sigue sin ninguna barrera real por
detrás. No es algo que DevOps pueda verificar ni decidir por su cuenta — **confirmar
explícitamente con Backend/QA** antes de dar este punto por completamente cerrado, no
asumir ninguna de las dos respuestas.

### Por qué este gap era explícitamente bloqueante antes de cualquier despliegue real (contexto que se mantiene)

- `node:sqlite` no estaba pensado para cargas concurrentes de producción ni para escalar
  horizontalmente (es un archivo único; con múltiples réplicas del contenedor, cada una
  tendría su propia copia si no comparten el volumen, y aun compartiéndolo, SQLite no está
  diseñado para escrituras concurrentes desde múltiples procesos con el nivel de
  paralelismo que se espera de una API multi-tenant real).
- Row Level Security — la segunda barrera de aislamiento multi-tenant documentada en
  `documento-arquitectura.md` §5 — no tenía ningún efecto sin Postgres de por medio. El
  aislamiento multi-tenant seguía dependiendo enteramente de la lógica de cada route
  handler (ya remediada y probada — ver CRITICAL-1 en el informe de Security), sin la
  segunda capa de defensa que el diseño original contempla — ver el párrafo de arriba sobre
  por qué esto todavía no está 100% confirmado como cerrado.

## 8. Registro de este ciclo (motivo, cambios, rollback)

### Ciclo 1 (2026-08-05)

- **Motivo:** QA y Security cerraron la Fase 5 de forma independiente (hallazgos
  bloqueantes remediados, ver `../05-codigo/backend/README.md`); correspondía a DevOps
  preparar contenerización y CI/CD (Fase 6) para dejar el backend listo para desplegarse
  apenas exista un destino real y se apruebe.
- **Cambios incluidos:** 5 archivos (Dockerfile, .dockerignore, docker-compose.yml,
  .env.example, workflow de CI), más un ajuste menor de higiene en
  `../05-codigo/backend/.gitignore` (excluir `.env` real mientras se mantiene
  `.env.example` versionado) y este mismo documento.
- **No se modificó ningún entregable de código de Backend/QA/Security** ya aprobado — el
  hallazgo del entrypoint (`dist/src/index.js`, §2) se resolvió a nivel de imagen, sin
  tocar `package.json`/`tsconfig.json`/`src/`.
- **Forma de rollback:** ese ciclo no publicó ningún entorno, así que no había nada que
  revertir todavía.

### Ciclo 2 (2026-08-07) — migración a PostgreSQL (driver de Backend + infraestructura de DevOps)

- **Motivo:** el CEO aprobó Render/Railway (PostgreSQL gestionado) para producción. Backend
  migró el driver de acceso a datos de `node:sqlite` a `pg` en paralelo a este ciclo,
  coordinado explícitamente (mismo push, ver §0) — correspondía a DevOps actualizar la
  infraestructura que hasta ahora reflejaba a propósito el estado anterior (`node:sqlite`,
  ver §7) para que la migración sea verificable en CI y desplegable en Render.
- **Cambios incluidos:** `.github/workflows/turnos-backend-ci.yml` (service container de
  Postgres en los dos jobs), `../05-codigo/backend/docker-compose.yml` (servicio `postgres`
  nuevo), `../05-codigo/backend/Dockerfile` (saca el volumen/lógica de `dev.sqlite3`),
  `../05-codigo/backend/.dockerignore` (comentario actualizado, mismo motivo),
  `../05-codigo/backend/.env.example` (`DATABASE_URL` en vez de `DB_PATH`),
  `../05-codigo/backend/render.yaml` (nuevo — Blueprint de Render, ver §10), y este
  documento (§0, §1, §3, §6, §7, §9, §10).
- **No se modificó ningún entregable de código de Backend** — ni `src/`, ni
  `package.json`, ni los `migrations/*.sql` (ni los de `../05-codigo/backend/migrations/`
  ni `../05-codigo/database/migrations/001_init.sql`). Backend migró el driver por su
  cuenta, en paralelo; este ciclo solo tocó configuración/infraestructura.
- **No verificado localmente** (sigue sin haber Docker en este entorno, ver §0/§5) — la
  verificación real es el próximo run de GitHub Actions en verde (ver §7). El YAML de los
  3 archivos tocados (workflow, docker-compose.yml, render.yaml) sí se validó
  sintácticamente con un parser real (`js-yaml`), no solo a simple vista — mismo criterio
  que el ciclo 1.
- **Forma de rollback:** este ciclo tampoco publica ningún entorno real (ver §0). Si el
  push coordinado con Backend deja el CI en rojo:
  - Revertir es seguro y de bajo riesgo: son cambios de configuración/infraestructura, no
    hay datos de producción todavía en juego (ningún servicio de Render/Railway
    aprovisionado aún).
  - Si el problema es específico de la infraestructura (no del driver de Backend), el
    `Dockerfile`/`docker-compose.yml`/workflow de CI del ciclo 1 (`node:sqlite`) siguen
    siendo el último estado conocido-bueno al que volver mientras se corrige, sin bloquear
    a Backend de seguir iterando su parte por separado.
  - Una vez que exista un despliegue real en Render: rollback = volver a desplegar la
    imagen/revisión anterior conocida-buena desde el dashboard de Render (o
    `kubectl rollout undo` si en el futuro se orquesta con Kubernetes vía
    `infra/kubernetes/`) — nunca editar en caliente el servicio corriendo. El Postgres
    gestionado de Render tiene un ciclo de vida independiente del código/imagen — un
    rollback de código no revierte por sí solo cambios de datos o de esquema; una
    migración que necesite ser reversible se escribe explícitamente así, no se asume.
  - Ningún rollback, igual que ningún forward-deploy, ocurre sin aprobación previa (ver
    reglas de actuación del rol DevOps y `docs/04-manual-operativo.md`).

## 9. Checklist antes de un despliegue real a producción

- [x] Corregir el desajuste de `package.json` (`main`/`start` → `dist/src/index.js`, §2) —
      resuelto en `memory/proyectos/turnos-profesionales/decisiones.md`, "Cierre del
      hallazgo de `package.json` (Director General IA, 2026-08-06)". Este checklist nunca
      se había actualizado para reflejarlo — corregido ahora (2026-08-07), sin relación con
      la migración de Postgres.
- [ ] **Migrar el acceso a datos de `node:sqlite` a PostgreSQL (Backend)** — driver `pg` +
      `DATABASE_URL` migrado en paralelo a este ciclo (2026-08-07, ver §7). Infraestructura
      (CI/docker-compose/Dockerfile) ya actualizada en este mismo ciclo.
  - [ ] **Confirmar con un run de GitHub Actions en verde** (`build-and-test` +
        `docker-build-smoke`, ambos con su service container de Postgres, ver §6) que la
        migración funciona de punta a punta — no confirmado todavía, ver §7.
  - [ ] **Confirmar explícitamente con Backend/QA si `SET LOCAL app.negocio_id`/
        `app.usuario_id` ya está conectado** junto con el driver, para que la Row Level
        Security ya diseñada (`../03-arquitectura/modelo-datos.md` §5) tenga efecto real —
        DevOps no puede confirmar esto por su cuenta (ver §7).
  - [x] Revisar/actualizar `Dockerfile`/`docker-compose.yml`/CI para el nuevo driver
        (servicio `postgres:`, `DATABASE_URL`, quitar el volumen sqlite) — hecho en este
        ciclo (2026-08-07).
- [ ] Aprovisionar de verdad el servicio en Render (o Railway) — hoy solo existe
      `render.yaml` como Blueprint sin aplicar (§10); ningún agente de IA puede crear la
      cuenta ni cargar el método de pago, requiere al CEO.
- [ ] Configurar a mano en el dashboard del proveedor elegido las variables que
      `render.yaml` no resuelve solo (ver §10): confirmar que `JWT_SECRET` generado y
      `ENABLE_DEV_ROUTES=false` quedaron como se espera, y cualquier variable opcional que
      se quiera distinta del default de la aplicación (rate limits, ventanas, etc., §3).
- [ ] Si el proveedor elegido NO es Render (ej. Railway), no hay Blueprint equivalente
      todavía — cargar las variables de §3 a mano en su gestor de configuración.
- [ ] Definir un registry de imágenes y una convención de tags inmutable **solo si el
      proveedor elegido lo requiere** — Render específicamente buildea la imagen directo
      desde el Dockerfile del repo en cada deploy (ver §10), sin necesitar un registry
      externo propio.
- [ ] Decidir si el destino es Kubernetes (`infra/kubernetes/` en la raíz del repo, hoy
      vacío) o algún otro orquestador, y escribir los manifiestos correspondientes — no
      hace falta si el destino es un PaaS como Render/Railway (§10), que no lo requieren.
- [ ] Configurar `cors` con allowlist explícita el día que se sume un frontend web (LOW-1
      de Security, no bloqueante hoy porque el consumo actual es mobile nativo +
      `web-preview/` same-origin, que de todos modos no viaja en esta imagen).
- [ ] Pipeline de CI en verde (`build-and-test` + `docker-build-smoke`) sobre el commit
      exacto que se va a desplegar.
- [ ] Aprobación explícita del Director General IA / CEO — ningún cambio llega a
      producción sin ella.

## 10. Desplegar en Render

El CEO aprobó Render/Railway (§0). Esta sección documenta Render en concreto (recomendación
de CTO IA, `../03-arquitectura/plan-produccion.md` §6); si en cambio se elige Railway, la
lógica de variables de entorno (§3) es la misma, pero no hay `render.yaml` equivalente para
Railway en este repo todavía — hay que cargar las variables a mano en su dashboard.

**Nada de esto se ejecutó todavía** — ningún agente de IA puede crear una cuenta de Render
ni cargar un método de pago (mismo tipo de límite que ya aplica a las cuentas de tiendas de
apps, ver `../03-arquitectura/plan-produccion.md` §8). Lo que sigue es el instructivo para
que el CEO (o DevOps, con las credenciales del CEO) lo ejecute cuando corresponda, con
aprobación previa.

### Opción A — con el Blueprint (`render.yaml`), recomendada

1. Generar un `JWT_SECRET` no hace falta hacerlo a mano — el Blueprint lo genera solo (ver
   más abajo). Sí hace falta tener a mano el repositorio conectado a una cuenta de GitHub
   con acceso desde Render.
2. En el dashboard de Render: **New → Blueprint**, conectar este repositorio.
   `../05-codigo/backend/render.yaml` **no está en la raíz del repo** (este repo es un
   monorepo de toda la AI Software Factory, ver §0) — si Render no lo detecta solo,
   indicarle explícitamente la ruta
   `proyectos/turnos-profesionales/05-codigo/backend/render.yaml` en ese paso (la opción
   exacta puede variar — ver la advertencia al principio del propio `render.yaml` sobre
   verificar contra la documentación vigente de Render).
3. Revisar el plan propuesto para la base (`turnos-profesionales-db`) y el servicio web
   (`turnos-profesionales-backend`) **antes de aplicar** — en particular el campo `plan` de
   ambos recursos (el Blueprint fija `starter` en los dos; confirmar que ese nombre de plan
   siga vigente y el costo mensual contra `../03-arquitectura/plan-produccion.md` §6, no
   usar el free tier de Postgres: expira a los 30 días).
4. Aplicar el Blueprint. Render crea la base, la deja lista, y crea el servicio web **sin
   deployar todavía** (`autoDeploy: false`, a propósito — ver el comentario en el propio
   `render.yaml`: ningún cambio llega a producción sin aprobación previa).
5. Con los recursos creados, revisar en el dashboard del servicio web que las variables de
   entorno hayan quedado como se espera: `DATABASE_URL` (resuelta sola desde la base
   conectada), `JWT_SECRET` (generado solo, valor oculto), `PORT=3000`,
   `ENABLE_DEV_ROUTES=false`. Si se quiere un valor no-default para
   `EXPIRACION_PAGO_MIN`/`VENTANA_CANCELACION_MIN`/`RATE_LIMIT_*` (§3), agregarlo a mano acá.
6. Recién con eso revisado y con aprobación explícita del Director General IA/CEO, disparar
   el primer deploy manual desde el dashboard.
7. Verificar `GET https://<url-de-render>/health` y correr
   `BASE_URL=https://<url-de-render> node scripts/smoke-test.mjs` (ajustar el script si
   `BASE` sigue hardcodeado a `localhost`, ver la recomendación de CTO IA en
   `../03-arquitectura/plan-produccion.md` §7, paso 5) antes de considerar el despliegue
   verificado.

### Opción B — a mano, sin Blueprint (si se prefiere no usar `render.yaml` todavía)

1. **New → PostgreSQL** en Render. Elegir un plan pago (no el free tier, expira a los 30
   días — ver `../03-arquitectura/plan-produccion.md` §6). Anotar la `Internal Database
   URL` que Render genera — **no hay que armarla a mano**, Render la provee.
2. **New → Web Service**, conectar este repositorio, apuntando el `Root Directory` (o
   equivalente en la UI vigente de Render) a
   `proyectos/turnos-profesionales/05-codigo/backend` — este repo es un monorepo (§0), no
   asumir que la raíz del repo es la raíz del servicio.
3. Runtime: **Docker** (Render detecta el `Dockerfile` de ese directorio). Health check
   path: `/health`.
4. Variables de entorno del servicio (ver tabla completa en §3):
   - `DATABASE_URL`: pegar la que generó el paso 1 (o conectarla desde el propio flujo de
     Render si ofrece un selector de base existente — varía según la versión de la UI).
   - `JWT_SECRET`: generar un valor propio fuerte y pegarlo (`openssl rand -base64 48`),
     **nunca** commitear este valor en ningún archivo del repo.
   - `PORT`: `3000`.
   - `ENABLE_DEV_ROUTES`: `false` (o no declararla — ausente equivale a `false`, pero
     declararla explícita deja la decisión visible, ver §3).
   - Opcionalmente `EXPIRACION_PAGO_MIN`/`VENTANA_CANCELACION_MIN`/`RATE_LIMIT_*` si se
     quiere un valor distinto al default de la aplicación.
5. **Desactivar auto-deploy** en la configuración del servicio (equivalente manual del
   `autoDeploy: false` del Blueprint) — ningún cambio llega a producción sin aprobación
   previa (`docs/04-manual-operativo.md`).
6. Con todo revisado y aprobado, disparar el primer deploy manual. Verificar igual que en
   la Opción A, paso 7.
