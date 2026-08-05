import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../state/sesion.dart';
import 'mis_turnos_screen.dart';

/// HU-09b: confirma la reserva. Si el profesional requiere seña para este servicio (D2/RN10),
/// el backend responde con `estado: pendiente_de_pago`; si no, queda `confirmado` directo.
/// Si otro cliente reservó el mismo horario primero, el backend responde 409 (RN2) — es el
/// caso de error más importante de esta pantalla, no un detalle secundario.
class ConfirmarTurnoScreen extends StatefulWidget {
  const ConfirmarTurnoScreen({
    super.key,
    required this.profesionalId,
    required this.profesionalNombre,
    required this.servicioId,
    required this.inicio,
  });

  final String profesionalId;
  final String profesionalNombre;
  final String servicioId;
  final String inicio;

  @override
  State<ConfirmarTurnoScreen> createState() => _ConfirmarTurnoScreenState();
}

class _ConfirmarTurnoScreenState extends State<ConfirmarTurnoScreen> {
  bool _reservando = false;
  String? _error;

  Future<void> _confirmar() async {
    setState(() {
      _reservando = true;
      _error = null;
    });
    try {
      final api = context.read<Sesion>().api;
      final turno = await api.post('/turnos', {
        'profesional_id': widget.profesionalId,
        'servicio_id': widget.servicioId,
        'inicio': widget.inicio,
      });

      if (!mounted) return;
      if (turno['requiere_pago'] == true) {
        // TODO: integrar checkout real (Mercado Pago) cuando Integraciones reemplace el Mock
        // del backend (ver backend/src/integraciones/pagos.ts) — este slice solo confirma.
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Seña requerida'),
            content: Text('Este turno requiere una seña de \$${turno['monto_sena']}. Completá el pago para confirmarlo.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MisTurnosScreen()),
        (route) => route.isFirst,
      );
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 409
          ? 'Ese horario ya no está disponible — alguien más lo reservó. Elegí otro horario.'
          : e.message);
    } finally {
      if (mounted) setState(() => _reservando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEEE d MMMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar turno')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.profesionalNombre, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(formato.format(DateTime.parse(widget.inicio).toLocal())),
            const SizedBox(height: 24),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const Spacer(),
            FilledButton(
              onPressed: _reservando ? null : _confirmar,
              child: _reservando ? const CircularProgressIndicator() : const Text('Confirmar turno'),
            ),
          ],
        ),
      ),
    );
  }
}
