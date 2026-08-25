-- Turnos Profesionales — migración inicial (Postgres)
-- Rol: DBA · Fase 3 — Diseño (evolucionada en varios ciclos posteriores: fix CRITICAL-1 §2bis,
-- generalización N:M §2ter, D10/duracion_cita_min §2quater, la ratificación de RLS del
-- 2026-08-09, HU-20/HU-21/HU-35 del 2026-08-10 (ficha de paciente extendida + historial
-- clínico + login con Google), HU-32 del 2026-08-11 (preferencias de privacidad de usuario, ver
-- §2septies/§5quater — mención agregada acá; no se había sumado a este resumen en su propio
-- ciclo), HU-14b/HU-25/HU-26 del 2026-08-12 (bandeja de notificaciones con destinatario/leído +
-- preferencias de notificación, ver §2octies/§5quinquies), HU-29/E11 del 2026-08-14
-- (suscripción "Turnario Pro", ver §2novies/§5sexies), el fast-follow de E15 del 2026-08-15
-- (acceso de SOLO LECTURA del administrador al historial de pacientes — ficha/tratamiento/
-- nota_medica —, ver §5septies), la recuperación de contraseña (token de un solo uso) del
-- 2026-08-16, prioridad alta del CEO (ver §2decies/§5octies), y el resto de datos operativos de
-- HU-31 del 2026-08-17 (horario general de atención, dirección detallada, teléfono, logo — ver
-- §2undecies) — ver 03-arquitectura/modelo-datos.md para el detalle completo de cada una y
-- memory/proyectos/turnos-profesionales/decisiones.md para la traza de decisiones).
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
CREATE TYPE estado_turno AS ENUM ('por_confirmar', 'pendiente_de_pago', 'confirmado', 'cancelado', 'reprogramado');
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
--
-- Datos operativos del negocio — horario/dirección/teléfono/logo (HU-31, `02-backlog/
-- backlog.md`, épica E13) — 2026-08-17, DBA. HU-31 pide "completar datos operativos de mi negocio
-- más allá del alta inicial (horario general de atención, dirección detallada, teléfono/contacto,
-- logo o imagen)". La ronda "Modo Administrador v1" (E15, 2026-08-15) ya conectó
-- `PATCH /negocios/:id` a una pantalla real (`configuracion_consultorio_screen.dart`, modo edición
-- para `Rol.administrador`), pero la dejó ACOTADA a los 3 campos que YA tenían columna
-- (`nombre`/`rubro`/`ubicacion`) — documentado explícitamente en esa misma ronda como gap de DBA/
-- Backend, no de Mobile/UX (`backlog.md`, tabla de la épica E15: "Resto del alcance original de
-- HU-31... Sin columnas de datos ni endpoint — requiere DBA + Backend antes de poder
-- construirse"). Este ciclo cierra la mitad de DBA de ese gap: 4 columnas nuevas, TODAS nullable
-- — un negocio ya existente no tiene ninguna cargada hasta que su administrador las complete
-- desde Configuración de Consultorio; sin backfill posible ni con sentido (a diferencia de
-- `es_rubro_salud`, que sí tenía un candidato de backfill manual documentado arriba), porque son
-- datos que solo el dueño del negocio conoce. PATCH/Mobile quedan fuera de este ciclo — ver
-- recomendación para Backend al final de este bloque y `03-arquitectura/modelo-datos.md`
-- §2undecies para el razonamiento completo.
--
-- `horario_atencion` (TEXT) — texto libre, DELIBERADAMENTE NO estructurado por día (ej. "Lunes a
-- Viernes 9 a 18hs, Sábados 9 a 13hs" tal cual lo escriba el administrador, sin columnas por
-- día/franja). Es puramente INFORMATIVO para el perfil del negocio — NO participa en el cálculo
-- de disponibilidad real de ningún profesional, que sigue resuelto enteramente por
-- `disponibilidad`/`excepcion_disponibilidad` (bloques recurrentes + excepciones puntuales, POR
-- PROFESIONAL, ya mucho más granular que cualquier horario a nivel de negocio) — modelar esto
-- como una segunda fuente de "horarios" duplicaría esa lógica sin necesidad y, peor, abriría la
-- puerta a que ambas fuentes queden inconsistentes entre sí (ej. el texto libre dice "Sábados
-- cerrado" pero un profesional puntual sí tiene disponibilidad cargada ese día) sin que nada en
-- el esquema lo detecte. Mismo criterio de "no sobre-diseñar / no duplicar una única fuente de
-- verdad" ya aplicado en este archivo a `genero`/`contacto_emergencia_relacion` de `paciente`
-- (TEXT libre en vez de estructura, porque el contenido es informativo/de UI, no una regla de
-- negocio que dependa de valores específicos).
--
-- `direccion` (TEXT) — dirección postal completa (calle, altura, piso), campo NUEVO Y DISTINTO de
-- `ubicacion` (columna ya existente, SIN CAMBIOS). Investigado contra el código real antes de
-- decidir si hacía falta un campo separado o alcanzaba con ampliar `ubicacion` (no asumido): hoy
-- `ubicacion` viaja en las 2 lecturas públicas de descubrimiento (`GET /negocios` y
-- `GET /negocios/:id`, `src/routes/negocios.ts`) y Mobile la consume como referencia CORTA de
-- zona/ciudad, mostrada junto a `rubro` en el subtítulo de cada card del listado de "Buscar
-- Negocios" (HU-00b, `buscar_negocios_screen.dart`: `[rubro, ubicacion].join(' · ')`) — un texto
-- pensado para convivir con N negocios a la vez en una lista, no para una dirección postal
-- completa. `direccion` resuelve un propósito distinto y posterior en el embudo: alguien que YA
-- decidió ir a ESTE negocio puntual y necesita saber exactamente adónde, un dato que no tiene
-- sentido amontonado en la lista de descubrimiento junto a otros negocios. Sobrecargar `ubicacion`
-- con este propósito nuevo además redefiniría retroactivamente el significado de datos ya
-- cargados por negocios existentes (vía `registro_negocio_screen.dart` o el propio
-- `configuracion_consultorio_screen.dart` de la ronda anterior) bajo su semántica actual ("zona/
-- ciudad corta"), sin ninguna forma de distinguir, para esas filas, si el valor ya cargado sigue
-- sirviendo como dirección completa o no. `ubicacion` sigue sin cambios, con su mismo propósito de
-- descubrimiento; ambos campos coexisten y se muestran en contextos distintos (recomendación de
-- Mobile más abajo). Reutiliza el nombre genérico `direccion` ya usado en `paciente.direccion`
-- (mismo criterio que `nombre`/`creado_en`, columnas que también se repiten en más de una tabla de
-- este esquema con el mismo significado) — no hay ninguna relación entre ambas filas, cada una
-- vive scopeada a su propia tabla.
--
-- `telefono` (TEXT) — texto simple, sin `CHECK` de formato, mismo criterio ya aplicado a
-- `usuario.telefono` (ver `CREATE TABLE usuario`, más arriba) y a
-- `paciente.contacto_emergencia_telefono`: ninguna columna de teléfono de este esquema valida
-- formato a nivel de base de datos (distintos países/formatos, sin ninguna HU que pida un formato
-- único) — queda como posible mejora de UX en la capa de aplicación, no como constraint.
--
-- `logo_url` (TEXT) — URL de una imagen YA alojada en otro lado, NO un upload de archivo real ni
-- una columna binaria/BYTEA: este esquema no tiene (ni este ciclo agrega) ningún servicio de
-- almacenamiento de objetos (S3/Cloudinary/similar) — un agente de IA operando esta Factory no
-- puede aprovisionar por su cuenta credenciales nuevas para un servicio de storage externo, así
-- que el patrón elegido es que el administrador pegue la URL de una imagen que ya subió a algún
-- otro lado (mismo criterio ya aplicado en esta Factory para no depender de infraestructura de
-- storage nueva). Sin `CHECK` de formato de URL a nivel de base de datos — mismo criterio que
-- `usuario.email` (tampoco tiene un `CHECK` de formato en el esquema; la validación de forma vive
-- en `zod`, del lado de Backend): se recomienda a Backend agregar `z.string().url()` (o
-- equivalente) al extender `actualizarNegocioSchema`, y a Mobile replicar la misma validación
-- client-side antes de habilitar "Guardar" (mismo patrón ya usado en esta app para la longitud
-- mínima de contraseña). No se valida que la URL sea efectivamente una IMAGEN (ni acá ni se
-- recomienda hacerlo de forma estricta a nivel de aplicación): eso solo puede confirmarse
-- intentando cargarla — la recomendación para Mobile es un `Image.network(..., errorBuilder:
-- ...)` con un ícono/placeholder de fallback si la URL no carga, no un chequeo previo de
-- contenido.
--
-- Las 4 nullable, sin `DEFAULT`: mismo motivo que el resto de columnas agregadas a una tabla ya en
-- uso en este esquema (`usuario.telefono`/`google_id`, `profesional.duracion_cita_min`) — agregar
-- una columna nullable sin DEFAULT no rompe ninguna fila ni ningún INSERT existente que no la
-- mencione. Comparten el `modificado_en` genérico que la tabla ya tenía desde la Fase 3 original
-- (sin auditoría por columna individual), mismo criterio que el resto de columnas mutables de este
-- esquema. Sin Row Level Security nueva: `negocio` sigue sin tener RLS habilitada en ningún punto
-- de este archivo (ver el comentario de `PATCH /negocios/:id` en `src/routes/negocios.ts`, que ya
-- lo confirma contra el código real) — nada que agregar acá. Sin índice nuevo: ninguna consulta
-- existente ni recomendada filtra por `horario_atencion`/`direccion`/`telefono`/`logo_url` (son
-- campos de despliegue/lectura directa por `id`, igual que `rubro`/`ubicacion` hoy, que tampoco
-- tienen índice propio) — el índice implícito de la PK ya cubre el único patrón de acceso real
-- (`GET /negocios/:id`).
--
-- Recomendación para Backend (no implementada acá, fuera de alcance de DBA) — extender
-- `PATCH /negocios/:id`, `src/routes/negocios.ts`. Línea aproximada verificada contra el archivo
-- TAL COMO ESTÁ en este momento (ya incluye cambios de Backend ajenos a este ciclo, un fast-follow
-- de E15 sin relación con HU-31) — puede correrse más si Backend sigue tocando este archivo:
--   1) `actualizarNegocioSchema` (línea ~67-71) — sumar `horario_atencion`/`direccion`/`telefono`
--      con `z.string().nullable()` (mismo patrón que `rubro`/`ubicacion`, NO `.optional()` — hace
--      falta poder mandar `null` explícito para vaciar un campo ya cargado) y `logo_url` con una
--      validación de formato URL (ver más arriba).
--   2) Body destructuring + UPDATE (línea ~643 y ~645-656) — sumar las 4 columnas nuevas al
--      `UPDATE negocio SET ...` y a su `RETURNING`, mismo patrón que `nombre`/`rubro`/`ubicacion`
--      ya tienen hoy.
--   3) `GET /negocios` y `GET /negocios/:id` (línea ~116 y ~134) — considerar sumar las 4 columnas
--      al `SELECT`, al menos en `GET /:id` (perfil completo de un negocio puntual, que es
--      exactamente donde HU-31 pide que "el cliente vea información completa... al elegir mi
--      negocio"); si conviene exponerlas también en el listado `GET /` es una decisión de
--      UX/producto, no cerrada acá.
--   4) NO extender `POST /auth/registro-negocio` (`src/routes/auth.ts`) ni `POST /dev/seed`
--      (`src/routes/dev.ts`) con estos 4 campos — HU-31 los define explícitamente como datos que
--      se completan "más allá del alta inicial", no en el registro; el alta de negocio sigue
--      pidiendo únicamente nombre/rubro/ubicacion, sin cambios.
--   5) Mobile (`configuracion_consultorio_screen.dart`) — sumar 4 `TextEditingController` nuevos
--      siguiendo el mismo patrón que `_ubicacionCtrl`, y considerar previsualizar `logo_url` con
--      `Image.network` en vez de mostrar solo el campo de texto crudo.
CREATE TABLE negocio (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre            TEXT NOT NULL,
  rubro             TEXT,
  es_rubro_salud    BOOLEAN NOT NULL DEFAULT false,
  ubicacion         TEXT,
  horario_atencion  TEXT,
  direccion         TEXT,
  telefono          TEXT,
  logo_url          TEXT,
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

-- ============================================================================
-- Bandeja de notificaciones — destinatario + leído (HU-14b/HU-25/HU-26, 2026-08-12, DBA)
-- ============================================================================
-- Hasta este ciclo `notificacion` era, en la práctica, un LOG interno ("se generó un aviso de
-- tipo X para este turno": turno_id, tipo, enviado_en, creado_en) — sin ninguna columna que
-- dijera A QUIÉN había que notificar, ni si ya lo vio. Alcanzaba para que Backend registrara que
-- planeaba avisar (D4), pero no para una bandeja consultable por usuario (mapa-pantallas.md
-- §5.15, tab "Notificaciones", HU-14b/HU-25) ni para "marcar como leída".
--
-- Investigado contra el código real (backend/src/routes/turnos.ts, backend/src/jobs/,
-- backend/src/integraciones/notificaciones.ts) antes de modelar, no asumido:
-- - Solo 2 call sites insertan acá HOY, los dos literal `tipo = 'confirmacion'`: POST /turnos (al
--   reservar) y PATCH /:id/reprogramar (para el turno nuevo). PATCH /:id/cancelar NO inserta
--   ninguna fila — gap real de Backend, no solo de modelado (ver recomendación más abajo).
-- - No existe ningún job de recordatorio: `src/jobs/expirarPagosPendientes.ts` es el ÚNICO
--   archivo en `src/jobs/` y expira pagos vencidos (turno/pago), no envía avisos. El
--   `tipo = 'recordatorio'` que ya anticipaba el comentario original de esta columna — y la
--   propia interfaz `NotificacionProvider.enviar(destinatarioUsuarioId, tipo, mensaje)` de
--   `integraciones/notificaciones.ts`, que YA tiene un parámetro de destinatario pero nunca se
--   invoca desde ningún endpoint — sigue sin ningún productor real.
-- - ¿Para quién son las filas `confirmacion` que sí se insertan hoy? El wireframe resuelve la
--   ambigüedad: los 3 ejemplos de la bandeja (mapa-pantallas.md §5.15) — "María Pérez confirmó su
--   turno de las 10:00", "Recordatorio: turno con Juan Ramírez en 1 hora", "Sofía Cano canceló su
--   turno de las 16:00" — están redactados en 3ra persona sobre la acción del CLIENTE: es la
--   bandeja del PROFESIONAL. HU-26 (§5.14) lista "nueva reserva" como sub-ítem "[solo
--   Profesional]" de "Citas y recordatorios", distinto de "confirmación" (que HU-14 describe del
--   lado del cliente). Conclusión aplicada acá: las filas `confirmacion` que ya insertan
--   POST /turnos y PATCH /reprogramar SON, hoy, el aviso de "nueva reserva"/"turno reprogramado"
--   PARA EL PROFESIONAL de ese turno — se backfillean así en `004_notificaciones.sql`
--   (`turno.profesional_id -> profesional.usuario_id`). No se renombra el label `'confirmacion'`
--   del ENUM nuevo (ver abajo) precisamente para no romper esos 2 call sites, que quedan sin
--   tocar en este ciclo (fuera de alcance de DBA).
--
-- `destinatario_usuario_id` — lo único que faltaba para que esto sea una bandeja real y no un
-- log: a quién notifica. NULLABLE, no NOT NULL — mismo motivo exacto que `usuario.telefono`/
-- `usuario.google_id` (ver esa tabla, más arriba): los 2 call sites que YA insertan en esta
-- tabla (POST /turnos, PATCH /:id/reprogramar) siguen sin tocarse en este ciclo (fuera de alcance
-- de DBA) y NO van a pasar esta columna en su INSERT — si fuera NOT NULL sin default, esos 2
-- INSERT, hoy funcionando, empezarían a fallar (23502, not-null violation) apenas corra esta
-- migración, en CUALQUIER ambiente (no solo Render: también un docker-compose/CI recién creado
-- que corre `001_init.sql` de punta a punta). Postgres no permite un `DEFAULT` que derive el
-- valor de OTRA columna del mismo INSERT (acá haría falta resolver `turno_id -> profesional.
-- usuario_id`), así que un `DEFAULT` constante no es una opción — se evaluó también un trigger
-- `BEFORE INSERT` que auto-completara `destinatario_usuario_id` cuando venga NULL, y se descarta
-- por ahora: sería el primer trigger de todo este esquema, y este proyecto viene resolviendo
-- sistemáticamente este tipo de derivación en la capa de aplicación, no con lógica implícita en
-- la base de datos (mismo criterio que el fallback de `duracion_cita_min`, §2quater, o el gate de
-- `es_rubro_salud`, más abajo) — se prefiere consistencia con ese criterio antes que resolver un
-- caso puntual con una herramienta nueva. La policy de INSERT (ver sección RLS) acepta
-- explícitamente `destinatario_usuario_id IS NULL` para no romper esos 2 call sites; el SELECT de
-- la bandeja (`destinatario_usuario_id = app.usuario_id`) nunca muestra una fila con esa columna
-- en NULL a nadie (`NULL = x` nunca es `true`) — fail-closed, no un dato mal mostrado. Seguimiento
-- recomendado para un ciclo futuro (no implementado acá): una vez que Backend agregue esta columna
-- a esos 2 INSERT y al nuevo de PATCH /:id/cancelar (ver recomendación más abajo), y confirmado
-- que no queden filas NULL, agregar `ALTER TABLE notificacion ALTER COLUMN
-- destinatario_usuario_id SET NOT NULL` en una migración incremental nueva.
--
-- `leido` — booleano simple, sin un `leido_en` dedicado: es el ÚNICO atributo mutable de esta
-- fila aparte de su creación, así que el `modificado_en` genérico agregado acá (mismo criterio
-- que `usuario`/`negocio`/`profesional`/`servicio`/`turno`/`pago`/`paciente`/`tratamiento`/
-- `nota_medica`, todos con `modificado_en` en vez de un timestamp dedicado por columna) ya
-- captura "cuándo se marcó" sin necesitar una columna extra para ese único caso.
--
-- Deliberadamente NO se guarda texto/nombre/hora "congelados" en la fila (ej. un `mensaje` con
-- "María Pérez confirmó su turno de las 10:00" ya armado) — mismo criterio de "no duplicar una
-- única fuente de verdad" que ya aplica este archivo a `tratamiento`/`nota_medica` (no repiten
-- `negocio_id`/`profesional_id` de `paciente`, ver esa sección). Todo lo que necesita el texto de
-- la bandeja (nombre del cliente, hora del turno) ya es derivable sin ambigüedad vía `turno_id`
-- — `turno` nunca se borra físicamente (solo cambia `estado`), la referencia queda válida para
-- siempre. El string final lo arma el Backend (ver recomendación de queries más abajo), no la
-- base de datos — mismo principio que el fallback de `duracion_cita_min` (§2quater) o el gate de
-- `es_rubro_salud` (más arriba): a nivel de aplicación, no de constraint.
--
-- `tipo` pasa de `TEXT` libre a ENUM (`tipo_notificacion`, declarado justo abajo): a diferencia
-- de `genero`/`contacto_emergencia_relacion` (TEXT a propósito, contenido de UI que no controla
-- lógica), acá sí hay lógica real que depende del valor exacto — qué plantilla de texto arma el
-- Backend, y a futuro qué toggle de HU-26 lo gatea — mismo criterio que `rol_usuario`/
-- `estado_turno`/`estado_pago`. Se agregan `'cancelacion'` y `'reprogramacion'` (nuevos, ningún
-- código los usa todavía) junto a `'confirmacion'`/`'recordatorio'` (ya existían como convención
-- informal, solo un comentario TEXT hasta este ciclo).
--
-- Recomendación para Backend (no implementada acá, fuera de alcance de DBA) — 3 INSERT que faltan
-- para que la bandeja tenga contenido real, uno por evento:
-- 1) PATCH /:id/cancelar (turnos.ts) — agregar, dentro de la misma transacción que hace el
--    UPDATE turno SET estado = 'cancelado', un INSERT INTO notificacion con
--    tipo = 'cancelacion' y destinatario_usuario_id = el usuario_id del profesional del turno
--    (mismo JOIN turno -> profesional que ya resuelve `paciente` en POST /turnos).
-- 2) PATCH /:id/reprogramar (turnos.ts) — el INSERT que ya existe (tipo='confirmacion', sin
--    destinatario) pasa a necesitar destinatario_usuario_id (mismo JOIN); evaluar además si
--    conviene tipo='reprogramacion' en vez de 'confirmacion' para que el texto no confunda una
--    reprogramación con una reserva nueva (label ya disponible en el ENUM, decisión de Backend).
-- 3) Job de recordatorio NUEVO (no existe archivo todavía) — recorrer turnos con
--    estado IN ('pendiente_de_pago','confirmado') cuyo `inicio` cae dentro de la ventana de aviso
--    (ej. ~1h, wireframe "Recordatorio: turno con Juan Ramírez en 1 hora") e insertar
--    tipo='recordatorio' para el profesional; correr con `withTransaction(fn, { jobSistema: true
--    })` (mismo patrón que expirarPagosPendientes.ts) — la policy
--    `notificacion_insert_job_sistema` (ver sección RLS) ya está lista para ese caso. Necesita
--    además una guarda anti-duplicados (ej. una columna o un SELECT previo que evite mandar el
--    mismo recordatorio en cada corrida del intervalo) — no resuelta acá, es lógica de Backend.
-- POST /turnos (turno nuevo) también necesita el mismo destinatario_usuario_id agregado a su
-- INSERT ya existente (no es un evento nuevo, es la misma fila 'confirmacion' de siempre).
CREATE TYPE tipo_notificacion AS ENUM ('confirmacion', 'recordatorio', 'cancelacion', 'reprogramacion');

CREATE TABLE notificacion (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turno_id                 UUID NOT NULL REFERENCES turno(id),
  tipo                     tipo_notificacion NOT NULL,
  destinatario_usuario_id  UUID REFERENCES usuario(id),
  leido                    BOOLEAN NOT NULL DEFAULT false,
  enviado_en               TIMESTAMPTZ,
  creado_en                TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en            TIMESTAMPTZ
);
-- `idx_notificacion_turno`: sentido original de la tabla (log por turno), se mantiene.
-- `idx_notificacion_destinatario`: la query dominante de la bandeja — "mis notificaciones, más
-- nuevas primero" (WHERE destinatario_usuario_id = ? ORDER BY creado_en DESC) — `creado_en DESC`
-- ya en el índice para no pagar un sort aparte; el agrupado "Hoy"/"Ayer" de mapa-pantallas.md
-- §5.15 lo arma Backend/Mobile sobre ese mismo orden, no SQL.
-- `idx_notificacion_destinatario_no_leida`: parcial (WHERE leido = false), para el badge/contador
-- de no leídas sin escanear el historial completo — mismo patrón que `uq_turno_slot_activo`
-- (índice parcial filtrado por estado activo, documento-arquitectura.md §4).
CREATE INDEX idx_notificacion_turno ON notificacion (turno_id);
CREATE INDEX idx_notificacion_destinatario ON notificacion (destinatario_usuario_id, creado_en DESC);
CREATE INDEX idx_notificacion_destinatario_no_leida ON notificacion (destinatario_usuario_id) WHERE leido = false;

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
-- Preferencias de notificación (HU-26, 2026-08-12, DBA)
-- ============================================================================
-- Compartida Cliente/Profesional, mismo patrón que "Preferencias de privacidad de usuario"
-- (HU-32, ciclo paralelo en `feature/configuracion-profesional`, todavía no mergeado a `main` al
-- momento de este commit — ver motivo 2 más abajo). mapa-pantallas.md §5.14, 3 secciones: Canal
-- (push/email/whatsapp), Tipo de aviso (citas y recordatorios / promociones y ofertas —
-- "Mensajes" y "Reseñas y Calificaciones" quedan OCULTOS por decisión ya tomada de UX/UI, no se
-- modelan acá) y Sonido y vibración. "Este es el único lugar de la app donde se activan/
-- desactivan tipos de aviso y canales" (§5.14) — un solo toggle "Citas y recordatorios" cubre
-- confirmación/recordatorio/cancelación/reprogramación/nueva-reserva a la vez, no 5 toggles
-- separados: el wireframe no expone más granularidad que esa — modelar 5 columnas hubiera sido
-- diseñar por encima de lo que pide la UI real.
--
-- Decisión de diseño (la pregunta central de este ciclo): ¿tabla nueva, o columnas nuevas en
-- `usuario_preferencias` (la tabla de Privacidad, HU-32)? Elegida TABLA NUEVA, por 2 motivos
-- independientes — ninguno alcanza solo:
-- 1) (lógico) `usuario_preferencias` ya tiene nombre genérico ("preferencias", no
--    "preferencias_privacidad"), lo que en principio invita a extenderla — pero Configuración
--    (ver historial de commits: Perfil/Privacidad/Consultorio/Pagos/Reportes, y ahora
--    Notificaciones) va camino a sumar más pantallas de ajustes de usuario. Agregar cada familia
--    de toggles a una única tabla "cajón de sastre" degrada con el tiempo — visibilidad de perfil
--    y canales de notificación no tienen ninguna relación funcional entre sí más que "son de
--    configuración". Se traza acá el límite: `usuario_preferencias*` sirve para preferencias
--    PLANAS (booleanos/enums escalares, sin sub-estructura ni historial propio) — el día que una
--    pantalla de Configuración necesite algo con estado/historial propio (ej. WhatsApp,
--    mapa-pantallas.md §5.16: estado de conexión + log de mensajes enviados, no un simple on/off)
--    eso ya no calificaría para vivir acá y necesitaría su propia tabla, igual que esta.
-- 2) (operativo — el que decide en la práctica) `usuario_preferencias` NO EXISTE en esta rama
--    (`feature/notificaciones`, parada sobre `main`): la creó DBA en
--    `feature/configuracion-profesional` (HU-32, commit 7a106e8), rama todavía no mergeada a
--    `main`. Depender de ella acá (`ALTER TABLE usuario_preferencias ADD COLUMN ...`) hubiera
--    acoplado esta migración al orden y al éxito de un merge ajeno todavía en curso — riesgo
--    operativo real, no hipotético, para una migración que además tiene que poder aplicarse a
--    mano contra Render (ver `004_notificaciones.sql`). Una tabla propia, sin ninguna referencia
--    a `usuario_preferencias`, es 100% autocontenida: se prueba/migra en esta rama sin importar
--    en qué orden termine mergeándose respecto a HU-32.
-- Nombre `usuario_preferencias_notificacion` (no `notificacion_preferencias`): comparte a
-- propósito el prefijo exacto de `usuario_preferencias` — dos tablas hermanas de la misma familia
-- conceptual ("las preferencias de este usuario"), separadas por los 2 motivos de arriba, no dos
-- conceptos sin relación. Cuando se mergeen ambas ramas, si conviene consolidarlas en una sola
-- tabla queda a criterio de un ciclo futuro (Director General IA/DBA) — no se decide acá, no hace
-- falta para que ninguna de las dos funcione por separado.
--
-- Columnas — 1 booleano por control del wireframe, ya son atómicos, sin agrupar:
--   Canal:             notif_canal_push / notif_canal_email / notif_canal_whatsapp (default
--                       true — el wireframe muestra los 3 activados por defecto).
--   Tipo de aviso:      notif_citas_recordatorios (default true), notif_promociones (default
--                       false — "Promociones y Ofertas" aparece apagado por defecto).
--   Sonido y vibración: notif_sonido, notif_vibracion (default true).
-- Prefijo `notif_` en las 7 (a diferencia de las columnas de `usuario_preferencias`, que no
-- llevan prefijo `privacidad_`): acá sí se justifica — convención barata que compensa que esta
-- tabla puede terminar conviviendo, tras el merge, con otras familias de preferencias en el mismo
-- espacio de nombres visual (`\d usuario_preferencias*`).
--
-- Sin `creado_por`/`modificado_por` (mismo motivo que `usuario_preferencias`, HU-32): la fila es
-- propiedad exclusiva de `usuario_id`, y RLS (ver más abajo) ya solo permite que ese mismo usuario
-- la escriba — `modificado_por` sería 100% redundante con `usuario_id` bajo esa policy. Sin
-- `eliminado_en` (mismo motivo): un ajuste de preferencias no se "da de baja" — existe con sus
-- valores actuales, o todavía no se creó la fila (ver recomendación de Backend abajo).
--
-- Recomendación para Backend (no implementada acá, fuera de alcance de DBA): ninguna fila se crea
-- automáticamente al registrarse un usuario — igual que `usuario_preferencias` de HU-32, el
-- endpoint de lectura (`GET /config/notificaciones` o el que se defina) debe devolver estos
-- defaults cuando no exista fila todavía, o hacer un `INSERT ... ON CONFLICT (usuario_id) DO
-- NOTHING` perezoso antes de leer — el UNIQUE de abajo ya lo permite sin duplicar filas.
CREATE TABLE usuario_preferencias_notificacion (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id                  UUID NOT NULL UNIQUE REFERENCES usuario(id),
  notif_canal_push            BOOLEAN NOT NULL DEFAULT true,
  notif_canal_email           BOOLEAN NOT NULL DEFAULT true,
  notif_canal_whatsapp        BOOLEAN NOT NULL DEFAULT true,
  notif_citas_recordatorios   BOOLEAN NOT NULL DEFAULT true,
  notif_promociones           BOOLEAN NOT NULL DEFAULT false,
  notif_sonido                BOOLEAN NOT NULL DEFAULT true,
  notif_vibracion             BOOLEAN NOT NULL DEFAULT true,
  creado_en                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  modificado_en               TIMESTAMPTZ
);

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
-- profesional del mismo negocio pasan ESTA policy — sigue siendo así a propósito, incluso después
-- del cambio de 2026-08-15 más abajo (bloque "Acceso de administrador al historial de pacientes",
-- ubicado después de la policy de `nota_medica`, al cierre de esta misma sección): esta policy (y
-- sus análogas `tratamiento_acceso_via_paciente`/`nota_medica_acceso_via_paciente`) sigue siendo,
-- SIN NINGÚN CAMBIO, la ÚNICA fuente de autorización de ESCRITURA (INSERT/UPDATE/DELETE) sobre
-- estas 3 tablas — el administrador NUNCA pasa a poder escribir acá; ver ese bloque para el
-- razonamiento completo de por qué. Esto coincidía, hasta esa fecha, con el default documentado
-- en documento-funcional.md §6, ítem 2 ("Alcance de permisos del administrador... A7/D3 dejan al
-- administrador sin acceso al historial por defecto — confirmar si es correcto"), pregunta que
-- ese documento dejaba como menor y todavía abierta — el CEO la resolvió confirmando que el
-- administrador SÍ debe tener acceso (de SOLO LECTURA, ver bloque de abajo, no de escritura).
-- Pendiente que Business Analyst/Product Manager actualicen formalmente D3/RN7/§6
-- (documento-funcional.md) y la pregunta abierta análoga de la épica E15 (02-backlog/backlog.md)
-- con este resultado — fuera del alcance de DBA, que modela el dato y no reescribe esos
-- documentos.
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
-- Acceso de administrador al historial de pacientes — SOLO LECTURA (fast-follow de E15, DBA,
-- 2026-08-15)
-- ============================================================================
-- El CEO confirmó (sesión 2026-08-15 — ver memory/proyectos/turnos-profesionales/decisiones.md,
-- entrada "E15 'Modo Administrador v1'") la pregunta que documento-funcional.md §6, ítem 2, dejaba
-- abierta desde la Fase 2 ("Alcance de permisos del administrador del negocio sobre el historial
-- de clientes... A7/D3 dejan al administrador sin acceso por defecto — confirmar si es
-- correcto"), y que 02-backlog/backlog.md (épica E15) había registrado con una propuesta de
-- Product Manager de MANTENER el default sin acceso: el CEO pidió expresamente "acceso completo"
-- — rechazando esa propuesta conservadora — y, al no existir todavía backend para eso, aceptó la
-- recomendación de tratarlo como este fast-follow separado (DBA primero, sobre este mismo diseño;
-- Backend/Mobile en una ronda posterior). Pendiente que Business Analyst/Product Manager
-- actualicen formalmente documento-funcional.md (D3/RN7/§6) y backlog.md (E15) con esta
-- resolución — fuera del alcance de DBA, no se tocan esos 2 documentos acá.
--
-- ALCANCE DECIDIDO ACÁ — SOLO LECTURA (SELECT), no escritura — evaluado explícitamente por DBA,
-- no asumido, contra el criterio de "no otorgar más permiso del que se pidió":
-- 1) Lo pedido textualmente es "acceso completo AL HISTORIAL" — un historial se CONSULTA; nada en
--    el pedido del CEO, ni en HU-20/HU-21/RN7/RN13/D3, ni en ninguna otra HU/backlog de este
--    proyecto, menciona que el administrador deba poder EDITAR o BORRAR una ficha, un tratamiento
--    o una nota médica ajena. "Completo" se lee acá como "el historial ENTERO (ficha +
--    tratamientos + notas, no un subconjunto recortado)", no como "con permiso de escritura
--    incluido" — es la lectura más consistente con qué fue lo que el CEO rechazó (el default de
--    CERO acceso que proponía Product Manager), no con pedir un permiso más amplio y distinto.
-- 2) RN7/RN13/D3 (documento-funcional.md §3) siguen íntegramente vigentes para la ESCRITURA: la
--    ficha/tratamiento/nota médica es un registro de autoría clínica de QUIEN atendió — con
--    implicancia médico-legal, no solo de producto (mismo espíritu que la nota de seguridad de
--    HU-20/HU-33 sobre datos de salud, backlog.md). Dar a un actor no-clínico (el administrador)
--    la capacidad de modificar o eliminar el registro clínico de OTRO profesional es un salto de
--    alcance cualitativamente distinto a poder verlo — nadie lo pidió, y concederlo igual sería
--    diseñar por encima de la instrucción real.
-- 3) Principio de mínimo privilegio ya aplicado en este mismo archivo ante instrucciones
--    ambiguas entre 2 lecturas posibles (ver, ej., `es_rubro_salud DEFAULT false`, o el alcance
--    deliberadamente angosto de `notificacion_insert_evento_turno`): implementar la lectura más
--    angosta que satisface el pedido explícito, dejando la más amplia como extensión futura
--    documentada si se llega a pedir — nunca al revés.
-- 4) Costo asimétrico de equivocarse: si el CEO pide después, explícitamente, que el
--    administrador también edite, es una policy nueva y aditiva (mismo patrón que este bloque).
--    Lo inverso — haber otorgado escritura de más y tener que retirarla — es operativamente más
--    caro (hay que auditar si ya se usó para modificar/borrar un registro clínico ajeno) y expone
--    datos de salud sensibles (D11/RN15) a un riesgo que nadie pidió asumir.
--
-- DISEÑO — 3 policies NUEVAS, `FOR SELECT` únicamente, una por tabla. NINGUNA de las 3 policies
-- `FOR ALL` de arriba (`paciente_acceso_propio_profesional`/`tratamiento_acceso_via_paciente`/
-- `nota_medica_acceso_via_paciente`) se modifica ni se separa en policies más chicas. Se evaluó
-- explícitamente separar cada `FOR ALL` en `FOR SELECT` + policies de escritura — tal como
-- sugería el comentario original de este bloque en ciclos anteriores ("agregar una policy
-- adicional... mismo patrón que turno") — y se descarta por INNECESARIO, no por sobre-diseño:
-- Postgres evalúa, para cada comando, TODAS las policies permisivas (`PERMISSIVE`, el default —
-- ninguna policy de este archivo usa `AS RESTRICTIVE`) que aplican a ese comando, y las combina
-- con OR. Una policy `FOR ALL` aplica a los 4 comandos (SELECT/INSERT/UPDATE/DELETE); una policy
-- `FOR SELECT` nueva aplica SOLO a SELECT. Agregar la `FOR SELECT` nueva ya amplía el SELECT (se
-- evalúa en OR junto al `USING` de la `FOR ALL` existente) SIN tocar INSERT/UPDATE/DELETE, que
-- siguen dependiendo EXCLUSIVAMENTE del `USING`/`WITH CHECK` de la `FOR ALL` original, sin
-- cambios — el mismo resultado final que "separar" la policy vieja, con MENOR superficie de
-- cambio (0 líneas tocadas de las 3 policies ya aprobadas) y por lo tanto menor riesgo de
-- regresión sobre algo que ya funciona en producción (Render).
--
-- Verificado además contra el código real de Backend antes de decidir que este agregado es
-- inofensivo (no asumido): `../../backend/src/routes/profesionales.ts` — `GET`/`PATCH`
-- `/:id/pacientes/:pacienteId` y `GET /:id/pacientes/:pacienteId/historial` — es HOY el único
-- lugar que lee o escribe estas 3 tablas, y las 3 rutas exigen `requireAuth('profesional')` +
-- `esPropioProfesional(req)` ("Solo podés ver/editar tus propios pacientes", 403 si no) ANTES de
-- tocar la base, y llaman a `withTransaction(fn, { usuarioId: req.auth!.sub, ... })` — es decir,
-- `app.usuario_id` en el contexto RLS de esas transacciones SIEMPRE es el propio profesional
-- dueño de la fila, nunca un administrador. Ningún código hoy depende de que estas 3 tablas
-- tengan una única policy `FOR ALL`, así que sumar policies de `SELECT` en paralelo no cambia el
-- comportamiento de ninguna ruta existente. Backend todavía NO tiene ningún endpoint que lea
-- estas tablas en contexto de administrador — esta migración deja lista la autorización a nivel
-- de base de datos para cuando la ronda de Backend de este mismo fast-follow agregue ese
-- endpoint (fuera del alcance de DBA, instrucción explícita de no tocar Backend/Mobile en este
-- ciclo).
--
-- `negocio_id` para el chequeo: `paciente.negocio_id` ya existe en la fila (a diferencia de
-- `suscripcion_negocio`/HU-29, que necesitó `app.negocio_id` de sesión por no tener FK directa a
-- una identidad — ver bloque "Suscripción 'Turnario Pro'", más abajo) — no hace falta ninguna
-- variable de sesión nueva. `tratamiento`/`nota_medica` lo resuelven vía `JOIN` a `paciente`,
-- mismo patrón ya usado por `tratamiento_acceso_via_paciente`/`nota_medica_acceso_via_paciente`
-- (arriba) para resolver "quién es el profesional dueño" sin duplicar la columna.
CREATE POLICY paciente_select_admin_del_negocio ON paciente
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = paciente.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

CREATE POLICY tratamiento_select_admin_del_negocio ON tratamiento
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM paciente pa
      JOIN negocio_administrador na ON na.negocio_id = pa.negocio_id
      WHERE pa.id = tratamiento.paciente_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

CREATE POLICY nota_medica_select_admin_del_negocio ON nota_medica
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM paciente pa
      JOIN negocio_administrador na ON na.negocio_id = pa.negocio_id
      WHERE pa.id = nota_medica.paciente_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

-- ============================================================================
-- RLS de la bandeja de notificaciones + preferencias de notificación (HU-14b/HU-25/HU-26,
-- 2026-08-12, DBA)
-- ============================================================================
-- FORCE desde el primer commit para la tabla nueva (`usuario_preferencias_notificacion`) y, **por
-- primera vez, también para `notificacion`**: existe desde la Fase 3 original sin ninguna policy
-- — el gap de ownership de §5bis le aplicaba igual que a cualquier tabla sin FORCE, pero nadie lo
-- había cerrado porque hasta este ciclo la tabla no tenía ninguna noción de "de quién es cada
-- fila" (sin `destinatario_usuario_id` no había nada que proteger con RLS). Este bloque cierra
-- además el "pendiente para una próxima iteración" que ya dejaba documentado la sección 5 de
-- 03-arquitectura/modelo-datos.md sobre `notificacion` (sin `negocio_id` propio, necesitaría una
-- política basada en subquery) — exactamente lo que se implementa acá.
--
-- `notificacion` — 3 policies, ninguna cubre todos los comandos (a diferencia de
-- `usuario_preferencias_notificacion`, que sí tiene una única policy simétrica, más abajo):
-- 1) SELECT/UPDATE ("ver mi bandeja"/"marcar como leída") — estrictamente acotado al propio
--    destinatario (destinatario_usuario_id = app.usuario_id), sin excepción para staff del
--    negocio ni para quien originó el evento — la bandeja es personal (mapa-pantallas.md §5.15).
--    El WITH CHECK del UPDATE es simétrico al USING a propósito: impide que la fila cambie de
--    dueño vía un UPDATE que conserve el resto de las columnas — mismo patrón que
--    `usuario_preferencias_acceso_propio` (HU-32) y `turno_acceso_negocio_o_cliente`.
-- 2) INSERT ("generar un aviso") — necesariamente MÁS ancha que 1), y a propósito: verificado
--    contra el código real de POST /turnos (turnos.ts) que el actor que ejecuta el INSERT casi
--    nunca es el propio destinatario. Ejemplo concreto: un cliente reserva → el contexto RLS de
--    esa transacción es `app.usuario_id = <cliente>` (todo el handler corre con
--    `requireAuth('cliente')`) → pero el destinatario de la notificación es el PROFESIONAL de ese
--    turno. Una policy de INSERT acotada como la de 1) HABRÍA ROTO ese INSERT, ya existente y
--    funcionando, en cuanto RLS tuviera efecto real — exactamente la regresión que este ciclo
--    tiene que evitar (no se toca código de Backend, la policy tiene que acomodar el código TAL
--    COMO ESTÁ). En vez de replicar acá el truco que sí usa POST /turnos para `paciente` (un
--    `SELECT set_config('app.usuario_id', <otro usuario>, true)` a mitad de transacción, ver ese
--    archivo), la policy verifica que TANTO el actor COMO el destinatario sean participantes del
--    MISMO turno (`turno_id`): el actor con el mismo criterio ancho que ya usa
--    `turno_acceso_negocio_o_cliente` (el cliente dueño, o cualquier staff del negocio), el
--    destinatario con un criterio más angosto a propósito (el cliente dueño, o específicamente el
--    profesional ASIGNADO a ese turno — no cualquier staff), para que nadie pueda insertar una
--    notificación dirigida a un tercero ajeno al turno referenciado. Acepta además
--    `destinatario_usuario_id IS NULL` explícitamente — necesario para que los 2 call sites que
--    hoy insertan sin esa columna (POST /turnos, PATCH /:id/reprogramar, sin tocar en este ciclo)
--    sigan funcionando exactamente igual que antes de esta migración (ver comentario junto a
--    `destinatario_usuario_id` en `CREATE TABLE notificacion`, más arriba) — no relaja nada para
--    una fila que SÍ trae destinatario, esas siguen validándose completas.
-- 3) INSERT adicional para el futuro job de recordatorio (app.job_sistema = 'true') — mismo
--    criterio que `turno_acceso_job_expiracion`: un job que recorre turnos de CUALQUIER
--    cliente/negocio en un solo barrido no actúa "como" ningún usuario puntual, 2) no lo cubre.
--    Sin scope adicional sobre qué turno/destinatario, mismo criterio que
--    `turno_acceso_job_expiracion` — se confía en la lógica interna del job (privilegios de
--    sistema, no de request HTTP). Ese job todavía no existe (ver recomendación junto a
--    `CREATE TABLE notificacion` más arriba); policy dejada lista para cuando Backend lo
--    implemente, mismo criterio que las funciones `SECURITY DEFINER` de más abajo (preparadas
--    antes de que el código las use).
-- No hay policy de DELETE — mismo motivo que `negocio_administrador`: ningún endpoint/HU de este
-- ciclo borra notificaciones (mapa-pantallas.md §5.15 no muestra ninguna acción de descarte);
-- queda como extensión futura documentada, no implementada.
ALTER TABLE notificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE notificacion FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo

CREATE POLICY notificacion_select_propia ON notificacion
  FOR SELECT USING (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);

CREATE POLICY notificacion_update_propia_marcar_leida ON notificacion
  FOR UPDATE
  USING (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
  WITH CHECK (destinatario_usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);

CREATE POLICY notificacion_insert_evento_turno ON notificacion
  FOR INSERT WITH CHECK (
    -- El actor participa del turno referenciado (mismo criterio que turno_acceso_negocio_o_cliente).
    EXISTS (
      SELECT 1 FROM turno t
      WHERE t.id = notificacion.turno_id
        AND (
          t.cliente_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
          OR EXISTS (
            SELECT 1 FROM negocio_administrador na
            WHERE na.negocio_id = t.negocio_id
              AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
          )
          OR EXISTS (
            SELECT 1 FROM negocio_profesional np
            JOIN profesional p ON p.id = np.profesional_id
            WHERE np.negocio_id = t.negocio_id
              AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
          )
        )
    )
    -- El destinatario es el cliente dueño o el profesional ASIGNADO a ese turno — más angosto a
    -- propósito que el chequeo de arriba, ver comentario de esta sección. `IS NULL` explícito:
    -- compat con los 2 call sites que hoy insertan sin destinatario (ver arriba).
    AND (
      notificacion.destinatario_usuario_id IS NULL
      OR EXISTS (
        SELECT 1 FROM turno t
        JOIN profesional p ON p.id = t.profesional_id
        WHERE t.id = notificacion.turno_id
          AND (t.cliente_id = notificacion.destinatario_usuario_id OR p.usuario_id = notificacion.destinatario_usuario_id)
      )
    )
  );

CREATE POLICY notificacion_insert_job_sistema ON notificacion
  FOR INSERT WITH CHECK (
    current_setting('app.job_sistema', true) = 'true'
  );

-- `usuario_preferencias_notificacion` — policy única simétrica, mismo patrón exacto que
-- `usuario_preferencias_acceso_propio` (HU-32): sin JOIN, cada usuario lee/edita únicamente su
-- propia fila.
ALTER TABLE usuario_preferencias_notificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuario_preferencias_notificacion FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo

CREATE POLICY usuario_preferencias_notificacion_acceso_propio ON usuario_preferencias_notificacion
  USING (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid)
  WITH CHECK (usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid);

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

-- ============================================================================
-- Suscripción "Turnario Pro" (HU-29/E11, 2026-08-14, DBA)
-- ============================================================================
-- Origen: HU-29 (E11, 02-backlog/backlog.md) — freemium POR NEGOCIO, no por profesional
-- individual: el plan gratis limita 1 profesional por negocio y 60 turnos confirmados/mes por
-- negocio (ninguno de los dos necesita columnas nuevas — ambos son consultas sobre tablas ya
-- existentes, ver el índice nuevo al final de este bloque para el segundo). "Turnario Pro"
-- levanta esos límites y desbloquea Reportes (HU-28, ya construido), WhatsApp (HU-24, todavía
-- no), plantillas de horario recurrente (HU-17, ya construido) e import/export de pacientes
-- (HU-22, todavía no) — esos desbloqueos de OTRAS features son responsabilidad de Backend en cada
-- endpoint (chequear el plan de ese negocio), no de este modelado. Precio confirmado por el CEO
-- (backlog.md, esta ronda): USD 9/mes por negocio, 20% off pagando anual (USD 86.40/año, ya
-- calculado por DevOps en `08-despliegue/google-play-billing.md` §5). Plataforma v1: SOLO
-- Android, cobrado vía Google Play Billing — pero esa integración real todavía no existe (necesita
-- que el CEO cree una cuenta de Google Play Developer, USD 25 + verificación de identidad, ver ese
-- mismo documento §1/§2) — este ciclo modela el soporte de datos para una ACTIVACIÓN SIMULADA
-- (mismo criterio que ya usa Mercado Pago, `MockPagoProvider` en
-- `backend/src/integraciones/pagos.ts`), no una verificación real de compra. Comportamiento al
-- llegar al límite del plan gratis, confirmado por el CEO en esta misma ronda: BLOQUEAR nuevas
-- reservas/turnos ese mes (no solo avisar) — lo aplica Backend en el endpoint de reserva, no la
-- base de datos (ver recomendación al final de este bloque).
--
-- DECISIÓN DE DISEÑO — ¿columna `negocio.plan` sola, o tabla `suscripcion_negocio` separada?
-- Evaluadas ambas antes de decidir, mismo criterio que ya usó este archivo para
-- `usuario_preferencias`/`paciente` (ver esos bloques, más arriba): la cardinalidad NO fuerza la
-- respuesta acá (1:1 con `negocio` bajo cualquiera de las dos), así que decide otro criterio.
-- Se descarta una columna `negocio.plan` sola porque el plan pago necesita, además, 3 atributos
-- que el plan gratis no tiene sentido de tener (`periodo`, `vencimiento`, `estado` de ESA
-- suscripción puntual) — una columna sola en `negocio` de todos modos habría necesitado sumar esas
-- mismas 3 columnas ahí (`plan_periodo`/`plan_vencimiento`/`plan_estado`), con el mismo resultado
-- práctico que una tabla propia, pero ensanchando `negocio` (identidad: nombre/rubro/ubicación) con
-- un concern de facturación ajeno — mismo razonamiento ya aplicado para separar
-- `usuario_preferencias` de `usuario` ("las preferencias son un concern independiente que ya se
-- sabe va a seguir creciendo", ver ese bloque). Se elige TABLA SEPARADA (`suscripcion_negocio`,
-- 1:1 con `negocio` vía `negocio_id UNIQUE`), mismo patrón estructural que
-- `profesional`/`pago`/`usuario_preferencias` en este archivo (GUID propio +
-- `<dueño>_id UNIQUE REFERENCES <dueño>(id)`, no `negocio_id` como PK directamente — nada
-- referencia hoy una fila de esta tabla por su propio id, pero mantiene la forma consistente con
-- el resto del esquema). Nombre `suscripcion_negocio` (no `negocio_suscripcion`): este esquema no
-- tiene una única regla para nombrar satélites 1:1 (`usuario_preferencias` antepone el dueño;
-- `pago`, satélite 1:1 de `turno`, no) — se mantiene el nombre ya anticipado en la consigna de
-- este ciclo, sin motivo de peso para apartarse.
--
-- Columnas `plan`/`periodo`/`estado` — 3 ENUM dedicados, mismo criterio que
-- `rol_usuario`/`estado_turno`/`estado_pago`/`visibilidad_perfil_usuario`: gobiernan lógica real
-- (qué límites aplica Backend, qué desbloquea), no son contenido descriptivo de UI. Minúscula sin
-- tilde, mismo estilo que el resto de los ENUM de este archivo.
-- - `plan_negocio` ('gratis' | 'turnario_pro') — 'turnario_pro' coincide literalmente con el ID de
--   producto de suscripción recomendado para Play Console (`turnario_pro`,
--   `08-despliegue/google-play-billing.md` §5) — mismo vocabulario en toda la cadena (backlog →
--   DevOps → DBA), no una coincidencia: cuando Backend mapee esta columna al `productId` real de
--   la Android Publisher API, no hace falta traducir entre 2 nombres para el mismo concepto.
-- - `periodo_suscripcion` ('mensual' | 'anual') — NULLABLE (ver CHECK más abajo): solo tiene
--   sentido cuando `plan = 'turnario_pro'`; el plan gratis no tiene periodicidad de facturación.
--   Coincide, otra vez a propósito, con los 2 "planes base" recomendados dentro del producto de
--   Play Console (`mensual`/`anual`, mismo documento §5) — Backend combina `plan`+`periodo` para
--   derivar el identificador compuesto `turnario_pro_mensual`/`turnario_pro_anual` que va a usar
--   contra Play Console el día que la verificación real exista; no se guarda ese string compuesto
--   como columna propia acá para no duplicar lo que ya expresan `plan`+`periodo` juntos (mismo
--   criterio anti-redundancia ya aplicado en este archivo, ej. al descartar una columna
--   `proveedor_auth` separada para `usuario.password_hash`/`google_id`, más arriba).
-- - `estado_suscripcion_negocio` ('activa' | 'vencida' | 'cancelada') — el estado de ESE período
--   pago puntual, independiente de si `plan` sigue diciendo 'turnario_pro': una vez que un negocio
--   se suscribe por primera vez, `plan` puede quedarse en 'turnario_pro' de forma permanente
--   (registro de "este negocio alguna vez pagó", útil para analítica futura) mientras `estado`
--   refleja el momento actual ('vencida' = pasó `vencimiento` sin renovarse; 'cancelada' = el
--   administrador pidió cancelar, pero puede seguir con acceso hasta que venza lo ya pagado —
--   patrón común de SaaS). Bajo ese criterio, el ACCESO EFECTIVO a las funciones Pro no es
--   `plan = 'turnario_pro'` solo — es `plan = 'turnario_pro' AND estado = 'activa' AND
--   vencimiento >= now()` (recomendación para Backend, no una regla de la base de datos: ningún
--   job de este ciclo recalcula `estado`/`plan` automáticamente al pasar `vencimiento` — mismo
--   criterio de "resolver en la capa de aplicación, no con lógica implícita en la base de datos"
--   ya aplicado sistemáticamente en este archivo, ej. el fallback de `duracion_cita_min` o el gate
--   de `es_rubro_salud`). Es una recomendación, no una obligación: si Backend prefiere resetear
--   `plan` a 'gratis' (+ `periodo`/`vencimiento` a NULL) al cancelar/vencer, el CHECK de abajo
--   sigue siendo válido para ese otro criterio también — decisión de Backend al implementar la
--   verificación real.
--
-- CHECK — `periodo`/`vencimiento` NULL si y solo si `plan = 'gratis'`, mismo patrón de invariante
-- cruzada entre columnas que `ck_usuario_password_o_google` (más arriba): a nivel de base de
-- datos, no solo de convención documentada, para que una fila inconsistente (ej. `plan = 'gratis'`
-- con un `vencimiento` seteado) sea imposible de insertar por error, no solo "no debería pasar".
--
-- Auditoría completa (`creado_por`/`modificado_por`, además de `creado_en`/`modificado_en`): a
-- diferencia de `usuario_preferencias`/`usuario_preferencias_notificacion` (las omiten porque el
-- único actor posible es siempre el propio dueño de la fila, dato 100% redundante — regla general
-- en `modelo-datos.md` §1), acá el "dueño" es `negocio_id`, pero `negocio_administrador` es N:M —
-- puede haber más de un administrador para el mismo negocio, así que QUIÉN activó/canceló Turnario
-- Pro no es deducible de `negocio_id` solo. Mismo criterio ya aplicado a
-- `negocio`/`paciente`/`tratamiento`/`nota_medica` (tablas donde quien escribe puede no coincidir
-- con un único dueño obvio), y particularmente apropiado acá por ser un dato de facturación, donde
-- "quién autorizó este cambio" es una pregunta de negocio legítima (auditoría/soporte/disputas).
-- Sin `eliminado_en` (soft delete): ninguna otra tabla referencia `suscripcion_negocio.id`, y el
-- ciclo de vida de esta fila es de ESTADO MUTABLE (activar/cancelar/vencer/reactivar in-place), no
-- de alta/baja — mismo motivo que `usuario_preferencias`.
--
-- Deliberadamente NO se modela en este ciclo (no es un olvido) — mismo criterio de "no
-- sobre-construir" ya aplicado en el resto de este esquema: ninguna columna para los datos de
-- verificación real de Google Play (`purchaseToken`/el resultado de la Android Publisher API). Hay
-- un precedente directo en este mismo archivo que en un primer momento parece sugerir lo
-- contrario — `pago.referencia_externa TEXT` (más arriba) es exactamente ese patrón, una columna
-- nullable agregada "por si hace falta después" para un dato externo de un proveedor que hoy solo
-- tiene un Mock — pero, verificado contra el código real (sin ninguna coincidencia en
-- `backend/src/`), ESA columna tampoco tiene ningún consumidor hoy, ni siquiera el propio
-- `MockPagoProvider` la escribe: ya es, en la práctica, el contraejemplo de "no sobre-construir"
-- que este ciclo prefiere no repetir una segunda vez. La activación simulada de este ciclo
-- (Backend, próxima ronda) no produce ningún `purchaseToken` real que guardar — un Mock que simula
-- "la compra funcionó" no tiene un dato externo genuino que persistir todavía. Cuando la
-- integración real exista (después de que el CEO complete `08-despliegue/google-play-billing.md`
-- §2/§6), agregar recién ahí una columna nueva (ej. `purchase_token TEXT`, nullable) en una
-- migración incremental futura — no antes.
-- Tampoco se modela el precio/monto de la suscripción (a diferencia de `pago.monto`, que sí
-- registra el importe real de cada pago de turno): USD 9/mes y USD 86.40/año son un dato de
-- CONFIGURACIÓN DE PRODUCTO (vive en Play Console y en `02-backlog/backlog.md` como referencia),
-- no un hecho transaccional por fila mientras la activación sea simulada y no exista ningún cobro
-- real que registrar — un campo de monto hoy derivaría 100% de `periodo` sin ningún consumidor que
-- lo necesite. Si el precio pudiera variar por negocio (descuentos, planes legacy) o hiciera falta
-- el importe real cobrado por Google, ese es el momento de agregarlo — no antes.
CREATE TYPE plan_negocio AS ENUM ('gratis', 'turnario_pro');
CREATE TYPE periodo_suscripcion AS ENUM ('mensual', 'anual');
CREATE TYPE estado_suscripcion_negocio AS ENUM ('activa', 'vencida', 'cancelada');

CREATE TABLE suscripcion_negocio (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  negocio_id      UUID NOT NULL UNIQUE REFERENCES negocio(id),
  plan            plan_negocio NOT NULL DEFAULT 'gratis',
  periodo         periodo_suscripcion,
  vencimiento     TIMESTAMPTZ,
  estado          estado_suscripcion_negocio NOT NULL DEFAULT 'activa',
  creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
  creado_por      UUID,
  modificado_en   TIMESTAMPTZ,
  modificado_por  UUID,
  CONSTRAINT ck_suscripcion_negocio_periodo_vencimiento_segun_plan CHECK (
    (plan = 'gratis' AND periodo IS NULL AND vencimiento IS NULL)
    OR (plan = 'turnario_pro' AND periodo IS NOT NULL AND vencimiento IS NOT NULL)
  )
);

-- Todo negocio EXISTENTE (creado antes de este ciclo) queda en plan 'gratis' automáticamente, sin
-- backfill manual: en este archivo (001_init.sql) es un no-op por construcción — una base nueva
-- todavía no tiene ninguna fila en `negocio` en el momento en que corre este DDL, mismo motivo por
-- el que 001_init.sql nunca backfillea nada (ver el header de `004_notificaciones.sql`). Contra un
-- ambiente YA migrado (Render, con negocios reales ya creados) el backfill equivalente SÍ hace
-- falta y vive en `005_suscripcion_negocio.sql` (`INSERT ... SELECT id FROM negocio ON CONFLICT DO
-- NOTHING`, confiando en los mismos DEFAULT de arriba) — no acá.
--
-- Recomendación para Backend (no implementada acá, fuera de alcance de DBA) — cuándo se crea la
-- fila para un negocio NUEVO (creado después de este ciclo): la forma más simple es agregar un 4to
-- INSERT a la misma transacción de `POST /auth/registro-negocio` (`backend/src/routes/auth.ts`),
-- justo después del INSERT sobre `negocio_administrador` — `INSERT INTO suscripcion_negocio
-- (negocio_id) VALUES ($1)`, dejando plan/estado en sus DEFAULT ('gratis'/'activa'). Verificado
-- contra ese código real que esto es seguro bajo la policy de INSERT de más abajo:
-- `withTransaction` ya setea `app.usuario_id` al `usuarioId` recién generado ANTES del primer
-- INSERT de esa transacción (no en un `set_config` a mitad de camino), y para ese momento el
-- INSERT sobre `negocio_administrador (negocioId, usuarioId)` ya corrió — la policy de INSERT de
-- `suscripcion_negocio` (`EXISTS` contra `negocio_administrador`) encuentra esa fila y pasa. Si en
-- cambio Backend prefiere no tocar `registro-negocio` y resolverlo de forma perezosa (mismo patrón
-- ya usado para `usuario_preferencias`/`paciente`: `INSERT ... ON CONFLICT (negocio_id) DO
-- NOTHING` la primera vez que se lee/escribe el estado del plan), también es válido — cualquiera
-- de los dos caminos deja, en la práctica, a un negocio nuevo sin fila todavía por un tiempo corto;
-- no es un problema mientras ningún endpoint dependa de esta tabla (fuera de alcance de este
-- ciclo), pero SÍ hay que resolverlo antes de conectar el chequeo de límites: un negocio sin fila
-- en `suscripcion_negocio` debe tratarse como 'gratis' en cualquier lectura (`COALESCE`/fallback
-- explícito), nunca como "sin límite" por accidente — chequear explícitamente por
-- `plan = 'turnario_pro'` (en vez de `plan <> 'gratis'`) ya hace esto seguro por default en SQL:
-- si no hay fila que joinear, la comparación da `NULL`/falso, no verdadero.
--
-- RLS — FORCE desde el primer commit (misma lección de §5bis, más arriba: cualquier tabla nueva la
-- necesita desde el día 1). 3 policies separadas (no una única simétrica como
-- `usuario_preferencias_acceso_propio`) porque acá, a diferencia de esa tabla, el criterio de
-- LECTURA es más ancho que el de ESCRITURA — pedido explícito de esta ronda: "quién puede
-- leer/escribir el estado del plan de un negocio (administrador del negocio, y lectura para
-- profesionales de ese negocio para poder mostrar el estado 'gratis: 42/60 turnos este mes' en
-- Mobile)":
-- - SELECT: cualquier STAFF del negocio — administrador O profesional activo en ese negocio_id —
--   mismo criterio EXISTS/OR que `turno_acceso_negocio_o_cliente` (sin la rama de `cliente_id`:
--   ningún caso de uso de este ciclo necesita que un cliente vea el plan del negocio). Sin filtrar
--   por `negocio_profesional.activo` — mismo criterio ya aplicado en
--   `paciente_acceso_propio_profesional` y en la rama de staff de `turno_acceso_negocio_o_cliente`,
--   ninguna de las dos lo exige.
-- - INSERT/UPDATE: solo ADMINISTRADOR del negocio — mismo criterio que
--   `servicio_insert_admin_del_negocio`/`servicio_update_admin_del_negocio` (el profesional puede
--   VER el estado del plan, pero gestionar la suscripción — dato de facturación del negocio — es
--   una decisión de administrador, igual que dar de alta un servicio o un profesional). Sin
--   `WITH CHECK` explícito en el UPDATE (a diferencia de `turno_acceso_negocio_o_cliente`/
--   `usuario_preferencias_acceso_propio`): mismo criterio que `servicio_update_admin_del_negocio`/
--   `negocio_profesional_update_admin_del_negocio` — Postgres reutiliza el `USING` como chequeo de
--   la fila nueva cuando no se da un `WITH CHECK` separado, y `negocio_id` no es un valor que
--   ningún flujo de este ciclo necesite reasignar (mismo motivo que `servicio.negocio_id`).
-- - Sin policy de DELETE — mismo motivo que `negocio_administrador`/`usuario_preferencias`: ningún
--   endpoint/HU de este ciclo borra una suscripción (cancelar es un UPDATE de `estado`, no un
--   DELETE de la fila) — fail-closed por default (RLS deniega cualquier comando sin policy
--   propia), documentado como intencional, no un olvido.
ALTER TABLE suscripcion_negocio ENABLE ROW LEVEL SECURITY;
ALTER TABLE suscripcion_negocio FORCE ROW LEVEL SECURITY; -- ver nota junto a `profesional`, más arriba en este archivo

CREATE POLICY suscripcion_negocio_select_staff_del_negocio ON suscripcion_negocio
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = suscripcion_negocio.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
    OR EXISTS (
      SELECT 1 FROM negocio_profesional np
      JOIN profesional p ON p.id = np.profesional_id
      WHERE np.negocio_id = suscripcion_negocio.negocio_id
        AND p.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

CREATE POLICY suscripcion_negocio_insert_admin_del_negocio ON suscripcion_negocio
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = suscripcion_negocio.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

CREATE POLICY suscripcion_negocio_update_admin_del_negocio ON suscripcion_negocio
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM negocio_administrador na
      WHERE na.negocio_id = suscripcion_negocio.negocio_id
        AND na.usuario_id = NULLIF(current_setting('app.usuario_id', true), '')::uuid
    )
  );

-- [BACKEND] suscripcion_negocio_select_negocio_en_contexto — pendiente de ratificación por DBA
-- (2026-08-14, mismo mecanismo ya usado y luego ratificado por DBA para
-- `profesional_update_propio_duracion_cita`/`turno_select_publico`/`notificacion_insert_job_sistema`
-- en este mismo archivo — ver 03-arquitectura/modelo-datos.md §5bis: Backend agrega acá una
-- policy acotada para cerrar un gap real encontrado al conectar código nuevo contra RLS, marcada
-- para revisión de DBA en su próximo ciclo).
--
-- Gap encontrado al implementar el chequeo de "60 turnos confirmados/mes" (HU-29,
-- backend/src/dominio/suscripciones.ts) en `POST /turnos` (backend/src/routes/turnos.ts): ese
-- endpoint corre con `requireAuth('cliente')` — `app.usuario_id` en su transacción es el CLIENTE
-- que reserva, nunca administrador ni profesional de ESE negocio, así que
-- `suscripcion_negocio_select_staff_del_negocio` (arriba) nunca lo habilita, sin importar cuál
-- sea el negocio. Sin esta policy, el chequeo del límite en el único camino de "reserva de
-- cliente sin seña -> turno nace confirmado directo" (ver ese archivo) leería siempre 0 filas
-- (fail-closed silencioso de RLS) y trataría CUALQUIER negocio, incluido uno con Turnario Pro
-- activo, como si nunca tuviera fila -> 'gratis' implícito (ver `obtenerEstadoSuscripcion`,
-- dominio/suscripciones.ts) — un negocio pago quedaría erróneamente limitado a 60 turnos/mes por
-- esta lectura. No es un problema de seguridad (nunca deja pasar de más), pero sí un bug
-- funcional real, y el motivo por el que esta policy se agrega en el mismo ciclo que el código
-- que la necesita, no se posterga.
--
-- Por qué acotada por `app.negocio_id` (no por `app.usuario_id`, a diferencia de las 3 policies
-- de arriba): el actor legítimo acá (el cliente reservando) nunca va a tener una fila propia en
-- `negocio_administrador`/`negocio_profesional` para este negocio — no hay forma de acotar por
-- identidad del actor sin excluir exactamente al actor legítimo. `obtenerEstadoSuscripcion`
-- (dominio/suscripciones.ts) fija `app.negocio_id` al negocio YA VALIDADO de la operación en
-- curso (ej. `servicio.negocio_id`, resuelto server-side, nunca un valor crudo del body)
-- INMEDIATAMENTE antes de este SELECT, sin confiar en lo que haya seteado el resto del handler —
-- mismo criterio defensivo que el resto de este archivo.
--
-- Alternativa evaluada y descartada — función `SECURITY DEFINER` (en vez de policy nueva): con
-- `FORCE ROW LEVEL SECURITY` activo y sin separación de roles todavía (hoy un solo rol para
-- migración+runtime, ver el bloque grande de RLS más arriba y §5bis), una función
-- `SECURITY DEFINER` de un owner sin `BYPASSRLS` NO bypassea RLS por sí sola (mismo warning ya
-- documentado junto a `turno_ocupacion_publica`/`turno_propio_para_gestion`, más abajo) —
-- necesitaría de todos modos una policy de respaldo como esta, así que se prefiere la policy
-- sola, más simple, en vez de dos capas.
--
-- Alcance de la relajación: SOLO lee `plan`/`periodo`/`vencimiento`/`estado` de la fila del
-- negocio con el que la transacción YA está interactuando — no expone la suscripción de otros
-- negocios, y no habilita ningún INSERT/UPDATE (siguen exclusivamente
-- `suscripcion_negocio_insert_admin_del_negocio`/`_update_admin_del_negocio`, arriba). Dato de
-- sensibilidad baja en este contexto puntual (un cliente en medio de reservar con ESE negocio
-- puede enterarse de si tiene o no Turnario Pro activo — nunca de negocios con los que no está
-- interactuando), comparable en espíritu a que el propio catálogo público de negocios/servicios
-- (`GET /negocios`, `GET /negocios/:id/servicios`) ya es de lectura pública sin autenticación.
--
-- Único call site hoy: `obtenerEstadoSuscripcion` (dominio/suscripciones.ts) — usado por los 2
-- chequeos de límite de HU-29 y por `GET /negocios/:id/plan` (aunque para administrador/
-- profesional ese último ya pasa por la policy de arriba sin necesitar esta). Si se agrega un
-- segundo call site con un criterio distinto, revisar explícitamente que esta policy siga siendo
-- la mínima necesaria — mismo criterio de revisión que ya dejó DBA junto a
-- `profesional_update_propio_duracion_cita`.
CREATE POLICY suscripcion_negocio_select_negocio_en_contexto ON suscripcion_negocio
  FOR SELECT USING (
    negocio_id = NULLIF(current_setting('app.negocio_id', true), '')::uuid
  );

-- ---------------------------------------------------------------------------
-- Índice adicional sobre `turno` (tabla existente, sin cambios de columnas) — soporte del límite
-- de 60 turnos confirmados/mes del plan gratis (HU-29). La query de chequeo (hot path: corre en
-- cada intento de reserva de un negocio en plan gratis) tiene la forma `SELECT count(*) FROM turno
-- WHERE negocio_id = ? AND estado = 'confirmado' AND inicio >= <inicio de mes> AND inicio <
-- <inicio de mes siguiente>` — índice parcial (mismo patrón que `uq_turno_slot_activo`/
-- `idx_notificacion_destinatario_no_leida`) filtrado por `estado = 'confirmado'`, columnas
-- `(negocio_id, inicio)` en ese orden (igualdad primero, rango después).
--
-- Supuesto no verificado, señalado para Backend: se indexa por `turno.inicio` (la fecha/hora DEL
-- TURNO), no por `turno.creado_en` (cuándo se creó/confirmó el registro) — interpretación más
-- consistente con la redacción del backlog ("60, ~2/día", una medida de densidad de agenda, no de
-- "cuándo se tocó la fila"), y coherente con que `uq_turno_slot_activo` ya indexa la disponibilidad
-- real por `inicio`. Si Backend/Product Manager definen lo contrario al implementar el chequeo (ej.
-- contar por `creado_en`), este índice no sirve para esa query — cambiarlo es una migración de una
-- sola línea (`CREATE INDEX ... ON turno (negocio_id, creado_en) WHERE ...`), no un rediseño.
-- No se agrega índice para el otro límite de HU-29 ("1 profesional por negocio"): ya está cubierto
-- por la PK compuesta `(negocio_id, profesional_id)` de `negocio_profesional` (negocio_id es la
-- columna líder) — ver `modelo-datos.md` §6.
CREATE INDEX idx_turno_negocio_confirmado_inicio
  ON turno (negocio_id, inicio)
  WHERE estado = 'confirmado';

-- ============================================================================
-- Recuperación de contraseña — token de un solo uso (2026-08-16, DBA)
-- ============================================================================
-- Origen: pedido del CEO, prioridad alta. Verificado antes de modelar (no asumido): hoy `usuario`
-- solo tiene `password_hash`/`google_id` para el login normal (HU-35, ver arriba), sin ningún
-- mecanismo de reset — no existe nada de esto ni en el esquema ni en el código. Alcance de esta
-- ronda ya decidido por el Director General IA (no se reabre acá — es la base sobre la que
-- Backend construye en un ciclo posterior, no implementado en este ciclo): Backend genera un
-- token de un solo uso, aleatorio y criptográficamente seguro (DISTINTO del JWT normal de sesión,
-- `src/auth.ts`), lo guarda SIEMPRE hasheado (nunca en texto plano — mismo criterio que
-- `usuario.password_hash`), con expiración corta, invalidable tras un solo uso o al expirar.
--
-- ¿TABLA NUEVA O COLUMNAS EN `usuario`? Tabla nueva — a diferencia de `usuario_preferencias`/
-- `suscripcion_negocio` (más arriba), acá la cardinalidad SÍ fuerza la respuesta, no es una
-- decisión de estilo: un usuario puede tener 0, 1 o varios tokens a lo largo del tiempo (ver
-- "varias recuperaciones seguidas" más abajo) — no es 1:1 con `usuario`.
--
-- NOMBRE — `token_recuperacion_password`, no `password_reset_token`: consistencia con el resto
-- del esquema en español ("password" se mantiene como préstamo ya establecido en este mismo
-- archivo — ver `usuario.password_hash`/`ck_usuario_password_o_google` — en vez de traducir a
-- "contraseña", que no aparece en ningún otro lado de este DDL). SIN prefijo `usuario_` (a
-- diferencia de `usuario_preferencias`/`usuario_preferencias_notificacion`): ese prefijo
-- identifica específicamente a la familia de PREFERENCIAS/configuración 1:1 con `usuario` (ver
-- más abajo, bloque de esa familia, "el límite explícito" que traza ese prefijo) — esta tabla no
-- es una preferencia, es un artefacto de autenticación efímero, más cerca en espíritu de
-- `turno`/`pago`/`notificacion` (sustantivo propio, sin anteponer el nombre de ninguna tabla que
-- referencia por FK) que de esa familia.
--
-- COLUMNAS:
-- - `usuario_id UUID NOT NULL REFERENCES usuario(id)` — a quién pertenece el token. Resuelto por
--   Backend ANTES del INSERT (`SELECT id FROM usuario WHERE email = ?`, lectura ya sin RLS — ver
--   más abajo), nunca provisto crudo por quien pide la recuperación.
-- - `token_hash TEXT NOT NULL UNIQUE` — el hash del token, NUNCA el token en texto plano (mismo
--   criterio que `password_hash`). A diferencia de `password_hash` (bcrypt, pensado para una
--   contraseña de BAJA entropía elegida por una persona, donde el costo adaptativo de bcrypt es
--   precisamente lo que dificulta la fuerza bruta), se RECOMIENDA a Backend (no implementado acá,
--   ni impuesto por ningún CHECK — el algoritmo de hash es implementación, no esquema) un hash
--   rápido no adaptativo (ej. SHA-256) en vez de bcrypt: el token en sí ya es de ALTA entropía
--   (aleatorio, generado por el servidor — no elegido por una persona), no necesita costo
--   computacional extra para resistir fuerza bruta, y usar bcrypt igual tendría 2 costos reales
--   sin ningún beneficio: (a) CPU innecesaria en cada validación — spamear el endpoint de canje
--   con hashes inválidos forzaría el costo adaptativo de bcrypt en cada intento, un vector de DoS
--   barato que un hash rápido no abre; (b) el límite de 72 bytes de entrada de bcrypt, no crítico
--   para un token corto pero una limitación real que un hash rápido no tiene. `UNIQUE`: colisión
--   prácticamente imposible por construcción (token aleatorio de suficiente entropía), pero
--   además ES el índice que cubre la query de validación por igualdad (`WHERE token_hash = ?`) —
--   resuelve el pedido explícito de este ciclo ("índice para buscar eficientemente por el hash
--   del token"), mismo patrón que `usuario.email`/`usuario.google_id` (UNIQUE inline = constraint
--   + índice a la vez, sin objeto nombrado aparte).
-- - `expira_en TIMESTAMPTZ NOT NULL` — sin DEFAULT: Backend lo calcula y lo pasa siempre explícito
--   (`now() + <TTL>`), mismo criterio que `turno.fin`/`excepcion_disponibilidad.fin` (NOT NULL,
--   sin default, el valor nace de una regla de aplicación, no de una constante de esquema).
--   Duración recomendada (no impuesta acá — decisión de producto/seguridad de Backend, no de DDL,
--   mismo criterio de "resolver en la capa de aplicación" ya aplicado sistemáticamente en este
--   archivo): 15–60 minutos, rango habitual para este tipo de flujo.
-- - `usado_en TIMESTAMPTZ` (nullable) — `NULL` = el token sigue vigente (pendiente de canjear);
--   con valor = YA NO puede usarse para resetear la contraseña, desde ese momento. A propósito UNA
--   sola columna cubre DOS motivos distintos de invalidación sin distinguir cuál fue (ver más
--   abajo, "varias recuperaciones seguidas") — ninguna HU pide diferenciar "se usó" de "quedó
--   invalidado por un pedido más nuevo del mismo usuario"; si hiciera falta en el futuro, es
--   aditivo (una columna `motivo_invalidacion` nueva, sin romper esta). Deliberadamente NO se
--   sigue acá el patrón de `notificacion.leido` (BOOLEAN + `modificado_en` genérico) pese a ser el
--   precedente más cercano de este archivo (una única columna mutable sobre una fila por lo demás
--   de solo-creación): a diferencia de `notificacion` (que ya se anticipaba iba a seguir sumando
--   campos mutables a futuro, ver bloque de esa tabla), esta fila tiene un ciclo de vida
--   deliberadamente binario y cerrado (vigente -> ya no vigente, para siempre) — una columna
--   dedicada es más precisa que una genérica para un hecho de auditoría de seguridad, sin pagar el
--   costo de una segunda columna redundante que siempre valdría exactamente lo mismo.
-- - `creado_en TIMESTAMPTZ NOT NULL DEFAULT now()` — igual que el resto del esquema. SIN
--   `creado_por`/`modificado_por`: OJO, no es el mismo motivo que la "auditoría reducida" de
--   `usuario_preferencias`/`usuario_preferencias_notificacion` (ahí se omiten por ser 100%
--   redundantes con `usuario_id`, porque RLS GARANTIZA que el actor autenticado es el propio
--   dueño de la fila). ACÁ no hay ningún actor autenticado en NINGUNA escritura de esta tabla —
--   ni crear el token (pedido de reset anónimo, por email, antes de cualquier sesión) ni canjearlo
--   (el token en sí ES la credencial, todavía sin JWT) pasan nunca por un `usuario_id` de sesión
--   (ver `withTransaction`/`ContextoRls`, `src/db.ts`) — `creado_por` sería NULL el 100% de las
--   veces, no por convención, sino porque la propia naturaleza pre-autenticación de este flujo
--   nunca provee ese dato. Mismo principio que ya reconoce este archivo para
--   `POST /auth/registro-cliente` sobre `usuario` ("usuario no tiene RLS... no hace falta pasar
--   por una transacción con contexto"). Sin `eliminado_en` (soft delete): nada referencia
--   `token_recuperacion_password.id`, y el ciclo de vida ya lo captura `usado_en`.
--
-- CHECK `expira_en > creado_en` — mismo patrón de invariante temporal ya usado en `turno.fin >
-- turno.inicio`/`disponibilidad.hora_fin > hora_inicio` (2 timestamps fijados juntos en el mismo
-- INSERT, deben quedar ordenados): guarda contra un bug de Backend que calculara mal el TTL y
-- emitiera un token ya vencido desde su creación.
--
-- "VARIAS RECUPERACIONES SEGUIDAS" (pedido explícito de esta ronda — pensar si hay que invalidar
-- tokens anteriores del mismo usuario al pedir uno nuevo, o dejarlos expirar solos; decisión de
-- DBA, documentada acá). SE ELIGE invalidar los anteriores, no dejarlos expirar solos, por 2
-- motivos:
-- 1. Seguridad — con expiración corta pero varios pedidos seguidos dentro de esa ventana (ej. "no
--    me llegó el mail, pido de nuevo" 2-3 veces en pocos minutos, el caso concreto que motiva esta
--    pregunta), dejarlos expirar solos deja VARIOS tokens simultáneamente válidos para la misma
--    cuenta durante el resto de la ventana — más secretos vivos a la vez de los necesarios, sin
--    ningún beneficio para el caso de reenvío (que solo necesita que el ÚLTIMO link funcione).
--    Invalidar los anteriores no perjudica en nada ese reenvío legítimo.
-- 2. Se puede garantizar a nivel de BASE DE DATOS, no solo como convención documentada que Backend
--    tiene que recordar (mismo valor que ya justifica `ck_usuario_password_o_google`/
--    `uq_turno_slot_activo` en este archivo): el índice único parcial de abajo
--    (`uq_token_recuperacion_password_usuario_pendiente`) hace IMPOSIBLE que exista más de 1 fila
--    con `usado_en IS NULL` para el mismo `usuario_id` — Backend queda estructuralmente obligado a
--    invalidar (`UPDATE ... SET usado_en = now() WHERE usuario_id = ? AND usado_en IS NULL`) el/los
--    token(s) pendientes existentes ANTES de insertar uno nuevo, en la misma transacción, o el
--    INSERT nuevo falla por violación de unicidad (23505) — mismo patrón de "conflicto detectado
--    por el motor, no solo por la aplicación" que `uq_turno_slot_activo`. Ese mismo índice cubre
--    además, como efecto secundario, la propia consulta de invalidación
--    (`WHERE usuario_id = ? AND usado_en IS NULL`).
--
-- Recomendación para Backend (no implementada acá, fuera de alcance de DBA):
-- - `POST /auth/recuperar-password` (o el nombre que se defina): 1) `SELECT id FROM usuario WHERE
--   email = $1` (sin RLS, igual que `/registro-cliente`); 2) si existe, EN LA MISMA transacción,
--   `UPDATE token_recuperacion_password SET usado_en = now() WHERE usuario_id = $1 AND usado_en IS
--   NULL` (invalida cualquier pendiente) seguido de `INSERT INTO token_recuperacion_password
--   (usuario_id, token_hash, expira_en) VALUES ($1, $2, $3)` con el hash del token nuevo — EN ESE
--   ORDEN (invalidar antes de insertar), por el índice único parcial de abajo. 3) responder
--   SIEMPRE el mismo mensaje genérico exista o no la cuenta ("si el email existe, vas a recibir
--   instrucciones..."), para no filtrar por timing/contenido de la respuesta qué emails están
--   registrados (user enumeration) — el envío del email en sí es tarea de Integraciones, no de
--   este modelado.
-- - `POST /auth/reset-password` (o el nombre que se defina): recibe el token en TEXTO PLANO
--   (nunca `usuario_id` ni ningún identificador — el token ES la prueba de identidad acá), lo
--   hashea con el mismo algoritmo, y hace `SELECT * FROM token_recuperacion_password WHERE
--   token_hash = $1 AND usado_en IS NULL AND expira_en > now()`. Sin fila -> 400 genérico ("token
--   inválido o vencido", sin distinguir cuál de las 2 razones — no darle a un atacante información
--   sobre si el token existió alguna vez). Con fila: EN LA MISMA transacción,
--   `UPDATE usuario SET password_hash = $1 WHERE id = $2` (el `usuario_id` de la fila recién
--   encontrada) + `UPDATE token_recuperacion_password SET usado_en = now() WHERE id = $3 AND
--   usado_en IS NULL` — el `AND usado_en IS NULL` extra en este 2do UPDATE (aunque ya se filtró en
--   el SELECT de arriba) cierra la carrera de un doble submit concurrente con el mismo token
--   (mismo espíritu que el manejo de 23505 ya existente para `uq_turno_slot_activo`): si
--   `rowCount === 0`, alguien más ya canjeó este token en el medio — abortar la transacción sin
--   aplicar el cambio de contraseña.
-- - Rate limiting — mismo patrón que `registroLimiter`/`loginLimiter`
--   (`src/middleware/rateLimit.ts`): recomendado para ambos endpoints nuevos, en especial el de
--   canje (intentar adivinar un token por fuerza bruta, aunque de altísima entropía, es
--   exactamente el tipo de endpoint que un rate limit debe cubrir).
-- - Job de limpieza (no implementado, no bloqueante): con el tiempo esta tabla acumula filas ya
--   usadas/invalidadas o vencidas sin usar — un job periódico que borre filas con más de, ej., 30
--   días de antigüedad (mismo espíritu que `expirarPagosPendientes.ts`) es una mejora de
--   housekeeping razonable para un ciclo futuro, no urgente (el volumen de esta tabla es bajo por
--   diseño: como máximo 1 fila pendiente por usuario a la vez, por el índice único parcial de
--   abajo).
CREATE TABLE token_recuperacion_password (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id    UUID NOT NULL REFERENCES usuario(id),
  token_hash    TEXT NOT NULL UNIQUE,
  expira_en     TIMESTAMPTZ NOT NULL,
  usado_en      TIMESTAMPTZ,
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_token_recuperacion_password_expira_futuro CHECK (expira_en > creado_en)
);

-- Único índice adicional (`token_hash` ya queda cubierto por el UNIQUE inline de arriba): parcial
-- sobre `usuario_id`, filtrado a filas todavía vigentes (`usado_en IS NULL`) — mismo patrón que
-- `uq_turno_slot_activo`/`idx_notificacion_destinatario_no_leida` (índice parcial filtrado por
-- estado activo). UNIQUE, no solo un índice de performance: es la garantía a nivel de base de
-- datos de "a lo sumo un token pendiente por usuario" (ver "varias recuperaciones seguidas" más
-- arriba) — Backend no puede insertar un segundo token pendiente para el mismo usuario sin
-- invalidar antes el anterior, el motor lo rechaza (23505) si lo intenta en el orden equivocado.
-- No se agrega un índice plano adicional sobre `usuario_id` (sin el filtro parcial) para "ver
-- todo el historial de un usuario, incluidos los ya usados": ninguna HU lo pide hoy — mismo
-- criterio de "no sobre-diseñar" ya aplicado en el resto de este archivo (ej. sin columna de
-- precio en `suscripcion_negocio` hasta que haga falta).
CREATE UNIQUE INDEX uq_token_recuperacion_password_usuario_pendiente
  ON token_recuperacion_password (usuario_id)
  WHERE usado_en IS NULL;

-- Row Level Security — DELIBERADAMENTE NO SE HABILITA en esta tabla. A diferencia de TODAS las
-- tablas nuevas de los últimos 5 ciclos (paciente/tratamiento/nota_medica, usuario_preferencias,
-- usuario_preferencias_notificacion, suscripcion_negocio — todas con FORCE ROW LEVEL SECURITY
-- desde el primer commit, lección de §5bis en modelo-datos.md), esta NO la lleva — no es un
-- olvido, es la misma conclusión, y por el mismo tipo de motivo, que ya dejó este archivo para
-- `usuario` en sí (ver comentario junto a `CREATE TABLE usuario`, más arriba, y
-- modelo-datos.md §2septies/§5octies para el desarrollo completo).
--
-- El patrón de RLS de todo este esquema se apoya en `current_setting('app.usuario_id')`, seteado
-- por `withTransaction(fn, { usuarioId })` (src/db.ts) a partir de un ACTOR YA AUTENTICADO (el
-- `sub` de un JWT, o -en un puñado de endpoints de registro- el id recién generado de la fila que
-- se está creando). Verificado contra `src/db.ts`/`src/routes/auth.ts` (no asumido) antes de
-- decidir esto: NINGUNA operación sobre esta tabla nueva tiene, en ningún momento de su ciclo de
-- vida, un `app.usuario_id` disponible de esa forma:
-- - Crear el token (`POST /auth/recuperar-password`) es un pedido ANÓNIMO por email — exactamente
--   el mismo tipo de operación que ya corre hoy sin contexto RLS sobre `usuario`
--   (`POST /auth/registro-cliente`, `pool.query` suelto, sin `withTransaction`) — no hay ningún
--   `usuario_id` de sesión que setear porque todavía no existe sesión.
-- - Canjear el token (`POST /auth/reset-password`) NO PUEDE, ni en principio, setear
--   `app.usuario_id` ANTES de la lectura que lo necesitaría: la consulta que resuelve a qué
--   usuario pertenece el token es justamente `SELECT ... WHERE token_hash = ?` — recién ESA
--   consulta devuelve el `usuario_id`. Una policy `usuario_id = app.usuario_id` exigiría conocer
--   el valor que la propia consulta todavía tiene que descubrir (dependencia circular
--   estructural), a diferencia de `usuario_preferencias`/`paciente`/etc., donde `app.usuario_id`
--   siempre se fija ANTES de la primera query de la transacción autenticada.
-- La autorización real de esta tabla no es "¿de quién es esta fila?" (el terreno que cubre RLS en
-- el resto de este esquema) sino "¿quién conoce el token en texto plano?" — un hecho que la base
-- de datos no puede verificar por sí sola (la comparación ocurre en la capa de aplicación, vía
-- hash, ANTES de que exista cualquier fila con la que RLS pueda razonar), estructuralmente análogo
-- a cómo `usuario.password_hash` tampoco depende de RLS para protegerse en el login
-- (`bcrypt.compareSync`, sin ninguna policy de por medio). Agregar `ENABLE ROW LEVEL SECURITY` con
-- una policy permisiva (`USING (true)`, mismo patrón transitorio que `turno_select_publico`,
-- §5bis) no sumaría protección real (equivalente a no tener RLS para el SELECT que más importa) y
-- sí el riesgo de dar una falsa sensación de "esta tabla ya está defendida por RLS" a quien lea el
-- esquema — se prefiere dejarlo explícitamente afuera y documentado, mismo criterio de honestidad
-- ya aplicado a `usuario`, antes que agregar RLS de cara a la galería. La protección real de esta
-- tabla es: alta entropía del token + hash irreversible + expiración corta + un solo uso + el
-- índice único parcial de arriba — no RLS.
-- Reevaluar esta conclusión si en algún ciclo futuro se agrega un endpoint AUTENTICADO que lea
-- esta tabla (ej. "ver mis solicitudes de recuperación recientes" en Configuración/Seguridad —
-- ninguna HU lo pide hoy): ese caso SÍ tendría `app.usuario_id` disponible y podría sumar una
-- policy de solo lectura (`usuario_id = app.usuario_id`) sin afectar el resto de este diseño.
