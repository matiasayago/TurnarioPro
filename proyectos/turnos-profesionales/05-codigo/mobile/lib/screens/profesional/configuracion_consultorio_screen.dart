import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Datos del Negocio / Configuración de Consultorio — HU-31. Contrato: `GET /negocios/:id`
/// (público, sin auth) -> `{ id, nombre, rubro, ubicacion, es_rubro_salud, horario_atencion,
/// direccion, telefono, logo_url }`; `PATCH /negocios/:id` (`requireAuth('administrador')`), body
/// `{ nombre, rubro, ubicacion, horario_atencion, direccion, telefono, logo_url }` -> mismo shape.
/// `nombre` es requerido; el resto viajan como `string | null` — SIEMPRE los 7 juntos (no es un
/// patch parcial: no hay ningún `SET` condicional del lado del backend) y hay que mandar `null`
/// explícito para vaciar un campo ya cargado, nunca omitirlo (ver `_vacioANull`, reusado tal cual
/// para los 4 campos nuevos). Son los ÚNICOS 7 campos editables hoy — `es_rubro_salud` queda
/// deliberadamente fuera del PATCH del lado del backend (ver el comentario junto a ese endpoint en
/// `negocios.ts`), se sigue mostrando de solo lectura en los dos modos de abajo.
///
/// `direccion` (2026-08-17) es un campo NUEVO y DISTINTO de `ubicacion` (que no cambió):
/// `ubicacion` es una referencia corta de zona/ciudad (la que ya arma el subtítulo de cada card en
/// "Buscar Negocios", HU-00b); `direccion` es el domicilio completo (calle, altura, piso), pensado
/// para quien ya eligió este negocio puntual — ver el razonamiento completo de DBA en
/// `03-arquitectura/modelo-datos.md` §2undecies. `logo_url` es la URL de una imagen YA alojada en
/// otro lado (este backend no tiene upload de archivo real) — el servidor valida que sea una URL
/// con formato válido (400 si no), pero nunca que apunte efectivamente a una imagen; por eso la
/// vista previa de abajo (`_logoPreview`) usa `Image.network` con `errorBuilder` de fallback en
/// vez de asumir que siempre va a cargar.
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
  final _ubicacionCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _horarioAtencionCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  bool _esRubroSalud = false;

  // A diferencia del resto de los campos de esta pantalla, "Rubro" ya no es un `TextField` de
  // texto libre en `_vistaEditar` (ver [CampoRubro], `widgets/campo_rubro.dart`) — el valor final
  // a mandar al backend lo entrega directo su `onChanged`, con el mismo criterio "vacío es null"
  // que [_vacioANull] aplica al resto de los campos opcionales de acá. Se sigue usando también en
  // `_vistaVer` (solo lectura), que no cambia.
  String? _rubro;

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
    _rubro = data['rubro'] as String?;
    _ubicacionCtrl.text = (data['ubicacion'] as String?) ?? '';
    _direccionCtrl.text = (data['direccion'] as String?) ?? '';
    _telefonoCtrl.text = (data['telefono'] as String?) ?? '';
    _horarioAtencionCtrl.text = (data['horario_atencion'] as String?) ?? '';
    _logoUrlCtrl.text = (data['logo_url'] as String?) ?? '';
    _esRubroSalud = data['es_rubro_salud'] == true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ubicacionCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    _horarioAtencionCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  String? _vacioANull(String texto) => texto.trim().isEmpty ? null : texto.trim();

  /// Feedback client-side antes de "Guardar" — el backend YA valida formato de URL server-side
  /// (`z.string().url()`, ver el comentario de `actualizarNegocioSchema` en `negocios.ts`) y
  /// devuelve 400 si no es válida, pero repetir el chequeo acá evita el viaje de ida y vuelta
  /// completo solo para enterarse de un typo. Campo opcional — vacío es válido (se manda `null`,
  /// ver `_vacioANull`). No valida que la URL sea efectivamente una imagen (el backend tampoco lo
  /// hace, ver doc comment de la clase) — solo la forma.
  String? _errorLogoUrl() {
    final valor = _logoUrlCtrl.text.trim();
    if (valor.isEmpty) return null;
    final uri = Uri.tryParse(valor);
    final esUrlValida = uri != null && uri.isAbsolute && (uri.scheme == 'http' || uri.scheme == 'https');
    return esUrlValida ? null : 'La URL del logo no es válida. Usá una dirección completa (ej. https://...).';
  }

  Future<void> _guardar() async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() {
        _mensaje = 'El nombre no puede estar vacío.';
        _mensajeEsError = true;
      });
      return;
    }
    final errorLogoUrl = _errorLogoUrl();
    if (errorLogoUrl != null) {
      setState(() {
        _mensaje = errorLogoUrl;
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
        'rubro': _rubro,
        'ubicacion': _vacioANull(_ubicacionCtrl.text),
        'horario_atencion': _vacioANull(_horarioAtencionCtrl.text),
        'direccion': _vacioANull(_direccionCtrl.text),
        'telefono': _vacioANull(_telefonoCtrl.text),
        'logo_url': _vacioANull(_logoUrlCtrl.text),
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
        Center(child: _logoPreview(context, _logoUrlCtrl.text)),
        const SizedBox(height: AppSpacing.lg),
        _sectionCard(
          context,
          title: 'Datos del consultorio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Nombre', _nombreCtrl.text),
              _infoRow(context, 'Rubro', (_rubro == null || _rubro!.isEmpty) ? 'Sin especificar' : _rubro!),
              _infoRow(context, 'Ubicación', _ubicacionCtrl.text.isEmpty ? 'Sin especificar' : _ubicacionCtrl.text),
              _infoRow(context, 'Dirección', _direccionCtrl.text.isEmpty ? 'Sin especificar' : _direccionCtrl.text),
              _infoRow(context, 'Teléfono', _telefonoCtrl.text.isEmpty ? 'Sin especificar' : _telefonoCtrl.text),
              _infoRow(
                context,
                'Horario de atención',
                _horarioAtencionCtrl.text.isEmpty ? 'Sin especificar' : _horarioAtencionCtrl.text,
              ),
              _infoRow(context, 'Logo (URL)', _logoUrlCtrl.text.isEmpty ? 'Sin especificar' : _logoUrlCtrl.text),
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
          title: 'Logo del negocio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vista previa reactiva: `AnimatedBuilder` escucha `_logoUrlCtrl` directo
              // (`TextEditingController` ya es un `Listenable`/`ValueNotifier`, no hace falta
              // envolverlo en un `ValueListenableBuilder` aparte) para actualizarse mientras el
              // administrador tipea, sin esperar a "Guardar".
              Center(
                child: AnimatedBuilder(
                  animation: _logoUrlCtrl,
                  builder: (context, _) => _logoPreview(context, _logoUrlCtrl.text),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _logoUrlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL del logo', hintText: 'https://...'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pegá la URL de una imagen ya publicada en otro sitio (ej. Google Drive, Imgur) — '
                'todavía no se puede subir un archivo directo desde la app.',
                style: AppTypography.caption(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _sectionCard(
          context,
          title: 'Datos del negocio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre *')),
              const SizedBox(height: AppSpacing.md),
              CampoRubro(valorInicial: _rubro, onChanged: (valor) => _rubro = valor),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _ubicacionCtrl, decoration: const InputDecoration(labelText: 'Ubicación')),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: _direccionCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'La ubicación es una referencia corta (zona o ciudad) que ven los clientes al buscar '
                'negocios; la dirección es el domicilio completo para quien ya eligió el tuyo.',
                style: AppTypography.caption(context),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: AppSpacing.md),
              // Texto libre potencialmente largo (ej. "Lunes a Viernes 9 a 18hs, Sábados 9 a
              // 13hs") — multilínea en vez de un TextField de una sola línea, a diferencia del
              // resto de los campos de esta card.
              TextField(
                controller: _horarioAtencionCtrl,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Horario de atención',
                  hintText: 'Ej.: Lunes a Viernes 9 a 18hs, Sábados 9 a 13hs',
                  alignLabelWithHint: true,
                ),
              ),
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

  /// Vista previa del logo — recuadro cuadrado con radio de card, misma "forma de contenedor" que
  /// el resto de esta app (`_sectionCard`/`StatCard`, `radius.card` + `AppRadius.cardShadow` no
  /// aplica acá para no competir visualmente con la imagen). Sin URL cargada todavía: ícono
  /// placeholder neutral. Con URL: `Image.network` — el backend solo valida FORMATO de URL, no que
  /// sea efectivamente una imagen (ver doc comment de la clase), así que `errorBuilder` es
  /// necesario, no defensivo de más, para no romper el layout con la imagen "rota" nativa del
  /// navegador/framework ante una URL que no carga o no es una imagen real.
  Widget _logoPreview(BuildContext context, String url) {
    final colors = AppColors.of(context);
    final valor = url.trim();
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.neutral.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: valor.isEmpty
          ? Icon(Icons.storefront_outlined, color: colors.neutral.base, size: 32)
          : Image.network(
              valor,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.broken_image_outlined, color: colors.neutral.base, size: 32),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colors.neutral.base),
                  ),
                );
              },
            ),
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
