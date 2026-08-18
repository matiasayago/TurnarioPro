import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/widgets.dart';
import 'registro_cliente_screen.dart';
import 'registro_negocio_screen.dart';

/// HU-00a/HU-01 (`02-backlog/backlog.md`): paso intermedio de selección de tipo de cuenta entre
/// `LoginScreen` y los 2 formularios de alta pre-autenticación (`RegistroClienteScreen`/
/// `RegistroNegocioScreen`) — reemplaza a los 2 links que antes convivían al pie del login (uno
/// por formulario) por un único link "¿Todavía no tenés cuenta? Registrate" que empuja esta
/// pantalla; acá el usuario elige a cuál de los 2 formularios llegar. Ninguno de los 2 formularios
/// cambió (mismo contrato, mismo comportamiento) — esta pantalla solo decide CÓMO se llega a ellos.
///
/// Cada opción navega con [Navigator.pushReplacement] (no `push`): así esta pantalla no queda en
/// el historial entre `LoginScreen` y el formulario elegido — si el usuario toca "atrás" desde el
/// formulario, vuelve directo al login, no a este selector intermedio.
class RegistroSelectorScreen extends StatelessWidget {
  const RegistroSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '📝',
        title: 'Registrarte',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elegí cómo vas a usar la app — te vamos a pedir algunos datos distintos según tu '
              'elección.',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: AppSpacing.xl),
            _TipoCuentaCard(
              icon: Icons.person_outline,
              titulo: 'Soy Cliente',
              bajada: 'Quiero reservar turnos con profesionales',
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RegistroClienteScreen()),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _TipoCuentaCard(
              icon: Icons.storefront_outlined,
              titulo: 'Tengo un Negocio',
              bajada: 'Quiero ofrecer mis servicios y gestionar turnos',
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RegistroNegocioScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta grande tappeable de opción — mismo criterio de tarjeta tappeable (`InkWell` + sombra
/// propia) que `_NegocioCard` (`cliente/buscar_negocios_screen.dart`), pero más grande/prominente:
/// acá son solo 2 opciones centrales de toda la pantalla, no una fila más de una lista larga.
class _TipoCuentaCard extends StatelessWidget {
  const _TipoCuentaCard({
    required this.icon,
    required this.titulo,
    required this.bajada,
    required this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String bajada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: colors.primaryContainer,
                child: Icon(icon, size: 32, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: AppTypography.sectionTitle(context)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(bajada, style: AppTypography.caption(context)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
