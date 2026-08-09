-- Turnos Profesionales — migración inicial (Postgres)
-- Rol: DBA · Fase 3 — Diseño (evolucionada en varios ciclos posteriores: fix CRITICAL-1 §2bis,
-- generalización N:M §2ter, D10/duracion_cita_min §2quater, y la ratificación de RLS de este
-- mismo ciclo (2026-08-09) — ver 03-arquitectura/modelo-datos.md para el detalle completo de cada
-- una y memory/proyectos/turnos-profesionales/decisiones.md para la traza de decisiones).
-- Convenciones: GUID como PK, auditoría completa, soft delete donde corresponde (docs/06-modelo-datos.md §3)
--
-- ARCHIVO DUPLICADO A PROPÓSITO — mantener sincronizado. Este archivo es la fuente de verdad del
-- diseño de datos (rol DBA). Existe una copia física BYTE-IDÉNTICA en
-- ../../backend/migrations/001_init.sql porque `runMigrations()` (backend/src/db.ts) la lee con
-- una ruta relativa a su propio paquete — no puede alcanzar un archivo fuera del árbol de
-- backend/, ni en desarrollo ni en la imagen Docker (ver Dockerfile, `COPY migrations
-- ./dist/migrations`, y ../../../08-despliegue/README.md §2). Cualquier cambio futuro a este
-- archivo debe replicarse de inmediato, en el mismo commit, a esa otra ruta. Recomendación para
-- un ciclo futuro de DevOps/Backend: reemplazar esta sincronización manual por un paso de build
-- que copie desde esta única fuente en vez de mantener 2 copias versionadas por separado (ver
-- modelo-datos.md §5bis) — no implementado en este ciclo por no tocar build/código de Backend.
--
-- 2026-08-09 (DBA) — ratificadas las 3 policies de Row Level Security que Backend había agregado
-- (marcadas `-- [BACKEND] ... pendiente de ratificación` en la copia operativa) al conectar este
-- esquema a un Postgres real por primera vez, e incorporado un hallazgo propio, más grave, sobre
-- el mismo gap que Backend reportó: el rol de conexión de la app es owner de las tablas (corrió el
-- CREATE TABLE) y Postgres ignora RLS para el owner salvo FORCE ROW LEVEL SECURITY — agregada acá
-- para las 5 tablas con RLS — PERO en docker-compose/CI ese rol es además SUPERUSUARIO (ver el
-- bloque grande al inicio de la sección de Row Level Security, más abajo, para la evidencia), y
-- un superusuario bypassea RLS siempre, FORCE incluido. Cierre completo = FORCE (ya aplicado acá)
-- + separar un rol de migración de un rol de runtime sin BYPASSRLS (script y detalle exacto para
-- DevOps en ../scripts/provisionar_roles_postgres.sql y modelo-datos.md §5bis).

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

-- ============================================================================
-- Separación owner/runtime y FORCE ROW LEVEL SECURITY — cierre de gap crítico (DBA, 2026-08-09)
-- ============================================================================
-- Hallazgo (reportado por Backend al conectar este DDL a un Postgres real por primera vez,
-- TURNOS-2026-001, migración node:sqlite -> pg): `runMigrations()` (backend/src/db.ts) corre
-- ESTE archivo completo con el mismo `pool`/rol de conexión que sirve TODO el tráfico de la app
-- (una sola DATABASE_URL por ambiente — ver docker-compose.yml, .github/workflows/
-- turnos-backend-ci.yml, render.yaml). En Postgres, quien ejecuta CREATE TABLE se vuelve
-- automáticamente OWNER de esa tabla, y Postgres ignora RLS por completo para el owner (y para
-- cualquier rol con BYPASSRLS o superusuario) salvo que la tabla tenga FORCE ROW LEVEL SECURITY.
-- Ninguna tabla de este archivo la tenía hasta este ciclo — el párrafo de arriba ("El rol de
-- conexión... NO debe ser el owner...") ya advertía el riesgo desde la Fase 3 original, pero
-- nunca se había cerrado con un mecanismo real. Conclusión: hasta este ciclo, TODO el trabajo de
-- RLS de este archivo podía no tener ningún efecto real en ningún ambiente (docker-compose local,
-- CI, o render.yaml tal como está configurado) — la autorización real la seguían haciendo
-- únicamente los WHERE de cada query + los checks de cada handler (ninguno de los dos deja de
-- existir ni se debilita con este cambio: RLS es defensa EN PROFUNDIDAD, adicional a esos checks,
-- nunca el único mecanismo de autorización de este proyecto).
--
-- Arreglo en DOS capas, no una sola — ninguna alcanza sola en todos los ambientes:
--
-- 1) FORCE ROW LEVEL SECURITY en las 5 tablas con RLS habilitada (ver cada `ALTER TABLE ...
--    FORCE...` más abajo, junto a su `ENABLE` correspondiente) — un comando por tabla, aplica en
--    ESTE mismo archivo, sin depender de ningún cambio de infraestructura. Corrige que el owner
--    deje de bypassear RLS, PERO SOLO si el rol de conexión no es superusuario ni tiene
--    BYPASSRLS explícito — ver el punto 2 para por qué esto NO alcanza por sí solo en todos los
--    ambientes de este proyecto.
--
-- 2) Separar un rol de MIGRACIÓN (owner, corre este archivo una vez) de un rol de RUNTIME (sirve
--    el tráfico de la app vía `DATABASE_URL`, sin ser owner y sin BYPASSRLS) — la separación que
--    el diseño original de este bloque ya asumía (párrafo de arriba). Es la ÚNICA capa que
--    garantiza RLS real en TODOS los ambientes de este proyecto, por un motivo concreto y
--    verificado (no solo teórico): el rol que crean `docker-compose.yml` (`turnos`) y
--    `.github/workflows/turnos-backend-ci.yml` (`turnos_ci`) vía la variable `POSTGRES_USER` de
--    la imagen oficial `postgres:16-alpine` se crea como SUPERUSUARIO DEL CLUSTER — documentado
--    así por la propia imagen oficial de Docker ("This variable will create the specified user
--    with superuser power") — y un superusuario bypassea RLS SIEMPRE, FORCE ROW LEVEL SECURITY
--    incluido (FORCE solo afecta al owner cuando NO es superusuario ni tiene BYPASSRLS). Es
--    decir: en docker-compose y en CI, el punto 1 por sí solo NO tiene ningún efecto real hoy —
--    RLS seguiría 100% bypasseada en ambos, sin que nada lo indique (ningún error, ningún test
--    rojo: `scripts/*.mjs` no puede distinguir "pasó porque RLS filtró correctamente" de "pasó
--    porque RLS nunca se evaluó", porque los checks de cada handler ya cubren los mismos casos
--    de forma independiente). En Render (producción), el rol que provisiona el Blueprint
--    (`turnos_profesionales`, ver render.yaml) NO debería ser superusuario — los proveedores de
--    Postgres gestionado no suelen otorgar superusuario de cluster a su usuario de aplicación,
--    a diferencia de la imagen oficial de Docker usada en desarrollo/CI — pero esto NO está
--    verificado contra una cuenta real de Render (misma limitación ya documentada en render.yaml
--    y 08-despliegue/README.md), así que el punto 1 SÍ debería tener efecto ahí, a falta de esa
--    confirmación — VERIFICAR antes de asumirlo, no dar por cerrado el gap en producción solo
--    por haber agregado FORCE.
--
-- Script de aprovisionamiento de los 2 roles (GRANTs exactos, un solo script reutilizable para
-- los 3 ambientes vía variables de psql, pensado para NO correr automáticamente vía
-- `runMigrations()`) en `../scripts/provisionar_roles_postgres.sql`. DEVOPS: es la tarea de
-- seguimiento pendiente para cerrar el punto 2 en docker-compose.yml/turnos-backend-ci.yml/
-- render.yaml — NINGUNO de los 3 se tocó en este ciclo (fuera del alcance de DBA). Detalle
-- completo, incluido por qué `runMigrations()` (backend/src/db.ts, sin modificar en este ciclo)
-- sigue funcionando sin cambios de código una vez separados los roles, en
-- ../../../03-arquitectura/modelo-datos.md §5bis.
--
-- Recomendación adicional para QA/DevOps: la primera vez que RLS tenga efecto real en cualquier
-- ambiente (hoy nunca lo tuvo, ni siquiera en CI), conviene re-correr la batería completa de
-- `scripts/*.mjs` en ESE ambiente antes de confiar en el resultado — pueden aparecer fallos que
-- estuvieron enmascarados todo este tiempo por el bypass total de RLS, no necesariamente
-- introducidos por este cambio.
--
-- Corroborado de forma independiente por Security (revisión en paralelo de esta misma migración,
-- 2026-08-09): confirmó con evidencia propia que en docker-compose.yml y en el service container
-- de CI el rol de conexión es efectivamente superusuario (mismo hallazgo que el punto 2 de
-- arriba) y que el gap de ownership de esta sección y la policy `turno_select_publico` (más abajo)
-- NO son dos problemas independientes: arreglar uno sin el otro en el mismo cambio rompe
-- funcionalidad hoy verde en CI (ver el comentario completo junto a `turno_select_publico`, más
-- abajo, para el detalle). Por eso ambos arreglos viven en este mismo archivo/commit, no en
-- cambios separados. Security también sugirió, para Render específicamente, verificar con
-- `SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user` (conectado como el
-- rol que usaría `DATABASE_URL` ahí) si ese rol ya es no-superuser/no-BYPASSRLS antes de asumir
-- que ahí además hace falta separar roles — query incluida en
-- `../scripts/provisionar_roles_postgres.sql`. Y recomendó agregar un test de RLS a nivel de base
-- de datos (conectándose directo con el rol de runtime, sin pasar por los WHERE de la app) porque
-- ningún test HTTP existente puede detectar este tipo de gap — la autorización de aplicación ya
-- cubre el mismo terreno y lo esconde; script en `../scripts/verificar_rls_postgres.sql`.
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
-- FORCE: sin esto, el rol OWNER (quien corrió el CREATE TABLE de más arriba) bypassea todas las
-- políticas de esta tabla por completo, tenga o no BYPASSRLS/superusuario explícito — ver el
-- bloque grande "Separación owner/runtime..." más arriba para el detalle completo, incluido por
-- qué esto NO alcanza por sí solo en docker-compose/CI (rol owner ahí es superusuario, bypassea
-- RLS siempre). Reversible con `ALTER TABLE profesional NO FORCE ROW LEVEL SECURITY;`.
ALTER TABLE profesional FORCE ROW LEVEL SECURITY;
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

-- Ratificada por DBA (2026-08-09) — propuesta originalmente por Backend al conectar este DDL a un
-- Postgres real (TURNOS-2026-001). Resuelve un gap que yo mismo había dejado documentado como
-- pendiente desde la Fase 3 original, con 2 alternativas evaluadas sin decidir cuál (ver historial
-- completo en modelo-datos.md §5/§5bis): la policy de UPDATE de arriba solo habilita a un
-- ADMINISTRADOR a escribir `profesional`, pero RN11/D10 dice que el propio profesional configura
-- `duracion_cita_min` (PATCH /profesionales/:id/configuracion, ver
-- backend/src/routes/profesionales.ts). Sin esta policy, ese UPDATE queda denegado por RLS en
-- silencio (0 filas afectadas, sin error) en cuanto RLS tenga efecto real (ver bloque de
-- FORCE/separación de roles más arriba) — Backend ya blindó ese caso devolviendo un 500 explícito
-- en vez de un 200 que mintiera que se guardó (ver ese archivo), pero la policy sigue haciendo
-- falta para que el endpoint funcione de verdad, no solo para que falle de forma prolija.
--
-- Elegida la alternativa (a) — policy acotada a `usuario_id` propio + restricción de columnas a
-- nivel de aplicación — sobre la (b) —función SECURITY DEFINER—: verificado por DBA contra el
-- código real, no solo aceptado del razonamiento de Backend. `PATCH /:id/configuracion` es HOY el
-- ÚNICO call site de todo el código que ejecuta `UPDATE profesional ...` con el usuario_id del
-- propio profesional en su contexto RLS, y ese statement es hardcodeado
-- (`UPDATE profesional SET duracion_cita_min = $1 WHERE id = $2`, sin nombres de columna
-- dinámicos ni construidos desde input del cliente) — un profesional autenticado no tiene ningún
-- otro camino en el código para tocar otra columna de su propia fila (ej. `eliminado_en`, el
-- riesgo que motivaba evaluar la alternativa (b)) a través de este contexto. Si se agrega un
-- segundo endpoint de auto-servicio sobre `profesional`, hay que revisar explícitamente que esta
-- policy siga siendo segura para ESE nuevo UPDATE también — no se cierra automáticamente por
-- transitividad con esta revisión.
CREATE POLICY profesional_update_propio_duracion_cita ON profesional
  FOR UPDATE USING (
    profesional.usuario_id = current_setting('app.usuario_id', true)::uuid
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
ALTER TABLE negocio_administrador FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional` arriba
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
ALTER TABLE negocio_profesional FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional` arriba
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
ALTER TABLE servicio FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional` arriba
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
ALTER TABLE turno FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional` arriba
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

-- Ratificada por DBA (2026-08-09) CON RESERVA DOCUMENTADA, EXPLÍCITAMENTE TRANSITORIA — la más
-- sensible de las 3 policies que propuso Backend. Security la revisó en paralelo de forma
-- independiente (mismo patrón de doble revisión ya usado en Fase 5) y coincide en que hace falta
-- HOY (ver por qué en (a)/(b) más abajo) pero **no debe quedar como diseño permanente tal cual**:
-- es una policy PERMISIVA de SELECT, y las permisivas se combinan por OR — mientras esta policy
-- exista, `USING (true)` gana siempre y vuelve irrelevante para lectura a la policy
-- `turno_acceso_negocio_o_cliente` de arriba, sin importar qué tan bien diseñada esté esa otra.
-- Si la conclusión de Security hubiera sido otra (no coincidió acá), decide el Director General
-- IA — no se resuelve unilateralmente.
--
-- Qué resuelve, verificado por DBA contra el código real (no solo aceptado del comentario de
-- Backend):
-- (a) GET /profesionales/:id/slots (público, HU-09/CU1) — y un hallazgo ADICIONAL de esta
--     revisión, más grave que (a) por sí solo: la validación INTERNA de RN1/RN2 que hace el
--     propio POST /turnos ANTES de insertar (`calcularSlotsDisponibles(pool, ...)`, invocada dos
--     veces desde backend/src/routes/turnos.ts) lee `turno` a través de `pool` DIRECTO — igual
--     que GET /slots, nunca a través de un `client` dentro de una transacción con contexto RLS
--     (ver backend/src/dominio/disponibilidad.ts, `SELECT inicio, fin FROM turno WHERE
--     profesional_id = ...`). Es decir, NINGUNA de las dos lecturas tiene `app.usuario_id`
--     seteado, ni siquiera cuando quien reserva es un cliente autenticado. Sin esta policy (o una
--     equivalente), bajo RLS con efecto real, AMBAS lecturas verían 0 turnos ocupados: no solo
--     mostraría como "libres" horarios ya tomados (GET /slots), sino que el propio POST /turnos
--     podría aceptar una reserva que se solapa con otra ya existente si no coincide EXACTAMENTE
--     con el mismo `(profesional_id, inicio)` que protege `uq_turno_slot_activo` (índice que
--     sigue aplicando siempre, independientemente de RLS, pero que no cubre solapamientos
--     parciales) — sería una regresión funcional de RN2, no solo una relajación de privacidad.
-- (b) La distinción 403 (no es tuyo) vs. 404 (no existe) que exige
--     scripts/test-autorizacion-cruzada.mjs al cancelar/reprogramar el turno de OTRO cliente:
--     PATCH /turnos/:id/cancelar y /reprogramar hacen `SELECT * FROM turno WHERE id = $1` SIN
--     filtrar por cliente_id, y recién comparan `turno.cliente_id` en código (ver turnos.ts) para
--     decidir cuál de los dos códigos devolver.
--
-- Confirmado (Security + DBA, coincidente): el gap de ownership (FORCE/separación de roles, ver
-- el bloque grande más arriba) y esta policy están ACOPLADOS, no son dos cambios independientes —
-- cerrar el primero sin ratificar/mantener el segundo en el MISMO cambio rompe (a) y (b) en
-- cuanto RLS empiece a tener efecto real. Por eso viven en el mismo archivo/commit.
--
-- Reemplazo preparado, NO adoptado todavía (agregado en este ciclo a pedido de Security — ver
-- `turno_ocupacion_publica`/`turno_propio_para_gestion` al final de este archivo): 2 funciones
-- `SECURITY DEFINER` de alcance acotado, una por caso de uso (a)/(b), en vez de esta policy de
-- tabla completa. **No se retira esta policy en este ciclo** porque adoptarlas requiere que
-- Backend deje de leer `turno` por `pool`/`SELECT *` suelto en esos 3 call sites y llame a las
-- funciones en su lugar — cambio de código de Backend (`disponibilidad.ts`, `turnos.ts`), fuera
-- del alcance de este ciclo (instrucción explícita de no tocar rutas/db.ts). Retirar esta policy
-- SIN que Backend haya adoptado las funciones en el mismo cambio reproduciría exactamente el
-- riesgo que Security señaló (dos cambios que se pisan) — así que se prioriza no romper nada por
-- sobre cerrar el hallazgo del todo en este ciclo. Detalle completo de la secuencia recomendada
-- (quién hace qué, en qué orden, con qué verificación) en modelo-datos.md §5bis — el resumen es:
-- 1) este ciclo dejó las funciones listas; 2) el próximo ciclo conjunto Backend+DBA las adopta y
-- recién ahí se hace `DROP POLICY turno_select_publico ON turno;` (reversible por diseño: esa
-- única sentencia).
--
-- Por qué no se restringió MÁS esta policy en este ciclo en su lugar (evaluado activamente, no
-- por omisión): cualquier policy de SELECT más estricta que `USING (true)` — ej. acotarla a
-- "algún app.usuario_id seteado" — seguiría rompiendo (a), porque las DOS lecturas de
-- `calcularSlotsDisponibles` corren sin contexto RLS en absoluto (ni siquiera cuando el caller SÍ
-- está autenticado, ver arriba), no solo en el caso anónimo. Una restricción a nivel de COLUMNA
-- (GRANT SELECT de columnas específicas en vez de la tabla completa) tampoco es viable sin tocar
-- código: `cancelar`/`reprogramar` hacen `SELECT *`, que Postgres rechaza por completo si el rol
-- no tiene privilegio sobre TODAS las columnas seleccionadas (no devuelve un subconjunto
-- silencioso ante un GRANT parcial).
--
-- Alcance de la relajación (sin cambios respecto a la propuesta de Backend): SOLO el SELECT. El
-- INSERT/UPDATE/DELETE de `turno` siguen exclusivamente gobernados por
-- `turno_acceso_negocio_o_cliente` (más `turno_acceso_job_expiracion` para el job, ver abajo) —
-- un cliente/staff normal sigue sin poder escribir turnos ajenos. Qué queda expuesto mientras
-- siga activa: cualquier request que llegue a ejecutar un `SELECT ... FROM turno` (autenticado o
-- no) puede leer columnas de un turno ajeno si conoce/adivina el UUID exacto — hoy ningún
-- endpoint del código expone esa vía sin acotar (cada SELECT ya filtra por cliente_id/
-- profesional_id propio en el WHERE de la query, ver turnos.ts/profesionales.ts/clientes.ts) y el
-- dato más sensible (inicio/fin de un turno ocupado) ya es observable indirectamente por
-- CUALQUIERA sin login vía la ausencia de ese horario en GET /profesionales/:id/slots —
-- comportamiento central e intencional del producto (HU-09/CU1).
CREATE POLICY turno_select_publico ON turno
  FOR SELECT USING (true);

-- Ratificada por DBA (2026-08-09) sin cambios — la menos controvertida de las 3: acotada
-- exclusivamente a `app.job_sistema = 'true'` (solo lo setea
-- expirarPagosPendientesVencidos(), ver backend/src/jobs/expirarPagosPendientes.ts), y solo
-- agrega UPDATE — el SELECT del propio job ya queda cubierto por `turno_select_publico` de
-- arriba, y el job nunca actúa "como" un usuario/negocio puntual, así que ninguna policy pensada
-- para requests HTTP autenticados podría cubrirlo. Ya estaba anticipada por el comentario de
-- `ContextoRls.jobSistema` en backend/src/db.ts (código ya aprobado, sin cambios en este ciclo).
-- El otro UPDATE que corre ese mismo job (`UPDATE pago SET estado = 'expirado' ...`) no necesita
-- policy propia: `pago` no tiene RLS habilitada (ver "Pendiente para una próxima iteración" en
-- modelo-datos.md §5) — gap preexistente, no introducido por esta policy, fuera de alcance acá.
CREATE POLICY turno_acceso_job_expiracion ON turno
  FOR UPDATE USING (
    current_setting('app.job_sistema', true) = 'true'
  ) WITH CHECK (
    current_setting('app.job_sistema', true) = 'true'
  );

-- ============================================================================
-- Funciones SECURITY DEFINER — reemplazo preparado para `turno_select_publico` (DBA, 2026-08-09,
-- a pedido explícito de Security en su revisión independiente de esta misma migración). NO
-- adoptadas todavía por Backend — ver el comentario largo junto a `turno_select_publico`, más
-- arriba, para la secuencia exacta de adopción y por qué esa policy sigue activa mientras tanto.
-- ============================================================================
-- Reemplazan, una por caso de uso, el SELECT de tabla completa de `turno_select_publico` por un
-- contrato angosto y explícito: cada función solo devuelve exactamente las columnas que su caller
-- necesita, para exactamente el criterio de búsqueda que necesita (un profesional_id, o un
-- turno_id puntual) — no una tabla entera abierta a cualquier `SELECT`/`JOIN` presente o futuro
-- que toque `turno` sin querer. `LANGUAGE sql` (un único SELECT cada una, no hace falta
-- `plpgsql`), `STABLE` (sin efectos secundarios, resultado estable dentro de un mismo statement,
-- pero cambia entre statements a medida que se crean/modifican turnos — no es `IMMUTABLE`).
-- `SET search_path` fijo (buena práctica estándar de Postgres para funciones `SECURITY DEFINER`:
-- sin esto, quien ejecuta la función podría influir qué objeto resuelve un nombre no calificado
-- vía su propio `search_path` de sesión).
--
-- ADVERTENCIA IMPORTANTE para quien ejecute la adopción (Backend+DBA, próximo ciclo) — verificado
-- por razonamiento contra el comportamiento documentado de Postgres, NO contra un Postgres real
-- (mismo caveat que el resto de este archivo, ver modelo-datos.md §5): `SECURITY DEFINER` hace
-- que estas funciones corran con los privilegios de su OWNER (quien las crea al correr esta
-- migración — hoy, el único rol existente; el día que se separen roles por el bloque grande de
-- más arriba, el rol de MIGRACIÓN). Si ese mismo rol es además el OWNER de `turno` y `turno` tiene
-- `FORCE ROW LEVEL SECURITY` (como se agregó en este mismo ciclo, ver arriba), estas funciones
-- NO van a bypassear RLS por sí solas una vez que `turno_select_publico` se retire — FORCE aplica
-- las políticas al owner incluso dentro de una función `SECURITY DEFINER` que ese owner posee, así
-- que sin `turno_select_publico` de respaldo, `turno_acceso_negocio_o_cliente` seguiría filtrando
-- las lecturas de estas funciones exactamente igual que un SELECT directo. HOY esto no importa
-- (mientras `turno_select_publico` siga activa, su `USING (true)` permisivo gana por OR sin
-- importar qué haga esta sección), pero el día que se ejecute el paso 2) de la secuencia de
-- adopción (retirar esa policy), hay que resolver ADEMÁS uno de estos dos puntos en el MISMO
-- cambio, no asumir que alcanza con que las funciones ya existan:
--   (i) Crear un tercer rol NOLOGIN con BYPASSRLS explícito, dueño ÚNICAMENTE de estas 2
--       funciones (no de ninguna tabla) — nadie se conecta con ese rol directamente, así que su
--       BYPASSRLS queda acotado a lo que estas 2 funciones exponen, no a cualquier acceso directo
--       a `turno`. Es el patrón más alineado con el resto de este archivo (mínimo privilegio,
--       ningún rol de conexión real con BYPASSRLS) — RECOMENDADO.
--   (ii) Otorgarle BYPASSRLS al rol de migración — más simple, pero reintroduce sobre ESE rol
--       exactamente el riesgo que motivó preferir separar roles por sobre FORCE-solo en primer
--       lugar (rol peligroso para cualquier acceso directo futuro) — NO RECOMENDADO salvo que se
--       acepte ese trade-off conscientemente.
-- Grants de `EXECUTE` (revocados de PUBLIC acá abajo, deben otorgarse explícitamente al rol de
-- runtime) en `../scripts/provisionar_roles_postgres.sql`.

CREATE FUNCTION turno_ocupacion_publica(p_profesional_id UUID)
RETURNS TABLE(inicio TIMESTAMPTZ, fin TIMESTAMPTZ)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT t.inicio, t.fin
  FROM turno t
  WHERE t.profesional_id = p_profesional_id
    AND t.estado IN ('pendiente_de_pago', 'confirmado');
$$;
COMMENT ON FUNCTION turno_ocupacion_publica(UUID) IS
  'Reemplazo acotado de turno_select_publico para el caso de uso (a): GET /profesionales/:id/slots '
  'y la validación interna RN1/RN2 de POST /turnos (backend/src/dominio/disponibilidad.ts). Expone '
  'solo inicio/fin de turnos activos de UN profesional — no cliente_id, no negocio_id, no otros '
  'profesionales. No adoptada por Backend todavía, ver 03-arquitectura/modelo-datos.md §5bis.';
REVOKE EXECUTE ON FUNCTION turno_ocupacion_publica(UUID) FROM PUBLIC;

CREATE FUNCTION turno_propio_para_gestion(p_turno_id UUID)
RETURNS TABLE(
  id UUID, cliente_id UUID, profesional_id UUID, servicio_id UUID,
  negocio_id UUID, inicio TIMESTAMPTZ, fin TIMESTAMPTZ, estado estado_turno
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT t.id, t.cliente_id, t.profesional_id, t.servicio_id, t.negocio_id, t.inicio, t.fin, t.estado
  FROM turno t
  WHERE t.id = p_turno_id;
$$;
COMMENT ON FUNCTION turno_propio_para_gestion(UUID) IS
  'Reemplazo acotado de turno_select_publico para el caso de uso (b): PATCH /turnos/:id/cancelar y '
  '/reprogramar (backend/src/routes/turnos.ts) necesitan poder leer un turno por id SIN filtrar '
  'por cliente_id todavía, para poder distinguir 403 (no es tuyo) de 404 (no existe) en código, y '
  'reprogramar además necesita servicio_id/profesional_id/negocio_id/estado para recalcular la '
  'duración y el turno nuevo. No expone creado_en/modificado_en (ninguno de los dos handlers los '
  'usa). No adoptada por Backend todavía, ver 03-arquitectura/modelo-datos.md §5bis.';
REVOKE EXECUTE ON FUNCTION turno_propio_para_gestion(UUID) FROM PUBLIC;
