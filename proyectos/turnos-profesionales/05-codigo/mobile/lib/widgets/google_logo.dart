import 'package:flutter/material.dart';

/// Logo de Google (la "G" multicolor) para el botón "Google" del login (HU-35,
/// `04-diseno/mapa-pantallas.md` §5.17). `OutlineButton.icon` solo acepta un `IconData` de
/// Material (un solo color) — no alcanza para representar la marca real de Google, que es
/// multicolor. Se usa en cambio este asset propio (`assets/branding/google_logo.png`), tal cual
/// lo publica Google en sus lineamientos de marca para armar botones de "Sign in with Google"
/// (ver developers.google.com/identity/branding-guidelines) — bundleado en el repo (declarado en
/// `pubspec.yaml`) en vez de cargado por red, para no depender de que Google siga sirviendo ese
/// archivo en esa URL ni de tener conexión en cada render.
///
/// Usado tanto por el estado "no configurado" (`google_sign_in_button_web.dart`,
/// `GOOGLE_CLIENT_ID` vacío) como por el fallback no-web (`google_sign_in_button_stub.dart`) —
/// cuando SÍ hay Client ID configurado en Web, el botón real lo renderiza el SDK de Google
/// (`google_sign_in_web`, ver ese archivo) con su propio logo, este asset no aplica ahí.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/google_logo.png',
      width: size,
      height: size,
    );
  }
}
