import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'elegir_profesional_screen.dart';

/// HU-07: el cliente elige un servicio dentro del negocio ya seleccionado.
class DetalleNegocioScreen extends StatefulWidget {
  const DetalleNegocioScreen({super.key, required this.negocioId, required this.nombreNegocio});

  final String negocioId;
  final String nombreNegocio;

  @override
  State<DetalleNegocioScreen> createState() => _DetalleNegocioScreenState();
}

class _DetalleNegocioScreenState extends State<DetalleNegocioScreen> {
  late Future<List<dynamic>> _servicios;

  @override
  void initState() {
    super.initState();
    _servicios = context.read<Sesion>().api.getList('/negocios/${widget.negocioId}/servicios');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🧰',
        title: widget.nombreNegocio,
        subtitle: 'Elegí un servicio',
        showBackButton: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _servicios,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final servicios = snapshot.data!;
          if (servicios.isEmpty) {
            return const _EstadoVacio(
              icon: Icons.design_services_outlined,
              texto: 'Este negocio todavía no cargó servicios.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: servicios.length,
            itemBuilder: (context, i) {
              final s = servicios[i] as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _ServicioCard(
                  nombre: s['nombre'] as String,
                  detalle: '${s['duracion_min']} min · \$${s['precio_referencia'] ?? '-'}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ElegirProfesionalScreen(
                        negocioId: widget.negocioId,
                        servicioId: s['id'] as String,
                        servicioNombre: s['nombre'] as String,
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

/// Fila de servicio — misma tarjeta tappeable que `_NegocioCard`
/// (`buscar_negocios_screen.dart`), duplicada localmente a propósito (cada pantalla de este
/// código ya define sus propios widgets privados en vez de compartir uno común).
class _ServicioCard extends StatelessWidget {
  const _ServicioCard({required this.nombre, required this.detalle, required this.onTap});

  final String nombre;
  final String detalle;
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
                child: Icon(Icons.design_services_outlined, color: colors.primary),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: AppTypography.subtitle(context)
                          .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(detalle, style: AppTypography.caption(context)),
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
