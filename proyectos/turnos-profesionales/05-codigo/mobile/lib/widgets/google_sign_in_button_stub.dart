import 'package:flutter/material.dart';

import 'buttons.dart';
import 'google_logo.dart';

/// Fallback para cualquier plataforma sin implementación real de Google Sign-In todavía (hoy:
/// todo lo que no sea Web — ver `google_sign_in_button.dart` para el import condicional que elige
/// entre este archivo y `google_sign_in_button_web.dart`). Alcance de esta tanda de HU-35 es
/// explícitamente solo Web (`02-backlog/backlog.md`, `08-despliegue/google-oauth.md` §2 Paso 4:
/// Client ID Android todavía bloqueado) — este stub deja el botón visible con el mismo aspecto
/// que el estado "no configurado" de la implementación Web, para que la pantalla nunca crashee
/// en una plataforma que todavía no tiene el flujo real, en vez de omitir el botón en silencio.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onSignedIn,
    required this.onError,
    required this.onUnavailable,
  });

  /// Se invoca con `(idToken, email)` al completar un login de Google exitoso. No se usa en este
  /// stub (no hay ningún flujo real todavía en esta plataforma) — se mantiene en la firma para
  /// que sea intercambiable con `google_sign_in_button_web.dart` sin que `login_screen.dart`
  /// necesite saber cuál de las dos implementaciones terminó resolviendo el import condicional.
  final void Function(String idToken, String email) onSignedIn;

  /// Se invoca con un mensaje legible ante un error del SDK de Google ya iniciado. No se usa en
  /// este stub, mismo motivo que [onSignedIn].
  final void Function(String message) onError;

  /// Se invoca al tocar el botón mientras Google Sign-In no está disponible. En este stub es
  /// SIEMPRE el callback que se dispara (no hay ningún caso "disponible" todavía).
  final VoidCallback onUnavailable;

  @override
  Widget build(BuildContext context) {
    return OutlineButton(
      label: 'Google',
      leading: const GoogleLogo(),
      radiusVariant: AppButtonRadius.card,
      onPressed: onUnavailable,
    );
  }
}
