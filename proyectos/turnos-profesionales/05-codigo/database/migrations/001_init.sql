-- Turnos Profesionales — migración inicial
-- Rol: DBA · Fase 3 — Diseño
-- Convenciones: GUID como PK, auditoría completa, soft delete donde corresponde (docs/06-modelo-datos.md §3)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE rol_usuario AS ENUM ('cliente', 'profesional', 'administrador');
CREATE TYPE estado_turno AS ENUM ('pendiente_de_pago', 'confirmado', 'cancelado', 'reprogramado');
CREATE TYPE estado_pago AS ENUM ('pendiente', 'acreditado', 'rechazado', 'expirado');

CREATE TABLE negocio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre          TEXT NOT NULL,
  rubro           TEXT,
  ubicacion       TEXT,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID,
  eliminado_en    TIMESTAMPTZ
);

CREATE TABLE usuario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  rol             rol_usuario NOT NULL,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ
);

CREATE TABLE profesional (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL UNIQUE REFERENCES usuario(id),
  negocio_id      UUID NOT NULL REFERENCES negocio(id),
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ,
  eliminado_en    TIMESTAMPTZ
);
CREATE INDEX idx_profesional_negocio ON profesional (negocio_id);

CREATE TABLE servicio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id      UUID NOT NULL REFERENCES negocio(id),
  nombre          TEXT NOT NULL,
  duracion_min    INTEGER NOT NULL CHECK (duracion_min > 0),
  precio_referencia NUMERIC(10,2),
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ,
  eliminado_en    TIMESTAMPTZ
);
CREATE INDEX idx_servicio_negocio ON servicio (negocio_id);

-- Asociación N:M profesional-servicio; la seña se configura por esta combinación (D2/RN10)
CREATE TABLE profesional_servicio (
  profesional_id  UUID NOT NULL REFERENCES profesional(id),
  servicio_id     UUID NOT NULL REFERENCES servicio(id),
  requiere_sena   BOOLEAN NOT NULL DEFAULT false,
  monto_sena      NUMERIC(10,2),
  PRIMARY KEY (profesional_id, servicio_id)
);

CREATE TABLE disponibilidad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profesional_id  UUID NOT NULL REFERENCES profesional(id),
  servicio_id     UUID NOT NULL REFERENCES servicio(id),
  dia_semana      SMALLINT NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
  hora_inicio     TIME NOT NULL,
  hora_fin        TIME NOT NULL CHECK (hora_fin > hora_inicio),
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_disponibilidad_profesional ON disponibilidad (profesional_id);

CREATE TABLE excepcion_disponibilidad (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profesional_id  UUID NOT NULL REFERENCES profesional(id),
  inicio          TIMESTAMPTZ NOT NULL,
  fin             TIMESTAMPTZ NOT NULL CHECK (fin > inicio),
  motivo          TEXT,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_excepcion_profesional ON excepcion_disponibilidad (profesional_id);

CREATE TABLE turno (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id      UUID NOT NULL REFERENCES negocio(id),
  profesional_id  UUID NOT NULL REFERENCES profesional(id),
  servicio_id     UUID NOT NULL REFERENCES servicio(id),
  cliente_id      UUID NOT NULL REFERENCES usuario(id),
  inicio          TIMESTAMPTZ NOT NULL,
  fin             TIMESTAMPTZ NOT NULL CHECK (fin > inicio),
  estado          estado_turno NOT NULL DEFAULT 'pendiente_de_pago',
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ
);
CREATE INDEX idx_turno_negocio ON turno (negocio_id);
CREATE INDEX idx_turno_cliente_profesional ON turno (cliente_id, profesional_id);

-- Garantiza RN2 (no doble reserva) — ver documento-arquitectura.md §4
CREATE UNIQUE INDEX uq_turno_slot_activo
  ON turno (profesional_id, inicio)
  WHERE estado IN ('pendiente_de_pago', 'confirmado');

CREATE TABLE pago (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turno_id        UUID NOT NULL UNIQUE REFERENCES turno(id),
  monto           NUMERIC(10,2) NOT NULL,
  estado          estado_pago NOT NULL DEFAULT 'pendiente',
  referencia_externa TEXT,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ
);

CREATE TABLE notificacion (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turno_id        UUID NOT NULL REFERENCES turno(id),
  tipo            TEXT NOT NULL, -- 'confirmacion' | 'recordatorio'
  enviado_en      TIMESTAMPTZ,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notificacion_turno ON notificacion (turno_id);

-- ============================================================================
-- Row Level Security — defensa en profundidad además de los checks de la API
-- (documento-arquitectura.md §5). El backend debe, en cada transacción autenticada,
-- ejecutar `SET LOCAL app.negocio_id = '<uuid>'` (profesional/administrador, desde el claim
-- del JWT) y/o `SET LOCAL app.usuario_id = '<uuid>'` (todo usuario autenticado, incluido
-- cliente). Sin esas variables seteadas, current_setting(..., true) devuelve NULL y las
-- políticas de escritura deniegan por defecto (fail-closed).
--
-- El rol de conexión de la aplicación NO debe ser el owner de las tablas ni tener
-- BYPASSRLS/superusuario — si lo es, Postgres ignora RLS por completo.
-- ============================================================================

-- profesional y servicio se listan públicamente sin autenticación para que el cliente
-- pueda descubrir negocios (CU3/HU-00b, HU-07, HU-08) — por eso el SELECT queda abierto.
-- Las escrituras (alta/edición) sí quedan acotadas al negocio del actor autenticado.
ALTER TABLE profesional ENABLE ROW LEVEL SECURITY;
CREATE POLICY profesional_select_publico ON profesional
  FOR SELECT USING (true);
CREATE POLICY profesional_insert_propio_negocio ON profesional
  FOR INSERT WITH CHECK (negocio_id = current_setting('app.negocio_id', true)::uuid);
CREATE POLICY profesional_update_propio_negocio ON profesional
  FOR UPDATE USING (negocio_id = current_setting('app.negocio_id', true)::uuid);

ALTER TABLE servicio ENABLE ROW LEVEL SECURITY;
CREATE POLICY servicio_select_publico ON servicio
  FOR SELECT USING (true);
CREATE POLICY servicio_insert_propio_negocio ON servicio
  FOR INSERT WITH CHECK (negocio_id = current_setting('app.negocio_id', true)::uuid);
CREATE POLICY servicio_update_propio_negocio ON servicio
  FOR UPDATE USING (negocio_id = current_setting('app.negocio_id', true)::uuid);

-- turno NUNCA es de lectura pública (a diferencia de profesional/servicio): son datos
-- privados de agenda y de cliente. Pero un `turno` lo puede necesitar ver/tocar tanto el
-- STAFF del negocio (scoping por negocio_id) COMO el CLIENTE dueño de la reserva — y un
-- cliente reserva en múltiples negocios, así que su JWT no lleva negocio_id (ver auth.ts).
-- Por eso la política es un OR entre ambos scopes, no solo negocio_id como en las tablas de
-- catálogo de arriba.
ALTER TABLE turno ENABLE ROW LEVEL SECURITY;
CREATE POLICY turno_acceso_negocio_o_cliente ON turno
  USING (
    negocio_id = current_setting('app.negocio_id', true)::uuid
    OR cliente_id = current_setting('app.usuario_id', true)::uuid
  )
  WITH CHECK (
    negocio_id = current_setting('app.negocio_id', true)::uuid
    OR cliente_id = current_setting('app.usuario_id', true)::uuid
  );
