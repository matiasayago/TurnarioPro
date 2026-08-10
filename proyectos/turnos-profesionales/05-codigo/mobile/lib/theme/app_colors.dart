import 'package:flutter/material.dart';

/// Paleta cruda (hex) del sistema de diseño — ver
/// `04-diseno/sistema-diseno.md` §3 (claro) y §8 (oscuro), corregida contra capturas reales en
/// §3bis. Estos son los ÚNICOS literales de color de hex de toda la app: ninguna pantalla ni
/// widget debe escribir un `Color(0xFF...)` propio — todo pasa por [AppColors.of] (o, para
/// construir el [ThemeData] en sí, por `app_theme.dart`, que importa esta clase en vez de
/// repetir los hex). No usar [AppPalette] directamente desde pantallas/widgets de negocio.
class AppPalette {
  const AppPalette._();

  // §3.1 Marca / primario
  static const Color primaryLight = Color(0xFF6C7FE0);
  static const Color primaryDark = Color(0xFF8B9AEF);
  static const Color primaryPressedLight = Color(0xFF5567D6);
  static const Color primaryPressedDark = Color(0xFF7482D6);
  static const Color primaryContainerLight = Color(0xFFE4E7FB);
  static const Color primaryContainerDark = Color(0xFF2A2F5C);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color onPrimaryDark = Color(0xFF0B0C14);

  // §3.2 Neutros / superficie
  static const Color backgroundLight = Color(0xFFF7F8FA);
  static const Color backgroundDark = Color(0xFF14151C);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E202B);
  static const Color borderLight = Color(0xFFE8EAF1);
  static const Color borderDark = Color(0xFF2C2E3A);
  static const Color textPrimaryLight = Color(0xFF1A1B25);
  static const Color textPrimaryDark = Color(0xFFF2F3F7);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textSecondaryDark = Color(0xFFA7ACC0);
  static const Color textDisabledLight = Color(0xFFA0A4B2);
  static const Color textDisabledDark = Color(0xFF5B5F6E);

  // §3.3 Estados (base + fondo pastel), corregidos/confirmados en §3bis.
  static const Color successBaseLight = Color(0xFF2FAE60);
  static const Color successBgLight = Color(0xFFE1F6E9);
  static const Color successBaseDark = Color(0xFF4ECB86);
  static const Color successBgDark = Color(0xFF16321F);

  static const Color warningBaseLight = Color(0xFFF5A623);
  static const Color warningBgLight = Color(0xFFFDECD1);
  static const Color warningBaseDark = Color(0xFFF7B955);
  static const Color warningBgDark = Color(0xFF3A2A12);

  static const Color dangerBaseLight = Color(0xFFE5484D);
  static const Color dangerBgLight = Color(0xFFFBE1E2);
  static const Color dangerBaseDark = Color(0xFFF2777B);
  static const Color dangerBgDark = Color(0xFF3A1517);

  static const Color neutralBaseLight = Color(0xFF8A8F9C);
  static const Color neutralBgLight = Color(0xFFEEEFF2);
  static const Color neutralBaseDark = Color(0xFF9AA0B0);
  static const Color neutralBgDark = Color(0xFF262834);
}

/// Un estado semántico (§3.3/3.4): color "base" (texto/borde/punto) + fondo pastel. Usado por
/// `StatusPill` y por cualquier otro widget que necesite representar
/// éxito/advertencia/peligro/neutral de forma consistente.
@immutable
class AppStateColor {
  const AppStateColor({required this.base, required this.background});

  final Color base;
  final Color background;

  AppStateColor lerp(AppStateColor other, double t) => AppStateColor(
        base: Color.lerp(base, other.base, t)!,
        background: Color.lerp(background, other.background, t)!,
      );
}

/// Tokens de color que NO tienen equivalente directo en `ColorScheme` de Material (ver
/// `sistema-diseno.md` §8): `primaryPressed` y los cuatro estados semánticos de §3.3/3.4. El
/// resto de los tokens (`primary`, `primaryContainer`, `onPrimary`, `background`, `surface`,
/// `border`, `textPrimary`, `textSecondary`, `textDisabled`) sí tienen un slot razonable en
/// `ColorScheme`/`ThemeData` estándar de Material y se resuelven ahí — ver el mapeo completo en
/// [AppColors].
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.primaryPressed,
    required this.success,
    required this.warning,
    required this.danger,
    required this.neutral,
  });

  final Color primaryPressed;
  final AppStateColor success;
  final AppStateColor warning;
  final AppStateColor danger;
  final AppStateColor neutral;

  static const AppColorTokens light = AppColorTokens(
    primaryPressed: AppPalette.primaryPressedLight,
    success: AppStateColor(base: AppPalette.successBaseLight, background: AppPalette.successBgLight),
    warning: AppStateColor(base: AppPalette.warningBaseLight, background: AppPalette.warningBgLight),
    danger: AppStateColor(base: AppPalette.dangerBaseLight, background: AppPalette.dangerBgLight),
    neutral: AppStateColor(base: AppPalette.neutralBaseLight, background: AppPalette.neutralBgLight),
  );

  static const AppColorTokens dark = AppColorTokens(
    primaryPressed: AppPalette.primaryPressedDark,
    success: AppStateColor(base: AppPalette.successBaseDark, background: AppPalette.successBgDark),
    warning: AppStateColor(base: AppPalette.warningBaseDark, background: AppPalette.warningBgDark),
    danger: AppStateColor(base: AppPalette.dangerBaseDark, background: AppPalette.dangerBgDark),
    neutral: AppStateColor(base: AppPalette.neutralBaseDark, background: AppPalette.neutralBgDark),
  );

  @override
  AppColorTokens copyWith({
    Color? primaryPressed,
    AppStateColor? success,
    AppStateColor? warning,
    AppStateColor? danger,
    AppStateColor? neutral,
  }) {
    return AppColorTokens(
      primaryPressed: primaryPressed ?? this.primaryPressed,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      neutral: neutral ?? this.neutral,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      neutral: neutral.lerp(other.neutral, t),
    );
  }
}

/// Punto único de acceso a los tokens de color (§3/§8/§10 — "AppColors, con getters que
/// resuelven claro/oscuro vía `Theme.of(context)`"). Todas las pantallas y widgets de negocio
/// deben leer color a través de `AppColors.of(context).xxx`, nunca `Color(0xFF...)` ni
/// `AppPalette` directamente.
///
/// Mapeo de cada token de `sistema-diseno.md` §3 a su fuente real:
/// - `primary`, `primaryContainer`, `onPrimary` → `ColorScheme` (slots directos de Material).
/// - `background` (fondo de pantalla) → `ColorScheme.surface` (rol M3 recomendado para el fondo
///   base, lo que usa `Scaffold` por defecto).
/// - `surface` (tarjeta) → `ColorScheme.surfaceContainerLowest` (superficie elevada, distinta
///   del fondo de pantalla — necesitamos dos tonos separados, no uno solo).
/// - `border`/`divider` → `ColorScheme.outlineVariant` (rol M3 para bordes/separadores sutiles).
/// - `textPrimary`/`textSecondary` → `ColorScheme.onSurface`/`onSurfaceVariant`.
/// - `textDisabled` → `ThemeData.disabledColor`.
/// - `primaryPressed` y los 4 estados (`success`/`warning`/`danger`/`neutral`) → [AppColorTokens]
///   (sin equivalente directo en Material, ver esa clase).
@immutable
class AppColors {
  const AppColors._(this._scheme, this._tokens, this._disabledColor);

  final ColorScheme _scheme;
  final AppColorTokens _tokens;
  final Color _disabledColor;

  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppColorTokens>() ??
        (theme.brightness == Brightness.dark ? AppColorTokens.dark : AppColorTokens.light);
    return AppColors._(theme.colorScheme, tokens, theme.disabledColor);
  }

  Color get primary => _scheme.primary;
  Color get primaryPressed => _tokens.primaryPressed;
  Color get primaryContainer => _scheme.primaryContainer;
  Color get onPrimary => _scheme.onPrimary;
  Color get background => _scheme.surface;
  Color get surface => _scheme.surfaceContainerLowest;
  Color get border => _scheme.outlineVariant;
  Color get textPrimary => _scheme.onSurface;
  Color get textSecondary => _scheme.onSurfaceVariant;
  Color get textDisabled => _disabledColor;

  AppStateColor get success => _tokens.success;
  AppStateColor get warning => _tokens.warning;
  AppStateColor get danger => _tokens.danger;
  AppStateColor get neutral => _tokens.neutral;
}
