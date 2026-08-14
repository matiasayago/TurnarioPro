-- Turnos Profesionales — migración incremental 006 (Postgres)
-- Rol: Backend (con marca de "pendiente de ratificación por DBA") · Fase 4 — ciclo HU-29/E11
-- "Turnario Pro", 2026-08-14
--
-- QUÉ ES ESTE ARCHIVO: mismo mecanismo operativo que 002/003/004/005 — 001_init.sql ya tiene esta
-- policy nueva (para entornos que migran desde cero), pero Render ya corrió 005_suscripcion_negocio.sql
-- sin ella (esta policy se agregó DESPUÉS, al conectar el chequeo de límites de HU-29 contra
-- POST /turnos y encontrar el gap descripto abajo). Este archivo es el DELTA que falta aplicar a
-- mano contra Render:
--
--   psql "$DATABASE_URL" -f 006_suscripcion_negocio_policy_contexto.sql
--
-- Gap encontrado al implementar el chequeo de "60 turnos confirmados/mes" (HU-29,
-- backend/src/dominio/suscripciones.ts) en `POST /turnos` (backend/src/routes/turnos.ts): ese
-- endpoint corre con `requireAuth('cliente')` — `app.usuario_id` en su transacción es el CLIENTE
-- que reserva, nunca administrador ni profesional de ESE negocio, así que
-- `suscripcion_negocio_select_staff_del_negocio` (005) nunca lo habilita, sin importar cuál sea el
-- negocio. Sin esta policy, el chequeo del límite en el camino "reserva de cliente sin seña ->
-- turno nace confirmado directo" leería siempre 0 filas (fail-closed silencioso de RLS) y trataría
-- CUALQUIER negocio, incluido uno con Turnario Pro activo, como si nunca tuviera fila -> 'gratis'
-- implícito — un negocio pago quedaría erróneamente limitado a 60 turnos/mes por esta lectura. No
-- es un problema de seguridad (nunca deja pasar de más), pero sí un bug funcional real.
--
-- Acotada por `app.negocio_id` (no por `app.usuario_id`, a diferencia de las 3 policies de 005):
-- el actor legítimo acá (el cliente reservando) nunca va a tener una fila propia en
-- `negocio_administrador`/`negocio_profesional` para este negocio — no hay forma de acotar por
-- identidad del actor sin excluir exactamente al actor legítimo. `obtenerEstadoSuscripcion`
-- (backend/src/dominio/suscripciones.ts) fija `app.negocio_id` al negocio YA VALIDADO de la
-- operación en curso (ej. `servicio.negocio_id`, resuelto server-side, nunca un valor crudo del
-- body) INMEDIATAMENTE antes de este SELECT. Alcance: SOLO lee plan/periodo/vencimiento/estado de
-- la fila del negocio con el que la transacción YA está interactuando — no expone la suscripción
-- de otros negocios, y no habilita ningún INSERT/UPDATE (siguen exclusivamente admin del negocio).
--
-- Detalle completo del razonamiento (incluida la alternativa SECURITY DEFINER evaluada y
-- descartada): database/migrations/001_init.sql, bloque "Suscripción 'Turnario Pro'", policy
-- `suscripcion_negocio_select_negocio_en_contexto` — y backend/src/dominio/suscripciones.ts,
-- doc comment de `obtenerEstadoSuscripcion`.
--
-- Idempotencia: CREATE POLICY no admite IF NOT EXISTS (mismo límite ya documentado en
-- 002/003/004/005) — guard vía bloque DO + pg_policy, mismo patrón.
--
-- Reversible: DROP POLICY IF EXISTS suscripcion_negocio_select_negocio_en_contexto ON suscripcion_negocio;
-- (sentencia única, sin transacción — no hay nada más que revertir en este archivo).

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'suscripcion_negocio_select_negocio_en_contexto') THEN
    CREATE POLICY suscripcion_negocio_select_negocio_en_contexto ON suscripcion_negocio
      FOR SELECT USING (
        negocio_id = NULLIF(current_setting('app.negocio_id', true), '')::uuid
      );
  END IF;
END $$;

COMMIT;
