import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';

/// HU-11: historial de visitas de un cliente — D3/RN7: el backend ya filtra por
/// profesional_id del JWT, así que esta pantalla nunca puede mostrar visitas de otro
/// profesional aunque lo intentara (la privacidad se garantiza en la API, no en la UI).
class HistorialVisitasScreen extends StatefulWidget {
  const HistorialVisitasScreen({super.key, required this.clienteId, required this.clienteNombre});

  final String clienteId;
  final String clienteNombre;

  @override
  State<HistorialVisitasScreen> createState() => _HistorialVisitasScreenState();
}

class _HistorialVisitasScreenState extends State<HistorialVisitasScreen> {
  late Future<List<dynamic>> _historial;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _historial = sesion.api.getList('/clientes/${widget.clienteId}/historial');
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('d MMM yyyy · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: Text(widget.clienteNombre)),
      body: FutureBuilder<List<dynamic>>(
        future: _historial,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final visitas = snapshot.data!;
          if (visitas.isEmpty) return const Center(child: Text('Sin visitas registradas todavía.'));
          return ListView.builder(
            itemCount: visitas.length,
            itemBuilder: (context, i) {
              final v = visitas[i] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(v['servicio'] as String),
                subtitle: Text(formato.format(DateTime.parse(v['inicio'] as String).toLocal())),
                trailing: Text(v['estado'] as String),
              );
            },
          );
        },
      ),
    );
  }
}
