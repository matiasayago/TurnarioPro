import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Variante de radio de esquina (sistema-diseno.md §7.1bis, corrección sobre §7.1): `pill`
/// (`radius.chip`, píldora completa) para botones de barra de acción o footer de pantalla
/// completa (ej. "Guardar N Fechas", "Restablecer", "Aplicar plantilla al calendario"); `card`
/// (`radius.card`, radio moderado) para footers de modal/formulario y pantallas de
/// autenticación (ej. "Crear Cita y Notificar Cliente", "Iniciar sesión").
enum AppButtonRadius { pill, card }

double _radiusFor(AppButtonRadius variant) => switch (variant) {
      AppButtonRadius.pill => AppRadius.chip,
      AppButtonRadius.card => AppRadius.card,
    };

/// Botón sólido base compartido por [PrimaryButton]/[WarningButton]/[SuccessButton] (§7.1):
/// misma forma/altura/estado-deshabilitado/loading, solo cambia el color de fondo y de texto.
class _SolidAppButton extends StatelessWidget {
  const _SolidAppButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    required this.radiusVariant,
    required this.expand,
    this.icon,
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final AppButtonRadius radiusVariant;
  final bool expand;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // §7.1: "Estado deshabilitado: opacidad reducida (~40%) + textDisabled, sin cambiar la
    // forma." No aplica mientras `loading` (el botón sigue "activo", solo ocupado).
    final disabledLook = onPressed == null && !loading;
    final bg = disabledLook ? background.withValues(alpha: 0.4) : background;
    final fg = disabledLook ? colors.textDisabled : foreground;
    final radius = BorderRadius.circular(_radiusFor(radiusVariant));
    final interactive = onPressed != null && !loading;

    return SizedBox(
      width: expand ? double.infinity : null,
      height: 50,
      child: Material(
        color: bg,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: interactive ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: loading
                  ? [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))]
                  : [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.buttonLabel(context, color: fg),
                        ),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §7.1 — acción principal de pantalla/modal ("Reservar", "Guardar", "Agendar Cita"). Píldora,
/// fondo `primary` sólido, texto `onPrimary` bold.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.radiusVariant = AppButtonRadius.pill,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonRadius radiusVariant;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _SolidAppButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      loading: loading,
      background: colors.primary,
      foreground: colors.onPrimary,
      radiusVariant: radiusVariant,
      expand: expand,
    );
  }
}

/// §7.1 — advertencia no destructiva (ej. "Restablecer"). Fondo `warning` sólido, texto blanco.
/// No usar para "eliminar" (ver nota de `DestructiveButton` en el sistema de diseño).
class WarningButton extends StatelessWidget {
  const WarningButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.radiusVariant = AppButtonRadius.pill,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonRadius radiusVariant;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _SolidAppButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      loading: loading,
      background: colors.warning.base,
      foreground: Colors.white,
      radiusVariant: radiusVariant,
      expand: expand,
    );
  }
}

/// §7.1bis/§10 — acción constructiva de crear/guardar/aplicar observada en varias pantallas de
/// las capturas reales (ej. "Aplicar plantilla al calendario", "Agregar Paciente"). Mismo
/// tratamiento que [PrimaryButton] pero con fondo `success` sólido.
class SuccessButton extends StatelessWidget {
  const SuccessButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.radiusVariant = AppButtonRadius.pill,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonRadius radiusVariant;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return _SolidAppButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      loading: loading,
      background: colors.success.base,
      foreground: Colors.white,
      radiusVariant: radiusVariant,
      expand: expand,
    );
  }
}

/// §7.1 — "Cancelar" en modales, acciones secundarias no destacadas. Píldora, fondo
/// transparente, borde `border` ~1.5dp, texto `textPrimary`.
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.radiusVariant = AppButtonRadius.pill,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonRadius radiusVariant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    final borderColor = enabled ? colors.border : colors.border.withValues(alpha: 0.4);
    final fg = enabled ? colors.textPrimary : colors.textDisabled;
    final radius = BorderRadius.circular(_radiusFor(radiusVariant));

    return SizedBox(
      width: expand ? double.infinity : null,
      height: 50,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: borderColor, width: 1.5)),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.buttonLabel(context, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
