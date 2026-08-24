import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'detalle_negocio_screen.dart';

/// HU-00b / CU3: el cliente descubre negocios disponibles en la plataforma (multi-tenant, D1).
/// Pestaña raíz "Buscar" de `ClienteShell` (índice `_tabBuscar`, ver ese archivo).
///
/// Fast-follow del CEO (2026-08-18): esta pantalla pasa de ser una lista simple de negocios a un
/// dashboard, mismo espíritu que `profesional/dashboard_screen.dart` (saludo + fecha en el
/// header, secciones dentro de un único `ListView`) — se mantiene el nombre de archivo/clase
/// `BuscarNegociosScreen` a propósito: `cliente_shell.dart` y `MisTurnosScreen.onIrABuscar` ya lo
/// referencian, renombrar es riesgo innecesario. Dos agregados sobre la versión anterior:
/// - "Tus próximos turnos": preview de `GET /turnos/mios` (mismo endpoint que
///   `mis_turnos_screen.dart`, sin endpoint nuevo ni lógica de negocio duplicada) — ver
///   [_cargarTurnos]. El botón "Nueva Cita" no navega a ningún lado (a diferencia del FAB
///   equivalente de Profesional): hace scroll dentro de esta misma pantalla hasta la sección de
///   negocios, ver [_irANegocios].
/// - Búsqueda por texto: además de nombre/rubro/ubicación (filtro LOCAL sobre el `GET /negocios`
///   sin filtro, cacheado una sola vez) cubre servicios ofrecidos vía
///   `GET /negocios?servicio=texto` (HU-00b, fast-follow 2026-08-18) — ver [_buscar].
class BuscarNegociosScreen extends StatefulWidget {
  const BuscarNegociosScreen({super.key, this.onTurnoConfirmado});

  /// Task #115: callback que se propaga a través de DetalleNegocioScreen, ElegirProfesionalScreen,
  /// HorariosDisponiblesScreen, y finalmente a ConfirmarTurnoScreen — se ejecuta después de crear
  /// un turno para cambiar el tab de ClienteShell a "Mis Turnos" sin destruir la pila.
  final VoidCallback? onTurnoConfirmado;

  @override
  State<BuscarNegociosScreen> createState() => _BuscarNegociosScreenState();
}

class _BuscarNegociosScreenState extends State<BuscarNegociosScreen> {
  // `GET /negocios` sin filtro — un solo fetch, reusado tanto para "sin búsqueda" como para la
  // fuente del filtro LOCAL por nombre/rubro/ubicación cuando hay texto (ver [_buscar]): un
  // `Future` de Dart corre su cuerpo una única vez, así que esperarlo de nuevo no dispara un
  // segundo request.
  late Future<List<dynamic>> _negociosCache;
  late Future<List<_TurnoProximo>> _turnosFuture;

  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  // No nulo solo mientras `_query` no está vacío (ver [_onBusquedaCambiada]/[_refrescar]).
  Future<List<dynamic>>? _resultadoBusqueda;

  // Ancla para el scroll interno del botón "Nueva Cita" (ver doc-comment de la clase).
  final _negociosSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _negociosCache = sesion.api.getList('/negocios');
    _turnosFuture = _cargarTurnos();
    _busquedaCtrl.addListener(_onBusquedaCambiada);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<List<_TurnoProximo>> _cargarTurnos() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/turnos/mios');
    final ahora = DateTime.now();
    final turnos = raw
        .map((e) => e as Map<String, dynamic>)
        // Mismo criterio de "gestionable" que ya usa `mis_turnos_screen.dart` — acá además decide
        // inclusión (no solo si se muestran acciones): un turno cancelado, o uno ya pasado, no es
        // una "próxima cita".
        .where((t) => t['estado'] == 'confirmado' || t['estado'] == 'pendiente_de_pago')
        .map(_TurnoProximo.fromApi)
        .where((t) => t.inicio.isAfter(ahora))
        .toList()
      ..sort((a, b) => a.inicio.compareTo(b.inicio));
    // Preview de dashboard, no el listado completo (eso ya lo cubre "Mis Turnos") — tope de 3.
    return turnos.take(3).toList();
  }

  Future<void> _refrescar() async {
    final api = context.read<Sesion>().api;
    final nuevosTurnos = _cargarTurnos();
    final nuevosNegocios = api.getList('/negocios');
    setState(() {
      _turnosFuture = nuevosTurnos;
      _negociosCache = nuevosNegocios;
      if (_query.isNotEmpty) _resultadoBusqueda = _buscar(_query);
    });
    final busqueda = _resultadoBusqueda;
    await nuevosTurnos;
    await nuevosNegocios;
    if (busqueda != null) await busqueda;
  }

  // Debounce ~400ms (pedido explícito del CEO) para no disparar un `GET /negocios?servicio=`
  // contra el backend por cada tecla.
  void _onBusquedaCambiada() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final texto = _busquedaCtrl.text.trim();
      setState(() {
        _query = texto;
        _resultadoBusqueda = texto.isEmpty ? null : _buscar(texto);
      });
    });
  }

  /// Unión de (a) filtro LOCAL sobre `_negociosCache` ya resuelto (nombre/rubro/ubicación —
  /// cubre "buscar por negocio") y (b) `GET /negocios?servicio=texto` (nombre de servicio
  /// ofrecido — cubre "buscar por servicio", HU-00b fast-follow 2026-08-18), sin duplicar por
  /// `id`.
  Future<List<dynamic>> _buscar(String texto) async {
    // Capturado ANTES del único `await` real de este método (la búsqueda por servicio, más abajo)
    // para no tocar `context` después de un gap async si el widget ya se desmontó mientras tanto.
    final api = context.read<Sesion>().api;
    final todos = await _negociosCache;
    final q = texto.toLowerCase();
    final local = todos.where((n) {
      final m = n as Map<String, dynamic>;
      return [m['nombre'], m['rubro'], m['ubicacion']]
          .whereType<String>()
          .any((campo) => campo.toLowerCase().contains(q));
    }).toList();

    List<dynamic> porServicio;
    try {
      porServicio = await api.getList('/negocios?servicio=${Uri.encodeQueryComponent(texto)}');
    } catch (_) {
      // El filtro por servicio suma sobre el local (que ya cubre "buscar por negocio") — si
      // falla, no tiene sentido tirar abajo resultados locales válidos.
      porServicio = const [];
    }

    final vistos = <String>{};
    final combinados = <dynamic>[];
    for (final n in [...local, ...porServicio]) {
      if (vistos.add((n as Map<String, dynamic>)['id'] as String)) combinados.add(n);
    }
    return combinados;
  }

  void _irANegocios() {
    final ctx = _negociosSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final fechaFormateada = _capitalize(DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'es').format(DateTime.now()));

    return Scaffold(
      // Mismos criterios que el Dashboard de Profesional: header `surface`, saludo genérico (no
      // hay claim `nombre` en el JWT, ver ese archivo) + fecha del día.
      appBar: AppHeader(variant: AppHeaderVariant.surface, title: '¡Hola!', subtitle: fechaFormateada),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            _seccionProximosTurnos(context),
            const SizedBox(height: AppSpacing.xl),
            _seccionBuscarNegocios(context),
          ],
        ),
      ),
    );
  }

  Widget _seccionProximosTurnos(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tus próximos turnos', style: AppTypography.sectionTitle(context)),
        const SizedBox(height: AppSpacing.sm),
        FutureBuilder<List<_TurnoProximo>>(
          future: _turnosFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final turnos = snapshot.data!;
            // Mensaje simple a propósito (no el tratamiento grande de `_EstadoVacio`): esta
            // pantalla ya tiene más contenido debajo, a diferencia de `mis_turnos_screen.dart`.
            if (turnos.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('Todavía no tenés turnos próximos.', style: AppTypography.body(context)),
              );
            }
            return Column(
              children: [
                for (final t in turnos) ...[
                  _TurnoProximoCard(turno: t),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          label: 'Nueva Cita',
          icon: Icons.add,
          expand: false,
          radiusVariant: AppButtonRadius.card,
          onPressed: _irANegocios,
        ),
      ],
    );
  }

  Widget _seccionBuscarNegocios(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _busquedaCtrl,
          decoration: const InputDecoration(
            hintText: 'Buscar por negocio o servicio...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Column(
          key: _negociosSectionKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Negocios disponibles', style: AppTypography.sectionTitle(context)),
            const SizedBox(height: AppSpacing.sm),
            _listaNegocios(context),
          ],
        ),
      ],
    );
  }

  Widget _listaNegocios(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _query.isEmpty ? _negociosCache : _resultadoBusqueda,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final negocios = snapshot.data!;
        if (negocios.isEmpty) {
          return _EstadoVacio(
            icon: _query.isEmpty ? Icons.storefront_outlined : Icons.search_off,
            texto: _query.isEmpty
                ? 'Todavía no hay negocios cargados.'
                : 'No encontramos resultados para tu búsqueda.',
          );
        }
        return Column(
          children: [
            for (final n in negocios) ...[
              _NegocioCard(
                nombre: (n as Map<String, dynamic>)['nombre'] as String,
                detalle: [n['rubro'], n['ubicacion']].whereType<String>().join(' · '),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DetalleNegocioScreen(negocioId: n['id'] as String, nombreNegocio: n['nombre'] as String, onTurnoConfirmado: onTurnoConfirmado),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Turno propio "gestionable" (ver [_BuscarNegociosScreenState._cargarTurnos]) — solo lo mínimo
/// que necesita esta preview: fecha/hora + estado. A diferencia de `mis_turnos_screen.dart`, acá
/// no hace falta el `id` (esta card no tiene acciones de Reprogramar/Cancelar, ver
/// [_TurnoProximoCard]).
class _TurnoProximo {
  const _TurnoProximo({required this.inicio, required this.estado});

  final DateTime inicio;
  final TurnoEstado estado;

  factory _TurnoProximo.fromApi(Map<String, dynamic> json) => _TurnoProximo(
        inicio: DateTime.parse(json['inicio'] as String).toLocal(),
        estado: turnoEstadoFromApi(json['estado'] as String),
      );
}

/// Card compacta de "Tus próximos turnos" — mismo encabezado (ícono + fecha + `StatusPill.turno`)
/// que `_TurnoCard` de `mis_turnos_screen.dart`, sin las acciones de Reprogramar/Cancelar: esto es
/// una preview de dashboard, la gestión completa vive en la pestaña "Mis Turnos".
class _TurnoProximoCard extends StatelessWidget {
  const _TurnoProximoCard({required this.turno});

  final _TurnoProximo turno;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fechaTexto = DateFormat('EEE d MMM · HH:mm', 'es').format(turno.inicio);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              fechaTexto,
              style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusPill.turno(turno.estado),
        ],
      ),
    );
  }
}

/// Fila de negocio — tarjeta completa tappeable (`InkWell` + sombra propia), mismo criterio
/// visual que `administrador/pacientes_negocio_screen.dart` (`_PacienteNegocioCard`): sin
/// acciones en la card, un único destino posible, `chevron_right` como única señal de
/// navegación.
class _NegocioCard extends StatelessWidget {
  const _NegocioCard({required this.nombre, required this.detalle, required this.onTap});

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
                child: Icon(Icons.storefront_outlined, color: colors.primary),
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
                    if (detalle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(detalle, style: AppTypography.caption(context)),
                    ],
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

/// Estado vacío con ícono — mismo tratamiento que `_SinNegocioView`
/// (`profesional/dashboard_screen.dart`), duplicado localmente a propósito (cada pantalla de
/// este código ya define sus propios widgets privados en vez de compartir uno común). Reusado acá
/// para dos casos con distinto ícono/texto: sin negocios cargados (backend vacío) y sin
/// resultados de búsqueda (ver `_listaNegocios`).
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
