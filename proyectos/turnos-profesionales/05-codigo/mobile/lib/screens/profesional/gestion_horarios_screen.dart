import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';

/// Alcance preestablecido de "Replicar en semanas / meses" (§5.6bis: 4 chips, no dos steppers).
enum _AlcanceReplica { semanas4, semanas8, semanas12, meses6 }

String _alcanceLabel(_AlcanceReplica a) => switch (a) {
      _AlcanceReplica.semanas4 => '4 sem.',
      _AlcanceReplica.semanas8 => '8 sem.',
      _AlcanceReplica.semanas12 => '12 sem.',
      _AlcanceReplica.meses6 => '~6 meses',
    };

int _diasDelAlcance(_AlcanceReplica a) => switch (a) {
      _AlcanceReplica.semanas4 => 7 * 4,
      _AlcanceReplica.semanas8 => 7 * 8,
      _AlcanceReplica.semanas12 => 7 * 12,
      _AlcanceReplica.meses6 => 7 * 26, // ~6 meses, ver §5.6bis ("~6 meses" — aproximado)
    };

// Chips de días de la semana en el mismo orden domingo-primero que MonthCalendarPicker.
const List<String> _diasChipLabels = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

/// Gestión de Horarios (Profesional) — HU-05 + HU-16 + HU-18, reemplaza a
/// `definir_disponibilidad_screen.dart`. Versión COMPACTA confirmada por el CEO (2026-08-09),
/// wireframe corregido completo en `mapa-pantallas.md` §5.4bis: una sola página con scroll,
/// footer fijo "Restablecer" / "Guardar N Fechas".
///
/// Nota de alcance sobre el backend real (ver `routes/profesionales.ts` y
/// `migrations/001_init.sql`): el modelo de datos de disponibilidad es **recurrente por día de
/// la semana** (`dia_semana` 0–6), no por fecha puntual, y no existe endpoint para "citas
/// máximas por día", "anticipación de reservas" ni "tiempo de descanso". Esta pantalla:
/// - Deja seleccionar fechas puntuales en el calendario (fiel al wireframe) y, al guardar,
///   traduce cada fecha a su día de la semana (deduplicando) para llamar al endpoint real
///   `POST /profesionales/:id/disponibilidad` — ver [_guardar].
/// - También guarda "Duración de Citas" contra `PATCH /profesionales/:id/configuracion`
///   (endpoint real, D10).
/// - Mantiene "Citas Máximas por Día", "Anticipación de Reservas", "Tiempo de Descanso" y
///   "Replicar en semanas/meses" totalmente interactivos (estado local), pero SIN backend propio
///   todavía — no se inventa una llamada a una API que Backend no publicó (ver la tensión ya
///   documentada en `mapa-pantallas.md` §6 y `02-backlog/backlog.md` HU-16 pregunta abierta #1).
class GestionHorariosScreen extends StatefulWidget {
  const GestionHorariosScreen({super.key});

  @override
  State<GestionHorariosScreen> createState() => _GestionHorariosScreenState();
}

class _GestionHorariosScreenState extends State<GestionHorariosScreen> {
  // Selector de servicio real (fast-follow 2026-08-19: el CEO probó la app como Profesional y
  // encontró que este campo pedía pegar el UUID a mano). Reemplaza el `TextField` de texto libre
  // que había acá — se resuelve contra `GET /profesionales/:id/servicios` (servicios que el
  // profesional YA asoció a su agenda; mismo contrato que ya consume `precios_senas_screen.dart`)
  // en [_cargarServicios], con 3 casos según cuántos devuelva (ver [_servicioSelector]):
  // - 0: nada para elegir — el guardado queda deshabilitado y se explica que primero hay que
  //   agregar un servicio desde "Editar Perfil" > "Servicios que brindo" (mismo fast-follow, ver
  //   `editar_perfil_screen.dart`).
  // - 1: se autoselecciona, sin mostrar ningún control (cero fricción).
  // - 2+: chips de selección (mismo `_ToggleChip` que "Replicar en semanas/meses" más abajo).
  List<_ServicioProfesional> _servicios = [];
  bool _cargandoServicios = true;
  String? _errorServicios;
  String? _servicioIdSeleccionado;

  DateTime _mesVisible = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<DateTime> _fechasSeleccionadas = {};

  // Fechas que esta pantalla sabe, en esta sesión, que ya se guardaron (no hay GET de
  // disponibilidad en el backend todavía para saberlo de entrada) — alimenta el badge de reloj
  // del calendario (§7.5) y el criterio "no sobrescribir" de Replicar (§5.6bis).
  final Set<DateTime> _fechasConHorarioGuardado = {};

  // Horarios por Defecto (§5.4bis) — minutos desde medianoche, steppers "− / +" de 30 min.
  int _bloque1InicioMin = 9 * 60;
  int _bloque1FinMin = 12 * 60;
  int _bloque2InicioMin = 14 * 60;
  int _bloque2FinMin = 18 * 60;

  // Replicar en semanas/meses (§5.6bis) — Lun a Vie seleccionados por defecto.
  final Set<int> _diasReplicar = {1, 2, 3, 4, 5};
  _AlcanceReplica _alcanceReplicar = _AlcanceReplica.semanas12;
  bool _sobrescribirReplicar = false;

  // Configuración General (§5.4bis).
  int _duracionCitaMin = 60;
  int _citasMaximasDia = 20;
  int _anticipacionReservas = 30;
  int _descansoInicioMin = 12 * 60;
  int _descansoFinMin = 14 * 60;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void initState() {
    super.initState();
    _cargarServicios();
  }

  Future<void> _cargarServicios() async {
    final sesion = context.read<Sesion>();
    try {
      final raw = await sesion.api.getList('/profesionales/${sesion.profesionalId}/servicios');
      final servicios = raw.map((e) => _ServicioProfesional.fromApi(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _servicios = servicios;
        _cargandoServicios = false;
        if (servicios.length == 1) _servicioIdSeleccionado = servicios.single.servicioId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoServicios = false;
        _errorServicios = e.toString();
      });
    }
  }

  int _diaSemanaBackend(DateTime fecha) => fecha.weekday % 7; // Dart lun=1..dom=7 -> dom=0..sáb=6

  void _alternarFecha(DateTime fecha) {
    setState(() {
      final normalizada = MonthCalendarPicker.dateOnly(fecha);
      if (_fechasSeleccionadas.contains(normalizada)) {
        _fechasSeleccionadas.remove(normalizada);
      } else {
        _fechasSeleccionadas.add(normalizada);
      }
    });
  }

  void _aplicarPlantilla() {
    if (_diasReplicar.isEmpty) {
      setState(() {
        _mensaje = 'Elegí al menos un día de la semana para replicar.';
        _mensajeEsError = true;
      });
      return;
    }
    final hoy = MonthCalendarPicker.dateOnly(DateTime.now());
    final horizonte = hoy.add(Duration(days: _diasDelAlcance(_alcanceReplicar)));

    final nuevas = <DateTime>{};
    for (var fecha = hoy; fecha.isBefore(horizonte); fecha = fecha.add(const Duration(days: 1))) {
      if (!_diasReplicar.contains(_diaSemanaBackend(fecha))) continue;
      final yaGuardada = _fechasConHorarioGuardado.contains(fecha);
      if (_sobrescribirReplicar || !yaGuardada) {
        nuevas.add(fecha);
      }
    }

    setState(() {
      _fechasSeleccionadas.addAll(nuevas);
      _mesVisible = DateTime(hoy.year, hoy.month, 1);
      _mensajeEsError = false;
      _mensaje = nuevas.isEmpty
          ? 'La plantilla no agregó fechas nuevas (¿ya estaban todas seleccionadas?).'
          : 'Se agregaron ${nuevas.length} fecha(s) al calendario. Revisalas y confirmá con '
              '"Guardar ${_fechasSeleccionadas.length} Fechas" para que se apliquen de verdad.';
    });
  }

  void _restablecer() {
    setState(() {
      _fechasSeleccionadas.clear();
      _bloque1InicioMin = 9 * 60;
      _bloque1FinMin = 12 * 60;
      _bloque2InicioMin = 14 * 60;
      _bloque2FinMin = 18 * 60;
      _diasReplicar
        ..clear()
        ..addAll({1, 2, 3, 4, 5});
      _alcanceReplicar = _AlcanceReplica.semanas12;
      _sobrescribirReplicar = false;
      _duracionCitaMin = 60;
      _citasMaximasDia = 20;
      _anticipacionReservas = 30;
      _descansoInicioMin = 12 * 60;
      _descansoFinMin = 14 * 60;
      _mensaje = null;
    });
  }

  Future<void> _guardar() async {
    final servicioId = _servicioIdSeleccionado;
    if (servicioId == null) {
      setState(() {
        _mensaje = _servicios.isEmpty
            ? 'Todavía no tenés servicios asociados a tu agenda — agregá uno desde "Editar '
                'Perfil" antes de configurar horarios.'
            : 'Elegí a qué servicio aplican estos horarios.';
        _mensajeEsError = true;
      });
      return;
    }
    if (_fechasSeleccionadas.isEmpty) {
      setState(() {
        _mensaje = 'Seleccioná al menos una fecha en el calendario.';
        _mensajeEsError = true;
      });
      return;
    }

    setState(() {
      _guardando = true;
      _mensaje = null;
    });

    final sesion = context.read<Sesion>();
    final diasSemana = _fechasSeleccionadas.map(_diaSemanaBackend).toSet();
    // Record posicional (int, int) = (inicio, fin) — un literal `(a, b)` siempre crea campos
    // posicionales ($1/$2); para campos con nombre habría que escribir `(inicio: a, fin: b)`.
    final bloques = <(int, int)>[
      (_bloque1InicioMin, _bloque1FinMin),
      (_bloque2InicioMin, _bloque2FinMin),
    ].where((b) => b.$1 < b.$2).toList();

    var creados = 0;
    final errores = <String>[];
    for (final diaSemana in diasSemana) {
      for (final bloque in bloques) {
        try {
          await sesion.api.post('/profesionales/${sesion.profesionalId}/disponibilidad', {
            'servicio_id': servicioId,
            'dia_semana': diaSemana,
            'hora_inicio': NumericStepperField.formatHHmm(bloque.$1),
            'hora_fin': NumericStepperField.formatHHmm(bloque.$2),
          });
          creados++;
        } catch (e) {
          errores.add(e.toString());
        }
      }
    }

    // "Duración de Citas" sí tiene endpoint real (PATCH .../configuracion, D10) — se guarda en
    // la misma acción para no sumar un segundo botón que el wireframe compacto no contempla.
    try {
      await sesion.api.patch('/profesionales/${sesion.profesionalId}/configuracion', {
        'duracion_cita_min': _duracionCitaMin,
      });
    } catch (e) {
      errores.add(e.toString());
    }

    if (!mounted) return;
    setState(() {
      _guardando = false;
      if (creados > 0) _fechasConHorarioGuardado.addAll(_fechasSeleccionadas);
      _mensajeEsError = errores.isNotEmpty;
      _mensaje = errores.isEmpty
          ? 'Guardado: $creados bloque(s) de horario para ${diasSemana.length} día(s) de la semana.'
          : 'Se guardaron $creados bloque(s), pero hubo ${errores.length} error(es). '
              'Último: ${errores.last}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: const AppHeader(variant: AppHeaderVariant.primary, emoji: '⏰', title: 'Gestión de Horarios'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(emoji: '🧰', text: 'Servicio'),
                _servicioSelector(context),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(emoji: '🗓️', text: 'Seleccionar Fechas Disponibles'),
                MonthCalendarPicker(
                  month: _mesVisible,
                  onMonthChanged: (m) => setState(() => _mesVisible = m),
                  selectedDates: _fechasSeleccionadas,
                  onDayTap: _alternarFecha,
                  datesWithSchedule: _fechasConHorarioGuardado,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '📅 ${_fechasSeleccionadas.length} fecha(s) seleccionadas este mes',
                  style: AppTypography.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fechas Seleccionadas:', style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary)),
                const SizedBox(height: AppSpacing.sm),
                if (_fechasSeleccionadas.isEmpty)
                  Text('Todavía no elegiste ninguna fecha.', style: AppTypography.caption(context))
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final fecha in _fechasOrdenadas())
                        _FechaChip(label: _capitalize(DateFormat('d MMM', 'es').format(fecha))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(emoji: '⏰', text: 'Horarios por Defecto'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Inicio',
                        value: _bloque1InicioMin,
                        onChanged: (v) => setState(() => _bloque1InicioMin = v),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Fin',
                        value: _bloque1FinMin,
                        onChanged: (v) => setState(() => _bloque1FinMin = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Inicio',
                        value: _bloque2InicioMin,
                        onChanged: (v) => setState(() => _bloque2InicioMin = v),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Fin',
                        value: _bloque2FinMin,
                        onChanged: (v) => setState(() => _bloque2FinMin = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(emoji: '🗓️', text: 'Replicar en semanas / meses'),
                Text('Días de la semana', style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (var i = 0; i < _diasChipLabels.length; i++)
                      _ToggleChip(
                        label: _diasChipLabels[i],
                        selected: _diasReplicar.contains(i),
                        onTap: () => setState(() {
                          if (!_diasReplicar.remove(i)) _diasReplicar.add(i);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                Text('Alcance desde hoy', style: AppTypography.caption(context)),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final alcance in _AlcanceReplica.values)
                      _ToggleChip(
                        label: _alcanceLabel(alcance),
                        selected: _alcanceReplicar == alcance,
                        onTap: () => setState(() => _alcanceReplicar = alcance),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Sobrescribir días que ya tienen horario', style: AppTypography.body(context)),
                  subtitle: Text(
                    'Desactivado: solo completa días vacíos. Activado: reemplaza también los ya guardados.',
                    style: AppTypography.caption(context),
                  ),
                  value: _sobrescribirReplicar,
                  onChanged: (v) => setState(() => _sobrescribirReplicar = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                SuccessButton(label: '📋 Aplicar plantilla al calendario', onPressed: _aplicarPlantilla),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _sectionCard(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(emoji: '⚙️', text: 'Configuración General'),
                NumericStepperField(
                  label: 'Duración de Citas',
                  value: _duracionCitaMin,
                  min: 15,
                  max: 240,
                  step: 15,
                  unit: ' min',
                  onChanged: (v) => setState(() => _duracionCitaMin = v),
                ),
                const SizedBox(height: AppSpacing.md),
                NumericStepperField(
                  label: 'Citas Máximas por Día',
                  value: _citasMaximasDia,
                  min: 1,
                  max: 50,
                  onChanged: (v) => setState(() => _citasMaximasDia = v),
                ),
                const SizedBox(height: AppSpacing.md),
                NumericStepperField(
                  label: 'Anticipación de Reservas',
                  value: _anticipacionReservas,
                  min: 0,
                  max: 90,
                  onChanged: (v) => setState(() => _anticipacionReservas = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle(emoji: '☕', text: 'Tiempo de Descanso'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Hora de Inicio',
                        value: _descansoInicioMin,
                        glyph: NumericStepperGlyph.chevron,
                        onChanged: (v) => setState(() => _descansoInicioMin = v),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.base),
                    Expanded(
                      child: _LabeledStepperCompact(
                        label: 'Hora de Fin',
                        value: _descansoFinMin,
                        glyph: NumericStepperGlyph.chevron,
                        onChanged: (v) => setState(() => _descansoFinMin = v),
                      ),
                    ),
                  ],
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
      bottomNavigationBar: Material(
        color: colors.surface,
        elevation: 8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Row(
              children: [
                Expanded(
                  child: WarningButton(
                    label: 'Restablecer',
                    onPressed: _guardando ? null : _restablecer,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Guardar ${_fechasSeleccionadas.length} Fechas',
                    loading: _guardando,
                    onPressed: (_guardando || _fechasSeleccionadas.isEmpty || _servicioIdSeleccionado == null)
                        ? null
                        : _guardar,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DateTime> _fechasOrdenadas() => _fechasSeleccionadas.toList()..sort();

  Widget _servicioSelector(BuildContext context) {
    final colors = AppColors.of(context);
    if (_cargandoServicios) {
      return Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpacing.sm),
          Text('Cargando tus servicios...', style: AppTypography.caption(context)),
        ],
      );
    }
    if (_errorServicios != null) {
      return Text(
        'No se pudieron cargar tus servicios: $_errorServicios',
        style: AppTypography.caption(context).copyWith(color: colors.danger.base),
      );
    }
    if (_servicios.isEmpty) {
      return Text(
        'Todavía no asociaste ningún servicio a tu agenda. Andá a "Editar Perfil" > "Servicios '
        'que brindo" para agregar al menos uno — recién ahí vas a poder configurar horarios.',
        style: AppTypography.body(context),
      );
    }
    if (_servicios.length == 1) {
      return Text('Horarios para: ${_servicios.single.nombre}', style: AppTypography.caption(context));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿A qué servicio aplican estos horarios?', style: AppTypography.caption(context)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final servicio in _servicios)
              _ToggleChip(
                label: servicio.nombre,
                selected: _servicioIdSeleccionado == servicio.servicioId,
                onTap: () => setState(() => _servicioIdSeleccionado = servicio.servicioId),
              ),
          ],
        ),
      ],
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
}

/// Fila de `GET /profesionales/:id/servicios` — solo los 2 campos que este selector necesita
/// (nombre para mostrar, servicio_id para el POST de `_guardar`). El resto del contrato
/// (`duracion_min`, `precio_referencia`, `negocio_id`, `negocio_nombre`, `requiere_sena`,
/// `monto_sena` — ver `precios_senas_screen.dart` para el shape completo) no hace falta acá.
class _ServicioProfesional {
  const _ServicioProfesional({required this.servicioId, required this.nombre});

  final String servicioId;
  final String nombre;

  factory _ServicioProfesional.fromApi(Map<String, dynamic> json) => _ServicioProfesional(
        servicioId: json['servicio_id'] as String,
        nombre: json['nombre'] as String,
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          ExcludeSemantics(child: Text(emoji, style: const TextStyle(fontSize: 18))),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(text, style: AppTypography.sectionTitle(context))),
        ],
      ),
    );
  }
}

/// Columna label chico + `NumericStepperField` sin su propio label — para poner dos steppers de
/// hora lado a lado ("Inicio"/"Fin"), tal como el wireframe compacto (§5.4bis).
class _LabeledStepperCompact extends StatelessWidget {
  const _LabeledStepperCompact({
    required this.label,
    required this.value,
    required this.onChanged,
    this.glyph = NumericStepperGlyph.minusPlus,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final NumericStepperGlyph glyph;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(context)),
        const SizedBox(height: AppSpacing.xs),
        NumericStepperField(
          value: value,
          min: 0,
          max: 23 * 60 + 30,
          step: 30,
          glyph: glyph,
          semanticLabel: label,
          valueFormatter: NumericStepperField.formatHHmm,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Chip de selección (§7.9): seleccionado = fondo `primary` + texto blanco; no seleccionado =
/// fondo `surface` + borde `border` + texto `textPrimary`.
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

/// Chip de solo lectura para "Fechas Seleccionadas" — sin "✕" (§7.5bis: no removible desde acá).
class _FechaChip extends StatelessWidget {
  const _FechaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(
        label,
        style: AppTypography.caption(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
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
