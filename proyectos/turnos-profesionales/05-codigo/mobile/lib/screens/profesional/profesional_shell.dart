import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import 'dashboard_screen.dart';
import 'gestion_horarios_screen.dart';
import 'proximamente_screen.dart';

/// Shell de navegación del lado Profesional: dueño del `AppBottomNavigationBar` de 6 ítems
/// (Dashboard, Horarios, Pacientes, WhatsApp, Notificaciones, Configuración —
/// `sistema-diseno.md` §7.6.1) y de un `IndexedStack` que mantiene vivo el estado de cada pestaña
/// al cambiar entre ellas. Reemplaza a `AgendaScreen` como punto de entrada del rol Profesional
/// en `main.dart` — "Agenda semanal completa" (HU-06) deja de ser una pantalla raíz del bottom
/// nav y pasa a accederse desde el botón "Ver agenda >" del Dashboard
/// (`mapa-pantallas.md` §4/§5.3).
///
/// Pacientes/WhatsApp/Notificaciones/Configuración quedan como placeholders simples en este
/// ciclo (ver `proximamente_screen.dart`) — a propósito no se reutiliza `MisClientesScreen`
/// (versión anterior y más simple de "Mis Clientes"/HU-10, todavía en `mis_clientes_screen.dart`)
/// para no mezclar el lenguaje visual viejo con el nuevo dentro del mismo shell; queda
/// disponible en el código para cuando se construya la versión rediseñada de "Gestión de
/// Pacientes" (HU-10+HU-19, `mapa-pantallas.md` §5.8bis).
class ProfesionalShell extends StatefulWidget {
  const ProfesionalShell({super.key});

  @override
  State<ProfesionalShell> createState() => _ProfesionalShellState();
}

class _ProfesionalShellState extends State<ProfesionalShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    DashboardScreen(),
    GestionHorariosScreen(),
    ProximamenteScreen(titulo: 'Pacientes', emoji: '🏥'),
    ProximamenteScreen(titulo: 'WhatsApp', emoji: '💬'),
    ProximamenteScreen(titulo: 'Notificaciones', emoji: '🔔'),
    ProximamenteScreen(titulo: 'Configuración', emoji: '⚙️'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNavigationBar(
        items: AppBottomNavigationBar.profesionalItems,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
