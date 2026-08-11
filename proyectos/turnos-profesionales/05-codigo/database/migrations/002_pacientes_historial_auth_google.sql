-- Turnos Profesionales — migración incremental 002 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (ciclo HU-20/HU-21/HU-35, 2026-08-10)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — a diferencia de todo el historial previo de este
-- proyecto, que evolucionó un único 001_init.sql en el lugar en cada ciclo (ver su propio header
-- y modelo-datos.md §2ter/§2quater/§5bis): `runMigrations()` (backend/src/db.ts) corre
-- 001_init.sql COMPLETO una sola vez por base de datos, gateado por un chequeo simple
-- ("¿ya existe la tabla `usuario`?" → si existe, se omite TODO el script sin ejecutar ni una
-- sola sentencia). Hasta el ciclo anterior (§5bis, 2026-08-09) esto no importaba en la práctica:
-- cada edición de 001_init.sql ocurría ANTES de que existiera ningún Postgres ya migrado
-- (docker-compose/CI se recrean desde cero en cada corrida; Render corrió su primera migración
-- en ese mismo ciclo). En ESTE ciclo, por primera vez, ya existe un Postgres de producción real
-- y persistente en Render (`https://turnos-profesionales-backend.onrender.com`, confirmado
-- activo con datos ya migrados) con la tabla `usuario` ya creada — así que cualquier edición
-- directa a 001_init.sql (tablas/columnas nuevas) queda invisible para Render en el próximo
-- deploy: el gate de `runMigrations()` la salta por completo, sin error, sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 002_pacientes_historial_auth_google.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que 001_init.sql, no con el rol de
-- runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- 001_init.sql (ambas copias, database/ y backend/) SÍ se actualizó en este mismo ciclo con el
-- mismo contenido final (mismas tablas/columnas, con el razonamiento completo en sus
-- comentarios) — sigue siendo correcto y necesario para cualquier ambiente NUEVO que corra la
-- migración desde cero por primera vez (un clon local nuevo, un service container de CI, un
-- docker-compose recién creado, o un eventual segundo ambiente). Este archivo 002 es
-- EXCLUSIVAMENTE para cerrar la brecha en ambientes que ya migraron antes de este ciclo. Por eso
-- acá NO se repite el razonamiento completo de cada columna/policy (por qué esta forma y no
-- otra) — ya está documentado en los comentarios de 001_init.sql y en
-- 03-arquitectura/modelo-datos.md; acá solo lo mínimo para que este archivo sea legible de forma
-- independiente.
--
-- Recomendación de seguimiento para Backend/DevOps (NO implementada acá, fuera del alcance de
-- DBA en este ciclo): extender `runMigrations()` para soportar una secuencia de migraciones
-- numeradas con una tabla de control (ej. `schema_migrations(version, aplicada_en)`), en vez de
-- un único script "todo o nada" gateado por la existencia de `usuario`. Este archivo 002 es
-- exactamente el caso de uso que ese mecanismo resolvería de forma automática y auditable, en
-- vez de manual.
--
-- Idempotencia: CREATE TABLE / ADD COLUMN usan guards IF NOT EXISTS (Postgres los soporta) para
-- que un reintento accidental no rompa. CREATE POLICY NO admite IF NOT EXISTS en Postgres (mismo
-- límite ya documentado en 001_init.sql/backend/src/db.ts) — las 3 nuevas están envueltas en
-- bloques DO con manejo de la excepción `duplicate_object` para que este script sí sea
-- reintentable de punta a punta (a diferencia de 001_init.sql, que depende enteramente del gate
-- externo de `runMigrations()` para su idempotencia) — ver el porqué de esta diferencia más abajo,
-- junto a cada bloque DO.
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (DROP explícito de cada
-- objeto que crea/altera este script, en orden inverso de dependencias). No se ejecuta solo;
-- copiar y correr a mano si hace falta revertir.

BEGIN;

-- ---------------------------------------------------------------------------
-- HU-20 — negocio.es_rubro_salud (D11/RN15) y paciente.* — razonamiento completo del porqué de
-- esta forma (tabla nueva NO 1:1 con usuario, sino 1 fila por negocio_id+profesional_id+
-- cliente_id) en 001_init.sql, bloque "Ficha de paciente extendida + historial clínico", y en
-- 03-arquitectura/modelo-datos.md.
-- ---------------------------------------------------------------------------
ALTER TABLE negocio ADD COLUMN IF NOT EXISTS es_rubro_salud BOOLEAN NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- HU-35 — login con Google (razonamiento completo: 001_init.sql, comentario sobre
-- `CREATE TABLE usuario`, y backlog.md, sección HU-35).
-- ---------------------------------------------------------------------------
ALTER TABLE usuario ALTER COLUMN password_hash DROP NOT NULL;
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS google_id TEXT;
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS telefono TEXT;

-- ADD CONSTRAINT no admite IF NOT EXISTS en Postgres — guard manual contra pg_constraint para
-- que este script sea reintentable (a diferencia del resto de 001_init.sql, que no lo necesita
-- porque nunca se re-corre sin pasar primero por el gate de runMigrations()).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_usuario_google_id') THEN
    ALTER TABLE usuario ADD CONSTRAINT uq_usuario_google_id UNIQUE (google_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_usuario_password_o_google') THEN
    ALTER TABLE usuario ADD CONSTRAINT ck_usuario_password_o_google
      CHECK (password_hash IS NOT NULL OR google_id IS NOT NULL);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- HU-20 — tabla paciente
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS paciente (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id                    UUID NOT NULL REFERENCES negocio(id),
  profesional_id                UUID NOT NULL REFERENCES profesional(id),
  cliente_id                    UUID NOT NULL REFERENCES usuario(id),
  fecha_nacimiento              DATE,
  genero                        TEXT,
  direccion                     TEXT,
  contacto_emergencia_nombre    TEXT,
  contacto_emergencia_telefono  TEXT,
  contacto_emergencia_relacion  TEXT,
  alergias                      TEXT,
  notas_medicas_generales       TEXT,
  activo                        BOOLEAN NOT NULL DEFAULT true,
  creado_en                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por                    UUID,
  modificado_en                 TIMESTAMPTZ,
  modificado_por                UUID,
  eliminado_en                  TIMESTAMPTZ,
  CONSTRAINT uq_paciente_negocio_profesional_cliente UNIQUE (negocio_id, profesional_id, cliente_id)
);
CREATE INDEX IF NOT EXISTS idx_paciente_cliente ON paciente (cliente_id);

-- ---------------------------------------------------------------------------
-- HU-21 — tratamiento / nota_medica
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tratamiento (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id     UUID NOT NULL REFERENCES paciente(id),
  descripcion     TEXT NOT NULL,
  fecha_inicio    DATE NOT NULL,
  fecha_fin       DATE,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID
);
CREATE INDEX IF NOT EXISTS idx_tratamiento_paciente ON tratamiento (paciente_id);

CREATE TABLE IF NOT EXISTS nota_medica (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id     UUID NOT NULL REFERENCES paciente(id),
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  texto           TEXT NOT NULL,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID
);
CREATE INDEX IF NOT EXISTS idx_nota_medica_paciente ON nota_medica (paciente_id);

-- ---------------------------------------------------------------------------
-- Row Level Security — ver 001_init.sql (bloque "RLS de paciente/tratamiento/nota_medica") para
-- el razonamiento completo de cada policy: dueño único = el profesional referenciado, sin acceso
-- de administrador/otros profesionales/cliente, por RN7/RN13/D3. FORCE desde el primer commit
-- (lección de §5bis de 001_init.sql: el rol que corre este script se vuelve owner de estas 3
-- tablas nuevas, y Postgres ignora RLS para el owner salvo FORCE).
--
-- ALTER TABLE ... ENABLE/FORCE ROW LEVEL SECURITY SÍ es idempotente en Postgres (no error si ya
-- estaba activado) — no hace falta guard ahí. CREATE POLICY sí necesita guard (ver DO más abajo).
-- ---------------------------------------------------------------------------
ALTER TABLE paciente ENABLE ROW LEVEL SECURITY;
ALTER TABLE paciente FORCE ROW LEVEL SECURITY;
ALTER TABLE tratamiento ENABLE ROW LEVEL SECURITY;
ALTER TABLE tratamiento FORCE ROW LEVEL SECURITY;
ALTER TABLE nota_medica ENABLE ROW LEVEL SECURITY;
ALTER TABLE nota_medica FORCE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'paciente_acceso_propio_profesional') THEN
    CREATE POLICY paciente_acceso_propio_profesional ON paciente
      USING (
        EXISTS (
          SELECT 1 FROM negocio_profesional np
          JOIN profesional p ON p.id = np.profesional_id
          WHERE np.negocio_id = paciente.negocio_id
            AND np.profesional_id = paciente.profesional_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM negocio_profesional np
          JOIN profesional p ON p.id = np.profesional_id
          WHERE np.negocio_id = paciente.negocio_id
            AND np.profesional_id = paciente.profesional_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'tratamiento_acceso_via_paciente') THEN
    CREATE POLICY tratamiento_acceso_via_paciente ON tratamiento
      USING (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN profesional p ON p.id = pa.profesional_id
          WHERE pa.id = tratamiento.paciente_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN profesional p ON p.id = pa.profesional_id
          WHERE pa.id = tratamiento.paciente_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'nota_medica_acceso_via_paciente') THEN
    CREATE POLICY nota_medica_acceso_via_paciente ON nota_medica
      USING (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN profesional p ON p.id = pa.profesional_id
          WHERE pa.id = nota_medica.paciente_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN profesional p ON p.id = pa.profesional_id
          WHERE pa.id = nota_medica.paciente_id
            AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP TABLE IF EXISTS nota_medica;
-- DROP TABLE IF EXISTS tratamiento;
-- DROP TABLE IF EXISTS paciente;
-- ALTER TABLE usuario DROP CONSTRAINT IF EXISTS ck_usuario_password_o_google;
-- ALTER TABLE usuario DROP CONSTRAINT IF EXISTS uq_usuario_google_id;
-- ALTER TABLE usuario DROP COLUMN IF EXISTS telefono;
-- ALTER TABLE usuario DROP COLUMN IF EXISTS google_id;
-- -- OJO: revertir password_hash a NOT NULL solo es seguro si ninguna cuenta 100% Google se dio
-- -- de alta todavía (si existe alguna fila con password_hash NULL, este ALTER falla en Postgres,
-- -- tal como debe: resolver esas filas primero — asignarles un hash o eliminarlas a mano — no es
-- -- automatizable a ciegas).
-- ALTER TABLE usuario ALTER COLUMN password_hash SET NOT NULL;
-- ALTER TABLE negocio DROP COLUMN IF EXISTS es_rubro_salud;
-- COMMIT;
