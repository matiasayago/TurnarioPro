-- Turnos Profesionales — migración incremental 009 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (HU-31 — datos operativos del negocio: horario general de atención,
-- dirección detallada, teléfono, logo — ver 03-arquitectura/modelo-datos.md §2undecies para el
-- razonamiento completo de esta ronda, y memory/proyectos/turnos-profesionales/decisiones.md)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- 002_pacientes_historial_auth_google.sql/003_privacidad_usuario.sql/004_notificaciones.sql/
-- 005_suscripcion_negocio.sql/006_suscripcion_negocio_policy_contexto.sql/
-- 007_paciente_historial_acceso_administrador.sql/008_recuperacion_password.sql (ver sus propios
-- headers para el diagnóstico completo): `runMigrations()` (backend/src/db.ts) corre
-- `001_init.sql` COMPLETO una sola vez por base de datos, gateado por un chequeo simple
-- ("¿ya existe la tabla `usuario`?" → si existe, se omite TODO el script sin ejecutar ni una sola
-- sentencia). En Render producción esa tabla ya existe desde hace varios ciclos — así que editar
-- `001_init.sql` con las 4 columnas nuevas de `negocio` (ya aplicado en este mismo ciclo, en las
-- DOS copias — `database/migrations/001_init.sql` y `backend/migrations/001_init.sql` quedan
-- byte-idénticas, verificado con `diff`) es necesario para cualquier ambiente que migre desde
-- cero, pero NO alcanza para que Render la reciba en el próximo deploy — el gate de
-- `runMigrations()` salta el script completo, sin error, sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 009_negocio_datos_operativos.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que los archivos anteriores, no con
-- el rol de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- NOTA sobre "ambas copias" — por qué este archivo 009 NO se duplica en `backend/migrations/`
-- (a diferencia de `001_init.sql`, que sí se mantiene idéntico en ambas rutas). Verificado contra
-- el código real antes de decidir esto, no asumido: `runMigrations()` (backend/src/db.ts) lee
-- ÚNICAMENTE el nombre de archivo hardcodeado "001_init.sql" — nunca hace glob del directorio
-- `migrations/`, así que jamás va a ejecutar un archivo `009_*.sql` aunque existiera ahí.
-- Confirmado además, empíricamente, que NINGUNO de los 7 incrementales anteriores (002 a 008)
-- tiene copia en `backend/migrations/` (ese directorio solo contiene `001_init.sql`) — es un
-- patrón consistente en los últimos 7 ciclos, no una omisión de este archivo puntual.
--
-- QUÉ HACE — puramente aditivo (no toca ninguna tabla/columna/policy existente): 4 columnas TEXT
-- nullable nuevas en `negocio` (`horario_atencion`, `direccion`, `telefono`, `logo_url`). Sin ENUM
-- nuevo, sin índice nuevo, sin cambios de Row Level Security (`negocio` sigue sin tener RLS
-- habilitada, sin cambios en este ciclo), sin backfill — nullable sin `DEFAULT`, así que ningún
-- negocio ya existente queda con un valor no deseado; quedan simplemente sin cargar hasta que su
-- administrador las complete desde Configuración de Consultorio (no hay backfill con sentido
-- posible: son datos que solo el dueño de cada negocio conoce, a diferencia de
-- `suscripcion_negocio` en `005`, que sí backfillea un plan 'gratis' por defecto). Razonamiento
-- completo columna por columna (por qué 4 columnas y no una sola JSON/estructurada, por qué
-- `direccion` es un campo nuevo y no una ampliación de `ubicacion`, por qué `horario_atencion` no
-- toca `disponibilidad`, y por qué `logo_url` es una URL pegada y no un upload real) en
-- `001_init.sql`, bloque "Datos operativos del negocio — horario/dirección/teléfono/logo", y en
-- `03-arquitectura/modelo-datos.md` §2undecies — acá solo lo mínimo para que este archivo sea
-- legible de forma independiente.
--
-- Idempotencia: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` para las 4 columnas (Postgres lo
-- soporta de forma nativa, sin necesitar un bloque `DO` con guard — a diferencia de
-- `CREATE POLICY`, que NO admite `IF NOT EXISTS`; no hace falta ninguno acá porque este archivo no
-- toca RLS). Una corrida repetida no falla, simplemente no hace nada la segunda vez.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (`DROP COLUMN` de las 4
-- columnas). No se ejecuta solo; copiar y correr a mano si hace falta revertir. Antes de revertir
-- en un ambiente con datos reales: cualquier valor ya cargado por un administrador en estas 4
-- columnas se pierde de forma permanente (a diferencia de `008`, acá no hay ningún artefacto de
-- vida corta que "ya iba a perderse igual" — son datos de perfil que el negocio cargó a propósito)
-- — confirmar con el Director General IA/CEO antes de correr el rollback contra Render si ya hay
-- negocios con estos campos completos.

BEGIN;

-- ---------------------------------------------------------------------------
-- HU-31 — datos operativos del negocio. Razonamiento completo (nombre de cada columna, por qué
-- nullable sin DEFAULT, por qué sin CHECK de formato, por qué sin RLS/índice nuevo) en
-- 001_init.sql, mismo bloque, y en 03-arquitectura/modelo-datos.md §2undecies.
-- ---------------------------------------------------------------------------
ALTER TABLE negocio ADD COLUMN IF NOT EXISTS horario_atencion TEXT;
ALTER TABLE negocio ADD COLUMN IF NOT EXISTS direccion TEXT;
ALTER TABLE negocio ADD COLUMN IF NOT EXISTS telefono TEXT;
ALTER TABLE negocio ADD COLUMN IF NOT EXISTS logo_url TEXT;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- ALTER TABLE negocio DROP COLUMN IF EXISTS logo_url;
-- ALTER TABLE negocio DROP COLUMN IF EXISTS telefono;
-- ALTER TABLE negocio DROP COLUMN IF EXISTS direccion;
-- ALTER TABLE negocio DROP COLUMN IF EXISTS horario_atencion;
-- COMMIT;
-- ============================================================================
