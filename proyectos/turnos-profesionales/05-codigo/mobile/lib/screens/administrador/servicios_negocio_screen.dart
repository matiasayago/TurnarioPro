import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Servicios del Negocio (Panel Administrador, HU-03 — épica E15 "Modo Administrador v1",
/// `02-backlog/backlog.md`). Contrato: alta `POST /negocios/:id/servicios`
/// (`requireAuth('administrador')`), body `{ nombre, duracion_min, precio_referencia? }` -> 201
/// `{ id }`; listado `GET /negocios/:id/servicios` (público — mismo endpoint que ya consume
/// `screens/cliente/detalle_negocio_screen.dart` en el flujo de reserva de HU-07) -> array de
/// `{ id, nombre, duracion_min, precio_referencia }`.
///
/// Sin edición ni baja: `negocios.ts` solo expone alta para este recurso (ver "Fuera de alcance"
/// de esta épica en el backlog: "remoción de un servicio... sin endpoint") — cada servicio, una
/// vez cargado, es de solo lectura en esta pantalla.
class ServiciosNegocioScreen extends StatefulWidget {
  const ServiciosNegocioScreen({super.key});

  @override
  State<ServiciosNegocioScreen> createState() => _ServiciosNegocioScreenState();
}

class _ServiciosNegocioScreenState extends State<ServiciosNegocioScreen> {
  late Future<List<_Servicio>> _futureServicios;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _futureServicios = sesion.negocioId == null
        ? Future.error(Exception('No se pudo determinar tu negocio (falta negocio_id en la sesión).'))
        : _cargar();
  }

  Future<List<_Servicio>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/negocios/${sesion.negocioId}/servicios');
    return raw.map((e) => _Servicio.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() => _futureServicios = next);
    await next;
  }

  Future<void> _abrirAlta() async {
    final creado = await AppModalSheet.show<bool>(context, builder: (_) => const _AltaServicioSheet());
    if (creado == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servicio agregado.')));
      await _refrescar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🧰',
        title: 'Servicios del Negocio',
        showBackButton: true,
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_Servicio>>(
          future: _futureServicios,
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
                    child: Text(
                      'No se pudieron cargar los servicios: ${snapshot.error}',
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            final servicios = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                if (servicios.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        'Todavía no cargaste ningún servicio. Agregá el primero con el botón de abajo.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body(context),
                      ),
                    ),
                  )
                else
                  for (final servicio in servicios) ...[
                    _ServicioCard(servicio: servicio),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.base),
                PrimaryButton(
                  label: 'Agregar Servicio',
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

/// Igual criterio de formateo que `profesional/precios_senas_screen.dart`/`reportes_screen.dart`
/// (duplicado a propósito, ver convención ya documentada en ese archivo): sin decimales sobrantes
/// para los montos típicos de este dominio.
String _formatMonto(num valor) => valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toStringAsFixed(2);

class _Servicio {
  const _Servicio({
    required this.id,
    required this.nombre,
    required this.duracionMin,
    required this.precioReferencia,
  });

  final String id;
  final String nombre;
  final int duracionMin;
  final num? precioReferencia;

  factory _Servicio.fromApi(Map<String, dynamic> json) => _Servicio(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        duracionMin: json['duracion_min'] as int,
        precioReferencia: json['precio_referencia'] as num?,
      );
}

class _ServicioCard extends StatelessWidget {
  const _ServicioCard({required this.servicio});

  final _Servicio servicio;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final precio =
        servicio.precioReferencia != null ? '\$${_formatMonto(servicio.precioReferencia!)}' : 'sin precio de referencia';
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
          Text(
            servicio.nombre,
            style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('${servicio.duracionMin} min · $precio', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}

/// Alta de servicio — modal de pantalla completa (`AppModalSheet`), mismo patrón que
/// `profesional/nueva_cita_screen.dart`: `pop(true)` al crear con éxito para que la pantalla que
/// lo abrió sepa que tiene que refrescar la lista.
class _AltaServicioSheet extends StatefulWidget {
  const _AltaServicioSheet();

  @override
  State<_AltaServicioSheet> createState() => _AltaServicioSheetState();
}

class _AltaServicioSheetState extends State<_AltaServicioSheet> {
  final _nombreCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  int _duracionMin = 30;

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() {
        _mensaje = 'Ingresá un nombre para el servicio.';
        _mensajeEsError = true;
      });
      return;
    }
    double? precio;
    final precioTexto = _precioCtrl.text.trim();
    if (precioTexto.isNotEmpty) {
      precio = double.tryParse(precioTexto.replaceAll(',', '.'));
      if (precio == null || precio <= 0) {
        setState(() {
          _mensaje = 'Ingresá un precio de referencia válido mayor a 0, o dejalo vacío.';
          _mensajeEsError = true;
        });
        return;
      }
    }

    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/negocios/${sesion.negocioId}/servicios', {
        'nombre': nombre,
        'duracion_min': _duracionMin,
        'precio_referencia': precio,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo agregar el servicio: ${e.message}';
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _mensaje = 'No se pudo agregar el servicio: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: 'Agregar Servicio',
      primaryLabel: 'Guardar',
      primaryLoading: _enviando,
      onPrimary: _enviando ? null : _guardar,
      onSecondary: _enviando ? null : () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nombreCtrl,
                  enabled: !_enviando,
                  decoration: const InputDecoration(labelText: 'Nombre del servicio *'),
                ),
                const SizedBox(height: AppSpacing.md),
                NumericStepperField(
                  label: 'Duración',
                  value: _duracionMin,
                  min: 15,
                  max: 240,
                  step: 15,
                  unit: ' min',
                  onChanged: (v) => setState(() => _duracionMin = v),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _precioCtrl,
                  enabled: !_enviando,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Precio de referencia (opcional)', prefixText: '\$ '),
                ),
              ],
            ),
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.base),
            _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
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
