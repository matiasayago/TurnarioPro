import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Ayuda y Soporte (Configuración > Aplicación > Ayuda y Soporte, `configuracion_screen.dart`,
/// confirmado contra capturas reales en `mapa-pantallas.md` §5.11bis). Pantalla estática, sin
/// backend — no hay HU ni endpoint asociado.
///
/// A propósito **no incluye ningún dato de contacto** (teléfono/email/chat) que pudiera parecer
/// real sin serlo: esta versión de la app no tiene ningún canal de soporte operativo todavía, y
/// mostrar un teléfono o email de relleno induciría a un profesional real a intentar
/// contactarlo. En su lugar, la sección "Contacto" lo dice explícitamente.
class AyudaSoporteScreen extends StatelessWidget {
  const AyudaSoporteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '❓',
        title: 'Ayuda y Soporte',
        showBackButton: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _sectionCard(
            context,
            title: 'Preguntas frecuentes',
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FaqItem(
                  pregunta: '¿Cómo edito mis datos de perfil?',
                  respuesta: 'Andá a Configuración > Editar Perfil.',
                ),
                _FaqItem(
                  pregunta: '¿Cómo configuro mis horarios de atención?',
                  respuesta: 'Andá a Configuración > Configurar Disponibilidad (o Gestionar Horarios).',
                ),
                _FaqItem(
                  pregunta: '¿Cómo activo el cobro de seña para un servicio?',
                  respuesta:
                      'Andá a Configuración > Configuración de Pagos y activá "Requiere seña" en el servicio '
                      'correspondiente.',
                ),
                _FaqItem(
                  pregunta: '¿Dónde veo mis estadísticas de turnos?',
                  respuesta: 'Andá a Configuración > Reportes y Estadísticas, dentro de Panel Profesional.',
                  esUltimo: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            title: 'Contacto',
            child: Text(
              'Esta versión de la app todavía no tiene un canal de soporte habilitado (teléfono, email o '
              'chat). Esta sección se va a completar en una futura actualización.',
              style: AppTypography.body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required String title, required Widget child}) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.sectionTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.pregunta, required this.respuesta, this.esUltimo = false});

  final String pregunta;
  final String respuesta;
  final bool esUltimo;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: esUltimo ? 0 : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pregunta, style: AppTypography.body(context).copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(respuesta, style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}
