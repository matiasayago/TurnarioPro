-- Turnos Profesionales — migración incremental 007 (Postgres)
-- Rol: DBA · Fase 3 — Diseño (fast-follow de la épica E15 "Modo Administrador v1", 2026-08-15 —
-- ver memory/proyectos/turnos-profesionales/decisiones.md, entrada "E15 'Modo Administrador v1'",
-- y 03-arquitectura/modelo-datos.md §5septies para el razonamiento completo de esta ronda)
--
-- QUÉ ES ESTE ARCHIVO Y POR QUÉ EXISTE — mismo motivo operativo que
-- 002_pacientes_historial_auth_google.sql/003_privacidad_usuario.sql/004_notificaciones.sql/
-- 005_suscripcion_negocio.sql/006_suscripcion_negocio_policy_contexto.sql (ver sus propios
-- headers para el diagnóstico completo): `runMigrations()` (backend/src/db.ts) corre
-- `001_init.sql` COMPLETO una sola vez por base de datos, gateado por un chequeo simple ("¿ya
-- existe la tabla `usuario`?" → si existe, se omite TODO el script sin ejecutar ni una sola
-- sentencia). En Render producción esa tabla ya existe desde hace varios ciclos — así que editar
-- `001_init.sql` con las 3 policies nuevas (ya aplicado en este mismo ciclo, en las DOS copias —
-- `database/migrations/001_init.sql` y `backend/migrations/001_init.sql` quedan byte-idénticas)
-- es necesario para cualquier ambiente que migre desde cero, pero NO alcanza para que Render las
-- reciba en el próximo deploy — el gate de `runMigrations()` salta el script completo, sin error,
-- sin aviso.
--
-- Este archivo es el DELTA que hace falta aplicar A MANO contra un ambiente YA migrado (Render
-- producción; o cualquier docker-compose/CI cuyo volumen de Postgres persista entre corridas y ya
-- haya corrido una vez). NO se ejecuta automáticamente — `runMigrations()` no lo conoce (solo lee
-- el nombre de archivo hardcodeado "001_init.sql", ver backend/src/db.ts). Para aplicarlo:
--
--   psql "$DATABASE_URL" -f 007_paciente_historial_acceso_administrador.sql
--
-- (o pegar el contenido en el shell de psql que exponga el proveedor de hosting, ej. el "Connect"
-- de Render) — correrlo con el rol de MIGRACIÓN/owner, igual que los archivos anteriores, no con
-- el rol de runtime si ya se separaron roles (ver ../scripts/provisionar_roles_postgres.sql).
--
-- QUÉ HACE — puramente aditivo, sin DDL de esquema (no crea tablas, columnas ni tipos nuevos): 3
-- policies `FOR SELECT` nuevas, una sobre `paciente`, una sobre `tratamiento`, una sobre
-- `nota_medica`, que habilitan a un administrador (`negocio_administrador`) del `negocio_id` de la
-- fila a LEERLA. Ninguna de las 3 policies `FOR ALL` ya existentes sobre esas tablas
-- (`paciente_acceso_propio_profesional`/`tratamiento_acceso_via_paciente`/
-- `nota_medica_acceso_via_paciente`, aplicadas contra Render por `002_pacientes_historial_auth_
-- google.sql`) se toca — siguen siendo, sin cambios, la única fuente de autorización de escritura
-- (INSERT/UPDATE/DELETE), exclusiva del profesional dueño de la fila. Detalle completo del
-- razonamiento (por qué solo lectura y no también escritura, por qué no hace falta separar las
-- policies existentes en SELECT/resto, verificación contra el código real de Backend) en
-- `001_init.sql`, bloque "Acceso de administrador al historial de pacientes — SOLO LECTURA", y en
-- `03-arquitectura/modelo-datos.md` §5septies.
--
-- Idempotencia: Postgres NO admite `CREATE POLICY ... IF NOT EXISTS` (mismo límite ya documentado
-- en 002/003/004/005/006) — las 3 policies quedan envueltas en un único bloque `DO` con guard
-- contra `pg_policy`, mismo patrón que usa `005_suscripcion_negocio.sql` para sus 3 policies (una
-- corrida repetida no falla, simplemente no hace nada la segunda vez). `ALTER TABLE ...
-- ENABLE/FORCE ROW LEVEL SECURITY` NO hace falta acá: `paciente`/`tratamiento`/`nota_medica` ya
-- tienen RLS forzada desde `002_pacientes_historial_auth_google.sql` — este archivo solo agrega
-- policies sobre tablas que ya están bajo RLS forzada (agregar una policy nueva no requiere que la
-- tabla tenga RLS habilitada, pero acá ya la tiene desde 002, así que no hay nada que repetir).
--
-- Reversible — ver bloque ROLLBACK comentado al final de este archivo (3 `DROP POLICY`, sin
-- ningún otro objeto que revertir). No se ejecuta solo; copiar y correr a mano si hace falta
-- revertir. Revertir esto solo retira la capacidad de LECTURA del administrador — no afecta la
-- escritura (nunca la tuvo) ni el acceso del profesional dueño de cada fila (policies separadas,
-- sin tocar por este archivo).

BEGIN;

-- ---------------------------------------------------------------------------
-- Acceso de administrador al historial de pacientes — SOLO LECTURA. Razonamiento completo (por
-- qué solo SELECT y no también INSERT/UPDATE/DELETE, por qué 3 policies nuevas en vez de separar
-- las 3 `FOR ALL` existentes, verificación contra el código real de Backend) en `001_init.sql`,
-- mismo bloque, y en `03-arquitectura/modelo-datos.md` §5septies.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'paciente_select_admin_del_negocio') THEN
    CREATE POLICY paciente_select_admin_del_negocio ON paciente
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM negocio_administrador na
          WHERE na.negocio_id = paciente.negocio_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'tratamiento_select_admin_del_negocio') THEN
    CREATE POLICY tratamiento_select_admin_del_negocio ON tratamiento
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN negocio_administrador na ON na.negocio_id = pa.negocio_id
          WHERE pa.id = tratamiento.paciente_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'nota_medica_select_admin_del_negocio') THEN
    CREATE POLICY nota_medica_select_admin_del_negocio ON nota_medica
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM paciente pa
          JOIN negocio_administrador na ON na.negocio_id = pa.negocio_id
          WHERE pa.id = nota_medica.paciente_id
            AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
        )
      );
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- BEGIN;
-- DROP POLICY IF EXISTS nota_medica_select_admin_del_negocio ON nota_medica;
-- DROP POLICY IF EXISTS tratamiento_select_admin_del_negocio ON tratamiento;
-- DROP POLICY IF EXISTS paciente_select_admin_del_negocio ON paciente;
-- COMMIT;
-- ============================================================================
