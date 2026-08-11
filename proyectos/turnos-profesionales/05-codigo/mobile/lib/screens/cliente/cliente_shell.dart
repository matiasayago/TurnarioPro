import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import 'buscar_negocios_screen.dart';
import 'mis_turnos_screen.dart';

/// Shell de navegación del lado Cliente: dueño del `AppBottomNavigationBar` de 4 ítems (Buscar,
/// Mis Turnos, Notificaciones, Configuración — `mapa-pantallas.md` §3, `sistema-diseno.md`
/// §7.6.2) y de un `IndexedStack` que mantiene vivo el estado de cada pestaña al cambiar entre
/// ellas — mismo patrón que `ProfesionalShell` (ver ese archivo, `screens/profesional/`).
/// Reemplaza a `BuscarNegociosScreen` como punto de entrada del rol Cliente en `main.dart`: antes
/// era la única pantalla raíz del lado Cliente (sin forma de navegar a otra sección salvo el
/// flujo lineal de reserva), ahora es una pestaña más dentro de este shell.
///
/// Buscar (HU-00b) y Mis Turnos (HU-12/HU-13) reusan las pantallas ya existentes sin cambios de
/// contenido. Notificaciones y Configuración quedan como `ProximamenteScreen`: ninguna de las dos
/// tiene backend real todavía (Notificaciones no tiene endpoint; Configuración de Cliente no fue
/// pedida en esta ronda) — mismo criterio que ya usa `ProfesionalShell` para WhatsApp/
/// Notificaciones.
///
/// A diferencia de `ConfiguracionScreen` (Profesional), acá ninguna pestaña necesita todavía un
/// callback para saltar a otra pestaña de esta instancia (no hay equivalente cliente de
/// `onIrAHorarios`/`onIrAPacientes` en este alcance) — aun así la lista se arma igual que en
/// `ProfesionalShell` (no `const` a nivel de lista, cada pantalla `const` por separado) para
/// que agregar ese tipo de callback más adelante sea el mismo cambio mínimo en ambos shells.
class ClienteShell extends StatefulWidget {
  const ClienteShell({super.key});

  @override
  State<ClienteShell> createState() => _ClienteShellState();
}

class _ClienteShellState extends State<ClienteShell> {
  int _index = 0;

  void _irATab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const BuscarNegociosScreen(),
      const MisTurnosScreen(),
      const ProximamenteScreen(titulo: 'Notificaciones', emoji: '🔔'),
      const ProximamenteScreen(titulo: 'Configuración', emoji: '⚙️'),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: AppBottomNavigationBar(
        items: AppBottomNavigationBar.clienteItems,
        currentIndex: _index,
        onTap: _irATab,
      ),
    );
  }
}
