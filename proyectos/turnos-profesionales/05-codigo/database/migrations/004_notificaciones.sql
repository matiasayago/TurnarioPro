-- Turnos Profesionales — migración incremental 004 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (ciclo HU-14b/HU-25/HU-26, 2026-08-12)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- `002_pacientes_historial_auth_google.sql`/`003_privacidad_usuario.sql` (ver sus propios headers
-- para el diagnóstico completo): `runMigrations()` (backend/src/db.ts) corre `001_init.sql`
-- COMPLETO una sola vez por base de datos, gateado por un chequeo simple ("¿ya existe la tabla
-- `usuario`?" → si existe, se omite TODO el script sin ejecutar ni una sola sentencia). En Render
-- producción esa tabla ya existe desde el ciclo de HU-20/HU-21/HU-35 (2026-08-10) — así que editar
-- `001_init.sql` con los cambios de este ciclo (ya aplicado, ambas copias:
-- `05-codigo/database/migrations/001_init.sql` y `05-codigo/backend/migrations/001_init.sql`) es
-- necesario para cualquier ambiente que migre desde cero, pero NO alcanza para que Render lo
-- reciba en el próximo deploy — el gate de `runMigrations()` salta el script completo, sin error,
-- sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 004_notificaciones.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que 001_init.sql/002/003, no con el
-- rol de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- Numerado "004" y no "003" a propósito, aunque en esta rama (`feature/notificaciones`, parada
-- sobre `main`) el último archivo incremental existente es `002_pacientes_historial_auth_google.
-- sql`: `003_privacidad_usuario.sql` (HU-32) ya existe en paralelo en
-- `feature/configuracion-profesional`, todavía no mergeada a `main`. Reservar "004" acá evita que
-- ambas ramas registren un archivo "003" distinto y colisionen al mergear — instrucción explícita
-- recibida para este ciclo, aplicada tal cual.
--
-- Este archivo NO depende de que `003_privacidad_usuario.sql` (ni la tabla que crea,
-- `usuario_preferencias`) haya corrido en este ambiente — a propósito. Ver el razonamiento
-- completo en `001_init.sql`, bloque "Preferencias de notificación":
-- `usuario_preferencias_notificacion` es una tabla propia, sin ninguna referencia a
-- `usuario_preferencias`, específicamente para que este archivo se pueda aplicar contra Render
-- sin importar en qué orden terminen mergeándose ambos ciclos (HU-32 y HU-14b/HU-25/HU-26).
--
-- `001_init.sql` (ambas copias, `database/` y `backend/`) SÍ se actualizó en este mismo ciclo con
-- el mismo contenido final (mismo razonamiento completo en sus comentarios) — sigue siendo
-- correcto y necesario para cualquier ambiente NUEVO que corra la migración desde cero. Este
-- archivo 004 es EXCLUSIVAMENTE para cerrar la brecha en ambientes que ya migraron antes de este
-- ciclo. Por eso acá NO se repite el razonamiento completo de cada decisión (por qué
-- `destinatario_usuario_id` es nullable y no NOT NULL, por qué `leido` booleano simple sin
-- `leido_en` dedicado, por qué NO se guarda texto/nombre/hora armados en la fila, por qué `tipo`
-- pasa a ENUM, por qué tabla nueva y no extender `usuario_preferencias`, el diseño de cada
-- policy) — ya está documentado en los comentarios de `001_init.sql` y en
-- `03-arquitectura/modelo-datos.md` §2octies/§5quinquies; acá solo lo mínimo para que este
-- archivo sea legible de forma independiente, más el backfill, que SOLO tiene sentido acá (una
-- base ya migrada puede tener filas `notificacion` existentes de antes de este ciclo;
-- `001_init.sql` arranca de una base vacía y no necesita backfillear nada).
--
-- Idempotencia: `ADD COLUMN IF NOT EXISTS`/`CREATE TABLE IF NOT EXISTS`/`CREATE INDEX IF NOT
-- EXISTS` para columnas/tablas/índices (Postgres los soporta de forma nativa). El backfill
-- (`UPDATE ... WHERE destinatario_usuario_id IS NULL`) es reintentable por construcción: la
-- segunda corrida no encuentra filas para actualizar. La conversión de `tipo` a ENUM
-- (`ALTER COLUMN ... TYPE ... USING ...`) también es segura de reintentar: convertir una columna
-- que YA es del tipo destino, al mismo tipo, es un no-op válido en Postgres (no tira error).
-- Postgres NO admite `CREATE TYPE ... IF NOT EXISTS` ni `CREATE POLICY ... IF NOT EXISTS` (mismo
-- límite ya documentado en 002/003/`runMigrations()`) — el ENUM y las policies quedan envueltos
-- en bloques `DO` con guard contra `pg_type`/`pg_policy`, mismo patrón que 002/003, para que este
-- script sí sea reintentable de punta a punta.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (DROP/revert explícito de
-- cada objeto que crea/altera este script, en orden inverso de dependencias). No se ejecuta solo;
-- copiar y correr a mano si hace falta revertir. Único matiz: el `UPDATE` de backfill no es
-- reversible celda por celda (no queda registro de qué valor tenía cada fila ANTES del backfill —
-- siempre NULL, porque la columna no existía) — revertir la COLUMNA completa (DROP COLUMN, en el
-- bloque de abajo) ya es la reversión correcta y suficiente, mismo criterio que 002/003 (revierte
-- el esquema, no reconstruye un historial de valores intermedios que nunca existió).

BEGIN;

-- ---------------------------------------------------------------------------
-- `tipo_notificacion` — razonamiento completo en 001_init.sql, bloque "Bandeja de
-- notificaciones".
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_notificacion') THEN
    CREATE TYPE tipo_notificacion AS ENUM ('confirmacion', 'recordatorio', 'cancelacion', 'reprogramacion');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- `notificacion` — destinatario + leído + tipo ENUM. Razonamiento completo (por qué
-- `destinatario_usuario_id` es NULLABLE y no NOT NULL, por qué `leido` booleano simple sin
-- `leido_en` dedicado, por qué NO se guarda texto/nombre/hora armados en la fila, por qué `tipo`
-- pasa a ENUM) en 001_init.sql, bloque "Bandeja de notificaciones".
-- ---------------------------------------------------------------------------
ALTER TABLE notificacion ADD COLUMN IF NOT EXISTS destinatario_usuario_id UUID REFERENCES usuario(id);
ALTER TABLE notificacion ADD COLUMN IF NOT EXISTS leido BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE notificacion ADD COLUMN IF NOT EXISTS modificado_en TIMESTAMPTZ;

-- Backfill — SOLO tiene sentido en este archivo (una base ya migrada puede tener filas
-- `notificacion` existentes de antes de este ciclo; `001_init.sql` arranca de una base vacía).
-- Investigado contra el código real (ver 001_init.sql): hasta este ciclo el ÚNICO tipo que se
-- insertaba era 'confirmacion', desde POST /turnos y PATCH /:id/reprogramar — en los dos casos
-- pensado para avisar al PROFESIONAL del turno (ver el razonamiento completo del porqué en
-- 001_init.sql). Se deriva acá con el mismo JOIN turno -> profesional que ya usa el código para
-- el alta de `paciente` en POST /turnos. `WHERE destinatario_usuario_id IS NULL` hace que sea
-- seguro reintentar (la 2da corrida no encuentra nada para actualizar) y además no pisa ningún
-- valor que Backend ya haya empezado a completar por su cuenta si este archivo se corre después
-- de que Backend adopte la recomendación de 001_init.sql.
UPDATE notificacion n
SET destinatario_usuario_id = p.usuario_id
FROM turno t
JOIN profesional p ON p.id = t.profesional_id
WHERE n.turno_id = t.id
  AND n.destinatario_usuario_id IS NULL;

-- Conversión TEXT -> ENUM. Segura contra los datos reales de este proyecto: el único valor que
-- pudo haberse insertado hasta hoy es 'confirmacion' (ver backfill de arriba), y ese label existe
-- en el ENUM nuevo sin cambios — ninguna fila puede fallar el cast.
ALTER TABLE notificacion ALTER COLUMN tipo TYPE tipo_notificacion USING tipo::tipo_notificacion;

CREATE INDEX IF NOT EXISTS idx_notificacion_destinatario ON notificacion (destinatario_usuario_id, creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_notificacion_destinatario_no_leida ON notificacion (destinatario_usuario_id) WHERE leido = false;

-- ---------------------------------------------------------------------------
-- RLS de `notificacion` — primera vez que esta tabla tiene RLS (ver 001_init.sql, bloque "RLS de
-- la bandeja de notificaciones..." para el razonamiento completo de cada policy, incluido por qué
-- la de INSERT acepta `destinatario_usuario_id IS NULL` — compat con los 2 call sites que hoy
-- insertan sin esa columna). FORCE necesario para que tenga efecto real contra el rol owner — ver
-- bloque grande "Separación owner/runtime..." en 001_init.sql.
--
-- ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY SÍ es idempotente en Postgres (no error si ya
-- estaba activado) — no hace falta guard ahí, igual que en 002/003. CREATE POLICY sí necesita
-- guard.
-- ---------------------------------------------------------------------------
ALTER TABLE notificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificacion FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'notificacion_select_propia') THEN
    CREATE POLICY notificacion_select_propia ON notificacion
      FOR SELECT USING (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'notificacion_update_propia_marcar_leida') THEN
    CREATE POLICY notificacion_update_propia_marcar_leida ON notificacion
      FOR UPDATE
      USING (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
      WITH CHECK (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'notificacion_insert_evento_turno') THEN
    CREATE POLICY notificacion_insert_evento_turno ON notificacion
      FOR INSERT WITH CHECK (
        EXISTS (
          SELECT 1 FROM turno t
          WHERE t.id = notificacion.turno_id
            AND (
              t.cliente_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
              OR EXISTS (
                SELECT 1 FROM negocio_administrador na
                WHERE na.negocio_id = t.negocio_id
                  AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
              )
              OR EXISTS (
                SELECT 1 FROM negocio_profesional np
                JOIN profesional p ON p.id = np.profesional_id
                WHERE np.negocio_id = t.negocio_id
                  AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
              )
            )
        )
        AND (
          notificacion.destinatario_usuario_id IS NULL
          OR EXISTS (
            SELECT 1 FROM turno t
            JOIN profesional p ON p.id = t.profesional_id
            WHERE t.id = notificacion.turno_id
              AND (t.cliente_id = notificacion.destinatario_usuario_id OR p.usuario_id = notificacion.destinatario_usuario_id)
          )
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'notificacion_insert_job_sistema') THEN
    CREATE POLICY notificacion_insert_job_sistema ON notificacion
      FOR INSERT WITH CHECK (
        current_setting('app.job_sistema', true) = 'true'
      );
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- `usuario_preferencias_notificacion` (HU-26) — razonamiento completo (por qué tabla nueva y no
-- columnas en `usuario_preferencias`, por qué estas 7 columnas y estos defaults, por qué sin
-- creado_por/modificado_por/eliminado_en) en 001_init.sql, bloque "Preferencias de notificación",
-- y en 03-arquitectura/modelo-datos.md §2octies. Tabla 100% nueva y autocontenida — sin ninguna
-- referencia a `usuario_preferencias` (ver ese mismo bloque para por qué) — este `CREATE TABLE`
-- no depende de que `003_privacidad_usuario.sql` (`feature/configuracion-profesional`) haya
-- corrido en este ambiente.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario_preferencias_notificacion (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id                  UUID NOT NULL UNIQUE REFERENCES usuario(id),
  notif_canal_push            BOOLEAN NOT NULL DEFAULT true,
  notif_canal_email           BOOLEAN NOT NULL DEFAULT true,
  notif_canal_whatsapp        BOOLEAN NOT NULL DEFAULT true,
  notif_citas_recordatorios   BOOLEAN NOT NULL DEFAULT true,
  notif_promociones           BOOLEAN NOT NULL DEFAULT false,
  notif_sonido                BOOLEAN NOT NULL DEFAULT true,
  notif_vibracion             BOOLEAN NOT NULL DEFAULT true,
  creado_en                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en               TIMESTAMPTZ
);

ALTER TABLE usuario_preferencias_notificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_preferencias_notificacion FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'usuario_preferencias_notificacion_acceso_propio') THEN
    CREATE POLICY usuario_preferencias_notificacion_acceso_propio ON usuario_preferencias_notificacion
      USING (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
      WITH CHECK (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP POLICY IF EXISTS usuario_preferencias_notificacion_acceso_propio ON usuario_preferencias_notificacion;
-- DROP TABLE IF EXISTS usuario_preferencias_notificacion;
--
-- DROP POLICY IF EXISTS notificacion_insert_job_sistema ON notificacion;
-- DROP POLICY IF EXISTS notificacion_insert_evento_turno ON notificacion;
-- DROP POLICY IF EXISTS notificacion_update_propia_marcar_leida ON notificacion;
-- DROP POLICY IF EXISTS notificacion_select_propia ON notificacion;
-- ALTER TABLE notificacion DISABLE ROW LEVEL SECURITY;
-- DROP INDEX IF EXISTS idx_notificacion_destinatario_no_leida;
-- DROP INDEX IF EXISTS idx_notificacion_destinatario;
-- ALTER TABLE notificacion ALTER COLUMN tipo TYPE TEXT USING tipo::TEXT;
-- ALTER TABLE notificacion DROP COLUMN IF EXISTS modificado_en;
-- ALTER TABLE notificacion DROP COLUMN IF EXISTS leido;
-- ALTER TABLE notificacion DROP COLUMN IF EXISTS destinatario_usuario_id;
-- DROP TYPE IF EXISTS tipo_notificacion;
-- COMMIT;
-- ============================================================================
