import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// §7.3 — tarjeta blanca (`surface`), `radius.card`. Número grande bold (`statNumber`) arriba,
/// etiqueta gris chica (`caption`) abajo, ícono opcional arriba a la izquierda del número.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.value, required this.label, this.icon, this.emphasize = false});

  final String value;
  final String label;
  final IconData? icon;

  /// Si es `true`, el número usa `primary` en vez de `textPrimary` (§7.3: "o `primary` si la
  /// stat card es de énfasis").
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: emphasize ? colors.primary : colors.textSecondary),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            value,
            style: AppTypography.statNumber(context).copyWith(color: emphasize ? colors.primary : colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.caption(context),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// §7.3 — agrupa [StatCard] en una grilla responsive de 2 a 4 columnas según ancho de pantalla.
/// Implementado con `Wrap` (no `GridView`) para poder vivir dentro de un `ListView`/
/// `SingleChildScrollView` sin necesitar una altura acotada.
class StatCardGrid extends StatelessWidget {
  const StatCardGrid({super.key, required this.cards});

  final List<StatCard> cards;

  int _columnsFor(double width, int count) {
    if (count <= 1) return 1;
    // 2 o 3 stat cards entran cómodas en una sola fila incluso en mobile angosto (ver Dashboard,
    // sistema-diseno.md §5.2bis) — el recorte a 2 columnas de §7.3 aplica sobre todo a partir de
    // la 4ta card (ej. futura Gestión de Pacientes, §5.8bis).
    if (count <= 3) return count;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth, cards.length);
        const spacing = AppSpacing.md;
        final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}
