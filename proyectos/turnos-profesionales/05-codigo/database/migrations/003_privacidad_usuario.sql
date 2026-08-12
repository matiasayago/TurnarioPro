-- Turnos Profesionales — migración incremental 003 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (ciclo HU-32, 2026-08-11)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- `002_pacientes_historial_auth_google.sql` (ver su propio header para el diagnóstico completo):
-- `runMigrations()` (backend/src/db.ts) corre `001_init.sql` COMPLETO una sola vez por base de
-- datos, gateado por un chequeo simple ("¿ya existe la tabla `usuario`?" → si existe, se omite
-- TODO el script sin ejecutar ni una sola sentencia). En Render producción esa tabla ya existe
-- desde el ciclo de HU-20/HU-21/HU-35 (2026-08-10, ver header de 002) — así que editar
-- `001_init.sql` con la tabla `usuario_preferencias` nueva (ya aplicado en este mismo ciclo,
-- ambas copias: `05-codigo/database/migrations/001_init.sql` y
-- `05-codigo/backend/migrations/001_init.sql`) es necesario para cualquier ambiente que migre
-- desde cero, pero NO alcanza para que Render la reciba en el próximo deploy — el gate de
-- `runMigrations()` salta el script completo, sin error, sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 003_privacidad_usuario.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que 001_init.sql/002, no con el rol
-- de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- `001_init.sql` (ambas copias, `database/` y `backend/`) SÍ se actualizó en este mismo ciclo con
-- el mismo contenido final (mismo tipo/tabla/policy, con el razonamiento completo en sus
-- comentarios, bloque "Preferencias de privacidad de usuario") — sigue siendo correcto y
-- necesario para cualquier ambiente NUEVO que corra la migración desde cero por primera vez (un
-- clon local nuevo, un service container de CI, un docker-compose recién creado, o un eventual
-- segundo ambiente). Este archivo 003 es EXCLUSIVAMENTE para cerrar la brecha en ambientes que ya
-- migraron antes de este ciclo. Por eso acá NO se repite el razonamiento completo de cada
-- decisión (tabla separada `usuario_preferencias` vs. columnas en `usuario`, ENUM vs. TEXT para
-- `visibilidad_perfil`, por qué sin `creado_por`/`modificado_por`, la conclusión sobre el estado
-- de RLS de `usuario`, etc.) — ya está documentado en los comentarios de `001_init.sql` (bloque
-- "Preferencias de privacidad de usuario") y en `03-arquitectura/modelo-datos.md` §2septies/
-- §5quater; acá solo lo mínimo para que este archivo sea legible de forma independiente.
--
-- Idempotencia: `CREATE TABLE ... IF NOT EXISTS` para la tabla (Postgres lo soporta de forma
-- nativa). Postgres NO admite `CREATE TYPE ... IF NOT EXISTS` ni `CREATE POLICY ... IF NOT
-- EXISTS` (mismo límite ya documentado en 002/`runMigrations()`) — el ENUM queda envuelto en un
-- bloque `DO` con guard contra `pg_type`, y la policy en un bloque `DO` con guard contra
-- `pg_policy`, mismo patrón exacto que usa 002 para sus 3 policies/constraints nuevas, para que
-- este script sí sea reintentable de punta a punta.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (DROP explícito de cada
-- objeto que crea este script, en orden inverso de dependencias: primero la tabla, después el
-- tipo que usa). No se ejecuta solo; copiar y correr a mano si hace falta revertir.

BEGIN;

-- ---------------------------------------------------------------------------
-- HU-32 — tipo ENUM `visibilidad_perfil_usuario` + tabla `usuario_preferencias`. Razonamiento
-- completo (por qué tabla separada y no columnas en `usuario`, por qué ENUM y no TEXT para
-- `visibilidad_perfil`, por qué los defaults elegidos, por qué sin `creado_por`/`modificado_por`,
-- por qué sin soft delete, y la conclusión sobre el estado de RLS de `usuario`) en 001_init.sql,
-- bloque "Preferencias de privacidad de usuario", y en 03-arquitectura/modelo-datos.md §2septies.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'visibilidad_perfil_usuario') THEN
    CREATE TYPE visibilidad_perfil_usuario AS ENUM ('publico', 'solo_contactos', 'privado');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS usuario_preferencias (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id               UUID NOT NULL UNIQUE REFERENCES usuario(id),
  visibilidad_perfil       visibilidad_perfil_usuario NOT NULL DEFAULT 'publico',
  mostrar_estado_en_linea  BOOLEAN NOT NULL DEFAULT true,
  compartir_datos_uso      BOOLEAN NOT NULL DEFAULT true,
  creado_en                TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en            TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
-- Row Level Security — FORCE desde el primer commit (misma lección de 001_init.sql §5bis/§5ter:
-- el rol que corre este script se vuelve owner de esta tabla nueva, y Postgres ignora RLS para el
-- owner salvo FORCE). Policy única: cada usuario lee/edita únicamente su propia fila
-- (`usuario_id = app.usuario_id`), sin JOIN — no hay negocio/profesional de por medio como sí
-- necesitan paciente/tratamiento/nota_medica.
--
-- ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY SÍ es idempotente en Postgres (no error si ya
-- estaba activado) — no hace falta guard ahí, igual que en 002. CREATE POLICY sí necesita guard.
-- ---------------------------------------------------------------------------
ALTER TABLE usuario_preferencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_preferencias FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'usuario_preferencias_acceso_propio') THEN
    CREATE POLICY usuario_preferencias_acceso_propio ON usuario_preferencias
      USING (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
      WITH CHECK (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP TABLE IF EXISTS usuario_preferencias;
-- DROP TYPE IF EXISTS visibilidad_perfil_usuario;
-- COMMIT;
