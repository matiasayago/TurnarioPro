import 'package:flutter/material.dart';

/// Radios y elevación de `04-diseno/sistema-diseno.md` §5.
class AppRadius {
  const AppRadius._();

  /// 16dp — tarjetas.
  static const double card = 16;

  /// 999dp (full pill) — chips, badges, status pills, botones.
  static const double chip = 999;

  /// 12dp — campos de texto, search bar.
  static const double input = 12;

  /// 20dp — esquinas superiores de bottom sheet / modal.
  static const double modalTop = 20;

  /// `elevation.card` (§5): sombra sutil de un solo nivel para tarjetas sobre `background`. Se
  /// expone como `List<BoxShadow>` listo para `BoxDecoration.boxShadow` en vez de depender del
  /// `CardTheme` de Material (evitamos el widget `Card` para tener control exacto de color +
  /// radio + sombra en un solo `Container`, sin que M3 le superponga su propio tinte de
  /// elevación). Igual en ambos temas — el documento no define una variante oscura distinta.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
      ];
}
