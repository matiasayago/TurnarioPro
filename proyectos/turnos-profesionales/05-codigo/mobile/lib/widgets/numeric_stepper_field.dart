import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// §7.4bis — variante de glifo: `minusPlus` ("− valor +", duraciones/cantidades) o `chevron`
/// (▾/▴, valores de hora del día — ej. Tiempo de Descanso). Mismo comportamiento
/// (deshabilitar en el límite, valor central bold), solo cambian los íconos.
enum NumericStepperGlyph { minusPlus, chevron }

/// §7.4 — patrón "− valor +": dos botones a los lados de un valor central bold, con `min`,
/// `max`, `step` y sufijo de unidad opcional. Los botones se deshabilitan (no desaparecen) al
/// llegar a `min`/`max`.
class NumericStepperField extends StatelessWidget {
  const NumericStepperField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.unit,
    this.valueFormatter,
    this.glyph = NumericStepperGlyph.minusPlus,
    this.semanticLabel,
  });

  /// Label opcional a la izquierda (fila "Duración de Citas [ − ] 60 min [ + ]"). Si es `null`,
  /// el widget renderiza solo el cluster del stepper (útil para colocar dos steppers uno al
  /// lado del otro, ej. "Inicio"/"Fin" de Horarios por Defecto, con su propio label externo).
  final String? label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? unit;

  /// Formateador de valor a texto. Por defecto `'$value$unit'` — pasar [formatHHmm] (o un
  /// wrapper propio) para representar el valor como hora del día en vez de cantidad cruda.
  final String Function(int value)? valueFormatter;
  final NumericStepperGlyph glyph;
  final ValueChanged<int> onChanged;
  final String? semanticLabel;

  /// Formatea minutos-desde-medianoche como "HH:mm" — para usar este mismo widget con valores
  /// de hora del día (variante `chevron`, §7.4bis) sin duplicar la conversión en cada pantalla.
  static String formatHHmm(int minutesSinceMidnight) {
    final normalizado = minutesSinceMidnight % (24 * 60);
    final h = normalizado ~/ 60;
    final m = normalizado % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formattedValue() => valueFormatter != null ? valueFormatter!(value) : '$value${unit ?? ''}';

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final canDecrement = value - step >= min;
    final canIncrement = value + step <= max;
    final (minusIcon, plusIcon) = switch (glyph) {
      NumericStepperGlyph.minusPlus => (Icons.remove, Icons.add),
      NumericStepperGlyph.chevron => (Icons.keyboard_arrow_down, Icons.keyboard_arrow_up),
    };
    final formatted = _formattedValue();

    // Semántica de "adjustable" (increase/decrease + value hablado) en vez de exponer los dos
    // botones internos por separado — patrón estándar de Flutter para steppers/sliders.
    final stepper = Semantics(
      label: semanticLabel ?? (label ?? 'Valor'),
      value: formatted,
      onIncrease: canIncrement ? () => onChanged(value + step) : null,
      onDecrease: canDecrement ? () => onChanged(value - step) : null,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperGlyphButton(
              icon: minusIcon,
              enabled: canDecrement,
              onTap: canDecrement ? () => onChanged(value - step) : null,
            ),
            SizedBox(
              width: 64,
              child: Text(
                formatted,
                textAlign: TextAlign.center,
                style: AppTypography.body(context).copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary),
              ),
            ),
            _StepperGlyphButton(
              icon: plusIcon,
              enabled: canIncrement,
              onTap: canIncrement ? () => onChanged(value + step) : null,
            ),
          ],
        ),
      ),
    );

    if (label == null) return stepper;

    return Row(
      children: [
        Expanded(child: Text(label!, style: AppTypography.body(context))),
        stepper,
      ],
    );
  }
}

class _StepperGlyphButton extends StatelessWidget {
  const _StepperGlyphButton({required this.icon, required this.enabled, required this.onTap});

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // §9: área táctil mínima 44x44dp, aunque el círculo visual sea más chico (32dp).
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? colors.primaryContainer : colors.border.withValues(alpha: 0.5),
              ),
              child: Icon(icon, size: 18, color: enabled ? colors.primary : colors.textDisabled),
            ),
          ),
        ),
      ),
    );
  }
}
