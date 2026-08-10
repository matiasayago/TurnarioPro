import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'agenda_screen.dart';

/// Dashboard (Profesional) — HU-27, pantalla nueva (no reemplaza nada existente). Wireframe
/// corregido completo en `mapa-pantallas.md` §5.2bis.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<_TurnoDashboard>> _futureTurnos;

  // HU-27 pide un stat de "Completadas" y una acción "marcar como completada" por turno, pero
  // el backend actual (`estado_turno`, migrations/001_init.sql) no tiene un estado
  // "completado" ni un endpoint para transicionar un turno a ese estado (solo
  // pendiente_de_pago/confirmado/cancelado/reprogramado, ver routes/turnos.ts). Hasta que
  // Backend lo agregue, "marcar como completada" es una simulación local de esta sesión (no
  // persiste, se pierde si se recarga la pantalla) — se documenta acá en vez de fingir una
  // llamada a una API que no existe (CLAUDE.md: sincronizar contra las APIs publicadas, no
  // inventar lógica de negocio en el cliente).
  final Set<String> _completadosLocalmente = {};

  @override
  void initState() {
    super.initState();
    _futureTurnos = _cargarTurnos();
  }

  Future<List<_TurnoDashboard>> _cargarTurnos() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/profesionales/${sesion.profesionalId}/turnos');
    return raw.map((e) => _TurnoDashboard.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargarTurnos();
    setState(() => _futureTurnos = next);
    await next;
  }

  void _marcarCompletada(String turnoId) {
    setState(() => _completadosLocalmente.add(turnoId));
  }

  bool _esHoy(DateTime fecha) {
    final hoy = DateTime.now();
    return fecha.year == hoy.year && fecha.month == hoy.month && fecha.day == hoy.day;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fechaFormateada = _capitalize(DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'es').format(DateTime.now()));

    return Scaffold(
      // §7.7bis: Dashboard usa header `surface` (blanco), no `primary` — corrección puntual
      // sobre §7.7, confirmada en mapa-pantallas.md §5.2bis.
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        // No hay claim `nombre` en el JWT (ver auth.ts: sub/rol/negocio_id/profesional_id
        // únicamente) — se evita inventar un nombre/título ("Dr. García") que la app no puede
        // conocer todavía.
        title: '¡Hola!',
        subtitle: fechaFormateada,
        actions: [
          IconButton(
            // §7.7bis/§5.2bis: la captura real muestra este ícono de "cambiar de vista" en el
            // header del Dashboard; su comportamiento sigue sin definir (HU-27, pregunta
            // abierta #6 del backlog) — no-op a propósito.
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Cambiar de vista',
            onPressed: () => _avisoNoDisponible(context, 'Cambiar de vista todavía no está definido.'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_TurnoDashboard>>(
          future: _futureTurnos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(child: Text('No se pudo cargar el dashboard: ${snapshot.error}', style: AppTypography.body(context))),
                ],
              );
            }

            final turnosHoy = (snapshot.data ?? [])
                .where((t) => _esHoy(t.inicio))
                .toList()
              ..sort((a, b) => a.inicio.compareTo(b.inicio));
            final pacientesHoy = turnosHoy.map((t) => t.cliente).toSet().length;
            final completadas = turnosHoy.where((t) => _completadosLocalmente.contains(t.id)).length;
            final pendientes = turnosHoy.length - completadas;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                StatCardGrid(cards: [
                  StatCard(value: '$pacientesHoy', label: 'Pacientes hoy', icon: Icons.people_outline),
                  StatCard(value: '$pendientes', label: 'Citas pendientes', icon: Icons.schedule_outlined),
                  StatCard(
                    value: '$completadas',
                    label: 'Completadas',
                    icon: Icons.check_circle_outline,
                    emphasize: true,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Próximas citas', style: AppTypography.sectionTitle(context)),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaScreen())),
                      child: Text('Ver agenda >', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (turnosHoy.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: Text('No tenés citas para hoy.', style: AppTypography.body(context))),
                  )
                else
                  for (final turno in turnosHoy) ...[
                    _ProximaCitaCard(
                      turno: turno,
                      completada: _completadosLocalmente.contains(turno.id),
                      onCompletar: () => _marcarCompletada(turno.id),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        tooltip: 'Agendar Cita',
        onPressed: () => _avisoNoDisponible(context, 'Agendar Cita todavía no está disponible.'),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _avisoNoDisponible(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _TurnoDashboard {
  const _TurnoDashboard({
    required this.id,
    required this.cliente,
    required this.servicio,
    required this.inicio,
    required this.estado,
  });

  final String id;
  final String cliente;
  final String servicio;
  final DateTime inicio;
  final TurnoEstado estado;

  factory _TurnoDashboard.fromApi(Map<String, dynamic> json) {
    return _TurnoDashboard(
      id: json['id'] as String,
      cliente: json['cliente'] as String,
      servicio: json['servicio'] as String,
      inicio: DateTime.parse(json['inicio'] as String).toLocal(),
      estado: turnoEstadoFromApi(json['estado'] as String),
    );
  }
}

/// §5.2bis — card enriquecida de "Próximas citas": franja de acento a la izquierda,
/// `StatusPill`, botón ancho "✓✓ Marcar como completada" debajo del contenido.
///
/// Nota de diseño: no se pudo confirmar en las capturas si la franja de acento representa el
/// color del estado del turno o es puramente decorativa (sistema-diseno.md §12.4). Esta
/// implementación la ata al color del estado (igual que el `StatusPill` adyacente) por ser la
/// interpretación más consistente a falta de una regla confirmada — fácil de desacoplar si
/// UX/UI define lo contrario más adelante.
class _ProximaCitaCard extends StatelessWidget {
  const _ProximaCitaCard({required this.turno, required this.completada, required this.onCompletar});

  final _TurnoDashboard turno;
  final bool completada;
  final VoidCallback onCompletar;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final estado = completada ? TurnoEstado.completada : turno.estado;
    final acento = switch (estado) {
      TurnoEstado.confirmada => colors.success.base,
      TurnoEstado.porConfirmar => colors.warning.base,
      TurnoEstado.programada => colors.warning.base,
      TurnoEstado.cancelada => colors.danger.base,
      TurnoEstado.completada => colors.neutral.base,
    };
    final hora = DateFormat('HH:mm').format(turno.inicio);

    // Patrón estándar de Flutter para "card con sombra + contenido con esquinas recortadas": el
    // contenedor externo lleva la sombra (sin clip, para que no se corte), el ClipRRect interno
    // recorta la franja de acento + el fondo a las esquinas redondeadas.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          color: colors.surface,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: acento),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                turno.cliente,
                                style: AppTypography.subtitle(context)
                                    .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StatusPill.turno(estado),
                          ],
                        ),
                        Text(turno.servicio, style: AppTypography.caption(context)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(hora, style: AppTypography.body(context).copyWith(color: acento, fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.md),
                        if (completada)
                          OutlineButton(label: '✓✓ Completada', onPressed: null, radiusVariant: AppButtonRadius.card)
                        else
                          PrimaryButton(
                            label: '✓✓ Marcar como completada',
                            onPressed: onCompletar,
                            radiusVariant: AppButtonRadius.card,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
