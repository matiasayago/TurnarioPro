import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// HU-13: elegir un nuevo horario para un turno propio (mismo profesional/servicio, CU5).
/// Reutiliza /profesionales/{id}/slots para listar horarios y PATCH /turnos/{id}/reprogramar
/// para confirmar — el backend aplica la misma garantía anti-doble-reserva que en la reserva
/// original (ver backend/src/routes/turnos.ts).
class ReprogramarTurnoScreen extends StatefulWidget {
  const ReprogramarTurnoScreen({
    super.key,
    required this.turnoId,
    required this.profesionalId,
    required this.servicioId,
  });

  final String turnoId;
  final String profesionalId;
  final String servicioId;

  @override
  State<ReprogramarTurnoScreen> createState() => _ReprogramarTurnoScreenState();
}

class _ReprogramarTurnoScreenState extends State<ReprogramarTurnoScreen> {
  late Future<Map<String, dynamic>> _slots;
  bool _reprogramando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _slots = context.read<Sesion>().api.getMap(
      '/profesionales/${widget.profesionalId}/slots?servicio_id=${widget.servicioId}',
    );
  }

  Future<void> _reprogramar(String nuevoInicio) async {
    setState(() {
      _reprogramando = true;
      _error = null;
    });
    try {
      await context.read<Sesion>().api.patch('/turnos/${widget.turnoId}/reprogramar', {
        'nuevo_inicio': nuevoInicio,
      });
      if (!mounted) return;
      Navigator.pop(context, true); // true = se reprogramó, la pantalla anterior refresca
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 409
          ? 'Ese horario ya no está disponible — alguien más lo tomó. Elegí otro.'
          : e.message);
    } finally {
      if (mounted) setState(() => _reprogramando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🔁',
        title: 'Elegir Nuevo Horario',
        showBackButton: true,
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.base, AppSpacing.base, 0),
              child: _FeedbackBanner(mensaje: _error!, esError: true),
            ),
          if (_reprogramando) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _slots,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final slots = (snapshot.data!['slots'] as List).cast<String>();
                if (slots.isEmpty) {
                  return const _EstadoVacio(
                    icon: Icons.event_busy_outlined,
                    texto: 'No hay otros horarios disponibles.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: slots.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _HorarioCard(
                      texto: formato.format(DateTime.parse(slots[i]).toLocal()),
                      habilitado: !_reprogramando,
                      onTap: () => _reprogramar(slots[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de horario — mismo criterio visual que `_HorarioCard`
/// (`horarios_disponibles_screen.dart`), duplicada localmente a propósito, con el agregado de
/// [habilitado]: reemplaza al `enabled: !_reprogramando` que tenía el `ListTile` original, para no
/// perder la protección contra doble-tap mientras el PATCH está en vuelo.
class _HorarioCard extends StatelessWidget {
  const _HorarioCard({required this.texto, required this.habilitado, required this.onTap});

  final String texto;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = habilitado ? colors.textPrimary : colors.textDisabled;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: habilitado ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, color: habilitado ? colors.primary : colors.textDisabled),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Text(texto, style: AppTypography.subtitle(context).copyWith(color: fg, fontWeight: FontWeight.bold)),
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

/// Mismo patrón de banner de error que el resto de las pantallas de esta app (ej.
/// `registro_cliente_screen.dart`), duplicado localmente a propósito.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.mensaje, required this.esError});

  final String mensaje;
  final bool esError;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final estado = esError ? colors.danger : colors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: estado.background, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Text(mensaje, style: AppTypography.body(context).copyWith(color: estado.base)),
    );
  }
}
