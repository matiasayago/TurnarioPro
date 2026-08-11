# Mobile — Turnos Profesionales (Flutter)

App única con dos modos (Cliente / Profesional) según el rol del usuario autenticado — ver
`../../04-diseno/mapa-pantallas.md`.

## ✅ Estado (slice original, hasta HU-15): compilación verificada por CI (2026-08-06)

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

## Pantallas implementadas (ver mapa completo en `04-diseno/mapa-pantallas.md`)

**Cliente:** Login, `ClienteShell` (bottom nav de 4 ítems, ver sección de arriba), Buscar Negocios
(HU-00b), Detalle de Negocio/Servicios (HU-07), Elegir Profesional (HU-08), Horarios Disponibles
(HU-09), Confirmar Turno (HU-09b), Mis Turnos (HU-12), Reprogramar Turno (HU-13). Las pantallas
del flujo de reserva y Mis Turnos siguen con el `ThemeData` genérico anterior a este ciclo (el
rediseño visual "Turnario Pro" fue exclusivamente del lado Profesional, según lo pedido); solo el
`ClienteShell` y su `AppBottomNavigationBar` usan el sistema de diseño nuevo. Notificaciones y
Configuración (Cliente): placeholders "Próximamente".

**Profesional:** Dashboard (HU-27, nueva), Gestión de Horarios (HU-05 + HU-16 + HU-18, reemplaza a
"Definir Disponibilidad"), Agenda semanal (HU-06, reubicada), Excepciones (HU-15), Mis Clientes
(HU-10) y Configuración de Servicios (HU-04b) — estas dos últimas ya no están en la navegación
activa (ver arriba), Historial de Visitas (HU-11). Pacientes/WhatsApp/Notificaciones/Configuración:
placeholders "Próximamente".

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
