import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'definir_disponibilidad_screen.dart';
import 'excepciones_screen.dart';
import 'mis_clientes_screen.dart';
import 'configuracion_servicios_screen.dart';

/// HU-06: agenda del profesional (turnos + acceso a disponibilidad/excepciones/clientes) —
/// ver wireframe en docs/04-diseno/mapa-pantallas.md §5.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late Future<List<dynamic>> _turnos;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _turnos = sesion.api.getList('/profesionales/${sesion.profesionalId}/turnos');
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Mi agenda')),
      body: FutureBuilder<List<dynamic>>(
        future: _turnos,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final turnos = snapshot.data!;
          if (turnos.isEmpty) return const Center(child: Text('No tenés turnos próximos.'));
          return ListView.builder(
            itemCount: turnos.length,
            itemBuilder: (context, i) {
              final t = turnos[i] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.event),
                title: Text('${t['servicio']} · ${t['cliente']}'),
                subtitle: Text(formato.format(DateTime.parse(t['inicio'] as String).toLocal())),
                trailing: Text(t['estado'] as String, style: Theme.of(context).textTheme.labelSmall),
              );
            },
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        destinations: const [
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Disponibilidad'),
          NavigationDestination(icon: Icon(Icons.block), label: 'Excepciones'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Servicios'),
        ],
        onDestinationSelected: (i) {
          final destinos = [
            const DefinirDisponibilidadScreen(),
            const ExcepcionesScreen(),
            const MisClientesScreen(),
            const ConfiguracionServiciosScreen(),
          ];
          Navigator.push(context, MaterialPageRoute(builder: (_) => destinos[i]));
        },
      ),
    );
  }
}
