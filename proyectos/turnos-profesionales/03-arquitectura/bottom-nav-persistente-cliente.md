# Bottom Nav Persistente en Cliente — Decisión de Arquitectura

**Rol:** Arquitecto
**Fase:** 5 — Desarrollo (corrección arquitectónica sobre app ya en producción)
**Referencia:** Task #115 ("Arquitectura — Bottom nav persistente en Cliente")
**Pedido del CEO (textual):** "los botones de navegacion deben estar visibles en todas las pantallas"
**Entradas:** Director General IA (encargo), código real de `05-codigo/mobile/lib/screens/cliente/`,
`main.dart`, `03-arquitectura/lineamientos-tecnicos.md`, `memory/proyectos/turnos-profesionales/decisiones.md`
**Alcance de este documento:** diseño únicamente — **no se modificó código** en esta tarea. La
implementación queda para un ciclo de Mobile, con el contrato de la sección 6.

> Consultado `knowledge-base/patrones-arquitectonicos/` antes de escribir este documento: el
> directorio existe solo como entrada de `knowledge-base/README.md`, todavía sin contenido (repo
> en etapa de scaffolding, ver `CLAUDE.md`) — no hay un patrón previo con el que conciliar ni
> contradecir. La sección 7 deja este documento marcado como candidato a alimentar ese directorio
> una vez implementado y probado.

---

## 0. Resumen ejecutivo

El bottom nav de `ClienteShell` desaparece en 13 pantallas reales (no 10) apenas se navega un
nivel más allá de las 4 raíces de pestaña, porque **todo `Navigator.push` de este código empuja
sobre el Navigator raíz de la app** (hay uno solo hoy), fuera del `Scaffold`/`IndexedStack` que
contiene la bottom nav.

**Recomendación:** adoptar un **`Navigator` anidado por pestaña** dentro de `ClienteShell` (Opción
A de la sección 2), usando únicamente widgets ya incluidos en el SDK de Flutter (`Navigator`,
`NavigatorPopHandler`) — **sin agregar ninguna dependencia nueva a `pubspec.yaml`**. Con este
cambio, el 100% de las pantallas ya escritas (`DetalleNegocioScreen`, `ElegirProfesionalScreen`,
etc.) sigue funcionando **sin tocarlas**, porque `Navigator.of(context)`/`Navigator.push`/`.pop`/
`.maybePop` ya usados en ellas resuelven automáticamente al Navigator ancestro más cercano — que
pasa a ser el anidado de su pestaña en vez del raíz de la app, de forma transparente.

Solo 2 archivos requieren cambios reales: `cliente_shell.dart` (la estructura del fix) y
`confirmar_turno_screen.dart` (el único punto que hoy salta de pestaña programáticamente, más un
hallazgo adicional de un diálogo — sección 4.6). `go_router` con `StatefulShellRoute` (Opción B)
es la solución "correcta" a mediano plazo, pero implica reescribir la navegación de Cliente,
Profesional y Administrador completos (30+ pantallas) y agregar una dependencia nueva — se deja
como refactor de fondo, sujeto a validación de CTO IA, no incluido en este ciclo.

---

## 1. El problema, verificado contra el código real

### 1.1 Mecanismo de la falla

`main.dart` monta `MaterialApp(home: const _Router())`. `_Router` es un `StatelessWidget` que
observa `Sesion` y devuelve `ClienteShell()`/`ProfesionalShell()`/`AdministradorShell()`/
`LoginScreen()` según el rol — **todo dentro de una única Route** (la que `MaterialApp.home` crea
implícitamente). `ClienteShell` arma su bottom nav así (`cliente_shell.dart:68-75`):

```dart
return Scaffold(
  body: IndexedStack(index: _index, children: screens),
  bottomNavigationBar: AppBottomNavigationBar(...),
);
```

La bottom nav vive en ESE `Scaffold`. Cualquier `Navigator.push(context, MaterialPageRoute(...))`
ejecutado desde una pantalla dentro de `screens` resuelve `Navigator.of(context)` al **único
Navigator que existe hoy** (el raíz de `MaterialApp`) y apila la nueva Route **por encima** de esa
misma Route única que contiene a `ClienteShell` — es decir, por encima del `Scaffold` con la
bottom nav, no dentro de él. Resultado: la pantalla nueva ocupa toda la pantalla, sin bottom nav.

### 1.2 Inventario completo de superficies afectadas (grep sobre `screens/cliente/`)

No son solo los 2 flujos que menciona el encargo — hay un tercero:

| # | Pestaña de origen | Cadena de `Navigator.push` | Profundidad |
|---|---|---|---|
| 1 | Buscar | `BuscarNegociosScreen` → `DetalleNegocioScreen` → `ElegirProfesionalScreen` → `HorariosDisponiblesScreen` → `ConfirmarTurnoScreen` | 4 pantallas empujadas |
| 2 | Mis Turnos | `MisTurnosScreen` → `ReprogramarTurnoScreen` | 1 pantalla empujada |
| 3 | Notificaciones | `NotificacionesScreen` → `ConfiguracionNotificacionesScreen` (ícono ⚙ del header, `profesional/notificaciones_screen.dart:124`, reusada tal cual por Cliente) | 1 pantalla empujada |
| 4 | Configuración | `ConfiguracionClienteScreen` → una de 6: `EditarPerfilScreen`, `ConfiguracionNotificacionesScreen`, `PrivacidadScreen`, `ProximamenteScreen("Idioma")`, `AyudaSoporteClienteScreen`, `AcercaDeClienteScreen` | 1 pantalla empujada |

`ConfiguracionNotificacionesScreen` es alcanzable desde **dos** pestañas distintas (3 y 4) — ver
tratamiento en 4.7. Verificado que ninguna de las 6 pantallas de Configuración empuja una tercera
pantalla propia cuando la sesión es `Rol.cliente`: `EditarPerfilScreen` sí puede empujar
`PreciosSenasScreen` (`profesional/editar_perfil_screen.dart:444`), pero esa sección está
gateada por `_esProfesional` (línea 78) y nunca se muestra a un cliente — la profundidad máxima
real de la pestaña Configuración para Cliente es 2 (raíz + 1), no 3.

### 1.3 El "hack" ya existente que hay que reemplazar, no solo rodear

`ConfirmarTurnoScreen._confirmar()` (líneas 77-89) ya intenta resolver el caso "saltar a otra
pestaña tras completar el flujo", pero con un mecanismo que **también** pierde la bottom nav hoy:

```dart
final navigator = Navigator.of(context);
navigator.pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => MisTurnosScreen(onIrABuscar: navigator.pop)),
  (route) => route.isFirst,
);
```

Esto vacía el stack hasta la primera Route (`ClienteShell`) y empuja una **segunda instancia** de
`MisTurnosScreen` por encima — otra pantalla fuera del `Scaffold` de la shell. Cualquier diseño
que solo "envuelva" las pantallas nuevas sin tocar este punto deja este caso roto. Está incluido
explícitamente en el contrato de la sección 6.

---

## 2. Alternativas evaluadas

### 2.1 Opción A — Navigator anidado por pestaña

Cada entrada del `IndexedStack` de `ClienteShell` pasa a ser su propio `Navigator` (con una
`GlobalKey<NavigatorState>` propia), cuya única Route inicial es la pantalla raíz actual de esa
pestaña (`BuscarNegociosScreen`, `MisTurnosScreen`, etc.). El `IndexedStack` sigue decidiendo qué
pestaña se pinta; cada pestaña administra su propio historial de navegación por dentro.

- **Ventaja:** cambio acotado a `cliente_shell.dart` + `confirmar_turno_screen.dart`. Las 13
  pantallas del inventario (1.2) seguían funcionando sin ningún cambio de código, porque
  `Navigator.of(context)` ya usado en todas ellas resuelve solo al ancestro más cercano.
- **Ventaja:** cero dependencias nuevas — `Navigator`/`NavigatorPopHandler` son parte del SDK de
  Flutter ya en uso (`flutter/material.dart`, ya importado en todos lados).
- **Desventaja real (no cosmética):** cambiar de pestaña desde una pantalla empujada dentro de
  OTRA pestaña (el caso "ir a Mis Turnos" desde el flujo de reserva) no tiene un mecanismo nativo
  de Flutter — hay que construirlo a propósito (sección 4.5). Es la única pieza genuinamente nueva
  de este diseño.
- **Desventaja:** el botón/gesto atrás del sistema (Android) necesita manejo explícito
  (`NavigatorPopHandler`, sección 4.6) — sin él, se **rompe de una forma distinta** a la bottom nav
  (ver riesgo 1, sección 5).

### 2.2 Opción B — `go_router` con Shell Routes (`StatefulShellRoute.indexedStack`)

`go_router` (paquete mantenido por el equipo de Flutter, referenciado en la documentación oficial
de navegación como la vía recomendada para apps con rutas declarativas/deep linking) resuelve
exactamente este patrón con `StatefulShellRoute.indexedStack`: un "shell" (la bottom nav) con N
"branches", cada una con su propio Navigator persistente — es, en esencia, la misma idea de la
Opción A pero declarada como árbol de rutas en vez de construida a mano con `Navigator`/
`GlobalKey`.

- **Ventaja:** navegación declarativa, deep linking real (`/negocios/:id/servicios/:id/...`),
  cambio de pestaña y navegación anidada resueltos por el framework del paquete en vez de código
  a medida.
- **Desventaja confirmada contra el código real (no solo teórica):** hoy **no existe una sola
  ruta con nombre en toda la app** — `pubspec.yaml` no tiene `go_router` como dependencia, y
  `main.dart`/todas las pantallas usan exclusivamente `MaterialPageRoute` anónimo +
  `Navigator.push` imperativo. Adoptarlo implica convertir cada `Navigator.push(context,
  MaterialPageRoute(builder: (_) => Pantalla(param: x)))` en una `GoRoute` declarativa con sus
  parámetros tipados, y migrar el enrutamiento por rol de `_Router` (`main.dart:57-86`) al
  mecanismo `redirect` de `go_router`. Alcanza a Cliente (13 pantallas), Profesional y
  Administrador (ambos con el mismo patrón, ver sección 7) — 30+ archivos, no un cambio acotado.
- **Desventaja de gobierno:** agrega una dependencia externa nueva — por regla de la empresa
  ("las decisiones que impliquen nueva tecnología... requieren validación del CTO IA"), no puede
  adoptarse solo por decisión de Arquitecto.

### 2.3 Comparación

| Criterio | A — Navigator anidado | B — go_router |
|---|---|---|
| Archivos que se tocan ahora | 2 | 30+ (Cliente+Profesional+Administrador) |
| Dependencia nueva | No | Sí (`go_router`) |
| Requiere validación CTO IA | No | Sí |
| Resuelve el bug pedido | Sí, completo | Sí, completo |
| Deep linking / rutas con nombre | No (no lo tiene hoy tampoco) | Sí |
| Riesgo de regresión | Bajo (pantallas hoja sin cambios) | Alto (reescritura completa) |
| Esfuerzo estimado | Chico (2 archivos) | Grande (proyecto propio) |

---

## 3. Decisión

**Se recomienda la Opción A ahora**, con la Opción B registrada como refactor de fondo a evaluar
en un ciclo de planificación separado, no como parte de este arreglo.

**Justificación:**

1. Resuelve el 100% del pedido del CEO ("los botones de navegación deben estar visibles en todas
   las pantallas") sin reescribir código que ya funciona y está probado.
2. Es consistente con el criterio que CTO IA ya estableció para este mismo proyecto
   (`lineamientos-tecnicos.md` §2: "V1 modular monolito... V2+ si el volumen lo justifica,
   extraer..." — resolver con la solución mínima suficiente ahora, dejando la reestructuración
   mayor para cuando el volumen/necesidad real la justifique, en vez de adelantarla sin evidencia
   de que haga falta deep linking u otra capacidad que hoy nadie pidió).
3. No introduce tecnología nueva → no bloquea esta corrección detrás de un ciclo de validación de
   CTO IA. `go_router` sí lo requeriría — queda planteado en la sección 7 para que el Director
   General IA decida si lo escala.

---

## 4. Diseño de la solución (Opción A)

### 4.1 Diagrama — estado actual (roto)

```
MaterialApp
 └─ Navigator (RAÍZ — el único que existe hoy)
     └─ Route "home" → _Router → ClienteShell
          │
          ├─ Scaffold
          │   ├─ body: IndexedStack[ _index ]
          │   │     [0] BuscarNegociosScreen        (pestaña "Buscar")
          │   │     [1] MisTurnosScreen              (pestaña "Mis Turnos")
          │   │     [2] NotificacionesScreen          (pestaña "Notificaciones")
          │   │     [3] ConfiguracionClienteScreen    (pestaña "Configuración")
          │   └─ bottomNavigationBar: AppBottomNavigationBar
          │        ▲ visible SOLO mientras la Route activa sea esta
          │
          └─ Navigator.push desde CUALQUIERA de las 4 pantallas de arriba
              apila una Route NUEVA sobre el MISMO Navigator raíz,
              por encima del Scaffold de ClienteShell:

                   Route → DetalleNegocioScreen       ✗ sin bottom nav
                   Route → ElegirProfesionalScreen     ✗ sin bottom nav
                   Route → HorariosDisponiblesScreen   ✗ sin bottom nav
                   Route → ConfirmarTurnoScreen         ✗ sin bottom nav
                   Route → ReprogramarTurnoScreen       ✗ sin bottom nav
                   Route → EditarPerfilScreen / etc.    ✗ sin bottom nav
```

### 4.2 Diagrama — estado propuesto

```
MaterialApp
 └─ Navigator (RAÍZ — sigue existiendo, sigue con UNA sola Route, sin cambios)
     └─ Route "home" → _Router → ClienteShell
          │
          └─ Provider<ClienteTabController>.value   (expone el cambio de pestaña a cualquier
              │                                       descendiente, sin importar cuán profundo)
              └─ Scaffold
                  ├─ body: IndexedStack[ _index ]   (los 4 hijos SIEMPRE montados, igual que hoy)
                  │
                  │  [0] NavigatorPopHandler → Navigator(key: _navBuscar)
                  │        Route "/" → BuscarNegociosScreen
                  │             └─ push → DetalleNegocioScreen
                  │                  └─ push → ElegirProfesionalScreen
                  │                       └─ push → HorariosDisponiblesScreen
                  │                            └─ push → ConfirmarTurnoScreen
                  │                                 (showDialog "Seña requerida" → Navigator RAÍZ,
                  │                                  correcto: un modal debe tapar TODO, ver 4.6)
                  │
                  │  [1] NavigatorPopHandler → Navigator(key: _navMisTurnos)
                  │        Route "/" → MisTurnosScreen
                  │             └─ push → ReprogramarTurnoScreen
                  │
                  │  [2] NavigatorPopHandler → Navigator(key: _navNotificaciones)
                  │        Route "/" → NotificacionesScreen
                  │             └─ push → ConfiguracionNotificacionesScreen  (instancia A)
                  │
                  │  [3] NavigatorPopHandler → Navigator(key: _navConfiguracion)
                  │        Route "/" → ConfiguracionClienteScreen
                  │             ├─ push → EditarPerfilScreen
                  │             ├─ push → ConfiguracionNotificacionesScreen  (instancia B, ver 4.7)
                  │             ├─ push → PrivacidadScreen
                  │             ├─ push → ProximamenteScreen("Idioma")
                  │             ├─ push → AyudaSoporteClienteScreen
                  │             └─ push → AcercaDeClienteScreen
                  │
                  └─ bottomNavigationBar: AppBottomNavigationBar
                       ▲ vive en el MISMO Scaffold que el IndexedStack de arriba:
                         SIEMPRE visible, sin importar la profundidad del stack
                         anidado de la pestaña activa.
```

### 4.3 Contrato de archivos (qué se toca, qué no)

**Se modifican (2 archivos):**

| Archivo | Cambio |
|---|---|
| `lib/screens/cliente/cliente_shell.dart` | Estructura completa del fix — ver 4.4 |
| `lib/screens/cliente/confirmar_turno_screen.dart` | Reemplaza el hack de `pushAndRemoveUntil` (1.3) + corrige el `showDialog` (4.6) |

**No se modifican (verificado contra el inventario de 1.2 — 0 cambios de código):**

`buscar_negocios_screen.dart`, `detalle_negocio_screen.dart`, `elegir_profesional_screen.dart`,
`horarios_disponibles_screen.dart`, `mis_turnos_screen.dart`, `reprogramar_turno_screen.dart`,
`configuracion_cliente_screen.dart`, `acerca_de_cliente_screen.dart`,
`ayuda_soporte_cliente_screen.dart`, y las 4 reusadas de `profesional/`: `notificaciones_screen.dart`,
`editar_perfil_screen.dart`, `configuracion_notificaciones_screen.dart`, `privacidad_screen.dart`.
Ninguna necesita saber que ahora vive dentro de un Navigator anidado — su `Navigator.push`/`.pop`/
`.maybePop` ya escrito sigue funcionando porque resuelve al ancestro más cercano, que pasa a ser
el Navigator de su pestaña en vez del raíz.

### 4.4 Pseudocódigo — `cliente_shell.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';   // ya es dependencia del proyecto (Sesion, ThemeController)
import '../../widgets/widgets.dart';
import '../profesional/notificaciones_screen.dart';
import 'buscar_negocios_screen.dart';
import 'configuracion_cliente_screen.dart';
import 'mis_turnos_screen.dart';

const int _tabBuscar = 0;
const int _tabMisTurnos = 1;   // NUEVO: antes solo _tabBuscar tenía nombre; ahora
                                 // ConfirmarTurnoScreen también necesita saltar por índice.

/// Expuesto vía Provider a TODO el subárbol de ClienteShell — los 4 Navigator anidados incluidos
/// — para que una pantalla arbitrariamente profunda dentro de CUALQUIER pestaña (hoy, el único
/// caso real: ConfirmarTurnoScreen, 4 niveles bajo "Buscar") pueda pedir un cambio de pestaña sin
/// que las pantallas intermedias (DetalleNegocioScreen, ElegirProfesionalScreen,
/// HorariosDisponiblesScreen) necesiten conocer ni reenviar por constructor un callback que no
/// les concierne. Reemplaza el mecanismo viejo de ConfirmarTurnoScreen (Navigator.of(context)
/// sobre el Navigator raíz + pushAndRemoveUntil con una segunda instancia de MisTurnosScreen,
/// ver §1.3 de bottom-nav-persistente-cliente.md), que dejaba de andar apenas el Navigator raíz
/// pasó a tener una sola Route estable.
///
/// Se expone solo un método con nombre de intención (irAMisTurnos), no el índice crudo —
/// encapsula el número de pestaña dentro de este archivo, ningún otro archivo necesita conocerlo.
class ClienteTabController {
  const ClienteTabController(this._irATabDesdeRaiz);
  final void Function(int index) _irATabDesdeRaiz;

  void irAMisTurnos() => _irATabDesdeRaiz(_tabMisTurnos);
}

class ClienteShell extends StatefulWidget {
  const ClienteShell({super.key});
  @override
  State<ClienteShell> createState() => _ClienteShellState();
}

class _ClienteShellState extends State<ClienteShell> {
  int _index = _tabBuscar;

  // Una GlobalKey<NavigatorState> por pestaña — única forma de manipular el Navigator anidado
  // de una pestaña que NO es ancestro del contexto que llama (ej. resetear "Buscar" desde un
  // callback que vive en este State, no dentro del árbol de esa pestaña).
  final _navBuscar = GlobalKey<NavigatorState>();
  final _navMisTurnos = GlobalKey<NavigatorState>();
  final _navNotificaciones = GlobalKey<NavigatorState>();
  final _navConfiguracion = GlobalKey<NavigatorState>();

  List<GlobalKey<NavigatorState>> get _navKeys =>
      [_navBuscar, _navMisTurnos, _navNotificaciones, _navConfiguracion];

  /// Tap directo de un ícono del bottom nav: cambia de pestaña TAL CUAL la dejó el usuario — el
  /// IndexedStack mantiene vivo el Navigator anidado de cada pestaña, mismo criterio con el que
  /// ya se preserva hoy el scroll/texto de búsqueda de "Buscar" al cambiar de pestaña y volver.
  void _irATab(int index) => setState(() => _index = index);

  /// Usado SOLO por accesos directos entre pestañas que representan "iniciar tal pantalla/flujo"
  /// (MisTurnosScreen.onIrABuscar, ClienteTabController.irAMisTurnos) — a diferencia de _irATab,
  /// además vacía el stack anidado de la pestaña DESTINO antes de mostrarla, para aterrizar
  /// siempre en su raíz y no en lo que haya quedado pusheado de una visita anterior.
  void _irATabDesdeRaiz(int index) {
    _navKeys[index].currentState?.popUntil((route) => route.isFirst);
    _irATab(index);
  }

  /// Envuelve la raíz de una pestaña en su propio Navigator + NavigatorPopHandler (botón atrás
  /// del sistema, ver 4.6). Cualquier Navigator.push/.pop/.maybePop ya escrito en las pantallas
  /// hijas sigue funcionando SIN cambios (ver 4.3).
  Widget _tabNavigator(GlobalKey<NavigatorState> key, Widget raiz) {
    return NavigatorPopHandler(
      onPop: () => key.currentState?.maybePop(),
      child: Navigator(
        key: key,
        onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => raiz),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      _tabNavigator(_navBuscar, const BuscarNegociosScreen()),
      _tabNavigator(_navMisTurnos, MisTurnosScreen(onIrABuscar: () => _irATabDesdeRaiz(_tabBuscar))),
      _tabNavigator(_navNotificaciones, const NotificacionesScreen()),
      _tabNavigator(_navConfiguracion, const ConfiguracionClienteScreen()),
    ];

    return Provider<ClienteTabController>.value(
      value: ClienteTabController(_irATabDesdeRaiz),
      child: Scaffold(
        body: IndexedStack(index: _index, children: screens),
        bottomNavigationBar: AppBottomNavigationBar(
          items: AppBottomNavigationBar.clienteItems,
          currentIndex: _index,
          onTap: _irATab,
        ),
      ),
    );
  }
}
```

Nota de diseño — por qué `onIrABuscar` cambia de `_irATab` a `_irATabDesdeRaiz`: es un cambio de
comportamiento chico y deliberado, no un descuido. Hoy, sin Navigator anidado, tocar "+"/"Buscar
Negocios" desde Mis Turnos ya aterriza en la raíz de Buscar porque no hay otro estado posible. Con
Navigator anidado, si el usuario hubiera dejado un flujo de reserva a medias en "Buscar" y después
tocara ese botón desde Mis Turnos, `_irATab` simple lo devolvería a la pantalla pusheada vieja
(posiblemente con datos obsoletos) en vez de una búsqueda limpia — `_irATabDesdeRaiz` preserva el
comportamiento actual real, no solo el visible hasta ahora.

### 4.5 Pseudocódigo — `confirmar_turno_screen.dart` (caso especial cross-tab)

```dart
// ANTES (líneas 77-89 reales del archivo):
if (!mounted) return;
final navigator = Navigator.of(context);
navigator.pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => MisTurnosScreen(onIrABuscar: navigator.pop)),
  (route) => route.isFirst,
);

// DESPUÉS:
if (!mounted) return;
// Vacía ESTA pestaña ("Buscar"): Navigator.of(context) resuelve al Navigator anidado de "Buscar"
// (el ancestro más cercano de ConfirmarTurnoScreen), no al raíz — vuelve a BuscarNegociosScreen.
Navigator.of(context).popUntil((route) => route.isFirst);
// Cambia la pestaña ACTIVA a "Mis Turnos" (vía el controller expuesto por ClienteShell, 4.4).
context.read<ClienteTabController>().irAMisTurnos();
```

Import a quitar: `mis_turnos_screen.dart` (ya no se instancia acá). Import a agregar:
`cliente_shell.dart` (para `ClienteTabController`) — `provider` ya está importado en este archivo.

### 4.6 Botón/gesto atrás del sistema — por qué `NavigatorPopHandler` no es opcional

Hoy, el botón "volver" de `AppHeader` (`showBackButton: true`) llama `Navigator.maybePop(context)`
(`widgets/app_header.dart:62`) — sigue funcionando sin cambios, porque resuelve al Navigator
anidado correcto igual que cualquier otro `Navigator.of(context)` de este código.

El botón/gesto atrás **del sistema operativo** (Android) es distinto: por defecto solo sabe pedirle
al Navigator **raíz** de la app que intente hacer pop. Con el diseño de este documento, el Navigator
raíz vuelve a tener **una sola Route** siempre (la de `_Router`/`ClienteShell`) — sin manejo
explícito, `Navigator.maybePop()` sobre el raíz devolvería `false` (nada para hacer pop) y Android
**cerraría/minimizaría la app** en vez de retroceder un paso, aunque la pestaña activa tuviera 3
pantallas pusheadas por dentro. `NavigatorPopHandler` (parte del SDK de Flutter, sin dependencia
nueva) es exactamente el mecanismo para este caso: delega el pop del sistema al Navigator anidado
de la pestaña activa primero, y solo lo deja subir al raíz cuando esa pestaña ya está en su raíz.
Por eso está incluido en el pseudocódigo de 4.4 desde el principio, no como mejora opcional.

**Hallazgo adicional en el mismo archivo, mismo mecanismo de fondo:** el diálogo "Seña requerida"
de `ConfirmarTurnoScreen` (líneas 67-75) es el **único** `showDialog` de las 7 pantallas de esta
app que lo usan (`login_screen.dart`, `administrador/servicios_negocio_screen.dart`,
`administrador/profesionales_negocio_screen.dart`, `profesional/dashboard_screen.dart`,
`profesional/ficha_paciente_screen.dart`, `profesional/nueva_cita_screen.dart`) que **no** sigue
el patrón ya establecido en las otras 6: todas las demás nombran el `BuildContext` del propio
diálogo (`builder: (dialogContext) => ...`) y lo usan para el pop del botón
(`Navigator.of(dialogContext).pop(...)`); esta pantalla descarta ese contexto (`builder: (_) =>
...`) y reutiliza el `context` exterior de `ConfirmarTurnoScreen` para el botón "Entendido"
(`Navigator.pop(context)`). Hoy "funciona" solo porque hay un único Navigator en toda la app. Con
Navigator anidado, `Navigator.pop(context)` resolvería al Navigator de la pestaña "Buscar" (donde
vive `ConfirmarTurnoScreen`), no al raíz (donde `showDialog` — con `useRootNavigator: true` por
default, correcto para un modal — realmente empujó el diálogo): el botón "Entendido" intentaría
cerrar `ConfirmarTurnoScreen` en vez del diálogo, que quedaría abierto. Fix de una línea, mismo
patrón que el resto del código: `builder: (dialogContext) => AlertDialog(..., actions:
[TextButton(onPressed: () => Navigator.pop(dialogContext), ...)])`. Incluido en el contrato de
archivos de 4.3 (no es un archivo nuevo a tocar).

### 4.7 Caso: `ConfiguracionNotificacionesScreen` alcanzable desde 2 pestañas

Se llega a la misma pantalla desde "Notificaciones" (ícono ⚙ del header) y desde "Configuración"
(ítem de menú). Con Navigator anidado, cada acceso crea una instancia **independiente** dentro del
stack de SU PROPIA pestaña — exactamente el mismo comportamiento que hoy (ya son 2 instancias sin
estado compartido, cada una con su propio `initState`/fetch). No es un riesgo nuevo introducido
por este diseño; se deja documentado para que QA no lo confunda con una regresión (ej.: cambiar un
toggle desde un acceso no se refleja instantáneamente en el otro hasta reabrir esa pantalla — así
se comporta ya hoy).

### 4.8 Estado del Navigator anidado al cambiar de pestaña y volver

Si el usuario deja `ElegirProfesionalScreen` pusheada en "Buscar", cambia a "Notificaciones" y
vuelve a "Buscar", reaparece en `ElegirProfesionalScreen` (no en la raíz) — porque `IndexedStack`
mantiene montados los 4 hijos, Navigator anidado incluido. Es el mismo principio con el que
`IndexedStack` ya preserva hoy el scroll y el texto de búsqueda de "Buscar" al cambiar de pestaña,
y coincide con la convención de apps con bottom-tabs (cada pestaña conserva su propia pila). No es
un defecto de este diseño, pero es observable recién con este cambio (hoy ni siquiera se puede
llegar a ese estado, porque el push ya rompía la bottom nav antes de que hubiera chance de cambiar
de pestaña). Si Product Manager/UX/UI prefieren resetear una pestaña no activa después de cierto
tiempo, o al re-tocar el ícono de la pestaña ya activa (convención común en iOS/Android: volver a
tocar el ícono de la pestaña actual la lleva a su raíz), es un agregado chico sobre
`_irATab`/`_navKeys` — **no incluido en el contrato de esta ronda**, queda como mejora opcional a
decidir con Product Manager.

---

## 5. Riesgos identificados y mitigaciones

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Botón/gesto atrás de Android cierra la app en vez de retroceder un paso, en cualquier pestaña con stack anidado | `NavigatorPopHandler` por pestaña (4.6) — no es opcional, ya incluido en el pseudocódigo de 4.4 |
| 2 | El hack de `pushAndRemoveUntil` (1.3) queda sin arreglar si solo se "envuelve" el resto | Migración explícita a `ClienteTabController` incluida en el contrato (4.3/4.5) |
| 3 | Diálogo "Seña requerida" queda roto (pop apunta a la pantalla incorrecta) | Fix de 1 línea, mismo patrón ya usado en el resto de la app (4.6) |
| 4 | `ConfiguracionNotificacionesScreen` duplicada entre pestañas se confunde con una regresión | Documentado en 4.7 — comportamiento ya existente hoy, sin cambios |
| 5 | Cambio de comportamiento observable en persistencia de stack por pestaña (4.8) | Documentado explícitamente; validar con Product Manager/UX si hace falta un reset adicional (no incluido en esta ronda) |
| 6 | El mismo bug de fondo existe en `ProfesionalShell`/`AdministradorShell` (confirmado por grep: `administrador_shell.dart`, `pacientes_negocio_screen.dart`, `profesionales_negocio_screen.dart`, `agenda_screen.dart`, `configuracion_screen.dart`, `dashboard_screen.dart`, `gestion_pacientes_screen.dart`, `mis_clientes_screen.dart`, `notificaciones_screen.dart`) | Fuera de alcance de Task #115 (acotada a Cliente por el CEO) — mismo patrón aplicaría 1:1, ver sección 7 |
| 7 | Sin SDK de Flutter disponible en este entorno de desarrollo (limitación ya documentada del proyecto), este diseño no fue verificado con `flutter analyze`/`flutter run` reales; la firma exacta de `NavigatorPopHandler` (nombres de parámetros) no fue confirmada contra la versión instalada | Mismo proceso ya establecido en este proyecto: CI de GitHub Actions (`turnos-mobile-ci.yml`, canal `stable`) corre `flutter analyze` + `flutter build apk --debug` en cada push; Mobile debe confirmar la firma exacta al implementar y QA debe probar manualmente en dispositivo/emulador real: (a) bottom nav visible en las 13 pantallas del inventario (1.2), (b) botón atrás del sistema en cada nivel de cada pestaña, (c) flujo completo "confirmar turno → aterriza en Mis Turnos con esa pestaña ya seleccionada" |

---

## 6. Contrato de implementación (para quien lo tome, ej. Mobile)

1. `cliente_shell.dart`: agregar `_tabMisTurnos`, las 4 `GlobalKey<NavigatorState>`, la clase
   `ClienteTabController`, `_tabNavigator(...)`, `_irATabDesdeRaiz(...)`; envolver el `Scaffold` en
   `Provider<ClienteTabController>.value`; reemplazar los 4 hijos directos del `IndexedStack` por
   `_tabNavigator(...)`; actualizar `MisTurnosScreen(onIrABuscar: ...)` a `_irATabDesdeRaiz`.
2. `confirmar_turno_screen.dart`: reemplazar el bloque `pushAndRemoveUntil` (4.5) + corregir el
   `showDialog` (4.6); quitar el import de `mis_turnos_screen.dart`; agregar el de
   `cliente_shell.dart`.
3. Ningún otro archivo de `screens/cliente/` requiere cambios (contrato cerrado en 4.3).
4. Verificar con el mismo pipeline ya existente: `flutter analyze` + `flutter build apk --debug`
   (`turnos-mobile-ci.yml`).
5. QA manual en dispositivo/emulador real — los 3 casos del riesgo 7 de la sección 5. No alcanza
   con revisar solo el botón "volver" del `AppHeader` (ya funcionaba y sigue funcionando); el caso
   que de verdad prueba este fix es el botón/gesto atrás **nativo** del sistema operativo.

---

## 7. Fuera de alcance de esta ronda

- **`ProfesionalShell`/`AdministradorShell` tienen el mismo bug de fondo** (ver riesgo 6). El CEO
  acotó este pedido a Cliente; el mismo patrón de esta sección 4 aplicaría 1:1 a esos 2 shells.
  Recomendación: una vez validado en Cliente, levantar una tarea de fast-follow para replicarlo
  ahí — evita que la app quede con bottom nav persistente en un rol pero no en los otros dos.
- **`go_router`/`StatefulShellRoute`** (Opción B, sección 2.2): refactor de fondo, requiere
  dependencia nueva y validación de CTO IA antes de iniciarse — no autorizado ni descartado por
  este documento, queda como decisión pendiente para un ciclo de planificación futuro.
- **Reset de pestaña inactiva** (4.8): mejora opcional, no incluida en el contrato de la sección 6.
- **Patrón reutilizable:** "Navigator anidado por pestaña + `NavigatorPopHandler` + controller
  expuesto vía Provider para saltos cross-tab desde pantallas profundas" es candidato a
  `knowledge-base/patrones-arquitectonicos/` una vez implementado y verificado en este proyecto —
  aplica a cualquier app Flutter futura de la Factory con bottom nav + flujos multi-pantalla
  (mismo criterio que ya usaron DBA/DevOps para otros patrones de este mismo proyecto, ver
  `memory/proyectos/turnos-profesionales/decisiones.md`). No se creó la entrada todavía — no hay
  código probado que respalde el patrón hasta que Mobile lo implemente y QA lo valide.

---

## 8. Gobierno

- **No requiere validación de CTO IA:** la Opción A recomendada usa exclusivamente widgets ya
  incluidos en el SDK de Flutter (`Navigator`, `NavigatorPopHandler`), sin agregar ninguna
  dependencia a `pubspec.yaml` ni cambiar ningún estándar ya aprobado — es una aplicación del
  mismo framework y del mismo idioma (`Navigator.push`/`MaterialPageRoute`) que este código ya usa
  en todas partes.
- **Si en algún momento se decide avanzar con `go_router` (Opción B):** por regla de la empresa
  ("las decisiones que impliquen nueva tecnología o cambio de estándar requieren validación del
  CTO IA antes de darse por definitivas"), debe pasar por CTO IA antes de iniciarse — no antes.
- Este documento es una propuesta de diseño del Arquitecto; su aprobación como entregable final
  queda a criterio del Director General IA / CEO, conforme a las reglas de actuación de este rol.

---

## 9. Recursos de referencia

Citados desde conocimiento de entrenamiento (este entorno no tiene acceso a internet en esta
tarea) — Mobile debe confirmar que cada URL resuelve igual contra la versión de Flutter vigente
(canal `stable`, sin versión pineada en `turnos-mobile-ci.yml`) al momento de implementar:

- Flutter cookbook — navegación anidada con múltiples `Navigator` y `NavigatorPopHandler`:
  https://docs.flutter.dev/cookbook/navigation/nested-nav
- `Navigator` (API docs): https://api.flutter.dev/flutter/widgets/Navigator-class.html
- `NavigatorPopHandler` (API docs): https://api.flutter.dev/flutter/widgets/NavigatorPopHandler-class.html
- Flutter — Navigation and routing (overview, incluye cuándo preferir `go_router`):
  https://docs.flutter.dev/ui/navigation
- `go_router` (paquete, para la Opción B): https://pub.dev/packages/go_router
- `StatefulShellRoute` (API docs de `go_router`):
  https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html

---

## 10. Registro

Decisión registrada en `memory/proyectos/turnos-profesionales/decisiones.md` (entrada "Bottom nav
persistente en Cliente — Navigator anidado por pestaña — Arquitecto") para que Mobile/QA/CTO IA la
reutilicen sin tener que releer este documento completo.
