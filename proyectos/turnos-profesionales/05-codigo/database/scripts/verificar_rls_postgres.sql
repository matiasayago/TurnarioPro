-- Verificación de Row Level Security a nivel de base de datos — Turnos Profesionales
-- Rol: DBA · script auxiliar, agregado a pedido EXPLÍCITO de Security en su revisión
-- independiente de la ratificación de RLS (2026-08-09, ver ../migrations/001_init.sql).
--
-- POR QUÉ EXISTE. Ningún test HTTP de backend/scripts/*.mjs puede detectar un gap de RLS real,
-- porque la autorización de aplicación (los WHERE de cada query + los checks de cada handler, ej.
-- `esPropioProfesional()`) cubre el mismo terreno y lo esconde: si RLS estuviera completamente
-- bypasseada — como lo estuvo hasta este ciclo, ver el hallazgo de ownership en
-- ../migrations/001_init.sql — esos tests HTTP igual pasarían en verde, porque nunca dependieron
-- de RLS para dar el resultado correcto. Este script se conecta DIRECTO a Postgres con los roles
-- reales (sin pasar por la app en absoluto) y verifica que las políticas filtren de verdad.
--
-- REQUIERE: los 2 roles de provisionar_roles_postgres.sql (mismo directorio) ya creados y sus
-- GRANTs ya aplicados, y ../migrations/001_init.sql ya corrida en la base contra la que se ejecuta
-- esto. NO VERIFICADO CONTRA UN POSTGRES REAL — este entorno de desarrollo no tiene psql/Docker
-- instalados (mismo caveat que el resto de este proyecto documenta, ver
-- ../../03-arquitectura/modelo-datos.md §5). Revisar con atención antes de confiar en él a ciegas
-- la primera vez que corra de verdad — en particular el uso de `SET ROLE` (ver nota más abajo) y
-- los nombres exactos de rol, que dependen de cómo se haya invocado
-- provisionar_roles_postgres.sql en cada ambiente.
--
-- CÓMO CORRERLO (conectado como un rol que pueda hacer `SET ROLE` a ambos roles de prueba —
-- superusuario, o miembro de ambos vía `GRANT <rol> TO <quien_conecta>`; en docker-compose/CI el
-- rol único de hoy alcanza):
--
--   psql "$MIGRADOR_DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -v migrador_rol=turnos_migrador -v app_rol=turnos_app \
--     -f verificar_rls_postgres.sql
--
-- Con `ON_ERROR_STOP=1`, cualquier `RAISE EXCEPTION` de los bloques de abajo corta la ejecución
-- con código de salida distinto de 0 — apto para un step de CI el día que exista un ambiente con
-- los roles ya separados (ver la recomendación en provisionar_roles_postgres.sql, paso 6).
--
-- Todo el script corre dentro de una única transacción con ROLLBACK al final (última línea) — no
-- deja ningún dato de prueba persistido en la base, sin importar el resultado.
--
-- Nota sobre `SET ROLE`: se usa (en vez de reconectar con `psql` una vez por rol) para poder
-- correr todo esto en una sola invocación y una sola transacción. Cambia el usuario efectivo para
-- chequeos de privilegios dentro de la misma sesión, incluida la evaluación de RLS y de "soy el
-- owner de esta tabla" — es el comportamiento documentado de Postgres para `SET ROLE`, pero si el
-- resultado observado la primera vez no coincidiera con lo esperado acá, probar reconectando con
-- `psql` por separado para cada rol como alternativa más estricta antes de asumir un bug en las
-- políticas mismas.

\set ON_ERROR_STOP on
BEGIN;

-- CORRECCIÓN (2026-08-10, confirmado en el primer run real de CI): dentro de un bloque
-- `DO $$ ... $$` (o el cuerpo de cualquier función PL/pgSQL), psql NO sustituye `:'variable'`/
-- `:"variable"` — el $$ existe justamente para que su contenido viaje literal al servidor sin
-- que psql lo toque, así que cada referencia quedaba como el carácter ":" crudo y el parser de
-- PL/pgSQL la rechazaba ("syntax error at or near ':'"). Fuera de un bloque $$ (sentencias SQL
-- sueltas, como los `SET ROLE :"migrador_rol";` de más abajo) la sustitución de psql sí aplica
-- normalmente — no se tocan esos casos. Para los usos DENTRO de un bloque $$, se resuelve
-- guardando los valores como variables de sesión de Postgres ANTES (con `set_config`, en una
-- sentencia suelta) y leyéndolas DENTRO de cada bloque con `current_setting`, en vez de la
-- sustitución de texto de psql.
SELECT set_config('verificar_rls.migrador_rol', :'migrador_rol', true);
SELECT set_config('verificar_rls.app_rol', :'app_rol', true);

-- ============================================================================
-- Parte 0 — chequeos de metadata (no necesitan datos de prueba)
-- ============================================================================

DO $$
DECLARE
  tablas_sin_force TEXT;
BEGIN
  SELECT string_agg(relname, ', ')
  INTO tablas_sin_force
  FROM pg_class
  WHERE relname IN ('profesional', 'negocio_administrador', 'negocio_profesional', 'servicio', 'turno')
    AND relnamespace = 'public'::regnamespace
    AND relrowsecurity = true
    AND relforcerowsecurity = false;

  IF tablas_sin_force IS NOT NULL THEN
    RAISE EXCEPTION 'FALLA Parte 0: FORCE ROW LEVEL SECURITY no está activo en: %', tablas_sin_force;
  END IF;
  RAISE NOTICE 'OK Parte 0: FORCE ROW LEVEL SECURITY activo en las 5 tablas con RLS.';
END $$;

DO $$
DECLARE
  es_super BOOLEAN;
  bypassea_rls BOOLEAN;
BEGIN
  SELECT rolsuper, rolbypassrls INTO es_super, bypassea_rls
  FROM pg_roles WHERE rolname = current_setting('verificar_rls.app_rol');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FALLA Parte 0: el rol de runtime % no existe — correr provisionar_roles_postgres.sql primero.', current_setting('verificar_rls.app_rol');
  END IF;
  IF es_super OR bypassea_rls THEN
    RAISE EXCEPTION 'FALLA Parte 0: el rol de runtime % tiene rolsuper=% / rolbypassrls=% — RLS NO puede tener efecto real con este rol.', current_setting('verificar_rls.app_rol'), es_super, bypassea_rls;
  END IF;
  RAISE NOTICE 'OK Parte 0: el rol de runtime % no es superusuario ni BYPASSRLS.', current_setting('verificar_rls.app_rol');
END $$;

DO $$
DECLARE
  es_super BOOLEAN;
  bypassea_rls BOOLEAN;
BEGIN
  -- Informativo, no hace RAISE EXCEPTION acá: el rol de MIGRACIÓN siendo superusuario/BYPASSRLS
  -- es exactamente el estado ANTERIOR a la separación de roles (ver ../migrations/001_init.sql) —
  -- si se está corriendo este script para diagnosticar ESE estado a propósito (ej. pasando el
  -- rol único de hoy como migrador_rol Y como app_rol), es esperable. La Parte 3, más abajo, es
  -- la que realmente prueba si esto importa en la práctica para este rol puntual.
  SELECT rolsuper, rolbypassrls INTO es_super, bypassea_rls
  FROM pg_roles WHERE rolname = current_setting('verificar_rls.migrador_rol');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FALLA Parte 0: el rol de migración % no existe — correr provisionar_roles_postgres.sql primero.', current_setting('verificar_rls.migrador_rol');
  END IF;
  IF es_super OR bypassea_rls THEN
    RAISE NOTICE 'INFO Parte 0: el rol de migración % tiene rolsuper=% / rolbypassrls=% — la Parte 3 de este script va a mostrar si FORCE ROW LEVEL SECURITY alcanza igual para este rol puntual (spoiler: no, si cualquiera de los dos es true).', current_setting('verificar_rls.migrador_rol'), es_super, bypassea_rls;
  ELSE
    RAISE NOTICE 'OK Parte 0: el rol de migración % no es superusuario ni BYPASSRLS (FORCE ROW LEVEL SECURITY puede tener efecto real sobre él).', current_setting('verificar_rls.migrador_rol');
  END IF;
END $$;

-- ============================================================================
-- Parte 1 — datos de prueba mínimos, 2 tenants (A y B), creados EXACTAMENTE como los crearía la
-- app real: conectado como el rol de MIGRACIÓN, pero seteando `app.usuario_id` antes de cada
-- INSERT que lo necesite (igual que `withTransaction`, backend/src/db.ts) — no se usa ningún
-- bypass de RLS para sembrar, a propósito: si algún INSERT de acá fallara por RLS, sería la
-- primera señal de que algo en las policies de escritura está mal, antes incluso de llegar a las
-- aserciones de las partes siguientes.
-- ============================================================================

SET ROLE :"migrador_rol";

-- IDs fijos (no aleatorios) para poder referenciarlos sin capturar resultados de INSERT en
-- variables — más simple de leer para quien audite este script a mano.
-- Tenant A
--   usuario admin:       00000000-0000-4000-8000-0000000000a1
--   negocio:             00000000-0000-4000-8000-0000000000a2
--   servicio:            00000000-0000-4000-8000-0000000000a3
--   usuario profesional: 00000000-0000-4000-8000-0000000000a4
--   profesional:         00000000-0000-4000-8000-0000000000a5
--   usuario cliente:     00000000-0000-4000-8000-0000000000a6
--   turno:               00000000-0000-4000-8000-0000000000a7
-- Tenant B (mismo patrón, sufijo b)
--   usuario admin:       00000000-0000-4000-8000-0000000000b1
--   negocio:             00000000-0000-4000-8000-0000000000b2
--   servicio:            00000000-0000-4000-8000-0000000000b3

INSERT INTO usuario (id, email, password_hash, nombre, rol) VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'verificar-rls-admin-a@test.local', 'x', 'Admin A (verificación RLS)', 'administrador'),
  ('00000000-0000-4000-8000-0000000000a4', 'verificar-rls-prof-a@test.local', 'x', 'Profesional A (verificación RLS)', 'profesional'),
  ('00000000-0000-4000-8000-0000000000a6', 'verificar-rls-cliente-a@test.local', 'x', 'Cliente A (verificación RLS)', 'cliente'),
  ('00000000-0000-4000-8000-0000000000b1', 'verificar-rls-admin-b@test.local', 'x', 'Admin B (verificación RLS)', 'administrador');

INSERT INTO negocio (id, nombre) VALUES
  ('00000000-0000-4000-8000-0000000000a2', 'Negocio A (verificación RLS)'),
  ('00000000-0000-4000-8000-0000000000b2', 'Negocio B (verificación RLS)');

-- negocio_administrador.WITH CHECK exige usuario_id = app.usuario_id -> setear antes de cada INSERT.
SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000a1', true);
INSERT INTO negocio_administrador (negocio_id, usuario_id) VALUES
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1');

SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000b1', true);
INSERT INTO negocio_administrador (negocio_id, usuario_id) VALUES
  ('00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000b1');

-- servicio.WITH CHECK exige EXISTS negocio_administrador para app.usuario_id -> admin de A sigue seteado.
SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000a1', true);
INSERT INTO servicio (id, negocio_id, nombre, duracion_min) VALUES
  ('00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000a2', 'Servicio A (verificación RLS)', 30);

SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000b1', true);
INSERT INTO servicio (id, negocio_id, nombre, duracion_min) VALUES
  ('00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000b2', 'Servicio B (verificación RLS)', 30);

-- profesional.INSERT exige EXISTS negocio_administrador para app.usuario_id -> admin de A.
SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000a1', true);
INSERT INTO profesional (id, usuario_id) VALUES
  ('00000000-0000-4000-8000-0000000000a5', '00000000-0000-4000-8000-0000000000a4');
INSERT INTO negocio_profesional (negocio_id, profesional_id, activo) VALUES
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a5', true);

-- turno: WITH CHECK exige cliente_id = app.usuario_id (o ser staff del negocio) -> cliente de A.
SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000a6', true);
INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado) VALUES
  ('00000000-0000-4000-8000-0000000000a7', '00000000-0000-4000-8000-0000000000a2',
   '00000000-0000-4000-8000-0000000000a5', '00000000-0000-4000-8000-0000000000a3',
   '00000000-0000-4000-8000-0000000000a6', now() + interval '1 day', now() + interval '1 day 30 minutes',
   'confirmado');

RESET ROLE;
DO $$ BEGIN
  RAISE NOTICE 'OK Parte 1: datos de prueba de 2 tenants sembrados sin bypassear RLS.';
END $$;

-- ============================================================================
-- Parte 2 — aislamiento cross-tenant con el rol de RUNTIME (el que usa la app de verdad).
-- ============================================================================

SET ROLE :"app_rol";
SELECT set_config('app.usuario_id', '00000000-0000-4000-8000-0000000000a1', true); -- admin de A

DO $$
DECLARE cantidad INT;
BEGIN
  -- negocio_administrador NO es de lectura pública (a diferencia de profesional/servicio) — el
  -- admin de A no debe ver la membresía del admin de B.
  SELECT count(*) INTO cantidad FROM negocio_administrador
    WHERE usuario_id = '00000000-0000-4000-8000-0000000000b1';
  IF cantidad <> 0 THEN
    RAISE EXCEPTION 'FALLA Parte 2: admin de A ve la membresía de administrador de OTRO negocio (esperado 0 filas, obtuvo %).', cantidad;
  END IF;
  RAISE NOTICE 'OK Parte 2: negocio_administrador aísla correctamente entre tenants (SELECT).';
END $$;

DO $$
DECLARE afectadas INT;
BEGIN
  -- servicio_update_admin_del_negocio: el admin de A NO debe poder escribir un servicio de B.
  UPDATE servicio SET nombre = 'INTENTO DE ESCRITURA CRUZADA'
    WHERE id = '00000000-0000-4000-8000-0000000000b3';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 0 THEN
    RAISE EXCEPTION 'FALLA Parte 2: admin de A pudo actualizar un servicio de OTRO negocio (esperado 0 filas afectadas, obtuvo %).', afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 2: admin de A no puede escribir un servicio de otro negocio (0 filas afectadas).';
END $$;

DO $$
DECLARE afectadas INT;
BEGIN
  -- Control positivo: el admin de A SÍ debe poder escribir su propio servicio.
  UPDATE servicio SET nombre = 'Servicio A (verificación RLS, editado)'
    WHERE id = '00000000-0000-4000-8000-0000000000a3';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 1 THEN
    RAISE EXCEPTION 'FALLA Parte 2 (control positivo): admin de A NO pudo actualizar su PROPIO servicio (esperado 1 fila afectada, obtuvo %) — revisar servicio_update_admin_del_negocio antes de confiar en las FALLAs de arriba.', afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 2 (control positivo): admin de A puede escribir su propio servicio.';
END $$;

DO $$
DECLARE afectadas INT;
BEGIN
  -- turno_acceso_negocio_o_cliente: el admin de A no administra ni es cliente del turno de A
  -- (ese turno es del CLIENTE a6, no de este admin) -> tampoco debería poder escribirlo desde acá
  -- salvo que sea staff del negocio_id del turno. El turno a7 SÍ pertenece al negocio de A
  -- (negocio_id = a2), así que el admin de A SÍ es staff válido — este es un control positivo de
  -- "staff del negocio", no un caso de aislamiento cruzado. Se deja explícito para no confundir
  -- ambos casos.
  UPDATE turno SET estado = 'cancelado' WHERE id = '00000000-0000-4000-8000-0000000000a7';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 1 THEN
    RAISE EXCEPTION 'FALLA Parte 2 (control positivo): admin de A (staff del negocio del turno) NO pudo actualizar un turno de SU PROPIO negocio (esperado 1, obtuvo %).', afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 2 (control positivo): admin de A puede escribir un turno de su propio negocio (staff).';
END $$;

RESET ROLE;

-- ============================================================================
-- Parte 3 — LA ASERCIÓN MÁS IMPORTANTE: confirmar que el gap de ownership está realmente cerrado.
-- Con el rol de MIGRACIÓN (OWNER de las tablas) y SIN setear `app.usuario_id` en absoluto — el
-- escenario exacto que, antes de este ciclo, bypasseaba RLS por completo — un UPDATE sobre un
-- servicio de cualquier tenant debe seguir siendo rechazado por FORCE ROW LEVEL SECURITY.
-- ============================================================================

SET ROLE :"migrador_rol";
RESET app.usuario_id; -- explícitamente sin contexto, a propósito (limpia cualquier valor que haya quedado seteado en la Parte 2)

DO $$
DECLARE afectadas INT;
BEGIN
  UPDATE servicio SET nombre = 'INTENTO DE ESCRITURA COMO OWNER SIN CONTEXTO'
    WHERE id = '00000000-0000-4000-8000-0000000000a3';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 0 THEN
    RAISE EXCEPTION 'FALLA CRÍTICA Parte 3: el rol OWNER (%) pudo escribir sin ningún contexto de RLS seteado (esperado 0 filas afectadas, obtuvo %) — FORCE ROW LEVEL SECURITY NO está teniendo efecto para este rol. Si este rol es superusuario o tiene BYPASSRLS, esto es esperable (ver Parte 0 y el diagnóstico de Security en ../migrations/001_init.sql) — si NO lo es, es el gap original sin cerrar.', current_setting('verificar_rls.migrador_rol'), afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 3 (LA ASERCIÓN CLAVE): el rol OWNER (%) NO puede escribir sin contexto de RLS — el gap de ownership está cerrado para este rol.', current_setting('verificar_rls.migrador_rol');
END $$;

RESET ROLE;

-- ============================================================================
-- Parte 4 — policy `turno_acceso_job_expiracion`: solo debe habilitar UPDATE con
-- `app.job_sistema = 'true'`, nunca por defecto ni con cualquier otro valor.
-- ============================================================================

SET ROLE :"app_rol";
RESET app.usuario_id;
RESET app.job_sistema;

DO $$
DECLARE afectadas INT;
BEGIN
  -- Sin ningún contexto seteado: ni cliente, ni staff, ni job -> 0 filas.
  UPDATE turno SET estado = 'cancelado' WHERE id = '00000000-0000-4000-8000-0000000000a7';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 0 THEN
    RAISE EXCEPTION 'FALLA Parte 4: se pudo actualizar un turno ajeno SIN ningún contexto RLS seteado (esperado 0, obtuvo %).', afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 4: sin contexto, el UPDATE de turno queda denegado (fail-closed).';
END $$;

SELECT set_config('app.job_sistema', 'true', true);

DO $$
DECLARE afectadas INT;
BEGIN
  -- Con app.job_sistema = 'true': el job puede actualizar CUALQUIER turno, sin ser cliente ni staff.
  UPDATE turno SET estado = 'cancelado' WHERE id = '00000000-0000-4000-8000-0000000000a7';
  GET DIAGNOSTICS afectadas = ROW_COUNT;
  IF afectadas <> 1 THEN
    RAISE EXCEPTION 'FALLA Parte 4: con app.job_sistema=true, el job NO pudo actualizar un turno ajeno (esperado 1, obtuvo %) — revisar turno_acceso_job_expiracion.', afectadas;
  END IF;
  RAISE NOTICE 'OK Parte 4: con app.job_sistema=true, el job puede actualizar cualquier turno.';
END $$;

RESET ROLE;

-- ============================================================================
-- Resultado final: si se llegó hasta acá sin que ningún RAISE EXCEPTION cortara la ejecución
-- (con -v ON_ERROR_STOP=1), las 5 partes pasaron. ROLLBACK explícito: ningún dato de prueba de
-- este script queda persistido, se haya llegado a este punto o se haya cortado antes por una falla.
-- ============================================================================
DO $$ BEGIN
  RAISE NOTICE 'OK FINAL: verificar_rls_postgres.sql — todas las aserciones pasaron. Haciendo ROLLBACK de los datos de prueba (no quedan persistidos).';
END $$;
ROLLBACK;
