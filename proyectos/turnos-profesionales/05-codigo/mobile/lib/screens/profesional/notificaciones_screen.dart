import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/widgets.dart';
import 'configuracion_notificaciones_screen.dart';

/// Bandeja de Notificaciones (tab "Notificaciones", Profesional) — HU-14b + HU-25
/// (`mapa-pantallas.md` §5.15). Reemplaza al `ProximamenteScreen` que tenía este ítem en
/// `profesional_shell.dart`. Contrato: `GET /notificaciones` -> lista PLANA (no envuelta en un
/// objeto), más nuevas primero, cada item `{ id, tipo, leido, creado_en, turno_id, mensaje }` —
/// `mensaje` ya viene armado en español desde `dominio/notificaciones.ts`, no se reconstruye acá.
/// `turno_id` no se mapea a este modelo: nada en esta ronda navega desde una notificación a su
/// turno (candidato para una ronda futura de deep-link, ver nota al pie de este archivo).
///
/// **Agrupado "Hoy"/"Ayer" (§5.15): decisión de a quién le toca.** El backend documenta
/// explícitamente (`routes/notificaciones.ts`, GET /notificaciones) que a propósito NO agrupa —
/// no tiene forma confiable de conocer la zona horaria del dispositivo, así que agrupar ahí
/// podría mostrar "Ayer" en vez de "Hoy" cerca de la medianoche para un usuario en otro huso. Acá
/// sí se puede: `creado_en` llega en ISO-8601, se parsea con `.toLocal()` y se agrupa contra
/// `DateTime.now()` del propio dispositivo — mismo criterio que ya usa `_esHoy` en
/// `dashboard_screen.dart` (comparar year/month/day, no la marca de tiempo completa). El array ya
/// llega ordenado por `creado_en DESC` (contrato del backend) y no se reordena acá: como Dart
/// preserva el orden de inserción de un `Map` (`LinkedHashMap` por defecto), agrupar en una sola
/// pasada produce los grupos en el mismo orden relativo en que aparecen las notificaciones —
/// "Hoy" antes que "Ayer" antes que fechas más viejas, sin ordenar los grupos por separado.
///
/// **"Marcar todas como leídas" (`PATCH /notificaciones/leer-todas`): no está en el wireframe
/// explícito de §5.15, se agrega igual.** Es un patrón estándar de cualquier bandeja de
/// notificaciones, el backend ya expone el endpoint pensado para esto (ver el comentario de ese
/// endpoint en `routes/notificaciones.ts`) y sin él la única forma de vaciar el badge de no
/// leídas es tocar notificación por notificación. Se muestra como acción de texto arriba de la
/// lista (no en el header, para no competir con el ícono ⚙ que sí está en el wireframe) y solo
/// cuando hay al menos una no leída.
///
/// **Marcar como leída es optimista, no un refetch completo.** Tocar una notificación no leída
/// actualiza el estado local al instante (vía `_leidasLocalmente`, mismo patrón de "overlay local
/// sobre datos ya resueltos" que `_completadosLocalmente` en `dashboard_screen.dart`) y dispara
/// el PATCH en segundo plano; si falla, se revierte y se avisa por snackbar. Se prefiere esto a
/// volver a pedir `GET /notificaciones` entero por cada toque: releer N notificaciones para
/// tildar 1 sola es una espera perceptible sin ganancia (el backend no cambia orden ni forma de
/// los demás campos al marcar una como leída).
class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  late Future<List<_Notificacion>> _futureNotificaciones;

  final Set<String> _leidasLocalmente = {};

  @override
  void initState() {
    super.initState();
    _futureNotificaciones = _cargar();
  }

  Future<List<_Notificacion>> _cargar() async {
    final sesion = context.read<Sesion>();
    final raw = await sesion.api.getList('/notificaciones');
    return raw.map((e) => _Notificacion.fromApi(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refrescar() async {
    final next = _cargar();
    setState(() {
      _futureNotificaciones = next;
      _leidasLocalmente.clear();
    });
    await next;
  }

  bool _estaLeida(_Notificacion n) => n.leido || _leidasLocalmente.contains(n.id);

  Future<void> _marcarLeida(_Notificacion n) async {
    if (_estaLeida(n)) return;
    setState(() => _leidasLocalmente.add(n.id));
    try {
      await context.read<Sesion>().api.patch('/notificaciones/${n.id}/leer');
    } catch (e) {
      if (!mounted) return;
      setState(() => _leidasLocalmente.remove(n.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo marcar como leída: $e')));
    }
  }

  Future<void> _marcarTodasLeidas(List<_Notificacion> notificaciones) async {
    final pendientes = notificaciones.where((n) => !_estaLeida(n)).map((n) => n.id).toList();
    if (pendientes.isEmpty) return;
    setState(() => _leidasLocalmente.addAll(pendientes));
    try {
      await context.read<Sesion>().api.patch('/notificaciones/leer-todas');
    } catch (e) {
      if (!mounted) return;
      setState(() => _leidasLocalmente.removeAll(pendientes));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo marcar todas como leídas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      // Root del bottom nav, mismo criterio que Gestión de Horarios/Pacientes: header `primary`
      // con emoji (no `surface`, esa variante queda para Dashboard). El ícono ⚙ del wireframe
      // (§5.15) abre la Configuración de Notificaciones granular (§5.14).
      appBar: AppHeader(
        variant: AppHeaderVariant.primary,
        emoji: '🔔',
        title: 'Notificaciones',
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configuración de notificaciones',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfiguracionNotificacionesScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refrescar,
        child: FutureBuilder<List<_Notificacion>>(
          future: _futureNotificaciones,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  Center(
                    child: Text(
                      'No se pudieron cargar las notificaciones: ${snapshot.error}',
                      style: AppTypography.body(context),
                    ),
                  ),
                ],
              );
            }

            final notificaciones = snapshot.data ?? [];
            final hayNoLeidas = notificaciones.any((n) => !_estaLeida(n));
            final grupos = _agruparPorDia(notificaciones, DateTime.now());

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                if (notificaciones.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text('Todavía no tenés notificaciones.', style: AppTypography.body(context)),
                    ),
                  )
                else ...[
                  if (hayNoLeidas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _marcarTodasLeidas(notificaciones),
                          icon: Icon(Icons.done_all, size: 18, color: colors.primary),
                          label: Text(
                            'Marcar todas como leídas',
                            style: AppTypography.caption(context)
                                .copyWith(color: colors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  for (final grupo in grupos.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(grupo.key, style: AppTypography.sectionTitle(context)),
                    ),
                    for (final n in grupo.value) ...[
                      _NotificacionCard(notificacion: n, leida: _estaLeida(n), onTap: () => _marcarLeida(n)),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Notificacion {
  const _Notificacion({
    required this.id,
    required this.tipo,
    required this.leido,
    required this.creadoEn,
    required this.mensaje,
  });

  final String id;
  final String tipo;
  final bool leido;
  final DateTime creadoEn;
  final String mensaje;

  factory _Notificacion.fromApi(Map<String, dynamic> json) => _Notificacion(
        id: json['id'] as String,
        tipo: json['tipo'] as String,
        leido: json['leido'] as bool,
        creadoEn: DateTime.parse(json['creado_en'] as String).toLocal(),
        mensaje: json['mensaje'] as String,
      );
}

/// Agrupa preservando el orden de llegada (ver nota de la clase de arriba sobre por qué no hace
/// falta ordenar los grupos por separado). `ahora` se recibe como parámetro (en vez de llamar
/// `DateTime.now()` adentro) para que "Hoy"/"Ayer" se calculen una sola vez por `build`, no una
/// vez por notificación.
Map<String, List<_Notificacion>> _agruparPorDia(List<_Notificacion> notificaciones, DateTime ahora) {
  final grupos = <String, List<_Notificacion>>{};
  for (final n in notificaciones) {
    grupos.putIfAbsent(_etiquetaGrupo(n.creadoEn, ahora), () => []).add(n);
  }
  return grupos;
}

String _etiquetaGrupo(DateTime fecha, DateTime ahora) {
  if (_mismoDiaCalendario(fecha, ahora)) return 'Hoy';
  if (_mismoDiaCalendario(fecha, ahora.subtract(const Duration(days: 1)))) return 'Ayer';
  final mismoAnio = fecha.year == ahora.year;
  final formato = DateFormat(mismoAnio ? "d 'de' MMMM" : "d 'de' MMMM 'de' yyyy", 'es');
  return _capitalizar(formato.format(fecha));
}

bool _mismoDiaCalendario(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _capitalizar(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Card de una notificación: franja de acento + ícono coloreados según `tipo` (mismo criterio que
/// `_ProximaCitaCard` en `dashboard_screen.dart` para el color de estado de un turno), texto en
/// negrita + punto `primary` mientras no está leída. A diferencia de `_ProximaCitaCard`, la
/// superficie de fondo es un `Material` (no un `Container(color:)` liso): esta card sí es
/// interactiva (toca para marcar como leída) y el ripple de `InkWell` necesita pintar sobre un
/// `Material` propio para verse — sobre un `Container` opaco quedaría tapado.
class _NotificacionCard extends StatelessWidget {
  const _NotificacionCard({required this.notificacion, required this.leida, required this.onTap});

  final _Notificacion notificacion;
  final bool leida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (icono, estado) = switch (notificacion.tipo) {
      'confirmacion' => (Icons.check_circle_outline, colors.success),
      'recordatorio' => (Icons.schedule_outlined, colors.warning),
      'cancelacion' => (Icons.cancel_outlined, colors.danger),
      'reprogramacion' => (Icons.event_repeat_outlined, colors.neutral),
      _ => (Icons.notifications_outlined, colors.neutral),
    };
    final hora = DateFormat('HH:mm').format(notificacion.creadoEn);

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: AppRadius.cardShadow),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Material(
          color: colors.surface,
          child: InkWell(
            onTap: leida ? null : onTap,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: estado.base),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.base),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icono, size: 20, color: estado.base),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notificacion.mensaje,
                                  style: AppTypography.body(context).copyWith(
                                        color: colors.textPrimary,
                                        fontWeight: leida ? FontWeight.w400 : FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(hora, style: AppTypography.caption(context)),
                              ],
                            ),
                          ),
                          if (!leida) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
