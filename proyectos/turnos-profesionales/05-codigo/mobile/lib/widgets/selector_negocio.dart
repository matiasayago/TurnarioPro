import 'package:flutter/material.dart';

import '../state/sesion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_modal_sheet.dart';

/// HU-27 ("cambiar de vista", `02-backlog/backlog.md`): selector de negocio activo, compartido
/// por los dos puntos de entrada que necesitan elegir uno entre los `Sesion.negocios` ya
/// cargados desde el login (ningún endpoint propio de "mis negocios", ver `state/sesion.dart`):
/// - `login_screen.dart`: cuenta recién autenticada con 2+ negocios activos, todavía sin ninguno
///   elegido — ahí [actualNegocioId] queda `null` (nada elegido todavía).
/// - `screens/profesional/dashboard_screen.dart`: ícono "cambiar de vista" del header, con la
///   sesión ya iniciada — ahí [actualNegocioId] marca cuál es el negocio activo hoy.
///
/// Devuelve el negocio elegido, o `null` si se cancela (botón "✕" del propio [AppModalSheet]).
Future<NegocioMembresia?> elegirNegocio(
  BuildContext context,
  List<NegocioMembresia> negocios, {
  String? actualNegocioId,
}) {
  return AppModalSheet.show<NegocioMembresia>(
    context,
    builder: (_) => _SelectorNegocioSheet(negocios: negocios, actualNegocioId: actualNegocioId),
  );
}

class _SelectorNegocioSheet extends StatelessWidget {
  const _SelectorNegocioSheet({required this.negocios, this.actualNegocioId});

  final List<NegocioMembresia> negocios;
  final String? actualNegocioId;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppModalSheet(
      title: 'Elegir negocio',
      // El botón "✕" del propio header ya permite cancelar — elegir una fila ES la acción, no
      // hace falta un footer aparte (mismo criterio que cualquier picker de una sola opción).
      secondaryLabel: null,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: AppRadius.cardShadow,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Column(
              children: [
                for (var i = 0; i < negocios.length; i++) ...[
                  _NegocioTile(
                    negocio: negocios[i],
                    activo: negocios[i].negocioId == actualNegocioId,
                    onTap: () => Navigator.of(context).pop(negocios[i]),
                  ),
                  if (i != negocios.length - 1) Divider(height: 1, color: colors.border),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NegocioTile extends StatelessWidget {
  const _NegocioTile({required this.negocio, required this.activo, required this.onTap});

  final NegocioMembresia negocio;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.storefront_outlined, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Text(
                negocio.nombre,
                style: AppTypography.body(context)
                    .copyWith(fontWeight: activo ? FontWeight.bold : FontWeight.normal),
              ),
            ),
            Icon(
              activo ? Icons.check_circle : Icons.chevron_right,
              size: 20,
              color: activo ? colors.primary : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
