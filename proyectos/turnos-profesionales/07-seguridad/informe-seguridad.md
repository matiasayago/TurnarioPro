# Informe de Seguridad — Turnos Profesionales (TURNOS-2026-001)

**Rol:** Security
**Fase:** 5 — Calidad (revision en paralelo con QA)
**Fecha:** 2026-08-05

**Alcance revisado:** `05-codigo/backend/src/` (Node + TypeScript + Express + `node:sqlite` en
desarrollo; produccion apunta a PostgreSQL). Revision estatica de codigo + pruebas activas con
`curl` contra el servidor corriendo en `http://localhost:3000` (no se detuvo ni reinicio el
servidor; se generaron datos propios via `POST /dev/seed` y `POST /auth/registro-negocio` para
las pruebas, sin reutilizar credenciales de otras corridas).

Metodologia guiada por OWASP Top 10 (2021), priorizando lo especifico del dominio: aislamiento
multi-tenant (RN9) e historial privado por profesional (RN7/D3).

## Resumen ejecutivo

Se encontro **una vulnerabilidad Critical de escalada de privilegios cross-tenant** en el login
de administradores, que rompe la garantia central de aislamiento multi-tenant (RN9) del
proyecto y que fue **reproducida activamente con exito** (PoC incluida). Ademas hay 4 hallazgos
High, 3 Medium y varios Low/Info. **El backend NO esta listo para pasar a DevOps/despliegue**
hasta resolver al menos el hallazgo Critical y los High relacionados con autenticacion.

Nota positiva: el control de autorizacion cruzada punto-a-punto que pidio el Director General IA
probar activamente (profesional intentando leer/escribir /profesionales/:id/... o
/clientes/:id/historial de OTRO profesional cambiando el :id de la URL) **funciona
correctamente** -- esta bien implementado y fue el hallazgo Critical el que aparecio por una via
distinta y menos obvia (resolucion de negocio_id en el login de administrador), no por los
endpoints de profesional que fueron el foco explicito de la sospecha inicial.

---

## Hallazgos

### [CRITICAL-1] Escalada de privilegios cross-tenant: el login de administrador entrega el negocio_id de UN NEGOCIO AJENO (rompe RN9)

**Ubicacion:** `05-codigo/backend/src/routes/auth.ts`, endpoint `POST /auth/login`, rama
`rol === 'administrador'` (lineas ~63-72).

**Descripcion:** Al loguearse (no al registrarse -- el registro si firma el token correcto), la
query que resuelve el negocio_id del administrador es:

```sql
SELECT n.id FROM negocio n
JOIN usuario u ON u.id = ? WHERE u.rol = 'administrador' LIMIT 1
```

La condicion del JOIN (`u.id = ?`) fija que fila de usuario se usa, pero **no correlaciona
en absoluto** la tabla negocio con ese administrador -- no hay ninguna columna que vincule
usuario/administrador con su negocio. El resultado es un producto cruzado entre negocio
y la unica fila de usuario que matchea, asi que LIMIT 1 sin ORDER BY devuelve
efectivamente **el primer negocio insertado en toda la base de datos**, sin importar a que
negocio pertenece el administrador que se loguea.

Esto no es solo un bug de la query: **el modelo de datos no tiene ninguna relacion persistida**
entre un usuario administrador y su negocio (ni una columna negocio.admin_usuario_id ni una
tabla de asociacion) -- la unica vez que se conoce esa relacion es en el momento de
POST /auth/registro-negocio, donde se firma el token correcto porque el negocio se acaba de
crear en la misma request. En cualquier login posterior, esa informacion ya no se puede
reconstruir con el esquema actual.

**Impacto:** cualquier administrador que se loguea (el flujo normal en produccion -- el registro
solo ocurre una vez) recibe un JWT con negocio_id de un negocio que no le pertenece,
obteniendo asi **permisos de escritura administrativa sobre un tenant ajeno**
(POST /negocios/:id/servicios, POST /negocios/:id/profesionales) -- violacion directa de RN9
("ningun dato de un negocio es visible/administrable desde otro"). Simultaneamente, el
administrador **pierde la capacidad de gestionar su propio negocio real** (su token ya no lleva
su propio negocio_id, asi que sus propias altas de servicio/profesional son rechazadas con 403
"No podes administrar recursos de otro negocio").

Es probable que este bug no se haya detectado en pruebas de humo previas porque el flujo de
smoke test tipico registra un solo negocio (con una sola fila en negocio, el bug es
inobservable: "el primero de la tabla" coincide por casualidad con el propio). Se vuelve visible
recien con 2+ negocios en la base, que es exactamente el escenario multi-tenant que la
aplicacion existe para soportar.

**Evidencia (PoC reproducido en este entorno):**
1. Se registraron dos negocios distintos via POST /auth/registro-negocio: Negocio A
   (negocio_id propio devuelto en el registro: f82ad199-...) y Negocio B
   (negocio_id propio: 4df33002-...).
2. Se hizo POST /auth/login con las credenciales del administrador del Negocio A -> el token
   devuelto llevaba negocio_id = 3d9f17b7-... (un tercer negocio, el primero creado en esta
   sesion de pruebas -- NO el f82ad199-... que le pertenece).
3. Se hizo POST /auth/login con las credenciales del administrador del Negocio B -> el token
   devuelto llevo el mismo negocio_id = 3d9f17b7-... (no el 4df33002-... propio).
4. Con el token de login del administrador B se ejecuto:
   POST /negocios/3d9f17b7-.../servicios con body
   {"nombre":"SERVICIO-INYECTADO-POR-ADMIN-B", ...} -> **201 Created**. El administrador B
   inyecto exitosamente un servicio en un negocio que no es el suyo.
   (Nota de transparencia: este servicio de prueba quedo efectivamente creado en el negocio
   3d9f17b7-... de este entorno de pruebas como evidencia del PoC; no se realizo ninguna
   limpieza porque no existe endpoint de borrado y no corresponde a Security aplicar
   remediaciones. Si QA esta corriendo pruebas sobre ese mismo negocio, esta fila es atribuible
   a esta prueba de seguridad, no a un tercero.)

**Severidad:** **Critical**. Bloqueante para despliegue.

**Remediacion sugerida:**
- Cambio de esquema (DBA): agregar una relacion persistida entre administrador y negocio -- por
  ejemplo negocio.admin_usuario_id (1:1, alcanza para el MVP "1 admin = 1 negocio" documentado)
  o, si se anticipa mas de un administrador por negocio a futuro, una tabla de asociacion
  negocio_administrador(usuario_id, negocio_id).
- Backend: reescribir la resolucion de negocio_id en POST /auth/login para consultar esa
  relacion directamente (WHERE admin_usuario_id = usuario.id o equivalente), eliminando el
  JOIN sin correlacion actual.
- Agregar un test de regresion especifico con 2+ negocios en la base (el smoke test actual
  con un solo negocio no lo hubiera detectado) que verifique que el login de cada administrador
  devuelve su propio negocio_id.
- Revisar si Row Level Security (pendiente de conectar, ver modelo-datos.md parrafo 5) mitigaria
  esto: **no lo haria por si sola** -- si SET LOCAL app.negocio_id se poblara con el mismo claim
  roto del JWT, RLS aplicaria la politica sobre el negocio_id incorrecto igual, dando falsa
  sensacion de seguridad. Este hallazgo debe resolverse en el JWT/esquema antes o
  independientemente de conectar RLS.

---

### [HIGH-1] Sin rate limiting / proteccion de fuerza bruta en /auth/login

**Ubicacion:** `05-codigo/backend/src/routes/auth.ts` (POST /auth/login), `app.ts` (sin
middleware de rate limiting global).

**Descripcion:** No existe ningun control de intentos fallidos por IP, por cuenta, ni backoff
exponencial ni bloqueo temporal.

**Evidencia:** se enviaron 8 intentos de login consecutivos con contrasena incorrecta contra la
misma cuenta -- los 8 fueron procesados normalmente (401 cada vez, sin 429, sin demora
creciente, sin bloqueo de cuenta).

**Impacto:** habilita ataques de fuerza bruta / credential stuffing contra cualquier cuenta
(cliente, profesional o administrador), especialmente relevante porque tampoco hay politica de
contrasenas minimas (ver MEDIUM-1).

**Severidad:** High. OWASP A07:2021 (Identification and Authentication Failures).

**Remediacion sugerida:** agregar express-rate-limit (o equivalente) por IP y por
email/cuenta en /auth/login y /auth/registro-*; considerar bloqueo temporal tras N intentos
fallidos consecutivos y logging de intentos fallidos para auditoria (alineado con el requisito
de "auditoria" del rol Security).

---

### [HIGH-2] Errores no controlados devuelven stack traces completos con rutas absolutas del servidor

**Ubicacion:** No hay middleware de manejo de errores (4 argumentos) en app.ts; cualquier
excepcion no capturada cae en el manejador de error por defecto de Express.

**Evidencia:**
- POST /turnos con inicio: "esto-no-es-una-fecha" -> 500 con pagina HTML mostrando
  RangeError: Invalid time value y el stack completo, incluyendo la ruta absoluta del
  proyecto en disco (.../05-codigo/backend/src/routes/turnos.ts:60:20, etc.).
- POST /profesionales/:id/disponibilidad con dia_semana: 99 (fuera del CHECK (dia_semana
  BETWEEN 0 AND 6)) -> 500 con el mismo patron: Error: CHECK constraint failed:
  dia_semana BETWEEN 0 AND 6 + stack trace completo con rutas absolutas.
- El servidor sigue respondiendo con normalidad despues (GET /health -> 200 {"ok":true}), es
  decir, no tira el proceso completo, pero cada excepcion de este tipo expone informacion
  interna en la respuesta.

**Impacto:** exposicion de estructura de directorios, nombres de archivo/linea de codigo y
mensajes crudos del motor de base de datos -- informacion de reconocimiento util para un
atacante (OWASP A05:2021 Security Misconfiguration), y aunque no se probo con NODE_ENV=production
explicito, no hay ninguna verificacion en el codigo de que este comportamiento cambie en
produccion (Express usa el mismo manejador por defecto salvo que se agregue uno propio).

**Severidad:** High.

**Remediacion sugerida:** agregar middleware de manejo de errores centralizado en app.ts que
loguee el detalle completo server-side (auditoria) pero devuelva al cliente un mensaje generico
({"error":"Error interno"}, 500) sin stack trace, en todos los entornos. Complementar con
validacion de entrada (ver MEDIUM-3) para que estos casos ni siquiera lleguen a lanzar la
excepcion.

---

### [HIGH-3] Fallback de JWT_SECRET hardcodeado, sin verificacion de arranque

**Ubicacion:** `05-codigo/backend/src/auth.ts` linea 4:

```ts
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-not-for-production';
```

**Descripcion:** si la variable de entorno JWT_SECRET no esta seteada, el proceso arranca
igual y firma/verifica todos los JWT con el string hardcodeado dev-secret-not-for-production,
visible en el codigo fuente. No hay ninguna comprobacion de arranque (fail-fast) que impida
que el servidor levante en produccion sin ese secreto seteado correctamente.

**Impacto:** si esta configuracion llegara a un entorno real sin JWT_SECRET seteado, cualquiera
que conozca (o adivine, dado que esta en el codigo) ese valor podria **forjar JWT arbitrarios**
-- cualquier rol, negocio_id o profesional_id -- logrando bypass total de autenticacion y
autorizacion sobre toda la plataforma. Es un riesgo condicional (depende de un error de
configuracion de despliegue) pero de impacto maximo si ocurre, y hoy no hay ninguna barrera
automatica que lo prevenga.

**Severidad:** High (impacto Critical si el condicionante ocurre; se califica High porque
requiere un error de configuracion externo para materializarse, pero dado que no hay ningun
control que lo evite, DevOps debe tratarlo como bloqueante de checklist de despliegue).

**Remediacion sugerida:** eliminar el fallback en cualquier build de produccion, o mejor, hacer
que el arranque falle explicitamente (throw/process.exit(1)) si NODE_ENV==='production' y
JWT_SECRET no esta seteado o no cumple una longitud/entropia minima. Gestionar el secreto via
gestor de secretos (Vault/Secrets Manager/variables de entorno del orquestador), nunca en el
repositorio.

---

### [HIGH-4] Endpoints /dev/* y web-preview sin autenticacion, protegidos solo por una variable de entorno

**Ubicacion:** `05-codigo/backend/src/app.ts` lineas 27-30, `05-codigo/backend/src/routes/dev.ts`.

**Descripcion:** POST /dev/seed y POST /dev/forzar-expiracion (mas el estatico
web-preview/) se montan unicamente si process.env.NODE_ENV !== 'production'. Ninguno de los
dos endpoints tiene autenticacion ni autorizacion propia -- quien pueda alcanzarlos por red puede
usarlos sin restriccion.

**Impacto:** es un unico punto de fallo de configuracion. Si un entorno compartido (staging, o
produccion por error de despliegue) no setea NODE_ENV=production explicitamente, cualquier
llamante anonimo puede:
- POST /dev/seed repetidamente: crear negocios/usuarios arbitrarios con contrasena fija y
  conocida desde el codigo fuente (demo1234), pudiendo saturar la base o generar datos falsos
  en un entorno real.
- POST /dev/forzar-expiracion: forzar la cancelacion anticipada de turnos pendiente_de_pago
  de OTROS usuarios/negocios en cualquier momento -- un vector de denegacion de servicio dirigido
  contra la integridad de las reservas (afecta RN2/D2), sin necesidad de autenticarse.

**Severidad:** High. Depende de un error de configuracion de despliegue, pero el "blast radius"
si ocurre es alto (creacion de datos + DoS de reservas ajenas, sin autenticacion).

**Remediacion sugerida:** no depender solo de NODE_ENV en runtime -- excluir estas rutas y la
carpeta web-preview del artefacto/build de produccion (a nivel de empaquetado, no solo de
montaje condicional), y si se necesitan en staging, protegerlas ademas con un secreto/header de
desarrollo o restriccion de red (allowlist de IP). Preferir un flag explicito de opt-in
(ENABLE_DEV_ROUTES=true) en vez de un opt-out implicito por NODE_ENV.

---

### [MEDIUM-1] Sin politica de fortaleza de contrasenas

**Ubicacion:** `05-codigo/backend/src/routes/auth.ts` (registro-cliente, registro-negocio),
`05-codigo/backend/src/routes/negocios.ts` (alta de profesional por el administrador).

**Descripcion:** la unica validacion sobre password es que no sea falsy (!password); no hay
longitud minima ni chequeo de complejidad.

**Evidencia:** POST /auth/registro-cliente con "password":"a" (1 caracter) -> 201 Created,
cuenta creada y hasheada normalmente con bcrypt.

**Impacto:** contrasenas triviales facilitan compromiso de cuenta, especialmente combinado con
la falta de rate limiting (HIGH-1).

**Severidad:** Medium.

**Remediacion sugerida:** exigir longitud minima (ej. 8-10 caracteres) y, opcionalmente, chequeo
contra listas de contrasenas filtradas (ej. API de HaveIBeenPwned en modo k-anonimato) en los
tres puntos de creacion de contrasena.

---

### [MEDIUM-2] Sin cabeceras de seguridad HTTP basicas (falta helmet o equivalente)

**Ubicacion:** `05-codigo/backend/src/app.ts` -- solo express.json(), sin ningun middleware de
cabeceras.

**Evidencia:** curl -D - http://localhost:3000/health devuelve X-Powered-By: Express
(revela stack tecnologico) y no incluye X-Content-Type-Options, X-Frame-Options /
frame-ancestors, ni Referrer-Policy.

**Impacto:** bajo para una API JSON consumida por una app mobile nativa (la mayoria de estas
cabeceras son mitigaciones de navegador), pero web-preview/ si sirve HTML y se beneficiaria de
proteccion anti-clickjacking/MIME-sniffing; ademas, X-Powered-By es informacion de
reconocimiento gratuita para un atacante.

**Severidad:** Medium (Low de explotabilidad directa, pero de correccion trivial y buena
practica estandar).

**Remediacion sugerida:** agregar app.use(helmet()) como minimo, o al menos
app.disable('x-powered-by'). La cabecera Strict-Transport-Security corresponde configurarla
en la capa de terminacion TLS/reverse proxy (DevOps), no en la app Node directamente.

---

### [MEDIUM-3] Validacion de entrada insuficiente (mas alla de presencia) permite llegar a excepciones no controladas

**Ubicacion:** multiples handlers en turnos.ts, profesionales.ts -- validan que los campos
existan pero no su formato/rango.

**Evidencia:** ver los dos casos de HIGH-2 (inicio no es una fecha valida; dia_semana fuera
de rango 0-6). Adicionalmente, negocio_id/servicio_id/profesional_id recibidos por
parametro de URL o body nunca se validan como GUID bien formado -- hoy es inofensivo porque las
queries estan parametrizadas y simplemente devuelven []/404 (no hay inyeccion ni fuga), pero
es una buena practica ausente que ademas contribuye a que casos invalidos lleguen mas profundo
de lo necesario en el codigo.

**Impacto:** combinado con MEDIUM-2/HIGH-2, un request malformado puede producir un 500 con
detalle interno en vez de un 400 limpio.

**Severidad:** Medium.

**Remediacion sugerida:** validacion de esquema (ej. zod/joi) al inicio de cada handler:
fechas ISO-8601 validas, GUID con formato validado, rangos numericos (dia_semana 0-6,
duraciones > 0), devolviendo 400 antes de tocar la base de datos.

---

### [LOW-1] Sin politica CORS explicita

**Ubicacion:** `05-codigo/backend/src/app.ts` -- no hay middleware cors.

**Descripcion:** al no configurar CORS, el navegador bloquea por defecto cualquier request
cross-origin desde JS de un sitio distinto -- lo cual, para el modelo actual (consumo desde app
mobile nativa, donde CORS no aplica; y web-preview/ que es same-origin), **no es explotable
hoy**. Se documenta como hallazgo Low/de diseno porque cuando se incorpore un frontend web (o
el Portal del CEO) que consuma esta API desde otro origen, hara falta configurar
Access-Control-Allow-Origin explicitamente con una allowlist -- nunca wildcard en una API que
usa JWT Bearer -- para no abrir la superficie de ataque en ese momento.

**Severidad:** Low / Info -- no bloqueante para el alcance mobile actual, si a tener en cuenta
antes de sumar un cliente web.

**Remediacion sugerida:** dejar documentado para cuando se agregue un cliente web: usar
cors con origin explicito (lista blanca), no wildcard.

---

### [LOW-2] /dev/seed devuelve contrasenas en texto plano (contexto: endpoint ya marcado dev-only)

**Ubicacion:** `05-codigo/backend/src/routes/dev.ts` -- la respuesta incluye
password: "demo1234" para las cuentas de profesional/cliente recien creadas.

**Descripcion:** es un valor fijo ya visible en el codigo fuente (no un secreto real generado
en runtime), y el endpoint entero es dev-only (ver HIGH-4). Se documenta como recordatorio para
reforzar que este patron no debe replicarse en ningun endpoint que llegue a produccion.

**Severidad:** Low/Info, subsumido en HIGH-4.

---

## Observaciones informativas (no vulnerabilidades, quedan registradas para trazabilidad)

- **Inyeccion SQL -- sin hallazgos.** Se revisaron todas las queries en src/ (busqueda de SQL con
  interpolacion de template literals no encontro coincidencias) y se probaron activamente
  payloads tipo ' OR '1'='1 en email de login y 1 OR 1=1 en parametros de URL -- en todos
  los casos el resultado fue el esperado para un dato inexistente (401/[]), sin evidencia de
  inyeccion. Todas las queries usan placeholders ? parametrizados.
- **password_hash -- sin hallazgos.** Se revisaron todos los SELECT * sobre usuario -- se
  usan solo internamente (comparacion de bcrypt, resolucion de claims); ningun endpoint
  serializa el objeto usuario completo en la respuesta JSON.
- **Autorizacion cruzada profesional-profesional -- sin hallazgos (control positivo).** Se probo
  activamente: Profesional 1 (negocio A) contra GET /profesionales/:id/clientes,
  GET /profesionales/:id/turnos y POST /profesionales/:id/disponibilidad usando el :id del
  Profesional 2 (negocio B) -> los tres devolvieron 403 correctamente
  (esPropioProfesional() en profesionales.ts funciona como se espera).
- **Historial de cliente (D3/RN7) -- sin hallazgos.** GET /clientes/:id/historial filtra
  siempre por profesional_id del JWT ademas del cliente_id de la URL -- un profesional que
  pide el historial de un cliente que nunca atendio recibe [] (200, no filtra por UI sino por
  query, como documenta el propio codigo).
- **Algorithm confusion en JWT -- sin hallazgos.** Se probo un token forjado con
  alg: "none" (sin firma) contra un endpoint protegido -> jsonwebtoken lo rechazo
  correctamente (401 Token invalido o expirado).
- **Endpoints /negocios/:id/servicios y /negocios/:id/profesionales (alta por
  administrador) -- el chequeo req.auth.negocio_id !== req.params.id esta bien implementado**;
  el problema no es este chequeo sino que, por CRITICAL-1, req.auth.negocio_id llega
  corrompido desde el login.
- **Webhook de Mercado Pago:** aun no esta montada la ruta (POST /webhooks/mercadopago
  mencionada en documento-arquitectura.md parrafo 5 no existe todavia en app.ts/rutas) y
  MockPagoProvider.validarWebhook() siempre devuelve true. No es un hallazgo actual porque no
  hay superficie expuesta, pero queda como recordatorio explicito para Integraciones: la
  implementacion real debe validar la firma (no heredar el return true del Mock) antes de
  ir a produccion.
- **Row Level Security (Postgres):** confirmado que sigue sin conectar (SET LOCAL
  app.negocio_id/app.usuario_id pendiente), tal como ya documentan DBA/Backend. Ver nota en
  CRITICAL-1: RLS no es sustituto de corregir la resolucion de negocio_id en el JWT.
- **Brecha diseno-implementacion:** documento-arquitectura.md parrafo 5 especifica "JWT con
  expiracion corta + refresh token"; la implementacion actual usa JWT plano de 2 horas sin
  mecanismo de refresh ni revocacion (diseno stateless estandar, trade-off aceptable pero no
  documentado como decision explicita). No es un hallazgo de severidad asignada, es una nota
  para que Arquitecto/Backend cierren la brecha o confirmen el trade-off conscientemente.

---

## Tabla resumen

| ID | Severidad | Hallazgo | Bloqueante despliegue |
|---|---|---|---|
| CRITICAL-1 | Critical | Login de administrador entrega negocio_id de otro negocio (rompe RN9) | Si |
| HIGH-1 | High | Sin rate limiting en /auth/login | Si |
| HIGH-2 | High | Stack traces con rutas absolutas en errores no controlados | Si |
| HIGH-3 | High | Fallback hardcodeado de JWT_SECRET sin fail-fast | Si (checklist DevOps) |
| HIGH-4 | High | /dev/* sin autenticacion propia, solo gateado por NODE_ENV | Si (checklist DevOps) |
| MEDIUM-1 | Medium | Sin politica de fortaleza de contrasenas | No, recomendado antes de produccion |
| MEDIUM-2 | Medium | Faltan cabeceras de seguridad HTTP (helmet) | No |
| MEDIUM-3 | Medium | Validacion de entrada insuficiente (tipos/rangos) | No |
| LOW-1 | Low/Info | Sin politica CORS explicita (no explotable en alcance mobile actual) | No |
| LOW-2 | Low/Info | /dev/seed devuelve password en texto plano (ya dev-only) | No |

Total: 1 Critical, 4 High, 3 Medium, 2 Low/Info, mas 8 observaciones informativas de
controles verificados como correctos.

---

## Conclusion

**El backend NO esta listo para pasar a DevOps/despliegue en su estado actual.** El hallazgo
CRITICAL-1 rompe la garantia de aislamiento multi-tenant (RN9) que es la decision de mayor
impacto de todo el proyecto (D1) y fue reproducido activamente con una prueba de concepto
exitosa (escritura cruzada entre negocios). Los hallazgos HIGH-1 a HIGH-4 son bloqueantes de
checklist de seguridad antes de cualquier despliegue, aunque HIGH-3 y HIGH-4 son condicionales a
errores de configuracion (deben resolverse igual, ya que hoy no existe ninguna barrera
automatica que impida esa mala configuracion).

Recomendacion: remediar CRITICAL-1 (requiere cambio de esquema de DBA + fix de Backend, no es
un simple ajuste de query) y HIGH-1/HIGH-2/HIGH-3/HIGH-4 antes de solicitar nueva revision de
Security. Los MEDIUM se recomiendan resolver en el mismo ciclo por ser de bajo costo de
correccion, pero no son bloqueantes estrictos. Los LOW quedan como mejoras de higiene /
recordatorios para fases futuras (frontend web, integracion real de pagos).

Ningun hallazgo de este informe fue remediado por Security -- se reporta para decision del
Director General IA sobre como y cuando priorizar la correccion, conforme a las reglas de
actuacion del rol.

---

## Adenda (2026-08-10) -- Dos decisiones puntuales pre-implementacion: HU-35 y HU-20

**Alcance de esta adenda, distinto del resto de este informe:** el cuerpo del documento de
arriba es una revision de codigo ya escrito (Fase 5, 2026-08-05). Aca se documentan dos
decisiones de diseno de seguridad pedidas puntualmente por UX/UI y Product Manager durante el
diseno de HU-35 (login con Google, `02-backlog/backlog.md`) y HU-20 (datos de salud en la Ficha
de Paciente, `02-backlog/backlog.md` + `04-diseno/mapa-pantallas.md` parrafos 5.9/6) -- **antes**
de que exista implementacion. No es una auditoria OWASP completa del proyecto. El detalle
operativo de cada decision (la regla que Backend/DBA deben implementar) tambien quedo reflejado
directamente en `02-backlog/backlog.md`, junto a cada historia; aca se documenta ademas el
razonamiento completo y las alternativas descartadas.

| Decision | Bloquea diseno/desarrollo (Fases 3-5)? | Bloquea produccion con datos/vinculacion reales? |
|---|---|---|
| HU-35 -- nunca vincular/loguear solo por coincidencia de email | No | Si, si se implementara distinto de lo decidido aca (ej. auto-vinculacion silenciosa) |
| HU-20 -- RLS por negocio no alcanza solo; falta scope por profesional + auditoria de accesos | No | Si (scope por profesional + auditoria) -- complementa, no reemplaza, el gate legal de Ley 25.326 ya definido por el CEO |

### A. HU-35 -- Vinculacion de cuentas al loguear con Google

**Pregunta original** (`02-backlog/backlog.md`, HU-35): si un email ya tiene una cuenta creada
por el flujo de contrasena y esa persona toca "Google" con el mismo email, el sistema vincula
automaticamente por coincidencia de email, o es riesgo de account takeover si Google no verifico
ese email con el mismo criterio de confianza que hoy exige el sistema?

**Decision: nunca vincular ni loguear automaticamente solo por coincidencia de email** -- ni
siquiera cuando el ID token de Google confirma `email_verified: true`. Reglas completas (ya
trasladadas al backlog, HU-35, para que Backend las implemente tal cual):

1. Sin cuenta previa con ese email -> alta nueva via Google solo si `email_verified: true`; si
   viene `false`, rechazar el alta.
2. Cuenta previa por contrasena con ese email -> exigir que la persona confirme la contrasena
   existente en el mismo flujo antes de persistir la vinculacion Google<->usuario_id, sin importar
   `email_verified`.
3. Una vez vinculada: sigue existiendo una unica fila `usuario`; Google pasa a ser un metodo de
   acceso adicional de ese `usuario_id`, no un usuario nuevo -- requiere que Backend/DBA persistan
   explicitamente esa asociacion (proveedor + `sub` de Google, no el email), nunca inferirla en
   cada login por comparar el string de email.

**Por que no alcanza con confiar solo en `email_verified: true`:**

- `email_verified: true` prueba que la cuenta de Google controla **hoy** esa casilla de correo --
  no prueba que quien la controla hoy es la misma persona que creo la contrasena original de esta
  app. Hay vectores conocidos donde esas dos cosas dejan de coincidir: casillas de email
  recicladas o abandonadas y reclamadas despues por otra persona (clase de ataque ya documentada
  en la industria contra servicios que tratan "mismo email" como "misma identidad" para
  vinculacion de cuentas), una cuenta de Google comprometida, o cuentas Google Workspace que una
  organizacion puede emitir para su propio dominio sin pasar por el mismo flujo de verificacion
  con el que una persona crea una cuenta personal de Gmail. El propio estandar OpenID Connect
  expone `email_verified` como una senal a chequear, no como una prueba absoluta de identidad --
  por eso sigue siendo obligatoria para el alta nueva (punto 1), pero no es suficiente por si
  sola para vincular una cuenta YA existente (punto 2).
- Impacto si se vinculara mal: esta cuenta puede tener reservas y, a partir de HU-20, datos de
  salud -- exactamente el tipo de dato que la parte B de esta misma adenda trata como sensible. El
  costo de explotar una vinculacion automatica (si existiera) es bajo para quien controle la
  casilla de correo en el momento del ataque; el costo de pedir una confirmacion adicional
  (contrasena existente, una sola vez, en el mismo flujo) es bajo y no degrada la propuesta de
  valor de HU-35 para el caso comun (alta nueva) -- solo agrega un paso en el caso de colision con
  una cuenta preexistente, que ademas es el caso de mayor riesgo.
- **Alternativas evaluadas y no elegidas:**
  - *Rechazar sin ofrecer vinculacion en absoluto* ("inicia sesion por el metodo original, sin
    opcion de vincular Google despues"): mas simple de implementar y tambien segura, pero peor
    experiencia sin necesidad real -- la confirmacion con contrasena ya cierra el riesgo con el
    mismo nivel de friccion que un login normal. Queda como alternativa valida para una primera
    version mas simple si Backend prefiere no construir el flujo de confirmacion todavia, pero no
    es la recomendacion.
  - *Vincular automatico si `email_verified: true`, sin pedir nada mas:* es la lectura mas directa
    de la pregunta original, pero no cierra los escenarios de email reciclado/cuenta Google
    comprometida/Workspace descritos arriba -- no se recomienda para un sistema que va a guardar
    datos de salud (HU-20).

**No bloqueante para el resto de HU-35** (mismo criterio que ya tenian las otras dos preguntas
abiertas de esta historia) -- condiciona el diseno detallado/implementacion de esta historia
puntual, no el resto de E4 (HU-01/HU-02 siguen funcionando sin cambios).

**Nota de higiene, informativa, no bloqueante de HU-35 (gap preexistente, no introducido por esta
historia):** verificado contra el codigo real (`05-codigo/backend/src/routes/auth.ts`,
`POST /auth/registro-cliente` y `/registro-negocio`) que el flujo de contrasena actual tampoco
verifica hoy que el email sea real -- no hay confirmacion por correo, se confia en el string tal
cual lo escribe quien se registra. Exigir `email_verified` de Google es, en los hechos, mas
estricto que la linea base actual del propio sistema. No se agrega como bloqueante de esta
historia (fuera del alcance puntual pedido), pero queda anotado como mejora de higiene futura
equivalente para ambos metodos.

### B. HU-20 -- Sensibilidad de datos de salud en la Ficha de Paciente

**Pregunta original** (`04-diseno/mapa-pantallas.md` parrafos 5.9/6, `02-backlog/backlog.md` HU-20):
alergias, notas medicas generales y contacto de emergencia van a quedar protegidos por el mismo
esquema de Row Level Security multi-tenant que ya protege el resto del proyecto -- ese
aislamiento estandar alcanza, o hace falta algo adicional (cifrado a nivel de columna, auditoria
de accesos, restriccion de endpoints) antes de produccion real?

**Decision: el RLS multi-tenant por negocio, tal como esta disenado hoy, es necesario pero no
alcanza solo.** Verificado contra el DDL real (`05-codigo/database/migrations/001_init.sql`) y
contra el codigo real (`05-codigo/backend/src/routes/clientes.ts`,
`03-arquitectura/documento-arquitectura.md` parrafo 5), no solo por inspeccion de los documentos de
diseno:

1. **El nivel que ya cubren las policies de RLS existentes es "por negocio" (cualquier staff del
   negocio), no "por profesional".** Las policies de `profesional`/`servicio`/
   `negocio_profesional` acotan la escritura a "algun administrador o profesional del negocio" y
   `turno_select_publico` es de lectura publica -- correcto para agenda/catalogo, pero **RN7/D3
   exige un nivel mas estricto para el historial y para lo que agrega HU-20**: visible unicamente
   para el profesional que atendio/registro a ese paciente, ni siquiera para otro profesional del
   mismo negocio. Esa restriccion mas fina existe hoy, pero se aplica **a nivel de query de
   aplicacion, no de RLS**: `GET /clientes/:id/historial` filtra explicitamente
   `WHERE t.cliente_id = $1 AND t.profesional_id = $2` (comentario del propio codigo: "No se
   filtra en el cliente (UI), se filtra aca, en la query"), y `documento-arquitectura.md` parrafo 5 lo
   documenta igual ("Ningun dato de historial de un cliente se expone a un profesional que no lo
   atendio (D3) -- se valida a nivel de query, no solo de UI"). Si las tablas nuevas de HU-20
   heredan el mismo patron de RLS que `turno`/`profesional` (correcto para esos casos) **sin**
   replicar ademas esta restriccion por profesional, alergias/notas medicas/contacto de
   emergencia quedarian visibles para cualquier profesional o administrador del mismo negocio --
   una regresion de privacidad respecto de lo que ya garantiza el historial hoy, y muy
   probablemente un incumplimiento de RN7/D3 tal como esta redactada.
2. **Punto de modelado urgente para DBA, que esta extendiendo este mismo esquema en paralelo
   ahora mismo:** hoy "cliente" es directamente la fila `usuario` (no existe una entidad
   "paciente" separada) y un mismo `usuario_id` puede ser cliente de profesionales y negocios
   distintos. `02-backlog/backlog.md` (HU-20, nota de reconciliacion de Product Manager,
   2026-08-10) ya deja escrito que "`Cliente` sigue siendo una unica entidad compartida por todos
   los rubros... con estas columnas nullable" -- afirmacion correcta para la pregunta que
   responde (no hace falta una entidad separada por rubro), pero que **no debe leerse como
   autorizacion para agregar estas columnas directamente sobre el `usuario` global**: si se
   agregan ahi, quedan visibles para cualquier profesional que alguna vez atendio a esa persona,
   en cualquier negocio -- rompe RN7/D3 de raiz, no es un problema de RLS sino de donde vive el
   dato fisicamente. Ya hay precedente en el propio backlog para la ubicacion correcta: HU-19
   (activo/inactivo del paciente) y la definicion de "Reciente" (ambas en `02-backlog/backlog.md`,
   2026-08-10) ya se resolvieron explicitamente como "atributo propio del paciente, scope por
   profesional" -- el mismo criterio (una tabla o relacion scopeada por
   `(profesional_id, cliente_id)`, no columnas del `usuario` compartido) debe aplicarse a
   alergias/notas medicas/contacto de emergencia. No es una decision que le corresponda cerrar a
   Security (es modelado de datos, de DBA) -- se deja marcado en detalle porque es exactamente el
   tipo de gap que ningun test HTTP existente detectaria por si solo (mismo aprendizaje que
   dejaron CRITICAL-1 de este informe y el hallazgo de RLS del 2026-08-09: la autorizacion de
   aplicacion puede esconder un gap de modelado en vez de mostrarlo).
3. **Checklist tecnico que debe quedar resuelto antes de produccion con datos reales**
   (complementa, no reemplaza, el gate legal de Ley 25.326 que ya definio el CEO -- ver
   `02-backlog/backlog.md` HU-20 y `03-arquitectura/plan-produccion.md` parrafo 9):
   - Acceso restringido por profesional (no solo por negocio) para estos campos especificos, con
     una prueba de regresion automatica dedicada (mismo espiritu que
     `scripts/test-autorizacion-cruzada.mjs`: profesional A no debe poder leer/escribir los
     campos de salud de un paciente que nunca atendio, aunque comparta negocio con el profesional
     que si lo atendio).
   - Log de auditoria de accesos (lectura y escritura) a estos campos especificamente -- quien,
     cuando, sobre que paciente. No existe hoy ningun mecanismo de auditoria en el esquema; es
     una capacidad nueva, razonablemente barata de agregar ahora que DBA ya esta tocando este
     mismo esquema en paralelo, mas cara de retrofit despues.
   - Confirmar que el export de HU-22 (que ya declara en el backlog "solo su propia cartera")
     reusa efectivamente este mismo control de acceso por profesional para estos campos -- un
     export masivo es el vector de mayor impacto si el control de acceso tuviera un agujero.
     (Nota: `02-backlog/backlog.md` ya marca HU-22 como diferida para una revision de Security
     propia antes de construirse -- este punto queda como recordatorio para esa revision futura,
     no se resuelve aca.)
   - Restriccion de endpoints: solo los endpoints ya scopeados por profesional (ficha/historial)
     deberian poder leer o escribir estos campos -- ningun endpoint administrativo de negocio con
     alcance mas amplio.
4. **Cifrado a nivel de columna -- recomendado, no bloqueante en este ciclo.** A favor: ya esta
   confirmado (no es hipotetico) que en `docker-compose.yml` y en el contenedor de CI el rol de
   conexion a Postgres es superusuario y bypassea RLS siempre (ver el bloque "Separacion
   owner/runtime..." en `001_init.sql` y la entrada del 2026-08-09 en
   `memory/proyectos/turnos-profesionales/decisiones.md`) -- mientras ese gap no este cerrado en
   todos los ambientes (incluido Render, sin confirmar todavia), cifrar a nivel de columna las dos
   variables mas sensibles (alergias, notas medicas generales) seria una capa adicional que sigue
   protegiendo el dato aunque RLS quede bypaseada por un error de configuracion. En contra: agrega
   complejidad real (gestion de claves, y pierde la posibilidad de buscar/filtrar por esos campos
   en el backend salvo que se disene explicitamente para eso) que no se justifica **si** el punto
   1 (scope por profesional) y la separacion de roles owner/runtime ya pendiente para DevOps
   (`05-codigo/database/scripts/provisionar_roles_postgres.sql`) se cierran antes de cargar datos
   reales. Decision: no exigirlo como bloqueante de este ciclo; si para cuando el CEO tenga la
   confirmacion legal de su abogado sobre Ley 25.326 la separacion de roles owner/runtime todavia
   no esta cerrada en el ambiente de produccion real, reevaluar como bloqueante en ese momento.
5. **Contacto de emergencia -- nota aparte:** es un dato personal de un tercero (no del paciente),
   pero queda identificado y vinculado a una ficha de salud -- se recomienda tratarlo con el mismo
   criterio de acceso que alergias/notas medicas (puntos 1-3 arriba) aunque en sentido estricto no
   sea, por si mismo, un "dato de salud".

**Que puede esperar:** todo lo anterior es diseno/documentacion -- no bloquea Fases 3-5
(diseno/desarrollo/pruebas), tal como ya establecio el CEO para HU-20 en general. Es la lista
tecnica concreta que debe estar resuelta antes de que datos reales de pacientes lleguen a
produccion, en linea con (no en reemplazo de) el gate legal ya definido.

---

Ningun hallazgo de esta adenda fue remediado ni implementado por Security -- son decisiones de
diseno documentadas para que Backend/DBA las implementen cuando les toque, conforme a las reglas
de actuacion del rol.
