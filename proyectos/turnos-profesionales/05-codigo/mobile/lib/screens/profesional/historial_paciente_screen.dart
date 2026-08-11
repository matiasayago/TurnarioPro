import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

final DateFormat _formatoFechaHora = DateFormat('d MMM yyyy · HH:mm', 'es');
final DateFormat _formatoFecha = DateFormat('d MMM yyyy', 'es');

String _formatoCosto(num? costo) => costo == null ? 'Sin costo definido' : '\$${costo.toStringAsFixed(0)}';

DateTime? _parseFechaSegura(String? raw) => raw == null ? null : DateTime.tryParse(raw)?.toLocal();

/// Historial de Paciente enriquecido — HU-11 + HU-21 (`mapa-pantallas.md` §5.10). Solo lectura en
/// esta ronda: no agrega acciones de crear tratamiento/nota médica (quedan para otra ronda).
/// Mismo criterio de privacidad que el resto de Gestión de Pacientes (RN7/D3) — el backend ya
/// filtra por el `profesional_id` del JWT, esta pantalla nunca puede traer el historial de otro
/// profesional aunque lo intentara.
class HistorialPacienteScreen extends StatefulWidget {
  const HistorialPacienteScreen({super.key, required this.pacienteId, required this.pacienteNombre});

  final String pacienteId;
  final String pacienteNombre;

  @override
  State<HistorialPacienteScreen> createState() => _HistorialPacienteScreenState();
}

class _HistorialPacienteScreenState extends State<HistorialPacienteScreen> {
  late Future<_Historial> _futureHistorial;

  @override
  void initState() {
    super.initState();
    _futureHistorial = _cargar();
  }

  Future<_Historial> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api
        .getMap('/profesionales/${sesion.profesionalId}/pacientes/${widget.pacienteId}/historial');
    return _Historial.fromApi(raw);
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futureHistorial = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '✱',
        title: 'Historial de ${widget.pacienteNombre}',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_Historial>(
          future: _futureHistorial,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text(
                      'No se pudo cargar el historial: ${snapshot.error}',
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            final historial = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                StatCardGrid(cards: [
                  StatCard(
                    value: '${historial.resumen.citasTotales}',
                    label: 'Citas totales',
                    icon: Icons.event_outlined,
                  ),
                  StatCard(
                    value: '${historial.resumen.citasCompletadas}',
                    label: 'Completadas',
                    icon: Icons.check_circle_outline,
                    emphasize: true,
                  ),
                  StatCard(
                    value: '${historial.resumen.tratamientos}',
                    label: 'Tratamientos',
                    icon: Icons.healing_outlined,
                  ),
                  StatCard(
                    value: '${historial.resumen.notasMedicas}',
                    label: 'Notas médicas',
                    icon: Icons.notes_outlined,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                Text('Turnos', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.turnos.isEmpty)
                  const _EstadoVacio(texto: 'Sin turnos registrados todavía.')
                else
                  for (final t in historial.turnos) ...[
                    _TurnoCard(turno: t),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text('Tratamientos', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.tratamientos.isEmpty)
                  const _EstadoVacio(texto: 'Sin tratamientos registrados todavía.')
                else
                  for (final t in historial.tratamientos) ...[
                    _TratamientoCard(tratamiento: t),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text('Notas médicas', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                if (historial.notasMedicas.isEmpty)
                  const _EstadoVacio(texto: 'Sin notas médicas registradas todavía.')
                else
                  for (final n in historial.notasMedicas) ...[
                    _NotaMedicaCard(nota: n),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Historial {
  const _Historial({
    required this.resumen,
    required this.turnos,
    required this.tratamientos,
    required this.notasMedicas,
  });

  final _Resumen resumen;
  final List<_Turno> turnos;
  final List<_Tratamiento> tratamientos;
  final List<_NotaMedica> notasMedicas;

  factory _Historial.fromApi(Map<String, dynamic> json) {
    return _Historial(
      resumen: _Resumen.fromApi(json['resumen'] as Map<String, dynamic>),
      turnos: (json['turnos'] as List<dynamic>).map((e) => _Turno.fromApi(e as Map<String, dynamic>)).toList(),
      tratamientos: (json['tratamientos'] as List<dynamic>)
          .map((e) => _Tratamiento.fromApi(e as Map<String, dynamic>))
          .toList(),
      notasMedicas: (json['notas_medicas'] as List<dynamic>)
          .map((e) => _NotaMedica.fromApi(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _Resumen {
  const _Resumen({
    required this.citasTotales,
    required this.citasCompletadas,
    required this.tratamientos,
    required this.notasMedicas,
  });

  final int citasTotales;
  final int citasCompletadas;
  final int tratamientos;
  final int notasMedicas;

  factory _Resumen.fromApi(Map<String, dynamic> json) => _Resumen(
        citasTotales: json['citas_totales'] as int,
        citasCompletadas: json['citas_completadas'] as int,
        tratamientos: json['tratamientos'] as int,
        notasMedicas: json['notas_medicas'] as int,
      );
}

class _Turno {
  const _Turno({
    required this.inicio,
    required this.estadoPago,
    required this.servicio,
    required this.costo,
    required this.profesional,
    required this.duracionMin,
  });

  final DateTime inicio;
  final TurnoEstado estadoPago;
  final String servicio;
  final num? costo;
  final String profesional;
  final int duracionMin;

  factory _Turno.fromApi(Map<String, dynamic> json) => _Turno(
        inicio: DateTime.parse(json['inicio'] as String).toLocal(),
        estadoPago: turnoEstadoFromApi(json['estado_pago'] as String),
        servicio: json['servicio'] as String,
        costo: json['costo'] as num?,
        profesional: json['profesional'] as String,
        duracionMin: json['duracion_min'] as int,
      );
}

class _Tratamiento {
  const _Tratamiento({required this.descripcion, required this.fechaInicio, required this.fechaFin});

  final String descripcion;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  factory _Tratamiento.fromApi(Map<String, dynamic> json) => _Tratamiento(
        descripcion: json['descripcion'] as String,
        fechaInicio: _parseFechaSegura(json['fecha_inicio'] as String?),
        fechaFin: _parseFechaSegura(json['fecha_fin'] as String?),
      );
}

class _NotaMedica {
  const _NotaMedica({required this.fecha, required this.texto});

  final DateTime? fecha;
  final String texto;

  factory _NotaMedica.fromApi(Map<String, dynamic> json) => _NotaMedica(
        fecha: _parseFechaSegura(json['fecha'] as String?),
        texto: json['texto'] as String,
      );
}

class _TurnoCard extends StatelessWidget {
  const _TurnoCard({required this.turno});

  final _Turno turno;

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
              Expanded(
                child: Text(
                  _formatoFechaHora.format(turno.inicio),
                  style: AppTypography.subtitle(context)
                      .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusPill.turno(turno.estadoPago),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(turno.servicio, style: AppTypography.body(context)),
          const SizedBox(height: 2),
          Text(
            'Profesional: ${turno.profesional} · Duración: ${turno.duracionMin} min',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: 2),
          Text('Costo: ${_formatoCosto(turno.costo)}', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

class _TratamientoCard extends StatelessWidget {
  const _TratamientoCard({required this.tratamiento});

  final _Tratamiento tratamiento;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final inicio =
        tratamiento.fechaInicio != null ? _formatoFecha.format(tratamiento.fechaInicio!) : 'fecha no informada';
    final finTexto = tratamiento.fechaFin != null ? ' · Finalizado ${_formatoFecha.format(tratamiento.fechaFin!)}' : ' · En curso';
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
          Text(tratamiento.descripcion, style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Iniciado $inicio$finTexto', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

class _NotaMedicaCard extends StatelessWidget {
  const _NotaMedicaCard({required this.nota});

  final _NotaMedica nota;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fecha = nota.fecha != null ? _formatoFecha.format(nota.fecha!) : 'Fecha no informada';
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
          Text(fecha, style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(nota.texto, style: AppTypography.body(context)),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto, style: AppTypography.caption(context));
}
