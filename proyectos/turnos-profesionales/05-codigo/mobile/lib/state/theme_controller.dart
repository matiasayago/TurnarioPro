import 'package:flutter/material.dart';

/// Estado del modo de tema (claro/oscuro/sistema), compartido por toda la app vía `Provider`
/// (ver `main.dart`) — sistema-diseno.md §8: "el cambio de tema debe poder alternarse sin
/// reiniciar la app y respetar la preferencia del sistema operativo por defecto". `ThemeMode`
/// por defecto es `system`, que ya delega en el SO; `setThemeMode` permite al usuario forzar
/// claro/oscuro explícitamente y, al notificar, `MaterialApp` se reconstruye con el nuevo modo
/// sin perder el estado de navegación (no hay restart).
///
/// Nota de alcance: el control visual para elegir el modo (Configuración → Tema) todavía no se
/// construye en este ciclo — la pantalla de Configuración del Profesional queda como placeholder
/// (ver `widgets/proximamente_screen.dart`). Esta clase deja la infraestructura
/// lista para que ese control futuro solo tenga que llamar a `setThemeMode`.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  void setThemeMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
  }
}
