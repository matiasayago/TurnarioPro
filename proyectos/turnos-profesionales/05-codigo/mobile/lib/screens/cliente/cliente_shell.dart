import 'package:flutter/material.dart';

import '../../widgets/widgets.dart';
import '../profesional/notificaciones_screen.dart';
import 'buscar_negocios_screen.dart';
import 'configuracion_cliente_screen.dart';
import 'mis_turnos_screen.dart';

// Índice de la pestaña "Buscar" del bottom nav de Cliente (orden real, ver `screens` en build()
// más abajo) — con nombre para no repetir un número mágico en el callback que le pasamos a
// `MisTurnosScreen` (ver [_ClienteShellState._irATab]), mismo criterio que
// `profesional/profesional_shell.dart`. Es el único índice que algún llamador necesita
// referenciar hoy — Notificaciones/Configuración no lo necesitan (nada salta a ellas
// programáticamente todavía).
const int _tabBuscar = 0;

/// Shell de navegación del lado Cliente: dueño del `AppBottomNavigationBar` de 4 ítems (Buscar,
/// Mis Turnos, Notificaciones, Configuración — `mapa-pantallas.md` §3, `sistema-diseno.md`
/// §7.6.2) y de un `IndexedStack` que mantiene vivo el estado de cada pestaña al cambiar entre
/// ellas — mismo patrón que `ProfesionalShell` (ver ese archivo, `screens/profesional/`).
/// Reemplaza a `BuscarNegociosScreen` como punto de entrada del rol Cliente en `main.dart`: antes
/// era la única pantalla raíz del lado Cliente (sin forma de navegar a otra sección salvo el
/// flujo lineal de reserva), ahora es una pestaña más dentro de este shell.
///
/// Buscar (HU-00b) y Mis Turnos (HU-12/HU-13) reusan las pantallas ya existentes sin cambios de
/// contenido. Notificaciones reusa `NotificacionesScreen`
/// (`screens/profesional/notificaciones_screen.dart`) TAL CUAL, import cross-carpeta — mismo
/// criterio que ya usa esta app para `ConfiguracionConsultorioScreen`, compartida entre
/// Profesional y Administrador (`administrador/administrador_shell.dart`). Es seguro reusarla sin
/// cambios: los 5 endpoints que toca (`routes/notificaciones.ts`, bandeja + configuración
/// granular) usan `requireAuth()` sin restricción de rol, y la pantalla no tiene ninguna
/// referencia a rol adentro. Configuración usa una pantalla propia
/// (`configuracion_cliente_screen.dart`, mismo patrón visual que `ConfiguracionScreen` de
/// Profesional, sin las secciones que no aplican a un cliente) — ver el doc-comment de esa clase
/// para el detalle completo de las diferencias.
///
/// A diferencia de la versión anterior de este archivo, `MisTurnosScreen` SÍ necesita ahora un
/// callback cross-tab (`onIrABuscar`) — mismo mecanismo exacto que `onIrAHorarios`/
/// `onIrAPacientes` en `ProfesionalShell`/`ConfiguracionScreen` (Profesional): salta a la pestaña
/// "Buscar" (índice [_tabBuscar]) dentro de este mismo `IndexedStack` en vez de empujar una
/// segunda instancia de `BuscarNegociosScreen` con `Navigator.push`, que duplicaría la pantalla
/// por encima del shell y taparía la bottom nav (ver el doc-comment de
/// `buscar_negocios_screen.dart` sobre por qué se sacó un atajo similar en el pasado). Por eso la
/// lista de pantallas de `build()` sigue sin ser `const` a nivel de lista (cada pantalla sigue
/// siendo `const` por separado salvo `MisTurnosScreen`): necesita los callbacks de ESTA instancia
/// de `_ClienteShellState`.
class ClienteShell extends StatefulWidget {
  const ClienteShell({super.key});

  @override
  State<ClienteShell> createState() => _ClienteShellState();
}

class _ClienteShellState extends State<ClienteShell> {
  int _index = _tabBuscar;

  void _irATab(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      BuscarNegociosScreen(onTurnoConfirmado: () => _irATab(1)), // Task #115: cambiar a "Mis Turnos"
      MisTurnosScreen(onIrABuscar: () => _irATab(_tabBuscar)),
      const NotificacionesScreen(),
      const ConfiguracionClienteScreen(),
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
