import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'horarios_disponibles_screen.dart';

/// HU-08: el cliente elige un profesional entre los que ofrecen el servicio elegido.
class ElegirProfesionalScreen extends StatefulWidget {
  const ElegirProfesionalScreen({
    super.key,
    required this.negocioId,
    required this.servicioId,
    required this.servicioNombre,
    this.onTurnoConfirmado,
  });

  final String negocioId;
  final String servicioId;
  final String servicioNombre;
  final VoidCallback? onTurnoConfirmado;

  @override
  State<ElegirProfesionalScreen> createState() => _ElegirProfesionalScreenState();
}

class _ElegirProfesionalScreenState extends State<ElegirProfesionalScreen> {
  late Future<List<dynamic>> _profesionales;

  @override
  void initState() {
    super.initState();
    _profesionales = context.read<Sesion>().api.getList(
          '/negocios/${widget.negocioId}/servicios/${widget.servicioId}/profesionales',
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '👤',
        title: widget.servicioNombre,
        subtitle: 'Elegí un profesional',
        showBackButton: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _profesionales,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final profesionales = snapshot.data!;
          if (profesionales.isEmpty) {
            return const _EstadoVacio(
              icon: Icons.person_search_outlined,
              texto: 'Ningún profesional ofrece este servicio todavía.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: profesionales.length,
            itemBuilder: (context, i) {
              final p = profesionales[i] as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ProfesionalCard(
                  nombre: p['nombre'] as String,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HorariosDisponiblesScreen(
                        profesionalId: p['id'] as String,
                        profesionalNombre: p['nombre'] as String,
                        servicioId: widget.servicioId,
                        servicioNombre: widget.servicioNombre,
                        onTurnoConfirmado: widget.onTurnoConfirmado,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Fila de profesional — misma tarjeta tappeable que `_NegocioCard`
/// (`buscar_negocios_screen.dart`), duplicada localmente a propósito (cada pantalla de este
/// código ya define sus propios widgets privados en vez de compartir uno común).
class _ProfesionalCard extends StatelessWidget {
  const _ProfesionalCard({required this.nombre, required this.onTap});

  final String nombre;
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
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                child: Icon(Icons.person, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Text(
                  nombre,
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
