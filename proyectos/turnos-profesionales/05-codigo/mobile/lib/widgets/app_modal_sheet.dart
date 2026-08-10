import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'buttons.dart';

/// §7.8, corregido en §7.8bis. El patrón real observado en las capturas es **pantalla completa**
/// (header propio + botón "✕" + footer fijo de borde a borde), no una hoja parcial que deja ver
/// el fondo atenuado — por eso [AppModalSheet] es un `Scaffold` completo pensado para empujarse
/// con [show] (`MaterialPageRoute(fullscreenDialog: true)`) en vez de `showModalBottomSheet`.
///
/// Footer: por defecto 2 botones (`Cancelar` outline + acción primaria), tal como el patrón más
/// confirmado en capturas (§7.8bis) — pasar `secondaryLabel: null` para un footer de un solo
/// botón, o agregar un tercero vía [extraFooterButton] (ej. "Restablecer", ver el caso de 3
/// botones documentado en §7.8bis).
class AppModalSheet extends StatelessWidget {
  const AppModalSheet({
    super.key,
    required this.title,
    required this.child,
    this.primaryLabel,
    this.onPrimary,
    this.primaryLoading = false,
    this.secondaryLabel = 'Cancelar',
    this.onSecondary,
    this.extraFooterButton,
  });

  final String title;
  final Widget child;

  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Tercer botón de footer opcional (ej. "Restablecer", `WarningButton`) — ver §7.8bis.
  final Widget? extraFooterButton;

  /// Empuja este modal como ruta de pantalla completa (§7.8bis) en vez de un bottom sheet
  /// parcial.
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder, fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasFooter = primaryLabel != null || secondaryLabel != null || extraFooterButton != null;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(title, style: AppTypography.sectionTitle(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: hasFooter
          ? SafeArea(
              minimum: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (extraFooterButton != null) ...[extraFooterButton!, const SizedBox(height: AppSpacing.sm)],
                  Row(
                    children: [
                      if (secondaryLabel != null)
                        Expanded(
                          child: OutlineButton(
                            label: secondaryLabel!,
                            radiusVariant: AppButtonRadius.card,
                            onPressed: onSecondary ?? () => Navigator.of(context).maybePop(),
                          ),
                        ),
                      if (secondaryLabel != null && primaryLabel != null) const SizedBox(width: AppSpacing.md),
                      if (primaryLabel != null)
                        Expanded(
                          child: PrimaryButton(
                            label: primaryLabel!,
                            radiusVariant: AppButtonRadius.card,
                            loading: primaryLoading,
                            onPressed: onPrimary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
