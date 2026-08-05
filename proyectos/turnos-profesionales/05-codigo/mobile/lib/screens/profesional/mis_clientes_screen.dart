import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'historial_visitas_screen.dart';

/// HU-10: listado de clientes atendidos por el profesional autenticado.
class MisClientesScreen extends StatefulWidget {
  const MisClientesScreen({super.key});

  @override
  State<MisClientesScreen> createState() => _MisClientesScreenState();
}

class _MisClientesScreenState extends State<MisClientesScreen> {
  late Future<List<dynamic>> _clientes;

  @override
  void initState() {
    super.initState();
    final sesion = context.read<Sesion>();
    _clientes = sesion.api.getList('/profesionales/${sesion.profesionalId}/clientes');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis clientes')),
      body: FutureBuilder<List<dynamic>>(
        future: _clientes,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final clientes = snapshot.data!;
          if (clientes.isEmpty) return const Center(child: Text('Todavía no atendiste a ningún cliente.'));
          return ListView.builder(
            itemCount: clientes.length,
            itemBuilder: (context, i) {
              final c = clientes[i] as Map<String, dynamic>;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c['nombre'] as String),
                subtitle: Text(c['email'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistorialVisitasScreen(clienteId: c['id'] as String, clienteNombre: c['nombre'] as String),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
