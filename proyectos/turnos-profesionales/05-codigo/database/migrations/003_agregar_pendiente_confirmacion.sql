-- Turnos Profesionales — migración incremental 003 (Postgres)
-- Rol: DBA · Fase — Implementación confirmación de turnos cliente (2026-08-25)
--
-- QUÉ ES ESTE ARCHIVO: extensión del ENUM tipo_notificacion para agregar 'pendiente_confirmacion',
-- nuevo estado de notificación que se envía al profesional cuando un cliente reserva un turno
-- sin pago (estado 'por_confirmar'). También agrega estado 'por_confirmar' al ENUM estado_turno.
--
-- Aplicación manual (Render):
--   psql "$DATABASE_URL" -f 003_agregar_pendiente_confirmacion.sql
--
-- Idempotencia: usa bloques DO con manejo de excepciones para que sea re-entrable sin errores,
-- igual que 002_pacientes_historial_auth_google.sql.

BEGIN;

-- ---------------------------------------------------------------------------
-- Agregar estado 'por_confirmar' al ENUM estado_turno (si no existe)
-- ---------------------------------------------------------------------------
-- En Postgres, no se puede hacer ALTER TYPE ... ADD VALUE IF NOT EXISTS directamente.
-- Se usa DO para capturar el error si el valor ya existe.
DO $$
BEGIN
  ALTER TYPE estado_turno ADD VALUE 'por_confirmar' BEFORE 'pendiente_de_pago';
EXCEPTION WHEN duplicate_object THEN
  -- El valor ya existe, no hacer nada
  NULL;
END $$;

-- ---------------------------------------------------------------------------
-- Agregar tipo 'pendiente_confirmacion' al ENUM tipo_notificacion (si no existe)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  ALTER TYPE tipo_notificacion ADD VALUE 'pendiente_confirmacion' BEFORE 'confirmacion';
EXCEPTION WHEN duplicate_object THEN
  -- El valor ya existe, no hacer nada
  NULL;
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (no se ejecuta automáticamente — copiar y correr a mano si hace falta revertir)
-- ============================================================================
-- En Postgres, no se puede remover valores de un ENUM una vez agregados. Si necesita revertir,
-- las opciones son:
-- 1. Renombrar el ENUM a uno nuevo, recrear con los valores originales (destructivo)
-- 2. Aceptar que los valores quedan pero simplemente no se usan
-- Por lo tanto, no hay rollback seguro para este archivo.
