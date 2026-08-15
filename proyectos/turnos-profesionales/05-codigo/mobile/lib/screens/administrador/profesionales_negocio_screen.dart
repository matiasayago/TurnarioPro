import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'turnario_pro_screen.dart';

/// Profesionales del Negocio (Panel Administrador, HU-02 — épica E15 "Modo Administrador v1",
/// `02-backlog/backlog.md`). Contrato:
/// - Alta `POST /negocios/:id/profesionales` (`requireAuth('administrador')`), body
///   `{ email, password, nombre }` -> 201 `{ id }` | 409 email ya registrado con un rol distinto
///   de `profesional` | 402 límite del plan gratis alcanzado (`requiere_turnario_pro: true` en el
///   body, ver `dominio/suscripciones.ts`, `cuerpoLimitePlanAlcanzado`) | 409 este profesional ya
///   pertenece a este negocio.
/// - Listado `GET /negocios/:id/profesionales` (nuevo de esta épica, `requireAuth('administrador')`)
///   -> array de `{ id, nombre, email, activo }` — `id` es `profesional.id`. `activo` es
///   `negocio_profesional.activo` (la membresía de ESTE profesional en ESTE negocio, no un estado
///   global de la identidad) — el mismo flag que ya usa el límite de "1 profesional activo" del
///   plan gratis (HU-29), se muestra con el mismo `StatusPill` genérico que el resto de la app usa
///   para un flag activo/inactivo (`StatusPill.activo`).
///
/// Sin baja/pausa ni acceso a historial/ficha: `negocios.ts` no expone ningún endpoint para dar de
/// baja/pausar un profesional todavía, y el acceso del administrador al historial de pacientes
/// queda explícitamente fuera de esta ronda (ver "Fuera de alcance" de esta épica en el backlog) —
/// el roster es de alta + solo lectura en esta pantalla, sin navegación por fila.
class ProfesionalesNegocioScreen extends StatefulWidget {
  const ProfesionalesNegocioScreen({super.key});

  @override
  State<ProfesionalesNegocioScreen> createState() => _ProfesionalesNegocioScreenState();
}

class _ProfesionalesNegocioScreenState extends State<ProfesionalesNegocioScreen> {
  late Future<List<_Profesional>> _futureProfesionales;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _futureProfesionales = sesion.negocioId == null
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargar();
  }

  Future<List<_Profesional>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/negocios/${sesion.negocioId}/profesionales');
    return raw.map((e) => _Profesional.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futureProfesionales = next);
    await next;
  }

  Future<void> _abrirAlta() async {
    final creado = await AppModalSheet.show<bool>(context, builder: (_) => const _AltaProfesionalSheet());
    if (creado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profesional agregado.')));
      await _refrescar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '👥',
        title: 'Profesionales del Negocio',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_Profesional>>(
          future: _futureProfesionales,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text('No se pudo cargar el roster: ${snapshot.error}', style: AppTypography.body(context)),
                  ),
                ],
              );
            }

            final profesionales = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                if (profesionales.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'Todavía no agregaste ningún profesional. Agregá el primero con el botón de abajo.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(context),
                      ),
                    ),
                  )
                else
                  for (final profesional in profesionales) ...[
                    _ProfesionalCard(profesional: profesional),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.base),
                PrimaryButton(
                  label: 'Agregar Profesional',
                  icon: Icons.add,
                  radiusVariant: AppButtonRadius.card,
                  onPressed: _abrirAlta,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Profesional {
  const _Profesional({required this.id, required this.nombre, required this.email, required this.activo});

  final String id;
  final String nombre;
  final String email;
  final bool activo;

  factory _Profesional.fromApi(Map<String, dynamic> json) => _Profesional(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        email: json['email'] as String,
        activo: json['activo'] as bool,
      );
}

class _ProfesionalCard extends StatelessWidget {
  const _ProfesionalCard({required this.profesional});

  final _Profesional profesional;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profesional.nombre,
                  style:
                      AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(profesional.email, style: AppTypography.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusPill.activo(profesional.activo),
        ],
      ),
    );
  }
}

/// Alta de profesional — modal de pantalla completa (`AppModalSheet`), mismo patrón que
/// `servicios_negocio_screen.dart`/`profesional/nueva_cita_screen.dart`. El 402 (límite del plan
/// gratis alcanzado) se distingue del resto de errores con un acceso directo a
/// `TurnarioProScreen` — mismo criterio de "flag explícito, no parsear texto" que ya usa
/// `login_screen.dart` para `requiere_confirmacion_password` (HU-35).
class _AltaProfesionalSheet extends StatefulWidget {
  const _AltaProfesionalSheet();

  @override
  State<_AltaProfesionalSheet> createState() => _AltaProfesionalSheetState();
}

class _AltaProfesionalSheetState extends State<_AltaProfesionalSheet> {
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;
  bool _requiereTurnarioPro = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (nombre.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _mensaje = 'Completá nombre, email y contraseña.';
        _mensajeEsError = true;
        _requiereTurnarioPro = false;
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = null;
      _requiereTurnarioPro = false;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/negocios/${sesion.negocioId}/profesionales', {
        'email': email,
        'password': password,
        'nombre': nombre,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = e.message;
        _mensajeEsError = true;
        _requiereTurnarioPro = e.statusCode == 402 && e.body?['requiere_turnario_pro'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo agregar el profesional: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: 'Agregar Profesional',
      primaryLabel: 'Guardar',
      primaryLoading: _enviando,
      onPrimary: _enviando ? null : _guardar,
      onSecondary: _enviando ? null : () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Text(
            'Se crea una cuenta nueva para este profesional (o se vincula una ya existente con el mismo '
            'email si ya trabaja en otro negocio) — va a poder iniciar sesión con este email y contraseña.',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: AppSpacing.base),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nombreCtrl,
                  enabled: !_enviando,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _emailCtrl,
                  enabled: !_enviando,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _passwordCtrl,
                  enabled: !_enviando,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña *'),
                ),
              ],
            ),
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.base),
            _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
          ],
          if (_requiereTurnarioPro) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlineButton(
              label: 'Ver Turnario Pro',
              radiusVariant: AppButtonRadius.card,
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TurnarioProScreen())),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required Widget child}) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: child,
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
