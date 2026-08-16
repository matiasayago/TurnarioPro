import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/sesion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/widgets.dart';
import 'canjear_token_password_screen.dart';

/// HU-37 (`02-backlog/backlog.md`, épica E4, extiende HU-01/HU-35) — paso 1 de 2 del flujo de
/// recuperación de contraseña: pantalla pre-autenticación, vive junto a `login_screen.dart`/
/// `registro_negocio_screen.dart`, fuera de cualquier shell — enlazada desde el link "¿Olvidaste
/// tu contraseña?" de esa pantalla (ver `LoginScreen`), antes de cualquier login.
///
/// Contrato: `POST /auth/recuperar-password` (`src/routes/auth.ts`, ya en producción/Render),
/// body `{ email }` -> SIEMPRE 200 `{ ok: true, mensaje: '...' }`, exista o no la cuenta, tenga o
/// no contraseña (cuenta 100%-Google, HU-35) — criterio de no-enumeración de usuarios explícito de
/// HU-37: no hay ningún 400/404 de negocio que distinguir acá, ni forma de intentarlo desde esta
/// pantalla. En desarrollo (`ENABLE_DEV_ROUTES=true`) el backend agrega además `token_dev` a esa
/// misma respuesta — pura ayuda de testing, nunca presente en producción real (en Render ese flag
/// queda en `false`) y a propósito IGNORADO acá: [CanjearTokenPasswordScreen] pide el token igual
/// que lo pediría en producción, un campo de texto vacío, nunca autorrellenado.
///
/// Sin deep-linking (backlog.md, "Flujo funcional en 2 pasos... no es una decisión de producto
/// abierta a reabrir"): el usuario recibe el token por email en texto plano y lo copia/pega a mano
/// en la pantalla siguiente. Apenas llega el 200 (siempre), esta pantalla empuja
/// [CanjearTokenPasswordScreen] con `Navigator.push` (no reemplaza, para poder volver acá si el
/// usuario todavía no tiene el token a mano) — el email tipeado viaja solo como referencia visual
/// para esa pantalla, nunca se reenvía al backend (el canje en sí es únicamente
/// `{ token, password }`, ver el doc-comment de esa clase).
class RecuperarPasswordScreen extends StatefulWidget {
  const RecuperarPasswordScreen({super.key});

  @override
  State<RecuperarPasswordScreen> createState() => _RecuperarPasswordScreenState();
}

class _RecuperarPasswordScreenState extends State<RecuperarPasswordScreen> {
  final _emailCtrl = TextEditingController();

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _solicitar() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _mensaje = 'Ingresá tu email.';
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
      // Contrato de HU-37: siempre 200 (ver doc-comment de la clase) — no hay ningún código de
      // error de negocio que este catch necesite distinguir, a diferencia del resto de los
      // formularios pre-autenticación de esta app.
      final resp = await sesion.api.post('/auth/recuperar-password', {'email': email});
      if (!mounted) return;
      setState(() => _enviando = false);
      // Mismo mensaje genérico que ya trae la respuesta (criterio de no-enumeración) — se avisa
      // por SnackBar, no por el banner de más abajo, porque esta pantalla se abandona de
      // inmediato (mismo criterio que "Perfil actualizado." en `editar_perfil_screen.dart`): al
      // usar el `ScaffoldMessenger` global de `MaterialApp`, el aviso sigue visible aunque ya se
      // haya empujado la pantalla siguiente encima.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp['mensaje'] as String)));
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CanjearTokenPasswordScreen(email: email)),
      );
    } catch (e) {
      // Solo alcanzable por un problema de red/servidor ajeno al propio flujo de negocio (rate
      // limiting incluido, HIGH-1) — el endpoint en sí nunca responde un error de negocio, ver
      // doc-comment de la clase.
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo enviar la solicitud: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🔑',
        title: 'Recuperar Contraseña',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresá el email con el que te registraste. Si está asociado a una cuenta, vas a '
              'recibir un email con un token para elegir una contraseña nueva.',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: AppSpacing.base),
            _sectionCard(
              context,
              child: TextField(
                controller: _emailCtrl,
                enabled: !_enviando,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email *'),
                onSubmitted: (_) {
                  if (!_enviando) _solicitar();
                },
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

  Widget _footer(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: PrimaryButton(
            label: 'Enviar Instrucciones',
            radiusVariant: AppButtonRadius.card,
            loading: _enviando,
            onPressed: _enviando ? null : _solicitar,
          ),
        ),
      ),
    );
  }
}

/// Mismo patrón de banner de éxito/error que el resto de las pantallas de esta app (ej.
/// `registro_negocio_screen.dart`), duplicado localmente a propósito. En la práctica esta pantalla
/// solo lo usa en su variante de error (ver [_RecuperarPasswordScreenState._solicitar]: el 200
/// nunca llega a mostrarse acá, se avisa por SnackBar antes de navegar) — se mantiene el mismo
/// componente de dos variantes que el resto de la app, en vez de escribir un widget de un solo
/// color.
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
