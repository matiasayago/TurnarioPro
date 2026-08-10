import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// §7.7bis — variante de color de fondo. `Dashboard` usa `surface`, no `primary` (corrección
/// puntual sobre §7.7, ver también `mapa-pantallas.md` §5.2bis).
enum AppHeaderVariant { primary, surface, warning }

/// §7.7/§7.7bis — header de pantalla. Construido sobre `AppBar` (en vez de un widget nuevo desde
/// cero) para heredar gratis el manejo de status bar / back button / accesibilidad ya probado
/// de Material, con el color/tipografía resueltos por el sistema de diseño.
///
/// El emoji decorativo de headers de sección (§6) se marca `ExcludeSemantics` para que los
/// lectores de pantalla no lo lean junto con el título (evita leer el mismo concepto dos veces).
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.emoji,
    this.subtitle,
    this.variant = AppHeaderVariant.primary,
    this.showBackButton = false,
    this.actions = const [],
  });

  final String title;

  /// Emoji decorativo de sección (ej. "⏰" en Gestión de Horarios, §6/§6bis). Opcional.
  final String? emoji;

  /// Segunda línea, chica (ej. la fecha del día en el Dashboard, §5.2bis).
  final String? subtitle;
  final AppHeaderVariant variant;
  final bool showBackButton;
  final List<Widget> actions;

  @override
  Size get preferredSize => Size.fromHeight(subtitle != null ? kToolbarHeight + 22 : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (Color bg, Color fg) = switch (variant) {
      AppHeaderVariant.primary => (colors.primary, colors.onPrimary),
      AppHeaderVariant.warning => (colors.warning.base, Colors.white),
      AppHeaderVariant.surface => (colors.surface, colors.textPrimary),
    };

    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      toolbarHeight: preferredSize.height,
      automaticallyImplyLeading: false,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              color: fg,
              tooltip: 'Volver',
              onPressed: () => Navigator.maybePop(context),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (emoji != null) ...[
            ExcludeSemantics(child: Text(emoji!, style: const TextStyle(fontSize: 20))),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.sectionTitle(context).copyWith(color: fg, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.caption(context).copyWith(color: fg.withValues(alpha: 0.8)),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
    );
  }
}
