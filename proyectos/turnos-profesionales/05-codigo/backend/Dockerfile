# syntax=docker/dockerfile:1
#
# Turnos Profesionales (TURNOS-2026-001) — Backend
# Build multi-stage: un stage de build compila TypeScript -> dist/ (con devDependencies),
# y el stage de runtime final se queda solo con lo mínimo para correr la API en producción
# (sin devDependencies, sin scripts/ de prueba manual, sin la preview web de desarrollo).
#
# ═══════════════════════════════════════════════════════════════════════════════════════
# Nota de versión de Node — coordinada con `.github/workflows/turnos-backend-ci.yml`
# (`NODE_VERSION`, raíz del repo): no bajar de acá sin revisar los dos archivos juntos.
#
# Históricamente este piso salía de que el acceso a datos (src/db.ts) usaba el módulo
# built-in `node:sqlite`, disponible recién desde Node >=22.5 — se había adoptado en
# desarrollo porque `better-sqlite3` (la elección original) requiere compilar un addon
# nativo vía node-gyp/Visual Studio Build Tools, no disponibles en el entorno de
# desarrollo de este proyecto (ver README.md de este backend y
# memory/proyectos/turnos-profesionales/decisiones.md).
#
# Producción ya apunta a PostgreSQL real (2026-08-07, driver `pg`, variable de entorno
# `DATABASE_URL` — ver ../../08-despliegue/README.md y ../../03-arquitectura/modelo-datos.md
# §5, Row Level Security). Esta imagen se queda en `node:22-slim` por consistencia con el
# runtime que valida CI, no porque `pg` en sí exija un piso de Node tan alto como el que
# exigía `node:sqlite` — bajar la versión de Node en el futuro es una decisión válida en
# principio, pero coordinada (revisar también el workflow de CI), no algo que se deba asumir
# solo porque el driver cambió.
# ═══════════════════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------------------
# Stage 1/2: build
# ---------------------------------------------------------------------------------------
FROM node:22-slim AS build
WORKDIR /app

# Copiamos primero solo los manifiestos para aprovechar la cache de capas de Docker:
# mientras package*.json no cambien, `npm ci` no se vuelve a correr aunque cambie el
# código fuente en un build posterior.
COPY package.json package-lock.json ./
RUN npm ci

# tsconfig.json + src/ alcanza para COMPILAR (tsc). `scripts/` (los .mjs de prueba manual)
# NO se copian ni hacen falta acá: son JavaScript suelto que no pasa por tsc (el include
# "scripts/**/*.ts" de tsconfig.json no matchea ningún archivo hoy, confirmado en este
# ciclo) y no se ejecuta en producción, solo en desarrollo/CI (ver
# .github/workflows/turnos-backend-ci.yml en la raíz del repo).
#
# migrations/ SÍ hace falta acá, aunque tsc no la toque (no es .ts, no está en ningún
# "include" de tsconfig.json): `npm run build` encadena automáticamente el script
# `postbuild` de package.json ("node -e require('fs').cpSync('migrations',
# 'dist/migrations',...)"), y ese cpSync corre con cwd /app (WORKDIR de este stage) — sin
# este COPY, migrations/ no existe todavía dentro de la imagen en construcción en ese punto
# y el postbuild revienta con ENOENT, tirando abajo todo "RUN npm run build" (bug real
# encontrado en este ciclo: docker-build-smoke fallaba acá, confirmado en el log de
# run 31142348973 vía el mecanismo de diagnóstico — ver
# memory/proyectos/turnos-profesionales/decisiones.md). El resultado de este cpSync dentro
# del build stage (dist/migrations acá) es redundante con el COPY explícito hacia
# ./dist/migrations del stage de runtime más abajo — se deja de todos modos: es el mismo
# postbuild que ya corre standalone en cualquier `npm run build` fuera de Docker (ver
# memory/proyectos/turnos-profesionales/decisiones.md, "Cierre del hallazgo de
# package.json"), y hacerlo fallar acá rompería la paridad entre build en Docker y build
# fuera de Docker.
COPY tsconfig.json ./
COPY src ./src
COPY migrations ./migrations
RUN npm run build

# Nos quedamos solo con las dependencias de producción — saca ts-node, ts-node-dev,
# typescript, @types/*, cross-env del node_modules que se copia al stage final. No hace
# falta un segundo `npm ci --omit=dev` en el stage de runtime: alcanza con podar acá.
RUN npm prune --omit=dev

# ---------------------------------------------------------------------------------------
# Stage 2/2: runtime — imagen final, sin herramientas de build ni de test.
# ---------------------------------------------------------------------------------------
FROM node:22-slim AS runtime
WORKDIR /app

# NODE_ENV=production recién en ESTE stage (nunca en el de build, donde `npm ci` necesita
# instalar devDependencies para poder compilar) — además de la semántica estándar de
# Node/Express, es lo que activa el fail-fast de JWT_SECRET en src/auth.ts (ver HIGH-3 en
# ../../07-seguridad/informe-seguridad.md): sin JWT_SECRET seteado, el proceso no arranca.
ENV NODE_ENV=production

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./

# ── Nota importante para quien toque este Dockerfile ────────────────────────────────────
# tsconfig.json compila con rootDir "." (ver ese archivo), así que el JS compilado queda
# en dist/src/*.js, NO en dist/*.js. Esto en su momento (hallazgo de un ciclo anterior)
# generó una inconsistencia real con package.json ("main"/"start" decían "dist/index.js",
# desactualizado — nunca se había ejercitado porque el flujo de desarrollo usa
# ts-node-dev, no el build compilado). Ya corregido en package.json (ver
# memory/proyectos/turnos-profesionales/decisiones.md, "Cierre del hallazgo de
# package.json"): "main"/"start" apuntan hoy a "dist/src/index.js", igual que el CMD de
# acá abajo. Este Dockerfile de todos modos sigue usando la ruta explícita en el CMD (en
# vez de depender de `npm start`) por ser la práctica estándar de contenedores — invocar
# `node` directo evita la capa de proceso extra de npm y sus quirks de propagación de
# señales (SIGTERM), no porque package.json siga roto.
#
# Por el mismo motivo, __dirname en runtime apunta a dist/src (no a src/), así que
# runMigrations() (src/db.ts) resuelve "../migrations" como dist/migrations, no como
# ./migrations junto al código fuente original. De ahí que la carpeta migrations/ se copie
# DENTRO de dist/ y no en la raíz de /app.
COPY migrations ./dist/migrations

# Con PostgreSQL real (DATABASE_URL, ver ../../08-despliegue/README.md), esta imagen ya NO
# persiste ningún archivo de base de datos local: no hace falta declarar ningún volumen ni
# crear ningún directorio de datos acá. La persistencia es responsabilidad del servicio de
# Postgres — el Postgres gestionado del proveedor de hosting en producción (Render/Railway),
# o el servicio `postgres` de docker-compose.yml en desarrollo/staging local — nunca de esta
# imagen. (Hasta este ciclo, acá se fijaba `ENV DB_PATH=/data/dev.sqlite3` y se creaba /data
# para el volumen nombrado `turnos_backend_data` que usaba docker-compose.yml con
# node:sqlite; ambos se sacaron junto con la migración de driver — ver
# memory/proyectos/turnos-profesionales/decisiones.md.)

# NUNCA se setea ENABLE_DEV_ROUTES=true en esta imagen (ver HIGH-4 en
# ../../07-seguridad/informe-seguridad.md): con la variable ausente, src/app.ts no monta
# /dev/* ni sirve web-preview/ estático — que además no se copia a esta imagen en absoluto
# (ver .dockerignore), como defensa adicional. Si algún entorno no productivo necesita
# activar /dev/* para depuración puntual, es una decisión consciente tomada AFUERA de esta
# imagen (docker run -e / environment: en compose), nunca un default acá.

ENV PORT=3000
EXPOSE 3000

# Healthcheck con un script Node inline en vez de curl/wget: las imágenes "slim" de Debian
# no garantizan traer ninguno de los dos instalado, y Node sí está garantizado (es la
# imagen). Usa el mismo puerto que la app (PORT), sin asumir 3000 si se lo pisara en runtime.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',(r)=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"]

# La imagen oficial de Node ya trae un usuario no-root llamado `node` (uid/gid 1000) —
# corremos con ese usuario en vez de root, buena práctica estándar de contenedores (no es
# un requisito puntual de este backend). Va al final del stage, después de todos los COPY
# (que si necesitan correr como root para fijar ownership por default).
USER node

CMD ["node", "dist/src/index.js"]
