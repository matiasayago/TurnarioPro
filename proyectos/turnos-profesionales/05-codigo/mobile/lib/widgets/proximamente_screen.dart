import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_header.dart';

/// Placeholder simple para secciones que todavía no se construyen en este ciclo (ej. WhatsApp y
/// Notificaciones del lado Profesional en `ProfesionalShell`; Notificaciones y Configuración del
/// lado Cliente en `ClienteShell`). No es un olvido: el alcance de cada iteración pidió
/// explícitamente dejarlas como "Próximamente" y no construirlas todavía.
///
/// Vive en `widgets/` (compartido entre ambos modos de la app) en vez de `screens/profesional/`
/// porque no tiene ninguna lógica ni dependencia específica de un rol — antes solo lo usaba
/// Profesional, ahora también Cliente (ver `screens/cliente/cliente_shell.dart`).
class ProximamenteScreen extends StatelessWidget {
  const ProximamenteScreen({super.key, required this.titulo, this.emoji, this.showBackButton = false});

  final String titulo;
  final String? emoji;

  /// `false` por defecto (preserva el comportamiento de las pestañas raíz de un bottom nav, que
  /// no llevan flecha de volver). Las pantallas de esta clase que se abren con `Navigator.push`
  /// desde otro lugar (ej. Configuración) deben pasar `true` explícito.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppHeader(title: titulo, emoji: emoji, showBackButton: showBackButton),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, size: 40, color: colors.textSecondary),
              const SizedBox(height: AppSpacing.base),
              Text('Próximamente', style: AppTypography.sectionTitle(context)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Esta sección todavía no está disponible.',
                style: AppTypography.body(context),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
