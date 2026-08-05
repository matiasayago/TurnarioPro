import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'horarios_disponibles_screen.dart';

/// HU-08: el cliente elige un profesional entre los que ofrecen el servicio elegido.
class ElegirProfesionalScreen extends StatefulWidget {
  const ElegirProfesionalScreen({
    super.key,
    required this.negocioId,
    required this.servicioId,
    required this.servicioNombre,
  });

  final String negocioId;
  final String servicioId;
  final String servicioNombre;

  @override
  State<ElegirProfesionalScreen> createState() => _ElegirProfesionalScreenState();
}

class _ElegirProfesionalScreenState extends State<ElegirProfesionalScreen> {
  late Future<List<dynamic>> _profesionales;

  @override
  void initState() {
    super.initState();
    _profesionales = context.read<Sesion>().api.getList(
          '/negocios/${widget.negocioId}/servicios/${widget.servicioId}/profesionales',
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.servicioNombre)),
      body: FutureBuilder<List<dynamic>>(
        future: _profesionales,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final profesionales = snapshot.data!;
          if (profesionales.isEmpty) {
            return const Center(child: Text('Ningún profesional ofrece este servicio todavía.'));
          }
          return ListView.builder(
            itemCount: profesionales.length,
            itemBuilder: (context, i) {
              final p = profesionales[i] as Map<String, dynamic>;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(p['nombre'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HorariosDisponiblesScreen(
                      profesionalId: p['id'] as String,
                      profesionalNombre: p['nombre'] as String,
                      servicioId: widget.servicioId,
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
