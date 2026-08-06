# syntax=docker/dockerfile:1
#
# Turnos Profesionales (TURNOS-2026-001) — Backend
# Build multi-stage: un stage de build compila TypeScript -> dist/ (con devDependencies),
# y el stage de runtime final se queda solo con lo mínimo para correr la API en producción
# (sin devDependencies, sin scripts/ de prueba manual, sin la preview web de desarrollo).
#
# ═══════════════════════════════════════════════════════════════════════════════════════
# ATENCIÓN — restricción de versión de Node poco común en este proyecto, léase antes de
# tocar la imagen base:
#
# El acceso a datos (src/db.ts) usa el módulo built-in `node:sqlite`, disponible recién
# desde Node >=22.5 (ver README.md de este backend y
# memory/proyectos/turnos-profesionales/decisiones.md). Se adoptó en desarrollo porque
# `better-sqlite3` — la elección original — requiere compilar un addon nativo vía
# node-gyp/Visual Studio Build Tools, no disponibles en el entorno de desarrollo de este
# proyecto. Por eso esta imagen NO puede bajarse a Node 18/20 LTS como se haría por
# default en cualquier otro proyecto Node: hace falta Node 22.x (o superior) sí o sí.
# `node:22-slim` sigue la serie 22 mientras reciba parches (a la fecha de este ciclo,
# muy por encima de 22.5). Si en algún momento se fija por dígest exacto, confirmar que
# el patch sea >=22.5.0 antes de considerar bajar la imagen a una versión menor.
#
# Producción (fuera de este ciclo) apunta a PostgreSQL, no a node:sqlite — ver el gap
# documentado en ../../08-despliegue/README.md y ../../03-arquitectura/modelo-datos.md §5
# (Row Level Security, diseñada pero todavía sin conectar). Esta imagen refleja el backend
# tal como existe HOY (node:sqlite), no un setup de Postgres que el código todavía no sabe
# hablar.
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

# tsconfig.json + src/ alcanza para compilar. `scripts/` (los .mjs de prueba manual) NO se
# copian ni hacen falta acá: son JavaScript suelto que no pasa por tsc (el include
# "scripts/**/*.ts" de tsconfig.json no matchea ningún archivo hoy, confirmado en este
# ciclo) y no se ejecuta en producción, solo en desarrollo/CI (ver
# .github/workflows/turnos-backend-ci.yml en la raíz del repo).
COPY tsconfig.json ./
COPY src ./src
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

# ── Hallazgo de este ciclo, importante para quien toque este Dockerfile ────────────────
# tsconfig.json compila con rootDir "." (ver ese archivo), así que el JS compilado queda
# en dist/src/*.js, NO en dist/*.js — pese a que package.json ("main"/"start") dice
# "dist/index.js". Ese campo de package.json está desactualizado y nunca se ejercitó en
# este proyecto (el flujo de desarrollo usa ts-node-dev, no el build compilado). Verificado
# en este ciclo: `npm run build && node dist/index.js` falla con "Cannot find module"; `node
# dist/src/index.js` funciona (smoke test completo pasado contra esa instancia — ver
# ../../08-despliegue/README.md). Por eso el CMD de esta imagen usa la ruta real y no la
# que dice package.json — reportado como defecto a corregir en un ciclo de Backend.
#
# Por el mismo motivo, __dirname en runtime apunta a dist/src (no a src/), así que
# runMigrations() (src/db.ts) resuelve "../migrations" como dist/migrations, no como
# ./migrations junto al código fuente original. De ahí que la carpeta migrations/ se copie
# DENTRO de dist/ y no en la raíz de /app.
COPY migrations ./dist/migrations

# El archivo sqlite de node:sqlite se guarda en /data (volumen nombrado, ver
# docker-compose.yml) en vez de depender del default de db.ts, que — por el mismo desfase
# de __dirname de arriba — resolvería a dist/dev.sqlite3: un lugar frágil y poco intuitivo
# para un volumen persistente (dentro del propio artefacto de build). DB_PATH ya es una
# variable soportada por el código (src/db.ts) — fijarla acá no requiere ningún cambio en
# el backend.
ENV DB_PATH=/data/dev.sqlite3
RUN mkdir -p /data && chown node:node /data

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
# un requisito puntual de este backend). Va al final para que los pasos anteriores
# (mkdir/chown de /data) puedan correr como root.
USER node

CMD ["node", "dist/src/index.js"]
