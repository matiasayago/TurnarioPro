import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'mis_turnos_screen.dart';

/// HU-09b: confirma la reserva. Si el profesional requiere seña para este servicio (D2/RN10),
/// el backend responde con `estado: pendiente_de_pago`; si no, queda `confirmado` directo.
/// Si otro cliente reservó el mismo horario primero, el backend responde 409 (RN2) — es el
/// caso de error más importante de esta pantalla, no un detalle secundario.
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
        // TODO: integrar checkout real (Mercado Pago) cuando Integraciones reemplace el Mock
        // del backend (ver backend/src/integraciones/pagos.ts) — este slice solo confirma.
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Seña requerida'),
            content:
                Text('Este turno requiere una seña de \$${turno['monto_sena']}. Completá el pago para confirmarlo.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
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
