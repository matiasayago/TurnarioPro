-- Turnos Profesionales — esquema de desarrollo (SQLite)
-- Adaptado de proyectos/turnos-profesionales/05-codigo/database/migrations/001_init.sql (DBA, Postgres)
-- Diferencias vs. Postgres: UUID/TIMESTAMPTZ -> TEXT, ENUM -> TEXT + CHECK, BOOLEAN -> INTEGER.
-- La garantía anti-doble-reserva (índice único parcial) se mantiene idéntica: SQLite soporta
-- índices parciales (WHERE) igual que Postgres.

-- usuario se crea antes que negocio porque negocio_administrador (definida más abajo,
-- reemplaza a la antigua columna negocio.admin_usuario_id) referencia usuario(id).
CREATE TABLE IF NOT EXISTS usuario (
  id              TEXT PRIMARY KEY,
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  rol             TEXT NOT NULL CHECK (rol IN ('cliente','profesional','administrador')),
  creado_en       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS negocio (
  id                TEXT PRIMARY KEY,
  nombre            TEXT NOT NULL,
  rubro             TEXT,
  ubicacion         TEXT,
  creado_en         TEXT NOT NULL,
  eliminado_en      TEXT
);

-- Generalización N:M (2026-08-06) del fix de CRITICAL-1 (ver ../../07-seguridad/informe-seguridad.md).
-- La columna que resolvía ese hallazgo, negocio.admin_usuario_id (1:1 NOT NULL UNIQUE), asumía
-- el alcance MVP "1 administrador = 1 negocio" (documento-funcional.md supuesto A7 original). El
-- CEO confirmó que un mismo administrador puede operar más de un negocio (ej. varias
-- sucursales), incompatible con una columna UNIQUE 1:1, así que se reemplaza por esta tabla de
-- asociación. Sigue resolviendo CRITICAL-1 igual (la query del login se correlaciona contra una
-- relación persistida real, nunca "el primer negocio de la tabla"); ahora puede devolver 0..N
-- filas en vez de exactamente 1. Ver comentario ampliado en database/migrations/001_init.sql
-- (Postgres) y en 03-arquitectura/modelo-datos.md.
CREATE TABLE IF NOT EXISTS negocio_administrador (
  negocio_id  TEXT NOT NULL REFERENCES negocio(id),
  usuario_id  TEXT NOT NULL REFERENCES usuario(id),
  creado_en   TEXT NOT NULL,
  PRIMARY KEY (negocio_id, usuario_id)
);
CREATE INDEX IF NOT EXISTS idx_negocio_administrador_usuario ON negocio_administrador (usuario_id);

-- Generalización N:M (2026-08-06, mismo cambio que negocio_administrador arriba): profesional
-- deja de tener negocio_id propio y pasa a ser una identidad profesional pura (análoga a
-- usuario), sin pertenencia fija a un negocio. La pertenencia real vive en negocio_profesional,
-- definida a continuación porque la referencia.
--
-- `duracion_cita_min` (D10, 2026-08-06 — AMENDA RN3): override de duración de turno que
-- configura el profesional, reemplaza servicio.duracion_min en TODOS sus turnos cuando no es
-- NULL, sin importar servicio ni negocio (el CEO descartó explícitamente la alternativa más
-- granular por combinación profesional+servicio). Vive acá por ser un valor de la identidad
-- profesional, no de una membresía a un negocio (negocio_profesional) ni de una configuración
-- por servicio (profesional_servicio). Ver comentario ampliado en database/migrations/001_init.sql
-- (Postgres) y en 03-arquitectura/modelo-datos.md §2quater (incluye la recomendación exacta de
-- dónde leerlo en Backend: disponibilidad.ts y turnos.ts, archivo + línea aproximada).
CREATE TABLE IF NOT EXISTS profesional (
  id              TEXT PRIMARY KEY,
  usuario_id      TEXT NOT NULL UNIQUE REFERENCES usuario(id),
  duracion_cita_min INTEGER CHECK (duracion_cita_min IS NULL OR duracion_cita_min > 0),
  creado_en       TEXT NOT NULL,
  eliminado_en    TEXT
);

-- N:M profesional↔negocio: la membresía real "este profesional trabaja en este negocio",
-- reemplazo de profesional.negocio_id. NO es redundante con profesional_servicio (definida más
-- abajo): puede existir un momento -- justo después de que el administrador da de alta a un
-- profesional (HU-02) -- en el que el profesional YA pertenece al negocio pero TODAVÍA no asoció
-- ningún servicio propio (HU-04/HU-04b, paso posterior y separado que hace el profesional
-- mismo). `activo` (no un segundo soft-delete) porque la pertenencia a un negocio puede
-- pausarse/reanudarse sin perder el vínculo; usar soft-delete de toda la fila `profesional` para
-- esto afectaría también a otros negocios donde ese mismo profesional sigue activo. Ver
-- comentario ampliado en database/migrations/001_init.sql (Postgres) y en modelo-datos.md.
CREATE TABLE IF NOT EXISTS negocio_profesional (
  negocio_id      TEXT NOT NULL REFERENCES negocio(id),
  profesional_id  TEXT NOT NULL REFERENCES profesional(id),
  activo          INTEGER NOT NULL DEFAULT 1,
  creado_en       TEXT NOT NULL,
  modificado_en   TEXT,
  PRIMARY KEY (negocio_id, profesional_id)
);
CREATE INDEX IF NOT EXISTS idx_negocio_profesional_profesional ON negocio_profesional (profesional_id);

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
