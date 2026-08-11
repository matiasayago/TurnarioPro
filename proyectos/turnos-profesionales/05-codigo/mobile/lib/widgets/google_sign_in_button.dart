/// HU-35 (login con Google, `02-backlog/backlog.md`) — botón "Google" de `login_screen.dart`
/// (wireframe en `04-diseno/mapa-pantallas.md` §5.17).
///
/// Alcance de este ciclo: **solo Web** (ver `08-despliegue/google-oauth.md` §2 Paso 4 — el
/// Client ID de tipo Android sigue bloqueado, no hay nombre de paquete ni SHA-1 definitivos
/// todavía). La implementación real (`google_sign_in_button_web.dart`) usa
/// `package:google_sign_in_web/web_only.dart`, que importa `dart:ui_web` — una librería que solo
/// existe al compilar para Web. Para que este archivo (y por lo tanto `login_screen.dart`, que
/// es una pantalla compartida por todas las plataformas) siga analizando/compilando sin romper el
/// día que se retome Android/iOS, la implementación real queda aislada detrás de un import
/// condicional: cualquier otra plataforma cae en `google_sign_in_button_stub.dart` (mismo botón
/// visual, siempre en estado "no disponible en esta plataforma" — no intenta ningún flujo real
/// todavía). Esto NO agrega configuración de Android — es un guard a nivel de Dart, no toca
/// `android/` ni ningún archivo de esa plataforma.
///
/// `dart.library.js_interop` (en vez de el más viejo `dart.library.html`) es el chequeo vigente
/// para "esto se está compilando para Web" — es la librería que ya usa `google_sign_in_web`
/// 1.1.3 internamente (junto con `package:web`, no con el `dart:html` en vías de dejar de usarse)
/// y sigue siendo válida tanto para el compilador JS clásico como para el más nuevo a WASM.
library;

export 'google_sign_in_button_stub.dart' if (dart.library.js_interop) 'google_sign_in_button_web.dart';
