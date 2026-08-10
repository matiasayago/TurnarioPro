/// Espaciado de `04-diseno/sistema-diseno.md` §5. Unidad base 4dp — usar siempre estos tokens
/// en vez de números sueltos (`SizedBox(height: 16)`) para que un cambio de escala futuro sea
/// un solo lugar.
class AppSpacing {
  const AppSpacing._();

  /// 4dp — separación entre ícono y texto.
  static const double xs = 4;

  /// 8dp — padding interno chico.
  static const double sm = 8;

  /// 12dp — separación entre elementos de una card.
  static const double md = 12;

  /// 16dp — padding estándar de card, margen de pantalla.
  static const double base = 16;

  /// 20dp — separación entre cards.
  static const double lg = 20;

  /// 24dp — separación entre secciones.
  static const double xl = 24;

  /// 32dp — márgenes superiores de pantalla, espacio antes de footer de modal.
  static const double xxl = 32;
}
