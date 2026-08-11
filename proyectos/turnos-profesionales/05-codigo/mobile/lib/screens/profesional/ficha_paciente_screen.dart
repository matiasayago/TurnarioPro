import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Modo de apertura de [FichaPacienteScreen] — "Ver" y "Editar" son la MISMA pantalla (mismo
/// `State`, mismos datos ya cargados), no dos rutas separadas: `Gestión de Pacientes` navega acá
/// con el modo inicial que corresponda ("Ver"/"Editar" de la fila) y el propio footer permite
/// alternar entre ambos sin volver a pedir el GET.
enum FichaPacienteModo { ver, editar }

/// Ficha de Paciente — HU-20, Variante B aprobada por el CEO (`mapa-pantallas.md` §5.9bis,
/// 2026-08-09; es la única variante a implementar, la Variante A no se construye).
///
/// Decisiones de esta pantalla que van más allá de lo literal del wireframe:
/// - **Nombre/Email/Teléfono se muestran pero NO son editables**, ni siquiera en modo "editar":
///   el PATCH real (`profesionales.ts`) solo acepta los 9 campos de la ficha clínica
///   (fecha_nacimiento, genero, direccion, contacto_emergencia_*, alergias,
///   notas_medicas_generales, activo) — esos 3 datos viven en `usuario`, no en `paciente`, y hoy
///   no hay endpoint de "editar mi perfil" (queda en Configuración → Editar Perfil →
///   "Próximamente"). Mostrarlos como `TextField` editable sin que el cambio se guarde sería
///   peor UX que mostrarlos de solo lectura con una nota — mismo criterio que ya usa
///   `gestion_horarios_screen.dart` para simplificar el selector de servicio.
/// - **"Fecha de nacimiento" usa `MonthCalendarPicker`** (en un diálogo compacto) en vez del
///   placeholder de texto libre "YYYY-MM-DD" que mostraban las capturas reales — mejora
///   consciente pedida explícitamente para esta ronda. `MonthCalendarPicker` nació para elegir
///   disponibilidad (siempre fechas futuras) y por defecto no deja tocar fechas pasadas — se le
///   agregó `allowPastSelection` (ver ese widget) para poder reusarlo acá con fechas de
///   nacimiento reales, en vez de construir un date picker nuevo desde cero.
/// - **"Género" y "Relación" (contacto de emergencia) son campos de texto libre, no dropdowns**:
///   el backend no tiene enum/CHECK para ninguno de los dos a propósito (son contenido de UI, no
///   regla de negocio, ver el comentario de `fichaPacienteSchema` en `profesionales.ts`) y no hay
///   un catálogo de opciones publicado — mismo criterio de simplificación que el selector de
///   servicio de texto libre en Gestión de Horarios.
/// - **"Paciente activo" se agrega como un switch propio**, fuera de la sección "Salud" (aplica a
///   cualquier rubro, no solo salud) y sin ubicación explícita en el brief de esta ronda: el PATCH
///   exige mandar `activo` siempre (upsert de fila completa) y HU-19 pide que sea "un toggle en
///   la ficha" — la Variante B confirmada contra capturas no muestra dónde vive ese control, así
///   que se ubica acá de forma explícita y comentada.
class FichaPacienteScreen extends StatefulWidget {
  const FichaPacienteScreen({
    super.key,
    required this.pacienteId,
    required this.pacienteNombre,
    this.modoInicial = FichaPacienteModo.ver,
  });

  final String pacienteId;
  final String pacienteNombre;
  final FichaPacienteModo modoInicial;

  @override
  State<FichaPacienteScreen> createState() => _FichaPacienteScreenState();
}

class _FichaPacienteScreenState extends State<FichaPacienteScreen> {
  late FichaPacienteModo _modo;
  late Future<void> _futureCarga;

  String _nombre = '';
  String _email = '';
  String? _telefono;
  DateTime? _fechaNacimiento;
  final _generoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _contactoNombreCtrl = TextEditingController();
  final _contactoTelefonoCtrl = TextEditingController();
  final _contactoRelacionCtrl = TextEditingController();
  final _alergiasCtrl = TextEditingController();
  final _notasMedicasCtrl = TextEditingController();
  String? _alergiasOriginal;
  String? _notasMedicasOriginal;
  bool _activo = true;
  bool _esRubroSalud = false;
  Map<String, dynamic>? _ultimoDataCargado;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _modo = widget.modoInicial;
    _nombre = widget.pacienteNombre;
    _futureCarga = _cargar();
  }

  @override
  void dispose() {
    _generoCtrl.dispose();
    _direccionCtrl.dispose();
    _contactoNombreCtrl.dispose();
    _contactoTelefonoCtrl.dispose();
    _contactoRelacionCtrl.dispose();
    _alergiasCtrl.dispose();
    _notasMedicasCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final sesion = context.read<Sesion>();
    final data = await sesion.api
        .getMap('/profesionales/${sesion.profesionalId}/pacientes/${widget.pacienteId}');
    final esRubroSalud = await _detectarRubroSalud(sesion);
    _aplicarDatos(data, esRubroSalud);
  }

  // `es_rubro_salud` (HU-20/D11): viene de `GET /negocios` (público, sin auth), buscando el
  // negocio cuyo `id` coincide con el `negocio_id` de la sesión activa. Si esta llamada
  // accesoria falla, se oculta la sección "Salud" por prudencia en vez de romper toda la ficha
  // por un dato que no es el propósito principal de la pantalla.
  Future<bool> _detectarRubroSalud(Sesion sesion) async {
    try {
      final negocios = await sesion.api.getList('/negocios');
      for (final n in negocios) {
        final negocio = n as Map<String, dynamic>;
        if (negocio['id'] == sesion.negocioId) return negocio['es_rubro_salud'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _aplicarDatos(Map<String, dynamic> data, bool esRubroSalud) {
    _ultimoDataCargado = data;
    _nombre = data['nombre'] as String;
    _email = data['email'] as String;
    _telefono = data['telefono'] as String?;
    final fechaNacimientoRaw = data['fecha_nacimiento'] as String?;
    _fechaNacimiento = fechaNacimientoRaw != null ? DateTime.parse(fechaNacimientoRaw) : null;
    _generoCtrl.text = (data['genero'] as String?) ?? '';
    _direccionCtrl.text = (data['direccion'] as String?) ?? '';
    _contactoNombreCtrl.text = (data['contacto_emergencia_nombre'] as String?) ?? '';
    _contactoTelefonoCtrl.text = (data['contacto_emergencia_telefono'] as String?) ?? '';
    _contactoRelacionCtrl.text = (data['contacto_emergencia_relacion'] as String?) ?? '';
    _alergiasOriginal = data['alergias'] as String?;
    _notasMedicasOriginal = data['notas_medicas_generales'] as String?;
    _alergiasCtrl.text = _alergiasOriginal ?? '';
    _notasMedicasCtrl.text = _notasMedicasOriginal ?? '';
    _activo = (data['activo'] as bool?) ?? true;
    _esRubroSalud = esRubroSalud;
  }

  String? _vacioANull(String texto) => texto.trim().isEmpty ? null : texto.trim();

  String _valorOTexto(String texto) => texto.trim().isEmpty ? 'Sin registrar' : texto.trim();

  Map<String, dynamic> _bodyActualizar() {
    return {
      'fecha_nacimiento': _fechaNacimiento != null ? DateFormat('yyyy-MM-dd').format(_fechaNacimiento!) : null,
      'genero': _vacioANull(_generoCtrl.text),
      'direccion': _vacioANull(_direccionCtrl.text),
      'contacto_emergencia_nombre': _vacioANull(_contactoNombreCtrl.text),
      'contacto_emergencia_telefono': _vacioANull(_contactoTelefonoCtrl.text),
      'contacto_emergencia_relacion': _vacioANull(_contactoRelacionCtrl.text),
      // Si la sección Salud está oculta (negocio no-salud) se reenvía el valor original sin
      // tocar — el PATCH es upsert de fila completa (RN de arriba), nunca se manda `null` acá
      // solo porque la UI no lo muestra.
      'alergias': _esRubroSalud ? _vacioANull(_alergiasCtrl.text) : _alergiasOriginal,
      'notas_medicas_generales': _esRubroSalud ? _vacioANull(_notasMedicasCtrl.text) : _notasMedicasOriginal,
      'activo': _activo,
    };
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final data = await sesion.api.patch(
        '/profesionales/${sesion.profesionalId}/pacientes/${widget.pacienteId}',
        _bodyActualizar(),
      );
      if (!mounted) return;
      setState(() {
        _aplicarDatos(data, _esRubroSalud);
        _modo = FichaPacienteModo.ver;
        _guardando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paciente actualizado.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo actualizar: $e';
        _mensajeEsError = true;
      });
    }
  }

  void _cancelarEdicion() {
    setState(() {
      if (_ultimoDataCargado != null) _aplicarDatos(_ultimoDataCargado!, _esRubroSalud);
      _modo = FichaPacienteModo.ver;
      _mensaje = null;
    });
  }

  Future<void> _elegirFechaNacimiento() async {
    var mesVisible = _fechaNacimiento ?? DateTime(DateTime.now().year - 30, DateTime.now().month, 1);
    final elegida = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: MonthCalendarPicker(
                  month: mesVisible,
                  onMonthChanged: (m) => setDialogState(() => mesVisible = m),
                  selectedDates: _fechaNacimiento != null ? {MonthCalendarPicker.dateOnly(_fechaNacimiento!)} : {},
                  onDayTap: (d) => Navigator.of(dialogContext).pop(d),
                  allowPastSelection: true,
                  showLegend: false,
                ),
              ),
            );
          },
        );
      },
    );
    if (elegida != null) setState(() => _fechaNacimiento = elegida);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _futureCarga,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppHeader(variant: AppHeaderVariant.surface, title: widget.pacienteNombre, showBackButton: true),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppHeader(variant: AppHeaderVariant.surface, title: widget.pacienteNombre, showBackButton: true),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text('No se pudo cargar la ficha: ${snapshot.error}', style: AppTypography.body(context)),
              ),
            ),
          );
        }

        final esVer = _modo == FichaPacienteModo.ver;
        return Scaffold(
          appBar: AppHeader(
            variant: AppHeaderVariant.surface,
            emoji: esVer ? '👁️' : '✏️',
            title: esVer ? _nombre : 'Editar Paciente',
            showBackButton: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: esVer ? _vistaVer(context) : _vistaEditar(context),
          ),
          bottomNavigationBar: esVer ? _footerVer(context) : _footerEditar(context),
        );
      },
    );
  }

  Widget _vistaVer(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          context,
          title: 'Datos personales',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Nombre', _nombre),
              _infoRow(context, 'Email', _email),
              _infoRow(context, 'Teléfono', _telefono ?? 'Sin registrar'),
              _infoRow(
                context,
                'Fecha de nacimiento',
                _fechaNacimiento != null ? DateFormat('dd/MM/yyyy').format(_fechaNacimiento!) : 'Sin registrar',
              ),
              _infoRow(context, 'Género', _valorOTexto(_generoCtrl.text)),
              _infoRow(context, 'Dirección', _valorOTexto(_direccionCtrl.text), esUltimo: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionCard(
          context,
          title: 'Contacto de emergencia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Nombre', _valorOTexto(_contactoNombreCtrl.text)),
              _infoRow(context, 'Teléfono', _valorOTexto(_contactoTelefonoCtrl.text)),
              _infoRow(context, 'Relación', _valorOTexto(_contactoRelacionCtrl.text), esUltimo: true),
            ],
          ),
        ),
        if (_esRubroSalud) ...[
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            title: '✱ Salud',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context, 'Alergias', _valorOTexto(_alergiasCtrl.text)),
                _infoRow(context, 'Notas médicas generales', _valorOTexto(_notasMedicasCtrl.text), esUltimo: true),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _vistaEditar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          context,
          title: 'Datos personales',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _campoSoloLectura(context, 'Nombre', _nombre),
              const SizedBox(height: AppSpacing.md),
              _campoSoloLectura(context, 'Email', _email),
              const SizedBox(height: AppSpacing.md),
              _campoSoloLectura(context, 'Teléfono', _telefono ?? 'Sin registrar'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Nombre, email y teléfono se editan desde tu perfil (todavía no disponible).',
                style: AppTypography.caption(context),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _campoFechaNacimiento(context)),
                  const SizedBox(width: AppSpacing.base),
                  Expanded(
                    child: TextField(
                      controller: _generoCtrl,
                      decoration: const InputDecoration(labelText: 'Género'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _direccionCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionCard(
          context,
          title: 'Contacto de emergencia',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _contactoNombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del contacto'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _contactoTelefonoCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono del contacto'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _contactoRelacionCtrl, decoration: const InputDecoration(labelText: 'Relación')),
            ],
          ),
        ),
        if (_esRubroSalud) ...[
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            title: '✱ Salud',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _alergiasCtrl,
                  decoration: const InputDecoration(labelText: 'Alergias'),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _notasMedicasCtrl,
                  decoration: const InputDecoration(labelText: 'Notas médicas generales'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _sectionCard(
          context,
          title: 'Estado del paciente',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Paciente activo', style: AppTypography.body(context)),
            subtitle: Text(
              'Se refleja en Gestión de Pacientes y en los filtros Activos/Inactivos.',
              style: AppTypography.caption(context),
            ),
            value: _activo,
            onChanged: (v) => setState(() => _activo = v),
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

  Widget _campoFechaNacimiento(BuildContext context) {
    final colors = AppColors.of(context);
    final texto = _fechaNacimiento != null ? DateFormat('dd/MM/yyyy').format(_fechaNacimiento!) : 'Seleccionar';
    return InkWell(
      onTap: _elegirFechaNacimiento,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Fecha de nacimiento',
          suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(texto, style: AppTypography.body(context).copyWith(color: colors.textPrimary)),
      ),
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

  Widget _footerVer(BuildContext context) {
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
                  label: 'Cerrar',
                  radiusVariant: AppButtonRadius.card,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PrimaryButton(
                  label: 'Editar Paciente',
                  radiusVariant: AppButtonRadius.card,
                  onPressed: () => setState(() => _modo = FichaPacienteModo.editar),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerEditar(BuildContext context) {
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
                  onPressed: _guardando ? null : _cancelarEdicion,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PrimaryButton(
                  label: 'Actualizar Paciente',
                  radiusVariant: AppButtonRadius.card,
                  loading: _guardando,
                  onPressed: _guardando ? null : _guardar,
                ),
              ),
            ],
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
