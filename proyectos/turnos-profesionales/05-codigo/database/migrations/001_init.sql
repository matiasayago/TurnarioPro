-- Turnos Profesionales — migración inicial
-- Rol: DBA · Fase 3 — Diseño
-- Convenciones: GUID como PK, auditoría completa, soft delete donde corresponde (docs/06-modelo-datos.md §3)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE rol_usuario AS ENUM ('cliente', 'profesional', 'administrador');
CREATE TYPE estado_turno AS ENUM ('pendiente_de_pago', 'confirmado', 'cancelado', 'reprogramado');
CREATE TYPE estado_pago AS ENUM ('pendiente', 'acreditado', 'rechazado', 'expirado');

-- usuario se crea antes que negocio porque negocio_administrador (definida más abajo,
-- reemplaza a la antigua columna negocio.admin_usuario_id) referencia usuario(id).
CREATE TABLE usuario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT NOT NULL,
  nombre          TEXT NOT NULL,
  rol             rol_usuario NOT NULL,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ
);

CREATE TABLE negocio (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            TEXT NOT NULL,
  rubro             TEXT,
  ubicacion         TEXT,
  creado_en         TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por        UUID,
  modificado_en     TIMESTAMPTZ,
  modificado_por    UUID,
  eliminado_en      TIMESTAMPTZ
);

-- Generalización N:M (2026-08-06) del fix de CRITICAL-1 (informe-seguridad.md). La columna que
-- resolvía ese hallazgo, `negocio.admin_usuario_id` (1:1 NOT NULL UNIQUE), asumía el alcance MVP
-- "1 administrador = 1 negocio" (documento-funcional.md supuesto A7 original) — y su propio
-- comentario ya preveía este reemplazo textualmente ("si a futuro se necesita soportar más de un
-- administrador por negocio, migrar a una tabla de asociación"). El CEO confirmó que un mismo
-- administrador puede operar más de un negocio (ej. varias sucursales), lo cual es incompatible
-- con una columna UNIQUE 1:1 en `negocio`, así que se reemplaza por esta tabla de asociación.
-- Sigue resolviendo CRITICAL-1 exactamente igual (la query del login se correlaciona contra una
-- relación persistida real, nunca "el primer negocio de la tabla"); lo único que cambia es que
-- ahora puede devolver 0..N filas en vez de exactamente 1 — ver recomendación de query para
-- Backend en modelo-datos.md, sección de esta generalización.
-- PK compuesta (no GUID propio): es una tabla de asociación pura, mismo criterio ya aplicado a
-- `profesional_servicio` más abajo — la clave del vínculo es el par (negocio_id, usuario_id), y
-- ninguna otra tabla necesita referenciar una fila de esta por un id propio.
-- Solo `creado_en` (sin creado_por/modificado_en/modificado_por): es un hecho binario (existe el
-- vínculo o no existe), sin atributos mutables — a diferencia de `negocio_profesional` (ver más
-- abajo), que sí tiene un flag `activo` y por eso lleva `modificado_en`.
CREATE TABLE negocio_administrador (
  negocio_id  UUID NOT NULL REFERENCES negocio(id),
  usuario_id  UUID NOT NULL REFERENCES usuario(id),
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (negocio_id, usuario_id)
);
CREATE INDEX idx_negocio_administrador_usuario ON negocio_administrador (usuario_id);

-- Generalización N:M (2026-08-06, mismo cambio de alcance que negocio_administrador arriba):
-- profesional deja de tener un `negocio_id` propio y pasa a ser una identidad profesional pura
-- (análoga a `usuario`), sin pertenencia fija a un negocio. La pertenencia real vive en
-- `negocio_profesional`, definida a continuación porque la referencia.
--
-- `duracion_cita_min` (D10, 2026-08-06 — AMENDA RN3 de documento-funcional.md). El CEO resolvió
-- la pregunta abierta de precedencia (D6/RN11 vs. RN3) eligiendo la opción más simple: la
-- duración de turno que configura el profesional reemplaza SIEMPRE la duración del servicio,
-- para TODOS sus turnos, sin importar cuál sea el servicio — descartó explícitamente la
-- alternativa más granular por combinación profesional+servicio (al estilo
-- `profesional_servicio.monto_sena`, evaluada y no elegida). Por eso vive acá, en `profesional`
-- (identidad profesional pura, ya sin negocio_id propio — ver el párrafo de arriba), y NO en
-- `negocio_profesional` (variaría por negocio, algo que el CEO no pidió — RN11 lo describe como
-- "su duración de cita" en singular, un valor general del profesional, no por negocio donde
-- trabaja) ni en `profesional_servicio` (variaría por servicio, exactamente la opción que el CEO
-- descartó). `NULL` = el profesional no configuró ningún override, se sigue usando
-- `servicio.duracion_min` sin ningún cambio — fallback que aplica Backend, no la base de datos
-- (ver recomendación de dónde exactamente, archivo + línea, en `03-arquitectura/modelo-datos.md`
-- §2quater). El `CHECK` admite NULL explícitamente y exige `> 0` en el resto de los casos, mismo
-- criterio que `servicio.duracion_min` más abajo, pero acá nullable porque configurar este
-- override no es obligatorio (a diferencia de la duración de un servicio, que siempre existe).
CREATE TABLE profesional (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      UUID NOT NULL UNIQUE REFERENCES usuario(id),
  duracion_cita_min INTEGER CHECK (duracion_cita_min IS NULL OR duracion_cita_min > 0),
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ,
  eliminado_en    TIMESTAMPTZ
);

-- N:M profesional↔negocio: la membresía real "este profesional trabaja en este negocio",
-- reemplazo de `profesional.negocio_id`. NO es redundante con `profesional_servicio` (definida
-- más abajo, junto con `servicio`) — se evaluó explícitamente antes de decidir esto: puede
-- existir un momento, ej. justo después de que el administrador da de alta a un profesional
-- (HU-02), en el que el profesional YA pertenece al negocio pero TODAVÍA no asoció ningún
-- servicio propio (HU-04/HU-04b es un paso posterior y separado, que hace el profesional mismo
-- al loguearse). Sin esta tabla, ese profesional recién dado de alta sería indistinguible de "no
-- pertenece a ningún negocio" hasta su primer `POST /profesionales/:id/servicios` — rompería,
-- entre otras cosas, la posibilidad de mostrarle a qué negocio(s) pertenece apenas se loguea.
-- `activo` (no un segundo `eliminado_en`) porque la pertenencia a un negocio concreto puede
-- pausarse y reanudarse (licencia, cambio temporal) sin perder el vínculo ni su historial; usar
-- soft-delete de toda la fila `profesional` para esto afectaría también a otros negocios donde
-- ese mismo profesional sigue activo — exactamente el acoplamiento 1:1 que esta generalización
-- busca eliminar. `modificado_en` sí se agrega acá (a diferencia de `negocio_administrador`)
-- porque `activo` es un atributo mutable cuyo último cambio vale la pena poder auditar.
CREATE TABLE negocio_profesional (
  negocio_id      UUID NOT NULL REFERENCES negocio(id),
  profesional_id  UUID NOT NULL REFERENCES profesional(id),
  activo          BOOLEAN NOT NULL DEFAULT true,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ,
  PRIMARY KEY (negocio_id, profesional_id)
);
CREATE INDEX idx_negocio_profesional_profesional ON negocio_profesional (profesional_id);

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
-- (documento-arquitectura.md §5). El backend debe, en cada transacción autenticada, ejecutar
-- `SET LOCAL app.usuario_id = '<uuid>'` (todo usuario autenticado). Sin esa variable seteada,
-- current_setting(..., true) devuelve NULL y las políticas de escritura deniegan por defecto
-- (fail-closed).
--
-- El rol de conexión de la aplicación NO debe ser el owner de las tablas ni tener
-- BYPASSRLS/superusuario — si lo es, Postgres ignora RLS por completo.
--
-- Generalización N:M (2026-08-06) — por qué ya no alcanza con `app.negocio_id`: antes de este
-- cambio, un actor (administrador o profesional) tenía a lo sumo UN negocio_id válido, así que
-- comparar `negocio_id = current_setting('app.negocio_id')` alcanzaba como política. Ahora un
-- mismo usuario puede pertenecer a 2+ negocios simultáneamente (`negocio_administrador` /
-- `negocio_profesional`), y `current_setting` solo guarda UN valor por sesión — comparar contra
-- un único "negocio activo" reintroduce el mismo patrón de riesgo que causó CRITICAL-1: confiar
-- en un único valor (ahí, una query sin correlacionar; acá, una variable de sesión) sin
-- re-derivarlo contra la relación persistida real en cada chequeo. Por eso las políticas de
-- abajo usan `EXISTS` contra `negocio_administrador`/`negocio_profesional`, ancladas en
-- `app.usuario_id` (el mismo identificador que ya se usaba para el scope de cliente en `turno`)
-- en vez de comparar contra un `app.negocio_id` de sesión: cada fila se re-verifica contra la
-- tabla de membresía real, no contra un claim que el backend podría haber resuelto mal para el
-- request actual. Esto vuelve innecesaria la variable de sesión `app.negocio_id` para RLS (el
-- backend puede seguir usando un claim `negocio_id` en el JWT para su propia lógica de
-- aplicación/UI de "vista activa", pero esa es una capa distinta de esta).
-- ============================================================================

-- profesional ya no tiene `negocio_id` (ver `negocio_profesional`): pasa a comportarse como una
-- identidad (similar a `usuario`), no como un recurso propiedad de un negocio. El SELECT sigue
-- público por la misma razón que antes (descubrimiento de negocios sin login, HU-07/HU-08); el
-- INSERT queda acotado a que quien lo ejecuta sea administrador de ALGÚN negocio (no importa
-- cuál — la fila en sí no lleva negocio_id; el negocio concreto se fija en el INSERT sobre
-- `negocio_profesional`, política siguiente) porque en el flujo actual (HU-02) solo un
-- administrador da de alta profesionales. El UPDATE (ej. soft-delete de la identidad completa)
-- queda acotado a un administrador de ALGUNO de los negocios donde ese profesional está
-- efectivamente vinculado hoy.
ALTER TABLE profesional ENABLE ROW LEVEL SECURITY;
CREATE POLICY profesional_select_publico ON profesional
  FOR SELECT USING (true);
CREATE POLICY profesional_insert_por_administrador ON profesional
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );
CREATE POLICY profesional_update_admin_de_su_negocio ON profesional
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN negocio_administrador na ON na.negocio_id = np.negocio_id
      WHERE np.profesional_id = profesional.id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );

-- negocio_administrador: cada usuario ve únicamente sus propias membresías de administrador
-- (ej. para resolver "a qué negocios administro" en el login o en un futuro "cambiar de vista").
-- El INSERT solo permite que un usuario autenticado se dé de alta a SÍ MISMO como administrador
-- (usuario_id propio) — nunca a otro usuario_id — para que ninguna escritura pueda otorgar
-- privilegios de administrador sobre un tercero. No hay política de UPDATE: la tabla no tiene
-- atributos mutables además de la PK (negocio_id, usuario_id) — cambiar cualquiera de los dos es
-- borrar e insertar de nuevo, no actualizar. No se agrega política de DELETE (revocar acceso de
-- administrador) porque todavía no existe ningún endpoint/HU que lo requiera — queda como
-- extensión futura documentada, no implementada.
ALTER TABLE negocio_administrador ENABLE ROW LEVEL SECURITY;
CREATE POLICY negocio_administrador_select_propio ON negocio_administrador
  FOR SELECT USING (usuario_id = current_setting('app.usuario_id', true)::uuid);
CREATE POLICY negocio_administrador_insert_propio ON negocio_administrador
  FOR INSERT WITH CHECK (usuario_id = current_setting('app.usuario_id', true)::uuid);

-- negocio_profesional: SELECT público — igual que profesional/servicio, hace falta para que
-- HU-08 (GET /negocios/:id/servicios/:servicioId/profesionales) pueda resolver qué
-- profesionales pertenecen a un negocio sin requerir login. El INSERT (alta de la membresía,
-- HU-02) y el UPDATE (activar/desactivar, ej. licencia o baja) quedan acotados a administradores
-- del negocio_id involucrado — todavía no hay ningún HU que permita al propio profesional
-- autogestionar su membresía (solo sus servicios/disponibilidad dentro de ella), así que no se
-- habilita esa vía acá.
ALTER TABLE negocio_profesional ENABLE ROW LEVEL SECURITY;
CREATE POLICY negocio_profesional_select_publico ON negocio_profesional
  FOR SELECT USING (true);
CREATE POLICY negocio_profesional_insert_admin_del_negocio ON negocio_profesional
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = negocio_profesional.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );
CREATE POLICY negocio_profesional_update_admin_del_negocio ON negocio_profesional
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = negocio_profesional.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );

ALTER TABLE servicio ENABLE ROW LEVEL SECURITY;
CREATE POLICY servicio_select_publico ON servicio
  FOR SELECT USING (true);
CREATE POLICY servicio_insert_admin_del_negocio ON servicio
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = servicio.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );
CREATE POLICY servicio_update_admin_del_negocio ON servicio
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = servicio.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );

-- turno NUNCA es de lectura pública (a diferencia de profesional/servicio/negocio_profesional):
-- son datos privados de agenda y de cliente. Pero un `turno` lo puede necesitar ver/tocar tanto
-- el STAFF del negocio COMO el CLIENTE dueño de la reserva — y un cliente reserva en múltiples
-- negocios, así que su JWT no lleva negocio_id (ver auth.ts), de ahí el scope por cliente_id sin
-- cambios. El scope de STAFF sí cambia con la generalización N:M (2026-08-06, ver nota extensa
-- al inicio de este bloque): ya no compara `negocio_id` contra un único `app.negocio_id` de
-- sesión, sino que verifica con `EXISTS` si `app.usuario_id` administra ese negocio_id
-- (`negocio_administrador`) o es un profesional activo en ese negocio_id (`negocio_profesional`
-- + `profesional`) — así un administrador o profesional con 2+ negocios sigue viendo/tocando
-- cada uno de los suyos, nunca uno ajeno "por adivinar cuál esté seteado en la sesión".
-- Nota de continuidad: igual que en el diseño original, esto NO acota a un profesional a ver
-- solo SUS PROPIOS turnos dentro del negocio (cualquier staff del negocio pasa este chequeo de
-- RLS; el filtro adicional por profesional_id propio lo aplican los endpoints, ej.
-- GET /profesionales/:id/turnos) — no se restringe más acá para no exceder el alcance de este
-- cambio (generalizar 1:1→N:M), que es independiente de esa otra decisión de producto.
ALTER TABLE turno ENABLE ROW LEVEL SECURITY;
CREATE POLICY turno_acceso_negocio_o_cliente ON turno
  USING (
    cliente_id = current_setting('app.usuario_id', true)::uuid
    OR EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = turno.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
    OR EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN profesional p ON p.id = np.profesional_id
      WHERE np.negocio_id = turno.negocio_id
        AND p.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  )
  WITH CHECK (
    cliente_id = current_setting('app.usuario_id', true)::uuid
    OR EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = turno.negocio_id
        AND na.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
    OR EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN profesional p ON p.id = np.profesional_id
      WHERE np.negocio_id = turno.negocio_id
        AND p.usuario_id = current_setting('app.usuario_id', true)::uuid
    )
  );
