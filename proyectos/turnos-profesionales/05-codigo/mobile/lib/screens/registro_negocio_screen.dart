import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../state/sesion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/widgets.dart';

/// HU-00a ("Como administrador, quiero registrar mi negocio... para empezar a operar de forma
/// aislada de otros negocios", `02-backlog/backlog.md` épica E0): alta de negocio + administrador,
/// pre-autenticación — vive junto a `login_screen.dart`, fuera de cualquier shell (accesible desde
/// el link "Registralo" de esa pantalla, antes de cualquier login). El registro de CLIENTE (HU-01)
/// es una pantalla propia distinta, NO cubierta acá — ver el doc-comment de [LoginScreen].
///
/// Contrato: `POST /auth/registro-negocio` (`src/routes/auth.ts`, ya en producción), body
/// `{ nombre_negocio, rubro?, ubicacion?, email, password, nombre_admin }` (`rubro`/`ubicacion`
/// opcionales, el resto requeridos) -> 201 `{ token, negocio_id }` | 400 falta algún campo
/// requerido (`'nombre_negocio, email, password y nombre_admin son requeridos'`) o `password` no
/// llega al mínimo (`src/dominio/validacion.ts`, `passwordSchema`: 8 caracteres,
/// `'La contraseña debe tener al menos 8 caracteres'` — se valida también del lado del cliente con
/// el mismo mensaje, en [_registrar], para no depender solo del viaje de red) | 409 el email ya
/// está registrado (`'Email ya registrado'`).
///
/// A diferencia de `POST /auth/login`/`POST /auth/google`, esta respuesta SIEMPRE trae `token`
/// directo, nunca `negocios`: un negocio recién creado es, por definición, el único del
/// administrador nuevo (`auth.ts` firma el token ya con ese `negocio_id`) — no hace falta pasar
/// por el selector de negocio de `login_screen.dart` (`elegirNegocio`/`_completarLogin`, HU-27),
/// alcanza con `sesion.iniciarSesion` directo, mismo patrón que ya usa esa pantalla para el login
/// con Google (`_iniciarConGoogle`).
///
/// Al completar el alta con éxito, esta pantalla se `pop`ea de vuelta a la raíz de la navegación
/// en vez de navegar a ningún lado explícito: el `_Router` de `main.dart` observa `Sesion` y, apenas
/// detecta `autenticado == true` con `rol == administrador`, renderiza `AdministradorShell` en el
/// lugar donde antes mostraba `LoginScreen` — sin ese `pop`, esta pantalla (empujada con
/// `Navigator.push` desde el link de Login) seguiría tapando ese cambio en la pantalla aunque ya
/// haya ocurrido debajo.
class RegistroNegocioScreen extends StatefulWidget {
  const RegistroNegocioScreen({super.key});

  @override
  State<RegistroNegocioScreen> createState() => _RegistroNegocioScreenState();
}

class _RegistroNegocioScreenState extends State<RegistroNegocioScreen> {
  final _nombreNegocioCtrl = TextEditingController();
  final _ubicacionCtrl = TextEditingController();
  final _nombreAdminCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // A diferencia del resto de los campos de esta pantalla, "Rubro" ya no es un `TextField` de
  // texto libre (ver [CampoRubro], `widgets/campo_rubro.dart`) — el valor final a mandar al
  // backend lo entrega directo su `onChanged`, con el mismo criterio "vacío es null" que
  // [_vacioANull] aplica al resto de los campos opcionales de acá.
  String? _rubro;

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _nombreNegocioCtrl.dispose();
    _ubicacionCtrl.dispose();
    _nombreAdminCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _vacioANull(String texto) => texto.trim().isEmpty ? null : texto.trim();

  Future<void> _registrar() async {
    final nombreNegocio = _nombreNegocioCtrl.text.trim();
    final nombreAdmin = _nombreAdminCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (nombreNegocio.isEmpty || nombreAdmin.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _mensaje = 'Completá el nombre del negocio, tu nombre, el email y la contraseña.';
        _mensajeEsError = true;
      });
      return;
    }
    // Mismo mínimo y mismo mensaje que el backend (`passwordSchema`,
    // `src/dominio/validacion.ts`) — validar acá evita un viaje de red solo para enterarse de
    // algo que ya se puede saber en el cliente, sin dejar de confiar en el 400 del backend como
    // resguardo final (ver doc-comment de la clase).
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
      final resp = await sesion.api.post('/auth/registro-negocio', {
        'nombre_negocio': nombreNegocio,
        'rubro': _rubro,
        'ubicacion': _vacioANull(_ubicacionCtrl.text),
        'email': email,
        'password': password,
        'nombre_admin': nombreAdmin,
      });
      // Nunca trae `negocios` (ver doc-comment de la clase) — alcanza con iniciar sesión directo,
      // mismo patrón que ya usa `login_screen.dart` para el login con Google.
      sesion.iniciarSesion(resp['token'] as String, email: email);
      if (!mounted) return;
      // Vuelve a la raíz de la navegación para que quede visible el `AdministradorShell` que el
      // `_Router` de `main.dart` ya construyó debajo, apenas `Sesion` notificó el cambio de
      // arriba (ver doc-comment de la clase).
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        // 409: mensaje específico (no el genérico `e.message`) — mismo criterio que el resto de
        // la app para distinguir un error de "ya existe" de cualquier otro (ver
        // `login_screen.dart`, `requiere_confirmacion_password`, HU-35).
        _mensaje = e.statusCode == 409
            ? 'Ya existe una cuenta registrada con ese email. Si es tuya, iniciá sesión en vez de registrarte de nuevo.'
            : e.message;
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo registrar el negocio: $e';
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
        title: 'Registrar tu Negocio',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Creá tu negocio y quedá registrado como su administrador — vas a poder empezar a '
              'usar la app apenas termines este formulario.',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: AppSpacing.base),
            _sectionCard(
              context,
              title: 'Datos del negocio',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nombreNegocioCtrl,
                    enabled: !_enviando,
                    decoration: const InputDecoration(labelText: 'Nombre del negocio *'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CampoRubro(
                    valorInicial: _rubro,
                    enabled: !_enviando,
                    onChanged: (valor) => _rubro = valor,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _ubicacionCtrl,
                    enabled: !_enviando,
                    decoration: const InputDecoration(labelText: 'Ubicación'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _sectionCard(
              context,
              title: 'Tu cuenta de administrador',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nombreAdminCtrl,
                    enabled: !_enviando,
                    decoration: const InputDecoration(labelText: 'Tu nombre *'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Tu nombre como persona a cargo del negocio, no el nombre del negocio de arriba.',
                    style: AppTypography.caption(context),
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
            label: 'Registrar Negocio',
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
