-- Turnos Profesionales — migración incremental 005 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (ciclo HU-29/E11 "Turnario Pro", 2026-08-14)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- `002_pacientes_historial_auth_google.sql`/`003_privacidad_usuario.sql`/`004_notificaciones.sql`
-- (ver sus propios headers para el diagnóstico completo): `runMigrations()` (backend/src/db.ts)
-- corre `001_init.sql` COMPLETO una sola vez por base de datos, gateado por un chequeo simple
-- ("¿ya existe la tabla `usuario`?" → si existe, se omite TODO el script sin ejecutar ni una sola
-- sentencia). En Render producción esa tabla ya existe desde hace varios ciclos — así que editar
-- `001_init.sql` con la tabla `suscripcion_negocio` nueva (ya aplicado en este mismo ciclo) es
-- necesario para cualquier ambiente que migre desde cero, pero NO alcanza para que Render la
-- reciba en el próximo deploy — el gate de `runMigrations()` salta el script completo, sin error,
-- sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 005_suscripcion_negocio.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que 001_init.sql/002/003/004, no con
-- el rol de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- `001_init.sql` (ambas copias en teoría — ver nota de alcance más abajo) debería tener el mismo
-- contenido final que este archivo termina dejando en la base. **Nota de alcance de este ciclo:**
-- por instrucción explícita, este ciclo NO tocó `backend/migrations/001_init.sql` (la copia
-- operativa que sí lee `runMigrations()`, ver el header de `001_init.sql` —mismo directorio que
-- este archivo— líneas 11-20 para el porqué de esa copia) — solo se actualizó
-- `05-codigo/database/migrations/001_init.sql` (la fuente de verdad del diseño, rol DBA). Las dos
-- copias quedan DIVERGENTES hasta que un próximo ciclo de Backend sincronice la copia operativa
-- (copiar el contenido actualizado, o adoptar el mecanismo de build sugerido en
-- `03-arquitectura/modelo-datos.md` §5bis en vez de mantener 2 copias a mano) — hasta entonces, un
-- ambiente NUEVO que arranque desde `backend/migrations/001_init.sql` (un docker-compose/CI/clon
-- local recién creado) NO va a tener `suscripcion_negocio` todavía. No bloquea este ciclo (DBA no
-- modela endpoints ni corre ambientes) pero si Backend arranca su propia ronda de HU-29 antes de
-- sincronizar esa copia, la va a necesitar de entrada.
--
-- Idempotencia: `CREATE TABLE ... IF NOT EXISTS` para la tabla y `CREATE INDEX ... IF NOT EXISTS`
-- para el índice nuevo sobre `turno` (Postgres los soporta de forma nativa). Postgres NO admite
-- `CREATE TYPE ... IF NOT EXISTS` ni `CREATE POLICY ... IF NOT EXISTS` (mismo límite ya
-- documentado en 002/003/004/`runMigrations()`) — los 3 ENUM y las 3 policies quedan envueltos en
-- bloques `DO` con guard contra `pg_type`/`pg_policy`, mismo patrón que 003/004, para que este
-- script sí sea reintentable de punta a punta. El backfill (`INSERT ... SELECT ... FROM negocio`)
-- es reintentable por construcción vía `ON CONFLICT (negocio_id) DO NOTHING` — una segunda corrida
-- no duplica ni pisa ninguna fila ya creada (ni las que puso este backfill, ni las que ya haya
-- podido crear Backend para negocios nuevos si esta migración se corre más de una vez).
--
-- Orden dentro de la transacción — el backfill corre ANTES de habilitar RLS a propósito (mismo
-- patrón que usa `004_notificaciones.sql` para su propio backfill sobre `notificacion`): así el
-- INSERT masivo no depende de qué policy de INSERT exista ni de si el rol que corre este script
-- tiene privilegios especiales — corre como cualquier INSERT normal mientras la tabla todavía no
-- tiene RLS activa, sin importar el resultado (hoy no verificado, ver 001_init.sql §5bis) de si el
-- rol de conexión de Render es o no superusuario/BYPASSRLS.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (DROP/revert explícito de
-- cada objeto que crea este script, en orden inverso de dependencias). No se ejecuta solo; copiar
-- y correr a mano si hace falta revertir. **Único matiz, más importante que el equivalente de
-- 004:** el `DROP TABLE suscripcion_negocio` del rollback no distingue entre las filas que puso el
-- backfill de este archivo (todas en plan 'gratis', triviales de perder) y cualquier fila que ya
-- se haya activado a 'turnario_pro' entre que esta migración corrió y el momento en que alguien
-- decida revertirla — revertir el ESQUEMA completo en ese escenario también borra qué negocios
-- están efectivamente suscriptos. Si ese escenario es real al momento de revertir, exportar
-- `SELECT * FROM suscripcion_negocio WHERE plan <> 'gratis'` antes de correr el rollback.

BEGIN;

-- ---------------------------------------------------------------------------
-- `plan_negocio` / `periodo_suscripcion` / `estado_suscripcion_negocio` + tabla
-- `suscripcion_negocio`. Razonamiento completo (por qué tabla separada y no columna en `negocio`,
-- por qué estos 3 ENUM y estos valores, por qué el CHECK de periodo/vencimiento, por qué
-- creado_por/modificado_por sí y eliminado_en no, por qué NO se modela todavía el purchaseToken
-- real ni el monto) en `001_init.sql`, bloque "Suscripción 'Turnario Pro'", y en
-- `03-arquitectura/modelo-datos.md` §2novies.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'plan_negocio') THEN
    CREATE TYPE plan_negocio AS ENUM ('gratis', 'turnario_pro');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'periodo_suscripcion') THEN
    CREATE TYPE periodo_suscripcion AS ENUM ('mensual', 'anual');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_suscripcion_negocio') THEN
    CREATE TYPE estado_suscripcion_negocio AS ENUM ('activa', 'vencida', 'cancelada');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS suscripcion_negocio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id      UUID NOT NULL UNIQUE REFERENCES negocio(id),
  plan            plan_negocio NOT NULL DEFAULT 'gratis',
  periodo         periodo_suscripcion,
  vencimiento     TIMESTAMPTZ,
  estado          estado_suscripcion_negocio NOT NULL DEFAULT 'activa',
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID,
  CONSTRAINT ck_suscripcion_negocio_periodo_vencimiento_segun_plan CHECK (
    (plan = 'gratis' AND periodo IS NULL AND vencimiento IS NULL)
    OR (plan = 'turnario_pro' AND periodo IS NOT NULL AND vencimiento IS NOT NULL)
  )
);

-- Backfill — SOLO tiene sentido en este archivo (una base ya migrada tiene negocios reales
-- creados antes de este ciclo; `001_init.sql` arranca de una base vacía y no necesita
-- backfillear nada, ver el comentario junto a este mismo bloque ahí). Le da a CADA negocio
-- existente una fila explícita en plan 'gratis' — confiando en los DEFAULT de la tabla de arriba
-- (`plan`/`estado`), no repitiéndolos a mano, para que no puedan desincronizarse de la definición
-- de la tabla. `ON CONFLICT (negocio_id) DO NOTHING` hace que sea seguro reintentar (la 2da
-- corrida no encuentra nada para insertar) y no pisa ninguna fila que ya exista (ej. si esta
-- migración corre después de que Backend ya haya empezado a insertar filas propias para negocios
-- nuevos).
INSERT INTO suscripcion_negocio (negocio_id)
SELECT id FROM negocio
ON CONFLICT (negocio_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Row Level Security — FORCE desde el primer commit (misma lección de `001_init.sql` §5bis: el
-- rol que corre este script se vuelve owner de esta tabla nueva, y Postgres ignora RLS para el
-- owner salvo FORCE). 3 policies: SELECT para cualquier staff del negocio (administrador o
-- profesional activo); INSERT/UPDATE solo para administrador del negocio; sin policy de DELETE
-- (ningún endpoint/HU de este ciclo borra una suscripción). Razonamiento completo de cada policy
-- en `001_init.sql`, mismo bloque.
--
-- ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY SÍ es idempotente en Postgres (no error si ya
-- estaba activado) — no hace falta guard ahí, igual que en 002/003/004. CREATE POLICY sí necesita
-- guard.
-- ---------------------------------------------------------------------------
ALTER TABLE suscripcion_negocio ENABLE ROW LEVEL SECURITY;
ALTER TABLE suscripcion_negocio FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'suscripcion_negocio_select_staff_del_negocio') THEN
    CREATE POLICY suscripcion_negocio_select_staff_del_negocio ON suscripcion_negocio
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM negocio_administrador na
          WHERE na.negocio_id = suscripcion_negocio.negocio_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
        OR EXISTS (
          SELECT 1 FROM negocio_profesional np
          JOIN profesional p ON p.id = np.profesional_id
          WHERE np.negocio_id = suscripcion_negocio.negocio_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'suscripcion_negocio_insert_admin_del_negocio') THEN
    CREATE POLICY suscripcion_negocio_insert_admin_del_negocio ON suscripcion_negocio
      FOR INSERT WITH CHECK (
        EXISTS (
          SELECT 1 FROM negocio_administrador na
          WHERE na.negocio_id = suscripcion_negocio.negocio_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'suscripcion_negocio_update_admin_del_negocio') THEN
    CREATE POLICY suscripcion_negocio_update_admin_del_negocio ON suscripcion_negocio
      FOR UPDATE USING (
        EXISTS (
          SELECT 1 FROM negocio_administrador na
          WHERE na.negocio_id = suscripcion_negocio.negocio_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Índice adicional sobre `turno` (tabla existente, sin cambios de columnas) — soporte del límite
-- de 60 turnos confirmados/mes del plan gratis. Razonamiento completo (por qué `inicio` y no
-- `creado_en`, por qué no hace falta índice para el límite de "1 profesional por negocio") en
-- `001_init.sql`, mismo ciclo.
--
-- Nota de tamaño para quien aplique esto contra Render: `CREATE INDEX` (sin `CONCURRENTLY`) toma
-- un lock que bloquea escrituras sobre `turno` mientras se construye — igual que el resto de este
-- archivo, corre dentro de una transacción, y `CONCURRENTLY` no puede usarse dentro de una
-- transacción. Si `turno` ya tiene un volumen grande de filas al momento de aplicar esto, evaluar
-- correr esta sentencia puntual aparte (fuera de este script, sin transacción, con
-- `CREATE INDEX CONCURRENTLY`) en vez de vía `psql -f` completo — decisión de quien aplique la
-- migración, no cambia el resultado final.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_turno_negocio_confirmado_inicio
  ON turno (negocio_id, inicio)
  WHERE estado = 'confirmado';

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP INDEX IF EXISTS idx_turno_negocio_confirmado_inicio;
--
-- DROP POLICY IF EXISTS suscripcion_negocio_update_admin_del_negocio ON suscripcion_negocio;
-- DROP POLICY IF EXISTS suscripcion_negocio_insert_admin_del_negocio ON suscripcion_negocio;
-- DROP POLICY IF EXISTS suscripcion_negocio_select_staff_del_negocio ON suscripcion_negocio;
-- ALTER TABLE suscripcion_negocio DISABLE ROW LEVEL SECURITY;
--
-- -- CAUTELA (ver nota de alcance al inicio de este archivo): esto borra TODAS las filas,
-- -- incluidas las que se hayan activado a 'turnario_pro' real después de que esta migración
-- -- corrió, no solo el backfill en plan 'gratis'. Exportar antes si corresponde:
-- --   SELECT * FROM suscripcion_negocio WHERE plan <> 'gratis';
-- DROP TABLE IF EXISTS suscripcion_negocio;
--
-- DROP TYPE IF EXISTS estado_suscripcion_negocio;
-- DROP TYPE IF EXISTS periodo_suscripcion;
-- DROP TYPE IF EXISTS plan_negocio;
-- COMMIT;
-- ============================================================================
