import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import 'configuracion_screen.dart';
import 'dashboard_screen.dart';
import 'gestion_horarios_screen.dart';
import 'gestion_pacientes_screen.dart';
import 'proximamente_screen.dart';

// Índices de pestaña del bottom nav de Profesional (orden real, ver `screens` en build() más
// abajo) — con nombre para no repetir números mágicos al cambiar de pestaña desde
// `ConfiguracionScreen` (ver [_ProfesionalShellState._irATab]). Solo se nombran las que algún
// llamador necesita referenciar por índice; WhatsApp/Notificaciones/Configuración no lo
// necesitan hoy (nada salta a ellas programáticamente todavía).
const int _tabDashboard = 0;
const int _tabHorarios = 1;
const int _tabPacientes = 2;

/// Shell de navegación del lado Profesional: dueño del `AppBottomNavigationBar` de 6 ítems
/// (Dashboard, Horarios, Pacientes, WhatsApp, Notificaciones, Configuración —
/// `sistema-diseno.md` §7.6.1) y de un `IndexedStack` que mantiene vivo el estado de cada pestaña
/// al cambiar entre ellas. Reemplaza a `AgendaScreen` como punto de entrada del rol Profesional
/// en `main.dart` — "Agenda semanal completa" (HU-06) deja de ser una pantalla raíz del bottom
/// nav y pasa a accederse desde el botón "Ver agenda >" del Dashboard
/// (`mapa-pantallas.md` §4/§5.3).
///
/// Pacientes usa la Gestión de Pacientes rediseñada (HU-10+HU-19, `mapa-pantallas.md` §5.8bis) y
/// Configuración el menú real (§5.11bis) — a propósito no se reutiliza `MisClientesScreen`
/// (versión anterior y más simple de "Mis Clientes"/HU-10, todavía en `mis_clientes_screen.dart`)
/// para no mezclar el lenguaje visual viejo con el nuevo dentro del mismo shell. WhatsApp y
/// Notificaciones siguen como placeholders (ver `proximamente_screen.dart`) — fuera de esta
/// ronda.
class ProfesionalShell extends StatefulWidget {
  const ProfesionalShell({super.key});

  @override
  State<ProfesionalShell> createState() => _ProfesionalShellState();
}

class _ProfesionalShellState extends State<ProfesionalShell> {
  int _index = _tabDashboard;

  void _irATab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    // Lista NO const (a diferencia de la versión anterior): `ConfiguracionScreen` necesita los
    // callbacks de cambio de pestaña de esta instancia. Esto no pierde el estado de cada pantalla
    // al cambiar de pestaña — `IndexedStack` mantiene montados a todos sus hijos en todo momento,
    // reconstruir esta lista en cada `build` no recrea sus `State`, solo sus `Widget` (misma
    // posición en el árbol = mismo `Element`/`State`, regla estándar de Flutter).
    final screens = <Widget>[
      const DashboardScreen(),
      const GestionHorariosScreen(),
      const GestionPacientesScreen(),
      const ProximamenteScreen(titulo: 'WhatsApp', emoji: '💬'),
      const ProximamenteScreen(titulo: 'Notificaciones', emoji: '🔔'),
      ConfiguracionScreen(
        onIrAHorarios: () => _irATab(_tabHorarios),
        onIrAPacientes: () => _irATab(_tabPacientes),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: AppBottomNavigationBar(
        items: AppBottomNavigationBar.profesionalItems,
        currentIndex: _index,
        onTap: _irATab,
      ),
    );
  }
}
