import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'confirmar_turno_screen.dart';

/// HU-09: horarios disponibles del profesional para el servicio elegido. Si no hay en el
/// rango consultado, el backend ya devuelve el próximo disponible (D5, sin lista de espera)
/// — ver wireframe conceptual en docs/04-diseno/mapa-pantallas.md §4.
class HorariosDisponiblesScreen extends StatefulWidget {
  const HorariosDisponiblesScreen({
    super.key,
    required this.profesionalId,
    required this.profesionalNombre,
    required this.servicioId,
  });

  final String profesionalId;
  final String profesionalNombre;
  final String servicioId;

  @override
  State<HorariosDisponiblesScreen> createState() => _HorariosDisponiblesScreenState();
}

class _HorariosDisponiblesScreenState extends State<HorariosDisponiblesScreen> {
  late Future<Map<String, dynamic>> _slots;

  @override
  void initState() {
    super.initState();
    _slots = context.read<Sesion>().api.getMap(
      '/profesionales/${widget.profesionalId}/slots?servicio_id=${widget.servicioId}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: Text(widget.profesionalNombre)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _slots,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final slots = (snapshot.data!['slots'] as List).cast<String>();
          final proximo = snapshot.data!['proximo_disponible'] as String?;

          if (slots.isEmpty) {
            return const Center(child: Text('No hay horarios disponibles próximamente.'));
          }
          return Column(
            children: [
              if (proximo != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Text('Próximo disponible: ${formato.format(DateTime.parse(proximo).toLocal())}'),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: slots.length,
                  itemBuilder: (context, i) {
                    final inicio = slots[i];
                    return ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(formato.format(DateTime.parse(inicio).toLocal())),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConfirmarTurnoScreen(
                            profesionalId: widget.profesionalId,
                            profesionalNombre: widget.profesionalNombre,
                            servicioId: widget.servicioId,
                            inicio: inicio,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
