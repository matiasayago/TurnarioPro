import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// §7.5, corregido en §7.5bis. Estado visual resuelto de una celda de día.
enum CalendarDayState { seleccionada, elegible, hoy, pasada }

// §6bis: bug de encoding a NO replicar — la app de referencia muestra "MI?"/"S?B" por un
// problema de codificación propio; acá se usan las abreviaturas correctas con acento.
const List<String> _diasSemana = ['DOM', 'LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB'];

/// §7.5 — grid mensual navegable con header "< Mes Año >". Componente **controlado**: no
/// guarda selección propia, el llamador es dueño de `selectedDates` y decide qué hacer en
/// `onDayTap` (agregar/quitar de su propio estado).
///
/// Semana en formato domingo-primero (`DOM LUN MAR MIÉ JUE VIE SÁB`), igual que el wireframe
/// compacto corregido de Gestión de Horarios (`mapa-pantallas.md` §5.4bis).
///
/// Corregido en §7.5bis contra capturas reales de la app de referencia:
/// - El anillo de "Hoy" es `warning` (ámbar), **no** `primary` — corrección real sobre el
///   diseño original, no un detalle menor.
/// - Se agrega el estado `elegible` (borde `primaryContainer`, fondo `surface`) para "día
///   seleccionable, todavía no elegido", más fiel a las capturas que el "Disponible" original.
class MonthCalendarPicker extends StatelessWidget {
  const MonthCalendarPicker({
    super.key,
    required this.month,
    required this.onMonthChanged,
    required this.selectedDates,
    required this.onDayTap,
    this.datesWithSchedule = const {},
    this.showLegend = true,
    this.allowPastSelection = false,
  });

  /// Cualquier fecha dentro del mes visible — se usan solo `year`/`month`, el día se ignora.
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  /// Fechas seleccionadas, normalizadas a medianoche (ver [dateOnly]).
  final Set<DateTime> selectedDates;

  /// Se invoca solo para días interactuables (no pasados).
  final ValueChanged<DateTime> onDayTap;

  /// Fechas que ya tienen un horario configurado (badge de reloj superpuesto, §7.5/§7.5bis).
  final Set<DateTime> datesWithSchedule;
  final bool showLegend;

  /// Si es `true`, las fechas pasadas se pueden elegir igual (se tratan como `elegible`, sin el
  /// estilo atenuado de `pasada`). Este widget se diseñó originalmente para disponibilidad
  /// (siempre fechas futuras, ver Gestión de Horarios) — `allowPastSelection` lo habilita también
  /// para elegir una fecha pasada real, ej. fecha de nacimiento (Ficha de Paciente, HU-20). Por
  /// defecto `false`: no cambia el comportamiento ya existente de ningún llamador actual.
  final bool allowPastSelection;

  /// Normaliza una fecha a medianoche local — usar siempre antes de agregar a `selectedDates`
  /// o comparar, para que la igualdad de `DateTime` funcione de forma consistente.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final today = dateOnly(DateTime.now());
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Dart: DateTime.weekday es lunes=1..domingo=7; %7 lo convierte a un offset domingo-primero
    // (domingo=0..sábado=6), que es exactamente el índice de columna que necesita el grid.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final monthLabel = _capitalize(DateFormat('MMMM yyyy', 'es').format(firstOfMonth));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: colors.textPrimary,
              tooltip: 'Mes anterior',
              onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1, 1)),
            ),
            Text(monthLabel, style: AppTypography.sectionTitle(context)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: colors.textPrimary,
              tooltip: 'Mes siguiente',
              onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1, 1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in _diasSemana)
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1,
          children: [
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              _DayCell(
                date: DateTime(month.year, month.month, day),
                today: today,
                selected: selectedDates.contains(DateTime(month.year, month.month, day)),
                hasSchedule: datesWithSchedule.contains(DateTime(month.year, month.month, day)),
                allowPastSelection: allowPastSelection,
                onTap: onDayTap,
              ),
          ],
        ),
        if (showLegend) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.base,
            runSpacing: AppSpacing.xs,
            children: [
              _LegendItem(color: colors.primary, filled: true, label: 'Seleccionada'),
              _LegendItem(color: colors.primaryContainer, filled: false, label: 'Elegible'),
              _LegendItem(color: colors.warning.base, filled: false, label: 'Hoy'),
              _LegendItem(color: colors.textDisabled, filled: true, label: 'Pasada'),
            ],
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.selected,
    required this.hasSchedule,
    required this.onTap,
    this.allowPastSelection = false,
  });

  final DateTime date;
  final DateTime today;
  final bool selected;
  final bool hasSchedule;
  final bool allowPastSelection;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isPast = date.isBefore(today) && !allowPastSelection;
    final isToday = date == today;

    final CalendarDayState state = selected
        ? CalendarDayState.seleccionada
        : isPast
            ? CalendarDayState.pasada
            : isToday
                ? CalendarDayState.hoy
                : CalendarDayState.elegible;

    Color? fill;
    Color textColor = colors.textPrimary;
    Border? border;
    switch (state) {
      case CalendarDayState.seleccionada:
        fill = colors.primary;
        textColor = colors.onPrimary;
        break;
      case CalendarDayState.elegible:
        border = Border.all(color: colors.primaryContainer, width: 1.5);
        break;
      case CalendarDayState.hoy:
        border = Border.all(color: colors.warning.base, width: 2);
        break;
      case CalendarDayState.pasada:
        textColor = colors.textDisabled;
        break;
    }

    final cell = Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: border),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Text(
            '${date.day}',
            style: AppTypography.body(context).copyWith(
                  color: textColor,
                  fontWeight:
                      state == CalendarDayState.seleccionada || state == CalendarDayState.hoy
                          ? FontWeight.bold
                          : FontWeight.normal,
                ),
          ),
          if (hasSchedule)
            Positioned(
              bottom: -2,
              right: 6,
              child: Icon(Icons.schedule, size: 10, color: selected ? colors.onPrimary : colors.primary),
            ),
        ],
      ),
    );

    return Semantics(
      label: '${date.day} de ${DateFormat('MMMM', 'es').format(date)}'
          '${hasSchedule ? ', con horario configurado' : ''}',
      button: !isPast,
      selected: selected,
      excludeSemantics: true,
      child: isPast
          ? cell
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onTap(date),
              child: cell,
            ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.filled, required this.label});

  final Color color;
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : null,
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.caption(context)),
      ],
    );
  }
}
