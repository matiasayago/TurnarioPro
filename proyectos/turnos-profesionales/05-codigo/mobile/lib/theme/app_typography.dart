import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Escala tipográfica de `04-diseno/sistema-diseno.md` §4. Fuente Roboto, forzada también en
/// iOS para consistencia visual (una sola app Flutter, un solo lenguaje visual) — Flutter ya
/// empaqueta Roboto en el engine como familia "Roboto" en todas las plataformas, así que fijar
/// `fontFamily: 'Roboto'` acá no requiere agregar fuentes ni dependencias nuevas a pubspec.yaml.
///
/// Cada estilo devuelve un `TextStyle` ya resuelto (color incluido) para el tema activo, para
/// que ninguna pantalla tenga que combinar tamaño/peso con color por su cuenta. `buttonLabel` es
/// la excepción: su color depende de la variante del botón (`onPrimary`, blanco fijo, etc.), así
/// que lo recibe como parámetro en vez de asumir uno.
class AppTypography {
  const AppTypography._();

  static const String _fontFamily = 'Roboto';

  /// §4: título de pantalla ("Dashboard", "Gestión de Horarios") — 26sp Bold, `textPrimary`.
  static TextStyle displayTitle(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).textPrimary,
      );

  /// §4: título de card/sección/modal — 18sp SemiBold, `textPrimary`.
  static TextStyle sectionTitle(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.of(context).textPrimary,
      );

  /// §4: subtítulos, nombre en fila de lista — 15sp Medium, `textSecondary` por defecto (pasar
  /// `color:` explícito vía `.copyWith` cuando el contexto pida `textPrimary`, ver §4).
  static TextStyle subtitle(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.of(context).textSecondary,
      );

  /// §4: texto de contenido general — 14sp Regular, `textPrimary`.
  static TextStyle body(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.of(context).textPrimary,
      );

  /// §4: texto de ayuda, timestamps, notas pequeñas — 12sp Regular, `textSecondary`.
  static TextStyle caption(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.of(context).textSecondary,
      );

  /// §4: número grande en stat card — 30sp Bold, `textPrimary` (pasar `color: primary` vía
  /// `.copyWith` cuando la stat card sea de énfasis, ver `StatCard.emphasize`).
  static TextStyle statNumber(BuildContext context) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: AppColors.of(context).textPrimary,
      );

  /// §4: texto de botones — 15sp SemiBold, +0.2 letter-spacing. El color varía según la
  /// variante del botón (`onPrimary`, blanco fijo en `WarningButton`/`SuccessButton`,
  /// `textPrimary` en `OutlineButton`), así que se recibe explícito.
  static TextStyle buttonLabel(BuildContext context, {required Color color}) => TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color,
      );
}
