# Mobile — Turnos Profesionales (Flutter)

App única con dos modos (Cliente / Profesional) según el rol del usuario autenticado — ver
`../../04-diseno/mapa-pantallas.md`.

## ✅ Estado (slice original, hasta HU-15): compilación verificada por CI (2026-08-06)

**Actualización (HU-35, este ciclo):** el entorno de desarrollo pasó a tener el SDK de Flutter
instalado (`C:\flutter`, 3.44.9 estable, con soporte Web/Chrome — `flutter doctor` sigue sin
Android SDK ni Visual Studio, así que Android/Windows desktop siguen sin poder compilarse acá,
pero eso no afecta a Web) — a diferencia de lo que dice el párrafo original de abajo (dejado tal
cual, como registro histórico de cuándo se escribió). Con eso, el cambio de HU-35 sí se verificó
localmente y de punta a punta para el target Web: `flutter pub get`, `flutter analyze` (limpio,
sin ningún hallazgo en el código nuevo — el único "info" que reporta es preexistente y ajeno a
este cambio, en `dashboard_screen.dart`) y `flutter build web` (compila y bundlea el asset del
logo de Google correctamente). No se instaló el SDK de Android en este ciclo — sigue sin poder
compilarse `flutter build apk` localmente, sin cambios respecto del párrafo original.

Este entorno de desarrollo sigue sin el SDK de Flutter (ni Dart standalone) instalado, así que
a diferencia del backend (que sí se instaló, corrió y se probó de punta a punta, ver
`../backend/README.md`), acá no se puede ejecutar el compilador localmente. En su lugar, desde
2026-08-06 hay un workflow de GitHub Actions
(`.github/workflows/turnos-mobile-ci.yml`, con el SDK oficial de Flutter) que corre en cada
push/PR que toca este directorio y da, por primera vez, **verificación real** (no solo revisión
manual): `flutter pub get` + `flutter analyze` + `flutter build apk --debug` — los tres en
verde para el slice original (run de referencia:
[31110105801](https://github.com/matiasayago/TurnarioPro/actions/runs/31110105801)).

En el primer intento, `flutter analyze` encontró 2 deprecaciones reales del SDK de Flutter (no
bugs de lógica) que se corrigieron:
- `DropdownButtonFormField.value` → `initialValue`.
- `Color.withOpacity(x)` → `Color.withValues(alpha: x)` (`screens/profesional/excepciones_screen.dart`).

**Gap conocido, documentado a propósito en vez de resolverlo a ciegas:** este directorio nunca
tuvo `android/` ni `ios/` (se escribió a mano, sin correr nunca `flutter create`) — el CI genera
`android/` al vuelo con `flutter create --platforms=android .` antes de compilar, pero eso pasa
solo dentro del runner de GitHub Actions y **no se commitea al repo**. Para correr esta app en
un emulador/dispositivo real (`flutter run`), hace falta primero generar esas carpetas de forma
permanente:

```bash
flutter create --platforms=android,ios .   # agrega android/ e ios/ sin tocar pubspec.yaml ni lib/
flutter pub get
flutter analyze
flutter run
```

en una máquina con el SDK de Flutter instalado.

## 🆕 Rediseño "Turnario Pro" (sistema de diseño + Dashboard + Gestión de Horarios) — sin correr por CI todavía

Se agregó el sistema de diseño completo (`lib/theme/`, `lib/widgets/`) y se reconstruyó el lado
Profesional del bottom nav a partir de `04-diseno/sistema-diseno.md` y `04-diseno/mapa-pantallas.md`
(ambos ya verificados por UX/UI contra 37 capturas reales de la app de referencia, incluidas sus
secciones "bis" de corrección). Este bloque de trabajo **todavía no pasó por el CI real** (se
escribió sin poder compilar localmente, igual que el resto de este proyecto) — la próxima corrida
de `turnos-mobile-ci.yml` después de subir estos cambios es la primera verificación real. Se hizo
una revisión manual rigurosa (sintaxis Dart, imports cruzados entre los ~18 archivos nuevos,
nombres de `Icons.*`/APIs de `ColorScheme`/`Semantics` contra los que ya se sabía que compilaban en
este mismo proyecto o de los que hay alta confianza), pero no reemplaza al compilador.

Novedades:
- `lib/theme/`: `app_colors.dart` (tokens + `ThemeExtension` para los 4 estados semánticos +
  `primaryPressed`, resto de tokens resuelto vía `ColorScheme`/`ThemeData`), `app_typography.dart`,
  `app_spacing.dart`, `app_radius.dart`, `app_theme.dart` (`ThemeData` claro/oscuro). Alternable en
  vivo vía `lib/state/theme_controller.dart` (`ThemeMode.system` por defecto), ya conectado en
  `main.dart` — falta únicamente el control visual en Configuración (pantalla placeholder por
  ahora, ver abajo).
- `lib/widgets/`: `PrimaryButton`/`WarningButton`/`SuccessButton`/`OutlineButton`, `StatusPill`,
  `StatCard`/`StatCardGrid`, `NumericStepperField`, `MonthCalendarPicker`, `AppBottomNavigationBar`,
  `AppHeader`, `AppModalSheet` — importar todos desde el barrel `lib/widgets/widgets.dart`.
- `lib/screens/profesional/dashboard_screen.dart` (nueva, HU-27) y
  `lib/screens/profesional/gestion_horarios_screen.dart` (**reemplaza** a la antigua
  `definir_disponibilidad_screen.dart`, ya borrada).
- `lib/screens/profesional/profesional_shell.dart`: nuevo punto de entrada del rol Profesional
  (antes era `AgendaScreen` directo), dueño del `AppBottomNavigationBar` de 6 ítems reales
  (Dashboard, Horarios, Pacientes, WhatsApp, Notificaciones, Configuración). Las últimas 4 son
  `ProximamenteScreen` (placeholder) — no se construyeron en este ciclo a propósito.
  `AgendaScreen` (HU-06) dejó de ser una pestaña raíz: ahora se accede desde "Ver agenda >" del
  Dashboard, y perdió su bottom nav propio (lo reemplaza el del shell) quedándose solo con la
  acción "Bloquear rango" → `ExcepcionesScreen`.
- `MisClientesScreen`/`ConfiguracionServiciosScreen` (versión previa, más simple) quedan sin
  referenciar desde la navegación activa — no se borraron (siguen compilando solas) porque no son
  el alcance de este ciclo, pero no se puede llegar a ellas navegando la app; candidatas a
  reemplazo cuando se construya "Gestión de Pacientes" (HU-10+HU-19) con el lenguaje visual nuevo.

## 🆕 Bottom nav del lado Cliente (`ClienteShell`) — sin correr por CI todavía

El lado Cliente nunca tuvo navegación persistente (cada pantalla era suelta, sin forma de moverse
entre secciones salvo el flujo lineal de reserva) — gap detectado probando la app en vivo, no
parte del rediseño "Turnario Pro" original (que fue exclusivamente del lado Profesional). Ya
estaba diseñado en `04-diseno/mapa-pantallas.md` §3, solo faltaba construirlo.

- `lib/screens/cliente/cliente_shell.dart`: nuevo punto de entrada del rol Cliente en `main.dart`
  (antes era `BuscarNegociosScreen` directo), mismo patrón exacto que `profesional_shell.dart`
  (`IndexedStack` + `AppBottomNavigationBar`, 4 ítems: Buscar, Mis Turnos, Notificaciones,
  Configuración). Buscar (HU-00b) y Mis Turnos (HU-12/HU-13) son las pantallas ya existentes sin
  cambios de contenido; Notificaciones y Configuración son `ProximamenteScreen` (sin backend
  todavía — Notificaciones no tiene endpoint, Configuración de Cliente no fue pedida en esta
  ronda).
- `ProximamenteScreen` se movió de `lib/screens/profesional/` a `lib/widgets/` (ahora la usan
  ambos modos) y se agregó al barrel `lib/widgets/widgets.dart`.
- `BuscarNegociosScreen` perdió el ícono de atajo a "Mis turnos" de su `AppBar` (quedó redundante
  con la pestaña nueva, y tapaba la bottom nav al empujar una pantalla completa por encima del
  shell). El flujo de reserva (Detalle de Negocio → Elegir Profesional → Horarios Disponibles →
  Confirmar Turno) sigue siendo un stack normal empujado por encima del shell, sin cambios —
  confirmado que ninguna de esas pantallas asume un `Navigator.pop()` a una pantalla específica.

### Gaps de backend documentados en el propio código (no inventados, no silenciados)

- El backend (`estado_turno` en `migrations/001_init.sql`) no tiene un estado "completado" ni
  endpoint para transicionar un turno — "Marcar como completada" del Dashboard es una simulación
  **local a la sesión** (no persiste), documentada en `dashboard_screen.dart`.
- El modelo de disponibilidad es recurrente por día de semana (`dia_semana` 0–6), no por fecha
  puntual — `gestion_horarios_screen.dart` deja elegir fechas puntuales en el calendario (fiel al
  wireframe) y las traduce a día de semana al guardar, contra el endpoint real
  `POST /profesionales/:id/disponibilidad`. "Duración de Citas" sí tiene endpoint real
  (`PATCH /profesionales/:id/configuracion`) y se guarda en la misma acción. "Citas Máximas por
  Día", "Anticipación de Reservas", "Tiempo de Descanso" y "Replicar en semanas/meses" quedan
  totalmente interactivos (estado local) pero sin backend propio todavía — ver
  `02-backlog/backlog.md` HU-16 pregunta abierta #1.
- El Dashboard no tiene forma de mostrar el nombre real del profesional ("¡Hola, Dr. García!" del
  wireframe): el JWT solo trae `sub`/`rol`/`negocio_id`/`profesional_id` (ver `src/auth.ts` del
  backend), sin `nombre` — se usa un saludo genérico en vez de inventar un dato.

## Bug encontrado y corregido en revisión manual (slice original)

`ApiClient.get()` devuelve `Future<dynamic>`. Escribir `api.get(path) as Future<List<dynamic>>`
castea el **Future**, no el valor que resuelve, y falla en runtime (`TypeError`). Se corrigió
agregando `ApiClient.getList()` / `ApiClient.getMap()`, que esperan la respuesta y castean el
valor ya resuelto — todas las pantallas usan estos helpers, no `get()` directo con cast.

## Cómo correr contra el backend

El backend expone `http://localhost:3000` (ver `../backend/README.md`). Desde un emulador
Android, `localhost` del host se accede como `10.0.2.2` — ya configurado como default en
`lib/api_client.dart`. Desde un dispositivo físico o iOS, cambiar `ApiClient(baseUrl: ...)` en
`lib/main.dart` a la IP de la máquina que corre el backend.

## Login con Google (HU-35) — solo Web en este ciclo

`02-backlog/backlog.md` (HU-35). Alcance de este ciclo: **únicamente el target Web**
(`flutter run -d chrome` / `-d web-server`) — Android queda explícitamente afuera (el Client ID
de tipo Android todavía está bloqueado, ver `../../08-despliegue/google-oauth.md` §2 Paso 4: no
existe nombre de paquete definitivo ni SHA-1 de firma para este proyecto todavía). No hay ninguna
configuración de Android agregada por este cambio.

**Paquete instalado:** `google_sign_in: ^7.2.0` (+ `google_sign_in_web: ^1.1.3` como dependencia
directa, necesaria para `renderButton` — ver el porqué en el doc comment de
`lib/widgets/google_sign_in_button_web.dart`). Es la versión con la API nueva (desde 7.0.0,
breaking change: `GoogleSignIn.instance` singleton + `initialize()` obligatorio antes que
cualquier otro método) — **no** el patrón viejo `GoogleSignIn(clientId: ...)` + `signIn()` de
versiones anteriores a la 6.0, que ya no existe en esta versión.

**Cómo se pasa el Client ID:** por variable de compilación, **nunca hardcodeado**:
`GOOGLE_CLIENT_ID` se lee con `String.fromEnvironment('GOOGLE_CLIENT_ID')`
(`lib/widgets/google_sign_in_button_web.dart`) y se pasa a
`GoogleSignIn.instance.initialize(clientId: ...)` recién ahí. Para correr o buildear con Google
habilitado:

```bash
flutter run -d chrome --web-hostname localhost --web-port 7357 \
  --dart-define=GOOGLE_CLIENT_ID=TU_CLIENT_ID.apps.googleusercontent.com
```

- El Client ID es el de tipo **"Web application"** (`../../08-despliegue/google-oauth.md` §2
  Paso 3) — no el de tipo Android (que ni siquiera existe todavía, ver arriba).
- **`--web-hostname`/`--web-port` fijos, no son opcionales acá:** `flutter run -d chrome` sin
  esas flags elige un puerto aleatorio en cada corrida, y el SDK de Google (Google Identity
  Services) solo funciona desde orígenes que estén cargados en la lista "Authorized JavaScript
  origins" del Client ID en Google Cloud Console (`../../08-despliegue/google-oauth.md` §2 Paso
  3, punto 5 — se dejó vacía a propósito hasta este punto). Con un puerto fijo alcanza con cargar
  ese origen (ej. `http://localhost:7357`) una sola vez. Mismo mecanismo para `flutter build web`
  servido detrás de un dominio real: ese dominio también tiene que estar en esa misma lista.
- Sin `--dart-define=GOOGLE_CLIENT_ID=...` (o con un valor vacío), el botón "Google" se sigue
  mostrando, pero al tocarlo avisa "Login con Google no está disponible en este momento" en vez
  de intentar inicializar el SDK — mismo espíritu que el 503 que ya devuelve el backend cuando
  falta esa misma variable del lado del servidor (`../backend/src/routes/auth.ts`,
  `verificarIdTokenGoogle`). Para probar ese flujo de éxito de punta a punta hace falta además
  que el backend tenga su propio `GOOGLE_CLIENT_ID` cargado (`../backend/.env`, mismo valor) —
  ver `../backend/README.md`.

**Archivos nuevos de este ciclo:**
- `lib/widgets/google_sign_in_button.dart` — export condicional (`dart.library.js_interop`) entre
  la implementación real (`_web.dart`) y un fallback (`_stub.dart`) para cualquier otra
  plataforma, para que `login_screen.dart` (pantalla compartida por todas las plataformas) no
  rompa el día que se retome Android/iOS — `google_sign_in_web` importa `dart:ui_web`, que solo
  existe compilando para Web.
- `lib/widgets/google_sign_in_button_web.dart` — la implementación real. Nota importante: en Web,
  `google_sign_in` 7.x **no admite un botón propio de la app que dispare el login** —
  `GoogleSignIn.instance.authenticate()` tira `UnimplementedError` a propósito en esta
  plataforma; el único login interactivo soportado es el botón que renderiza el SDK de Google
  (`google_sign_in_web`'s `renderButton`). Se configura lo más cerca posible del criterio de
  `04-diseno/sistema-diseno.md` §7.1bis (outline, radio moderado — no píldora) que da el propio
  SDK (`theme: outline`, `shape: rectangular`), pero **no es** el `OutlineButton` del sistema de
  diseño pixel a pixel — es el botón real de Google, requisito de la plataforma, no una elección
  de estilo. Ese `OutlineButton` sí se usa tal cual (con el logo de Google,
  `lib/widgets/google_logo.dart`) para el estado "no disponible" (sin `GOOGLE_CLIENT_ID` o con
  el SDK sin poder inicializar).
- `lib/widgets/google_sign_in_button_stub.dart` — fallback no-web (hoy: siempre "no disponible").
- `lib/widgets/google_logo.dart` — logo de Google para el botón propio del sistema de diseño
  (`assets/branding/google_logo.png`, asset propio publicado por Google para este uso — ver
  developers.google.com/identity/branding-guidelines).

## 🆕 Configuración del lado Profesional: Perfil, Privacidad, Consultorio, Pagos, Reportes

Conecta 6 ítems de `configuracion_screen.dart` (antes `ProximamenteScreen`) a los 9 endpoints
nuevos de Backend (`usuario.ts`/`negocios.ts`/`profesionales.ts`, ver
`memory/proyectos/turnos-profesionales/decisiones.md`) y agrega 2 pantallas estáticas. Detalle
completo en el doc comment de cada pantalla nueva, todas en
`lib/screens/profesional/`: `editar_perfil_screen.dart`, `privacidad_screen.dart`,
`configuracion_consultorio_screen.dart` (de solo lectura — el backend soporta edición vía
`PATCH /negocios/:id`, pero exige rol `administrador`, que esta app todavía no tiene UI propia
para representar), `precios_senas_screen.dart` (guardado por fila, no un botón general),
`reportes_screen.dart` (pantalla nueva, con selector de período Todo/7 días/Mes/Año),
`ayuda_soporte_screen.dart` y `acerca_de_screen.dart` (estáticas, sin backend). "Configuración de
Pagos" (Panel Profesional) y "Pagos y Señas" (su propia sección) navegan a la misma pantalla
(`precios_senas_screen.dart`) — mismo backend real (seña por servicio, HU-04b) detrás de ambos
ítems. `flutter analyze` corrido localmente (SDK disponible en este entorno): limpio, sin
hallazgos nuevos.

## 🆕 Branding real de la app (ícono, ícono adaptativo de Android, splash, logo en login)

Los 3 assets provistos por el CEO (`icon.png`, `adaptive-icon.png`, `splash-icon.png` — misma
imagen, un ícono con degradado azul→violeta y una "T" fusionada con un motivo de reloj) viven en
`assets/icon/` (fuente original sin procesar en `../../04-diseno/Iconos/`). Se integran vía dos
paquetes estándar de Flutter en vez de tocar cada plataforma a mano:

- `flutter_launcher_icons.yaml`: ícono nativo Android/iOS + favicon/PWA icons de `web/`.
  `adaptive_icon_background` usa `#6C7FE0` (el mismo `AppPalette.primaryLight` de
  `lib/theme/app_colors.dart`, no un hex inventado) porque los PNG del CEO no traen un foreground
  aislado con transparencia. Este proyecto todavía **no tiene `android/`/`ios/`** (no se corrió
  `flutter create --platforms=android,ios .`) — las secciones de esas plataformas quedan
  configuradas igual, listas para cuando esas carpetas existan; ver el comentario al inicio del
  archivo sobre por qué generar con Android/iOS habilitados falla en duro hoy (aborta antes de
  llegar a `web`) y cómo se generó `web` en este estado transitorio.
- `flutter_native_splash.yaml`: splash con el mismo logo, color `#F7F8FA` (= `scaffoldBackgroundColor`
  claro) para que no haya salto de color al primer frame real. Sin variante dark configurada a
  propósito — el PNG trae su fondo horneado en blanco opaco, no transparente (ver comentario en el
  archivo).
- `lib/screens/login_screen.dart`: el logo (`assets/icon/icon.png`) se muestra arriba del
  formulario, envuelto en `ClipRRect(AppRadius.card)` — sin este wrapper, el fondo blanco opaco del
  PNG se ve como un recorte cuadrado de esquinas filosas sobre el fondo oscuro del tema; con él se
  lee como una tarjeta de logo intencional.
- `web/` (favicon, `manifest.json`, `icons/`, `splash/`, `index.html`) quedó commiteado esta vez —
  hasta ahora se mantenía fuera de git como herramienta local de verificación (sigue pendiente la
  decisión sobre CI de Flutter Web, no relacionada con esto).

Verificado con `flutter analyze` (limpio) y visualmente sirviendo `flutter build web` (el modo
`flutter run -d web-server` está roto en este entorno por un bug de DWDS ajeno a este cambio —
`TypeError` en `dwds/src/injected/client.js` al deserializar un evento de debug — no bloquea builds
de producción).

## Pantallas implementadas (ver mapa completo en `04-diseno/mapa-pantallas.md`)

**Cliente:** Login (+ Google, HU-35, solo Web — ver sección propia arriba), `ClienteShell` (bottom
nav de 4 ítems, ver sección de arriba), Buscar Negocios (HU-00b), Detalle de Negocio/Servicios
(HU-07), Elegir Profesional (HU-08), Horarios Disponibles (HU-09), Confirmar Turno (HU-09b), Mis
Turnos (HU-12), Reprogramar Turno (HU-13). Las pantallas del flujo de reserva y Mis Turnos siguen
con el `ThemeData` genérico anterior a este ciclo (el rediseño visual "Turnario Pro" fue
exclusivamente del lado Profesional, según lo pedido); solo el `ClienteShell`/`AppBottomNavigationBar`
y el botón de Google usan piezas del sistema de diseño nuevo. No incluye "Crear Cuenta" ni
"¿Olvidaste tu contraseña?" — `mapa-pantallas.md` §5.17 documenta que esas dos partes no se
capturaron, quedan fuera de HU-35. Notificaciones y Configuración (Cliente): placeholders
"Próximamente".

**Profesional:** Dashboard (HU-27, nueva), Gestión de Horarios (HU-05 + HU-16 + HU-18, reemplaza a
"Definir Disponibilidad"), Agenda semanal (HU-06, reubicada), Excepciones (HU-15), Mis Clientes
(HU-10) y Configuración de Servicios (HU-04b) — estas dos últimas ya no están en la navegación
activa (ver arriba), Historial de Visitas (HU-11), Gestión de Pacientes + Ficha de Paciente
(HU-10+HU-19, HU-20). Configuración: menú real (Tema, Cerrar Sesión, Editar Perfil, Privacidad y
Seguridad, Configuración de Consultorio, Precios y Señas, Reportes y Estadísticas, Ayuda y
Soporte, Acerca de — ver sección "🆕 Configuración del lado Profesional" arriba).
WhatsApp/Notificaciones/Idioma/Turnario Pro/Nueva Cita/Autorizaciones Médicas: placeholders
"Próximamente".

## Simplificaciones deliberadas de este slice (no son bugs, son alcance reducido)

- El selector de servicio en las pantallas del profesional (Excepciones, Configuración de
  Servicios, Gestión de Horarios) es un campo de texto libre con el ID del servicio, no un
  dropdown poblado desde la API — se resuelve en una siguiente iteración.
- No hay registro de negocio/cliente desde la app (HU-00a se hizo vía API en las pruebas del
  backend) — falta la pantalla de registro.
- No hay checkout de pago real embebido — la pantalla de Confirmar Turno solo avisa que se
  requiere seña (el backend usa un Mock de Mercado Pago, ver
  `../backend/src/integraciones/pagos.ts`).
- Tema claro/oscuro: implementado de punta a punta en `lib/theme/` (ver sección de rediseño
  arriba), no se probó visualmente por no poder correr la app.
- **Login (contraseña y Google) no maneja todavía la respuesta con `negocios: [...]`** que manda
  el backend cuando un profesional/administrador tiene 0 o 2+ negocios activos (JWT sin
  `negocio_id`, ver `responderLoginConNegocios` en `../backend/src/routes/auth.ts`) — tanto
  `_login()` como el nuevo `_iniciarConGoogle()` de `login_screen.dart` toman `resp['token']` sin
  distinguir ese caso, igual que ya hacía el login por contraseña antes de HU-35. Es el mismo gap
  ya documentado en el backlog para HU-27 ("cambiar de vista" — implementado en Backend, falta el
  selector en Mobile), no uno nuevo introducido por Google.
