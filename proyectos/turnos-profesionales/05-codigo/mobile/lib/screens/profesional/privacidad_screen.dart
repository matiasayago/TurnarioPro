import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Privacidad y Seguridad (Configuración > Cuenta > Privacidad y Seguridad,
/// `configuracion_screen.dart`) — HU-32, bloque "Privacidad" únicamente. Contrato:
/// `GET /usuario/privacidad` -> `{ visibilidad_perfil, mostrar_estado_en_linea,
/// compartir_datos_uso }` (defaults de fábrica `publico`/`true`/`true` si la cuenta nunca guardó
/// nada, nunca 404); `PATCH /usuario/privacidad`, mismo body completo (los 3 campos siempre) ->
/// mismo shape.
///
/// **El bloque "Seguridad de la cuenta"** que muestra el wireframe original
/// (`mapa-pantallas.md` §5.13) NO se construye acá — confirmado contra capturas reales que no
/// existe en la app de referencia (§5.13bis) y no tiene backend (`usuario.ts` tampoco lo modela,
/// ver el comentario junto a `usuarioRouter` en ese archivo). Tres controles nada más:
/// visibilidad de perfil (radio de 3 opciones, no un dropdown — corrección confirmada en
/// §5.13bis) + 2 switches, con un único botón "Guardar" para el bloque entero (mismo criterio
/// de "reenviar el formulario completo" que exige el PATCH — no autoguardado campo por campo).
class PrivacidadScreen extends StatefulWidget {
  const PrivacidadScreen({super.key});

  @override
  State<PrivacidadScreen> createState() => _PrivacidadScreenState();
}

class _PrivacidadScreenState extends State<PrivacidadScreen> {
  late Future<void> _futureCarga;

  String _visibilidad = 'publico';
  bool _mostrarEstadoEnLinea = true;
  bool _compartirDatosUso = true;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _futureCarga = _cargar();
  }

  Future<void> _cargar() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api.getMap('/usuario/privacidad');
    _aplicarDatos(data);
  }

  void _aplicarDatos(Map<String, dynamic> data) {
    _visibilidad = data['visibilidad_perfil'] as String;
    _mostrarEstadoEnLinea = data['mostrar_estado_en_linea'] as bool;
    _compartirDatosUso = data['compartir_datos_uso'] as bool;
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final data = await sesion.api.patch('/usuario/privacidad', {
        'visibilidad_perfil': _visibilidad,
        'mostrar_estado_en_linea': _mostrarEstadoEnLinea,
        'compartir_datos_uso': _compartirDatosUso,
      });
      if (!mounted) return;
      setState(() {
        _aplicarDatos(data);
        _guardando = false;
        _mensaje = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferencias guardadas.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar: $e';
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
              emoji: '🔒',
              title: 'Privacidad y Seguridad',
              showBackButton: true,
            ),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: const AppHeader(
              variant: AppHeaderVariant.surface,
              emoji: '🔒',
              title: 'Privacidad y Seguridad',
              showBackButton: true,
            ),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  'No se pudieron cargar tus preferencias: ${snapshot.error}',
                  style: AppTypography.body(context),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: const AppHeader(
            variant: AppHeaderVariant.surface,
            emoji: '🔒',
            title: 'Privacidad y Seguridad',
            showBackButton: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  context,
                  title: 'Privacidad',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Visibilidad de mi perfil', style: AppTypography.body(context)),
                      // `RadioListTile.groupValue`/`.onChanged` están deprecados desde Flutter
                      // 3.32 a favor de un `RadioGroup<T>` ancestro compartido — API nueva, no
                      // una preferencia de estilo (`flutter analyze` marca el patrón viejo como
                      // `deprecated_member_use`).
                      RadioGroup<String>(
                        groupValue: _visibilidad,
                        onChanged: (v) => setState(() => _visibilidad = v ?? _visibilidad),
                        child: Column(
                          children: [
                            _radioVisibilidad(
                              value: 'publico',
                              titulo: 'Público',
                              subtitulo: 'Cualquier persona puede ver tu perfil.',
                            ),
                            _radioVisibilidad(
                              value: 'solo_contactos',
                              titulo: 'Solo contactos',
                              subtitulo: 'Solo tus clientes con turnos pueden verlo.',
                            ),
                            _radioVisibilidad(
                              value: 'privado',
                              titulo: 'Privado',
                              subtitulo: 'Tu perfil no es visible para otras personas.',
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: AppSpacing.lg),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Mostrar mi estado en línea', style: AppTypography.body(context)),
                        value: _mostrarEstadoEnLinea,
                        onChanged: (v) => setState(() => _mostrarEstadoEnLinea = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Compartir datos de uso con la plataforma', style: AppTypography.body(context)),
                        subtitle: Text(
                          'Ayuda a mejorar la app compartiendo datos de uso anónimos.',
                          style: AppTypography.caption(context),
                        ),
                        value: _compartirDatosUso,
                        onChanged: (v) => setState(() => _compartirDatosUso = v),
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
      },
    );
  }

  Widget _radioVisibilidad({required String value, required String titulo, required String subtitulo}) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: Text(titulo),
      subtitle: Text(subtitulo),
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
