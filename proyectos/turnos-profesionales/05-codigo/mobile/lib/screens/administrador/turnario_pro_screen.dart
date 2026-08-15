import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Turnario Pro · Suscripción (Panel Administrador, HU-29 — épica E15 "Modo Administrador v1",
/// `02-backlog/backlog.md`). Reemplaza, SOLO del lado Administrador, al placeholder
/// "Próximamente" que sigue viendo el Profesional en su propio menú de Configuración (ese ítem
/// queda sin tocar a propósito — ver `profesional/configuracion_screen.dart`, fuera del alcance de
/// esta ronda).
///
/// Contrato (`negocios.ts`, sin backend nuevo):
/// - `GET /negocios/:id/plan` (`requireAuth('administrador', 'profesional')`) -> `{ negocio_id,
///   plan, periodo, vencimiento, estado, acceso_turnario_pro, turnos_confirmados_mes: { usados,
///   limite, al_limite }, profesionales_activos: { usados, limite, al_limite } }`. `limite: null`
///   = ilimitado (Turnario Pro con acceso efectivo). El acceso REAL a mostrar es siempre
///   `acceso_turnario_pro` — nunca se re-deriva `plan`/`estado`/`vencimiento` del lado del cliente
///   (esa lógica ya vive en `dominio/suscripciones.ts`, `tieneAccesoTurnarioPro`; duplicarla acá
///   violaría el criterio de este proyecto de no reimplementar reglas de negocio en el cliente).
/// - `POST /negocios/:id/suscripcion` (`requireAuth('administrador')`), body
///   `{ periodo: 'mensual' | 'anual' }` -> activación SIMULADA/mock (sin cobro real todavía, ver
///   el comentario de ese endpoint) -> `{ plan, periodo, vencimiento, estado }`.
/// - `PATCH /negocios/:id/suscripcion/cancelar` (`requireAuth('administrador')`) -> `{ plan,
///   periodo, vencimiento, estado }` | 404 este negocio nunca se suscribió.
///
/// USD 9/mes y USD 86.40/año (20% off) son referencia de producto documentada en el propio
/// comentario de `POST /:id/suscripcion` (`negocios.ts`) — no viajan en la respuesta de la API
/// (la activación es simulada, sin cobro real todavía), se muestran acá como texto informativo
/// fijo para que el administrador pueda elegir entre mensual/anual con contexto.
class TurnarioProScreen extends StatefulWidget {
  const TurnarioProScreen({super.key});

  @override
  State<TurnarioProScreen> createState() => _TurnarioProScreenState();
}

class _TurnarioProScreenState extends State<TurnarioProScreen> {
  late Future<_PlanNegocio> _futurePlan;
  String _periodoElegido = 'mensual';

  bool _procesando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _futurePlan = sesion.negocioId == null
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargar();
  }

  Future<_PlanNegocio> _cargar() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api.getMap('/negocios/${sesion.negocioId}/plan');
    return _PlanNegocio.fromApi(data);
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futurePlan = next);
    await next;
  }

  Future<void> _activar() async {
    setState(() {
      _procesando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/negocios/${sesion.negocioId}/suscripcion', {'periodo': _periodoElegido});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turnario Pro activado.')));
      await _refrescar();
      if (mounted) setState(() => _procesando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _mensaje = 'No se pudo activar Turnario Pro: $e';
        _mensajeEsError = true;
      });
    }
  }

  Future<void> _cancelar() async {
    setState(() {
      _procesando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.patch('/negocios/${sesion.negocioId}/suscripcion/cancelar');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Suscripción cancelada.')));
      await _refrescar();
      if (mounted) setState(() => _procesando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _mensaje = 'No se pudo cancelar la suscripción: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '⭐',
        title: 'Turnario Pro · Suscripción',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<_PlanNegocio>(
          future: _futurePlan,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _CentradoScrollable(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text('No se pudo cargar tu plan: ${snapshot.error}', style: AppTypography.body(context)),
                  ),
                ],
              );
            }

            final plan = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _sectionCard(
                  context,
                  title: 'Tu plan actual',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(context, 'Plan', plan.plan == 'turnario_pro' ? 'Turnario Pro' : 'Gratis'),
                      _infoRow(context, 'Estado', _estadoLabel(plan.estado)),
                      if (plan.periodo != null)
                        _infoRow(context, 'Período', plan.periodo == 'anual' ? 'Anual' : 'Mensual'),
                      if (plan.vencimiento != null)
                        _infoRow(context, 'Vencimiento', DateFormat('d MMM yyyy', 'es').format(plan.vencimiento!)),
                      _infoRow(context, 'Acceso a Turnario Pro', plan.accesoTurnarioPro ? 'Sí' : 'No', esUltimo: true),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Uso este mes', style: AppTypography.sectionTitle(context)),
                const SizedBox(height: AppSpacing.sm),
                StatCardGrid(cards: [
                  StatCard(
                    value: plan.turnosLimite != null ? '${plan.turnosUsados}/${plan.turnosLimite}' : '${plan.turnosUsados}',
                    label: 'Turnos confirmados',
                    icon: Icons.event_note_outlined,
                  ),
                  StatCard(
                    value: plan.profesionalesLimite != null
                        ? '${plan.profesionalesUsados}/${plan.profesionalesLimite}'
                        : '${plan.profesionalesUsados}',
                    label: 'Profesionales activos',
                    icon: Icons.people_outline,
                  ),
                ]),
                const SizedBox(height: AppSpacing.lg),
                if (plan.esTurnarioProActivo) _cancelarSection(context) else _activarSection(context, plan),
                if (_mensaje != null) ...[
                  const SizedBox(height: AppSpacing.base),
                  _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),
      ),
    );
  }

  String _estadoLabel(String estado) => switch (estado) {
        'activa' => 'Activa',
        'vencida' => 'Vencida',
        'cancelada' => 'Cancelada',
        _ => estado,
      };

  Widget _activarSection(BuildContext context, _PlanNegocio plan) {
    return _sectionCard(
      context,
      title: 'Activar Turnario Pro',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (plan.estado == 'cancelada' && plan.accesoTurnarioPro)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Tu suscripción está cancelada, pero conservás el acceso hasta el vencimiento. '
                'Podés reactivarla en cualquier momento.',
                style: AppTypography.caption(context),
              ),
            ),
          Text(
            'Turnos confirmados y profesionales ilimitados, sin los límites del plan gratis (60 turnos '
            'confirmados/mes, 1 profesional activo). USD 9/mes o USD 86.40/año (20% off).',
            style: AppTypography.body(context),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'mensual', label: Text('Mensual')),
              ButtonSegment(value: 'anual', label: Text('Anual (20% off)')),
            ],
            selected: {_periodoElegido},
            onSelectionChanged: _procesando ? null : (s) => setState(() => _periodoElegido = s.first),
          ),
          const SizedBox(height: AppSpacing.base),
          PrimaryButton(
            label: 'Activar Turnario Pro',
            radiusVariant: AppButtonRadius.card,
            loading: _procesando,
            onPressed: _procesando ? null : _activar,
          ),
        ],
      ),
    );
  }

  Widget _cancelarSection(BuildContext context) {
    return _sectionCard(
      context,
      title: 'Tu suscripción',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Turnario Pro está activo. Si cancelás, conservás el acceso hasta la fecha de vencimiento — '
            'no se corta de inmediato.',
            style: AppTypography.body(context),
          ),
          const SizedBox(height: AppSpacing.base),
          WarningButton(
            label: 'Cancelar Suscripción',
            radiusVariant: AppButtonRadius.card,
            loading: _procesando,
            onPressed: _procesando ? null : _cancelar,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {bool esUltimo = false}) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: esUltimo ? 0 : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
        ],
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

/// `Center` como hijo directo de un `ListView`/`RefreshIndicator` (mismo patrón ya usado en
/// `profesional/reportes_screen.dart` para el estado de carga): con restricciones no acotadas de
/// altura, `Center` se ajusta al tamaño de su hijo en vez de reventar por altura infinita.
class _CentradoScrollable extends StatelessWidget {
  const _CentradoScrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(child: child),
        ),
      ],
    );
  }
}

/// Mismo patrón de banner de éxito/error que el resto de las pantallas de esta app (ej.
/// `profesional/editar_perfil_screen.dart`), duplicado localmente a propósito.
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

class _PlanNegocio {
  const _PlanNegocio({
    required this.plan,
    required this.periodo,
    required this.vencimiento,
    required this.estado,
    required this.accesoTurnarioPro,
    required this.turnosUsados,
    required this.turnosLimite,
    required this.profesionalesUsados,
    required this.profesionalesLimite,
  });

  final String plan; // 'gratis' | 'turnario_pro'
  final String? periodo; // 'mensual' | 'anual' | null (plan gratis)
  final DateTime? vencimiento;
  final String estado; // 'activa' | 'vencida' | 'cancelada'
  final bool accesoTurnarioPro;
  final int turnosUsados;
  final int? turnosLimite;
  final int profesionalesUsados;
  final int? profesionalesLimite;

  /// Turnario Pro con estado `activa` (no vencida ni cancelada) — decide si esta pantalla muestra
  /// "Activar" o "Cancelar". Distinto de [accesoTurnarioPro] (que puede seguir en `true` un
  /// tiempo después de cancelar, mientras no venza lo ya pagado, ver el comentario del endpoint
  /// `PATCH /:id/suscripcion/cancelar` en `negocios.ts`) — acá interesa el estado ADMINISTRATIVO
  /// de la suscripción (¿hay algo para cancelar?), no el acceso efectivo del momento.
  bool get esTurnarioProActivo => plan == 'turnario_pro' && estado == 'activa';

  factory _PlanNegocio.fromApi(Map<String, dynamic> json) {
    final turnos = json['turnos_confirmados_mes'] as Map<String, dynamic>;
    final profesionales = json['profesionales_activos'] as Map<String, dynamic>;
    final vencimientoRaw = json['vencimiento'] as String?;
    return _PlanNegocio(
      plan: json['plan'] as String,
      periodo: json['periodo'] as String?,
      vencimiento: vencimientoRaw != null ? DateTime.parse(vencimientoRaw).toLocal() : null,
      estado: json['estado'] as String,
      accesoTurnarioPro: json['acceso_turnario_pro'] as bool,
      turnosUsados: turnos['usados'] as int,
      turnosLimite: turnos['limite'] as int?,
      profesionalesUsados: profesionales['usados'] as int,
      profesionalesLimite: profesionales['limite'] as int?,
    );
  }
}
