import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Acerca de (Configuración > Aplicación > Acerca de, `configuracion_screen.dart`, confirmado
/// contra capturas reales en `mapa-pantallas.md` §5.11bis). Pantalla estática, sin backend.
///
/// Nombre mostrado: "Turnos Profesionales" — el mismo `MaterialApp.title` de `main.dart`, no
/// "Turnario" (la marca de la app de referencia que se ve en el footer de
/// `configuracion_screen.dart`, "Turnario v1.0.0" — texto ya existente, no tocado acá). Se elige
/// el nombre real de ESTE proyecto en vez de replicar el de la app de referencia.
class AcercaDeScreen extends StatelessWidget {
  const AcercaDeScreen({super.key});

  /// Mismo valor que `version:` en `pubspec.yaml` — actualizar ambos juntos si cambia. No se lee
  /// en runtime vía un paquete tipo `package_info_plus`: no es una dependencia de este proyecto
  /// (ver `pubspec.yaml`) y sumarla solo para esta pantalla estática, sin backend, sería
  /// desproporcionado para lo que pide esta ronda.
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
            'Gestioná turnos, pacientes y tu agenda profesional desde un solo lugar.',
            textAlign: TextAlign.center,
            style: AppTypography.body(context),
          ),
        ],
      ),
    );
  }
}
