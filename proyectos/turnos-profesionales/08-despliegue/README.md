# Despliegue — Turnos Profesionales (TURNOS-2026-001)

**Rol:** DevOps
**Fase:** 6 — Despliegue
**Entradas:** QA (`../06-qa/reporte-qa.md`) y Security (`../07-seguridad/informe-seguridad.md`),
ambos cerrados, con los hallazgos bloqueantes ya remediados (ver
`../05-codigo/backend/README.md`, secciones "Fase 5" y "Ciclo 2").

## 0. Alcance de este ciclo

Este ciclo entrega **artefactos de contenerización y CI/CD** para el backend
(`../05-codigo/backend/`):

- `../05-codigo/backend/Dockerfile`
- `../05-codigo/backend/.dockerignore`
- `../05-codigo/backend/docker-compose.yml`
- `../05-codigo/backend/.env.example`
- `../../../.github/workflows/turnos-backend-ci.yml` (raíz del repo, donde vive Git)

**No publica ningún entorno real.** No hay todavía un servidor/cluster/proveedor cloud
designado para este proyecto y, de todos modos, ningún cambio llega a producción sin
aprobación previa (principio operativo de la empresa, ver `docs/04-manual-operativo.md`,
y las reglas de actuación del rol DevOps). Lo que sí queda listo: la imagen se puede
buildear y correr apenas se decida un destino, y el pipeline de CI corre automáticamente
en cada push/PR que toque este backend — incluido un job que construye y prueba la
imagen Docker de verdad (ver §6).

Nota sobre el entorno de desarrollo de DevOps: **no tiene Docker instalado.** No se pudo
correr `docker build`/`docker compose up` para verificar este trabajo de la misma forma en
que DBA no pudo verificar las políticas de Row Level Security contra un Postgres real (ver
`../03-arquitectura/modelo-datos.md` §5). La sección 5 de este documento detalla
exactamente qué se validó igual (con Node real, sin Docker) y qué queda pendiente.

## 1. Cómo buildear y correr con Docker

### Standalone

```bash
cd proyectos/turnos-profesionales/05-codigo/backend
docker build -t turnos-profesionales-backend:local .
docker run -d --name turnos-backend -p 3000:3000 \
  -e JWT_SECRET="$(openssl rand -base64 48)" \
  -v turnos_backend_data:/data \
  turnos-profesionales-backend:local
curl http://localhost:3000/health
```

### Con docker-compose (recomendado para desarrollo/staging local)

```bash
cd proyectos/turnos-profesionales/05-codigo/backend
cp .env.example .env        # completar JWT_SECRET — ver los comentarios en ese archivo
docker compose up --build
```

El servicio `backend` expone el puerto 3000 (configurable vía `PORT` en `.env`), monta un
volumen nombrado (`turnos_backend_data`) en `/data` para persistir el archivo sqlite entre
reinicios/recreaciones del contenedor, y lee el resto de la configuración desde `.env`
(nunca commiteado — ver `.gitignore`/`.dockerignore` del backend).

`docker-compose.yml` **no incluye un servicio de PostgreSQL.** Agregarlo hoy sería un
espejismo — ver §7 para el porqué.

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

**No corregí `package.json` yo mismo:** es un entregable de Backend ya validado por
QA/Security, y las reglas de actuación de DevOps piden no modificar entregables aprobados
sin autorización del Director General IA. Lo resolví enteramente a nivel de imagen
(Dockerfile), sin tocar código fuente. **Queda reportado como defecto menor para que
Backend corrija en un próximo ciclo** (`main`/`start` → `dist/src/index.js`, o alternativamente
`tsconfig.json` con `rootDir: "src"` si prefieren aplanar la salida de `dist/`).

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
| `JWT_SECRET` | **Sí, en producción** (`NODE_ENV=production`, ya fijado por el Dockerfile) | `dev-secret-not-for-production` (solo fuera de `NODE_ENV=production`) | El proceso **no arranca** en producción sin esto seteado (hallazgo HIGH-3, ya remediado en código). Nunca commitear el valor real — generarlo aparte (ej. `openssl rand -base64 48`) y gestionarlo vía secretos del entorno real cuando exista. |
| `PORT` | No | `3000` | También la usa `docker-compose.yml` para el mapeo de puertos host:contenedor. |
| `DB_PATH` | No | Junto al código (`dev.sqlite3`); en la imagen: `/data/dev.sqlite3`, fijado por el Dockerfile | Mantenerlo dentro de `/data` (el volumen nombrado) para no perder persistencia entre reinicios. |
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
esta imagen para cualquier entorno real.**

## 6. CI (GitHub Actions)

`.github/workflows/turnos-backend-ci.yml` (raíz del repo) corre en push/PR que toquen
`proyectos/turnos-profesionales/05-codigo/backend/**`, en dos jobs:

1. **`build-and-test`** — `npm ci`, `npx tsc --noEmit`, `npm run build`, y la batería
   completa de `scripts/*.mjs` contra `ts-node` (feedback rápido sobre tipos y lógica de
   negocio/seguridad, en los dos arranques de servidor que describe §5). Usa Node 22
   (`actions/setup-node@v4`), coherente con el `Dockerfile`.
2. **`docker-build-smoke`** (corre después de que el anterior pase) — construye la imagen
   Docker real a partir de este mismo `Dockerfile` y corre `scripts/smoke-test.mjs` contra
   un contenedor levantado en config "tipo producción" (`NODE_ENV=production`, el default
   de la imagen, sin `ENABLE_DEV_ROUTES`) — la validación más representativa de un
   despliegue real que se puede hacer sin desplegar de verdad.

## 7. BLOQUEANTE — gap `node:sqlite` → PostgreSQL antes de cualquier despliegue real

El backend implementado usa **`node:sqlite`** (built-in de Node, sin dependencias
nativas) para desarrollo — ver `../05-codigo/backend/README.md` y
`memory/proyectos/turnos-profesionales/decisiones.md`. La arquitectura documentada apunta
a **PostgreSQL** en producción (`../05-codigo/database/migrations/001_init.sql`), con Row
Level Security ya diseñada — ver **[`../03-arquitectura/modelo-datos.md`, sección 5
("Row Level Security (Postgres, producción)")](../03-arquitectura/modelo-datos.md)** —
pero **todavía sin conectar**.

**El código de la aplicación hoy SOLO sabe hablar con `node:sqlite`:** `src/db.ts` importa
`node:sqlite` directamente, y todas las queries de `src/routes/*.ts` están escritas contra
esa API (parametrizadas con `?`, sin ORM ni capa de abstracción intermedia). No existe
ningún driver de Postgres (`pg`, `postgres.js`, etc.) integrado, ni configuración de
connection pool, ni el `SET LOCAL app.negocio_id` / `app.usuario_id` que necesitan las
políticas RLS para tener efecto (documentado como pendiente tanto por DBA como por
Security — ver el hallazgo CRITICAL-1 de `../07-seguridad/informe-seguridad.md`, que
aclara explícitamente que RLS **no sustituye** corregir la resolución de `negocio_id` en
el JWT, que ya está remediada).

**Por eso este ciclo de DevOps refleja la realidad actual del código (`node:sqlite`), no
un setup de Postgres que la aplicación no soporta.** `docker-compose.yml` no incluye un
servicio `postgres:` — agregarlo hoy sería aparentar un soporte que no existe y generaría
una falsa sensación de progreso. Migrar el código de acceso a datos de `node:sqlite` a
Postgres (driver, pool de conexiones, adaptar cada query, conectar `SET LOCAL app.*` por
transacción autenticada) es **trabajo de Backend**, no de DevOps.

### Esto es explícitamente bloqueante antes de cualquier despliegue real a producción

- `node:sqlite` no está pensado para cargas concurrentes de producción ni para escalar
  horizontalmente (es un archivo único; con múltiples réplicas del contenedor, cada una
  tendría su propia copia si no comparten el volumen, y aun compartiéndolo, SQLite no está
  diseñado para escrituras concurrentes desde múltiples procesos con el nivel de
  paralelismo que se espera de una API multi-tenant real).
- Row Level Security — la segunda barrera de aislamiento multi-tenant documentada en
  `documento-arquitectura.md` §5 — **no tiene ningún efecto hoy** porque no hay Postgres
  de por medio. El aislamiento multi-tenant actual depende **enteramente** de la lógica de
  cada route handler (ya remediada y probada — ver CRITICAL-1 en el informe de
  Security — pero sin la segunda capa de defensa que el diseño original contempla).
- Cuando Backend migre el driver, este mismo `Dockerfile`/`docker-compose.yml` van a
  necesitar revisión (agregar servicio `postgres:`, variables `DATABASE_URL` o
  equivalentes, quitar el volumen sqlite, ajustar el `HEALTHCHECK` si pasa a depender de
  una conexión de base externa) — no son un artefacto "terminado para siempre", son
  correctos **para el estado actual del código**.

## 8. Registro de este ciclo (motivo, cambios, rollback)

- **Motivo:** QA y Security cerraron la Fase 5 de forma independiente (hallazgos
  bloqueantes remediados, ver `../05-codigo/backend/README.md`); correspondía a DevOps
  preparar contenerización y CI/CD (Fase 6) para dejar el backend listo para desplegarse
  apenas exista un destino real y se apruebe.
- **Cambios incluidos:** los 5 archivos listados en §0 (Dockerfile, .dockerignore,
  docker-compose.yml, .env.example, workflow de CI), más un ajuste menor de higiene en
  `../05-codigo/backend/.gitignore` (excluir `.env` real mientras se mantiene
  `.env.example` versionado) y este mismo documento.
- **No se modificó ningún entregable de código de Backend/QA/Security** ya aprobado — el
  hallazgo del entrypoint (`dist/src/index.js`, §2) se resolvió a nivel de imagen, sin
  tocar `package.json`/`tsconfig.json`/`src/`.
- **Forma de rollback:** este ciclo no publica ningún entorno (ver §0), así que no hay
  nada que revertir todavía. Para cuando exista un despliegue real:
  - Cada imagen debe etiquetarse de forma inmutable (por SHA de commit o versión
    semántica), nunca solo `:latest` — el workflow de CI de este ciclo usa el tag `:ci`
    solo para las pruebas efímeras del propio pipeline; un pipeline de publicación real
    (fuera de este ciclo, pendiente de un registry designado) debería etiquetar por
    commit/versión.
  - Rollback = volver a desplegar la imagen con el último tag conocido-bueno (`docker
    run`/`docker compose` apuntando a ese tag, o `kubectl rollout undo` si en el futuro se
    orquesta con Kubernetes vía `infra/kubernetes/` en la raíz del repo) — nunca editar en
    caliente el contenedor corriendo.
  - El volumen de datos (`turnos_backend_data` en `docker-compose.yml`) tiene un ciclo de
    vida independiente de la imagen — un rollback de imagen no borra ni migra datos por sí
    solo. Las migraciones actuales (`migrations/001_init.sqlite.sql`) son solo "hacia
    adelante"; si algún rollback futuro necesitara revertir un cambio de esquema, esa
    migración debe escribirse explícitamente de forma reversible (fuera de alcance de este
    ciclo).
  - Ningún rollback, igual que ningún forward-deploy, ocurre sin aprobación previa (ver
    reglas de actuación del rol DevOps y `docs/04-manual-operativo.md`).

## 9. Checklist antes de un despliegue real a producción

- [ ] **Bloqueante:** migrar el acceso a datos de `node:sqlite` a PostgreSQL (Backend) y
      conectar `SET LOCAL app.negocio_id`/`app.usuario_id` para que la Row Level Security
      ya diseñada (`../03-arquitectura/modelo-datos.md` §5) tenga efecto real.
  - [ ] Correr `../05-codigo/database/migrations/001_init.sql` contra un Postgres de
        prueba antes de un entorno real (nunca verificado, ver nota de DBA en ese mismo
        documento).
  - [ ] Revisar/actualizar este `Dockerfile`/`docker-compose.yml` para el nuevo driver
        (servicio `postgres:`, `DATABASE_URL`, quitar el volumen sqlite).
- [ ] Corregir el desajuste de `package.json` (`main`/`start` → `dist/src/index.js`, §2) —
      cosmético mientras el `Dockerfile` fije el `CMD` correcto a mano, pero vale la pena
      cerrarlo para que `npm start` funcione igual que en Docker.
- [ ] Generar un `JWT_SECRET` real vía un gestor de secretos del entorno elegido (nunca a
      mano en un `.env` de servidor) antes de arrancar el contenedor con
      `NODE_ENV=production`.
- [ ] Definir un registry de imágenes y una convención de tags inmutable (ver §8).
- [ ] Decidir si el destino es Kubernetes (`infra/kubernetes/` en la raíz del repo, hoy
      vacío) o algún otro orquestador, y escribir los manifiestos correspondientes — este
      ciclo solo cubre Docker/`docker compose` para desarrollo/staging local.
- [ ] Configurar `cors` con allowlist explícita el día que se sume un frontend web (LOW-1
      de Security, no bloqueante hoy porque el consumo actual es mobile nativo +
      `web-preview/` same-origin, que de todos modos no viaja en esta imagen).
- [ ] Pipeline de CI en verde (`build-and-test` + `docker-build-smoke`) sobre el commit
      exacto que se va a desplegar.
- [ ] Aprobación explícita del Director General IA / CEO — ningún cambio llega a
      producción sin ella.
