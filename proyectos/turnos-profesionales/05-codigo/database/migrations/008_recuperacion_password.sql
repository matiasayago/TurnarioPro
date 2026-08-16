-- Turnos Profesionales — migración incremental 008 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (recuperación de contraseña — pedido del CEO, prioridad alta,
-- 2026-08-16 — ver 03-arquitectura/modelo-datos.md §2decies/§5octies para el razonamiento
-- completo de esta ronda, y memory/proyectos/turnos-profesionales/decisiones.md)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- 002_pacientes_historial_auth_google.sql/003_privacidad_usuario.sql/004_notificaciones.sql/
-- 005_suscripcion_negocio.sql/006_suscripcion_negocio_policy_contexto.sql/
-- 007_paciente_historial_acceso_administrador.sql (ver sus propios headers para el diagnóstico
-- completo): `runMigrations()` (backend/src/db.ts) corre `001_init.sql` COMPLETO una sola vez por
-- base de datos, gateado por un chequeo simple ("¿ya existe la tabla `usuario`?" → si existe, se
-- omite TODO el script sin ejecutar ni una sola sentencia). En Render producción esa tabla ya
-- existe desde hace varios ciclos — así que editar `001_init.sql` con la tabla
-- `token_recuperacion_password` nueva (ya aplicado en este mismo ciclo, en las DOS copias —
-- `database/migrations/001_init.sql` y `backend/migrations/001_init.sql` quedan byte-idénticas,
-- verificado con `git diff --no-index` sin salida) es necesario para cualquier ambiente que migre
-- desde cero, pero NO alcanza para que Render la reciba en el próximo deploy — el gate de
-- `runMigrations()` salta el script completo, sin error, sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 008_recuperacion_password.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que los archivos anteriores, no con
-- el rol de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- NOTA sobre "ambas copias" — por qué este archivo 008 NO se duplica en `backend/migrations/`
-- (a diferencia de `001_init.sql`, que sí se mantiene idéntico en ambas rutas). Verificado contra
-- el código real antes de decidir esto, no asumido: `runMigrations()` (backend/src/db.ts línea
-- ~164) lee ÚNICAMENTE el nombre de archivo hardcodeado "001_init.sql" — nunca hace glob del
-- directorio `migrations/`, así que jamás va a ejecutar un archivo `008_*.sql` aunque existiera
-- ahí. Confirmado además, empíricamente, que NINGUNO de los 5 incrementales anteriores (002 a 007)
-- tiene copia en `backend/migrations/` (ese directorio solo contiene `001_init.sql`) — es un
-- patrón consistente en los últimos 5 ciclos, no una omisión de este archivo puntual. Duplicar
-- este 008 ahí agregaría un archivo inerte (nunca se ejecuta) que además podría sugerir,
-- incorrectamente, que `runMigrations()` sí lo aplica. Si el criterio de este proyecto cambia más
-- adelante (ver la recomendación de seguimiento ya documentada en `001_init.sql` §5bis: que
-- `runMigrations()` pase a soportar una secuencia de migraciones numeradas con tabla de control),
-- recién ahí correspondería reconsiderar dónde viven estos archivos.
--
-- QUÉ HACE — puramente aditivo (no toca ninguna tabla/columna existente): 1 tabla nueva
-- (`token_recuperacion_password`), 1 índice único parcial. Sin ENUM nuevo, sin backfill (tabla
-- nueva que nace vacía — nadie tiene un token pendiente todavía, no hay ninguna fila que migrar,
-- mismo caso que `usuario_preferencias`/`usuario_preferencias_notificacion` en 003/004, a
-- diferencia de 002/005 que sí backfillearon filas ya existentes de otras tablas). Razonamiento
-- completo columna por columna (por qué tabla nueva y no columnas en `usuario`, por qué el nombre,
-- por qué `usado_en` timestamp y no un boolean, por qué invalidar tokens anteriores al pedir uno
-- nuevo y cómo lo garantiza el índice único parcial, y la decisión de NO habilitar RLS en esta
-- tabla con la justificación completa) en `001_init.sql`, bloque "Recuperación de contraseña —
-- token de un solo uso", y en `03-arquitectura/modelo-datos.md` §2decies/§5octies — acá solo lo
-- mínimo para que este archivo sea legible de forma independiente.
--
-- Idempotencia: `CREATE TABLE ... IF NOT EXISTS` para la tabla y `CREATE UNIQUE INDEX ... IF NOT
-- EXISTS` para el índice (Postgres soporta ambos de forma nativa, sin necesitar un bloque `DO` con
-- guard — a diferencia de `CREATE TYPE`/`CREATE POLICY`, que NO admiten `IF NOT EXISTS`; no hace
-- falta ninguno de los dos acá porque este archivo no crea ningún ENUM ni ninguna policy de RLS).
-- Una corrida repetida no falla, simplemente no hace nada la segunda vez.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (DROP explícito de cada
-- objeto que crea este script, en orden inverso de dependencias: primero el índice, después la
-- tabla). No se ejecuta solo; copiar y correr a mano si hace falta revertir. Antes de revertir en
-- un ambiente con datos reales: cualquier token pendiente en la tabla queda inválido de inmediato
-- (nadie va a poder completar un reset de contraseña ya iniciado) — aceptable dado que son tokens
-- de vida corta y de un solo uso, sin ningún otro dato que dependa de ellos (nada más en el
-- esquema referencia esta tabla).

BEGIN;

-- ---------------------------------------------------------------------------
-- Recuperación de contraseña — token de un solo uso. Razonamiento completo (nombre, columnas,
-- por qué invalidar tokens anteriores del mismo usuario al pedir uno nuevo, y por qué esta tabla
-- NO lleva Row Level Security) en 001_init.sql, mismo bloque, y en
-- 03-arquitectura/modelo-datos.md §2decies/§5octies.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS token_recuperacion_password (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES usuario(id),
  token_hash    TEXT NOT NULL UNIQUE,
  expira_en     TIMESTAMPTZ NOT NULL,
  usado_en      TIMESTAMPTZ,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_token_recuperacion_password_expira_futuro CHECK (expira_en > creado_en)
);

-- Parcial + UNIQUE: además de cubrir la búsqueda "¿tiene este usuario un token pendiente?", es la
-- garantía a nivel de base de datos de "a lo sumo 1 token pendiente por usuario" — ver
-- razonamiento en 001_init.sql/modelo-datos.md §2decies.
CREATE UNIQUE INDEX IF NOT EXISTS uq_token_recuperacion_password_usuario_pendiente
  ON token_recuperacion_password (usuario_id)
  WHERE usado_en IS NULL;

-- Sin ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY acá — decisión deliberada, no un paso
-- pendiente olvidado. Ver el bloque "Row Level Security — DELIBERADAMENTE NO SE HABILITA en esta
-- tabla" junto a esta misma tabla en 001_init.sql, y modelo-datos.md §5octies, para el
-- razonamiento completo (en resumen: ningún acceso a esta tabla, en ningún punto de su ciclo de
-- vida, ocurre con un `app.usuario_id` de sesión ya resuelto — el patrón de RLS de este esquema,
-- basado en `current_setting('app.usuario_id')`, no aplica a un flujo que es pre-autenticación por
-- diseño; la protección real es la del token en sí: alta entropía + hash + expiración corta + un
-- solo uso + el índice único parcial de arriba).

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP INDEX IF EXISTS uq_token_recuperacion_password_usuario_pendiente;
-- DROP TABLE IF EXISTS token_recuperacion_password;
-- COMMIT;
-- ============================================================================
