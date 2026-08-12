-- Turnos Profesionales — migración inicial (Postgres)
-- Rol: DBA · Fase 3 — Diseño (evolucionada en varios ciclos posteriores: fix CRITICAL-1 §2bis,
-- generalización N:M §2ter, D10/duracion_cita_min §2quater, la ratificación de RLS del
-- 2026-08-09, y HU-20/HU-21/HU-35 del 2026-08-10 (ficha de paciente extendida + historial
-- clínico + login con Google) — ver 03-arquitectura/modelo-datos.md para el detalle completo de
-- cada una y memory/proyectos/turnos-profesionales/decisiones.md para la traza de decisiones).
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
--
-- 2026-08-10 (DBA) — HU-20 (ficha de paciente extendida), HU-21 (historial clínico: Tratamiento/
-- Nota médica) y HU-35 (login con Google). 3 tablas nuevas (`paciente`, `tratamiento`,
-- `nota_medica`, con RLS FORCE desde el primer commit — ver bloque dedicado más abajo), 1 columna
-- nueva en `negocio` (`es_rubro_salud`, D11/RN15) y 3 cambios en `usuario` (`password_hash` pasa
-- a nullable, + `google_id`, + `telefono`). Detalle completo del razonamiento junto a cada bloque
-- y en modelo-datos.md. IMPORTANTE — a diferencia de los 3 ciclos anteriores que editaron este
-- archivo directamente (arriba), este es el PRIMER ciclo en que ya existe un Postgres de
-- producción real y persistente (Render) que ya corrió `runMigrations()` una vez — editar este
-- archivo por sí solo NO alcanza para que estos cambios lleguen a esa base (el gate de
-- `runMigrations()`, ver backend/src/db.ts, salta el script COMPLETO si la tabla `usuario` ya
-- existe). El delta para aplicar a mano contra un ambiente ya migrado vive en
-- `002_pacientes_historial_auth_google.sql`, mismo directorio — ver su propio header para el
-- detalle completo de este gap operativo y cómo correrlo.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE rol_usuario AS ENUM ('cliente', 'profesional', 'administrador');
CREATE TYPE estado_turno AS ENUM ('pendiente_de_pago', 'confirmado', 'cancelado', 'reprogramado');
CREATE TYPE estado_pago AS ENUM ('pendiente', 'acreditado', 'rechazado', 'expirado');

-- usuario se crea antes que negocio porque negocio_administrador (definida más abajo,
-- reemplaza a la antigua columna negocio.admin_usuario_id) referencia usuario(id).
--
-- `password_hash` pasa de NOT NULL a NULLABLE + se agrega `google_id` (HU-35, 2026-08-10, login
-- con Google). Resuelve la pregunta abierta explícita que backlog.md dejaba para Backend/DBA
-- ("la tabla usuario no contempla un alta sin contraseña propia") — decisión formalizada también
-- ahí, reemplazando esa pregunta por este mismo razonamiento. Alternativas evaluadas:
-- (a) columna nullable + una columna separada "proveedor_auth" (ENUM) para distinguir cómo
--     autentica cada usuario;
-- (b) un hash placeholder no utilizable (una constante que bcrypt nunca produciría de una
--     contraseña real) en vez de NULL;
-- (c, ELEGIDA) `password_hash` nullable + `google_id` nullable/UNIQUE, SIN columna "proveedor"
--     separada, más un CHECK que exige al menos una de las dos.
-- Se descarta (b): un placeholder es un caso especial invisible en el esquema (nada en el DDL
-- documenta qué constante es "falsa"; código que compare contra password_hash sin saber del
-- placeholder puede tratarlo como hash real) — NULL es autoexplicativo ("no tiene contraseña") y
-- el motor lo hace explícito por construcción, sin convención tácita que alguien pueda olvidar.
-- Se descarta (a) frente a (c) por redundancia: un "proveedor_auth" separado puede
-- desincronizarse de qué columnas están realmente pobladas (ej. quedar en 'google' con
-- password_hash NOT NULL de antes, o viceversa) — (c) deriva el/los métodos disponibles
-- directamente de qué columnas tienen valor, una sola fuente de verdad por hecho. Además (c) da
-- una garantía declarativa que (a) no da gratis: el CHECK de abajo impide a nivel de base de
-- datos que exista una fila sin NINGÚN método de login válido (cuenta huérfana, imposible de
-- autenticar). Si más adelante hace falta saber "cómo se registró originalmente" este usuario
-- (pregunta de negocio/analítica, no de autorización), se puede agregar sin romper nada — hoy
-- ninguna HU lo pide.
-- `google_id`: el claim `sub` (subject) del ID token de Google — identificador estable e
-- inmutable de la cuenta, NO el email (mejor práctica estándar de OIDC: un email puede cambiar;
-- `sub` no). UNIQUE (nullable-safe: Postgres permite múltiples NULL en una columna UNIQUE, así
-- que no afecta a las cuentas sin Google) para resolver "¿ya existe una cuenta para este Google?"
-- con una query directa por igualdad en el login.
-- **Recomendación para Backend (no implementada acá, fuera del alcance de DBA) — CORREGIDA
-- 2026-08-10/11 para alinearse con la revisión de Security (`07-seguridad/informe-seguridad.md`,
-- Adenda 2026-08-10, parte A — resuelta EN PARALELO a este mismo cambio, ver también
-- `02-backlog/backlog.md` HU-35): la primera versión de este comentario recomendaba vincular
-- automáticamente por coincidencia de email verificado — es EXACTAMENTE la alternativa que
-- Security evaluó y descartó ("no cierra los escenarios de email reciclado/cuenta Google
-- comprometida/Workspace"), así que se corrige acá para no dejar una recomendación contradictoria
-- entre este archivo y el backlog ya aprobado.**
-- `POST /auth/login-google` (o el endpoint que se defina) debería: 1) buscar por `google_id`
-- primero (login recurrente, ya vinculada); 2) si no hay match y NO existe ninguna cuenta con ese
-- email todavía, crear una fila nueva (`password_hash = NULL, google_id = <sub>`) SOLO si el ID
-- token trae `email_verified: true` — rechazar el alta si viene `false`; 3) si SÍ existe una
-- cuenta previa por contraseña con ese email, **NUNCA vincular ni loguear automáticamente, sin
-- importar `email_verified`** — responder pidiendo que confirme su contraseña actual en el mismo
-- flujo, y recién tras validarla (mismo mecanismo que `/login` de contraseña) persistir
-- `UPDATE usuario SET google_id = ...` sobre esa fila existente. Reglas completas y el porqué en
-- `informe-seguridad.md` (adenda citada arriba). Además, `/login` de contraseña (existente,
-- `src/routes/auth.ts`) hoy hace `bcrypt.compareSync(password ?? '', usuario.password_hash)` sin
-- chequear que `password_hash` no sea NULL — con esta migración, una cuenta 100% Google que
-- intente loguearse por contraseña pasaría un `NULL` como hash a bcrypt; agregar un chequeo
-- explícito (`if (!usuario.password_hash) return 401`) antes de esa línea, para no depender de
-- cómo maneje `bcryptjs` un hash nulo.
--
-- `telefono` (dato básico de Cliente, documento-funcional.md §5 glosario: "nombre, email,
-- teléfono" — NO es un campo extendido de HU-20/D11, aplica a todos los rubros/roles por igual,
-- a diferencia de los campos de `paciente` de más abajo). No existía como columna pese a estar
-- documentado como dato básico desde el origen del proyecto — brecha real encontrada al modelar
-- HU-20 (la Ficha de Paciente, mapa-pantallas.md §5.9bis, lo muestra como 1 de los 3 campos
-- obligatorios del formulario, junto a nombre/email). Vive en `usuario` (no en `paciente`) por
-- el mismo motivo que nombre/email: es un dato de IDENTIDAD de la persona, no de la relación
-- profesional↔paciente — editarlo desde cualquier pantalla (Editar Perfil, Editar Paciente) lo
-- actualiza una sola vez para toda la plataforma, igual que ya pasa hoy con nombre/email.
-- Nullable porque las cuentas existentes no lo tienen y `POST /auth/registro-cliente` hoy no lo
-- pide.
-- **Nota abierta para Arquitecto/Backend (no resuelta acá, fuera del alcance de DBA):** editar
-- nombre/email/teléfono desde "Editar Paciente" (pantalla que vive DENTRO del contexto de un
-- negocio/profesional) escribe sobre la fila GLOBAL de `usuario`, visible para cualquier otro
-- negocio donde esa misma persona también sea cliente — un profesional de un negocio puede así
-- cambiar el teléfono que ve otro profesional de otro negocio totalmente distinto. Es el mismo
-- comportamiento que ya existe hoy para nombre/email (no lo introduce esta migración) y coincide
-- con la app de referencia, pero vale la pena dejarlo señalado: `usuario` sigue sin RLS
-- habilitada (ver nota en `POST /auth/registro-cliente`, `src/routes/auth.ts`), así que hoy esa
-- escritura depende enteramente de que el endpoint la autorice bien en código de aplicación, sin
-- ninguna capa de RLS de respaldo.
CREATE TABLE usuario (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT NOT NULL UNIQUE,
  password_hash   TEXT,
  google_id       TEXT UNIQUE,
  telefono        TEXT,
  nombre          TEXT NOT NULL,
  rol             rol_usuario NOT NULL,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en   TIMESTAMPTZ,
  CONSTRAINT ck_usuario_password_o_google
    CHECK (password_hash IS NOT NULL OR google_id IS NOT NULL)
);

-- `es_rubro_salud` (D11/RN15, 2026-08-10 — HU-20). D11 (documento-funcional.md §1) dejó
-- pendiente para DBA el "criterio determinístico" para reconocer un negocio de rubro salud,
-- ofreciendo 2 alternativas: lista cerrada de rubros válidos, o un flag booleano dedicado ("ej.
-- es_rubro_salud" — se usa acá literalmente el nombre que ya proponía esa decisión). Se elige el
-- flag booleano sobre la lista cerrada porque `rubro` ya tiene datos reales como texto libre
-- (ej. "Salud", "Entrenamiento Personal", ver capturas en mapa-pantallas.md §5.11bis) y forzar
-- una migración a un catálogo cerrado arriesgaría invalidar valores existentes o ser demasiado
-- rígido para rubros futuros que el CEO no anticipó — mismo criterio de "la solución más simple
-- que resuelve el hallazgo sin sobre-diseñar" ya usado en el fix de CRITICAL-1 (§2bis).  `rubro`
-- se mantiene sin cambios (texto libre, para mostrar/describir el negocio); `es_rubro_salud` es
-- la señal consultable y determinística que gatea los campos extendidos de `paciente` (ver esa
-- tabla más abajo) — Backend/Mobile deciden mostrar/ocultar esos campos con
-- `SELECT es_rubro_salud FROM negocio WHERE id = ?`, no parseando `rubro`.
-- DEFAULT false (no NULL) + NOT NULL: un negocio recién creado nunca debería dejar esto
-- indefinido — el administrador lo confirma explícitamente al elegir su rubro en el alta
-- (HU-00a), con `false` como default seguro (no expone campos de salud por accidente si todavía
-- no se decidió explícitamente que corresponde).
-- Pendiente operativo (documentado, no ejecutado acá — es backfill de datos, no DDL): los
-- negocios ya existentes con `rubro` de salud en texto libre (ej. 'Salud') no van a tener
-- `es_rubro_salud = true` automáticamente — requiere una corrección manual puntual (sugerida en
-- 03-arquitectura/modelo-datos.md), no un patrón de texto ciego, porque requiere criterio humano
-- sobre qué valores de `rubro` realmente califican.
CREATE TABLE negocio (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            TEXT NOT NULL,
  rubro             TEXT,
  es_rubro_salud    BOOLEAN NOT NULL DEFAULT false,
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
-- Ficha de paciente extendida + historial clínico (HU-20/HU-21, 2026-08-10, DBA)
-- ============================================================================
-- Contexto: HU-20 pide campos ampliados de "ficha de paciente" (fecha de nacimiento, género,
-- dirección, alergias, contacto de emergencia, notas médicas, estado activo/inactivo) y HU-21
-- pide 2 entidades nuevas (Tratamiento, Nota médica) — ninguna de las dos existía en el modelo
-- hasta este ciclo (documento-funcional.md §5, glosario, ya las listaba como "no existe hoy en
-- el modelo de datos — a modelar por DBA").
--
-- Decisión de diseño (la pregunta central de este ciclo, más allá de "qué columnas"): ¿dónde
-- viven estos datos? Se evaluaron 2 alternativas obvias antes de decidir una tercera:
-- (a) columnas nuevas directamente en `usuario` (así como ya viven nombre/email) — tratar al
--     paciente como una extensión 1:1 de la identidad global del cliente;
-- (b) una tabla `paciente` nueva, 1:1 con `usuario` (mismo dato, solo separada para no ensuciar
--     `usuario` con columnas nullable de un solo rol) — la formulación literal de la pregunta
--     que motivó este ciclo (columnas en "cliente" vs. tabla "paciente" 1:1 con "cliente");
-- (c, ELEGIDA) una tabla `paciente` nueva, pero NO 1:1 con `usuario` — 1 fila por cada
--     combinación (negocio_id, profesional_id, cliente_id).
-- Se descartan (a) y (b) por el MISMO motivo, verificado con evidencia textual explícita, no por
-- preferencia estilística: RN7/RN13/D3 (documento-funcional.md §3) exigen que el historial de
-- visitas Y los tratamientos/notas médicas sean "visible[s] únicamente para el profesional que
-- lo atendió/registró... No se comparte entre profesionales del mismo negocio" — y HU-19
-- (backlog.md) extiende EXPLÍCITAMENTE ese mismo criterio a la ficha completa, no solo al
-- historial/notas: "guardar el estado [activo/inactivo] como un atributo propio del paciente
-- (SCOPE POR PROFESIONAL, mismo criterio de privacidad que el resto de LA FICHA, RN7/D3)". Y
-- HU-22 (import/export) confirma que la ficha completa (básica + extendida de HU-20) se exporta
-- "solo su propia cartera" bajo el mismo RN7/D3. Es decir: la ficha (no solo tratamientos y
-- notas) es un dato que cada profesional lleva POR SU CUENTA de cada paciente — dos
-- profesionales del MISMO negocio atendiendo al MISMO cliente llevan fichas independientes, que
-- pueden divergir (ej. uno marca a María como "inactiva" en su cartera; el otro no). Una columna
-- en `usuario` (a) o una tabla 1:1 con `usuario` (b) solo puede guardar UN valor de cada campo
-- por persona — estructuralmente incompatible con "dos profesionales, dos fichas". `negocio_id`
-- se suma además de `profesional_id` (no alcanzaría con profesional_id solo) por D1/RN9: un
-- mismo profesional puede pertenecer a 2+ negocios (§2ter) y el dato de un cliente "dentro de un
-- negocio" debe aislarse por negocio también — sin esto, el mismo profesional atendiendo al
-- mismo cliente en 2 consultorios distintos compartiría una única ficha entre ambos negocios,
-- exactamente el cruce que D1/RN9 prohíbe para cualquier otro dato de cliente.
--
-- Nota para Backend: esto es DISTINTO de lo que preguntaba literalmente la consigna de este
-- ciclo ("¿columnas en `cliente` o tabla `paciente` 1:1 con `cliente`?") — no existe ninguna
-- tabla `cliente` en este esquema (el rol "cliente" es un valor de `usuario.rol`; ver
-- `turno.cliente_id UUID REFERENCES usuario(id)` como precedente de esa misma convención), y la
-- cardinalidad real que exigen RN7/RN13/D3/HU-19/HU-22 no es 1:1 sino 1 fila por
-- (negocio_id, profesional_id, cliente_id) — más granular que lo que planteaba la pregunta
-- original. Ver 03-arquitectura/modelo-datos.md para el mismo razonamiento con más contexto.
--
-- `paciente` NO se limita a negocios de rubro salud (a diferencia de sus columnas extendidas, ver
-- abajo): HU-19 (estado activo/inactivo, "Gestión de Pacientes") y HU-10/HU-11 (listado de
-- clientes + historial) NO están condicionadas por rubro — son la base de "mi cartera" para
-- CUALQUIER profesional. Por eso `paciente` existe en general (1 fila por cada cliente que un
-- profesional atendió o agregó), y son específicamente las columnas de salud (fecha_nacimiento en
-- adelante) las que quedan vacías/sin usar para negocios que no son de rubro salud (D11/RN15) —
-- gateado por `negocio.es_rubro_salud` a nivel de aplicación (Backend/Mobile deciden mostrar u
-- ocultar esos campos consultando esa columna; no es un CHECK de base de datos porque Postgres no
-- puede validar contra una columna de OTRA tabla sin un trigger — mismo criterio ya usado en
-- §2ter para no implementar como constraint la validación de integridad profesional↔negocio, ahí
-- documentada como recomendación en vez de trigger).
--
-- Recomendación para Backend sobre CUÁNDO se crea la fila `paciente`: no implementado acá (fuera
-- de alcance de DBA) — 2 opciones razonables, ninguna cerrada: (i) al vuelo, la primera vez que
-- el profesional abre/edita la ficha de un cliente (lazy); (ii) automáticamente cuando se crea el
-- primer turno entre ese profesional y ese cliente dentro de ese negocio (mismo momento en que
-- HU-23/CU6 ya resuelven "el paciente ya existe en su cartera (o se da de alta en el mismo
-- flujo)"). El UNIQUE de abajo permite un INSERT ... ON CONFLICT (negocio_id, profesional_id,
-- cliente_id) DO NOTHING para cualquiera de las dos sin duplicar filas.
CREATE TABLE paciente (
  id                            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id                    UUID NOT NULL REFERENCES negocio(id),
  profesional_id                UUID NOT NULL REFERENCES profesional(id),
  cliente_id                    UUID NOT NULL REFERENCES usuario(id),
  -- Campos extendidos (HU-20/D7/RN12) — solo relevantes/mostrados para negocios de rubro salud
  -- (D11/RN15, negocio.es_rubro_salud = true), pero SIN CHECK que lo fuerce (ver nota arriba):
  -- gate de aplicación, no de base de datos. Todos nullable — "todos los campos nuevos son
  -- opcionales salvo los que ya son requeridos hoy" (HU-20, criterio de aceptación).
  fecha_nacimiento              DATE,
  -- TEXT libre, sin CHECK/ENUM a propósito: el wireframe (mapa-pantallas.md §5.9) muestra un
  -- dropdown ("Prefiero no decir" entre las opciones) pero es contenido de UI, no una regla de
  -- negocio que dependa de valores específicos (a diferencia de rol_usuario/estado_turno, que sí
  -- son ENUM porque controlan lógica real) — dejarlo TEXT evita que agregar/cambiar una opción
  -- del dropdown alguna vez requiera una migración de esquema.
  genero                        TEXT,
  direccion                     TEXT,
  contacto_emergencia_nombre    TEXT,
  contacto_emergencia_telefono  TEXT,
  -- Mismo criterio que `genero`: TEXT libre, el dropdown ("Familiar", etc.) es UI, no negocio.
  contacto_emergencia_relacion  TEXT,
  alergias                      TEXT,
  notas_medicas_generales       TEXT,
  -- Campo NO extendido/NO gateado por rubro (D20/RN20/HU-19) — activo/inactivo aplica a
  -- cualquier paciente de cualquier rubro. BOOLEAN (no un `estado` TEXT/ENUM), mismo criterio ya
  -- usado en `negocio_profesional.activo`. Manual únicamente (RN20): sin trigger ni job que lo
  -- recalcule por antigüedad de la última visita — el profesional lo cambia a mano.
  activo                        BOOLEAN NOT NULL DEFAULT true,
  creado_en                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por                    UUID,
  modificado_en                 TIMESTAMPTZ,
  modificado_por                UUID,
  -- Soft delete (no está en la lista original Negocio/Profesional/Servicio del estándar de
  -- empresa, docs/06-modelo-datos.md §3, pero por el MISMO motivo que ahí: "no romper el
  -- historial... si se da de baja" — acá, no romper `tratamiento`/`nota_medica`, que referencian
  -- `paciente_id`, si un profesional necesita retirar una ficha creada por error/duplicada).
  eliminado_en                  TIMESTAMPTZ,
  -- Un profesional lleva UNA sola ficha por cliente, POR NEGOCIO (ver razonamiento arriba) — el
  -- mismo trío no puede repetirse. Habilita además un INSERT ... ON CONFLICT DO NOTHING/UPDATE
  -- para el alta perezosa/automática que se recomienda a Backend más arriba.
  CONSTRAINT uq_paciente_negocio_profesional_cliente UNIQUE (negocio_id, profesional_id, cliente_id)
);
-- No hace falta un índice aparte sobre (negocio_id) ni sobre (negocio_id, profesional_id): la
-- UNIQUE de arriba ya es, en sí misma, un índice cuyo prefijo izquierdo cubre exactamente esas 2
-- consultas (ej. "mis pacientes en el negocio activo" = WHERE negocio_id = ? AND profesional_id
-- = ?, la consulta dominante bajo el patrón "vista activa" de auth.ts/modelo-datos.md §2ter). Sí
-- hace falta un índice propio para el sentido inverso (cliente_id no es prefijo de esa UNIQUE):
CREATE INDEX idx_paciente_cliente ON paciente (cliente_id);

-- Tratamiento (HU-21/D8/RN13) — "proceso de seguimiento asociado a un paciente por un
-- profesional, independiente de un turno puntual" (documento-funcional.md §5). Referencia
-- ÚNICAMENTE `paciente_id` (no negocio_id/profesional_id propios, a diferencia de `turno`): a
-- diferencia de `turno` (que puede resolver su negocio_id por más de un camino posible, ver
-- razonamiento de §2ter sobre servicio.negocio_id), acá el ÚNICO padre posible es `paciente`, ya
-- NOT NULL y sin ambigüedad — repetir negocio_id/profesional_id acá sería una redundancia con
-- una única fuente de verdad (la de `paciente`) que podría desincronizarse; se resuelve por JOIN
-- en la policy de RLS de más abajo, mismo criterio ya aceptado en este esquema para
-- disponibilidad/excepcion_disponibilidad/profesional_servicio (ver "pendiente para una próxima
-- iteración" en la sección de RLS original, más abajo).
CREATE TABLE tratamiento (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id     UUID NOT NULL REFERENCES paciente(id),
  descripcion     TEXT NOT NULL,
  fecha_inicio    DATE NOT NULL,
  -- Nullable: un tratamiento puede seguir abierto/en curso (sin evidencia de wireframe de un
  -- campo de fin, pero "proceso de seguimiento" del glosario admite duración — bajo riesgo
  -- agregarlo nullable desde ahora en vez de necesitar otra migración cuando se pida).
  fecha_fin       DATE,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID
);
CREATE INDEX idx_tratamiento_paciente ON tratamiento (paciente_id);

-- Nota médica (HU-21/D8/RN13) — "anotación clínica/de seguimiento... independiente de un turno
-- puntual" (documento-funcional.md §5). Mismo criterio de referencia que `tratamiento` (solo
-- paciente_id, ver comentario de arriba).
CREATE TABLE nota_medica (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paciente_id     UUID NOT NULL REFERENCES paciente(id),
  fecha           DATE NOT NULL DEFAULT CURRENT_DATE,
  texto           TEXT NOT NULL,
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID
);
CREATE INDEX idx_nota_medica_paciente ON nota_medica (paciente_id);

-- Recomendación para Backend — cómo resolver los 4 stat cards de HU-21 (mapa-pantallas.md
-- §5.10): "Citas totales"/"Completadas" NO salen de `paciente`/`tratamiento`/`nota_medica` —
-- salen de `turno`, igual que el historial de visitas ya lo hace hoy (RN7):
--   SELECT count(*) FROM turno WHERE cliente_id = ? AND profesional_id = ?                  -- Citas totales
--   SELECT count(*) FROM turno
--     WHERE cliente_id = ? AND profesional_id = ? AND estado = 'confirmado' AND fin < now()  -- Completadas
-- "Completadas" se deriva así (confirmado + ya pasado) porque `estado_turno` (ver ENUM al
-- principio de este archivo) NO tiene un valor 'atendido'/'completado' propio — un turno
-- confirmado se queda en 'confirmado' para siempre, incluso después de ocurrir (el comentario de
-- "Historial de visitas" en modelo-datos.md que menciona un estado "atendido" es conceptual, no
-- un valor real del ENUM — confirmado al revisar `CREATE TYPE estado_turno` más arriba). Agregar
-- un valor nuevo al ENUM (ej. 'completado', con o sin un job que lo transicione automáticamente
-- al pasar `fin`) sería la alternativa más prolija a mediano plazo, pero es un cambio de
-- comportamiento sobre la máquina de estados de `turno` (documento-arquitectura.md §3, ya
-- aprobada) — fuera del alcance de este ciclo (HU-21 pide modelar Tratamiento/Nota médica, no
-- rediseñar el estado de turno); se documenta acá como recomendación para un ciclo futuro, no se
-- implementa. "Tratamientos"/"Notas médicas" sí son conteos directos y triviales sobre las
-- tablas nuevas:
--   SELECT count(*) FROM tratamiento WHERE paciente_id = ?
--   SELECT count(*) FROM nota_medica WHERE paciente_id = ?

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
-- CORRECCIÓN (2026-08-10, confirmado con una consulta de diagnóstico real, con ROLLBACK, contra
-- Postgres real): el comentario de arriba ("Sin esa variable seteada, current_setting(..., true)
-- devuelve NULL") es cierto solo para una variable que NUNCA se seteó en la sesión — pero un
-- `RESET nombre_variable` explícito sobre una variable custom (no declarada en postgresql.conf),
-- después de haberla seteado con `set_config`, la deja en STRING VACÍO (''), no en NULL —
-- comportamiento real de Postgres, verificado empíricamente (no en la documentación general).
-- `''::uuid` lanza una excepción ("invalid input syntax for type uuid") en vez de evaluar la
-- policy a `false` como sí hace `NULL::uuid` — un `RESET` explícito de `app.usuario_id` a mitad
-- de una transacción (no el patrón normal de `withTransaction`, backend/src/db.ts, que usa
-- `SET LOCAL`/`set_config(..., true)` y deja que ese valor expire solo al terminar la
-- transacción — eso sí revierte a NULL limpio) podría hacer que una policy explote en vez de
-- denegar. Encontrado por ../scripts/verificar_rls_postgres.sql (Security), que sí ejercita ese
-- camino a propósito para simular "sin contexto" dentro de una misma transacción larga.
-- Todas las políticas de abajo que casteaban `current_setting('app.usuario_id', true)` directo a
-- `::uuid` ahora lo envuelven en `NULLIF(..., '')` antes del cast — convierte tanto NULL como ''
-- en NULL, así que el resultado (denegar, no romper) es el mismo sin importar cuál de los dos
-- devuelva `current_setting` en cada caso.
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
      WHERE na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );
CREATE POLICY profesional_update_admin_de_su_negocio ON profesional
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN negocio_administrador na ON na.negocio_id = np.negocio_id
      WHERE np.profesional_id = profesional.id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
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
    profesional.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
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
  FOR SELECT USING (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
CREATE POLICY negocio_administrador_insert_propio ON negocio_administrador
  FOR INSERT WITH CHECK (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);

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
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );
CREATE POLICY negocio_profesional_update_admin_del_negocio ON negocio_profesional
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = negocio_profesional.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
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
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );
CREATE POLICY servicio_update_admin_del_negocio ON servicio
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = servicio.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
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
    cliente_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    OR EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = turno.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
    OR EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN profesional p ON p.id = np.profesional_id
      WHERE np.negocio_id = turno.negocio_id
        AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  )
  WITH CHECK (
    cliente_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    OR EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = turno.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
    OR EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN profesional p ON p.id = np.profesional_id
      WHERE np.negocio_id = turno.negocio_id
        AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
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
-- RLS de paciente/tratamiento/nota_medica (HU-20/HU-21, 2026-08-10, DBA) — aplicando desde el
-- primer commit la lección de §5bis de este mismo archivo: CUALQUIER tabla nueva lleva FORCE ROW
-- LEVEL SECURITY además de ENABLE, no solo ENABLE (el gap de ownership que dejó toda la RLS de
-- este proyecto sin efecto real hasta 2026-08-09 aplicaría igual, desde el día 1, a cualquier
-- tabla nueva que se olvide de FORCE).
-- ============================================================================
--
-- A diferencia de `turno`/`servicio` (visibles para CUALQUIER staff del negocio — administrador
-- o cualquier profesional activo), acá el criterio es más estricto: SOLO el profesional dueño de
-- la fila (RN7/RN13/D3 — "visible únicamente para el profesional que lo atendió/registró... No
-- se comparte entre profesionales del mismo negocio"). Ni el administrador del negocio ni otro
-- profesional del mismo negocio pasan esta policy — coincide con el default ya documentado en
-- documento-funcional.md §6 ("Alcance de permisos del administrador... A7/D3 dejan al
-- administrador sin acceso al historial por defecto"), que ese documento deja como pregunta
-- menor todavía abierta, NO cerrada acá: si en un próximo ciclo el CEO confirma que el
-- administrador SÍ debe tener acceso, agregar una policy adicional (OR EXISTS contra
-- negocio_administrador, mismo patrón que `turno`) es aditivo y no rompe esta.
--
-- Tampoco hay policy para que el propio cliente/paciente vea su ficha/tratamientos/notas: ninguna
-- HU de este ciclo pide una vista de ese lado (Mobile, modo Cliente) — se puede agregar sin
-- romper nada si se pide más adelante.
ALTER TABLE paciente ENABLE ROW LEVEL SECURITY;
ALTER TABLE paciente FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo
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

-- tratamiento/nota_medica: NO repiten negocio_id/profesional_id (ver comentario junto a su
-- CREATE TABLE) — la policy se ancla en `paciente` vía JOIN, reusando exactamente el mismo
-- criterio de dueño único (profesional) que la policy de arriba, para que nunca puedan quedar
-- desincronizadas entre sí (no hay 2 columnas "profesional_id" que puedan decir cosas distintas).
ALTER TABLE tratamiento ENABLE ROW LEVEL SECURITY;
ALTER TABLE tratamiento FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo
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

ALTER TABLE nota_medica ENABLE ROW LEVEL SECURITY;
ALTER TABLE nota_medica FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo
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

-- ============================================================================
-- Preferencias de privacidad de usuario (HU-32, 2026-08-11, DBA)
-- ============================================================================
-- Origen: HU-32 (E14, 02-backlog/backlog.md) — "Como cliente o profesional, quiero controlar la
-- visibilidad de mi perfil (público/solo contactos/privado), si muestro mi estado en línea, y si
-- comparto datos de uso con la plataforma... Es transversal a ambos roles, no una funcionalidad
-- específica de un negocio." Wireframe en mapa-pantallas.md §5.13 (bloque "Privacidad" de la
-- pantalla "Privacidad y Seguridad"), verificado contra una captura real de la app de referencia
-- en §5.13bis (2026-08-07) — esa verificación confirma dos cosas relevantes para este modelado:
-- (1) "Visibilidad de mi perfil" es un grupo de radio buttons de 3 opciones fijas, no un input
-- libre; (2) el bloque "Seguridad de la cuenta" (contraseña, 2FA, biometría, sesiones,
-- exportar/eliminar datos) que el mismo wireframe mostraba junto a "Privacidad" NO EXISTE en la
-- app real — confirmado como adición de UX/UI sin HU propia, así que no se modela nada de eso acá
-- (ni tabla ni columnas): si Product Manager le asigna una HU en un ciclo futuro, es modelado
-- nuevo, no una extensión de esta tabla.
--
-- Un 4to control visible en la misma captura real, "Permitir Notificaciones" (entre "Mostrar
-- Estado en Línea" y "Compartir Datos de Uso"), queda EXPLÍCITAMENTE fuera de este modelado —
-- decisión de alcance para este ciclo, no un olvido: se superpone temáticamente con
-- HU-26/Configuración de Notificaciones (mapa-pantallas.md §5.14, "único lugar de la app donde se
-- activan/desactivan tipos de aviso y canales"), que todavía no se modeló. Modelarlo acá
-- adelantaría/pisaría ese trabajo futuro. Cuando se modele HU-26, ese ciclo decide si ese toggle
-- vive junto a la configuración granular de notificaciones (lo más consistente con "un solo lugar
-- para switches de notificación", ya documentado en mapa-pantallas.md §5.14) o si en cambio
-- necesita su propio campo acá — no se decide hoy.
--
-- DECISIÓN DE DISEÑO — ¿columnas en `usuario` o tabla `usuario_preferencias` separada 1:1?
-- A diferencia de la decisión equivalente para `paciente` (2026-08-10, ver bloque "Ficha de
-- paciente..." más arriba y modelo-datos.md §2quinquies), acá la cardinalidad NO fuerza la
-- respuesta: HU-32 es explícitamente "transversal... no una funcionalidad específica de un
-- negocio", y mapa-pantallas.md §5.13 confirma "pantalla y contenido idénticos para ambos roles
-- (misma cuenta, mismas garantías de privacidad)" — un solo valor por `usuario`, sin scope por
-- negocio/profesional/cliente como sí necesitaba `paciente`. Es decir, tanto "columnas en
-- `usuario`" como "tabla 1:1" son estructuralmente válidas acá (a diferencia de lo que pasaba con
-- `paciente`, donde una de las dos alternativas era directamente incompatible con los hechos) — la
-- decisión se toma por otro criterio, no por cardinalidad forzada. Se elige TABLA SEPARADA
-- (`usuario_preferencias`, 1:1 con `usuario` vía `usuario_id UNIQUE`) por 3 motivos:
--
-- 1) Separación de responsabilidades / crecimiento acotado: `usuario` es la tabla de
--    identidad/autenticación — se consulta en cada login y la referencian por FK casi todas las
--    demás tablas de este esquema (profesional, turno, paciente, negocio_administrador...). Sus
--    columnas hoy son todas hechos de identidad (email, password_hash, google_id, telefono,
--    nombre, rol). Las preferencias de privacidad/app son un concern independiente que ya se sabe
--    va a seguir creciendo: HU-26 (Configuración de Notificaciones, mismo menú "Cuenta" que HU-32
--    en mapa-pantallas.md §5.12/§5.14) queda para la próxima ronda a propósito (ver arriba), y el
--    propio wireframe de §5.13 documenta un bloque adicional ("Seguridad de la cuenta") que, si
--    algún ciclo futuro le asigna una HU propia, sería exactamente más columnas de este mismo tipo
--    ("configuración de cuenta", no "identidad"). Una tabla separada absorbe ese crecimiento
--    futuro sin seguir ensanchando `usuario` con columnas ajenas a autenticación cada vez que se
--    agrega una preferencia nueva.
-- 2) Precedente ya establecido en este mismo esquema: `profesional` (2026-08-06, §2ter) es
--    exactamente este mismo patrón — una tabla satélite 1:1 con `usuario` (`usuario_id UNIQUE
--    REFERENCES usuario(id)`), separada de `usuario` pese a ser 1:1, precisamente para no mezclar
--    la identidad base con un concern distinto (ahí, "ser profesional"; acá, "mis preferencias de
--    privacidad"). `usuario_preferencias` sigue la misma forma estructural: GUID propio
--    (`id UUID PRIMARY KEY DEFAULT gen_random_uuid()`) + `usuario_id UNIQUE REFERENCES
--    usuario(id)` para expresar el 1:1 — mismo patrón que `profesional`/`pago` en este archivo, en
--    vez de usar `usuario_id` directamente como PK: nada referencia hoy una fila de esta tabla por
--    su propio id, pero mantener la forma consistente con el resto del esquema evita una excepción
--    sin motivo real, y no cierra la puerta si alguna vez algo necesitara referenciar una fila de
--    preferencias en particular.
-- 3) RLS como motivo de fondo, no solo de estilo — ver la conclusión siguiente.
--
-- CONCLUSIÓN SOBRE RLS DE `usuario` (pedida explícitamente antes de decidir, no asumida):
-- confirmado leyendo este archivo completo que `usuario` HOY NO TIENE Row Level Security
-- habilitada — no hay ningún `ALTER TABLE usuario ENABLE ROW LEVEL SECURITY` en ningún punto de
-- este DDL (a diferencia de profesional/negocio_administrador/negocio_profesional/servicio/turno/
-- paciente/tratamiento/nota_medica, que sí la tienen). Ya estaba señalado, para otro caso (editar
-- nombre/email/teléfono vía "Editar Paciente"), en el comentario junto al `CREATE TABLE usuario`
-- de más arriba: "`usuario` sigue sin RLS habilitada... esa escritura depende enteramente de que
-- el endpoint la autorice bien en código de aplicación, sin ninguna capa de RLS de respaldo". Es
-- una brecha real, preexistente, no introducida por este ciclo — y aplicaría igual a estas 3
-- columnas si vivieran en `usuario`: quedarían con el mismo nivel de protección (ninguno a nivel
-- de base de datos) que el resto de esa tabla, dependiendo 100% de que Backend nunca introduzca un
-- bug que permita leer o escribir la fila de otro usuario. Para HU-32 específicamente (que ES la
-- funcionalidad de privacidad) dejar sus datos en la tabla con menos defensa en profundidad de
-- todo el esquema sería, como mínimo, una señal contradictoria. La tabla separada resuelve esto de
-- forma limpia: `usuario_preferencias` es nueva, así que aplica desde el primer commit la lección
-- ya documentada en §5bis/§5ter (FORCE ROW LEVEL SECURITY desde el día 1), sin necesitar
-- auditar/blindar retroactivamente los múltiples call sites de escritura que ya existen hoy sobre
-- `usuario` (registro-cliente, registro-negocio, alta-profesional, y el futuro login-google de
-- HU-35) antes de poder habilitarle RLS con seguridad — ese es un trabajo real, más grande, y
-- fuera del alcance de este ciclo. Habilitar RLS sobre `usuario` en sí (más allá de estas 3
-- columnas) queda documentado como recomendación para un ciclo futuro de DBA/Backend, no resuelta
-- ni bloqueada acá — mismo tratamiento que otras brechas ya reconocidas en este archivo (ej.
-- `pago`/`notificacion` sin RLS, §5bis "Qué no se tocó").
--
-- Columnas — 3, una por control de HU-32/§5.13, en el mismo orden que el wireframe:
--
-- `visibilidad_perfil` — ENUM dedicado (`visibilidad_perfil_usuario`, declarado abajo), no TEXT
-- libre. Se distingue a propósito del criterio ya usado para `paciente.genero`/
-- `contacto_emergencia_relacion` (TEXT libre porque son "contenido de UI, no una regla de negocio
-- que dependa de valores específicos"): acá, a diferencia de esos dos, el campo existe
-- ESPECÍFICAMENTE para controlar qué puede ver otro usuario (público/solo contactos/privado) —
-- mismo tipo de campo que `rol_usuario`/`estado_turno`/`estado_pago` (un conjunto cerrado de
-- estados que gobierna comportamiento real), no un dato descriptivo abierto. La app real
-- (§5.13bis) confirma que son exactamente 3 opciones fijas mostradas como radio buttons,
-- reforzando que es un estado controlado, no texto libre de UI. Valores en minúscula sin tilde,
-- mismo estilo que el resto de los ENUM de este archivo. **Dónde se aplica la restricción de
-- visibilidad en sí (ej. qué endpoint deja de mostrar el perfil de un profesional "privado" a
-- quien lo busca) NO se implementa en este ciclo** — ningún endpoint de este proyecto expone hoy
-- un "perfil público" navegable de cliente/profesional más allá de lo que ya cubre `GET
-- /negocios/:id/servicios/:servicioId/profesionales` (HU-08, que no filtra por esto); queda
-- documentado para que Backend lo aplique cuando exista ese caso de uso concreto, mismo patrón que
-- el gate de `es_rubro_salud` o el fallback de `duracion_cita_min` en este archivo.
--
-- `mostrar_estado_en_linea` / `compartir_datos_uso` — BOOLEAN simples, sin ambigüedad de UI (son
-- toggles on/off tanto en el wireframe como en la captura real). `compartir_datos_uso` no lleva
-- sufijo "_plataforma" pese a que el texto de HU-32 dice "compartir datos de uso CON LA
-- PLATAFORMA" — se omite por ser la única plataforma posible en este esquema, mismo criterio de
-- evitar redundancia ya aplicado en otras columnas de este archivo (ej. `es_rubro_salud`, no
-- `negocio_es_de_rubro_salud`).
--
-- Defaults — `visibilidad_perfil = 'publico'`, `mostrar_estado_en_linea = true`,
-- `compartir_datos_uso = true`. **Supuesto explícito, NO verificado contra evidencia de "alta de
-- cuenta nueva"**: no hay wireframe ni captura del estado de una cuenta recién creada — se toman
-- los mismos 3 valores "activado" que sí muestra la captura real de §5.13bis
-- (`Screenshot_20260427_095421_Turnario.jpg`) para una cuenta EXISTENTE, asumiendo que reflejan el
-- default de fábrica de la app de referencia y no una elección explícita que ese usuario haya
-- hecho alguna vez — supuesto razonable pero no confirmable con la evidencia disponible hoy. Si en
-- un ciclo futuro aparece evidencia de que una cuenta nueva arranca con otros valores, corregir
-- estos `DEFAULT`, no solo la documentación.
--
-- Auditoría — SOLO `creado_en`/`modificado_en`, SIN `creado_por`/`modificado_por` (a diferencia de
-- `negocio`/`servicio`/`paciente`/`tratamiento`/`nota_medica`, que sí los llevan). Decisión
-- consciente, mismo criterio ya aplicado (sin explicitarlo hasta ahora) en `usuario` y
-- `profesional`: son tablas de autogestión, donde la política de RLS de más abajo garantiza que
-- quien escribe una fila es SIEMPRE el propio `usuario_id` de esa fila — `creado_por`/
-- `modificado_por` serían siempre idénticos a `usuario_id`, un dato 100% redundante. Distinto es
-- el caso de `paciente`/`tratamiento`/`nota_medica` (un profesional escribe sobre datos DE OTRA
-- persona, el cliente) o `negocio`/`servicio` (un administrador puede no ser quien más tarde
-- modifica), donde sí hace falta registrar explícitamente quién actuó porque puede no coincidir
-- con el dueño del recurso.
--
-- Sin `eliminado_en` (soft delete): a diferencia de `paciente` (que sí lo lleva porque
-- `tratamiento`/`nota_medica` referencian `paciente_id` y no hay que romper ese historial), ninguna
-- otra tabla de este esquema referencia `usuario_preferencias.id` — no hay ningún historial que
-- proteger. El ciclo de vida de esta fila está atado por completo al de `usuario`: si la cuenta se
-- da de baja, estas preferencias dejan de tener sentido junto con ella (no hay ningún caso de uso
-- de "preferencias históricas de una cuenta eliminada"). Sin `ON DELETE CASCADE` explícito en el
-- FK, igual que el resto de las referencias a `usuario(id)` en este archivo (ninguna lo usa hoy) —
-- consistente, no una omisión puntual de esta tabla.
--
-- Recomendación para Backend — cuándo se crea/actualiza la fila (no implementado acá, fuera de
-- alcance de DBA, mismo patrón ya usado para la creación perezosa de `paciente`): no hace falta
-- una fila para que una cuenta nueva "tenga" estos valores — mientras no exista fila para un
-- `usuario_id` dado, la aplicación puede devolver los 3 `DEFAULT` de arriba sin tocar la base
-- (0 filas = "todavía en default de fábrica, nunca personalizó nada"). El botón "Guardar" del
-- footer real (3 botones, ver mapa-pantallas.md §5.13bis) es el punto natural para un
-- `INSERT ... ON CONFLICT (usuario_id) DO UPDATE SET visibilidad_perfil = ..., ..., modificado_en
-- = now()` (upsert; el `UNIQUE` de `usuario_id` de abajo ya lo habilita sin duplicar filas). Qué
-- hace exactamente "Restablecer" (el 3er botón, naranja) no se resuelve acá: puede ser un
-- `DELETE FROM usuario_preferencias WHERE usuario_id = ?` (vuelve a "sin fila" = defaults) o un
-- `UPDATE` explícito a los mismos 3 valores — cualquiera de los dos es válido contra este esquema,
-- decisión de Backend.
CREATE TYPE visibilidad_perfil_usuario AS ENUM ('publico', 'solo_contactos', 'privado');

CREATE TABLE usuario_preferencias (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id               UUID NOT NULL UNIQUE REFERENCES usuario(id),
  visibilidad_perfil       visibilidad_perfil_usuario NOT NULL DEFAULT 'publico',
  mostrar_estado_en_linea  BOOLEAN NOT NULL DEFAULT true,
  compartir_datos_uso      BOOLEAN NOT NULL DEFAULT true,
  creado_en                TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en            TIMESTAMPTZ
);

-- RLS — FORCE desde el primer commit (lección de §5bis/§5ter: cualquier tabla nueva la necesita
-- desde el día 1, no solo ENABLE). Política única (sin `FOR`, aplica a SELECT/INSERT/UPDATE/
-- DELETE) porque la regla es simétrica para los 4 comandos: "cada usuario solo lee/edita su propia
-- fila" — mismo criterio de columna simple (`usuario_id = app.usuario_id`, sin JOIN) que
-- `negocio_administrador_select_propio`/`profesional_update_propio_duracion_cita` más arriba, no
-- el patrón `EXISTS` con JOIN que usan `paciente`/`tratamiento`/`nota_medica` (acá no hace falta:
-- no hay negocio/profesional de por medio, la propiedad es directa contra `usuario_id`).
ALTER TABLE usuario_preferencias ENABLE ROW LEVEL SECURITY;
-- FORCE: ver nota junto a `profesional`, más arriba en este archivo, para el porqué completo.
ALTER TABLE usuario_preferencias FORCE ROW LEVEL SECURITY;
CREATE POLICY usuario_preferencias_acceso_propio ON usuario_preferencias
  USING (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
  WITH CHECK (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);
