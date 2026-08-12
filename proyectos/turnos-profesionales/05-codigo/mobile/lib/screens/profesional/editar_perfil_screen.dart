import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _futureCarga = _cargar();
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
