import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../api_client.dart';
import '../../state/sesion.dart';

/// HU-13: elegir un nuevo horario para un turno propio (mismo profesional/servicio, CU5).
/// Reutiliza /profesionales/{id}/slots para listar horarios y PATCH /turnos/{id}/reprogramar
/// para confirmar — el backend aplica la misma garantía anti-doble-reserva que en la reserva
/// original (ver backend/src/routes/turnos.ts).
class ReprogramarTurnoScreen extends StatefulWidget {
  const ReprogramarTurnoScreen({
    super.key,
    required this.turnoId,
    required this.profesionalId,
    required this.servicioId,
  });

  final String turnoId;
  final String profesionalId;
  final String servicioId;

  @override
  State<ReprogramarTurnoScreen> createState() => _ReprogramarTurnoScreenState();
}

class _ReprogramarTurnoScreenState extends State<ReprogramarTurnoScreen> {
  late Future<Map<String, dynamic>> _slots;
  bool _reprogramando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _slots = context.read<Sesion>().api.getMap(
      '/profesionales/${widget.profesionalId}/slots?servicio_id=${widget.servicioId}',
    );
  }

  Future<void> _reprogramar(String nuevoInicio) async {
    setState(() {
      _reprogramando = true;
      _error = null;
    });
    try {
      await context.read<Sesion>().api.patch('/turnos/${widget.turnoId}/reprogramar', {
        'nuevo_inicio': nuevoInicio,
      });
      if (!mounted) return;
      Navigator.pop(context, true); // true = se reprogramó, la pantalla anterior refresca
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 409
          ? 'Ese horario ya no está disponible — alguien más lo tomó. Elegí otro.'
          : e.message);
    } finally {
      if (mounted) setState(() => _reprogramando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Elegir nuevo horario')),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Text(_error!),
            ),
          if (_reprogramando) const LinearProgressIndicator(),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _slots,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final slots = (snapshot.data!['slots'] as List).cast<String>();
                if (slots.isEmpty) return const Center(child: Text('No hay otros horarios disponibles.'));
                return ListView.builder(
                  itemCount: slots.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(formato.format(DateTime.parse(slots[i]).toLocal())),
                    enabled: !_reprogramando,
                    onTap: () => _reprogramar(slots[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
