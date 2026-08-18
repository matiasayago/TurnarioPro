import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../state/theme_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import '../profesional/configuracion_notificaciones_screen.dart';
import '../profesional/editar_perfil_screen.dart';
import '../profesional/privacidad_screen.dart';
import 'acerca_de_cliente_screen.dart';
import 'ayuda_soporte_cliente_screen.dart';

/// Configuración (menú principal, Cliente) — conecta el ítem "Configuración" del bottom nav de
/// `ClienteShell` (antes apuntaba a `ProximamenteScreen`, ver el doc-comment de esa clase). Mismo
/// patrón visual exacto que `ConfiguracionScreen` (Profesional,
/// `screens/profesional/configuracion_screen.dart`) — `_PerfilHeader`/`_MenuSection`/`_MenuTile`/
/// `_SelectorTema` se REPLICAN acá en vez de compartirse desde `widgets/`, mismo criterio que ya
/// usa el resto de esta app para las secciones de menú de Configuración (`_MenuSection`/
/// `_MenuTile` también están duplicados tal cual en `administrador/administrador_shell.dart`; cada
/// pantalla de este estilo define sus propios widgets privados en vez de compartir uno común).
///
/// Diferencias contra la versión Profesional (`ConfiguracionScreen`), todas intencionales:
/// - Sin los 2 callbacks `onIrAHorarios`/`onIrAPacientes`: `ClienteShell` no tiene pestañas de
///   Horarios ni Pacientes a las que saltar (4 tabs: Buscar/Mis Turnos/Notificaciones/
///   Configuración).
/// - Sin la sección "Panel Profesional" (Gestionar Horarios, Gestionar Pacientes, Nueva Cita,
///   Reportes y Estadísticas, Configuración de Consultorio, Autorizaciones Médicas) ni "Pagos y
///   Señas": ningún cliente gestiona un negocio propio.
/// - Sin "Turnario Pro · Suscripción" (sección "Cuenta"), a diferencia de "Idioma" (que sí se
///   mantiene como `ProximamenteScreen`: es un ajuste genérico de la app que algún día va a
///   aplicar a cualquier rol). Turnario Pro es, estructuralmente, la suscripción de UN NEGOCIO
///   (`GET/POST /negocios/:id/plan|suscripcion`, `requireAuth('administrador', 'profesional')` —
///   ver `administrador/turnario_pro_screen.dart` — y, del lado Administrador, un ítem propio de
///   la sección "Mi negocio", no de "Cuenta", ver `administrador_shell.dart`), atada a
///   `negocio_id`. Una sesión Cliente nunca tiene `negocio_id` (`Sesion.negocioId` solo se resuelve
///   para profesional/administrador, ver `state/sesion.dart`): no hay ningún negocio propio al que
///   suscribir. Mostrar el ítem igual, aunque sea como "Próximamente", prometería una función que
///   esta cuenta nunca va a poder usar — se saca el ítem entero en vez de dejarlo apuntando a
///   `ProximamenteScreen`.
/// - Header (`_PerfilHeader`) con "Cliente" fijo en vez de "Profesional", SIN la carga de rubro de
///   negocio (`GET /negocios` + buscar el propio `negocioId` en la lista de la respuesta): un
///   cliente no tiene negocio asociado, ese dato no existiría para mostrar.
/// - "Ayuda y Soporte" y "Acerca de" apuntan a versiones propias
///   (`ayuda_soporte_cliente_screen.dart`/`acerca_de_cliente_screen.dart`), NO a las de
///   `profesional/`: a diferencia de Editar Perfil/Notificaciones/Privacidad y Seguridad (100%
///   genéricas, reusadas tal cual — confirmado contra el propio contrato de backend:
///   `usuario.ts` documenta ambos endpoints, `/usuario/perfil` y `/usuario/privacidad`, como
///   "transversal a cualquier rol autenticado (cliente/profesional/administrador)"), esas 2
///   pantallas estáticas SÍ tenían contenido específico de Profesional adentro (ver el doc-comment
///   de cada una) — se crean copias con el mismo armado visual y contenido ajustado a Cliente, en
///   vez de reusarlas tal cual con contenido incorrecto para este rol.
class ConfiguracionClienteScreen extends StatelessWidget {
  const ConfiguracionClienteScreen({super.key});

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
                      icon: Icons.person_outline,
                      label: 'Editar Perfil',
                      onTap: () => _irA(context, const EditarPerfilScreen()),
                    ),
                    _MenuTile(
                      icon: Icons.notifications_outlined,
                      label: 'Notificaciones',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConfiguracionNotificacionesScreen()),
                      ),
                    ),
                    _MenuTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacidad y Seguridad',
                      onTap: () => _irA(context, const PrivacidadScreen()),
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
                      onTap: () => _irA(context, const AyudaSoporteClienteScreen()),
                    ),
                    _MenuTile(
                      icon: Icons.info_outline,
                      label: 'Acerca de',
                      onTap: () => _irA(context, const AcercaDeClienteScreen()),
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

  /// Empuja una pantalla real (con backend o estática) — mismo `Navigator.push` que
  /// [_irAProximamente], sin el envoltorio de `ProximamenteScreen`.
  void _irA(BuildContext context, Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }
}

/// Header con perfil (avatar, identidad, rol) — mismo armado visual que `_PerfilHeader` de
/// `ConfiguracionScreen` (Profesional), SIN el `FutureBuilder` de rubro de negocio (un cliente no
/// tiene negocio asociado, ver el doc-comment de la clase de arriba) y con el label "Cliente" fijo
/// en vez de "Profesional" — por eso alcanza con `StatelessWidget` acá (no hace falta el
/// `StatefulWidget`/`initState` que sí necesita la versión Profesional para disparar la carga del
/// rubro).
class _PerfilHeader extends StatelessWidget {
  const _PerfilHeader();

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
                  // Mismo motivo que `_PerfilHeader` de la versión Profesional: no hay claim
                  // `nombre` en el JWT (`auth.ts` solo firma sub/rol/negocio_id/profesional_id) —
                  // se muestra el email, el mismo valor que el usuario tipeó para loguearse o
                  // registrarse.
                  Text(
                    sesion.email ?? 'Cliente',
                    style:
                        AppTypography.subtitle(context).copyWith(color: colors.onPrimary, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cliente',
                    style: AppTypography.caption(context).copyWith(color: colors.onPrimary.withValues(alpha: 0.85)),
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
/// que `_MenuSection` de `ConfiguracionScreen` (Profesional).
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
/// directo a `ThemeController` — idéntico a `_SelectorTema` de `ConfiguracionScreen` (Profesional),
/// aplica al instante para toda la app (`ThemeController` es un único `ChangeNotifier` global, sin
/// distinción de rol).
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
