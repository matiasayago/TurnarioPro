import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'detalle_negocio_screen.dart';
import 'mis_turnos_screen.dart';

/// HU-00b / CU3: el cliente descubre negocios disponibles en la plataforma (multi-tenant, D1).
class BuscarNegociosScreen extends StatefulWidget {
  const BuscarNegociosScreen({super.key});

  @override
  State<BuscarNegociosScreen> createState() => _BuscarNegociosScreenState();
}

class _BuscarNegociosScreenState extends State<BuscarNegociosScreen> {
  late Future<List<dynamic>> _negocios;

  @override
  void initState() {
    super.initState();
    _negocios = context.read<Sesion>().api.getList('/negocios');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Negocios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_note),
            tooltip: 'Mis turnos',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MisTurnosScreen())),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _negocios,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final negocios = snapshot.data!;
          if (negocios.isEmpty) return const Center(child: Text('Todavía no hay negocios cargados.'));
          return ListView.builder(
            itemCount: negocios.length,
            itemBuilder: (context, i) {
              final n = negocios[i] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(n['nombre'] as String),
                subtitle: Text([n['rubro'], n['ubicacion']].whereType<String>().join(' · ')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DetalleNegocioScreen(negocioId: n['id'] as String, nombreNegocio: n['nombre'] as String)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
