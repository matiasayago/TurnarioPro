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
/// - Pausar/reactivar `PATCH /negocios/:id/profesionales/:profesionalId` (E15 fast-follow,
///   2026-08-17 — ver `_cambiarEstado`/`_ProfesionalCard` más abajo), body `{ activo: boolean }`
///   -> 200 `{ id, activo }` | 402 (solo reactivando) mismo límite/shape de error que el alta de
///   arriba (`requiere_turnario_pro: true`) | 404 este profesional no tiene membresía en este
///   negocio.
///
/// Sin acceso a historial/ficha desde ESTE roster: navegar al detalle clínico de un paciente sigue
/// sin ser parte de esta pantalla puntual — ese acceso ya existe, pero como pantalla separada
/// (`pacientes_negocio_screen.dart`, fast-follow de 2026-08-15), no como navegación por fila desde
/// acá. El roster SÍ deja de ser puramente de solo lectura con el fast-follow de pausar/reactivar
/// de arriba: cada fila tiene ahora una acción (Pausar/Reactivar) — pero la card en sí sigue sin
/// navegar a ningún lado al tocarla (a diferencia de, por ejemplo, `_PacienteNegocioCard`).
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

  /// Pausar/reactivar la membresía de [profesional] en este negocio — `PATCH
  /// /negocios/:id/profesionales/:profesionalId`, body `{ activo: nuevoActivo }`. Pausar pide
  /// confirmación primero (`_confirmarPausa`) por ser una acción con consecuencia real (el
  /// profesional deja de poder recibir turnos nuevos) — reactivar no la pide, mismo criterio ya
  /// aplicado en el resto de esta app para acciones reversibles sin impacto hacia terceros (ver
  /// p.ej. "Cerrar Sesión" en `profesional/configuracion_screen.dart`, que tampoco confirma).
  ///
  /// `context` es el de la card que disparó la acción (pasado por [_ProfesionalCard]/
  /// [_ProfesionalCardState], no `this.context` del State) — se usa `context.mounted` en vez del
  /// `mounted` del State para los guards post-`await`, porque es ESE contexto puntual (y no
  /// necesariamente toda la pantalla) el que hay que validar antes de mostrar el diálogo/SnackBar.
  ///
  /// El 402 (reactivar con el plan gratis ya en el límite de "1 profesional activo") se distingue
  /// con el mismo criterio que ya usa `_AltaProfesionalSheetState` más abajo: `requiere_turnario_pro`
  /// explícito en el body del error, nunca parseando el texto del mensaje.
  Future<void> _cambiarEstado(BuildContext context, _Profesional profesional, bool nuevoActivo) async {
    if (!nuevoActivo) {
      final confirmado = await _confirmarPausa(context, profesional.nombre);
      if (confirmado != true || !context.mounted) return;
    }

    final sesion = context.read<Sesion>();
    try {
      await sesion.api.patch('/negocios/${sesion.negocioId}/profesionales/${profesional.id}', {'activo': nuevoActivo});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nuevoActivo ? '${profesional.nombre} fue reactivado.' : '${profesional.nombre} fue pausado.'),
        ),
      );
      await _refrescar();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.statusCode == 402 && e.body?['requiere_turnario_pro'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Ver Turnario Pro',
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TurnarioProScreen())),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
    }
  }

  /// Diálogo nativo (`showDialog`+`AlertDialog`) — mismo patrón ya usado en esta app para
  /// confirmaciones puntuales (ver `login_screen.dart`, `_pedirPasswordParaVincular`); no hay un
  /// helper de confirmación reusable en `lib/widgets/` todavía, así que se sigue el mismo criterio
  /// de "cada pantalla arma el suyo" que el resto de este código. `null` (dismiss sin elegir botón,
  /// ej. tocar afuera o back) se trata igual que "Cancelar" por el caller (`!= true`).
  Future<bool?> _confirmarPausa(BuildContext context, String nombreProfesional) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pausar profesional'),
        content: Text(
          '$nombreProfesional va a dejar de poder recibir turnos nuevos hasta que lo reactivés. '
          'Los turnos que ya tiene agendados no se cancelan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Pausar')),
        ],
      ),
    );
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
                    _ProfesionalCard(
                      profesional: profesional,
                      onCambiarEstado: (context, nuevoActivo) => _cambiarEstado(context, profesional, nuevoActivo),
                    ),
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

/// A diferencia de la versión previa (`StatelessWidget` puramente informativa), esta card ahora
/// dispara una escritura (`onCambiarEstado`) — pasa a `StatefulWidget` únicamente para llevar
/// `_procesando` (deshabilita la acción y muestra un spinner chico mientras el PATCH está en
/// vuelo, mismo criterio que `PrimaryButton(loading: ...)` en el resto de la app). En el camino
/// feliz esta card se descarta igual apenas `_refrescar()` reemplaza la lista completa (el
/// `FutureBuilder` padre vuelve a "waiting"), así que `_procesando` solo llega a importar de
/// verdad en los caminos de error/cancelación, donde la card sigue viva y el botón tiene que
/// volver a quedar disponible.
class _ProfesionalCard extends StatefulWidget {
  const _ProfesionalCard({required this.profesional, required this.onCambiarEstado});

  final _Profesional profesional;

  /// `BuildContext` del propio callback: se le pasa el `context` de ESTA card (no uno externo) —
  /// ver el doc comment de `_ProfesionalesNegocioScreenState._cambiarEstado` para por qué importa.
  final Future<void> Function(BuildContext context, bool nuevoActivo) onCambiarEstado;

  @override
  State<_ProfesionalCard> createState() => _ProfesionalCardState();
}

class _ProfesionalCardState extends State<_ProfesionalCard> {
  bool _procesando = false;

  Future<void> _tocar(bool nuevoActivo) async {
    setState(() => _procesando = true);
    await widget.onCambiarEstado(context, nuevoActivo);
    // Si el PATCH tuvo éxito, `_refrescar()` (dentro de `onCambiarEstado`) ya reemplazó la lista
    // completa y esta card está desmontada a esta altura (`mounted == false`) — este `setState`
    // solo llega a ejecutarse de verdad en los caminos de error/cancelación de arriba.
    if (mounted) setState(() => _procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final profesional = widget.profesional;
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profesional.nombre,
                      style: AppTypography.subtitle(context)
                          .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
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
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: profesional.activo
                ? _AccionProfesional(
                    icon: Icons.pause_circle_outline,
                    label: 'Pausar',
                    color: colors.warning.base,
                    loading: _procesando,
                    onTap: () => _tocar(false),
                  )
                : _AccionProfesional(
                    icon: Icons.play_circle_outline,
                    label: 'Reactivar',
                    color: colors.success.base,
                    loading: _procesando,
                    onTap: () => _tocar(true),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Acción de fila — mismo patrón visual que `_AccionPaciente`
/// (`profesional/gestion_pacientes_screen.dart`: `TextButton.icon` chico, ícono + label en
/// `caption` bold), duplicado localmente a propósito, mismo criterio ya establecido en este código
/// de que cada pantalla define sus propios widgets de fila en vez de compartir uno genérico. A
/// diferencia de `_AccionPaciente` (siempre `primary`, 3 acciones de navegación sin distinción
/// semántica entre ellas), acá el color SÍ distingue el tipo de acción — `warning` para pausar
/// (reversible, pero con efecto real) vs. `success` para reactivar (constructiva) — mismo criterio
/// semántico que ya usan `WarningButton`/`SuccessButton` (`widgets/buttons.dart`). Sin `Expanded`
/// (a diferencia de `_AccionPaciente`): acá hay una única acción por card, no 2-3 compartiendo el
/// ancho de una fila.
class _AccionProfesional extends StatelessWidget {
  const _AccionProfesional({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
          : Icon(icon, size: 18, color: color),
      label: Text(label, style: AppTypography.caption(context).copyWith(color: color, fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
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
