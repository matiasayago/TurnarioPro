import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'mis_turnos_screen.dart';

/// HU-09b: confirma la reserva. Si el profesional requiere seña para este servicio (D2/RN10),
/// el backend responde con `estado: pendiente_de_pago` y esta pantalla abre el checkout de
/// Mercado Pago para que el cliente pague la seña (Task #114, ver
/// `_abrirCheckoutDeMercadoPago` más abajo); si no requiere seña, el turno queda `confirmado`
/// directo. Si otro cliente reservó el mismo horario primero, el backend responde 409 (RN2) — es
/// el caso de error más importante de esta pantalla, no un detalle secundario.
///
/// Layout (fast-follow del CEO, 2026-08-18): estilo tomado de `profesional/nueva_cita_screen.dart`
/// (captura de referencia) — una card por campo, label en negrita arriba, check verde junto al
/// valor. Acá es solo una adaptación VISUAL: a diferencia de esa pantalla, ningún campo es
/// editable (el cliente ya eligió todo en las 3 pantallas previas del flujo), así que no hay
/// selectores/dropdowns, solo el resumen de solo lectura — ver [_CampoConfirmadoCard].
class ConfirmarTurnoScreen extends StatefulWidget {
  const ConfirmarTurnoScreen({
    super.key,
    required this.profesionalId,
    required this.profesionalNombre,
    required this.servicioId,
    required this.servicioNombre,
    required this.inicio,
  });

  final String profesionalId;
  final String profesionalNombre;
  final String servicioId;

  /// Ver el doc-comment de `HorariosDisponiblesScreen.servicioNombre` — llega por la misma
  /// cadena de navegación, originada en `DetalleNegocioScreen`.
  final String servicioNombre;
  final String inicio;

  @override
  State<ConfirmarTurnoScreen> createState() => _ConfirmarTurnoScreenState();
}

class _ConfirmarTurnoScreenState extends State<ConfirmarTurnoScreen> {
  bool _reservando = false;
  String? _error;

  Future<void> _confirmar() async {
    setState(() {
      _reservando = true;
      _error = null;
    });
    try {
      final api = context.read<Sesion>().api;
      final turno = await api.post('/turnos', {
        'profesional_id': widget.profesionalId,
        'servicio_id': widget.servicioId,
        'inicio': widget.inicio,
      });

      if (!mounted) return;
      if (turno['requiere_pago'] == true) {
        // Task #114: reemplaza el AlertDialog viejo (solo avisaba "seña requerida" y nunca
        // llamaba a nada) por el checkout real de Mercado Pago — ver el doc-comment de
        // `_abrirCheckoutDeMercadoPago` para el flujo completo y sus límites explícitos.
        await _abrirCheckoutDeMercadoPago(api, turno['id'] as String);
      }
      if (!mounted) return;
      // `NavigatorState` (no el `BuildContext` de esta pantalla) para el callback
      // `MisTurnosScreen.onIrABuscar`: el `pushAndRemoveUntil` de abajo saca a ESTA pantalla de
      // la pila apenas corre, así que su propio `context` queda inválido para cualquier lookup
      // posterior (ej. cuando el usuario recién más tarde toca el ícono "+" del header) — el
      // `NavigatorState` en cambio sigue vivo mientras la app corra, es seguro guardarlo. Acá
      // "ir a Buscar" equivale a volver a la pantalla de abajo en la pila (`ClienteShell`, ya en
      // su pestaña "Buscar": es la única forma de haber llegado hasta este flujo de reserva).
      final navigator = Navigator.of(context);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => MisTurnosScreen(onIrABuscar: navigator.pop)),
        (route) => route.isFirst,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 409
          ? 'Ese horario ya no está disponible — alguien más lo reservó. Elegí otro horario.'
          : e.message);
    } finally {
      if (mounted) setState(() => _reservando = false);
    }
  }

  /// Post-creación del turno (D2/RN10, Task #114): si requiere seña, pide a Backend la URL de
  /// checkout de Mercado Pago (`POST /turnos/:id/pago`, ver `routes/turnos.ts`/
  /// `integraciones/pagos.ts`) y la abre en el navegador del sistema — `platformDefault` en web
  /// (nueva pestaña), navegador nativo en mobile — para que el cliente pague ahí, afuera de la
  /// app. Cambio de `externalApplication` a `platformDefault` (2026-08-23): en web,
  /// `externalApplication` intenta un popup que puede ser bloqueado; `platformDefault` abre
  /// pestaña nueva que funciona en todos los navegadores.
  ///
  /// Esta pantalla NO espera ninguna confirmación de pago acá: eso lo resuelve, aparte, el job de
  /// verificación (Task #103, todavía no implementado) cuando Mercado Pago avise por webhook
  /// (`POST /webhooks/mercadopago`). Por el mismo motivo, vuelva el cliente habiendo pagado o no
  /// (cierre el navegador, cancele en Mercado Pago, o pague), esta pantalla sigue el mismo camino
  /// de siempre hacia "Mis Turnos" (el segundo `if (!mounted) return;` de [_confirmar], ya
  /// existente, corre igual apenas este método termina) — cambiar ESE flujo de navegación es
  /// Task #115, no esta.
  ///
  /// Por eso también cualquier error acá (Mercado Pago no configurado/caído — 503, ver
  /// `turnos.ts` — o el dispositivo sin ninguna app que abra la URL) se avisa con un SnackBar
  /// pero nunca se relanza: el turno YA quedó creado en `pendiente_de_pago` en la llamada
  /// anterior, así que un fallo acá no es un estado roto, solo un pago que el cliente puede
  /// reintentar más tarde. Por lo mismo NO reusa el `catch (e) on ApiException` de [_confirmar]
  /// (ese interpreta un 409 como "el horario ya fue tomado", RN2 — un 409 de este otro endpoint
  /// significa algo completamente distinto, "sin pago pendiente para cobrar", ver `turnos.ts`).
  Future<void> _abrirCheckoutDeMercadoPago(ApiClient api, String turnoId) async {
    try {
      final pago = await api.post('/turnos/$turnoId/pago', const {});
      final urlCheckout = pago['url_checkout'] as String?;
      if (urlCheckout == null || urlCheckout.isEmpty) return;

      final abierto = await launchUrl(Uri.parse(urlCheckout), mode: LaunchMode.platformDefault);
      if (abierto) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No encontramos una app para abrir Mercado Pago. Podés pagar la seña más tarde desde "Mis Turnos".',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No pudimos iniciar el pago de la seña ($e). Podés reintentarlo más tarde desde "Mis Turnos".',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final formato = DateFormat('EEEE d MMMM · HH:mm', 'es');
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '✅',
        title: 'Confirmar Turno',
        showBackButton: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _CampoConfirmadoCard(
            label: 'Servicio',
            child: Text(
              widget.servicioNombre,
              style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _CampoConfirmadoCard(
            label: 'Profesional',
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primaryContainer,
                  child: Icon(Icons.person, color: colors.primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.profesionalNombre,
                    style:
                        AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _CampoConfirmadoCard(
            label: 'Fecha y Hora',
            child: Text(
              formato.format(DateTime.parse(widget.inicio).toLocal()),
              style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _FeedbackBanner(mensaje: _error!, esError: true),
          ],
        ],
      ),
      bottomNavigationBar: _footer(context),
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
          child: Row(
            children: [
              Expanded(
                child: OutlineButton(
                  label: 'Cancelar',
                  radiusVariant: AppButtonRadius.card,
                  // El turno todavía no existe en este punto (recién se crea abajo, en
                  // `_confirmar`) — un `pop` simple alcanza, sin tocar ningún endpoint. Distinto
                  // de cancelar un turno YA reservado (`mis_turnos_screen.dart`/`_cancelar`).
                  onPressed: _reservando ? null : () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PrimaryButton(
                  label: 'Confirmar Turno',
                  radiusVariant: AppButtonRadius.card,
                  loading: _reservando,
                  onPressed: _reservando ? null : _confirmar,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de campo de solo lectura — estilo pedido por el CEO a partir de la captura de
/// `nueva_cita_screen.dart` (ver doc-comment de la clase de arriba): card propia por campo,
/// label en negrita arriba, check verde junto al valor. Acá el check no es condicional (a
/// diferencia de un formulario editable): los 3 campos de esta pantalla siempre están
/// confirmados, es un resumen de solo lectura.
class _CampoConfirmadoCard extends StatelessWidget {
  const _CampoConfirmadoCard({required this.label, required this.child});

  final String label;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: child),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.check_circle, color: colors.success.base),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mismo patrón de banner de error que el resto de las pantallas de esta app (ej.
/// `registro_cliente_screen.dart`), duplicado localmente a propósito.
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
