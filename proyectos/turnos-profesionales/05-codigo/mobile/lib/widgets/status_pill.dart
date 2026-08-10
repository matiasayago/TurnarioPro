import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Estados de turno (§3.4). El color de cada uno se resuelve internamente en [StatusPill],
/// nunca en la pantalla que lo usa.
enum TurnoEstado { porConfirmar, programada, confirmada, cancelada, completada }

/// Estados de paciente (§3.4).
enum PacienteEstado { activo, inactivo }

/// Convierte el `estado` crudo que devuelve la API (`estado_turno` de la base de datos:
/// `pendiente_de_pago` | `confirmado` | `cancelado` | `reprogramado`) al estado semántico de
/// diseño. `reprogramado` no tiene mapeo 1:1 documentado en §3.4 (el turno viejo queda
/// archivado, no se lista en las pantallas que usan `GET /profesionales/:id/turnos`, que ya
/// filtra por `pendiente_de_pago`/`confirmado`) — se resuelve como `completada` (gris/neutral)
/// por ser la opción menos alarmante para un valor inesperado, sin bloquear el render.
TurnoEstado turnoEstadoFromApi(String estadoApi) {
  switch (estadoApi) {
    case 'pendiente_de_pago':
      return TurnoEstado.porConfirmar;
    case 'confirmado':
      return TurnoEstado.confirmada;
    case 'cancelado':
      return TurnoEstado.cancelada;
    default:
      return TurnoEstado.completada;
  }
}

enum _PillKind { success, warning, danger, neutral }

/// §7.2 — píldora de estado, fondo pastel + texto bold en el color base del estado (tabla de
/// mapeo §3.4). Corregida en §7.10bis: además del fondo pastel, lleva borde del color base y un
/// punto de color antes del texto — ningún estado se comunica solo por color (§9): siempre hay
/// texto.
class StatusPill extends StatelessWidget {
  // CORRECCIÓN (2026-08-10, confirmado en el primer run real de CI): no puede ser `const` — un
  // `switch` usado como expresión (Dart 3 pattern matching) todavía no es una "expresión
  // constante" válida para el analizador de Dart, a diferencia del operador ternario `?:` que sí
  // lo es. `flutter analyze` lo rechazaba con "Invalid constant value" en las 4 ramas de abajo.
  // Sin impacto real: el único call site (`dashboard_screen.dart`) ya invocaba este constructor
  // sin `const`.
  StatusPill.turno(TurnoEstado estado, {super.key})
      : _label = switch (estado) {
          TurnoEstado.porConfirmar => 'Por confirmar',
          TurnoEstado.programada => 'Programada',
          TurnoEstado.confirmada => 'Confirmada',
          TurnoEstado.cancelada => 'Cancelada',
          TurnoEstado.completada => 'Completada',
        },
        _kind = switch (estado) {
          TurnoEstado.porConfirmar => _PillKind.warning,
          TurnoEstado.programada => _PillKind.warning,
          TurnoEstado.confirmada => _PillKind.success,
          TurnoEstado.cancelada => _PillKind.danger,
          TurnoEstado.completada => _PillKind.neutral,
        };

  // Mismo motivo que StatusPill.turno de arriba — no puede ser `const` por el switch-expression.
  StatusPill.paciente(PacienteEstado estado, {super.key})
      : _label = switch (estado) {
          PacienteEstado.activo => 'Activo',
          PacienteEstado.inactivo => 'Inactivo',
        },
        _kind = switch (estado) {
          PacienteEstado.activo => _PillKind.success,
          PacienteEstado.inactivo => _PillKind.danger,
        };

  final String _label;
  final _PillKind _kind;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final state = switch (_kind) {
      _PillKind.success => colors.success,
      _PillKind.warning => colors.warning,
      _PillKind.danger => colors.danger,
      _PillKind.neutral => colors.neutral,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: state.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: state.base, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: state.base, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _label,
            style: AppTypography.caption(context).copyWith(color: state.base, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
