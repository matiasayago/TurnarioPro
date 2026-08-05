import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import 'reprogramar_turno_screen.dart';

/// HU-12/HU-13: turnos del cliente autenticado, con acciones de cancelar y reprogramar
/// (RN8 — la ventana mínima la valida el backend; acá solo se muestra el resultado).
class MisTurnosScreen extends StatefulWidget {
  const MisTurnosScreen({super.key});

  @override
  State<MisTurnosScreen> createState() => _MisTurnosScreenState();
}

class _MisTurnosScreenState extends State<MisTurnosScreen> {
  late Future<List<dynamic>> _turnos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    _turnos = context.read<Sesion>().api.getList('/turnos/mios');
  }

  Future<void> _cancelar(String turnoId) async {
    final api = context.read<Sesion>().api;
    try {
      await api.patch('/turnos/$turnoId/cancelar');
      setState(_cargar);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reprogramar(Map<String, dynamic> turno) async {
    final reprogramado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReprogramarTurnoScreen(
          turnoId: turno['id'] as String,
          profesionalId: turno['profesional_id'] as String,
          servicioId: turno['servicio_id'] as String,
        ),
      ),
    );
    if (reprogramado == true) setState(_cargar);
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('EEE d MMM · HH:mm', 'es');
    return Scaffold(
      appBar: AppBar(title: const Text('Mis turnos')),
      body: FutureBuilder<List<dynamic>>(
        future: _turnos,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final turnos = snapshot.data!;
          if (turnos.isEmpty) return const Center(child: Text('Todavía no reservaste ningún turno.'));
          return ListView.builder(
            itemCount: turnos.length,
            itemBuilder: (context, i) {
              final t = turnos[i] as Map<String, dynamic>;
              final gestionable = t['estado'] == 'confirmado' || t['estado'] == 'pendiente_de_pago';
              return ListTile(
                title: Text(formato.format(DateTime.parse(t['inicio'] as String).toLocal())),
                subtitle: Text('Estado: ${t['estado']}'),
                trailing: gestionable
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(onPressed: () => _reprogramar(t), child: const Text('Reprogramar')),
                          TextButton(onPressed: () => _cancelar(t['id'] as String), child: const Text('Cancelar')),
                        ],
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
