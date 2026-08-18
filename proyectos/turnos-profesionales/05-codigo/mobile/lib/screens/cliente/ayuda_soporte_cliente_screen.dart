import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Ayuda y Soporte (Configuración > Aplicación > Ayuda y Soporte,
/// `configuracion_cliente_screen.dart`) — contraparte Cliente de
/// `profesional/ayuda_soporte_screen.dart`. Pantalla estática, sin backend, mismo armado visual
/// (`_sectionCard`/`_FaqItem`, duplicados acá igual que en el resto de las pantallas de
/// Configuración de esta app en vez de compartirse, ver el doc-comment de
/// `configuracion_cliente_screen.dart`) — se creó una copia en vez de reusar la de Profesional tal
/// cual porque sus 4 preguntas frecuentes apuntan a ítems que solo existen en el menú de
/// Configuración de Profesional ("Configurar Disponibilidad", "Configuración de Pagos" con
/// activación de seña, "Reportes y Estadísticas... dentro de Panel Profesional") — nada de eso
/// existe en el menú de Configuración de Cliente (`configuracion_cliente_screen.dart` no tiene
/// sección "Panel Profesional" ni "Pagos y Señas", ver el doc-comment de esa clase), así que
/// mostrárselas a un cliente lo mandaría a buscar opciones que no están. Se reemplazan por 4
/// preguntas sobre el flujo real de Cliente (reservar/cancelar/reprogramar turnos, ver
/// `cliente/buscar_negocios_screen.dart`/`cliente/mis_turnos_screen.dart`); "¿Cómo edito mis datos
/// de perfil?" se mantiene tal cual, sigue siendo precisa para este rol. La sección "Contacto" no
/// tiene ninguna referencia de rol — se reusa el mismo texto exacto.
class AyudaSoporteClienteScreen extends StatelessWidget {
  const AyudaSoporteClienteScreen({super.key});

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
                  pregunta: '¿Cómo reservo un turno?',
                  respuesta:
                      'Andá a Buscar, elegí un negocio y un profesional, y seguí los pasos para confirmar tu '
                      'turno.',
                ),
                _FaqItem(
                  pregunta: '¿Cómo edito mis datos de perfil?',
                  respuesta: 'Andá a Configuración > Editar Perfil.',
                ),
                _FaqItem(
                  pregunta: '¿Cómo cancelo o reprogramo un turno?',
                  respuesta:
                      'Andá a Mis Turnos y usá las opciones "Cancelar" o "Reprogramar" del turno '
                      'correspondiente.',
                ),
                _FaqItem(
                  pregunta: '¿Dónde veo el estado de mis turnos?',
                  respuesta: 'Andá a Mis Turnos para ver todos tus turnos, con su estado actualizado.',
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
