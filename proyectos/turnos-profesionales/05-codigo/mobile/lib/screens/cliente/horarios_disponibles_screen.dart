import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'confirmar_turno_screen.dart';

/// HU-09: horarios disponibles del profesional para el servicio elegido. Si no hay en el
/// rango consultado, el backend ya devuelve el próximo disponible (D5, sin lista de espera)
/// — ver wireframe conceptual en docs/04-diseno/mapa-pantallas.md §4.
class HorariosDisponiblesScreen extends StatefulWidget {
  const HorariosDisponiblesScreen({
    super.key,
    required this.profesionalId,
    required this.profesionalNombre,
    required this.servicioId,
    required this.servicioNombre,
  });

  final String profesionalId;
  final String profesionalNombre;
  final String servicioId;

  /// Propagado a `ConfirmarTurnoScreen` (fast-follow del CEO, 2026-08-18): esa pantalla necesita
  /// el nombre del servicio para su nueva card "Servicio", y no tiene forma propia de pedirlo
  /// (no hay endpoint `GET /servicios/:id`) — viaja por la cadena de navegación desde
  /// `DetalleNegocioScreen`, que ya lo conoce.
  final String servicioNombre;

  @override
  State<HorariosDisponiblesScreen> createState() => _HorariosDisponiblesScreenState();
}

class _HorariosDisponiblesScreenState extends State<HorariosDisponiblesScreen> {
  late Future<Map<String, dynamic>> _slots;

  @override
  void initState() {
    super.initState();
    _slots = context.read<Sesion>().api.getMap(
      '/profesionales/${widget.profesionalId}/slots?servicio_id=${widget.servicioId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🕐',
        title: widget.profesionalNombre,
        subtitle: 'Elegí un horario',
        showBackButton: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _slots,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final slots = (snapshot.data!['slots'] as List).cast<String>();
          final proximo = snapshot.data!['proximo_disponible'] as String?;

          if (slots.isEmpty) {
            return const _EstadoVacio(
              icon: Icons.event_busy_outlined,
              texto: 'No hay horarios disponibles próximamente.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.base),
            children: [
              if (proximo != null) ...[
                _ProximoDisponibleBanner(texto: formato.format(DateTime.parse(proximo).toLocal())),
                const SizedBox(height: AppSpacing.md),
              ],
              for (final inicio in slots)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _HorarioCard(
                    texto: formato.format(DateTime.parse(inicio).toLocal()),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConfirmarTurnoScreen(
                          profesionalId: widget.profesionalId,
                          profesionalNombre: widget.profesionalNombre,
                          servicioId: widget.servicioId,
                          servicioNombre: widget.servicioNombre,
                          inicio: inicio,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Banner informativo — mismo tratamiento de tarjeta que el resto de la app (`AppRadius.card`,
/// `AppSpacing`), en `primaryContainer`/`primary`: no es una advertencia (no usa `colors.warning`)
/// sino una sugerencia útil sobre el primer horario libre.
class _ProximoDisponibleBanner extends StatelessWidget {
  const _ProximoDisponibleBanner({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Próximo disponible: $texto',
              style: AppTypography.body(context).copyWith(color: colors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de horario — misma tarjeta tappeable que `_NegocioCard`
/// (`buscar_negocios_screen.dart`), duplicada localmente a propósito (cada pantalla de este
/// código ya define sus propios widgets privados en vez de compartir uno común).
class _HorarioCard extends StatelessWidget {
  const _HorarioCard({required this.texto, required this.onTap});

  final String texto;
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
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, color: colors.primary),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Text(
                  texto,
                  style: AppTypography.subtitle(context)
                      .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
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

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.textSecondary),
            const SizedBox(height: AppSpacing.base),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
