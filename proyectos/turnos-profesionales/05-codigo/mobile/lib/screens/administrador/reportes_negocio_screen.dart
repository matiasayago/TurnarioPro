import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Reportes y Estadísticas — vista de NEGOCIO/administrador (Panel Administrador, HU-28/E10,
/// `02-backlog/backlog.md`). Completa, del lado de administrador, lo que ya existía del lado
/// profesional (`profesional/reportes_screen.dart`, sin cambios — pantalla HERMANA, mismo patrón
/// visual, no reemplazada por esta): esa mitad quedó documentada explícitamente como scopeada a
/// un único profesional, con la vista agregada de negocio diferida a un endpoint nuevo aparte. Ese
/// endpoint ya se construyó (ver `backend/src/routes/negocios.ts`, bloque de comentarios
/// "Reportes y Estadísticas" al final del archivo) y esta es la pantalla que lo consume.
///
/// Contrato: `GET /negocios/:id/reportes?desde=<ISO>&hasta=<ISO>&servicio_id=<uuid>&
/// profesional_id=<uuid>` (los 4 query params son opcionales e independientes,
/// `requireAuth('administrador')`) -> `{ desde, hasta, servicio_id, profesional_id,
/// turnos_totales, turnos_completados, turnos_cancelados, monto_facturado }` — MISMO shape que
/// `GET /profesionales/:id/reportes` (mismas definiciones de cada métrica, ver ese bloque de
/// comentarios en `profesionales.ts` para el detalle completo, no repetido acá), más
/// `profesional_id` como eco del filtro aplicado.
///
/// 2 diferencias respecto de `reportes_screen.dart`, ambas ya anticipadas por los propios
/// comentarios de esa pantalla/del backend:
/// - **Filtro por profesional** (nuevo acá — HU-28 lo pide explícitamente para la vista de
///   negocio: "filtrable por período, por profesional y por servicio"): dropdown con "Todos" (sin
///   filtro, default) + la lista de profesionales del negocio, reutilizando el endpoint YA
///   EXISTENTE `GET /negocios/:id/profesionales` (el mismo que ya consume
///   `profesionales_negocio_screen.dart`, mismo shape `{id, nombre, email, activo}` — acá solo se
///   usan `id`/`nombre`). Se carga una única vez ([_futureProfesionales], no depende del período)
///   y separado del reporte en sí ([_futureReporte]), para no repetir ese GET en cada cambio de
///   filtro.
/// - El reporte agrega TODOS los profesionales del negocio a la vez (lo que pide HU-28 para el
///   rol administrador: `t.negocio_id = :id` del lado del backend), en vez de la agenda de uno
///   solo como hace la mitad profesional.
///
/// Todo lo demás es intencionalmente idéntico a `reportes_screen.dart`, duplicado localmente a
/// propósito (mismo criterio de duplicación puntual ya establecido en este paquete, ver el propio
/// comentario de esa pantalla):
/// - Selector de período (Todo/7 días/Mes/Año, `_Periodo`/`_rangoIsoPara` calcados tal cual — es
///   lógica de cliente sin nada específico del profesional ni del negocio).
/// - **Sin filtro por servicio en la UI**: el backend ya acepta `servicio_id` como filtro más,
///   pero HU-28 no lo prioriza para esta v1 y `reportes_screen.dart` ya tomó la misma decisión
///   para su propia mitad de este contrato — se mantiene la consistencia entre las dos pantallas
///   hermanas en vez de reabrir esa decisión acá.
/// - Sin gráficos ni exportar (HU-28 los deja explícitamente fuera de este alcance básico).
/// - Las 4 métricas se muestran con `StatCard`/`StatCardGrid`, igual que el resto de la app.
class ReportesNegocioScreen extends StatefulWidget {
  const ReportesNegocioScreen({super.key});

  @override
  State<ReportesNegocioScreen> createState() => _ReportesNegocioScreenState();
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

class _ReportesNegocioScreenState extends State<ReportesNegocioScreen> {
  _Periodo _periodo = _Periodo.todo;

  /// `null` = "Todos" (sin filtro, default) — mismo valor que `profesional.id` en cada elemento
  /// que devuelve `GET /negocios/:id/profesionales` (ver [_Profesional]).
  String? _profesionalId;

  late Future<_ReporteDatos> _futureReporte;
  late Future<List<_Profesional>> _futureProfesionales;

  @override
  void initState() {
    super.initState();
    // Mismo guard defensivo que el resto de las pantallas de este shell (`ServiciosNegocioScreen`,
    // `ProfesionalesNegocioScreen`, `PacientesNegocioScreen`, `FichaPacienteNegocioScreen`): en la
    // práctica esta pantalla sólo es alcanzable desde `AdministradorShell` cuando ya hay
    // `negocioId` (el ítem de menú vive dentro del `if (sesion.negocioId == null) ... else`), pero
    // se mantiene el mismo chequeo por si el criterio de esa pantalla cambia más adelante.
    final sesion = context.read<Sesion>();
    final sinNegocio = sesion.negocioId == null;
    _futureReporte = sinNegocio
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargarReporte();
    _futureProfesionales = sinNegocio
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargarProfesionales();
  }

  /// Idéntico a `reportes_screen.dart` (`_rangoIsoPara`), duplicado local a propósito — ver el
  /// comentario de esa pantalla para el razonamiento completo (por qué UTC, por qué sin selector
  /// de calendario arbitrario). Rango [desde, hasta] en UTC ISO-8601 para el período elegido, o
  /// `(null, null)` para "Todo" (sin filtro).
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

  Future<_ReporteDatos> _cargarReporte() async {
    final sesion = context.read<Sesion>();
    final (desde, hasta) = _rangoIsoPara(_periodo);
    final params = <String>[
      if (desde != null) 'desde=$desde',
      if (hasta != null) 'hasta=$hasta',
      if (_profesionalId != null) 'profesional_id=$_profesionalId',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await sesion.api.getMap('/negocios/${sesion.negocioId}/reportes$query');
    return _ReporteDatos.fromApi(data);
  }

  Future<List<_Profesional>> _cargarProfesionales() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/negocios/${sesion.negocioId}/profesionales');
    return raw.map((e) => _Profesional.fromApi(e as Map<String, dynamic>)).toList();
  }

  void _cambiarPeriodo(_Periodo periodo) {
    if (periodo == _periodo) return;
    setState(() {
      _periodo = periodo;
      _futureReporte = _cargarReporte();
    });
  }

  /// Dispara un nuevo `GET /reportes` con `profesional_id=<id>`, o sin ese parámetro si
  /// [profesionalId] es `null` ("Todos") — [_futureProfesionales] no se vuelve a pedir, no
  /// depende de este filtro.
  void _cambiarProfesional(String? profesionalId) {
    if (profesionalId == _profesionalId) return;
    setState(() {
      _profesionalId = profesionalId;
      _futureReporte = _cargarReporte();
    });
  }

  Future<void> _refrescar() async {
    final nextReporte = _cargarReporte();
    final nextProfesionales = _cargarProfesionales();
    setState(() {
      _futureReporte = nextReporte;
      _futureProfesionales = nextProfesionales;
    });
    await Future.wait([nextReporte, nextProfesionales]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '📊',
        title: 'Reportes del Negocio',
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
            _sectionCard(
              context,
              title: 'Profesional',
              child: FutureBuilder<List<_Profesional>>(
                future: _futureProfesionales,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Center(
                        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(
                      'No se pudo cargar la lista de profesionales: ${snapshot.error}',
                      style: AppTypography.caption(context),
                    );
                  }
                  final profesionales = snapshot.data ?? [];
                  return DropdownButtonFormField<String?>(
                    initialValue: _profesionalId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                      for (final p in profesionales)
                        DropdownMenuItem<String?>(value: p.id, child: Text(p.nombre, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _cambiarProfesional,
                  );
                },
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

/// Igual criterio de formato que `reportes_screen.dart`/`precios_senas_screen.dart`
/// (`_formatMonto`, no compartido a propósito — mismo criterio de duplicación puntual entre
/// pantallas ya establecido en este paquete).
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

/// Opción del dropdown de filtro por profesional — subconjunto de `_Profesional` de
/// `profesionales_negocio_screen.dart` (mismo `GET /negocios/:id/profesionales`, acá solo se
/// necesitan `id`/`nombre`, no `email`/`activo`). Clase propia en vez de importada de esa
/// pantalla: mismo criterio de "cada pantalla define sus propios modelos privados" ya aplicado en
/// el resto de este paquete (ver `pacientes_negocio_screen.dart`).
class _Profesional {
  const _Profesional({required this.id, required this.nombre});

  final String id;
  final String nombre;

  factory _Profesional.fromApi(Map<String, dynamic> json) =>
      _Profesional(id: json['id'] as String, nombre: json['nombre'] as String);
}
