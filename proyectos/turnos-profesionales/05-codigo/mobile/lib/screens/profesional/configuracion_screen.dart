import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../state/theme_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Configuración (menú principal, Profesional) — reemplaza el ítem "Configuración" del bottom
/// nav (antes apuntaba directo a `ProximamenteScreen`, ver `profesional_shell.dart`). Estructura
/// confirmada contra capturas reales en `mapa-pantallas.md` §5.11bis.
///
/// "Configurar Disponibilidad"/"Gestionar Horarios" y "Gestionar Pacientes" NO empujan una nueva
/// ruta: cambian de pestaña dentro del mismo `IndexedStack` de `ProfesionalShell` (vía los
/// callbacks [onIrAHorarios]/[onIrAPacientes]) porque son, literalmente, "el mismo destino" que
/// ya existe como pestaña propia (brief de esta ronda) — empujar una segunda instancia con
/// `Navigator.push` duplicaría la pantalla en la pila de navegación en vez de reusarla.
///
/// Único apartado con lógica real más allá de esas dos: el selector de Tema, conectado a
/// `ThemeController` (la infraestructura ya existía, ver `state/theme_controller.dart`) y
/// "Cerrar Sesión" (real, mismo `Sesion.cerrarSesion()` que usa el resto de la app). Todo lo
/// demás no tiene backend todavía y va a `ProximamenteScreen`.
class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key, required this.onIrAHorarios, required this.onIrAPacientes});

  final VoidCallback onIrAHorarios;
  final VoidCallback onIrAPacientes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _PerfilHeader(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MenuSection(
                  title: 'Cuenta',
                  children: [
                    _MenuTile(
                      icon: Icons.event_available_outlined,
                      label: 'Configurar Disponibilidad',
                      onTap: onIrAHorarios,
                    ),
                    _MenuTile(
                      icon: Icons.person_outline,
                      label: 'Editar Perfil',
                      onTap: () => _irAProximamente(context, 'Editar Perfil'),
                    ),
                    _MenuTile(
                      icon: Icons.notifications_outlined,
                      label: 'Notificaciones',
                      onTap: () => _irAProximamente(context, 'Notificaciones'),
                    ),
                    _MenuTile(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Turnario Pro · Suscripción',
                      onTap: () => _irAProximamente(context, 'Turnario Pro · Suscripción'),
                    ),
                    _MenuTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacidad y Seguridad',
                      onTap: () => _irAProximamente(context, 'Privacidad y Seguridad'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _MenuSection(
                  title: 'Aplicación',
                  children: [
                    const _SelectorTema(),
                    _MenuTile(
                      icon: Icons.language_outlined,
                      label: 'Idioma',
                      onTap: () => _irAProximamente(context, 'Idioma'),
                    ),
                    _MenuTile(
                      icon: Icons.help_outline,
                      label: 'Ayuda y Soporte',
                      onTap: () => _irAProximamente(context, 'Ayuda y Soporte'),
                    ),
                    _MenuTile(
                      icon: Icons.info_outline,
                      label: 'Acerca de',
                      onTap: () => _irAProximamente(context, 'Acerca de'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _MenuSection(
                  title: 'Panel Profesional',
                  children: [
                    _MenuTile(icon: Icons.schedule_outlined, label: 'Gestionar Horarios', onTap: onIrAHorarios),
                    _MenuTile(icon: Icons.people_outline, label: 'Gestionar Pacientes', onTap: onIrAPacientes),
                    _MenuTile(
                      icon: Icons.event_note_outlined,
                      label: 'Nueva Cita',
                      onTap: () => _irAProximamente(context, 'Nueva Cita'),
                    ),
                    _MenuTile(
                      icon: Icons.insert_chart_outlined,
                      label: 'Reportes y Estadísticas',
                      onTap: () => _irAProximamente(context, 'Reportes y Estadísticas'),
                    ),
                    _MenuTile(
                      icon: Icons.payments_outlined,
                      label: 'Configuración de Pagos',
                      onTap: () => _irAProximamente(context, 'Configuración de Pagos'),
                    ),
                    _MenuTile(
                      icon: Icons.storefront_outlined,
                      label: 'Configuración de Consultorio',
                      onTap: () => _irAProximamente(context, 'Configuración de Consultorio'),
                    ),
                    _MenuTile(
                      icon: Icons.medical_information_outlined,
                      label: 'Autorizaciones Médicas',
                      onTap: () => _irAProximamente(context, 'Autorizaciones Médicas'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _MenuSection(
                  title: 'Pagos y Señas',
                  children: [
                    _MenuTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Pagos y Señas',
                      onTap: () => _irAProximamente(context, 'Pagos y Señas'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                DestructiveButton(
                  label: 'Cerrar Sesión',
                  radiusVariant: AppButtonRadius.card,
                  onPressed: () => context.read<Sesion>().cerrarSesion(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(child: Text('Turnario v1.0.0', style: AppTypography.caption(context))),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _irAProximamente(BuildContext context, String titulo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProximamenteScreen(titulo: titulo, showBackButton: true)),
    );
  }
}

/// §5.11bis: header con perfil (avatar, identidad, rol, rubro) en vez de un título simple.
class _PerfilHeader extends StatefulWidget {
  const _PerfilHeader();

  @override
  State<_PerfilHeader> createState() => _PerfilHeaderState();
}

class _PerfilHeaderState extends State<_PerfilHeader> {
  late Future<String?> _futureRubro;

  @override
  void initState() {
    super.initState();
    _futureRubro = _cargarRubro();
  }

  // El rubro del negocio es un dato accesorio de este header — si `GET /negocios` falla, se
  // muestra el resto del header igual, solo sin esa línea (no se rompe toda la pantalla de
  // Configuración por un dato secundario).
  Future<String?> _cargarRubro() async {
    final sesion = context.read<Sesion>();
    try {
      final negocios = await sesion.api.getList('/negocios');
      for (final n in negocios) {
        final negocio = n as Map<String, dynamic>;
        if (negocio['id'] == sesion.negocioId) return negocio['rubro'] as String?;
      }
    } catch (_) {
      // swallow — ver comentario de arriba.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sesion = context.watch<Sesion>();
    return Container(
      width: double.infinity,
      color: colors.primary,
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.xxl, AppSpacing.base, AppSpacing.xl),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colors.onPrimary.withValues(alpha: 0.2),
              child: Icon(Icons.person, color: colors.onPrimary, size: 30),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // No hay claim `nombre` en el JWT (mismo motivo ya documentado en
                  // `dashboard_screen.dart`: `auth.ts` solo firma sub/rol/negocio_id/
                  // profesional_id) — se muestra el email como identificador principal, que sí es
                  // preciso: es el mismo valor que el usuario tipeó para loguearse
                  // (`login_screen.dart` → `Sesion.iniciarSesion(..., email: ...)`), no un dato
                  // inventado.
                  Text(
                    sesion.email ?? 'Profesional',
                    style:
                        AppTypography.subtitle(context).copyWith(color: colors.onPrimary, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Profesional',
                    style: AppTypography.caption(context).copyWith(color: colors.onPrimary.withValues(alpha: 0.85)),
                  ),
                  FutureBuilder<String?>(
                    future: _futureRubro,
                    builder: (context, snapshot) {
                      final rubro = snapshot.data;
                      if (rubro == null || rubro.isEmpty) return const SizedBox.shrink();
                      return Text(
                        rubro,
                        style: AppTypography.caption(context).copyWith(color: colors.onPrimary.withValues(alpha: 0.85)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card `surface` con título + filas, separadas por un `Divider` fino — mismo tratamiento visual
/// que el resto de cards de esta app (`AppRadius.card` + `AppRadius.cardShadow`).
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

/// Único control con lógica real de la sección "Aplicación": Claro/Oscuro/Sistema, conectado
/// directo a `ThemeController` — aplica al instante, sin pantalla intermedia.
class _SelectorTema extends StatelessWidget {
  const _SelectorTema();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final modo = context.watch<ThemeController>().mode;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined, size: 22, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.base),
              Text('Tema', style: AppTypography.body(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_outlined)),
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Sistema'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
            ],
            selected: {modo},
            onSelectionChanged: (seleccion) => context.read<ThemeController>().setThemeMode(seleccion.first),
          ),
        ],
      ),
    );
  }
}
