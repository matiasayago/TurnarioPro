import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import '../profesional/configuracion_consultorio_screen.dart';
import '../profesional/editar_perfil_screen.dart';
import '../profesional/privacidad_screen.dart';
import 'pacientes_negocio_screen.dart';
import 'profesionales_negocio_screen.dart';
import 'servicios_negocio_screen.dart';
import 'turnario_pro_screen.dart';

/// Shell/Dashboard de Administrador — HU-36 (épica E15 "Modo Administrador v1",
/// `02-backlog/backlog.md`). Punto de entrada del rol `Rol.administrador` en `main.dart`
/// (`_Router`): antes caía directo a `LoginScreen()`, igual que un usuario no autenticado.
///
/// A diferencia de `ProfesionalShell`/`ClienteShell` (bottom nav + `IndexedStack` de varias
/// pestañas), esta pantalla es un único hub — mismo criterio de "shell simple" que ya pidió esta
/// ronda ("el dashboard en sí puede ser simple: accesos a las otras 4 pantallas + un resumen
/// básico del plan"): un resumen liviano del plan del negocio (`GET /negocios/:id/plan`, mismo
/// shape que consume `turnario_pro_screen.dart`) + accesos a las otras 4 pantallas de esta épica
/// (Datos del Negocio, Servicios, Profesionales, Turnario Pro) más los 2 accesos "bonus"
/// rol-agnósticos (Mi Perfil/Privacidad, HU-32, reuso literal de las pantallas ya construidas del
/// lado Profesional — cero backend nuevo). Mismos widgets del sistema de diseño que el resto de
/// la app (`AppHeader`, `StatCard`, `AppColors`/`AppTypography`/`AppSpacing`/`AppRadius`), sin
/// inventar un lenguaje visual nuevo.
///
/// **Fast-follow (2026-08-15):** se sumó un 5to ítem a "Mi negocio", `PacientesNegocioScreen`
/// (acceso de SOLO LECTURA al historial de pacientes del negocio, `02-backlog/backlog.md` —
/// "Fast-follow — acceso de administrador al historial de pacientes") — no formaba parte del
/// alcance original de HU-36 (ver "Pregunta 2" en esa misma sección del backlog, secuenciada
/// aparte por no tener backend todavía en la v1).
///
/// No hay selector "actuar como Profesional/Administrador": el modelo de datos no permite que una
/// misma cuenta tenga los dos roles a la vez (`usuario.rol` es un único valor — E15, sección
/// "Preguntas abiertas", pregunta 1, ya resuelta) — cada cuenta entra a exactamente un shell.
///
/// Multi-negocio (HU-27): mismo mecanismo ya construido para el lado Profesional —
/// `Sesion.negocios`/`Sesion.entrarANegocio`/`widgets/selector_negocio.dart` (`elegirNegocio`) —,
/// sin selector nuevo (ver [_cambiarNegocio], calcado de `profesional/dashboard_screen.dart`).
/// `main.dart` le da a esta pantalla `key: ValueKey(sesion.negocioId)` (igual que
/// `ProfesionalShell`), así que cambiar de negocio recrea este shell desde cero.
class AdministradorShell extends StatefulWidget {
  const AdministradorShell({super.key});

  @override
  State<AdministradorShell> createState() => _AdministradorShellState();
}

class _AdministradorShellState extends State<AdministradorShell> {
  /// `null` cuando la sesión no tiene negocio activo (ver [_SinNegocioBanner]) — a diferencia de
  /// otras pantallas de esta app, acá NO se usa `Future.error(...)` para ese caso: esta Future se
  /// consulta condicionalmente (solo cuando hay negocio, ver [build]), así que un `Future.error`
  /// nunca escuchado quedaría como una excepción no manejada.
  Future<_PlanResumen>? _futurePlan;

  /// Mismo criterio que `profesional/dashboard_screen.dart` (`_cambiandoNegocio`): deshabilita el
  /// ícono de "cambiar de vista" mientras `POST /auth/entrar-a-negocio` está en curso.
  bool _cambiandoNegocio = false;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    if (sesion.negocioId != null) _futurePlan = _cargarPlan();
  }

  Future<_PlanResumen> _cargarPlan() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api.getMap('/negocios/${sesion.negocioId}/plan');
    return _PlanResumen.fromApi(data);
  }

  Future<void> _refrescar() async {
    final sesion = context.read<Sesion>();
    if (sesion.negocioId == null) return;
    final next = _cargarPlan();
    setState(() => _futurePlan = next);
    await next;
  }

  /// HU-27 — idéntico patrón que `dashboard_screen.dart` (`_cambiarNegocio`, Profesional): abre
  /// el selector compartido, reemite la sesión contra el negocio elegido y refresca. `main.dart`
  /// recrea todo este subárbol al cambiar `Sesion.negocioId` (`key: ValueKey`), así que el
  /// `mounted`/`setState` de acá solo defienden la ventana en la que esa recreación todavía no
  /// ocurrió cuando este método sigue corriendo.
  Future<void> _cambiarNegocio() async {
    final sesion = context.read<Sesion>();
    final elegido = await elegirNegocio(context, sesion.negocios, actualNegocioId: sesion.negocioId);
    if (!mounted || elegido == null || elegido.negocioId == sesion.negocioId) return;

    setState(() => _cambiandoNegocio = true);
    try {
      await sesion.entrarANegocio(elegido.negocioId);
      if (!mounted) return;
      await _refrescar();
    } catch (e) {
      if (mounted) _mostrarAviso('No se pudo cambiar de negocio: $e');
    } finally {
      if (mounted) setState(() => _cambiandoNegocio = false);
    }
  }

  void _mostrarAviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  void _irA(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();

    return Scaffold(
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        title: 'Panel de Administrador',
        subtitle: sesion.email,
        actions: [
          // HU-27: solo tiene sentido con 2+ negocios entre los que elegir — mismo criterio que
          // `dashboard_screen.dart` (Profesional).
          if (sesion.tieneMultiplesNegocios)
            IconButton(
              icon: _cambiandoNegocio
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.swap_horiz),
              tooltip: 'Cambiar de vista',
              onPressed: _cambiandoNegocio ? null : _cambiarNegocio,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.base),
          children: [
            if (sesion.negocioId == null)
              const _SinNegocioBanner()
            else ...[
              _resumenPlan(context, _futurePlan!),
              const SizedBox(height: AppSpacing.xl),
              _MenuSection(
                title: 'Mi negocio',
                children: [
                  _MenuTile(
                    icon: Icons.storefront_outlined,
                    label: 'Datos del Negocio',
                    onTap: () => _irA(const ConfiguracionConsultorioScreen()),
                  ),
                  _MenuTile(
                    icon: Icons.design_services_outlined,
                    label: 'Servicios',
                    onTap: () => _irA(const ServiciosNegocioScreen()),
                  ),
                  _MenuTile(
                    icon: Icons.people_outline,
                    label: 'Profesionales',
                    onTap: () => _irA(const ProfesionalesNegocioScreen()),
                  ),
                  _MenuTile(
                    icon: Icons.folder_shared_outlined,
                    label: 'Pacientes',
                    onTap: () => _irA(const PacientesNegocioScreen()),
                  ),
                  _MenuTile(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Turnario Pro · Suscripción',
                    onTap: () => _irA(const TurnarioProScreen()),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _MenuSection(
              title: 'Cuenta',
              children: [
                _MenuTile(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: () => _irA(const EditarPerfilScreen()),
                ),
                _MenuTile(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacidad y Seguridad',
                  onTap: () => _irA(const PrivacidadScreen()),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            DestructiveButton(
              label: 'Cerrar Sesión',
              radiusVariant: AppButtonRadius.card,
              onPressed: () => context.read<Sesion>().cerrarSesion(),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _resumenPlan(BuildContext context, Future<_PlanResumen> future) {
    final colors = AppColors.of(context);
    return FutureBuilder<_PlanResumen>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
            child: Text('No se pudo cargar tu plan: ${snapshot.error}', style: AppTypography.body(context)),
          );
        }
        final plan = snapshot.data!;
        final tituloPlan = plan.accesoTurnarioPro ? 'Turnario Pro' : 'Plan Gratis';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mi plan: $tituloPlan', style: AppTypography.sectionTitle(context)),
                TextButton(
                  onPressed: () => _irA(const TurnarioProScreen()),
                  child: Text(
                    'Ver más >',
                    style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            StatCardGrid(cards: [
              StatCard(
                value: plan.turnosLimite != null ? '${plan.turnosUsados}/${plan.turnosLimite}' : '${plan.turnosUsados}',
                label: 'Turnos confirmados (mes)',
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
          ],
        );
      },
    );
  }
}

/// Datos de `GET /negocios/:id/plan` que necesita el resumen de este dashboard — subconjunto
/// liviano del shape completo (ver `turnario_pro_screen.dart` para el modelo completo que sí
/// necesita `plan`/`periodo`/`vencimiento`/`estado`, que acá no se muestran).
class _PlanResumen {
  const _PlanResumen({
    required this.accesoTurnarioPro,
    required this.turnosUsados,
    required this.turnosLimite,
    required this.profesionalesUsados,
    required this.profesionalesLimite,
  });

  final bool accesoTurnarioPro;
  final int turnosUsados;
  final int? turnosLimite;
  final int profesionalesUsados;
  final int? profesionalesLimite;

  factory _PlanResumen.fromApi(Map<String, dynamic> json) {
    final turnos = json['turnos_confirmados_mes'] as Map<String, dynamic>;
    final profesionales = json['profesionales_activos'] as Map<String, dynamic>;
    return _PlanResumen(
      accesoTurnarioPro: json['acceso_turnario_pro'] as bool,
      turnosUsados: turnos['usados'] as int,
      turnosLimite: turnos['limite'] as int?,
      profesionalesUsados: profesionales['usados'] as int,
      profesionalesLimite: profesionales['limite'] as int?,
    );
  }
}

/// Cuenta de administrador sin ningún negocio activo todavía (`negocio_administrador` sin fila) —
/// caso borde, análogo a `_SinNegocioView` de `profesional/dashboard_screen.dart`, pero acá NO se
/// reemplaza toda la pantalla: la sección "Cuenta" (Mi Perfil/Privacidad/Cerrar Sesión) sigue
/// siendo útil sin negocio, así que solo se oculta "Mi negocio" (los 4 accesos de esta épica
/// requieren todos un `negocio_id`) y se avisa acá.
class _SinNegocioBanner extends StatelessWidget {
  const _SinNegocioBanner();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(color: colors.neutral.background, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.storefront_outlined, size: 18, color: colors.neutral.base),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Todavía no estás vinculado a ningún negocio.',
              style: AppTypography.caption(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card `surface` con título + filas tappeables, separadas por un `Divider` fino — mismo
/// tratamiento visual (y mismo criterio de duplicación local en vez de un widget compartido) que
/// `_MenuSection`/`_MenuTile` de `profesional/configuracion_screen.dart`.
class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(title, style: AppTypography.sectionTitle(context)),
          ),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) Divider(height: 1, color: colors.border),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.base),
            Expanded(child: Text(label, style: AppTypography.body(context))),
            Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
