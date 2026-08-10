-- Aprovisionamiento de roles Postgres — Turnos Profesionales (TURNOS-2026-001)
-- Rol: DBA · script auxiliar (NO es una migración — `runMigrations()`, backend/src/db.ts, no lo
-- ejecuta nunca; correrlo es responsabilidad manual de DevOps, una vez por ambiente).
--
-- QUÉ RESUELVE. Separa un rol de MIGRACIÓN (owner de las tablas, corre
-- ../migrations/001_init.sql una vez) de un rol de RUNTIME (el que usa `DATABASE_URL` de la app
-- en cada ambiente, sin ser owner y sin BYPASSRLS). Ver el bloque grande "Separación owner/runtime
-- y FORCE ROW LEVEL SECURITY" en ../migrations/001_init.sql para el porqué completo — resumen: sin
-- esto, `FORCE ROW LEVEL SECURITY` (ya aplicado en esa migración) NO alcanza para que Row Level
-- Security tenga efecto real en docker-compose/CI, porque el único rol que existe hoy ahí
-- (`turnos` / `turnos_ci`) es SUPERUSUARIO (lo crea así la imagen oficial `postgres:16-alpine` vía
-- `POSTGRES_USER`), y un superusuario bypassea RLS siempre, FORCE incluido.
--
-- DIAGNÓSTICO PRIMERO (sugerido por Security) — antes de asumir que un ambiente necesita este
-- script, conectado con el rol que HOY usa `DATABASE_URL` en ese ambiente, correr:
--
--   SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;
--
-- - docker-compose (`turnos`) y CI (`turnos_ci`): confirmado en este ciclo (ver comentario en
--   ../migrations/001_init.sql) que devuelven rolsuper=true — este script hace falta SÍ O SÍ ahí
--   para que RLS tenga cualquier efecto real.
-- - Render (`turnos_profesionales`, ver ../../backend/render.yaml): NO verificado contra una
--   cuenta real (misma limitación que el resto de este proyecto documenta para Render). Si esa
--   query devuelve rolsuper=false Y rolbypassrls=false ahí, `FORCE ROW LEVEL SECURITY` (ya
--   aplicado en la migración) ya alcanza en ESE ambiente puntual sin este script — la separación
--   de roles sigue siendo la arquitectura recomendada (más robusta, más auditable, y necesaria
--   para que docker-compose/CI puedan ejercitar RLS de verdad), pero no sería bloqueante ahí.
--
-- SECUENCIA COMPLETA DE ADOPCIÓN POR AMBIENTE (DevOps):
--   1. Conectarse con un rol que pueda crear roles (CREATEROLE) — en docker-compose/CI, el rol
--      único que existe hoy ya es superusuario y alcanza. En Render, VERIFICAR si el rol del
--      Blueprint (`turnos_profesionales`) tiene CREATEROLE; si no, puede hacer falta gestionarlo
--      desde el dashboard de Render o soporte — no asumido acá.
--   2. Completar las variables de más abajo (nombres/contraseñas reales, gestionados por el
--      secreto/orquestador de cada ambiente — NUNCA hardcodeados en un commit) y correr la
--      Parte 1 de este script (crear los 2 roles).
--   3. Si ../migrations/001_init.sql todavía no corrió en ese ambiente: correrla EXPLÍCITAMENTE,
--      conectado COMO el rol de MIGRACIÓN (`psql "$MIGRADOR_DATABASE_URL" -f
--      ../migrations/001_init.sql`) — ya no alcanza con dejar que `runMigrations()` la corra sola
--      al arrancar la app, porque `DATABASE_URL` de la app va a apuntar al rol de RUNTIME (sin
--      privilegios de CREATE) a partir del paso 5. `runMigrations()` NO necesita ningún cambio de
--      código para convivir con esto: ya está gateada por "¿existe `public.usuario`?"
--      (`SELECT to_regclass('public.usuario')`, una consulta de catálogo que cualquier rol puede
--      correr) — si este paso 3 ya corrió, el intento de `runMigrations()` con el rol de RUNTIME
--      simplemente no hace nada (no vuelve a intentar el DDL).
--      Si ../migrations/001_init.sql YA corrió en ese ambiente (con el rol único de hoy como
--      owner): no hace falta re-correrla — ese rol único pasa a ser, de hecho, el rol de
--      MIGRACIÓN de acá en adelante (ya es owner de las tablas); alcanza con crear el rol de
--      RUNTIME nuevo (Parte 1) y correr los GRANTs (Parte 2) para que ese rol nuevo pueda operar.
--   4. Correr la Parte 2 de este script (GRANTs) — necesita que las tablas/funciones ya existan
--      (por eso va DESPUÉS del paso 3), conectado como el rol de MIGRACIÓN o cualquier rol con
--      privilegios suficientes sobre esos objetos.
--   5. Recién ahora apuntar `DATABASE_URL` de la app (docker-compose.yml / variable de entorno del
--      job `build-and-test`/`docker-build-smoke` en turnos-backend-ci.yml / variable de entorno
--      del Web Service en render.yaml — NINGUNO de los 3 se tocó en este ciclo, es la tarea de
--      seguimiento de DevOps) al rol de RUNTIME — nunca al de MIGRACIÓN.
--   6. Re-correr la batería completa de `scripts/*.mjs` del backend contra ESE ambiente ya
--      reconfigurado — es la primera vez que corren con RLS realmente activo, pueden aparecer
--      fallos que estaban enmascarados (ver la recomendación en ../migrations/001_init.sql). Y
--      correr ../scripts/verificar_rls_postgres.sql (test de RLS a nivel de base de datos, pedido
--      por Security — no lo reemplaza la batería de `scripts/*.mjs`, que solo puede probar lo que
--      la aplicación ya decide exponer).
--
-- Nota para Render específicamente: el mecanismo de "databases:" del Blueprint
-- (../../backend/render.yaml) solo provisiona UN usuario/rol por base — no hay forma de declarar
-- un segundo rol ahí. Crear el rol de RUNTIME en Render requiere conectarse manualmente (psql, con
-- la "Internal/External Database URL" que Render ya provee para el rol único existente) y correr
-- este script a mano — no es un simple cambio de YAML. Después, el valor de `DATABASE_URL` del Web
-- Service deja de poder resolverse solo vía `fromDatabase: { property: connectionString }` (eso
-- siempre apunta al rol único que crea el Blueprint) — hay que reemplazarlo por un valor manual con
-- la connection string del rol de RUNTIME nuevo, gestionado como secreto en el dashboard de Render,
-- no en render.yaml. Documentar esto explícitamente si se aplica — no implementado en este ciclo.
--
-- ============================================================================
-- Variables (psql) — completar antes de correr, vía -v al invocar:
--   psql "$SUPERUSER_O_MIGRADOR_DATABASE_URL" \
--     -v migrador_rol=turnos_migrador -v migrador_password="'CAMBIAR_1'" \
--     -v app_rol=turnos_app -v app_password="'CAMBIAR_2'" \
--     -v nombre_db=turnos_dev \
--     -f provisionar_roles_postgres.sql
-- Los defaults de acá abajo son placeholders que fallan a propósito si no se pisan (nombres poco
-- probables de colisionar por accidente con un rol real).
--
-- CORRECCIÓN (2026-08-10, tras el primer run real de CI — ver commit de este cambio): un `\set`
-- plano acá SIEMPRE pisa el valor que haya llegado por `-v`, sin importar el orden de la línea de
-- comandos — no existe una semántica de "-v gana si está presente" para `\set` simple en psql. La
-- versión anterior de este bloque usaba `\set` sin condición, así que TODAS las corridas
-- terminaban usando los placeholders "CAMBIAR_*" literales sin importar qué `-v` se hubiera
-- pasado — confirmado en el primer run real de turnos-backend-ci.yml (que nadie pudo probar antes
-- por no tener Docker/psql en el entorno de desarrollo de DBA ni de DevOps): creó roles llamados
-- literalmente "CAMBIAR_migrador_rol"/"CAMBIAR_app_rol" y falló al referenciar "turnos_ci_migrador"
-- más abajo (paso agregado por DevOps en turnos-backend-ci.yml/docker/postgres-initdb/, que sí
-- pasaba los `-v` correctos). Se reemplaza por `\if :{?variable} ... \endif` (test de existencia
-- de variable de psql, soportado desde psql 10) — ahora el placeholder solo se aplica si la
-- variable NO llegó seteada por `-v`, que era la intención original documentada arriba.
-- ============================================================================
\if :{?migrador_rol}
\else
  \set migrador_rol 'CAMBIAR_migrador_rol'
\endif
\if :{?migrador_password}
\else
  \set migrador_password 'CAMBIAR_migrador_password'
\endif
\if :{?app_rol}
\else
  \set app_rol 'CAMBIAR_app_rol'
\endif
\if :{?app_password}
\else
  \set app_password 'CAMBIAR_app_password'
\endif
\if :{?nombre_db}
\else
  \set nombre_db 'CAMBIAR_nombre_db'
\endif

-- ============================================================================
-- Parte 1 — crear los 2 roles. Correr UNA sola vez por ambiente (conectado con un rol que tenga
-- CREATEROLE). Postgres no soporta `CREATE ROLE IF NOT EXISTS`: si un rol ya existe, la sentencia
-- correspondiente va a fallar con "role ... already exists" — es seguro ignorar ESE error puntual
-- y seguir con el resto del script (no repetir la Parte 1 completa a ciegas si ya se corrió antes:
-- un `ALTER ROLE ... PASSWORD` accidental sobre un rol ya en uso rotaría su contraseña sin previo
-- aviso).
--
-- Rol de MIGRACIÓN: LOGIN (para poder correr ../migrations/001_init.sql conectado como él) +
-- CREATEDB no hace falta (la base ya existe, provista por cada ambiente) — SIN BYPASSRLS ni
-- SUPERUSER explícitos (son atributos que NO se piden acá; el rol queda con los defaults de
-- `CREATE ROLE`, que son NOSUPERUSER/NOBYPASSRLS) — es justamente el punto: este rol va a ser
-- OWNER de las tablas (por correr el CREATE TABLE), y con FORCE ROW LEVEL SECURITY ya aplicado en
-- la migración, un owner SIN esos 2 atributos SÍ queda sujeto a RLS — ver el bloque grande de
-- ../migrations/001_init.sql para por qué esto es justamente la propiedad que se busca.
CREATE ROLE :"migrador_rol" LOGIN PASSWORD :'migrador_password';

-- CORRECCIÓN (2026-08-10, confirmado en el primer run real de CI): el rol de MIGRACIÓN necesita
-- privilegio de CREATE tanto sobre el esquema "public" (para CREATE TABLE/TYPE de
-- ../migrations/001_init.sql) como sobre la BASE DE DATOS misma (para CREATE EXTENSION
-- "pgcrypto", la primera sentencia de esa migración) — ninguno de los 2 se hereda solo por ser
-- LOGIN, y desde Postgres 15 ninguno de los 2 se otorga a PUBLIC por defecto. Sin el segundo
-- GRANT, "CREATE EXTENSION pgcrypto" falla con "permission denied ... Must have CREATE privilege
-- on current database" incluso teniendo ya CREATE sobre el esquema (confirmado empíricamente,
-- no una suposición). :"nombre_db" ya tiene que estar seteada acá arriba (Parte 0) para poder
-- resolver este GRANT.
GRANT CREATE ON SCHEMA public TO :"migrador_rol";
GRANT CREATE ON DATABASE :"nombre_db" TO :"migrador_rol";

-- Rol de RUNTIME: LOGIN, sin ningún atributo especial (NOSUPERUSER/NOCREATEDB/NOCREATEROLE/
-- NOBYPASSRLS son los defaults de `CREATE ROLE` — se dejan explícitos igual, más abajo con ALTER
-- ROLE, para no depender de que el default no cambie nunca sin que se note). Este es el rol que
-- va en `DATABASE_URL` de la app en cada ambiente — nunca el de migración.
CREATE ROLE :"app_rol" LOGIN PASSWORD :'app_password';
ALTER ROLE :"app_rol" NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION;

-- ============================================================================
-- Parte 2 — GRANTs sobre el esquema ya migrado. Correr DESPUÉS de que
-- ../migrations/001_init.sql ya haya corrido (necesita que las tablas/funciones existan),
-- conectado como el rol de MIGRACIÓN (o cualquier rol con privilegios suficientes sobre esos
-- objetos — en docker-compose/CI, el rol único de hoy sirve para este paso también).
-- ============================================================================

-- `:"nombre_db"` (sustitución de IDENTIFICADOR de psql, no de literal) — completar la variable
-- con el nombre real de la base de este ambiente (turnos_dev / turnos_test / turnos_profesionales,
-- según corresponda) antes de correr. Postgres ya otorga CONNECT a PUBLIC por defecto y ninguno de
-- los 3 ambientes de este proyecto lo revoca hoy, así que esta línea es redundante en la práctica
-- — se deja explícita de todos modos (no depender de un default silencioso que un ambiente futuro
-- podría cambiar).
GRANT CONNECT ON DATABASE :"nombre_db" TO :"app_rol";

GRANT USAGE ON SCHEMA public TO :"app_rol";
-- Explícito a propósito (no depender del default silencioso): desde Postgres 15, `CREATE` sobre
-- el esquema `public` ya NO está otorgado a PUBLIC por defecto (sí `USAGE`) — coherente con que
-- este rol NO deba poder crear tablas. Se revoca igual de forma explícita, por si el Postgres de
-- algún ambiente fuera anterior a la v15 (los 3 ambientes de este proyecto fijan Postgres 16, ver
-- docker-compose.yml/turnos-backend-ci.yml/render.yaml, pero no cuesta nada dejarlo explícito).
REVOKE CREATE ON SCHEMA public FROM :"app_rol";

-- DML sobre TODAS las tablas existentes hoy — sin DELETE: verificado contra el código real
-- (búsqueda en backend/src/) que ningún endpoint hace `DELETE FROM` — todo el borrado del dominio
-- es soft-delete (columna `eliminado_en`) vía UPDATE. Si en el futuro se agrega un DELETE real,
-- hay que agregar ese privilegio acá explícitamente, no asumir que ya está.
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO :"app_rol";

-- Tablas NUEVAS que cree el rol de MIGRACIÓN en una migración futura (ej. 002_*.sql) heredan
-- automáticamente los mismos privilegios, sin tener que repetir el GRANT de arriba a mano cada
-- vez — pero solo para objetos que ese MISMO rol de migración cree de acá en adelante; si en algún
-- momento otro rol corre una migración, hay que repetir este ALTER DEFAULT PRIVILEGES con ese rol.
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrador_rol" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE ON TABLES TO :"app_rol";

-- No hay GRANTs de secuencia: todas las PK de este esquema son UUID vía `gen_random_uuid()` (ver
-- ../migrations/001_init.sql) — no existe ninguna columna SERIAL/BIGSERIAL ni secuencia asociada.
-- `gen_random_uuid()` (extensión pgcrypto) normalmente queda con EXECUTE otorgado a PUBLIC al
-- crear la extensión — no se revoca ni se otorga explícitamente acá; si algún ambiente lo tuviera
-- revocado por alguna razón, el primer INSERT del rol de RUNTIME lo va a mostrar con un error
-- explícito de permisos (falla ruidosa, no silenciosa), fácil de diagnosticar si llegara a pasar.

-- EXECUTE de las 2 funciones SECURITY DEFINER agregadas en este ciclo (ver
-- ../migrations/001_init.sql, sección final) — revocado de PUBLIC en la propia migración; hace
-- falta este GRANT explícito para que el rol de RUNTIME pueda llamarlas el día que Backend las
-- adopte (no adoptadas todavía — ver el comentario junto a `turno_select_publico` en la
-- migración). Otorgado ya en este script para no tener que volver a tocar la parte de GRANTs en
-- ese momento — no tiene efecto hasta que algo las llame.
GRANT EXECUTE ON FUNCTION turno_ocupacion_publica(UUID) TO :"app_rol";
GRANT EXECUTE ON FUNCTION turno_propio_para_gestion(UUID) TO :"app_rol";

-- ============================================================================
-- Parte 3 — recordatorio, no ejecutable acá: una vez confirmados los pasos 1-4 de la secuencia de
-- arriba, actualizar `DATABASE_URL` de la app (docker-compose.yml / turnos-backend-ci.yml /
-- render.yaml, ninguno tocado en este ciclo) para que apunte al rol de RUNTIME (":"app_rol"" de
-- este script), nunca al de MIGRACIÓN. Ver ../migrations/001_init.sql para el detalle completo y
-- 03-arquitectura/modelo-datos.md §5bis para el resumen ejecutivo de esta tarea.
-- ============================================================================
