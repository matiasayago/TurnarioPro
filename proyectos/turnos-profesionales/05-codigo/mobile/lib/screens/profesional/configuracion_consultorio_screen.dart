import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Datos del Negocio / Configuración de Consultorio — HU-31. Contrato: `GET /negocios/:id`
/// (público, sin auth) -> `{ id, nombre, rubro, ubicacion, es_rubro_salud }`; `PATCH /negocios/:id`
/// (`requireAuth('administrador')`), body `{ nombre, rubro, ubicacion }` -> mismo shape. Son los
/// ÚNICOS 3 campos editables hoy — `es_rubro_salud` queda deliberadamente fuera del PATCH del lado
/// del backend (ver el comentario junto a ese endpoint en `negocios.ts`), se sigue mostrando de
/// solo lectura en los dos modos de abajo.
///
/// Misma pantalla para dos roles — mismo criterio que `FichaPacienteScreen` ("ver"/"editar" son el
/// mismo `State`, no dos rutas separadas): acá el modo lo decide el ROL de la sesión activa, no un
/// parámetro de navegación:
/// - **`Rol.profesional`** (alcanzable desde `ProfesionalShell` > Configuración > "Configuración
///   de Consultorio"): DE SOLO LECTURA — a propósito, no un recorte de alcance por tiempo. Un
///   token de rol `profesional` recibe 403 SIEMPRE contra `PATCH /negocios/:id` (verificado contra
///   la base real) — construir un formulario editable que termina en 403 en el 100% de los casos
///   sería peor UX que no ofrecerlo.
/// - **`Rol.administrador`** (alcanzable desde `AdministradorShell` > "Datos del Negocio" — épica
///   E15 "Modo Administrador v1", `02-backlog/backlog.md`): EDITABLE contra el mismo PATCH. Es la
///   UI que la versión anterior de este comentario dejaba pendiente ("cuando exista [un shell de
///   Administrador], ESA es la UI correcta para agregar el formulario editable reusando
///   PATCH /negocios/:id tal cual") — no hace falta ningún cambio de backend para habilitarla.
class ConfiguracionConsultorioScreen extends StatefulWidget {
  const ConfiguracionConsultorioScreen({super.key});

  @override
  State<ConfiguracionConsultorioScreen> createState() => _ConfiguracionConsultorioScreenState();
}

class _ConfiguracionConsultorioScreenState extends State<ConfiguracionConsultorioScreen> {
  late Future<void> _futureCarga;

  final _nombreCtrl = TextEditingController();
  final _rubroCtrl = TextEditingController();
  final _ubicacionCtrl = TextEditingController();
  bool _esRubroSalud = false;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    final negocioId = sesion.negocioId;
    _futureCarga = negocioId == null
        ? Future.error(Exception('No se pudo determinar tu consultorio (falta negocio_id en la sesión).'))
        : _cargar(sesion, negocioId);
  }

  Future<void> _cargar(Sesion sesion, String negocioId) async {
    final data = await sesion.api.getMap('/negocios/$negocioId');
    _aplicarDatos(data);
  }

  void _aplicarDatos(Map<String, dynamic> data) {
    _nombreCtrl.text = data['nombre'] as String;
    _rubroCtrl.text = (data['rubro'] as String?) ?? '';
    _ubicacionCtrl.text = (data['ubicacion'] as String?) ?? '';
    _esRubroSalud = data['es_rubro_salud'] == true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rubroCtrl.dispose();
    _ubicacionCtrl.dispose();
    super.dispose();
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
      final data = await sesion.api.patch('/negocios/${sesion.negocioId}', {
        'nombre': nombre,
        'rubro': _vacioANull(_rubroCtrl.text),
        'ubicacion': _vacioANull(_ubicacionCtrl.text),
      });
      if (!mounted) return;
      setState(() {
        _aplicarDatos(data);
        _guardando = false;
        _mensaje = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datos del negocio actualizados.')));
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
    final esAdministrador = context.watch<Sesion>().rol == Rol.administrador;
    return Scaffold(
      appBar: const AppHeader(
        variant: AppHeaderVariant.surface,
        emoji: '🏬',
        title: 'Configuración de Consultorio',
        showBackButton: true,
      ),
      body: FutureBuilder<void>(
        future: _futureCarga,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text('No se pudo cargar tu consultorio: ${snapshot.error}', style: AppTypography.body(context)),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: esAdministrador ? _vistaEditar(context) : _vistaVer(context),
          );
        },
      ),
      bottomNavigationBar: esAdministrador ? _footer(context) : null,
    );
  }

  Widget _vistaVer(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          context,
          title: 'Datos del consultorio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Nombre', _nombreCtrl.text),
              _infoRow(context, 'Rubro', _rubroCtrl.text.isEmpty ? 'Sin especificar' : _rubroCtrl.text),
              _infoRow(context, 'Ubicación', _ubicacionCtrl.text.isEmpty ? 'Sin especificar' : _ubicacionCtrl.text),
              _infoRow(context, 'Rubro de salud', _esRubroSalud ? 'Sí' : 'No', esUltimo: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: colors.neutral.background,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.neutral.base),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Estos datos son de solo lectura para tu rol. Los administra el dueño del negocio desde '
                  'su panel de Administrador.',
                  style: AppTypography.caption(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vistaEditar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          context,
          title: 'Datos del negocio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _rubroCtrl, decoration: const InputDecoration(labelText: 'Rubro')),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _ubicacionCtrl, decoration: const InputDecoration(labelText: 'Ubicación')),
              const SizedBox(height: AppSpacing.md),
              _campoSoloLectura(context, 'Rubro de salud', _esRubroSalud ? 'Sí' : 'No'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'El rubro de salud no se puede modificar desde esta pantalla.',
                style: AppTypography.caption(context),
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
    );
  }

  Widget _campoSoloLectura(BuildContext context, String label, String value) {
    final colors = AppColors.of(context);
    return InputDecorator(
      decoration: InputDecoration(labelText: label, enabled: false),
      child: Text(value, style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {bool esUltimo = false}) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: esUltimo ? 0 : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption(context)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
        ],
      ),
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
