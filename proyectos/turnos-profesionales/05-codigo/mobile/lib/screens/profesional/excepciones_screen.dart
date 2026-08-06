import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';

/// HU-15: bloqueo puntual de agenda (feriado/licencia) — RN5/RN6: si hay turnos ya
/// reservados en el rango, el backend avisa antes de que el bloqueo se dé por definitivo.
class ExcepcionesScreen extends StatefulWidget {
  const ExcepcionesScreen({super.key});

  @override
  State<ExcepcionesScreen> createState() => _ExcepcionesScreenState();
}

class _ExcepcionesScreenState extends State<ExcepcionesScreen> {
  DateTimeRange? _rango;
  final _motivoCtrl = TextEditingController();
  bool _guardando = false;
  String? _mensaje;

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: ahora,
      lastDate: ahora.add(const Duration(days: 365)),
    );
    if (rango != null) setState(() => _rango = rango);
  }

  Future<void> _guardar() async {
    if (_rango == null) return;
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      final resp = await sesion.api.post('/profesionales/${sesion.profesionalId}/excepciones', {
        'inicio': _rango!.start.toIso8601String(),
        'fin': _rango!.end.toIso8601String(),
        'motivo': _motivoCtrl.text.trim(),
      });
      setState(() => _mensaje = resp['aviso'] as String? ?? 'Bloqueo registrado.');
    } catch (e) {
      setState(() => _mensaje = e.toString());
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excepciones de disponibilidad')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: _elegirRango,
              child: Text(_rango == null ? 'Elegir rango a bloquear' : '${_rango!.start} → ${_rango!.end}'),
            ),
            const SizedBox(height: 16),
            TextField(controller: _motivoCtrl, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
            const SizedBox(height: 24),
            if (_mensaje != null)
              Container(
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                child: Text(_mensaje!),
              ),
            FilledButton(
              onPressed: _guardando || _rango == null ? null : _guardar,
              child: _guardando ? const CircularProgressIndicator() : const Text('Bloquear agenda'),
            ),
          ],
        ),
      ),
    );
  }
}
