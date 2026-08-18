import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Acerca de (Configuración > Aplicación > Acerca de, `configuracion_cliente_screen.dart`) —
/// contraparte Cliente de `profesional/acerca_de_screen.dart`. Pantalla estática, sin backend, con
/// exactamente el mismo armado visual (avatar circular + nombre + versión + descripción) — se creó
/// una copia en vez de reusar la de Profesional tal cual porque esa versión tiene una descripción
/// hardcodeada específica de ese rol ("Gestioná turnos, pacientes y tu agenda profesional desde un
/// solo lugar.", que no aplica a un cliente: un cliente no gestiona pacientes ni una agenda propia,
/// reserva turnos con profesionales de terceros) — acá se reemplaza por una frase equivalente desde
/// la perspectiva Cliente. El resto (nombre de la app, ícono, versión) es idéntico.
class AcercaDeClienteScreen extends StatelessWidget {
  const AcercaDeClienteScreen({super.key});

  /// Mismo valor que `_version` en `profesional/acerca_de_screen.dart` y que `version:` en
  /// `pubspec.yaml` — actualizar los 3 juntos si cambia.
  static const _version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: const AppHeader(variant: AppHeaderVariant.surface, emoji: 'ℹ️', title: 'Acerca de', showBackButton: true),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.event_available_outlined, color: colors.primary, size: 36),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Center(child: Text('Turnos Profesionales', style: AppTypography.sectionTitle(context))),
          const SizedBox(height: AppSpacing.xs),
          Center(child: Text('Versión $_version', style: AppTypography.caption(context))),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Reservá turnos con tus profesionales de confianza desde un solo lugar.',
            textAlign: TextAlign.center,
            style: AppTypography.body(context),
          ),
        ],
      ),
    );
  }
}
