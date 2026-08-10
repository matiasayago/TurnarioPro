import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../state/sesion.dart';
import '../../theme/app_colors.dart';
import '../../widgets/widgets.dart';
import 'excepciones_screen.dart';

/// HU-06: agenda semanal del profesional. Ya no es una pestaña raíz del bottom nav — se accede
/// desde el botón "Ver agenda >" del Dashboard (`mapa-pantallas.md` §4/§5.3/§5.2bis). La
/// navegación a Disponibilidad/Clientes/Servicios que antes vivía acá como bottom nav propio se
/// reemplazó por el `AppBottomNavigationBar` de 6 ítems del `ProfesionalShell` — esta pantalla
/// conserva únicamente la acción "Bloquear rango" (§5.3), que abre Excepciones (HU-15) tal como
/// ya describía el wireframe.
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
    final onPrimary = AppColors.of(context).onPrimary;
    return Scaffold(
      appBar: AppHeader(
        title: 'Agenda semanal',
        showBackButton: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExcepcionesScreen())),
            child: Text('Bloquear rango', style: TextStyle(color: onPrimary)),
          ),
        ],
      ),
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
    );
  }
}
