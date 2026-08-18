import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'reprogramar_turno_screen.dart';

/// HU-12/HU-13: turnos del cliente autenticado, con acciones de cancelar y reprogramar
/// (RN8 — la ventana mínima la valida el backend; acá solo se muestra el resultado). Pestaña raíz
/// "Mis Turnos" de `ClienteShell` — recibe [onIrABuscar] para saltar a la pestaña "Buscar" (mismo
/// mecanismo cross-tab exacto que `onIrAHorarios`/`onIrAPacientes` en
/// `profesional/configuracion_screen.dart`/`profesional_shell.dart`), el único punto de entrada
/// real al flujo de reserva (`buscar_negocios_screen.dart`) — antes esta pantalla no tenía ningún
/// botón para iniciar una reserva nueva, ni siquiera en su estado vacío. El CTA se ofrece dos
/// veces: un ícono "+" en el header (siempre visible, incluso con turnos ya cargados) y, además,
/// un botón grande en el estado vacío (`_EstadoVacio`, la situación donde más falta hace).
class MisTurnosScreen extends StatefulWidget {
  const MisTurnosScreen({super.key, required this.onIrABuscar});

  final VoidCallback onIrABuscar;

  @override
  State<MisTurnosScreen> createState() => _MisTurnosScreenState();
}

class _MisTurnosScreenState extends State<MisTurnosScreen> {
  late Future<List<dynamic>> _turnos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _turnos = context.read<Sesion>().api.getList('/turnos/mios');
  }

  Future<void> _cancelar(String turnoId) async {
    final api = context.read<Sesion>().api;
    try {
      await api.patch('/turnos/$turnoId/cancelar');
      setState(_cargar);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reprogramar(Map<String, dynamic> turno) async {
    final reprogramado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReprogramarTurnoScreen(
          turnoId: turno['id'] as String,
          profesionalId: turno['profesional_id'] as String,
          servicioId: turno['servicio_id'] as String,
        ),
      ),
    );
    if (reprogramado == true) setState(_cargar);
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.primary,
        emoji: '📅',
        title: 'Mis Turnos',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Reservar un turno',
            onPressed: widget.onIrABuscar,
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _turnos,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final turnos = snapshot.data!;
          if (turnos.isEmpty) return _EstadoVacio(onIrABuscar: widget.onIrABuscar);
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: turnos.length,
            itemBuilder: (context, i) {
              final t = turnos[i] as Map<String, dynamic>;
              final gestionable = t['estado'] == 'confirmado' || t['estado'] == 'pendiente_de_pago';
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _TurnoCard(
                  fechaTexto: formato.format(DateTime.parse(t['inicio'] as String).toLocal()),
                  estado: turnoEstadoFromApi(t['estado'] as String),
                  gestionable: gestionable,
                  onReprogramar: () => _reprogramar(t),
                  onCancelar: () => _cancelar(t['id'] as String),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Card de turno: fecha/hora + `StatusPill.turno` (mismo widget que ya usa
/// `profesional/dashboard_screen.dart` para el estado de un turno), con Reprogramar/Cancelar
/// como acciones de fila — mismo tratamiento visual que `_AccionPaciente`
/// (`profesional/gestion_pacientes_screen.dart`), solo visibles cuando [gestionable] (RN8: el
/// backend decide qué turnos siguen siendo gestionables, acá solo se refleja ese resultado).
class _TurnoCard extends StatelessWidget {
  const _TurnoCard({
    required this.fechaTexto,
    required this.estado,
    required this.gestionable,
    required this.onReprogramar,
    required this.onCancelar,
  });

  final String fechaTexto;
  final TurnoEstado estado;
  final bool gestionable;
  final VoidCallback onReprogramar;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_outlined, size: 18, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  fechaTexto,
                  style: AppTypography.subtitle(context)
                      .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill.turno(estado),
            ],
          ),
          if (gestionable) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: colors.border),
            Row(
              children: [
                Expanded(
                  child: _AccionTurno(icon: Icons.event_repeat_outlined, label: 'Reprogramar', onTap: onReprogramar),
                ),
                Expanded(
                  child: _AccionTurno(
                    icon: Icons.cancel_outlined,
                    label: 'Cancelar',
                    color: colors.danger.base,
                    onTap: onCancelar,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Acción de fila — mismo patrón visual que `_AccionPaciente`
/// (`profesional/gestion_pacientes_screen.dart`: `TextButton.icon` chico, ícono + label en
/// `caption` bold), duplicado localmente a propósito.
class _AccionTurno extends StatelessWidget {
  const _AccionTurno({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fg = color ?? colors.primary;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: fg),
      label: Text(label, style: AppTypography.caption(context).copyWith(color: fg, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
    );
  }
}

/// Estado vacío con CTA — a diferencia de `_SinNegocioView`
/// (`profesional/dashboard_screen.dart`, solo ícono + texto), acá el mensaje solo no alcanza: es
/// el punto de la pantalla donde más falta hacía un botón hacia "Buscar" (ver doc-comment de la
/// clase — este era justo el bug funcional que originó la modernización de esta pantalla).
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.onIrABuscar});

  final VoidCallback onIrABuscar;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 48, color: colors.textSecondary),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Todavía no reservaste ningún turno.',
              textAlign: TextAlign.center,
              style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Buscar Negocios',
              icon: Icons.search,
              radiusVariant: AppButtonRadius.card,
              expand: false,
              onPressed: onIrABuscar,
            ),
          ],
        ),
      ),
    );
  }
}
