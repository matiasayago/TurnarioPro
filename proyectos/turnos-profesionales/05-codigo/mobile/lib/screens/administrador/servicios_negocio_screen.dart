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
/// `{ id, nombre, duracion_min, precio_referencia }`; baja `DELETE
/// /negocios/:id/servicios/:servicioId` (E15 fast-follow, 2026-08-17 — ver `_eliminarServicio`/
/// `_ServicioCard` más abajo) -> 200 `{ id, eliminado: true }` | 403 rol distinto de administrador
/// o negocio ajeno | 404 no existe, ya estaba eliminado, o es de otro negocio.
///
/// La baja es SOFT-DELETE (`servicio.eliminado_en`), nunca `DELETE` físico — el backend nunca borra
/// la fila para no romper la FK `turno.servicio_id` (NOT NULL) de turnos ya existentes; esos
/// turnos, pasados o futuros, quedan intactos. El administrador confirma explícitamente antes de
/// desactivar (`_confirmarEliminacion`) — a diferencia de pausar un profesional
/// (`profesionales_negocio_screen.dart`), este endpoint no tiene contraparte de "reactivar", así
/// que el diálogo lo aclara junto con que el historial no se rompe.
///
/// Sin edición: `negocios.ts` sigue sin exponer un `PATCH` para este recurso — el nombre/duración/
/// precio de un servicio ya cargado siguen sin poder modificarse desde esta pantalla, solo darse
/// de baja (y, si hace falta un reemplazo con otros datos, cargar uno nuevo).
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

  /// Da de baja (soft-delete) [servicio] — `DELETE /negocios/:id/servicios/:servicioId`. Siempre
  /// pide confirmación primero (`_confirmarEliminacion`, a diferencia de reactivar un profesional
  /// en la pantalla hermana, acá no hay ninguna rama "sin confirmar": esta acción es más seria que
  /// pausar — no tiene contraparte de "reactivar" — así que se confirma siempre, sin excepción).
  ///
  /// `context` es el de la card que disparó la acción (mismo criterio que
  /// `ProfesionalesNegocioScreen._cambiarEstado` — ver el doc comment de ese método para el porqué
  /// de usar `context.mounted` en vez del `mounted` del State en los guards post-`await`).
  Future<void> _eliminarServicio(BuildContext context, _Servicio servicio) async {
    final confirmado = await _confirmarEliminacion(context, servicio.nombre);
    if (confirmado != true || !context.mounted) return;

    final sesion = context.read<Sesion>();
    try {
      await sesion.api.delete('/negocios/${sesion.negocioId}/servicios/${servicio.id}');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${servicio.nombre}" fue desactivado.')));
      await _refrescar();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo desactivar: $e')));
    }
  }

  /// Diálogo nativo (`showDialog`+`AlertDialog`), mismo patrón ya usado en esta app (ver
  /// `login_screen.dart`, `_pedirPasswordParaVincular`, y `ProfesionalesNegocioScreen.
  /// _confirmarPausa`) — no hay un helper de confirmación reusable en `lib/widgets/` todavía. El
  /// botón de confirmar usa el mismo criterio que documenta `DestructiveButton`
  /// (`widgets/buttons.dart`: "no usar [el sólido rojo de ancho completo] para eliminar una fila de
  /// lista, donde una variante outline podría ser más apropiada") — acá, dentro de un `AlertDialog`
  /// nativo, eso se traduce en un `TextButton` (mismo tratamiento "sin relleno" que "Cancelar") con
  /// el texto en `danger` en vez de un botón sólido, para no competir en peso visual con las
  /// acciones de confirmación no-destructivas del resto de la app (ej. "Pausar", `FilledButton`
  /// neutro en `ProfesionalesNegocioScreen`).
  Future<bool?> _confirmarEliminacion(BuildContext context, String nombreServicio) {
    final colors = AppColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desactivar servicio'),
        content: Text(
          '"$nombreServicio" va a dejar de estar disponible para reservar turnos nuevos. Los turnos '
          'que ya existen contra este servicio no se modifican ni se cancelan — tu historial y tus '
          'reportes quedan intactos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: colors.danger.base),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
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
                    _ServicioCard(
                      servicio: servicio,
                      onEliminar: (context) => _eliminarServicio(context, servicio),
                    ),
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

/// A diferencia de la versión previa (`StatelessWidget` puramente informativa), esta card ahora
/// dispara una escritura (`onEliminar`) — pasa a `StatefulWidget` únicamente para llevar
/// `_procesando` (deshabilita la acción y muestra un spinner chico mientras el DELETE está en
/// vuelo), mismo criterio exacto que `_ProfesionalCard`/`_ProfesionalCardState` en
/// `profesionales_negocio_screen.dart` — ver el doc comment de esa clase para el razonamiento
/// completo (aplica palabra por palabra acá: en el camino feliz la card se descarta apenas
/// `_refrescar()` reemplaza la lista, `_procesando` solo importa en error/cancelación).
class _ServicioCard extends StatefulWidget {
  const _ServicioCard({required this.servicio, required this.onEliminar});

  final _Servicio servicio;

  /// `BuildContext` de ESTA card — mismo criterio que `_ProfesionalCard.onCambiarEstado`.
  final Future<void> Function(BuildContext context) onEliminar;

  @override
  State<_ServicioCard> createState() => _ServicioCardState();
}

class _ServicioCardState extends State<_ServicioCard> {
  bool _procesando = false;

  Future<void> _tocar() async {
    setState(() => _procesando = true);
    await widget.onEliminar(context);
    if (mounted) setState(() => _procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final servicio = widget.servicio;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  servicio.nombre,
                  style:
                      AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('${servicio.duracionMin} min · $precio', style: AppTypography.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Ícono de acción en fila (tacho de basura) — mismo criterio de "botón de texto chico"
          // que `_AccionPaciente`/`_AccionProfesional` en las pantallas hermanas, pero acá solo un
          // `IconButton` sin label: una única acción posible por card (a diferencia de Pausar/
          // Reactivar, que alternan según `activo`), así que el ícono solo ya es inequívoco —
          // agregar un label fijo ("Desactivar") habría sido redundante con el diálogo de
          // confirmación que se abre al tocarlo.
          IconButton(
            tooltip: 'Desactivar servicio',
            onPressed: _procesando ? null : _tocar,
            icon: _procesando
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.danger.base),
                  )
                : Icon(Icons.delete_outline, color: colors.danger.base),
          ),
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
