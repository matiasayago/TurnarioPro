# Login con Google (HU-35) — credenciales OAuth y gestión del secreto por entorno

**Rol:** DevOps (con Arquitecto)
**Fase:** 3/4 — Diseño → Desarrollo. Cierra la tercera y última pregunta abierta que
`../02-backlog/backlog.md` dejaba pendiente para HU-35 antes de que Backend/Mobile construyan el
flujo real (las otras dos, de DBA y de Security, ya están resueltas y en `main` — ver Entradas).
**Entradas:** `../02-backlog/backlog.md` (HU-35, aprobada por el CEO 2026-08-09);
`../03-arquitectura/modelo-datos.md` §2sexies (DBA, `usuario.password_hash` nullable +
`google_id`, ya en `main`); `../07-seguridad/informe-seguridad.md`, Adenda 2026-08-10 parte A
(Security, reglas de vinculación de cuentas, ya en `main`);
`../01-requisitos/documento-funcional.md`, D15 (alcance de plataformas); `./README.md`
(infraestructura ya existente de este proyecto: Dockerfile, docker-compose, CI, render.yaml).
**Salidas:** este documento (el plan); `../05-codigo/backend/.env.example` (variable nueva
documentada); `../05-codigo/backend/render.yaml` (variable nueva declarada, sin valor real).
**No incluye credenciales reales de Google** — ver §0.

## 0. Qué resuelve este documento y qué NO

Resuelve la pregunta que `../02-backlog/backlog.md` (HU-35) dejaba explícitamente abierta para
DevOps/Arquitecto: quién administra las credenciales OAuth de la aplicación en Google Cloud
Console (Client ID/secret) y cómo se gestionan como secreto en desarrollo local, CI y producción
(Render).

**No crea ninguna credencial real.** Igual que con las cuentas de Render/Google Play/Apple
Developer ya documentadas en `../03-arquitectura/plan-produccion.md` §8 y en `./README.md` §0,
ningún agente de IA puede crear un proyecto de Google Cloud ni sus credenciales — hace falta una
cuenta de Google real, del CEO o de quien administre la cuenta de Google de la empresa. Lo que
sigue es el instructivo para que esa persona lo ejecute cuando tenga tiempo (§2 y §7), más la
infraestructura de configuración para recibir el resultado sin que ningún valor real quede
commiteado en el repo (§3–§4).

**No implementa el endpoint de Backend ni el flujo de Mobile.** Ambos equipos quedan habilitados
para construir en paralelo, sin esperar a que existan credenciales reales: el criterio de gateo
de §5 (mismo espíritu que `ENABLE_DEV_ROUTES`, ver `../05-codigo/backend/src/app.ts`) es
justamente lo que permite avanzar en el código ya, y activar la funcionalidad después con un solo
cambio de configuración, sin volver a tocar código ni redeployar nada.

## 1. Enfoque técnico — confirmado: `google-auth-library`, verificación de ID token del lado del servidor

`google-auth-library` (paquete npm oficial de Google, la base sobre la que se apoya también el
paquete más grande `googleapis` — acá alcanza con la librería chica, no hace falta la completa)
es el enfoque correcto. No hay que reinventar nada.

**Cómo encaja en el flujo real (Mobile → Backend):**

1. El SDK de Google Sign-In del lado del cliente (en Android, y potencialmente en un build web de
   Flutter más adelante — ver la nota sobre "Web application" más abajo) resuelve el login de la
   persona contra Google y le entrega a la app un **ID token**: un JWT firmado por Google, con
   claims estándar de OpenID Connect (`sub`, `email`, `email_verified`, `name`, `picture`, `aud`,
   `iss`, `exp`).
2. Mobile manda ese ID token, tal cual, a un endpoint nuevo del backend (ilustrativo — el nombre
   final y el verbo/ruta exacta son decisión de Backend, coherente con el resto de
   `../05-codigo/backend/src/routes/auth.ts`: algo como `POST /auth/google`).
3. Backend usa `OAuth2Client` de `google-auth-library`:
   ```ts
   const client = new OAuth2Client(); // sin client secret, ver más abajo
   const ticket = await client.verifyIdToken({ idToken, audience: GOOGLE_CLIENT_ID });
   const payload = ticket.getPayload(); // sub, email, email_verified, name, picture...
   ```
   La librería descarga y cachea las claves públicas de Google, verifica la firma criptográfica
   del JWT, `exp` (no vencido), `iss` (`accounts.google.com`) y `aud` (coincide con el/los Client
   ID de `audience`) — todo local, sin ningún intercambio de red adicional con Google en el
   momento del login (más allá de refrescar las claves públicas cada tanto, cacheadas).
4. Con el payload ya verificado, Backend aplica la lógica de negocio que ya dejaron resueltas DBA
   y Security (buscar primero por `google_id`; alta nueva solo si `email_verified: true`; si ya
   existe una cuenta por contraseña con ese email, exigir confirmarla antes de vincular — ver
   Entradas) y, recién al final, emite el JWT **propio** del proyecto exactamente como hoy
   (`signToken`, `../05-codigo/backend/src/auth.ts`). Google nunca reemplaza la sesión de la app —
   es un método adicional de probar identidad antes de emitirla, en paralelo a como
   `bcrypt.compareSync` prueba identidad hoy para el login por contraseña. Ningún otro endpoint ni
   el resto del modelo de autorización (roles, `negocio_id`, RLS) cambia.

**No hace falta `GOOGLE_CLIENT_SECRET`** (confirmado — ver también §3). El flujo de arriba nunca
llama al endpoint de intercambio de token de Google (`grant_type=authorization_code`), que es el
único que pide un client secret; solo valida localmente un JWT que el cliente ya obtuvo por su
cuenta. Un client secret haría falta recién si este backend necesitara actuar en nombre de la
persona contra otras APIs de Google (Calendar, Gmail, etc.) — no es el caso de HU-35, que solo
necesita identificarla.

**Ya era, además, el estándar arquitectónico de la empresa** — `../03-arquitectura/lineamientos-tecnicos.md`
("Autenticación: OAuth2/OIDC + JWT") y `docs/05-arquitectura-microservicios.md` §8 ya fijaban
"OAuth2/OIDC + JWT" desde el inicio del proyecto, antes incluso de que existiera HU-35 — este
enfoque no es una desviación, es la aplicación concreta de un estándar que ya estaba escrito.

**Alternativas evaluadas y descartadas** (para que quede registrado el porqué, no solo la
conclusión):

- **Endpoint `tokeninfo` de Google** (`GET https://oauth2.googleapis.com/tokeninfo?id_token=`) en
  vez de una librería: funciona y evita agregar una dependencia, pero la propia documentación de
  Google lo desaconseja para producción (pensado para debugging, con límite de cuota) y recomienda
  explícitamente verificación local con una librería cliente. Descartado.
- **Flujo completo de Authorization Code** (redirect + intercambio de código por token con
  `client_secret`): es el flujo típico de una app web tradicional con sesión de servidor. Acá el
  SDK nativo de Google Sign-In del lado del cliente ya resuelve el login y entrega directamente un
  ID token — reconstruir además un flujo de redirect propio sería duplicar algo que Google
  Sign-In para apps/mobile ya resuelve, sumando superficie nueva (manejo de `client_secret`,
  `redirect_uri`, estado CSRF de redirect) sin necesidad real para HU-35. Solo se reconsideraría
  si la app necesitara en el futuro operar otras APIs de Google en nombre del usuario — no es el
  caso hoy.
- **Delegar todo el login (incluida la sesión) a Firebase Authentication**: evitaría verificar el
  ID token a mano, pero reemplazaría el JWT propio ya implementado y probado (con sus claims de
  dominio — `rol`, `negocio_id`, `profesional_id`) por el modelo de sesión de Firebase, un cambio
  de arquitectura mucho mayor al pedido puntual de HU-35 ("opción ADICIONAL, no un reemplazo", ver
  backlog) y una dependencia de plataforma nueva sin necesidad. Descartado por desproporcionado.

**Nota que matiza el pedido original de este ciclo — el Client ID "Web application" no es "para
el build web de Flutter", es la audiencia común entre plataformas.** El Client ID de tipo **"Web
application"** (§2, Paso 3) hace falta ya, incluso si el único target que se publica hoy es
Android (D15, §2 Paso 5): es la práctica estándar de Google Sign-In para que el backend tenga
**una sola audiencia** (`aud`) contra la que verificar, sin importar si el ID token lo emitió la
app Android o, más adelante, un build web. Se logra configurando el SDK de Google Sign-In de
Android para que pida el ID token con ese mismo Client ID web como **`serverClientId`** (el
nombre exacto del parámetro depende del paquete de Flutter que termine usando Mobile — a
confirmar contra su documentación vigente al implementar, ver §6). El Client ID de tipo "Android"
(§2, Paso 4) sigue siendo necesario igual, pero por otro motivo: autoriza que ESA app concreta
(nombre de paquete + huella SHA-1 de firma) pueda pedir el login — su valor de Client ID no se
copia a ningún código ni variable de entorno, a diferencia del Web.

## 2. Qué tiene que crear el CEO en Google Cloud Console (instructivo paso a paso)

Sin tecnicismos: esto es gratis (a diferencia de Google Play Console — USD 25 único — o Apple
Developer Program — USD 99/año —, ver `../03-arquitectura/plan-produccion.md` §8) y alcanza con
cualquier cuenta de Google normal, no hace falta una cuenta "de desarrollador" aparte ni una
organización de Google Workspace. Tiempo estimado para los Pasos 1 a 3 (lo único que no tiene
ninguna dependencia pendiente): 15–30 minutos.

Los nombres de menú de abajo son los vigentes al momento de escribir este documento — Google
reorganiza esta parte de la consola de tanto en tanto (la propia consola ya viene migrando esta
sección hacia un nombre nuevo, "Google Auth Platform", que agrupa lo mismo que antes vivía suelto
bajo "APIs & Services"). Si algún nombre no coincide exactamente con lo que se ve en pantalla,
buscar por "OAuth" en el buscador de la consola — el mismo criterio de "VERIFICAR contra la
interfaz vigente" que ya usa este proyecto para Render (ver `../05-codigo/backend/render.yaml` y
`./README.md` §5, mismo tipo de limitación: este entorno de desarrollo no tiene acceso a un
navegador para confirmar la UI en vivo).

### Paso 1 — Crear el proyecto de Google Cloud

1. Entrar a [console.cloud.google.com](https://console.cloud.google.com/) con la cuenta de Google
   que va a administrar esto.
2. Arriba a la izquierda, junto al logo "Google Cloud", hay un selector de proyecto → **"New
   Project"** ("Proyecto nuevo").
3. Nombre sugerido: algo identificable, ej. "Turnos Profesionales" o "Turnario Pro" (es el nombre
   interno del proyecto en Google Cloud — no lo ve ningún usuario final; lo que sí ven los
   usuarios es el "Nombre de la aplicación" del Paso 2). No hace falta asociarlo a ninguna
   organización.
4. Crear, y confirmar que quede seleccionado (mismo selector de arriba) antes de seguir.

### Paso 2 — Configurar la Pantalla de Consentimiento OAuth ("OAuth consent screen")

En criollo: es la pantalla que ve cualquier persona la primera vez que toca "Continuar con
Google" en la app — muestra el nombre de la app, quién la publica, y qué datos va a compartir
(acá: email, nombre y foto de perfil, nada más). Se completa una sola vez por proyecto.

1. Buscar **"OAuth consent screen"** (o la sección "Google Auth Platform" si la consola ya migró
   el nombre, ver arriba).
2. **"User Type"**: elegir **"External"** ("Externo") — es lo correcto para una app pública
   (clientes reservando turnos), no solo para una organización. "Internal" ni siquiera va a estar
   disponible salvo cuenta de Google Workspace.
3. Completar los datos obligatorios: nombre de la app (el que ve el usuario, ej. "Turnario Pro"),
   un email de soporte y un email de contacto de desarrollador. Logo y dominio son opcionales en
   este paso.
4. **Scopes** (permisos que pide la app): dejar únicamente los básicos — email, perfil e `openid`
   (`.../auth/userinfo.email`, `.../auth/userinfo.profile`, `openid`; suelen aparecer ya
   premarcados o listados primero, bajo la categoría "no sensibles"). No agregar ningún otro
   permiso — HU-35 solo necesita identificar a la persona (email, nombre, foto), no acceder a
   Gmail, Calendar, Drive ni nada más.
5. Guardar. El proyecto queda en estado **"Testing"** ("Prueba"): en ese estado solo pueden entrar
   hasta 100 personas agregadas a mano como "test users", y el acceso de cada una vence cada 7
   días — sirve para probar, no para producción real.
6. **Antes de que cualquier cliente real pueda usar "Continuar con Google", volver a esta pantalla
   y pasar el estado a "In production"** ("En producción"). Con los permisos básicos de arriba
   esto normalmente NO dispara la revisión manual más estricta de Google (esa revisión aplica a
   permisos "sensibles", que acá no se piden), pero sí puede pedir completar algún dato adicional
   obligatorio — por ejemplo la URL de política de privacidad, que este proyecto ya tiene anotada
   como pendiente compartido con la publicación en Google Play (ver
   `../03-arquitectura/plan-produccion.md`, ítem B9) — conviene resolver esa URL antes de llegar a
   este punto.

### Paso 3 — Crear el Client ID de tipo "Web application" (primero, sin dependencias pendientes)

1. Ir a **"Credentials"** ("Credenciales") — mismo menú de arriba.
2. **"+ Create Credentials"** → **"OAuth client ID"** ("ID de cliente de OAuth").
3. **"Application type"** ("Tipo de aplicación"): **"Web application"** ("Aplicación web").
4. Nombre interno (no lo ve el usuario final): ej. "Turnos Profesionales - Backend".
5. **"Authorized JavaScript origins" / "Authorized redirect URIs"**: se pueden dejar vacíos por
   ahora — no hacen falta para que el backend verifique tokens (§1). Si más adelante se agrega un
   login por Google desde un navegador (un build web de Flutter, o una versión futura de
   `../05-codigo/backend/web-preview/`), ahí sí hay que volver acá y agregar cada origen (ej.
   `http://localhost:3000` para desarrollo local, y el dominio real cuando exista) — no bloqueante
   para HU-35 tal como está planteada hoy (login nativo desde la app, no desde un navegador).
6. Crear. Google muestra un **Client ID** (con forma similar a
   `123456789012-abcdefghijklmnopqrstuvwxyz123456.apps.googleusercontent.com`) — **ese es el
   valor de `GOOGLE_CLIENT_ID`** (§3). También muestra un "Client secret" en esta misma pantalla —
   **no hace falta usarlo ni guardarlo en ningún lado** (§1 explica por qué); es el comportamiento
   estándar de la consola para este tipo de credencial, no pasa nada por dejarlo sin usar.

### Paso 4 — Client ID de tipo "Android" — bloqueado hasta resolver 2 datos que hoy no existen

Antes de completar este paso hacen falta dos datos que este proyecto todavía no tiene definidos.
No es algo que el CEO deba resolver solo — es trabajo de Arquitecto/Mobile; se deja marcado acá
como dependencia visible, no se asume ningún valor:

1. **El nombre de paquete (`applicationId`) definitivo de la app Android**, con forma de dominio
   invertido (ej. `com.turnarioPro.app` o similar — el valor real queda a definir). Hoy no existe:
   `../05-codigo/mobile` nunca corrió `flutter create` con una organización propia (ver
   `../05-codigo/mobile/README.md`, "Gap conocido"). El único lugar donde hoy se genera una
   carpeta `android/` es el CI (`../../../.github/workflows/turnos-mobile-ci.yml`,
   `flutter create --platforms=android .`, sin `--org`), que arma un nombre temporal
   (`com.example.turnos_profesionales`, el default de Flutter) pensado solo para compilar en el
   runner — nunca se commitea, y no está pensado para publicarse: el nombre de paquete de una app
   Android es, en la práctica, permanente una vez publicada en Google Play (cambiarlo después
   implica perder reseñas/instalaciones).
2. **La huella SHA-1 del certificado de firma de la app**, que sale de un keystore que tampoco
   existe todavía en este proyecto (ni uno de debug persistente ni uno de subida/release). Un
   SHA-1 de *debug* (el que genera automáticamente cada instalación de Android Studio/Gradle)
   alcanza para probar el login en desarrollo; el que importa para producción es el del
   certificado con el que se firme el build que suba a Google Play (el "certificado de
   subida"/upload key si se usa Play App Signing, recomendado) — tampoco existe todavía.

**Se puede crear igual más adelante, en cuanto Arquitecto/Mobile fijen el nombre de paquete y
exista al menos un SHA-1 de debug** — no bloquea nada de este documento ni el trabajo de Backend
en paralelo (§5: el endpoint funciona igual sin esto). Una vez resueltos esos 2 datos:

1. Mismo flujo del Paso 3 ("+ Create Credentials" → "OAuth client ID"), pero **"Application
   type": "Android"**.
2. Completar **"Package name"** y **"SHA-1 certificate fingerprint"** con los valores reales.
3. A diferencia del Web (un solo Client ID alcanza), es normal repetir este paso más de una vez —
   un Client ID Android por cada SHA-1 que haga falta autorizar (típicamente uno por certificado
   de debug de cada desarrollador/CI, y otro para el certificado de subida real de Play Store).
4. El "Client ID" que genera esta pantalla **no hace falta copiarlo a ningún lado** (ni Backend ni
   Mobile lo necesitan en código ni en variables de entorno) — a diferencia del Web Client ID del
   Paso 3, este solo existe para que Google reconozca a la app por nombre de paquete + SHA-1 en el
   momento del login. Confirmar este comportamiento contra la documentación vigente del paquete de
   Google Sign-In que use Mobile al implementar (§6) antes de darlo por sentado a ciegas.

### Paso 5 — Client ID de tipo "iOS": no crear todavía

`../01-requisitos/documento-funcional.md` (D15, ya confirmada por el CEO) fija el lanzamiento
inicial **solo para Android (Google Play)** — "iOS/App Store queda para una release posterior".
Coherente con eso, y con que este proyecto tampoco tiene carpeta `ios/` ni Bundle ID definido
(mismo tipo de gap que el Android del Paso 4, pero sin ningún dato resuelto todavía, ni siquiera
parcial), no corresponde crear un Client ID iOS en este ciclo — quedaría sin uso y sería una
credencial más para administrar sin necesidad real. Si más adelante se aprueba una release iOS,
este mismo documento (o su sucesor) es el lugar para agregar ese paso, con el Bundle ID real que
se defina en ese momento.

## 3. Variables de entorno

| Variable | ¿Hace falta? | Valor | Notas |
|---|---|---|---|
| `GOOGLE_CLIENT_ID` | Sí (nueva) | El Client ID de tipo "Web application" del Paso 3 (termina en `.apps.googleusercontent.com`) | Backend lo usa como `audience` al verificar el ID token (§1). **Mismo valor en todos los entornos** (local, Render) — a diferencia de `JWT_SECRET`, un Client ID de OAuth no es una clave criptográfica propia de este backend, es un identificador que Google ya conoce; lo que varía por entorno son los orígenes/redirects autorizados *dentro* de ese mismo Client ID en la consola (§2 Paso 3), no el valor en sí. Formato esperado: uno o más Client ID separados por coma, para poder aceptar más de una audiencia el día de mañana sin agregar una variable nueva — hoy alcanza con uno solo. |
| `GOOGLE_CLIENT_SECRET` | **No se define** | — | Confirmado en §1: el flujo de verificación de ID token del lado del servidor (`google-auth-library`, sin intercambio de código de autorización) no lo necesita. Ausencia deliberada, no un olvido — ver `.env.example` para el mismo comentario en el propio archivo. |

`../05-codigo/backend/.env.example` ya quedó actualizado con `GOOGLE_CLIENT_ID`, documentado con
el mismo nivel de detalle que el resto de las variables de ese archivo (ver el archivo
directamente para el texto completo).

## 4. Gestión del secreto por entorno

### 4.1 Local (`.env`)

Sin cambios de mecanismo: `.env` sigue gitignorado (`../05-codigo/backend/.gitignore`), nunca se
commitea, y `.env.example` (§3) documenta la entrada nueva igual que las demás. Cada desarrollador
completa `GOOGLE_CLIENT_ID` con el mismo valor real (§3) una vez que exista.

`docker-compose.yml` **no necesita ningún cambio**: el servicio `backend` ya usa
`env_file: .env` (ver `../05-codigo/backend/docker-compose.yml`), así que cualquier variable
agregada a `.env` — incluida `GOOGLE_CLIENT_ID` — se propaga sola al contenedor, sin declarar nada
aparte en ese archivo.

### 4.2 CI (`../../../.github/workflows/turnos-backend-ci.yml`)

**Decisión: no configurar `GOOGLE_CLIENT_ID` en CI, y no modificar el workflow.** No van a existir
credenciales reales de Google disponibles en CI, y HU-35 no bloquea nada del resto del backlog
(mismo criterio ya usado para las otras dos preguntas de esta historia, ver
`../02-backlog/backlog.md`). Con el criterio de gateo de §5, esto no requiere ningún mock: sin
`GOOGLE_CLIENT_ID` seteada, pegarle al endpoint de Google devuelve 503 de forma determinística —
exactamente el mismo comportamiento que tendría cualquier entorno todavía sin configurar, sin
tocar la red ni simular nada de Google. Es, de hecho, el camino más simple de los dos que
planteaba este ciclo (frente a construir un mock de la respuesta de Google) y no deja ninguna
cobertura real sin probar: no hay lógica de Google que CI pueda ejercitar sin credenciales reales
de todos modos (verificar una firma JWT contra las claves públicas de Google *requiere* un ID
token real, emitido por Google, que este entorno no puede producir).

**Recomendación para Backend (no implementada acá, no bloqueante):** cuando se implemente el
endpoint, vale la pena agregar un script más a `../05-codigo/backend/scripts/*.mjs` que confirme
el 503 (`GOOGLE_CLIENT_ID` ausente → respuesta clara, no un 500 ni un crash) — es un test gratis
del propio criterio de gateo, se ejecuta solo con el servidor ya arriba (mismo patrón que el resto
de esa batería) y no necesita ningún dato ni mock de Google.

Por lo mismo, **este ciclo no modifica `../../../.github/workflows/turnos-backend-ci.yml`**: el
estado recomendado (variable ausente) ya es exactamente el estado actual, sin cambios.

### 4.3 Render (producción)

`../05-codigo/backend/render.yaml` ya declara:

```yaml
- key: GOOGLE_CLIENT_ID
  sync: false
```

`sync: false` es el mismo mecanismo que un Blueprint de Render usa para cualquier valor que tiene
que cargarse a mano desde el dashboard, sin escribirlo nunca en el repo — no hay `generateValue`
posible acá (a diferencia de `JWT_SECRET`: Render no puede "generar" un Client ID, ese valor lo
define Google) y tampoco corresponde escribir un valor real en este archivo (no existe uno
todavía, y aunque existiera, no es buena práctica commitear configuración de entorno aunque no
sea estrictamente secreta — ver la nota sobre esto en el propio comentario del archivo). Mismo
patrón que ya usa `JWT_SECRET` en espíritu (ningún valor real en el repo), aunque con un mecanismo
distinto porque la naturaleza del valor es distinta (Render no puede inventar un Client ID como sí
genera un secreto propio).

El servicio real (`turnos-profesionales-backend`, ver
`memory/proyectos/turnos-profesionales/decisiones.md`, ya desplegado y activo en
`https://turnos-profesionales-backend.onrender.com`) ya está conectado a este Blueprint desde
ciclos anteriores. Agregar esta entrada acá **no carga ningún valor real por sí sola** — el flujo
esperado (a confirmar contra el dashboard real al aplicar este cambio, mismo criterio de
"VERIFICAR" que ya usa el resto de este archivo, ver §5/§9 de `./README.md`) es que Render detecte
la clave nueva en el próximo sync del Blueprint y la deje pendiente de completar a mano en el
dashboard del servicio (Environment), sin afectar ninguna otra variable ya configurada
(`DATABASE_URL`, `JWT_SECRET`, `PORT`, `ENABLE_DEV_ROUTES`) ni disparar ningún deploy
(`autoDeploy: false` sigue vigente, ver §9 de `./README.md` — ningún cambio llega a producción sin
aprobación previa). Si por algún motivo el sync automático del Blueprint no recogiera la clave
nueva, alcanza con agregar `GOOGLE_CLIENT_ID` a mano en el dashboard del servicio (Environment →
Add Environment Variable) — con o sin esta entrada en `render.yaml`, el servicio la lee igual
(`process.env.GOOGLE_CLIENT_ID`); este archivo es documentación/plantilla declarativa, no la única
forma de cargar una variable en Render.

**Migración de base de datos, prerrequisito aparte, ya documentado, no de este ciclo:** que
`GOOGLE_CLIENT_ID` esté cargada no alcanza por sí sola para que el login con Google funcione en
producción — todavía hace falta correr a mano
`../05-codigo/database/migrations/002_pacientes_historial_auth_google.sql` contra la base de
Render (agrega `usuario.google_id` y vuelve nullable `password_hash`), pendiente real ya señalado
en `../02-backlog/backlog.md` (HU-35) y en `memory/proyectos/turnos-profesionales/decisiones.md`
— no es un pendiente nuevo de este documento, se referencia acá para que quede completo el
panorama de qué falta antes de un login con Google real en producción.

## 5. Mientras no existan credenciales reales: criterio de gateo del endpoint

Backend construye el endpoint completo ya, en paralelo a este documento, sin esperar a que
existan credenciales reales — para eso sirve fijar el nombre de la variable ahora (§3).

**Al arrancar, el proceso NO debe fallar si falta `GOOGLE_CLIENT_ID`** — a diferencia de
`JWT_SECRET`, que si falta en producción frena el arranque de TODO el proceso
(`../05-codigo/backend/src/auth.ts`, hallazgo HIGH-3): `GOOGLE_CLIENT_ID` gatea una única
funcionalidad opcional, no la base de la aplicación — el login por contraseña sigue siendo el
único método obligatorio, HU-35 es "una opción ADICIONAL, no un reemplazo" (backlog.md, HU-35).

**Tampoco conviene copiar tal cual el patrón de `ENABLE_DEV_ROUTES`**
(`../05-codigo/backend/src/app.ts`): ese gatea montando o no TODO un router — si no está
habilitado, pegarle a esas rutas da 404, indistinguible de "la ruta no existe". Para el endpoint
de Google eso sería confuso: Mobile/QA no podrían distinguir "todavía no está configurado en este
entorno" de "la URL está mal" o "es un bug". Ahí la diferencia tiene sentido: `/dev/*` necesita
ocultarse por motivos de seguridad (HIGH-4); el endpoint de Google no tiene ese motivo — no hay
nada sensible en que exista, solo en que funcione sin configuración real.

**Recomendación:** montar el endpoint/router SIEMPRE, y como primera verificación dentro del
handler (o en un middleware propio de esa sola ruta), devolver **503** con un mensaje claro si
`GOOGLE_CLIENT_ID` no está seteada — ilustrativo, la implementación final es de Backend:

```ts
if (!process.env.GOOGLE_CLIENT_ID) {
  return res.status(503).json({ error: 'Login con Google no está disponible todavía en este entorno' });
}
```

503 (Service Unavailable) y no 501 (Not Implemented): la funcionalidad SÍ está implementada,
temporalmente no está configurada — 503 comunica "va a funcionar apenas se configure" mejor que
501 ("nunca implementado acá").

Este criterio es, además, exactamente lo que hoy pasa en CI (§4.2) sin necesitar ningún mock: como
CI nunca setea `GOOGLE_CLIENT_ID`, pegarle al endpoint da 503 de forma determinística — un test
barato del propio criterio de gateo, sin tocar la red ni simular nada de Google.

Una vez que el CEO cargue el valor real en cada entorno (§4), el endpoint empieza a funcionar sin
ningún otro cambio de código ni de deploy — mismo criterio de "opt-in explícito, nunca un crash
silencioso" que este proyecto ya aplica de forma consistente (`ENABLE_DEV_ROUTES`, `JWT_SECRET`),
adaptado acá a una tercera variante (opt-in explícito, con un error claro en vez de una ruta
invisible) porque la naturaleza del caso es distinta a las otras dos.

## 6. Dependencias y bloqueos abiertos (resumen)

| Ítem | Bloquea | Dueño | Estado |
|---|---|---|---|
| Proyecto de Google Cloud + Client ID Web (§2, Pasos 1 y 3) | Que el endpoint funcione con datos reales — no bloquea construirlo (§5) | CEO | **Resuelto y confirmado en Render** (DevOps, 2026-08-22 — ver §9) |
| Pantalla de consentimiento OAuth pasada de "Testing" a "In production" (§2, Paso 2, punto 6) | Que cualquier cliente real (no solo test users) pueda usar "Continuar con Google" | CEO | No verificable desde este test — ver §9 |
| Nombre de paquete Android definitivo | Client ID Android (§2, Paso 4) | Arquitecto/Mobile | Pendiente, no resuelto en este documento |
| Keystore de firma (debug + subida) y su SHA-1 | Client ID Android (§2, Paso 4) | Mobile/DevOps | Pendiente, no resuelto en este documento |
| Confirmar el parámetro `serverClientId` (o equivalente) en el paquete de Google Sign-In que use Mobile | Que el ID token de Android traiga `aud = GOOGLE_CLIENT_ID` (web) (§1) | Mobile, coordinado con Backend | Pendiente de implementación, no de este documento |
| Client ID iOS | — | — | No crear todavía (D15, §2 Paso 5) |
| Aplicar `002_pacientes_historial_auth_google.sql` contra Render | Que `google_id`/`password_hash` nullable existan en producción (§4.3) | DBA/DevOps | Pendiente, ya documentado antes de este ciclo (`../02-backlog/backlog.md`, `memory/proyectos/turnos-profesionales/decisiones.md`) |
| Implementación del endpoint en Backend | Que HU-35 funcione de punta a punta | Backend | No bloqueada por nada de este documento — puede empezar ya (§5) |
| Implementación del flujo en Mobile | Que HU-35 funcione de punta a punta | Mobile | No bloqueada por nada de este documento — puede empezar ya; probar contra credenciales reales sí requiere al menos el Client ID Web + un Android de debug |

Ninguno de estos ítems bloquea el resto del backlog (mismo criterio ya establecido para las otras
dos preguntas de HU-35, ver `../02-backlog/backlog.md`).

## 7. Checklist para el CEO (resumen ejecutivo, sin tecnicismos)

- [x] Crear el proyecto en Google Cloud Console — gratis, cualquier cuenta de Google (§2, Paso 1).
      Confirmado indirectamente (§9): no puede existir un Client ID Web funcional sin este paso.
- [ ] Completar la Pantalla de Consentimiento OAuth, tipo "External", con permisos básicos
      únicamente (email, perfil) (§2, Paso 2). Prerrequisito de hecho del paso siguiente (la
      consola de Google no deja crear credenciales OAuth sin esto), pero no se verificó de forma
      independiente — no confundir con el punto de abajo ("In production"), que sí sigue abierto.
- [x] Crear el Client ID **"Web application"** (§2, Paso 3) — este es el valor que hay que
      entregarle a Backend/DevOps como `GOOGLE_CLIENT_ID`. No hace falta el "Client secret" que
      Google muestra al lado. **Confirmado cargado y funcionando en Render (§9).**
- [ ] Cuando Arquitecto/Mobile confirmen el nombre de paquete Android y exista al menos un SHA-1
      de debug: crear el Client ID **"Android"** (§2, Paso 4) — no bloquea nada de lo anterior, se
      puede hacer después.
- [ ] No crear todavía el Client ID **"iOS"** (§2, Paso 5).
- [ ] Antes de que cualquier cliente real use "Continuar con Google": volver a la Pantalla de
      Consentimiento y pasar el estado de "Testing" a **"In production"** (§2, Paso 2, punto 6) —
      puede pedir la URL de política de privacidad (ya es un pendiente compartido con Google Play,
      ver `../03-arquitectura/plan-produccion.md` ítem B9). **Sigue sin verificar — ver §9**, el
      comportamiento del endpoint del backend es idéntico en "Testing" o "In production", así que
      ningún test contra el backend puede confirmar ni descartar este punto.
- [x] Entregar el Client ID Web a DevOps/Backend para cargarlo como `GOOGLE_CLIENT_ID` en el
      dashboard de Render del servicio `turnos-profesionales-backend` (§4.3) — no hace falta
      tratarlo con el mismo secreto que una contraseña (§1/§3), pero tampoco conviene publicarlo
      más de lo necesario. **Ya cargado y confirmado (§9).**

## 8. Registro de este ciclo (motivo, cambios, forma de rollback)

**Motivo:** cerrar la tercera pregunta abierta de HU-35 (administración de credenciales OAuth),
pedida explícitamente al rol DevOps (con Arquitecto) en `../02-backlog/backlog.md`, para que
Backend/Mobile puedan empezar a construir el flujo real sin quedar bloqueados por la falta de
credenciales reales.

**Cambios incluidos:**
- Este documento (nuevo).
- `../05-codigo/backend/.env.example` — entrada `GOOGLE_CLIENT_ID` documentada.
- `../05-codigo/backend/render.yaml` — entrada `GOOGLE_CLIENT_ID` (`sync: false`) declarada, sin
  valor.
- `../02-backlog/backlog.md` — la pregunta abierta de HU-35 para DevOps marcada como resuelta, con
  puntero a este documento (mismo patrón que ya usaron DBA y Security para sus propias preguntas
  de esta historia).
- `memory/proyectos/turnos-profesionales/decisiones.md` — entrada nueva con el resumen de esta
  decisión, para que otros agentes la reutilicen sin releer este documento completo.

**No se tocó:** código de Backend (`../05-codigo/backend/src/`) ni de Mobile
(`../05-codigo/mobile/lib/`) — los implementan esos roles en paralelo, no este ciclo;
`docker-compose.yml` (ya propaga `.env` completo al contenedor vía `env_file`, sin necesitar una
entrada propia para esta variable, ver §4.1); `../../../.github/workflows/turnos-backend-ci.yml`
(la recomendación de §4.2 es no setear nada ahí, que es exactamente el estado actual, sin cambios
que aplicar).

**Ninguna credencial real se creó en este ciclo** — ver §0: ningún agente de IA puede crear el
proyecto de Google Cloud ni sus Client ID.

**Nota operativa — concurrencia real detectada al empezar este ciclo.** Al crear la rama
`feature/google-oauth-plan` en el directorio de trabajo principal se encontró al agente de Backend
trabajando en paralelo, en vivo, sobre ese mismo directorio (implementando el endpoint real de
HU-35 en su propia rama, `feature/google-oauth-backend` — coincide con lo esperado,
`../02-backlog/backlog.md` HU-35: DevOps resuelve este plan, Backend construye el endpoint en
paralelo). El primer `git checkout -b` de este ciclo movió sin querer la rama activa de ese
directorio compartido, arrastrando cambios sin commitear de Backend. Se revirtió de inmediato
(`git checkout` de vuelta a `feature/google-oauth-backend`, dejando ese directorio exactamente
como lo tenía Backend) y el resto de este ciclo — todo lo que aparece en §0–§7, más las ediciones
a `.env.example`/`render.yaml`/`backlog.md`/`memory/` — se hizo en un git worktree aislado
(`git worktree add`), sin volver a tocar el directorio de trabajo principal. No se perdió ningún
cambio de Backend; no se commiteó nada ajeno a este ciclo.

**No se validó `render.yaml` con un parser de YAML real en este ciclo** (a diferencia de ciclos
anteriores de este mismo archivo, que sí pudieron usar `js-yaml` — no está disponible en este
entorno esta vez, y este ciclo no instaló nada nuevo para no dejar dependencias sueltas por una
sola verificación puntual). Mitigación: el bloque agregado repite al carácter la indentación y la
forma de los bloques vecinos ya validados (`ENABLE_DEV_ROUTES`, mismo nivel de `- key:`/propiedad
anidada), se revisó a mano, y se corrió un script chico de Node (sin entender gramática YAML real
— no reemplaza a `js-yaml`) que confirmó ausencia de tabs y que todos los `- key:` del bloque
`envVars:` —incluido el nuevo— quedan a 6 espacios de indentación, consistente con el resto del
archivo. La primera confirmación real de que el YAML sigue siendo válido es, como para el resto de
este archivo, el próximo run de CI en verde (el job `docker-build-smoke` no depende de
`render.yaml`, pero cualquier herramienta que Render use para parsear el Blueprint al sincronizar
sí lo va a validar en los hechos la primera vez que se aplique).

**Forma de rollback:** revertir los archivos de este ciclo (este documento, `.env.example`,
`render.yaml`, la entrada de `backlog.md`, la entrada de `memory/`). Es un cambio de solo
documentación/plantilla — ninguna variable con valor real llegó a existir en ningún entorno
todavía (el Client ID real no existe), así que no hay ningún dato ni configuración real en
producción que revertir aparte del propio archivo. Particularidad de `render.yaml`: si en el
futuro alguien ya cargó un valor real de `GOOGLE_CLIENT_ID` a mano en el dashboard de Render y
después se revierte este `render.yaml`, ese valor cargado a mano queda intacto — un Blueprint de
Render no borra variables del servicio por dejar de declararlas (mismo criterio ya documentado
para el resto de este archivo). Ningún rollback, igual que ningún forward-deploy, ocurre sin
aprobación previa (`docs/04-manual-operativo.md`, reglas de actuación de DevOps).

## 9. Confirmación de carga en Render — DevOps (2026-08-22)

**Motivo:** encargo puntual de DevOps (Director General IA) para cargar `GOOGLE_CLIENT_ID` en el
dashboard de Render del servicio `turnos-profesionales-backend` y confirmar con un test HTTP real
que `POST /auth/google` deje de responder 503. El encargo asumía como punto de partida que la
variable **todavía no** estaba cargada — antes de repetir cualquier paso del dashboard, este ciclo
verificó primero el estado real en vez de asumir el punto de partida del encargo.

**Resultado de esa verificación: la variable ya estaba cargada y funcionando desde antes de este
ciclo**, no en este ciclo. `memory/project_turnos_profesionales_infra.md` (nota de infraestructura,
entrada sobre el bug de `MP_ACCESS_TOKEN`/`MP_WEBHOOK_SECRET` del 2026-08-17) ya dejaba registrado,
de paso, que "`GOOGLE_CLIENT_ID` (mismo mecanismo `sync: false`, cargada en una sesión anterior) sí
funciona" — sin una fecha exacta de cuándo el CEO la cargó, ni un ciclo de DevOps que lo documentara
en su momento en este archivo. Este ciclo cierra ese vacío de documentación y agrega verificación
propia contra el servicio real, en vez de aceptar el antecedente sin más.

**Verificación propia contra `https://turnos-profesionales-backend.onrender.com` (2026-08-22):**

1. `GET /health` → `{"ok":true}` — servicio arriba, sin necesitar ningún redeploy para esta
   verificación.
2. `POST /auth/google` con el payload tal como lo sugería el encargo original (`{"idToken":"test"}`,
   camelCase) → **400**
   `{"error":"Datos inválidos","detalles":{"id_token":["Invalid input: expected string, received undefined"]}}`.
   Ya cumple el criterio original de "no 503", aunque por un motivo más superficial: el endpoint
   real espera el campo en snake_case (`googleBodySchema` en `../05-codigo/backend/src/routes/auth.ts`
   línea 266: `z.object({ id_token: z.string()... })`), no `idToken`.
3. `POST /auth/google` con el nombre de campo correcto (`{"id_token":"test"}`) → **401**
   `{"error":"Token de Google inválido"}`. Esta es la confirmación fuerte, no la de arriba: por
   `verificarIdTokenGoogle` (mismo archivo, líneas 230–256), el único camino hacia ese 401 es que
   `process.env.GOOGLE_CLIENT_ID` ya haya pasado el chequeo `if (!clientId)` de la línea 231-234 (que
   devuelve 503 inmediatamente si la variable falta) y el código haya llegado a invocar
   `googleOAuthClient.verifyIdToken(...)`, que falla porque el string `"test"` no tiene forma de JWT
   — capturado por el `catch` que responde 401. Un 401 acá es evidencia directa de que la variable
   está seteada con algún valor en el proceso real de Render en este momento, no una inferencia.

**Qué NO quedó verificado en este ciclo (límite honesto, mismo criterio que el resto de este
documento) — este entorno de desarrollo sigue sin acceso al dashboard de Render** (sin navegador,
sin `RENDER_API_KEY`/CLI configurado; mismo tipo de limitación ya documentada en `./README.md`
§0/§5, y confirmado de nuevo en este ciclo: ni `render` CLI ni ninguna variable `RENDER_*` están
disponibles en este entorno):

- No se pudo entrar a Environment del servicio para leer a simple vista el valor exacto cargado, ni
  revisar los logs de deploy desde la consola — la verificación de arriba (comportamiento HTTP real
  del proceso vivo) es evidencia más directa que un log de texto para esta pregunta puntual
  ("¿el proceso tiene la variable seteada?"), pero no reemplaza una inspección visual del dashboard
  si en algún momento hiciera falta por otro motivo.
- No se pudo confirmar que el valor cargado sea efectivamente el Client ID "Web application" real
  emitido por Google Cloud Console (a diferencia de cualquier otro string no vacío): el chequeo de
  `auth.ts` solo verifica presencia/no-vacío, no valida el contenido. Solo un login real de Mobile
  contra un ID token emitido de verdad por Google podría confirmar esto de punta a punta — pendiente
  de Mobile, no de este ciclo.
- No se pudo confirmar si la Pantalla de Consentimiento OAuth ya pasó de "Testing" a
  "In production" (§2 Paso 2, punto 6; checklist §7) — el comportamiento del endpoint del backend
  es idéntico en ambos estados, así que ningún test contra el backend puede confirmarlo ni
  descartarlo. Sigue como pendiente explícito del CEO antes del lanzamiento público real.
- No se disparó ningún redeploy — no hacía falta: el servicio ya viene respondiendo con la
  variable cargada desde antes de este ciclo.

**No se modificó `render.yaml` en este ciclo** — ya declaraba `GOOGLE_CLIENT_ID` con `sync: false`
y sin valor, que sigue siendo el estado final correcto (nunca escribir el valor real en el repo,
ver §4.3); no hay ningún cambio "si aplica" que aplicar acá, el archivo ya estaba bien.

**§6 y §7 de este documento actualizados** para reflejar este cierre (fila de Client ID Web en §6
pasa de "Pendiente" a resuelta; en el checklist de §7 se marcan como hechos los 3 puntos que este
test puede confirmar — crear el proyecto, crear el Client ID Web, cargarlo en Render — dejando
explícitamente sin marcar los que este ciclo no pudo verificar, en vez de darlos por buenos).

**Forma de rollback:** ninguna acción de este ciclo requiere rollback — no se cargó ningún valor
nuevo (ya estaba cargado de antes), no se tocó código ni `render.yaml`, solo se confirmó un estado
ya existente y se actualizó documentación/memoria. Si en el futuro hiciera falta rotar el Client ID
(p. ej. por sospecha de uso indebido, aunque no es secreto por diseño — ver §1/§3), el procedimiento
es: crear un Client ID nuevo en Google Cloud Console (§2 Paso 3) y reemplazar el valor a mano en el
dashboard de Render (Environment) — no requiere cambios de código ni de `render.yaml`.
