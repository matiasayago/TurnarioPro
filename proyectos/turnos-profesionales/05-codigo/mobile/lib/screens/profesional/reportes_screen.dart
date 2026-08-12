import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Reportes y Estadísticas (Panel Profesional > Reportes y Estadísticas, HU-28) — pantalla
/// NUEVA, no reemplaza ningún placeholder con contenido propio (antes iba directo a
/// `ProximamenteScreen`, ver `configuracion_screen.dart`).
///
/// Contrato: `GET /profesionales/:id/reportes?desde=<ISO>&hasta=<ISO>&servicio_id=<uuid>` (los 3
/// query params son opcionales e independientes) -> `{ desde, hasta, servicio_id,
/// turnos_totales, turnos_completados, turnos_cancelados, monto_facturado }`.
///
/// v1 simplificada a propósito (ya decidido por Backend, no se reabre acá): sin gráficos, sin
/// exportar, sin filtro por profesional (este endpoint ya está scopeado a uno) ni por servicio.
/// Las 4 métricas se muestran como `StatCard`/`StatCardGrid` (mismo componente del sistema de
/// diseño que ya usan Dashboard y Gestión de Pacientes) + un selector de período simple
/// (Todo/7 días/Mes/Año), calculado del lado del cliente sobre `DateTime.now()` — no hay un
/// selector de rango arbitrario con calendario, para no invertir tiempo en UI elaborada antes de
/// que la versión sin filtros esté andando.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

enum _Periodo { todo, semana, mes, anio }

extension on _Periodo {
  String get etiqueta => switch (this) {
        _Periodo.todo => 'Todo',
        _Periodo.semana => '7 días',
        _Periodo.mes => 'Mes',
        _Periodo.anio => 'Año',
      };
}

class _ReportesScreenState extends State<ReportesScreen> {
  _Periodo _periodo = _Periodo.todo;
  late Future<_ReporteDatos> _futureReporte;

  @override
  void initState() {
    super.initState();
    _futureReporte = _cargar();
  }

  /// Rango [desde, hasta] en UTC ISO-8601 para el período elegido, o `(null, null)` para "Todo"
  /// (sin filtro — el backend interpreta cualquiera de los 2 ausentes como "sin límite" de ese
  /// lado, ver `reportesQuerySchema` en `profesionales.ts`). Se resuelve en UTC (no la hora local
  /// sin offset) para que el backend lo interprete de forma inequívoca sin importar en qué zona
  /// horaria corra el servidor — `fechaIsoSchema` solo exige que `Date` pueda parsearlo.
  (String?, String?) _rangoIsoPara(_Periodo periodo) {
    if (periodo == _Periodo.todo) return (null, null);
    final ahora = DateTime.now();
    final hoyInicio = DateTime(ahora.year, ahora.month, ahora.day);
    final desde = switch (periodo) {
      _Periodo.semana => hoyInicio.subtract(const Duration(days: 6)),
      _Periodo.mes => DateTime(ahora.year, ahora.month, 1),
      _Periodo.anio => DateTime(ahora.year, 1, 1),
      _Periodo.todo => hoyInicio,
    };
    return (desde.toUtc().toIso8601String(), ahora.toUtc().toIso8601String());
  }

  Future<_ReporteDatos> _cargar() async {
    final sesion = context.read<Sesion>();
    final (desde, hasta) = _rangoIsoPara(_periodo);
    final params = <String>[
      if (desde != null) 'desde=$desde',
      if (hasta != null) 'hasta=$hasta',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await sesion.api.getMap('/profesionales/${sesion.profesionalId}/reportes$query');
    return _ReporteDatos.fromApi(data);
  }

  void _cambiarPeriodo(_Periodo periodo) {
    if (periodo == _periodo) return;
    setState(() {
      _periodo = periodo;
      _futureReporte = _cargar();
    });
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futureReporte = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '📊',
        title: 'Reportes y Estadísticas',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            _sectionCard(
              context,
              title: 'Período',
              child: SegmentedButton<_Periodo>(
                showSelectedIcon: false,
                segments: [for (final p in _Periodo.values) ButtonSegment(value: p, label: Text(p.etiqueta))],
                selected: {_periodo},
                onSelectionChanged: (seleccion) => _cambiarPeriodo(seleccion.first),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<_ReporteDatos>(
              future: _futureReporte,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'No se pudo cargar el reporte: ${snapshot.error}',
                        style: AppTypography.body(context),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final reporte = snapshot.data!;
                return StatCardGrid(
                  cards: [
                    StatCard(value: '${reporte.turnosTotales}', label: 'Turnos totales', icon: Icons.event_note_outlined),
                    StatCard(
                      value: '${reporte.turnosCompletados}',
                      label: 'Turnos completados',
                      icon: Icons.check_circle_outline,
                    ),
                    StatCard(
                      value: '${reporte.turnosCancelados}',
                      label: 'Turnos cancelados',
                      icon: Icons.cancel_outlined,
                    ),
                    StatCard(
                      value: '\$${_formatMonto(reporte.montoFacturado)}',
                      label: 'Monto facturado',
                      icon: Icons.attach_money,
                      emphasize: true,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
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

/// Igual criterio de formato que `precios_senas_screen.dart` (`_formatMonto`, no compartido a
/// propósito — mismo criterio de duplicación puntual entre pantallas ya establecido en este
/// paquete, ver `_FeedbackBanner`/`_sectionCard` repetidos en varias pantallas de Configuración).
String _formatMonto(num valor) {
  if (valor == valor.roundToDouble()) return valor.toStringAsFixed(0);
  return valor.toStringAsFixed(2);
}

class _ReporteDatos {
  const _ReporteDatos({
    required this.turnosTotales,
    required this.turnosCompletados,
    required this.turnosCancelados,
    required this.montoFacturado,
  });

  final int turnosTotales;
  final int turnosCompletados;
  final int turnosCancelados;
  final num montoFacturado;

  factory _ReporteDatos.fromApi(Map<String, dynamic> json) => _ReporteDatos(
        turnosTotales: json['turnos_totales'] as int,
        turnosCompletados: json['turnos_completados'] as int,
        turnosCancelados: json['turnos_cancelados'] as int,
        montoFacturado: json['monto_facturado'] as num,
      );
}
