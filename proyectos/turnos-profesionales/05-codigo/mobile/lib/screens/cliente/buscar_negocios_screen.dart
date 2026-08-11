import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'detalle_negocio_screen.dart';

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
    // Antes tenía un ícono de atajo a "Mis turnos" en el AppBar (única forma de llegar ahí
    // cuando esta pantalla era la raíz suelta del lado Cliente, sin bottom nav). Ahora que
    // "Mis Turnos" es una pestaña persistente de `ClienteShell`, ese atajo quedó redundante y,
    // peor, tapaba la bottom nav al empujar una pantalla completa por encima del shell — se
    // quita en vez de dejarlo (ver nota de la tarea de navegación del Cliente).
    return Scaffold(
      appBar: AppBar(title: const Text('Negocios')),
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
