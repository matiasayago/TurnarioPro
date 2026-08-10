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

**Ciclo 3 (2026-08-09/10) — separación de roles de Postgres (cierre de gap CRITICAL,
TURNOS-2026-001), coordinado con DBA y Security.** DBA cerró la mayor parte de un hallazgo
Critical: el rol único de conexión a Postgres de cada ambiente es owner de las tablas y, en
docker-compose/CI, además superusuario del cluster (así lo crea la imagen oficial
`postgres:16-alpine` vía `POSTGRES_USER`) — un superusuario bypassea Row Level Security
siempre, incluso con `FORCE ROW LEVEL SECURITY` (capa 1, ya aplicada por DBA a las 5 tablas con
RLS en `../05-codigo/database/migrations/001_init.sql`). La capa 2 —separar un rol de
MIGRACIÓN (owner, corre el DDL una sola vez) de un rol de RUNTIME (sirve el tráfico de la app,
sin ser owner y sin BYPASSRLS)— es la tarea de este ciclo, ejecutada con
`../05-codigo/database/scripts/provisionar_roles_postgres.sql` (DBA):

- `../05-codigo/backend/docker-compose.yml` — el servicio `postgres` provisiona ambos roles
  automáticamente la primera vez que su volumen está vacío (2 scripts nuevos en
  `../05-codigo/backend/docker/postgres-initdb/`, vía el mecanismo estándar
  `docker-entrypoint-initdb.d/` de la imagen oficial) y migra el esquema con el rol de
  MIGRACIÓN antes de que `backend` pueda arrancar (`depends_on: condition: service_healthy`
  se cumple recién después). `DATABASE_URL` del servicio `backend` pasa a apuntar al rol de
  RUNTIME.
- `../../../.github/workflows/turnos-backend-ci.yml` — mismo patrón en los dos jobs
  (`build-and-test` y `docker-build-smoke`, cada uno con su propio service container de
  Postgres efímero): 5 pasos nuevos justo después de `Checkout` ("Roles Postgres 0/4"-"4/4" —
  asegurar `psql`, provisionar roles, migrar como el rol de MIGRACIÓN, completar GRANTs, y
  correr `../05-codigo/database/scripts/verificar_rls_postgres.sql` contra el service
  container real) antes de que el resto del job use `DATABASE_URL`/`docker run -e
  DATABASE_URL`, que también pasan a apuntar al rol de RUNTIME. Ver §6 para el detalle.
- `../05-codigo/backend/render.yaml` — sin cambio funcional (no se puede verificar ni aplicar
  contra una cuenta real de Render desde este entorno, misma limitación de siempre, ver §0/§5);
  se agregó documentación de qué chequear antes de asumir que ese ambiente necesita la misma
  separación — ver §10.
- Este documento (§1, §3, §6, §8, §9, §10).

**No se tocó código de Backend** (`src/`, incluido `db.ts`) — instrucción explícita del
Director General IA. `runMigrations()` sigue funcionando sin ningún cambio de código: ya
estaba gateada por "¿existe la tabla `usuario`?" (`SELECT to_regclass('public.usuario')`), así
que cuando el proceso de `backend` arranca (con `DATABASE_URL` ya apuntando al rol de RUNTIME)
el esquema ya fue migrado por el paso separado correspondiente (docker-entrypoint-initdb.d en
docker-compose, o los pasos "Roles Postgres */4" en CI) y ese chequeo da `true` — no vuelve a
intentar el DDL, que de todos modos fallaría con el rol de RUNTIME (sin privilegios de
`CREATE`). Detalle completo de esta tensión (y de por qué no se resolvió tocando `db.ts`) en
`../03-arquitectura/modelo-datos.md` §5bis y en los comentarios de
`../05-codigo/database/migrations/001_init.sql`.

**No verificado con un run real de GitHub Actions todavía** (mismo tipo de limitación que el
resto de este documento, ver §5) — sí se revisó línea por línea contra la documentación de
Postgres/psql/Docker (semántica de `docker-entrypoint-initdb.d/`, de `SET ROLE`, de
`ON_ERROR_STOP`, de `ALTER DEFAULT PRIVILEGES`, de por qué `CREATE EXTENSION pgcrypto` no
necesita superusuario desde Postgres 13 al estar marcada `trusted`), y el YAML de los 3
archivos tocados (`docker-compose.yml`, `turnos-backend-ci.yml`, `render.yaml`) y la sintaxis
`sh`/`bash` de los 4 scripts nuevos se validaron con parsers reales (`js-yaml`, `sh -n`/
`bash -n`) — no solo a simple vista. La primera confirmación real es el próximo run de GitHub
Actions en verde, en particular el paso "Roles Postgres 4/4" (`verificar_rls_postgres.sql`) de
cada job — si sale rojo, es información real (puede revelar algo enmascarado hasta ahora por el
bypass total de RLS, ver el comentario de ese script), no se debe ocultar ni forzar en verde.

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

**Separación de roles de Postgres (2026-08-09/10, ver §0 "Ciclo 3").** La primera vez que
`docker compose up` corre contra el volumen `turnos_postgres_data` vacío, el servicio
`postgres` provisiona automáticamente un rol de MIGRACIÓN y un rol de RUNTIME (2 scripts en
`docker/postgres-initdb/`, vía `docker-entrypoint-initdb.d/`) y migra el esquema con el rol de
MIGRACIÓN — todo esto termina ANTES de que el healthcheck de `postgres` pueda pasar, así que
`backend` nunca arranca contra una base a medio provisionar. No hace falta ningún paso manual
adicional: `docker compose up --build` sigue siendo el único comando. Si algo sale mal en este
proceso (ej. se corrige un typo en los scripts de provisión después de un primer intento
fallido), hay que recrear el volumen para que vuelva a correr desde cero — `docker compose down
-v` (**borra los datos**, aceptable en desarrollo local) seguido de `docker compose up --build`
de nuevo; `docker-entrypoint-initdb.d/` no se re-ejecuta sobre un volumen que ya tiene datos.

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
| `DATABASE_URL` | **Sí** | — (sin default; `src/db.ts` necesita un Postgres real) | Formato `postgresql://usuario:password@host:puerto/basededatos`. **En Render, la provee el proveedor solo** al conectar su addon de Postgres — nunca se arma a mano ahí (ver §10; pendiente de verificar ahí si ese rol necesita la separación de roles del párrafo siguiente, ver `render.yaml`). **En docker-compose, ya viene fijada en `docker-compose.yml`** apuntando al servicio `postgres` por su nombre de red interno de Compose — no hace falta (ni corresponde) completarla en `.env` para ese flujo. Solo se completa a mano en `.env`/`docker run` para el modo standalone (§1) o para apuntar a un Postgres externo. **Debe apuntar al rol de RUNTIME, nunca al de MIGRACIÓN ni a un superusuario** (separación de roles 2026-08-09/10, ver §0 "Ciclo 3" y §1) — necesario para que Row Level Security (`../03-arquitectura/modelo-datos.md` §5/§5bis) tenga efecto real. |
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
   container `postgres:16-alpine`** (credenciales de test fijas, no secretas — el rol de
   bootstrap `turnos_ci`, ver comentarios del propio workflow) — GitHub Actions espera a que
   su healthcheck (`pg_isready`) esté en verde antes de dejar correr el primer step, así que
   no hace falta ningún paso propio de espera.
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

**Separación de roles de Postgres + verificación de RLS (2026-08-09/10, ver §0 "Ciclo 3").**
`POSTGRES_USER=turnos_ci` de cada service container es superusuario del cluster (mismo motivo
que en docker-compose, ver §1) — ambos jobs agregan ahora, apenas después de `Checkout`, los
pasos **"Roles Postgres 0/4"–"4/4"**: aseguran que `psql` esté disponible en el runner
(`ubuntu-latest` ya lo trae; el paso instala `postgresql-client` solo si faltara), provisionan
un rol de MIGRACIÓN y un rol de RUNTIME (`../05-codigo/database/scripts/
provisionar_roles_postgres.sql`, DBA) conectándose por TCP a `localhost:5432` (a diferencia de
docker-compose, un service container de Actions no tiene el repo disponible cuando arranca, así
que el mecanismo `docker-entrypoint-initdb.d/` que usa `docker-compose.yml` no aplica acá),
migran el esquema con el rol de MIGRACIÓN (`../05-codigo/database/migrations/001_init.sql`), y
por último corren **`../05-codigo/database/scripts/verificar_rls_postgres.sql`** (Security)
contra el service container real
— la única forma de confirmar que Row Level Security filtra de verdad, no solo que el DDL
compila. Recién después de esos 5 pasos, `DATABASE_URL` (job `build-and-test`) y `docker run -e
DATABASE_URL` (job `docker-build-smoke`) apuntan al rol de RUNTIME ya provisionado. Si el paso
"Roles Postgres 4/4" sale rojo, es información real y valiosa — puede revelar algo que estuvo
enmascarado hasta ahora por el bypass total de RLS (ver el comentario de ese script) — no se
debe ocultar ni forzar en verde sin entender la causa.

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

### Ciclo 3 (2026-08-09/10) — separación de roles de Postgres (cierre de gap CRITICAL, TURNOS-2026-001)

- **Motivo:** DBA cerró la mayor parte de un hallazgo Critical de seguridad (confirmado de
  forma independiente por Security): el rol único de conexión a Postgres de cada ambiente es
  owner de las tablas que crea `runMigrations()` y, en docker-compose/CI, además superusuario
  del cluster — un superusuario bypassea Row Level Security siempre, incluso con `FORCE ROW
  LEVEL SECURITY` (que DBA ya aplicó, capa 1 del arreglo). La capa 2 —separar un rol de
  MIGRACIÓN de un rol de RUNTIME— es la única forma de que RLS tenga efecto real en
  docker-compose y en CI, y correspondía a DevOps ejecutarla (infraestructura/CI/CD).
- **Cambios incluidos:** `../05-codigo/backend/docker-compose.yml` (env vars/volumes nuevos del
  servicio `postgres`, `DATABASE_URL` de `backend` repuntada al rol de RUNTIME),
  `../05-codigo/backend/docker/postgres-initdb/01-provisionar-roles.sh` y
  `02-migrar-y-grants-finales.sh` (nuevos), `../../../.github/workflows/turnos-backend-ci.yml`
  (5 pasos nuevos por job, `DATABASE_URL`/`docker run -e DATABASE_URL` repuntados),
  `../05-codigo/backend/render.yaml` (solo documentación, sin cambio funcional), y este
  documento (§0, §1, §3, §6, §8, §9, §10).
- **No se modificó ningún entregable de código de Backend** — ni `src/`, ni `db.ts`, ni
  `package.json`. Tampoco se modificó ningún archivo de DBA
  (`../05-codigo/database/migrations/001_init.sql`,
  `../05-codigo/database/scripts/provisionar_roles_postgres.sql`,
  `../05-codigo/database/scripts/verificar_rls_postgres.sql`) — todos se invocan tal cual desde los
  scripts/pasos nuevos de este ciclo, sin editarlos.
- **Hallazgo propio de este ciclo, no atribuible a DBA:** el ejemplo de invocación del
  encabezado de `provisionar_roles_postgres.sql` (`-v migrador_password="'CAMBIAR_1'"`)
  duplicaría la cita SQL si se usa literal junto con `:'migrador_password'` del cuerpo del
  script (que ya cita/escapa el valor) — guardaría una contraseña con comillas literales de
  más, rompiendo la reconexión posterior con el valor limpio. Los scripts/pasos de este ciclo
  pasan las contraseñas crudas (sin comillas extra) — ver el comentario en
  `../05-codigo/backend/docker/postgres-initdb/01-provisionar-roles.sh` para el detalle. No se
  modificó el archivo de DBA (es solo un comentario de ejemplo, no afecta el SQL ejecutable) —
  reportado acá para
  que quien lo use manualmente en el futuro (ver la "SECUENCIA COMPLETA DE ADOPCIÓN" de ese
  script) no repita la doble cita.
- **Tampoco tenía `CREATE` sobre el esquema `public` el rol de MIGRACIÓN** en
  `provisionar_roles_postgres.sql` tal cual — desde Postgres 15, ese privilegio ya no se le
  otorga a PUBLIC por defecto, y no se hereda a un rol nuevo por ser owner de la base. Sin él,
  el rol de MIGRACIÓN no podría correr `CREATE TABLE`/`CREATE TYPE`/`CREATE EXTENSION` de
  `001_init.sql`. Resuelto con un `GRANT CREATE ON SCHEMA public TO <rol de MIGRACIÓN>;`
  adicional, propio de este ciclo (no de DBA), en el primer paso de provisión de roles de cada
  ambiente — ver el mismo comentario referenciado arriba.
- **No verificado con Docker/GitHub Actions real** (mismo tipo de limitación que el resto de
  este documento, ver §0/§5) — verificación de este ciclo: revisión línea por línea contra la
  documentación de Postgres/psql/Docker, y validación sintáctica con parsers reales (`js-yaml`
  para los 3 YAML tocados, `sh -n`/`bash -n` para los 4 scripts nuevos). La confirmación real es
  el próximo run de GitHub Actions en verde — en particular el paso "Roles Postgres 4/4" de
  cada job, que corre `verificar_rls_postgres.sql` (Security) contra el service container real.
- **Forma de rollback:** este ciclo tampoco publica ningún entorno real (ver §0). Si el próximo
  run de CI queda en rojo por estos cambios:
  - Revertir es seguro y de bajo riesgo: son cambios de configuración/infraestructura más 2
    scripts nuevos, sin ningún dato de producción en juego (ningún servicio de Render/Railway
    aprovisionado aún) y sin tocar código de aplicación.
  - El estado anterior a este ciclo (rol único `turnos`/`turnos_ci`, sin separación de roles)
    sigue siendo funcionalmente equivalente para todo lo que no sea RLS — `runMigrations()`
    seguía corriendo igual, solo que sin que `FORCE ROW LEVEL SECURITY` tuviera efecto real (ver
    el motivo de este ciclo, arriba). Volver a ese estado es tan simple como revertir
    `docker-compose.yml`/`turnos-backend-ci.yml` a la revisión anterior — no requiere ningún
    cambio de datos ni de esquema.
  - Una vez que exista un despliegue real en Render, mismo criterio de rollback documentado en
    el Ciclo 2 (volver a desplegar la revisión anterior conocida-buena desde el dashboard, nunca
    editar en caliente).
  - Ningún rollback, igual que ningún forward-deploy, ocurre sin aprobación previa (ver reglas
    de actuación del rol DevOps y `docs/04-manual-operativo.md`).

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
- [x] **Separar un rol de MIGRACIÓN de un rol de RUNTIME en docker-compose.yml y en CI**
      (2026-08-09/10, ver §0 "Ciclo 3") — cierra que `FORCE ROW LEVEL SECURITY` (ya aplicado en
      `../05-codigo/database/migrations/001_init.sql`) no tenía ningún efecto real en esos 2
      ambientes porque el único rol existente ahí es superusuario del cluster. Ver §1/§6 para
      el detalle.
  - [ ] **Verificar separación de roles de Postgres en Render antes de confiar en RLS ahí** —
        conectado con el rol que usaría `DATABASE_URL` en ese ambiente, correr `SELECT
        rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;` (ver el comentario
        grande al principio de `render.yaml`, §10, y `../05-codigo/database/scripts/
        provisionar_roles_postgres.sql`, DBA). Si alguna de las 2 columnas da `true`, aplicar
        ahí la misma separación de roles antes de considerar cerrado el gap de RLS en
        producción — no asumir que alcanza con `FORCE ROW LEVEL SECURITY` solo. No verificable
        desde este entorno de desarrollo (sin cuenta real de Render, ver §0/§5).
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
6. **Verificar separación de roles de Postgres antes de confiar en Row Level Security acá**
   (2026-08-09/10 — ver el comentario grande al principio de `render.yaml` y §0 "Ciclo 3").
   Con la "Internal/External Database URL" que Render ya provee para la base creada en el
   paso 4 (el rol único `turnos_profesionales` que declara `databases:` en `render.yaml`),
   conectarse (`psql`) y correr:

   ```sql
   SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;
   ```

   - Si **ambas** columnas dan `false`: `FORCE ROW LEVEL SECURITY` (ya aplicado en
     `../05-codigo/database/migrations/001_init.sql`) alcanza solo en este ambiente — es el
     resultado esperado para un Postgres gestionado, pero no se debe asumir sin correr la
     query. No hace falta ningún cambio más para RLS acá.
   - Si **cualquiera** de las 2 da `true`: aplicar la misma separación de roles que
     `docker-compose.yml`/CI antes de dar por cerrado el gap de RLS en producción — ver
     `../05-codigo/database/scripts/provisionar_roles_postgres.sql` (DBA) para los GRANTs
     exactos y la
     sección "Nota para Render específicamente" de ese mismo script para por qué esto
     requiere conectarse a mano (el Blueprint solo provisiona un rol por base) y reemplazar
     cómo se resuelve `DATABASE_URL` del paso 5 (deja de poder usar
     `fromDatabase: { property: connectionString }`).
7. Recién con eso revisado y con aprobación explícita del Director General IA/CEO, disparar
   el primer deploy manual desde el dashboard.
8. Verificar `GET https://<url-de-render>/health` y correr
   `BASE_URL=https://<url-de-render> node scripts/smoke-test.mjs` (ajustar el script si
   `BASE` sigue hardcodeado a `localhost`, ver la recomendación de CTO IA en
   `../03-arquitectura/plan-produccion.md` §7, paso 5) antes de considerar el despliegue
   verificado. Considerar además correr
   `../05-codigo/database/scripts/verificar_rls_postgres.sql`
   (Security) contra esta base — la única forma de confirmar que RLS filtra de verdad en
   producción, no solo que el DDL compiló.

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
6. **Verificar separación de roles de Postgres** — mismo chequeo que la Opción A, paso 6
   (`SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;`, conectado con
   el rol que generó el paso 1 de acá), antes de confiar en Row Level Security en este ambiente.
7. Con todo revisado y aprobado, disparar el primer deploy manual. Verificar igual que en
   la Opción A, paso 8.
