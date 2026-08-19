import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api_client.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Editar Perfil (Configuración > Cuenta > Editar Perfil, `configuracion_screen.dart`) — HU-32
/// (bloque "Cuenta" de `usuario.ts`, no el de privacidad). Contrato: `GET /usuario/perfil` ->
/// `{ id, nombre, email, telefono, rol }`; `PATCH /usuario/perfil`, body
/// `{ nombre: string, telefono: string | null }` -> mismo shape.
///
/// **`email` es de SOLO LECTURA** — el propio backend ni siquiera declara el campo en el schema
/// del PATCH (lo descarta en silencio si igual viaja en el body, ver comentario en
/// `src/routes/usuario.ts`): es el identificador único de login, cambiarlo excede el alcance de
/// esta pantalla. Se muestra igual (deshabilitado) para que el profesional vea con qué cuenta
/// está logueado, mismo criterio que los campos de solo lectura de `ficha_paciente_screen.dart`.
///
/// A diferencia de `FichaPacienteScreen`, esta pantalla NO tiene modo "ver" separado del modo
/// "editar": es la propia ficha del usuario autenticado (no una fila de una lista ajena que
/// primero se consulta y después, opcionalmente, se edita), así que arranca directo en un
/// formulario editable con un único botón "Guardar" al pie.
///
/// **"Servicios que brindo"** (fast-follow 2026-08-19: el CEO probó la app como Profesional y
/// pidió poder gestionar acá qué servicios ofrece, además de sacar el campo de ID de servicio de
/// texto libre de "Gestión de Horarios" — ver `gestion_horarios_screen.dart`). Sección nueva,
/// visible SOLO para `Rol.profesional` — mismo criterio de "una pantalla, varios roles, sección
/// condicionada por `sesion.rol`" que `configuracion_consultorio_screen.dart` (ver ese doc
/// comment): esta misma pantalla también la abren `Rol.cliente` y `Rol.administrador` (ver
/// `configuracion_cliente_screen.dart`/`administrador_shell.dart`), para quienes "servicios que
/// brindo" no aplica. Contrato: catálogo completo del negocio, `GET /negocios/:id/servicios`
/// (público, mismo endpoint que ya consume `cliente/detalle_negocio_screen.dart`) -> array de
/// `{ id, nombre, duracion_min, precio_referencia }`; ya asociados, `GET /profesionales/:id/servicios`
/// (mismo contrato que `precios_senas_screen.dart`, expone `servicio_id`); alta,
/// `POST /profesionales/:id/servicios`, body `{ servicio_id, requiere_sena: false }` -> 201. **Sin
/// baja**: `profesionales.ts` no publica ningún DELETE para desasociar, así que un servicio ya
/// asociado queda fijo ("Ya asociado", sin control) — la seña sí se configura después, servicio
/// por servicio, en "Precios y Señas" (`precios_senas_screen.dart`).
class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  late Future<void> _futureCarga;

  String _email = '';
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  // "Servicios que brindo" — ver el doc comment de la clase para el contrato completo y por qué
  // esta sección solo aplica a `Rol.profesional`. `_esProfesional` se resuelve una única vez en
  // [initState] (el rol de la sesión no cambia durante la vida de esta pantalla).
  late final bool _esProfesional;
  List<_ServicioCatalogo> _catalogoServicios = [];
  Set<String> _serviciosAsociadosIds = {};
  bool _cargandoServicios = true;
  String? _errorServicios;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _esProfesional = sesion.rol == Rol.profesional && sesion.profesionalId != null && sesion.negocioId != null;
    _futureCarga = _cargar();
    if (_esProfesional) _cargarServicios();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api.getMap('/usuario/perfil');
    _aplicarDatos(data);
  }

  void _aplicarDatos(Map<String, dynamic> data) {
    _email = data['email'] as String;
    _nombreCtrl.text = data['nombre'] as String;
    _telefonoCtrl.text = (data['telefono'] as String?) ?? '';
  }

  /// Carga en paralelo (junto con [_cargar], disparada desde [initState] sin esperarla) el
  /// catálogo completo del negocio y los servicios que el profesional ya asoció, para pintar
  /// [_serviciosBrindoContent]. Si cualquiera de los 2 pedidos falla, toda la sección muestra un
  /// único error — mostrar el catálogo sin saber cuáles ya están asociados (o viceversa) llevaría
  /// a un estado a medio camino más confuso que un error simple.
  Future<void> _cargarServicios() async {
    final sesion = context.read<Sesion>();
    try {
      final resultados = await Future.wait([
        sesion.api.getList('/negocios/${sesion.negocioId}/servicios'),
        sesion.api.getList('/profesionales/${sesion.profesionalId}/servicios'),
      ]);
      final catalogo = resultados[0].map((e) => _ServicioCatalogo.fromApi(e as Map<String, dynamic>)).toList();
      final asociados = resultados[1].map((e) => (e as Map<String, dynamic>)['servicio_id'] as String).toSet();
      if (!mounted) return;
      setState(() {
        _catalogoServicios = catalogo;
        _serviciosAsociadosIds = asociados;
        _cargandoServicios = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoServicios = false;
        _errorServicios = e.toString();
      });
    }
  }

  /// Asocia [servicioId] a la agenda del profesional — `POST /profesionales/:id/servicios`, sin
  /// seña por default (se ajusta después, servicio por servicio, en "Precios y Señas",
  /// `precios_senas_screen.dart`). Sin diálogo de confirmación: a diferencia de
  /// `_eliminarServicio` en `servicios_negocio_screen.dart` (mismo patrón de manejo de
  /// error/loading vía `context.mounted`, ver el doc comment de esa clase), esto es un alta
  /// simple y sin baja posible que la revierta — no hay nada "peligroso" que confirmar.
  Future<void> _asociarServicio(BuildContext context, String servicioId) async {
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/profesionales/${sesion.profesionalId}/servicios', {
        'servicio_id': servicioId,
        'requiere_sena': false,
      });
      if (!context.mounted) return;
      setState(() => _serviciosAsociadosIds = {..._serviciosAsociadosIds, servicioId});
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo agregar el servicio: $e')));
    }
  }

  String? _vacioANull(String texto) => texto.trim().isEmpty ? null : texto.trim();

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() {
        _mensaje = 'El nombre no puede estar vacío.';
        _mensajeEsError = true;
      });
      return;
    }
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final data = await sesion.api.patch('/usuario/perfil', {
        'nombre': nombre,
        'telefono': _vacioANull(_telefonoCtrl.text),
      });
      if (!mounted) return;
      setState(() {
        _aplicarDatos(data);
        _guardando = false;
        _mensaje = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo actualizar: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _futureCarga,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            appBar: AppHeader(
              variant: AppHeaderVariant.surface,
              emoji: '👤',
              title: 'Editar Perfil',
              showBackButton: true,
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: const AppHeader(
              variant: AppHeaderVariant.surface,
              emoji: '👤',
              title: 'Editar Perfil',
              showBackButton: true,
            ),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text('No se pudo cargar tu perfil: ${snapshot.error}', style: AppTypography.body(context)),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: const AppHeader(
            variant: AppHeaderVariant.surface,
            emoji: '👤',
            title: 'Editar Perfil',
            showBackButton: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  context,
                  title: 'Datos personales',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(controller: _nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                      const SizedBox(height: AppSpacing.md),
                      _campoSoloLectura(context, 'Email', _email),
                      const SizedBox(height: AppSpacing.xs),
                      Text('El email no se puede modificar desde la app.', style: AppTypography.caption(context)),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Teléfono'),
                      ),
                    ],
                  ),
                ),
                if (_esProfesional) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _sectionCard(
                    context,
                    title: 'Servicios que brindo',
                    child: _serviciosBrindoContent(context),
                  ),
                ],
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
      },
    );
  }

  Widget _campoSoloLectura(BuildContext context, String label, String value) {
    final colors = AppColors.of(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: label, enabled: false),
      child: Text(value, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
    );
  }

  Widget _serviciosBrindoContent(BuildContext context) {
    if (_cargandoServicios) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorServicios != null) {
      final colors = AppColors.of(context);
      return Text(
        'No se pudieron cargar los servicios del negocio: $_errorServicios',
        style: AppTypography.body(context).copyWith(color: colors.danger.base),
      );
    }
    if (_catalogoServicios.isEmpty) {
      return Text('Este negocio todavía no tiene servicios cargados.', style: AppTypography.body(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _catalogoServicios.length; i++) ...[
          if (i > 0) const Divider(height: AppSpacing.lg),
          _ServicioAsociacionTile(
            servicio: _catalogoServicios[i],
            asociado: _serviciosAsociadosIds.contains(_catalogoServicios[i].id),
            onAsociar: (context) => _asociarServicio(context, _catalogoServicios[i].id),
          ),
        ],
      ],
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
            label: 'Guardar',
            radiusVariant: AppButtonRadius.card,
            loading: _guardando,
            onPressed: _guardando ? null : _guardar,
          ),
        ),
      ),
    );
  }
}

/// Fila de `GET /negocios/:id/servicios` (catálogo público del negocio) — mismo contrato que ya
/// parsea `_Servicio` en `administrador/servicios_negocio_screen.dart` (duplicado localmente a
/// propósito, mismo criterio que el resto de los modelos privados de este código).
class _ServicioCatalogo {
  const _ServicioCatalogo({
    required this.id,
    required this.nombre,
    required this.duracionMin,
    required this.precioReferencia,
  });

  final String id;
  final String nombre;
  final int duracionMin;
  final num? precioReferencia;

  factory _ServicioCatalogo.fromApi(Map<String, dynamic> json) => _ServicioCatalogo(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        duracionMin: json['duracion_min'] as int,
        precioReferencia: json['precio_referencia'] as num?,
      );
}

/// Mismo criterio de formateo que `precios_senas_screen.dart`/`servicios_negocio_screen.dart`
/// (duplicado a propósito, convención ya documentada en esos archivos): sin decimales sobrantes
/// para los montos típicos de este dominio.
String _formatMonto(num valor) => valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toStringAsFixed(2);

/// Fila de "Servicios que brindo" — ya asociado (indicador fijo, sin acción: `profesionales.ts`
/// no publica ningún DELETE para esta asociación, ver el doc comment de
/// [_EditarPerfilScreenState._asociarServicio]) o todavía no asociado (botón "Agregar" que
/// dispara [onAsociar]). `StatefulWidget` solo para llevar `_procesando` mientras el POST está en
/// vuelo — mismo criterio que `_ServicioCardState` en `administrador/servicios_negocio_screen.dart`.
class _ServicioAsociacionTile extends StatefulWidget {
  const _ServicioAsociacionTile({required this.servicio, required this.asociado, required this.onAsociar});

  final _ServicioCatalogo servicio;
  final bool asociado;

  /// `BuildContext` de ESTA fila — mismo criterio que `_ServicioCard.onEliminar`
  /// (`administrador/servicios_negocio_screen.dart`).
  final Future<void> Function(BuildContext context) onAsociar;

  @override
  State<_ServicioAsociacionTile> createState() => _ServicioAsociacionTileState();
}

class _ServicioAsociacionTileState extends State<_ServicioAsociacionTile> {
  bool _procesando = false;

  Future<void> _tocar() async {
    setState(() => _procesando = true);
    await widget.onAsociar(context);
    if (mounted) setState(() => _procesando = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final servicio = widget.servicio;
    final precio =
        servicio.precioReferencia != null ? '\$${_formatMonto(servicio.precioReferencia!)}' : 'sin precio de referencia';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                servicio.nombre,
                style: AppTypography.body(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text('${servicio.duracionMin} min · $precio', style: AppTypography.caption(context)),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (widget.asociado)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 18, color: colors.success.base),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Ya asociado',
                style: AppTypography.caption(context).copyWith(color: colors.success.base, fontWeight: FontWeight.w600),
              ),
            ],
          )
        else
          SuccessButton(
            label: 'Agregar',
            radiusVariant: AppButtonRadius.card,
            expand: false,
            loading: _procesando,
            onPressed: _procesando ? null : _tocar,
          ),
      ],
    );
  }
}

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
