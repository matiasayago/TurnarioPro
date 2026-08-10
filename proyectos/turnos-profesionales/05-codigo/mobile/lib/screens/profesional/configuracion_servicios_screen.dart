import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';

/// HU-04b: el profesional configura, por servicio, si requiere seña para reservar (D2/RN10).
/// (El selector de servicio_id se simplifica a un campo de texto en este slice — misma
/// simplificación deliberada que `gestion_horarios_screen.dart`, que reemplazó a la antigua
/// `definir_disponibilidad_screen.dart`.)
class ConfiguracionServiciosScreen extends StatefulWidget {
  const ConfiguracionServiciosScreen({super.key});

  @override
  State<ConfiguracionServiciosScreen> createState() => _ConfiguracionServiciosScreenState();
}

class _ConfiguracionServiciosScreenState extends State<ConfiguracionServiciosScreen> {
  final _servicioIdCtrl = TextEditingController();
  final _montoSenaCtrl = TextEditingController();
  bool _requiereSena = false;
  bool _guardando = false;
  String? _mensaje;

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _mensaje = null;
    });
    final sesion = context.read<Sesion>();
    try {
      await sesion.api.post('/profesionales/${sesion.profesionalId}/servicios', {
        'servicio_id': _servicioIdCtrl.text.trim(),
        'requiere_sena': _requiereSena,
        'monto_sena': _requiereSena ? double.tryParse(_montoSenaCtrl.text) : null,
      });
      setState(() => _mensaje = 'Configuración guardada.');
    } catch (e) {
      setState(() => _mensaje = e.toString());
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración de servicios')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _servicioIdCtrl, decoration: const InputDecoration(labelText: 'ID del servicio')),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Requiere seña para reservar'),
              subtitle: const Text('Configurable por vos, no es una regla global del negocio (D2)'),
              value: _requiereSena,
              onChanged: (v) => setState(() => _requiereSena = v),
            ),
            if (_requiereSena)
              TextField(
                controller: _montoSenaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monto de la seña'),
              ),
            const SizedBox(height: 24),
            if (_mensaje != null) Text(_mensaje!),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando ? const CircularProgressIndicator() : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
