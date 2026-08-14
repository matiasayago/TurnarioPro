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

/// Crear Nueva Cita (Profesional) — HU-23, variante general: se abre desde el menú de
/// Configuración (`configuracion_screen.dart`, ítem "Nueva Cita", antes `_irAProximamente`), sin
/// paciente preseleccionado. Wireframe real en `04-diseno/mapa-pantallas.md` §5.7bis, variante
/// **"Crear Nueva Cita"** — la variante contextual "Agendar Cita" (desde una ficha de paciente ya
/// elegida, con un campo "Hora" de texto libre) NO es parte de este alcance.
///
/// Dos diferencias deliberadas respecto de las capturas de referencia de esa variante (decisión
/// explícita de esta ronda, no un olvido):
/// - **Sin campo "Notas"**: `turno` no tiene ninguna columna de texto libre para esto (ver
///   `POST /profesionales/:id/turnos` en `backend/src/routes/profesionales.ts`) y los criterios
///   de aceptación cerrados de HU-23 no la piden — mostrar un campo que no se persiste sería
///   engañoso.
/// - **"Hora" es selección ÚNICA** (chips sobre los slots realmente publicados vía
///   `GET /:id/slots`), no el campo de texto libre "Ej: 10:00, 14:30" de las capturas — "un solo
///   turno por acción" quedó resuelto para v1 (`02-backlog/backlog.md` HU-23) y
///   `POST /:id/turnos` solo acepta un `inicio` singular.
///
/// Contrato consumido (3 endpoints ya existentes, ninguno nuevo):
/// - `GET /profesionales/:id/servicios` — mismo endpoint que ya usa `precios_senas_screen.dart`.
///   A propósito devuelve los servicios del profesional en TODOS sus negocios; acá se filtra
///   client-side por `negocio_id == sesion.negocioId` (el negocio activo, HU-27) para que "Nueva
///   Cita" solo ofrezca servicios del negocio actualmente seleccionado.
/// - `GET /profesionales/:id/clientes` (HU-19) — sin filtrar por negocio a propósito, igual que
///   `gestion_pacientes_screen.dart` (ese endpoint ya mezcla negocios de forma intencional).
/// - `GET /profesionales/:id/slots?servicio_id=...` — mismo patrón de consumo que
///   `horarios_disponibles_screen.dart` (lado Cliente): un mapa con `slots`/`proximo_disponible`.
///   Acá los slots se agrupan por fecha calendario LOCAL para separar la UI en "Fecha" (día,
///   elegido con `MonthCalendarPicker` en un diálogo) + "Hora" (chip de selección única sobre los
///   slots de esa fecha) en vez de una lista plana de fecha+hora combinada.
/// - `POST /profesionales/:id/turnos`, body `{ paciente_id, servicio_id, inicio, cobrar_sena }`.
///   `cobrar_sena` viaja SIEMPRE (requerido, sin default silencioso del cliente): el switch
///   "¿Cobrar seña?" solo se muestra cuando el servicio elegido tiene `requiere_sena: true`; si
///   no, se manda `false` directo sin mostrar ningún control (no tiene sentido preguntar por algo
///   que el servicio no pide). Un `409` (carrera con otra reserva) muestra un mensaje específico
///   y refresca los horarios disponibles en vez de un error genérico.
///
/// Nota de layout: el wireframe (§5.7bis) muestra cada campo como su propia card con una franja
/// de acento lateral — UX/UI dejó ese tratamiento explícitamente sin formalizar como componente
/// por falta de evidencia sobre su regla de color (`sistema-diseno.md` §12.4). Acá se usa en su
/// lugar una única card `surface` agrupando todos los campos, igual que el resto de los
/// formularios de esta app (`editar_perfil_screen.dart`, `ficha_paciente_screen.dart`).
class NuevaCitaScreen extends StatefulWidget {
  const NuevaCitaScreen({super.key});

  @override
  State<NuevaCitaScreen> createState() => _NuevaCitaScreenState();
}

class _NuevaCitaScreenState extends State<NuevaCitaScreen> {
  late Future<void> _futureCarga;

  List<_ServicioOpcion> _servicios = [];
  List<_PacienteOpcion> _pacientes = [];

  _ServicioOpcion? _servicioSeleccionado;
  _PacienteOpcion? _pacienteSeleccionado;

  bool _cargandoSlots = false;
  String? _errorSlots;
  Map<DateTime, List<String>> _slotsPorFecha = {};
  DateTime? _fechaSeleccionada;
  String? _horaSeleccionada; // ISO-8601 completo, tal como lo devuelve GET /slots.

  bool _cobrarSena = true;

  bool _enviando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _futureCarga = _cargarOpciones();
  }

  Future<void> _cargarOpciones() async {
    final sesion = context.read<Sesion>();
    final resultados = await Future.wait([
      sesion.api.getList('/profesionales/${sesion.profesionalId}/servicios'),
      sesion.api.getList('/profesionales/${sesion.profesionalId}/clientes'),
    ]);
    // Filtrado client-side por negocio activo — ver el comentario de clase sobre por qué no se
    // le pide a Backend que cambie el endpoint (precios_senas_screen.dart sí necesita ver todos
    // los negocios a la vez).
    _servicios = resultados[0]
        .map((e) => _ServicioOpcion.fromApi(e as Map<String, dynamic>))
        .where((s) => s.negocioId == sesion.negocioId)
        .toList();
    _pacientes = resultados[1].map((e) => _PacienteOpcion.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _elegirServicio(_ServicioOpcion? servicio) async {
    setState(() {
      _servicioSeleccionado = servicio;
      _cobrarSena = servicio?.requiereSena ?? true;
      _slotsPorFecha = {};
      _fechaSeleccionada = null;
      _horaSeleccionada = null;
      _errorSlots = null;
    });
    if (servicio != null) await _cargarSlots();
  }

  Future<void> _cargarSlots() async {
    final servicio = _servicioSeleccionado;
    if (servicio == null) return;
    setState(() {
      _cargandoSlots = true;
      _errorSlots = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final data = await sesion.api
          .getMap('/profesionales/${sesion.profesionalId}/slots?servicio_id=${servicio.servicioId}');
      final slots = (data['slots'] as List).cast<String>();
      final agrupados = <DateTime, List<String>>{};
      for (final iso in slots) {
        final dia = MonthCalendarPicker.dateOnly(DateTime.parse(iso).toLocal());
        agrupados.putIfAbsent(dia, () => []).add(iso);
      }
      if (!mounted) return;
      setState(() {
        _slotsPorFecha = agrupados;
        _cargandoSlots = false;
        // Si la fecha ya elegida dejó de tener slots (ej. tras refrescar por un 409), se limpia
        // junto con la hora para no dejar una selección fantasma.
        if (_fechaSeleccionada != null && !agrupados.containsKey(_fechaSeleccionada)) {
          _fechaSeleccionada = null;
          _horaSeleccionada = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoSlots = false;
        _errorSlots = 'No se pudieron cargar los horarios disponibles: $e';
      });
    }
  }

  Future<void> _elegirFecha() async {
    if (_slotsPorFecha.isEmpty) return;
    var mesVisible = _fechaSeleccionada ?? _slotsPorFecha.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    final elegida = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              // `SingleChildScrollView` (defensivo, no solo por estética): `Dialog` limita su
              // alto al espacio disponible de la pantalla — en viewports bajos (celular en
              // horizontal, ventana partida) el mes completo + leyenda de `MonthCalendarPicker`
              // puede no entrar; sin scroll, eso overflowea en vez de simplemente scrollear.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: MonthCalendarPicker(
                  month: mesVisible,
                  onMonthChanged: (m) => setDialogState(() => mesVisible = m),
                  selectedDates: _fechaSeleccionada != null ? {_fechaSeleccionada!} : {},
                  onDayTap: (d) => Navigator.of(dialogContext).pop(d),
                  // Marca (🕐) los días que realmente tienen slots para el servicio elegido —
                  // mismo mecanismo visual que ya usa Gestión de Horarios, reutilizado acá con
                  // otro significado (ver doc comment de la clase).
                  datesWithSchedule: _slotsPorFecha.keys.toSet(),
                ),
              ),
            );
          },
        );
      },
    );
    if (elegida == null) return;
    setState(() {
      _fechaSeleccionada = elegida;
      _horaSeleccionada = null;
    });
  }

  Future<void> _crear() async {
    final servicio = _servicioSeleccionado;
    final paciente = _pacienteSeleccionado;
    final inicio = _horaSeleccionada;
    if (servicio == null || paciente == null || inicio == null) return;

    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/profesionales/${sesion.profesionalId}/turnos', {
        'paciente_id': paciente.id,
        'servicio_id': servicio.servicioId,
        'inicio': inicio,
        // El servicio decide si el switch aplica; si no pide seña, se manda `false` directo sin
        // mostrar ningún control (ver comentario de clase).
        'cobrar_sena': servicio.requiereSena ? _cobrarSena : false,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        setState(() {
          _mensaje = 'Ese horario se acaba de ocupar — elegí otro. Actualizamos la lista de horarios disponibles.';
          _mensajeEsError = true;
          _horaSeleccionada = null;
          _enviando = false;
        });
        await _cargarSlots();
        return;
      }
      setState(() {
        _mensaje = 'No se pudo crear la cita: ${e.message}';
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensaje = 'No se pudo crear la cita: $e';
        _mensajeEsError = true;
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _futureCarga,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppModalSheet(
            title: 'Crear Nueva Cita',
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return AppModalSheet(
            title: 'Crear Nueva Cita',
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: Text(
                  'No se pudieron cargar los datos para crear la cita: ${snapshot.error}',
                  style: AppTypography.body(context),
                ),
              ),
            ),
          );
        }
        return _contenido(context);
      },
    );
  }

  Widget _contenido(BuildContext context) {
    final sesion = context.watch<Sesion>();
    // HU-27: sin negocio activo (0 negocios, o 2+ sin elegir todavía) no hay agenda a la que
    // asociar el turno nuevo — mismo criterio que `_SinNegocioView` del Dashboard.
    if (sesion.negocioId == null) {
      return AppModalSheet(
        title: 'Crear Nueva Cita',
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: Text(
              'Elegí un negocio activo antes de crear una cita (ícono "cambiar de vista" del Dashboard).',
              textAlign: TextAlign.center,
              style: AppTypography.body(context),
            ),
          ),
        ),
      );
    }

    final puedeCrear = !_enviando &&
        _servicioSeleccionado != null &&
        _pacienteSeleccionado != null &&
        _horaSeleccionada != null;

    return AppModalSheet(
      title: 'Crear Nueva Cita',
      primaryLabel: 'Crear Cita y Notificar Cliente',
      primaryLoading: _enviando,
      onPrimary: puedeCrear ? _crear : null,
      onSecondary: _enviando ? null : () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Text(
            'Completá estos datos para crear el turno — el cliente recibe una notificación al confirmar.',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: AppSpacing.base),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_servicios.isEmpty)
                  const _AvisoVacio(
                    texto: 'Todavía no tenés servicios asociados a este negocio. Configurá al menos uno '
                        'desde "Configurar Disponibilidad" antes de crear una cita.',
                  )
                else
                  _CampoDropdown<_ServicioOpcion>(
                    label: 'Servicio',
                    requerido: true,
                    valor: _servicioSeleccionado,
                    hint: 'Seleccionar servicio...',
                    items: _servicios,
                    itemLabel: (s) => s.nombre,
                    onChanged: _elegirServicio,
                  ),
                const SizedBox(height: AppSpacing.md),
                if (_pacientes.isEmpty)
                  const _AvisoVacio(
                    texto: 'Todavía no tenés pacientes en tu cartera — se agregan automáticamente al '
                        'confirmar el primer turno de cada uno.',
                  )
                else
                  _CampoDropdown<_PacienteOpcion>(
                    label: 'Paciente',
                    requerido: true,
                    valor: _pacienteSeleccionado,
                    hint: 'Seleccionar paciente...',
                    items: _pacientes,
                    itemLabel: (p) => p.nombre,
                    onChanged: (p) => setState(() => _pacienteSeleccionado = p),
                  ),
                const SizedBox(height: AppSpacing.md),
                _campoFecha(context),
                if (_errorSlots != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _errorSlots!,
                          style: AppTypography.caption(context).copyWith(color: AppColors.of(context).danger.base),
                        ),
                      ),
                      TextButton(onPressed: _cargarSlots, child: const Text('Reintentar')),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _campoHora(context),
                if (_servicioSeleccionado?.requiereSena ?? false) ...[
                  const SizedBox(height: AppSpacing.md),
                  _campoCobrarSena(context),
                ],
              ],
            ),
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.base),
            _FeedbackBanner(mensaje: _mensaje!, esError: _mensajeEsError),
          ],
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }

  Widget _campoFecha(BuildContext context) {
    final colors = AppColors.of(context);
    final habilitado = !_cargandoSlots && _slotsPorFecha.isNotEmpty;
    final texto = _fechaSeleccionada != null
        ? _capitalize(DateFormat('EEEE d MMMM', 'es').format(_fechaSeleccionada!))
        : _servicioSeleccionado == null
            ? 'Elegí primero un servicio'
            : _cargandoSlots
                ? 'Buscando horarios disponibles...'
                : _errorSlots != null
                    ? 'No se pudieron cargar los horarios'
                    : _slotsPorFecha.isEmpty
                        ? 'No hay fechas disponibles próximamente'
                        : 'Seleccionar fecha...';

    return InkWell(
      onTap: habilitado ? _elegirFecha : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Fecha *',
          enabled: habilitado,
          suffixIcon: _cargandoSlots
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          texto,
          style: AppTypography.body(context)
              .copyWith(color: _fechaSeleccionada != null ? colors.textPrimary : colors.textSecondary),
        ),
      ),
    );
  }

  Widget _campoHora(BuildContext context) {
    final formatoHora = DateFormat('HH:mm');
    final fecha = _fechaSeleccionada;
    final horas = fecha != null ? (_slotsPorFecha[fecha] ?? const <String>[]) : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hora *', style: AppTypography.caption(context)),
        const SizedBox(height: AppSpacing.xs),
        if (fecha == null)
          Text('Elegí una fecha para ver los horarios disponibles.', style: AppTypography.caption(context))
        else if (horas.isEmpty)
          Text('No hay horarios disponibles para esta fecha.', style: AppTypography.caption(context))
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final iso in horas)
                _ToggleChip(
                  label: formatoHora.format(DateTime.parse(iso).toLocal()),
                  selected: _horaSeleccionada == iso,
                  onTap: () => setState(() => _horaSeleccionada = iso),
                ),
            ],
          ),
      ],
    );
  }

  Widget _campoCobrarSena(BuildContext context) {
    final servicio = _servicioSeleccionado!;
    final montoTexto = servicio.montoSena != null ? '\$${_formatMonto(servicio.montoSena!)}' : 'sin monto configurado';
    // `SwitchListTile` pinta su fondo/ripple sobre el `Material` ancestro más cercano — sin este
    // envoltorio, el `Container` coloreado de `_sectionCard` (un `DecoratedBox`, no un
    // `Material`) lo taparía (`debugCheckHasMaterial`/aviso "background... may be invisible").
    // `MaterialType.transparency` no agrega ningún color propio, solo habilita el ripple.
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('¿Cobrar seña?', style: AppTypography.body(context)),
        subtitle: Text(
          'Este servicio tiene una seña configurada de $montoTexto. Podés omitirla para esta cita puntual.',
          style: AppTypography.caption(context),
        ),
        value: _cobrarSena,
        onChanged: (v) => setState(() => _cobrarSena = v),
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

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Mismo criterio de formateo que `precios_senas_screen.dart` (duplicado a propósito, ver
  /// convención documentada en `_FiltroChip` de `gestion_pacientes_screen.dart`): sin decimales
  /// sobrantes para los montos típicos de este dominio.
  static String _formatMonto(num valor) =>
      valor == valor.roundToDouble() ? valor.toStringAsFixed(0) : valor.toStringAsFixed(2);
}

/// Dropdown con label + asterisco opcional, estilado por el `inputDecorationTheme` global
/// (`app_theme.dart`) — mismo tratamiento visual que cualquier `TextField` de esta app. `T` debe
/// comparar por identidad (comportamiento por defecto de Dart): [items] siempre proviene de la
/// misma lista que [valor], nunca se reconstruye entre selecciones.
class _CampoDropdown<T> extends StatelessWidget {
  const _CampoDropdown({
    required this.label,
    required this.valor,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.hint,
    this.requerido = false,
  });

  final String label;
  final T? valor;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final bool requerido;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: valor,
      isExpanded: true,
      decoration: InputDecoration(labelText: requerido ? '$label *' : label),
      hint: hint != null ? Text(hint!) : null,
      items: [
        for (final item in items)
          DropdownMenuItem<T>(value: item, child: Text(itemLabel(item), overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Chip de selección única (§7.9) — mismo tratamiento visual que `_ToggleChip` de
/// `gestion_horarios_screen.dart`, duplicado localmente a propósito (cada pantalla de este código
/// ya define sus propios widgets de chip/sección privados en vez de un componente compartido).
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: selected ? null : Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: AppTypography.caption(context).copyWith(
                color: selected ? colors.onPrimary : colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Banner de aviso no bloqueante (ej. "todavía no tenés servicios/pacientes") — variante `warning`
/// de `_FeedbackBanner`, para distinguir un estado vacío esperable de un error real.
class _AvisoVacio extends StatelessWidget {
  const _AvisoVacio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: colors.warning.background, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Text(texto, style: AppTypography.body(context).copyWith(color: colors.warning.base)),
    );
  }
}

/// Mismo patrón de banner de éxito/error que el resto de las pantallas de Configuración
/// (ej. `editar_perfil_screen.dart`, `precios_senas_screen.dart`), duplicado localmente.
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

class _ServicioOpcion {
  const _ServicioOpcion({
    required this.servicioId,
    required this.nombre,
    required this.negocioId,
    required this.requiereSena,
    required this.montoSena,
  });

  final String servicioId;
  final String nombre;
  final String negocioId;
  final bool requiereSena;
  final num? montoSena;

  factory _ServicioOpcion.fromApi(Map<String, dynamic> json) => _ServicioOpcion(
        servicioId: json['servicio_id'] as String,
        nombre: json['nombre'] as String,
        negocioId: json['negocio_id'] as String,
        requiereSena: json['requiere_sena'] as bool? ?? false,
        montoSena: json['monto_sena'] as num?,
      );
}

class _PacienteOpcion {
  const _PacienteOpcion({required this.id, required this.nombre});

  final String id;
  final String nombre;

  factory _PacienteOpcion.fromApi(Map<String, dynamic> json) =>
      _PacienteOpcion(id: json['id'] as String, nombre: json['nombre'] as String);
}
