-- Turnos Profesionales — esquema de desarrollo (SQLite)
-- Adaptado de proyectos/turnos-profesionales/05-codigo/database/migrations/001_init.sql (DBA, Postgres)
-- Diferencias vs. Postgres: UUID/TIMESTAMPTZ -> TEXT, ENUM -> TEXT + CHECK, BOOLEAN -> INTEGER.
-- La garantía anti-doble-reserva (índice único parcial) se mantiene idéntica: SQLite soporta
-- índices parciales (WHERE) igual que Postgres.

CREATE TABLE IF NOT EXISTS negocio (
  id              TEXT PRIMARY KEY,
  nombre          TEXT NOT NULL,
  rubro           TEXT,
  ubicacion       TEXT,
  creado_en       TEXT NOT NULL,
  eliminado_en    TEXT
);

CREATE TABLE IF NOT EXISTS usuario (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  rol             TEXT NOT NULL CHECK (rol IN ('cliente','profesional','administrador')),
  creado_en       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS profesional (
  id              TEXT PRIMARY KEY,
  usuario_id      TEXT NOT NULL UNIQUE REFERENCES usuario(id),
  negocio_id      TEXT NOT NULL REFERENCES negocio(id),
  creado_en       TEXT NOT NULL,
  eliminado_en    TEXT
);
CREATE INDEX IF NOT EXISTS idx_profesional_negocio ON profesional (negocio_id);

CREATE TABLE IF NOT EXISTS servicio (
  id                  TEXT PRIMARY KEY,
  negocio_id          TEXT NOT NULL REFERENCES negocio(id),
  nombre              TEXT NOT NULL,
  duracion_min        INTEGER NOT NULL CHECK (duracion_min > 0),
  precio_referencia   REAL,
  creado_en           TEXT NOT NULL,
  eliminado_en        TEXT
);
CREATE INDEX IF NOT EXISTS idx_servicio_negocio ON servicio (negocio_id);

CREATE TABLE IF NOT EXISTS profesional_servicio (
  profesional_id  TEXT NOT NULL REFERENCES profesional(id),
  servicio_id     TEXT NOT NULL REFERENCES servicio(id),
  requiere_sena   INTEGER NOT NULL DEFAULT 0,
  monto_sena      REAL,
  PRIMARY KEY (profesional_id, servicio_id)
);

CREATE TABLE IF NOT EXISTS disponibilidad (
  id              TEXT PRIMARY KEY,
  profesional_id  TEXT NOT NULL REFERENCES profesional(id),
  servicio_id     TEXT NOT NULL REFERENCES servicio(id),
  dia_semana      INTEGER NOT NULL CHECK (dia_semana BETWEEN 0 AND 6),
  hora_inicio     TEXT NOT NULL,
  hora_fin        TEXT NOT NULL,
  creado_en       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_disponibilidad_profesional ON disponibilidad (profesional_id);

CREATE TABLE IF NOT EXISTS excepcion_disponibilidad (
  id              TEXT PRIMARY KEY,
  profesional_id  TEXT NOT NULL REFERENCES profesional(id),
  inicio          TEXT NOT NULL,
  fin             TEXT NOT NULL,
  motivo          TEXT,
  creado_en       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_excepcion_profesional ON excepcion_disponibilidad (profesional_id);

CREATE TABLE IF NOT EXISTS turno (
  id              TEXT PRIMARY KEY,
  negocio_id      TEXT NOT NULL REFERENCES negocio(id),
  profesional_id  TEXT NOT NULL REFERENCES profesional(id),
  servicio_id     TEXT NOT NULL REFERENCES servicio(id),
  cliente_id      TEXT NOT NULL REFERENCES usuario(id),
  inicio          TEXT NOT NULL,
  fin             TEXT NOT NULL,
  estado          TEXT NOT NULL DEFAULT 'pendiente_de_pago'
                    CHECK (estado IN ('pendiente_de_pago','confirmado','cancelado','reprogramado')),
  creado_en       TEXT NOT NULL,
  modificado_en   TEXT
);
CREATE INDEX IF NOT EXISTS idx_turno_negocio ON turno (negocio_id);
CREATE INDEX IF NOT EXISTS idx_turno_cliente_profesional ON turno (cliente_id, profesional_id);

-- Garantiza RN2 (no doble reserva) — ver documento-arquitectura.md §4.
-- Esta es la pieza central de este slice: el INSERT en /turnos falla con constraint
-- violation si el slot ya está ocupado por un turno activo, sin necesidad de locking manual.
CREATE UNIQUE INDEX IF NOT EXISTS uq_turno_slot_activo
  ON turno (profesional_id, inicio)
  WHERE estado IN ('pendiente_de_pago', 'confirmado');

CREATE TABLE IF NOT EXISTS pago (
  id                  TEXT PRIMARY KEY,
  turno_id            TEXT NOT NULL UNIQUE REFERENCES turno(id),
  monto               REAL NOT NULL,
  estado              TEXT NOT NULL DEFAULT 'pendiente'
                        CHECK (estado IN ('pendiente','acreditado','rechazado','expirado')),
  referencia_externa  TEXT,
  creado_en           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notificacion (
  id          TEXT PRIMARY KEY,
  turno_id    TEXT NOT NULL REFERENCES turno(id),
  tipo        TEXT NOT NULL,
  enviado_en  TEXT,
  creado_en   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notificacion_turno ON notificacion (turno_id);
