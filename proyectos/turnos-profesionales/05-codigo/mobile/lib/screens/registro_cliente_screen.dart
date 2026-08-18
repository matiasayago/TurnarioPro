import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../state/sesion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/widgets.dart';

/// HU-01 ("Como cliente o profesional, quiero registrarme e iniciar sesión, para poder acceder a
/// las funciones de la app según mi rol", `02-backlog/backlog.md` épica E4): alta de CLIENTE por
/// email/contraseña, pre-autenticación — vive junto a `login_screen.dart`/
/// `registro_negocio_screen.dart`, fuera de cualquier shell (accesible desde el link "Registrate"
/// de esa pantalla, antes de cualquier login). Hasta esta pantalla, un cliente nuevo solo podía
/// entrar con el botón "Iniciar sesión con Google" del login (HU-35) — no existía ningún
/// formulario de alta con email/contraseña para clientes, a diferencia de los negocios, que ya
/// tenían el suyo desde HU-00a.
///
/// Mismo patrón exacto que [RegistroNegocioScreen] (mismo tipo de alta pre-auth, mismo manejo de
/// errores incluido el 409, mismo `sesion.iniciarSesion(...)` + `Navigator.popUntil` al terminar),
/// bastante más simple: acá NO hay "datos del negocio" ni "cuenta de administrador" como 2
/// secciones separadas — es un único formulario de 3 campos (Nombre, Email, Contraseña) para la
/// cuenta del cliente.
///
/// Contrato: `POST /auth/registro-cliente` (`src/routes/auth.ts`, ya en producción), body
/// `{ email, password, nombre }` (los 3 requeridos) -> 201 `{ token }` | 400 falta algún campo
/// requerido (`'email, password y nombre son requeridos'`) o `password` no llega al mínimo
/// (`src/dominio/validacion.ts`, `passwordSchema`: 8 caracteres, `'La contraseña debe tener al
/// menos 8 caracteres'` — se valida también del lado del cliente con el mismo mensaje, en
/// [_registrar], mismo criterio que [RegistroNegocioScreen] para no depender solo del viaje de
/// red) | 409 el email ya está registrado (`'Email ya registrado'`).
///
/// Igual que `POST /auth/registro-negocio`, esta respuesta SIEMPRE trae `token` directo, nunca
/// `negocios` (un cliente no tiene negocio, RN9) — alcanza con `sesion.iniciarSesion` directo, sin
/// pasar por el selector de negocio de `login_screen.dart` (`elegirNegocio`/`_completarLogin`,
/// HU-27).
///
/// Al completar el alta con éxito, esta pantalla se `pop`ea de vuelta a la raíz de la navegación
/// en vez de navegar a ningún lado explícito — mismo mecanismo que [RegistroNegocioScreen] (ver su
/// doc-comment): el `_Router` de `main.dart` observa `Sesion` y, apenas detecta
/// `autenticado == true` con `rol == cliente`, renderiza `ClienteShell` en el lugar donde antes
/// mostraba `LoginScreen` — sin ese `pop`, esta pantalla (empujada con `Navigator.push` desde el
/// link de Login) seguiría tapando ese cambio aunque ya haya ocurrido debajo.
class RegistroClienteScreen extends StatefulWidget {
  const RegistroClienteScreen({super.key});

  @override
  State<RegistroClienteScreen> createState() => _RegistroClienteScreenState();
}

class _RegistroClienteScreenState extends State<RegistroClienteScreen> {
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final nombre = _nombreCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (nombre.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _mensaje = 'Completá tu nombre, el email y la contraseña.';
        _mensajeEsError = true;
      });
      return;
    }
    // Mismo mínimo y mismo mensaje que el backend (`passwordSchema`, `src/dominio/validacion.ts`)
    // — mismo criterio que `registro_negocio_screen.dart`: validar acá evita un viaje de red solo
    // para enterarse de algo que ya se puede saber en el cliente, sin dejar de confiar en el 400
    // del backend como resguardo final (ver doc-comment de la clase).
    if (password.length < 8) {
      setState(() {
        _mensaje = 'La contraseña debe tener al menos 8 caracteres';
        _mensajeEsError = true;
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final resp = await sesion.api.post('/auth/registro-cliente', {
        'nombre': nombre,
        'email': email,
        'password': password,
      });
      // Nunca trae `negocios` (ver doc-comment de la clase) — alcanza con iniciar sesión directo,
      // mismo patrón que ya usa `registro_negocio_screen.dart`.
      sesion.iniciarSesion(resp['token'] as String, email: email);
      if (!mounted) return;
      // Vuelve a la raíz de la navegación para que quede visible el `ClienteShell` que el
      // `_Router` de `main.dart` ya construyó debajo, apenas `Sesion` notificó el cambio de arriba
      // (ver doc-comment de la clase).
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        // 409: mensaje específico (no el genérico `e.message`) — mismo criterio que
        // `registro_negocio_screen.dart` para distinguir un error de "ya existe" de cualquier
        // otro (ver también `login_screen.dart`, `requiere_confirmacion_password`, HU-35).
        _mensaje = e.statusCode == 409
            ? 'Ya existe una cuenta registrada con ese email. Si es tuya, iniciá sesión en vez de registrarte de nuevo.'
            : e.message;
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo completar el registro: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '📝',
        title: 'Crear tu Cuenta',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creá tu cuenta de cliente — vas a poder empezar a buscar negocios y reservar '
              'turnos apenas termines este formulario.',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: AppSpacing.base),
            _sectionCard(
              context,
              title: 'Tus datos',
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
                    onSubmitted: (_) {
                      if (!_enviando) _registrar();
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Mínimo 8 caracteres.', style: AppTypography.caption(context)),
                ],
              ),
            ),
            if (_mensaje != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
            ],
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
      bottomNavigationBar: _footer(context),
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

  Widget _footer(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: PrimaryButton(
            label: 'Crear Cuenta',
            radiusVariant: AppButtonRadius.card,
            loading: _enviando,
            onPressed: _enviando ? null : _registrar,
          ),
        ),
      ),
    );
  }
}

/// Mismo patrón de banner de éxito/error que el resto de las pantallas de esta app (ej.
/// `registro_negocio_screen.dart`), duplicado localmente a propósito.
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
