import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'elegir_profesional_screen.dart';

/// HU-07: el cliente elige un servicio dentro del negocio ya seleccionado.
class DetalleNegocioScreen extends StatefulWidget {
  const DetalleNegocioScreen({super.key, required this.negocioId, required this.nombreNegocio});

  final String negocioId;
  final String nombreNegocio;

  @override
  State<DetalleNegocioScreen> createState() => _DetalleNegocioScreenState();
}

class _DetalleNegocioScreenState extends State<DetalleNegocioScreen> {
  late Future<List<dynamic>> _servicios;

  @override
  void initState() {
    super.initState();
    _servicios = context.read<Sesion>().api.getList('/negocios/${widget.negocioId}/servicios');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombreNegocio)),
      body: FutureBuilder<List<dynamic>>(
        future: _servicios,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final servicios = snapshot.data!;
          if (servicios.isEmpty) return const Center(child: Text('Este negocio todavía no cargó servicios.'));
          return ListView.builder(
            itemCount: servicios.length,
            itemBuilder: (context, i) {
              final s = servicios[i] as Map<String, dynamic>;
              return ListTile(
                title: Text(s['nombre'] as String),
                subtitle: Text('${s['duracion_min']} min · \$${s['precio_referencia'] ?? '-'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ElegirProfesionalScreen(
                      negocioId: widget.negocioId,
                      servicioId: s['id'] as String,
                      servicioNombre: s['nombre'] as String,
                    ),
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
