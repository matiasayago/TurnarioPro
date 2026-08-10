import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';

/// Arma el `ThemeData` claro y oscuro completos a partir de los tokens de `app_colors.dart`
/// (§3/§8 de `sistema-diseno.md`). Se parte de `ColorScheme.fromSeed` (para que Material rellene
/// de forma razonable los roles que el sistema de diseño no especifica, ej. `secondary`,
/// `tertiary`, `shadow`) y se pisan con `copyWith` únicamente los roles que sí están definidos
/// explícitamente por el sistema de diseño — así no se hardcodea un `ColorScheme` completo a
/// mano ni se depende de que el seed por sí solo produzca nuestros hex exactos.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final seeded = ColorScheme.fromSeed(
      seedColor: isDark ? AppPalette.primaryDark : AppPalette.primaryLight,
      brightness: brightness,
    );

    final colorScheme = seeded.copyWith(
      primary: isDark ? AppPalette.primaryDark : AppPalette.primaryLight,
      onPrimary: isDark ? AppPalette.onPrimaryDark : AppPalette.onPrimaryLight,
      primaryContainer: isDark ? AppPalette.primaryContainerDark : AppPalette.primaryContainerLight,
      onPrimaryContainer: isDark ? AppPalette.textPrimaryDark : AppPalette.textPrimaryLight,
      // `background` (fondo de pantalla, §3.2) → ColorScheme.surface: ver nota de mapeo en
      // AppColors.
      surface: isDark ? AppPalette.backgroundDark : AppPalette.backgroundLight,
      onSurface: isDark ? AppPalette.textPrimaryDark : AppPalette.textPrimaryLight,
      onSurfaceVariant: isDark ? AppPalette.textSecondaryDark : AppPalette.textSecondaryLight,
      // `surface` (tarjeta, §3.2) → surfaceContainerLowest: superficie elevada distinta del
      // fondo de pantalla.
      surfaceContainerLowest: isDark ? AppPalette.surfaceDark : AppPalette.surfaceLight,
      outlineVariant: isDark ? AppPalette.borderDark : AppPalette.borderLight,
    );

    final tokens = isDark ? AppColorTokens.dark : AppColorTokens.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      // §4: Roboto forzada en toda la app, incluido iOS (ver nota en app_typography.dart).
      fontFamily: 'Roboto',
      disabledColor: isDark ? AppPalette.textDisabledDark : AppPalette.textDisabledLight,
      dividerColor: colorScheme.outlineVariant,
      extensions: [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );
  }
}
