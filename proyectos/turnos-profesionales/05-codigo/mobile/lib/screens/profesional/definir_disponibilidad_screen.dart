import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';

/// HU-05: el profesional define un bloque de disponibilidad recurrente por servicio.
/// (El selector de servicio_id se simplifica a un campo de texto en este slice; una versión
/// posterior lo reemplaza por un dropdown poblado desde /profesionales/{id}/servicios.)
class DefinirDisponibilidadScreen extends StatefulWidget {
  const DefinirDisponibilidadScreen({super.key});

  @override
  State<DefinirDisponibilidadScreen> createState() => _DefinirDisponibilidadScreenState();
}

class _DefinirDisponibilidadScreenState extends State<DefinirDisponibilidadScreen> {
  final _servicioIdCtrl = TextEditingController();
  int _diaSemana = 1; // 0=domingo .. 6=sábado (RN, ver DDL)
  TimeOfDay _horaInicio = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _horaFin = const TimeOfDay(hour: 18, minute: 0);
  bool _guardando = false;
  String? _mensaje;

  static const _dias = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/profesionales/${sesion.profesionalId}/disponibilidad', {
        'servicio_id': _servicioIdCtrl.text.trim(),
        'dia_semana': _diaSemana,
        'hora_inicio': '${_horaInicio.hour.toString().padLeft(2, '0')}:${_horaInicio.minute.toString().padLeft(2, '0')}',
        'hora_fin': '${_horaFin.hour.toString().padLeft(2, '0')}:${_horaFin.minute.toString().padLeft(2, '0')}',
      });
      setState(() => _mensaje = 'Bloque de disponibilidad guardado.');
    } catch (e) {
      setState(() => _mensaje = e.toString());
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Definir disponibilidad')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _servicioIdCtrl, decoration: const InputDecoration(labelText: 'ID del servicio')),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _diaSemana,
              decoration: const InputDecoration(labelText: 'Día de la semana'),
              items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(_dias[i]))],
              onChanged: (v) => setState(() => _diaSemana = v!),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Hora inicio'),
              trailing: Text(_horaInicio.format(context)),
              onTap: () async {
                final h = await showTimePicker(context: context, initialTime: _horaInicio);
                if (h != null) setState(() => _horaInicio = h);
              },
            ),
            ListTile(
              title: const Text('Hora fin'),
              trailing: Text(_horaFin.format(context)),
              onTap: () async {
                final h = await showTimePicker(context: context, initialTime: _horaFin);
                if (h != null) setState(() => _horaFin = h);
              },
            ),
            const SizedBox(height: 24),
            if (_mensaje != null) Text(_mensaje!),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando ? const CircularProgressIndicator() : const Text('Guardar bloque'),
            ),
          ],
        ),
      ),
    );
  }
}
