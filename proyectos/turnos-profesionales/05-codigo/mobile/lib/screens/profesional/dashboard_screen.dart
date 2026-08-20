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
import 'agenda_screen.dart';
import 'nueva_cita_screen.dart';

/// Dashboard (Profesional) — HU-27, pantalla nueva (no reemplaza nada existente). Wireframe
/// corregido completo en `mapa-pantallas.md` §5.2bis. El ícono "cambiar de vista" del header
/// (§5.2bis, pregunta abierta #6 del backlog, resuelta por el CEO 2026-08-06) ya tiene
/// comportamiento real: alterna entre los negocios de `Sesion.negocios` (ver [_cambiarNegocio])
/// — solo visible con 2+ negocios activos, cero cambio visual para el caso común (un profesional
/// en un único negocio). El caso "0 negocios" (cuenta todavía sin ningún negocio activo) también
/// se resuelve acá, ver [_SinNegocioView].
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<_TurnoDashboard>> _futureTurnos;

  // HU-27 pide un stat de "Completadas" y una acción "marcar como completada" por turno, pero
  // el backend actual (`estado_turno`, migrations/001_init.sql) no tiene un estado
  // "completado" ni un endpoint para transicionar un turno a ese estado (solo
  // pendiente_de_pago/confirmado/cancelado/reprogramado, ver routes/turnos.ts). Hasta que
  // Backend lo agregue, "marcar como completada" es una simulación local de esta sesión (no
  // persiste, se pierde si se recarga la pantalla) — se documenta acá en vez de fingir una
  // llamada a una API que no existe (CLAUDE.md: sincronizar contra las APIs publicadas, no
  // inventar lógica de negocio en el cliente).
  final Set<String> _completadosLocalmente = {};

  /// HU-27: `true` mientras `_cambiarNegocio` está en curso (llamada de red a
  /// `POST /auth/entrar-a-negocio` + refetch) — deshabilita el ícono del header para evitar
  /// disparar un segundo cambio antes de que termine el primero.
  bool _cambiandoNegocio = false;

  @override
  void initState() {
    super.initState();
    // HU-27: sin negocio activo (ver [_SinNegocioView] más abajo) no hay nada que pedirle a
    // `/profesionales/:id/turnos` todavía scopeado — se evita el round-trip de red y se va
    // directo al estado vacío.
    final sesion = context.read<Sesion>();
    _futureTurnos =
        sesion.negocioId == null ? Future<List<_TurnoDashboard>>.value(const []) : _cargarTurnos();
  }

  Future<List<_TurnoDashboard>> _cargarTurnos() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/profesionales/${sesion.profesionalId}/turnos');
    return raw.map((e) => _TurnoDashboard.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargarTurnos();
    setState(() => _futureTurnos = next);
    await next;
  }

  void _marcarCompletada(String turnoId) {
    setState(() => _completadosLocalmente.add(turnoId));
  }

  /// Pedido del CEO (2026-08-20): al marcar un turno como completado, ofrecer cargar una nota
  /// médica y/o un tratamiento para ese cliente. [_marcarCompletada] se dispara primero y de
  /// forma incondicional — no depende de lo que pase en el modal: el turno queda marcado como
  /// completado localmente lo haya cerrado el profesional cargando algo o no (ver
  /// [_CompletarTurnoModal]). Mismo mecanismo que [_abrirNuevaCita] (`AppModalSheet.show`) en vez
  /// de un `Navigator.push` a pantalla completa suelto.
  void _completarYAbrirModal(BuildContext context, _TurnoDashboard turno) {
    _marcarCompletada(turno.id);
    final profesionalId = context.read<Sesion>().profesionalId;
    // Defensivo: esta pantalla ya necesita `profesionalId` no nulo para haber podido cargar
    // `turnosHoy` en primer lugar (ver `_cargarTurnos`) — no debería poder ser nulo acá.
    if (profesionalId == null) return;
    AppModalSheet.show<void>(
      context,
      builder: (_) => _CompletarTurnoModal(
        profesionalId: profesionalId,
        clienteId: turno.clienteId,
        clienteNombre: turno.cliente,
      ),
    );
  }

  bool _esHoy(DateTime fecha) {
    final hoy = DateTime.now();
    return fecha.year == hoy.year && fecha.month == hoy.month && fecha.day == hoy.day;
  }

  /// HU-23: mismo mecanismo que `configuracion_screen.dart` (`_abrirNuevaCita`) — `NuevaCitaScreen`
  /// ya se construye sobre `AppModalSheet`, así que se abre con `AppModalSheet.show` en vez de
  /// `Navigator.push` para no duplicar el envoltorio. A diferencia de Configuración, el Dashboard
  /// sí muestra los turnos de hoy (`_futureTurnos`) — si la cita nueva es de hoy tiene que
  /// aparecer en "Próximas citas" sin esperar a un pull-to-refresh manual, por eso [_refrescar]
  /// además de la confirmación.
  Future<void> _abrirNuevaCita(BuildContext context) async {
    final creada = await AppModalSheet.show<bool>(context, builder: (_) => const NuevaCitaScreen());
    if (creada == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cita creada y cliente notificado.')),
      );
      await _refrescar();
    }
  }

  /// HU-27 ("cambiar de vista"): abre el selector con los negocios de `Sesion.negocios` y, si se
  /// elige uno distinto del activo, reemite la sesión contra ese negocio
  /// (`Sesion.entrarANegocio`) y refresca esta pantalla. El resto de las pestañas del
  /// `ProfesionalShell` (Horarios, Pacientes, etc. — cada una cachea su propio Future en
  /// `initState`, no reacciona sola a cambios de `Sesion`) se refrescan por su cuenta: `main.dart`
  /// (`_Router`) le da a `ProfesionalShell` una `key` atada a `Sesion.negocioId`, así que cambiar
  /// de negocio recrea todo ese subárbol desde cero y cada pestaña vuelve a pedir sus datos ya
  /// scopeados al negocio nuevo. El `mounted`/`setState` de acá defienden el caso en que esa
  /// recreación todavía no ocurrió cuando este método sigue corriendo — la propia instancia
  /// actual de este Dashboard también puede ser una de las que se recrean.
  Future<void> _cambiarNegocio() async {
    final sesion = context.read<Sesion>();
    final elegido = await elegirNegocio(context, sesion.negocios, actualNegocioId: sesion.negocioId);
    if (!mounted || elegido == null || elegido.negocioId == sesion.negocioId) return;

    setState(() => _cambiandoNegocio = true);
    try {
      await sesion.entrarANegocio(elegido.negocioId);
      if (!mounted) return;
      // Estado local de "completadas" (ver comentario de `_completadosLocalmente` arriba): es
      // una simulación por sesión, no persiste — al cambiar de negocio no debería seguir
      // marcando como completados turnos que ya no corresponden a la agenda que se está viendo.
      setState(() => _completadosLocalmente.clear());
      await _refrescar();
    } catch (e) {
      if (mounted) _avisoNoDisponible(context, 'No se pudo cambiar de negocio: $e');
    } finally {
      if (mounted) setState(() => _cambiandoNegocio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<Sesion>();
    final colors = AppColors.of(context);
    final fechaFormateada = _capitalize(DateFormat("EEEE, d 'de' MMMM 'de' yyyy", 'es').format(DateTime.now()));

    // HU-27, caso "0 negocios" (cuenta profesional todavía sin ningún negocio activo, ver
    // `login_screen.dart`/`_completarLogin`): estado propio en vez de un dashboard vacío que
    // sugiere "sin turnos hoy" cuando en realidad no hay ningún negocio del que traerlos.
    if (sesion.negocioId == null) {
      return _SinNegocioView(fechaFormateada: fechaFormateada);
    }

    return Scaffold(
      // §7.7bis: Dashboard usa header `surface` (blanco), no `primary` — corrección puntual
      // sobre §7.7, confirmada en mapa-pantallas.md §5.2bis.
      appBar: AppHeader(
        variant: AppHeaderVariant.surface,
        // No hay claim `nombre` en el JWT (ver auth.ts: sub/rol/negocio_id/profesional_id
        // únicamente) — se evita inventar un nombre/título ("Dr. García") que la app no puede
        // conocer todavía.
        title: '¡Hola!',
        subtitle: fechaFormateada,
        actions: [
          // HU-27: solo tiene sentido con 2+ negocios entre los que elegir — con uno solo (caso
          // común hoy) no se muestra nada, cero cambio visual respecto de antes de esta historia.
          if (sesion.tieneMultiplesNegocios)
            IconButton(
              icon: _cambiandoNegocio
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz),
              tooltip: 'Cambiar de vista',
              onPressed: _cambiandoNegocio ? null : _cambiarNegocio,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_TurnoDashboard>>(
          future: _futureTurnos,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(child: Text('No se pudo cargar el dashboard: ${snapshot.error}', style: AppTypography.body(context))),
                ],
              );
            }

            final turnosHoy = (snapshot.data ?? [])
                .where((t) => _esHoy(t.inicio))
                .toList()
              ..sort((a, b) => a.inicio.compareTo(b.inicio));
            final pacientesHoy = turnosHoy.map((t) => t.cliente).toSet().length;
            final completadas = turnosHoy.where((t) => _completadosLocalmente.contains(t.id)).length;
            final pendientes = turnosHoy.length - completadas;

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                StatCardGrid(cards: [
                  StatCard(value: '$pacientesHoy', label: 'Pacientes hoy', icon: Icons.people_outline),
                  StatCard(value: '$pendientes', label: 'Citas pendientes', icon: Icons.schedule_outlined),
                  StatCard(
                    value: '$completadas',
                    label: 'Completadas',
                    icon: Icons.check_circle_outline,
                    emphasize: true,
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Próximas citas', style: AppTypography.sectionTitle(context)),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgendaScreen())),
                      child: Text('Ver agenda >', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (turnosHoy.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: Text('No tenés citas para hoy.', style: AppTypography.body(context))),
                  )
                else
                  for (final turno in turnosHoy) ...[
                    _ProximaCitaCard(
                      turno: turno,
                      completada: _completadosLocalmente.contains(turno.id),
                      onCompletar: () => _completarYAbrirModal(context, turno),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        tooltip: 'Agendar Cita',
        onPressed: () => _abrirNuevaCita(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _avisoNoDisponible(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// HU-27, caso "0 negocios" — cuenta profesional autenticada pero todavía sin ninguna membresía
/// activa en `negocio_profesional` (ver el comentario de `DashboardScreen.build`). Mismo
/// `AppHeader` que el dashboard real (para no perder el saludo/fecha), sin ícono de "cambiar de
/// vista" (no hay nada entre qué elegir) ni el resto del contenido, que no tiene ningún negocio
/// del que traer datos — mensaje simple en vez de una pantalla en blanco o un error críptico.
class _SinNegocioView extends StatelessWidget {
  const _SinNegocioView({required this.fechaFormateada});

  final String fechaFormateada;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppHeader(variant: AppHeaderVariant.surface, title: '¡Hola!', subtitle: fechaFormateada),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: colors.textSecondary),
              const SizedBox(height: AppSpacing.base),
              Text(
                'Todavía no estás vinculado a ningún negocio',
                textAlign: TextAlign.center,
                style: AppTypography.subtitle(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnoDashboard {
  const _TurnoDashboard({
    required this.id,
    required this.cliente,
    required this.clienteId,
    required this.servicio,
    required this.inicio,
    required this.estado,
  });

  final String id;
  final String cliente;

  /// `usuario.id` real del cliente (NO el id de la ficha `paciente`) — mismo `:pacienteId` que ya
  /// consume `GET /profesionales/:id/pacientes/:pacienteId/historial`
  /// (`historial_paciente_screen.dart`). Lo agrega Backend (fast-follow 2026-08-20) a este mismo
  /// `GET /profesionales/:id/turnos`, para poder cargar nota médica/tratamiento desde acá sin un
  /// round-trip extra — ver [_DashboardScreenState._completarYAbrirModal].
  final String clienteId;
  final String servicio;
  final DateTime inicio;
  final TurnoEstado estado;

  factory _TurnoDashboard.fromApi(Map<String, dynamic> json) {
    return _TurnoDashboard(
      id: json['id'] as String,
      cliente: json['cliente'] as String,
      clienteId: json['cliente_id'] as String,
      servicio: json['servicio'] as String,
      inicio: DateTime.parse(json['inicio'] as String).toLocal(),
      estado: turnoEstadoFromApi(json['estado'] as String),
    );
  }
}

/// §5.2bis — card enriquecida de "Próximas citas": franja de acento a la izquierda,
/// `StatusPill`, botón ancho "✓✓ Marcar como completada" debajo del contenido.
///
/// Nota de diseño: no se pudo confirmar en las capturas si la franja de acento representa el
/// color del estado del turno o es puramente decorativa (sistema-diseno.md §12.4). Esta
/// implementación la ata al color del estado (igual que el `StatusPill` adyacente) por ser la
/// interpretación más consistente a falta de una regla confirmada — fácil de desacoplar si
/// UX/UI define lo contrario más adelante.
class _ProximaCitaCard extends StatelessWidget {
  const _ProximaCitaCard({required this.turno, required this.completada, required this.onCompletar});

  final _TurnoDashboard turno;
  final bool completada;
  final VoidCallback onCompletar;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final estado = completada ? TurnoEstado.completada : turno.estado;
    final acento = switch (estado) {
      TurnoEstado.confirmada => colors.success.base,
      TurnoEstado.porConfirmar => colors.warning.base,
      TurnoEstado.programada => colors.warning.base,
      TurnoEstado.cancelada => colors.danger.base,
      TurnoEstado.completada => colors.neutral.base,
    };
    final hora = DateFormat('HH:mm').format(turno.inicio);

    // Patrón estándar de Flutter para "card con sombra + contenido con esquinas recortadas": el
    // contenedor externo lleva la sombra (sin clip, para que no se corte), el ClipRRect interno
    // recorta la franja de acento + el fondo a las esquinas redondeadas.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppRadius.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          color: colors.surface,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: acento),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                turno.cliente,
                                style: AppTypography.subtitle(context)
                                    .copyWith(color: colors.textPrimary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StatusPill.turno(estado),
                          ],
                        ),
                        Text(turno.servicio, style: AppTypography.caption(context)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(hora, style: AppTypography.body(context).copyWith(color: acento, fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.md),
                        if (completada)
                          OutlineButton(label: '✓✓ Completada', onPressed: null, radiusVariant: AppButtonRadius.card)
                        else
                          PrimaryButton(
                            label: '✓✓ Marcar como completada',
                            onPressed: onCompletar,
                            radiusVariant: AppButtonRadius.card,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal ofrecido al marcar un turno como completado (pedido del CEO, 2026-08-20) — nota médica
/// y tratamiento son 2 acciones independientes y **opcionales**, cada una con su propio botón
/// "Guardar" y su propio feedback inline: mismo criterio de "guardado por fila/sección
/// independiente, no un botón general único" que `precios_senas_screen.dart` (ver el doc comment
/// de esa clase) — así, si una de las 2 falla, no hay ambigüedad sobre qué quedó guardado y qué
/// no. El profesional puede cerrar sin cargar nada (botón "Listo" del footer, o el "✕" de
/// `AppModalSheet`) — el turno ya se marcó como completado localmente ANTES de abrir este modal
/// (ver `_DashboardScreenState._completarYAbrirModal`), así que cerrar sin cargar nada es un
/// flujo válido y esperado, no una cancelación.
class _CompletarTurnoModal extends StatelessWidget {
  const _CompletarTurnoModal({required this.profesionalId, required this.clienteId, required this.clienteNombre});

  final String profesionalId;
  final String clienteId;
  final String clienteNombre;

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: 'Completar turno',
      secondaryLabel: 'Listo',
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          Text(
            'Turno de $clienteNombre marcado como completado. Opcionalmente, registrá acá una '
            'nota médica y/o un tratamiento — podés cerrar sin cargar nada.',
            style: AppTypography.caption(context),
          ),
          const SizedBox(height: AppSpacing.base),
          _NotaMedicaForm(profesionalId: profesionalId, clienteId: clienteId),
          const SizedBox(height: AppSpacing.md),
          _TratamientoForm(profesionalId: profesionalId, clienteId: clienteId),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}

/// Sección "Nota médica" del modal de arriba — `POST
/// /profesionales/:profesionalId/pacientes/:clienteId/notas-medicas`, body `{ texto }`. Mismo
/// criterio de estado propio (loading/error/mensaje) que `_ServicioSenaCardState`
/// (`precios_senas_screen.dart`).
class _NotaMedicaForm extends StatefulWidget {
  const _NotaMedicaForm({required this.profesionalId, required this.clienteId});

  final String profesionalId;
  final String clienteId;

  @override
  State<_NotaMedicaForm> createState() => _NotaMedicaFormState();
}

class _NotaMedicaFormState extends State<_NotaMedicaForm> {
  final _textoCtrl = TextEditingController();

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final texto = _textoCtrl.text.trim();
    if (texto.isEmpty) {
      setState(() {
        _mensaje = 'La nota no puede estar vacía.';
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
      await sesion.api.post(
        '/profesionales/${widget.profesionalId}/pacientes/${widget.clienteId}/notas-medicas',
        {'texto': texto},
      );
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'Nota guardada.';
        _mensajeEsError = false;
        _textoCtrl.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar la nota: ${e.message}';
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar la nota: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Nota médica', style: AppTypography.sectionTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _textoCtrl,
            enabled: !_guardando,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notas de la consulta'),
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _mensaje!,
              style: AppTypography.caption(context)
                  .copyWith(color: _mensajeEsError ? colors.danger.base : colors.success.base),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              label: 'Guardar nota',
              radiusVariant: AppButtonRadius.card,
              expand: false,
              loading: _guardando,
              onPressed: _guardando ? null : _guardar,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sección "Tratamiento" del modal de arriba — `POST
/// /profesionales/:profesionalId/pacientes/:clienteId/tratamientos`, body `{ descripcion,
/// fecha_inicio, fecha_fin }`. `fecha_inicio` arranca en hoy (requerida, siempre se manda);
/// `fecha_fin` es opcional — sin elegir queda `null` ("tratamiento en curso"). Mismo selector de
/// fecha que `_campoFechaNacimiento` (`ficha_paciente_screen.dart`): diálogo compacto con
/// `MonthCalendarPicker(allowPastSelection: true, showLegend: false)` en vez de un date picker
/// nuevo — `allowPastSelection` también habilita fechas futuras (ver ese widget), útil acá para
/// poder cargar un tratamiento con inicio o fin programado.
class _TratamientoForm extends StatefulWidget {
  const _TratamientoForm({required this.profesionalId, required this.clienteId});

  final String profesionalId;
  final String clienteId;

  @override
  State<_TratamientoForm> createState() => _TratamientoFormState();
}

class _TratamientoFormState extends State<_TratamientoForm> {
  final _descripcionCtrl = TextEditingController();
  DateTime _fechaInicio = MonthCalendarPicker.dateOnly(DateTime.now());
  DateTime? _fechaFin;

  bool _guardando = false;
  String? _mensaje;
  bool _mensajeEsError = false;

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<DateTime?> _elegirFecha(DateTime? actual) {
    var mesVisible = actual ?? _fechaInicio;
    return showDialog<DateTime>(
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
                  selectedDates: actual != null ? {MonthCalendarPicker.dateOnly(actual)} : {},
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
  }

  Future<void> _elegirFechaInicio() async {
    final elegida = await _elegirFecha(_fechaInicio);
    if (elegida != null) setState(() => _fechaInicio = elegida);
  }

  Future<void> _elegirFechaFin() async {
    final elegida = await _elegirFecha(_fechaFin);
    if (elegida != null) setState(() => _fechaFin = elegida);
  }

  Future<void> _guardar() async {
    final descripcion = _descripcionCtrl.text.trim();
    if (descripcion.isEmpty) {
      setState(() {
        _mensaje = 'La descripción no puede estar vacía.';
        _mensajeEsError = true;
      });
      return;
    }
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    final formato = DateFormat('yyyy-MM-dd');
    try {
      await sesion.api.post(
        '/profesionales/${widget.profesionalId}/pacientes/${widget.clienteId}/tratamientos',
        {
          'descripcion': descripcion,
          'fecha_inicio': formato.format(_fechaInicio),
          'fecha_fin': _fechaFin != null ? formato.format(_fechaFin!) : null,
        },
      );
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'Tratamiento guardado.';
        _mensajeEsError = false;
        _descripcionCtrl.clear();
        _fechaInicio = MonthCalendarPicker.dateOnly(DateTime.now());
        _fechaFin = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar el tratamiento: ${e.message}';
        _mensajeEsError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _mensaje = 'No se pudo guardar el tratamiento: $e';
        _mensajeEsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text('Tratamiento', style: AppTypography.sectionTitle(context)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _descripcionCtrl,
            enabled: !_guardando,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Descripción'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _campoFecha(
                  context,
                  label: 'Fecha de inicio',
                  fecha: _fechaInicio,
                  onTap: _guardando ? null : _elegirFechaInicio,
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: _campoFecha(
                  context,
                  label: 'Fecha de fin',
                  fecha: _fechaFin,
                  onTap: _guardando ? null : _elegirFechaFin,
                  onClear: _fechaFin != null && !_guardando ? () => setState(() => _fechaFin = null) : null,
                ),
              ),
            ],
          ),
          if (_fechaFin == null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Sin fecha de fin: tratamiento en curso.', style: AppTypography.caption(context)),
          ],
          if (_mensaje != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _mensaje!,
              style: AppTypography.caption(context)
                  .copyWith(color: _mensajeEsError ? colors.danger.base : colors.success.base),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(
              label: 'Guardar tratamiento',
              radiusVariant: AppButtonRadius.card,
              expand: false,
              loading: _guardando,
              onPressed: _guardando ? null : _guardar,
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoFecha(
    BuildContext context, {
    required String label,
    required DateTime? fecha,
    required VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    final colors = AppColors.of(context);
    final texto = fecha != null ? DateFormat('dd/MM/yyyy').format(fecha) : 'Sin definir';
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: onTap != null,
          suffixIcon: onClear != null
              ? IconButton(icon: const Icon(Icons.clear, size: 18), tooltip: 'Quitar fecha', onPressed: onClear)
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          texto,
          style: AppTypography.body(context).copyWith(color: onTap != null ? colors.textPrimary : colors.textSecondary),
        ),
      ),
    );
  }
}
