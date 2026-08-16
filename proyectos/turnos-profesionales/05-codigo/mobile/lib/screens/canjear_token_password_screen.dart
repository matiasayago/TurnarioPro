import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../state/sesion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/widgets.dart';

/// HU-37 (`02-backlog/backlog.md`, épica E4) — paso 2 de 2 del flujo de recuperación de
/// contraseña: pantalla pre-autenticación, empujada por `recuperar_password_screen.dart` (ver el
/// doc-comment de `RecuperarPasswordScreen`) apenas ese paso 1 confirma el 200 (siempre) de
/// `POST /auth/recuperar-password`.
///
/// Contrato: `POST /auth/reset-password` (`src/routes/auth.ts`, ya en producción/Render), body
/// `{ token, password }` -> 200 `{ ok: true, mensaje: 'Contraseña actualizada correctamente.' }`
/// si el token es válido y no venció; 400 `{ error: 'Token inválido o vencido' }` en cualquier
/// otro caso (token inexistente, ya usado o vencido — el backend usa a propósito el mismo mensaje
/// para las tres razones, para no darle a un atacante información sobre cuál de ellas ocurrió;
/// esta pantalla no intenta distinguirlas tampoco). `password` se valida server-side con el mismo
/// `passwordSchema` de siempre (mínimo 8 caracteres) — validado también acá del lado del cliente,
/// con el mismo mensaje, mismo criterio que ya usa `registro_negocio_screen.dart` para su propio
/// campo de password.
///
/// [email] llega solo como referencia visual (ver doc-comment de `RecuperarPasswordScreen`) — el
/// canje en sí no lo usa: el `token` es la única prueba de identidad que recibe el backend.
///
/// Sin deep-linking (backlog.md): el token (64 caracteres hexadecimales) se pega a mano desde el
/// email — el campo de abajo es multilínea/monoespaciado para que un token largo sea legible y
/// fácil de revisar, en vez de forzarlo a una sola línea que scrollea horizontalmente.
///
/// A diferencia de `RegistroNegocioScreen` (HU-00a), acá NO hay auto-login al confirmar:
/// `POST /auth/reset-password` no firma ningún JWT nuevo (ver el contrato de arriba), así que el
/// destino correcto tras el 200 es volver al login para que el usuario entre con la contraseña
/// nueva — no un shell autenticado. Mismo mecanismo de navegación que `RegistroNegocioScreen`
/// (`Navigator.popUntil((route) => route.isFirst)`), pero acá alcanza sin más porque `Sesion`
/// nunca se autenticó en este flujo: `_Router` (`main.dart`) sigue viendo `autenticado == false` y
/// renderiza `LoginScreen` en esa misma ruta raíz, tal cual.
class CanjearTokenPasswordScreen extends StatefulWidget {
  const CanjearTokenPasswordScreen({super.key, required this.email});

  /// Solo para mostrarlo como referencia visual (ver doc-comment de la clase) — nunca viaja al
  /// backend desde esta pantalla.
  final String email;

  @override
  State<CanjearTokenPasswordScreen> createState() => _CanjearTokenPasswordScreenState();
}

class _CanjearTokenPasswordScreenState extends State<CanjearTokenPasswordScreen> {
  final _tokenCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarPasswordCtrl = TextEditingController();

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmarPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _canjear() async {
    final token = _tokenCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmarPassword = _confirmarPasswordCtrl.text;

    if (token.isEmpty) {
      setState(() {
        _mensaje = 'Pegá el token que te enviamos por email.';
        _mensajeEsError = true;
      });
      return;
    }
    // Mismo mínimo y mismo mensaje que el backend (`passwordSchema`, `src/dominio/validacion.ts`)
    // — mismo criterio que ya usa `registro_negocio_screen.dart` para su propio campo de password.
    if (password.length < 8) {
      setState(() {
        _mensaje = 'La contraseña debe tener al menos 8 caracteres';
        _mensajeEsError = true;
      });
      return;
    }
    if (password != confirmarPassword) {
      setState(() {
        _mensaje = 'Las contraseñas no coinciden.';
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
      final resp = await sesion.api.post('/auth/reset-password', {'token': token, 'password': password});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp['mensaje'] as String)));
      // Sin auto-login (ver doc-comment de la clase) — vuelve a la raíz de la navegación, donde
      // `_Router` (`main.dart`) sigue mostrando `LoginScreen` porque `Sesion` nunca se autenticó
      // en este flujo.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        // Mismo mensaje para token inexistente/ya usado/vencido (ver doc-comment de la clase) —
        // se muestra tal cual lo manda el backend, sin intentar adivinar ni distinguir el motivo.
        _mensaje = e.message;
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo restablecer la contraseña: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🔒',
        title: 'Restablecer Contraseña',
        showBackButton: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Te enviamos un email a ${widget.email} con un token de recuperación — pegalo acá '
              'junto con tu contraseña nueva.',
              style: AppTypography.caption(context),
            ),
            const SizedBox(height: AppSpacing.base),
            _sectionCard(
              context,
              title: 'Token recibido por email',
              child: TextField(
                controller: _tokenCtrl,
                enabled: !_enviando,
                minLines: 2,
                maxLines: 4,
                style: AppTypography.body(context).copyWith(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Token *', alignLabelWithHint: true),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _sectionCard(
              context,
              title: 'Contraseña nueva',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _passwordCtrl,
                    enabled: !_enviando,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña nueva *'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Mínimo 8 caracteres.', style: AppTypography.caption(context)),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _confirmarPasswordCtrl,
                    enabled: !_enviando,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirmar contraseña nueva *'),
                    onSubmitted: (_) {
                      if (!_enviando) _canjear();
                    },
                  ),
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
            label: 'Restablecer Contraseña',
            radiusVariant: AppButtonRadius.card,
            loading: _enviando,
            onPressed: _enviando ? null : _canjear,
          ),
        ),
      ),
    );
  }
}

/// Mismo patrón de banner de éxito/error que el resto de las pantallas de esta app (ej.
/// `registro_negocio_screen.dart`), duplicado localmente a propósito. En la práctica esta pantalla
/// solo lo usa en su variante de error (ver `_CanjearTokenPasswordScreenState._canjear`: el 200 se
/// avisa por SnackBar antes de volver al login, mismo criterio que `RecuperarPasswordScreen`).
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
