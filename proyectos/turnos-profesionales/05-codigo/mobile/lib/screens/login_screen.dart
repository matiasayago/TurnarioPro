import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_client.dart';
import '../state/sesion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/selector_negocio.dart';
import 'recuperar_password_screen.dart';
import 'registro_selector_screen.dart';

/// HU-01: login de cliente o profesional, con un único link al pie ("¿Todavía no tenés cuenta?
/// Registrate", ver [build]) a `RegistroSelectorScreen` — paso intermedio donde el usuario elige
/// entre el registro de negocio/administrador (HU-00a, `registro_negocio_screen.dart`) y el
/// registro de cliente (HU-01, `registro_cliente_screen.dart`; hasta esa historia, un cliente
/// nuevo solo podía entrar con el botón "Iniciar sesión con Google" de más abajo, sin ningún
/// formulario de alta con email/contraseña propio). Antes de esta ronda había 2 links separados
/// acá mismo, uno por formulario — unificados en 1 solo para simplificar esta pantalla.
///
/// HU-35 (`02-backlog/backlog.md`): además del login por contraseña de abajo, esta pantalla
/// ofrece "Iniciar sesión con Google" (wireframe en `04-diseno/mapa-pantallas.md` §5.17) — ver
/// [_iniciarConGoogle] y [_pedirPasswordParaVincular] para el flujo completo contra
/// `POST /auth/google` / `POST /auth/login` (contrato real en `src/routes/auth.ts`).
///
/// HU-37 (`02-backlog/backlog.md`, extiende HU-01/HU-35): link "¿Olvidaste tu contraseña?" entre
/// el botón "Ingresar" y el botón de Google (ver [build]) — empuja `RecuperarPasswordScreen`,
/// paso 1 de 2 del flujo de recuperación; el paso 2 (`CanjearTokenPasswordScreen`) se alcanza
/// desde ahí, nunca directo desde este login. Pantalla pre-autenticación, fuera de cualquier
/// shell, empujada con `Navigator.push` (no reemplaza este login).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _cargando = false;
  bool _googleCargando = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final email = _emailCtrl.text.trim();
      final resp = await sesion.api.post('/auth/login', {
        'email': email,
        'password': _passCtrl.text,
      });
      await _completarLogin(sesion, resp, email);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _mostrarAviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// HU-27 ("cambiar de vista", `02-backlog/backlog.md`): procesa la respuesta de
  /// `/auth/login`/`/auth/google` una vez ya autenticadas las credenciales — comparten esta
  /// lógica [_login] e [_iniciarConGoogle], que reciben el mismo shape de respuesta
  /// (`emitirLoginParaUsuario`, `../backend/src/routes/auth.ts`). No se aplica al 3er lugar de
  /// este archivo que también llama `sesion.iniciarSesion` (confirmación de vinculación de
  /// Google dentro de [_pedirPasswordParaVincular]) — ver el comentario puntual ahí.
  /// - Sin `negocios` (caso común — un solo negocio, o rol cliente sin negocio): entra directo,
  ///   sin ningún cambio de comportamiento respecto de antes de esta historia.
  /// - `negocios` vacío (profesional/administrador todavía sin ningún negocio activo): entra
  ///   igual — no hay nada para elegir. El Dashboard (`profesional/dashboard_screen.dart`)
  ///   muestra un estado claro en vez de una pantalla en blanco, ver esa pantalla.
  /// - `negocios` con 2+ elementos: pide elegir uno ANTES de entrar (ver
  ///   `widgets/selector_negocio.dart`) y recién ahí llama `POST /auth/entrar-a-negocio` para
  ///   obtener el token definitivo, ya con `negocio_id`. Si se cancela el selector, no entra —
  ///   se queda en este login (mismo criterio que cualquier login incompleto).
  Future<void> _completarLogin(Sesion sesion, Map<String, dynamic> resp, String email) async {
    final negociosRaw = resp['negocios'] as List<dynamic>?;
    if (negociosRaw == null) {
      sesion.iniciarSesion(resp['token'] as String, email: email);
      return;
    }
    final negocios = negociosRaw.map((n) => NegocioMembresia.fromApi(n as Map<String, dynamic>)).toList();
    if (negocios.isEmpty) {
      sesion.iniciarSesion(resp['token'] as String, email: email, negocios: negocios);
      return;
    }
    final elegido = await elegirNegocio(context, negocios);
    if (!mounted) return;
    if (elegido == null) {
      _mostrarAviso('Elegí un negocio para continuar.');
      return;
    }
    await sesion.entrarANegocio(
      elegido.negocioId,
      tokenPrevio: resp['token'] as String,
      email: email,
      negocios: negocios,
    );
  }

  /// HU-35 — se dispara cuando [GoogleSignInButton] ya resolvió un login de Google exitoso
  /// (`idToken`/`email` vienen del propio SDK de Google, no del backend). A partir de acá el
  /// contrato es el mismo `ApiClient`/`Sesion` que usa [_login]:
  /// - `200`/`201` con `{token}` (o `{token, negocios}`, HU-27 — mismo manejo que [_login], ver
  ///   [_completarLogin]) → sesión iniciada (o selector de negocio si corresponde).
  /// - `401`/`403`/`503` → error tal cual lo manda el backend (mismo patrón que [_login]).
  /// - `409` con `requiere_confirmacion_password: true` → ya existe una cuenta por contraseña con
  ///   ese email; pasa a [_pedirPasswordParaVincular] en vez de mostrarse como error.
  Future<void> _iniciarConGoogle(String idToken, String email) async {
    if (_googleCargando) return;
    setState(() {
      _googleCargando = true;
      _error = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final resp = await sesion.api.post('/auth/google', {'id_token': idToken});
      await _completarLogin(sesion, resp, email);
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.body?['requiere_confirmacion_password'] == true) {
        if (mounted) await _pedirPasswordParaVincular(email, idToken);
      } else if (mounted) {
        setState(() => _error = e.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _googleCargando = false);
    }
  }

  /// HU-35, regla de Security (`02-backlog/backlog.md`, "Resuelto (Security, 2026-08-10)", punto
  /// 2): ya existe una cuenta creada por contraseña con este email — nunca se vincula sola por
  /// coincidencia de email. Pide esa contraseña acá y la confirma en `POST /auth/login` junto con
  /// el mismo `id_token` que ya dio Google: ese endpoint valida la contraseña, vincula la cuenta
  /// de Google y devuelve el login en un único paso (ver el comentario sobre HU-35 en el handler
  /// de `/login`, `src/routes/auth.ts`) — reutiliza el mismo rate limiting que el login normal,
  /// no abre un endpoint nuevo.
  Future<void> _pedirPasswordParaVincular(String email, String idToken) async {
    final sesion = context.read<Sesion>();
    final passwordCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool enviando = false;
        String? dialogError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> confirmar() async {
              setDialogState(() {
                enviando = true;
                dialogError = null;
              });
              try {
                final resp = await sesion.api.post('/auth/login', {
                  'email': email,
                  'password': passwordCtrl.text,
                  'id_token': idToken,
                });
                // A propósito NO pasa por `_completarLogin` (HU-27): vincular Google + tener 2+
                // negocios activos a la vez es una combinación de casos borde muy poco probable,
                // y abrir acá el selector de negocio (pantalla completa) encima de este diálogo
                // ya abierto agrega una complejidad de navegación anidada que esta ronda no
                // ejercita. Si la respuesta trajera `negocios`, este `as String` sigue
                // funcionando igual que antes de esta historia (mismo gap ya documentado en
                // README.md de este proyecto).
                sesion.iniciarSesion(resp['token'] as String, email: email);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (e) {
                setDialogState(() {
                  enviando = false;
                  dialogError = e.toString();
                });
              }
            }

            return AlertDialog(
              title: const Text('Vincular cuenta de Google'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ya existe una cuenta con este email ($email) — ingresá tu contraseña para vincular Google.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    autofocus: true,
                    obscureText: true,
                    enabled: !enviando,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) {
                      if (!enviando) confirmar();
                    },
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(dialogError!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: enviando ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: enviando ? null : confirmar,
                  child: enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
    passwordCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Branding real de la app (logo provisto por el CEO — ver flutter_launcher_icons.yaml
            // / flutter_native_splash.yaml para el mismo asset usado como ícono/splash). Envuelto
            // en `Center` para que no se estire al ancho completo pese al `CrossAxisAlignment
            // .stretch` de esta Column (mismo criterio que el resto de la pantalla).
            //
            // El PNG trae su propio fondo blanco opaco "horneado" detrás del ícono redondeado
            // (no hay una versión con transparencia, ver flutter_launcher_icons.yaml) — en tema
            // oscuro eso se ve como un cuadrado blanco con esquinas filosas flotando sobre
            // `background`. `ClipRRect` con `AppRadius.card` redondea ese borde exterior para que
            // se lea como una tarjeta de logo intencional en vez de un recorte accidental, en los
            // dos temas.
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Nombre de marca + bajada, del wireframe de referencia de esta pantalla
            // (`04-diseno/mapa-pantallas.md` §5.17, tomado de `Screenshot_20260805_202552_
            // Turnario.jpg`) — quedó pendiente de implementar hasta ahora, sin relación con
            // ninguna historia nueva.
            Text('Turnario', textAlign: TextAlign.center, style: AppTypography.displayTitle(context)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Gestiona tus citas de manera fácil',
              textAlign: TextAlign.center,
              style: AppTypography.subtitle(context),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            // HU-37: reubicado para que coincida con el wireframe de referencia de esta pantalla
            // (`04-diseno/mapa-pantallas.md` §5.17) — entre el campo de contraseña y el botón
            // "Ingresar", alineado a la derecha, no debajo del botón. Deshabilitado durante un
            // login en curso, mismo criterio que el resto de los controles de esta pantalla.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: (_cargando || _googleCargando)
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecuperarPasswordScreen())),
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: AppSpacing.sm),
            ],
            FilledButton(
              onPressed: (_cargando || _googleCargando) ? null : _login,
              child: _cargando ? const CircularProgressIndicator() : const Text('Ingresar'),
            ),
            const SizedBox(height: AppSpacing.md),
            // HU-35 (mapa-pantallas.md §5.17): outline, con el logo de Google, debajo del botón
            // principal — mismo criterio de radio moderado (no píldora) que sistema-diseno.md
            // §7.1bis ya documenta para los botones de esta pantalla.
            GoogleSignInButton(
              onSignedIn: _iniciarConGoogle,
              onError: _mostrarAviso,
              onUnavailable: () => _mostrarAviso('Login con Google no está disponible en este momento'),
            ),
            const SizedBox(height: AppSpacing.xl),
            // HU-00a/HU-01: único punto de entrada Mobile al alta pre-autenticación — antes había
            // 2 links acá (uno a `RegistroNegocioScreen`, otro a `RegistroClienteScreen`),
            // unificados en 1 solo que deriva la elección a `RegistroSelectorScreen` (ver su
            // doc-comment). Esa pantalla vive fuera de cualquier shell, pre-autenticación, igual
            // que este login. Deshabilitado mientras hay un login en curso, mismo criterio que ya
            // usa el botón "Ingresar" de arriba.
            TextButton(
              onPressed: (_cargando || _googleCargando)
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistroSelectorScreen())),
              child: const Text('¿Todavía no tenés cuenta? Registrate'),
            ),
          ],
        ),
      ),
    );
  }
}
