import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

import 'buttons.dart';
import 'google_logo.dart';

/// Client ID de OAuth de Google (HU-35, `08-despliegue/google-oauth.md` §3) — NUNCA hardcodeado:
/// se lee de una variable de compilación (`--dart-define=GOOGLE_CLIENT_ID=...` al correr/buildear,
/// ver README.md de este proyecto). Vacío (default de `String.fromEnvironment` sin ese
/// `--dart-define`) significa "Google no está configurado en este build" — mismo criterio de
/// opt-in explícito que ya usa el backend con `GOOGLE_CLIENT_ID`/`ENABLE_DEV_ROUTES` (ver
/// `src/routes/auth.ts`, `src/app.ts`): el botón se sigue mostrando, pero no intenta inicializar
/// el SDK de Google, y avisa en vez de fallar silenciosamente al tocarlo.
const String _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

/// `GoogleSignIn.instance.initialize()` solo se puede llamar UNA vez por vida del proceso —
/// llamarlo de nuevo tira `StateError` (ver el propio paquete, `google_sign_in_web`
/// `GoogleSignInPlugin.init`). Como `GoogleSignInButton` se puede volver a montar más de una vez
/// (ej. el usuario inicia sesión con Google, después cierra sesión, y vuelve a esta pantalla), la
/// inicialización se cachea acá a nivel de módulo — sobrevive a que el widget se desmonte y
/// remonte, y sigue resolviendo la MISMA instancia de `Future` en cada intento.
Future<void>? _googleSignInInitFuture;

Future<void> _ensureGoogleSignInInitialized() {
  return _googleSignInInitFuture ??= GoogleSignIn.instance.initialize(clientId: _googleClientId);
}

/// Botón "Google" de `login_screen.dart` (HU-35) — implementación real para Web.
///
/// **Por qué esto no es un botón propio del sistema de diseño (`OutlineButton` liso) que llame a
/// un método tipo `signIn()`, a diferencia de Android/iOS:** a partir de `google_sign_in` 7.x, la
/// implementación Web (`google_sign_in_web`, basada en el SDK "Google Identity Services" de
/// Google) **no soporta un flujo interactivo disparado por UI propia** —
/// `GoogleSignIn.instance.authenticate()` tira `UnimplementedError` en Web a propósito
/// (`supportsAuthenticate()` devuelve `false`); el propio README del paquete lo explica: "user
/// initiated sign in on web must use a button rendered by the sign in SDK, rather than
/// application-provided UI". La única forma soportada de un login interactivo en Web es
/// [gsi_web.renderButton], el botón que arma Google mismo (vía un `<iframe>`/elemento embebido) —
/// no un `Widget` de Flutter que se pueda restylear a píxel exacto. Se configura con
/// [gsi_web.GSIButtonConfiguration] lo más cerca posible del criterio de
/// `sistema-diseno.md` §7.1bis (outline, radio moderado — no píldora): `theme: outline`,
/// `shape: rectangular` (Google solo ofrece `rectangular` o `pill`; `rectangular` es la variante
/// "no píldora", aunque su radio exacto no es configurable y no coincide pixel a pixel con
/// `AppRadius.card`). Confirmado contra el código fuente del paquete instalado en este ciclo
/// (`google_sign_in_web` 1.1.3) — no se asumió el patrón viejo de `GoogleSignIn(clientId: ...)` +
/// `signIn()` de versiones anteriores a la 6.0 (que en Web tampoco hubiera funcionado igual: ya
/// desde la migración a Google Identity Services el flujo interactivo en Web requiere el botón
/// propio del SDK).
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({
    super.key,
    required this.onSignedIn,
    required this.onError,
    required this.onUnavailable,
  });

  /// Se invoca con `(idToken, email)` al completar un login de Google exitoso — `login_screen.dart`
  /// hace el resto (`POST /auth/google`, etc.).
  final void Function(String idToken, String email) onSignedIn;

  /// Se invoca con un mensaje legible ante un error del SDK de Google ya en curso (login
  /// inicializado pero el intento falló) — ej. no se pudo cargar el SDK, o Google no devolvió un
  /// id_token utilizable.
  final void Function(String message) onError;

  /// Se invoca al tocar el botón mientras Google Sign-In no está disponible en este entorno
  /// (`GOOGLE_CLIENT_ID` vacío, o falló la inicialización del SDK).
  final VoidCallback onUnavailable;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  Future<void>? _initFuture;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  @override
  void initState() {
    super.initState();
    if (_googleClientId.isNotEmpty) {
      _initFuture = _ensureGoogleSignInInitialized();
      _authSub = GoogleSignIn.instance.authenticationEvents.listen(_onAuthEvent, onError: _onAuthStreamError);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _onAuthEvent(GoogleSignInAuthenticationEvent event) {
    if (event is! GoogleSignInAuthenticationEventSignIn) {
      // GoogleSignInAuthenticationEventSignOut: esta pantalla es Login, no tiene sesión de
      // Google activa todavía de la que "desloguearse" — no se espera este evento acá.
      return;
    }
    final idToken = event.user.authentication.idToken;
    if (idToken == null) {
      widget.onError('Google no devolvió un token de identidad válido. Probá de nuevo.');
      return;
    }
    widget.onSignedIn(idToken, event.user.email);
  }

  void _onAuthStreamError(Object error, StackTrace stack) {
    if (error is GoogleSignInException && error.code == GoogleSignInExceptionCode.canceled) {
      return; // La persona cerró el selector de cuenta de Google — no es un error para mostrar.
    }
    widget.onError('No se pudo iniciar sesión con Google. Probá de nuevo.');
  }

  Widget _fallback(VoidCallback onPressed) {
    return OutlineButton(
      label: 'Google',
      leading: const GoogleLogo(),
      radiusVariant: AppButtonRadius.card,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_googleClientId.isEmpty) {
      return _fallback(widget.onUnavailable);
    }

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 50,
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))),
          );
        }
        if (snapshot.hasError) {
          // No se pudo inicializar el SDK (ej. Client ID inválido, no se pudo cargar el script de
          // Google) — mismo fallback visual que "no configurado", pero avisa con `onError` en vez
          // de `onUnavailable` porque acá sí había una configuración, solo que falló.
          return _fallback(() => widget.onError('No se pudo inicializar el login con Google. Probá de nuevo más tarde.'));
        }
        // Botón real del SDK de Google — ver el porqué en el doc comment de la clase.
        return Align(
          child: gsi_web.renderButton(
            configuration: gsi_web.GSIButtonConfiguration(
              theme: gsi_web.GSIButtonTheme.outline,
              shape: gsi_web.GSIButtonShape.rectangular,
              size: gsi_web.GSIButtonSize.large,
              text: gsi_web.GSIButtonText.signinWith,
              logoAlignment: gsi_web.GSIButtonLogoAlignment.left,
              minimumWidth: 400,
              locale: 'es',
            ),
          ),
        );
      },
    );
  }
}
