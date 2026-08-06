# Sistema de Diseño — Turnos Profesionales

**Rol:** UX/UI
**Fase:** 3 — Diseño
**Entradas:** Descripción detallada (transcripción) de capturas de otra app propiedad del CEO,
aportada por el Director General IA; `02-backlog/backlog.md` (Product Manager);
`03-arquitectura/lineamientos-tecnicos.md` (CTO IA, stack Flutter).
**Salidas:** Este documento (tokens + componentes) + pantallas actualizadas en
`04-diseno/mapa-pantallas.md`.

## 0. Origen y alcance

El CEO solicitó tomar como base el estilo visual y las funcionalidades de otra app de su
propiedad (aún no en producción) para rediseñar Turnos Profesionales. No hubo acceso directo
a las imágenes originales, solo a una descripción escrita detallada del lenguaje visual y de
las pantallas del lado **Profesional**. Este documento traduce esa descripción en un sistema
de diseño reutilizable (tokens + componentes) para que Mobile lo implemente en Flutter de
forma consistente en toda la app — incluido el lado **Cliente**, que no estaba en las
capturas pero debe mantener coherencia visual con el resto de la app (principio ya vigente en
§1 de `mapa-pantallas.md`: una sola app con dos modos, no dos apps separadas).

No existía previamente un sistema de diseño para este proyecto en
`knowledge-base/plantillas/` (carpeta sin plantillas de UI cargadas aún) — este documento es
la primera versión y queda como candidato a publicarse en la knowledge base organizacional al
cierre del proyecto (decisión de publicación fuera del alcance de este documento).

## 1. Principios de diseño

1. **Cálido pero funcional.** El toque distintivo de emojis en headers de sección convive con
   iconografía Material estándar — los emojis decoran, nunca reemplazan la única forma de
   identificar una acción o estado (ver §6 y §9, accesibilidad).
2. **Jerarquía clara.** Título de pantalla grande y bold, subtítulos medianos, texto de ayuda
   pequeño gris — sin ambigüedad sobre qué es lo más importante en cada pantalla.
3. **Componentes antes que soluciones ad-hoc.** Toda pantalla nueva reutiliza los componentes
   de §7 antes de introducir una variante nueva.
4. **Claro y oscuro de primera clase.** Todo color se define como token semántico con valor en
   ambos temas (§3, §8), nunca como hex hardcodeado en una pantalla puntual.
5. **Estados nunca solo por color.** Todo estado (pill, badge) lleva texto además de color,
   para accesibilidad y para no depender del daltonismo del usuario.

## 2. Resumen del lenguaje visual observado

- Color primario azul-índigo/periwinkle en headers, botones primarios, ítem activo de
  navegación inferior y chips seleccionados.
- Fondo gris muy claro, tarjetas blancas con esquinas redondeadas y sombra sutil.
- Verde / ámbar / rojo como semántica de estado consistente en toda la app.
- Steppers numéricos "− valor +" para configuración cuantitativa.
- Stat cards en grid para métricas rápidas.
- Navegación inferior de 6 ítems (lado Profesional).
- Emojis como decoración de headers de sección, nunca como único indicador de estado o acción.

## 3. Paleta de colores

Todos los valores son tokens semánticos con variante para tema claro y oscuro. Nombres
sugeridos para Flutter en `AppColors` (§10).

### 3.1 Marca / primario

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| `primary` | `#6C7FE0` | `#8B9AEF` | Headers, botón primario, ítem activo bottom nav, chip seleccionado, anillo "Hoy" en calendario |
| `primaryPressed` | `#5567D6` | `#7482D6` | Estado presionado/hover de `primary` |
| `primaryContainer` | `#E4E7FB` | `#2A2F5C` | Fondo de chip no seleccionado, fondo sutil de íconos activos, fondo de tarjetas destacadas (ej. plan Pro) |
| `onPrimary` | `#FFFFFF` | `#0B0C14` | Texto/ícono sobre `primary` sólido |

### 3.2 Neutros / superficie

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| `background` | `#F7F8FA` | `#14151C` | Fondo de pantalla, detrás de las tarjetas |
| `surface` (tarjeta) | `#FFFFFF` | `#1E202B` | Cards, modales, bottom nav, header si no usa `primary` |
| `border` / `divider` | `#E8EAF1` | `#2C2E3A` | Bordes de card sutiles, separadores de lista, borde de botón outline |
| `textPrimary` | `#1A1B25` | `#F2F3F7` | Títulos, texto principal |
| `textSecondary` | `#6B7280` | `#A7ACC0` | Subtítulos, texto de ayuda, labels |
| `textDisabled` | `#A0A4B2` | `#5B5F6E` | Placeholders, controles deshabilitados |

### 3.3 Estados (semántico, no ligado a una sola entidad)

| Token | Base claro | Fondo pastel claro | Base oscuro | Fondo pastel oscuro | Uso típico |
|---|---|---|---|---|---|
| `success` | `#2FAE60` | `#E1F6E9` | `#4ECB86` | `#16321F` | Activo (paciente), Confirmada (turno), Disponible (slot) |
| `warning` | `#F5A623` | `#FDECD1` | `#F7B955` | `#3A2A12` | Por confirmar (turno), Programada (turno), botón "Restablecer" |
| `danger` | `#E5484D` | `#FBE1E2` | `#F2777B` | `#3A1517` | Inactivo (paciente), Cancelada (turno) |
| `neutral` | `#8A8F9C` | `#EEEFF2` | `#9AA0B0` | `#262834` | Completada / Pasada (turno) — *estado agregado por UX/UI, no presente en las capturas originales, ver §11.2* |

`danger` para "Cancelada" y `neutral` para "Completada/Pasada" son extensiones de UX/UI sobre
lo descripto en las capturas (que solo mencionaban Activo/Inactivo y Por confirmar/Confirmada/
Programada); se agregan porque el dominio de Turnos Profesionales ya contempla esos estados
(ver `documento-arquitectura.md` y RN8) y necesitan representación visual consistente.

### 3.4 Tabla de mapeo estado → color (para Mobile / QA)

| Entidad | Estado | Token de color |
|---|---|---|
| Turno | Por confirmar (pendiente de pago, HU-09b) | `warning` |
| Turno | Programada (confirmada, a futuro) | `warning` |
| Turno | Confirmada (pago acreditado / sin seña requerida) | `success` |
| Turno | Cancelada | `danger` |
| Turno | Completada / Pasada | `neutral` |
| Horario/slot | Disponible | `success` |
| Paciente | Activo | `success` |
| Paciente | Inactivo | `danger` |

Nota de diseño abierta: en la descripción original, "Programada" y "Por confirmar" comparten
color (`warning`), pero son conceptualmente distintos (una espera acción del cliente/pago,
otra ya está confirmada pero es a futuro). Product Manager y Arquitecto deben confirmar si
"Programada" en el dominio real de Turnos Profesionales equivale a "Confirmada, a futuro" —
de ser así, se recomienda moverla a `success` para no generar ambigüedad de estado con "Por
confirmar". Queda marcado como pregunta abierta, no decisión unilateral de UX/UI.

## 4. Tipografía

Familia: **Roboto** (system default en Android; se fuerza también en iOS para consistencia
visual entre plataformas, dado que es una sola app Flutter con un solo lenguaje visual). Si
Mobile prefiere depender de la fuente nativa por plataforma, debe validarlo con UX/UI antes de
apartarse de este estándar.

| Estilo | Tamaño | Peso | Color (token) | Uso |
|---|---|---|---|---|
| `displayTitle` | 26sp | Bold (700) | `textPrimary` | Título de pantalla ("Dashboard", "Gestión de Pacientes") |
| `sectionTitle` | 18sp | SemiBold (600) | `textPrimary` | Título de card/sección, título de modal |
| `subtitle` | 15sp | Medium (500) | `textSecondary` o `textPrimary` según contexto | Subtítulos, nombre en fila de lista |
| `body` | 14sp | Regular (400) | `textPrimary` | Texto de contenido general |
| `caption` | 12sp | Regular (400) | `textSecondary` | Texto de ayuda, timestamps, notas pequeñas |
| `statNumber` | 30sp | Bold (700) | `textPrimary` (o `primary` si la stat card es de énfasis) | Número grande en stat card |
| `buttonLabel` | 15sp | SemiBold (600), +0.2 letter-spacing | `onPrimary` / color de texto del botón | Texto de botones |

## 5. Espaciado, radios y elevación

Unidad base: **4dp**.

| Token | Valor | Uso |
|---|---|---|
| `space.xs` | 4dp | Separación entre ícono y texto |
| `space.sm` | 8dp | Padding interno chico |
| `space.md` | 12dp | Separación entre elementos de una card |
| `space.base` | 16dp | Padding estándar de card, margen de pantalla |
| `space.lg` | 20dp | Separación entre cards |
| `space.xl` | 24dp | Separación entre secciones |
| `space.xxl` | 32dp | Márgenes superiores de pantalla, espacio antes de footer de modal |

| Token | Valor | Uso |
|---|---|---|
| `radius.card` | 16dp | Tarjetas (rango observado 12–16px, se fija 16 como estándar) |
| `radius.chip` | 999dp (full pill) | Chips, badges, status pills, botones |
| `radius.input` | 12dp | Campos de texto, search bar |
| `radius.modalTop` | 20dp | Esquinas superiores de bottom sheet / modal |

Sombra de card (`elevation.card`): sutil, un solo nivel — en Flutter,
`BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: Offset(0, 4))`.
Headers con fondo `primary` no llevan sombra (son de color sólido, se distinguen por color,
no por elevación); si el header queda con fondo `surface` (blanco) sobre contenido con
scroll, aplica una sombra de 2dp solo cuando el contenido está scrolleado (patrón estándar de
AppBar elevado on-scroll).

## 6. Iconografía

- Base: **Material Icons** (outline para inactivo, filled para activo — ej. bottom nav).
- Emojis como decoración de headers de sección (⏰, 📋, 🍽️, 🏥, ⚙️, 📅, y un ícono de
  salud/cruz para historial médico — la transcripción original usa "✱"; se recomienda a
  Mobile evaluar un ícono Material equivalente, ej. `Icons.health_and_safety` o
  `Icons.medical_information`, como alternativa más consistente entre plataformas si el emoji
  no renderiza igual en todos los dispositivos; queda a criterio de implementación siempre
  que se mantenga el tono "amigable" del resto de la app).
- **Regla de accesibilidad:** el emoji nunca es el único indicador de la acción o sección —
  siempre acompaña un texto (ej. "⏰ Gestión de Horarios", no un ícono solo). Los screen
  readers deben excluir el emoji de la lectura semántica (marcado como decorativo,
  `excludeSemantics: true` o equivalente) para no leer dos veces el mismo concepto.

## 7. Componentes reutilizables

Para cada componente: descripción, variantes/estados, y nombre de widget sugerido para
Flutter (Mobile define la implementación final; estos son nombres de referencia, no código).

### 7.1 Botones

- **`PrimaryButton`** — píldora (radius.chip), fondo `primary` sólido, texto `onPrimary`
  bold, altura ~50dp. Uso: acción principal de pantalla/modal ("Reservar", "Guardar",
  "Agendar Cita").
- **`WarningButton`** (secundario de advertencia) — misma forma, fondo `warning` sólido,
  texto blanco. Uso: acciones de advertencia no destructivas, ej. "Restablecer" (volver a
  valores por defecto de configuración de citas/horarios). No usar para "eliminar" (ver
  `DestructiveButton`).
- **`OutlineButton`** — píldora, fondo transparente, borde `border`/gris ~1.5dp, texto
  `textPrimary`. Uso: "Cancelar" en modales, acciones secundarias no destacadas.
- **`DestructiveButton`** *(adición de UX/UI, no observada explícitamente en la
  transcripción, pero necesaria por consistencia — ej. "Eliminar paciente")* — outline o
  texto en `danger`, mismo radius; confirmar con Product Manager si estas acciones requieren
  un diálogo de confirmación adicional antes de ejecutarse.
- Estado deshabilitado: opacidad reducida (~40%) + `textDisabled`, sin cambiar la forma.

### 7.2 Status Pill / Badge (`StatusPill`)

Forma píldora (`radius.chip`), fondo = color pastel del estado (§3.3/3.4), texto bold en el
color base del mismo estado, padding horizontal ~12dp / vertical ~4dp. Recibe un enum de
dominio (`TurnoEstado`, `PacienteEstado`) y resuelve el color internamente vía la tabla de
§3.4 — nunca hardcodear el color en la pantalla que lo usa.

### 7.3 Stat Card (`StatCard`)

Card blanca (`surface`), `radius.card`, padding `space.base`. Contenido: número grande bold
(`statNumber`) arriba, etiqueta gris chica (`caption`) abajo, ícono opcional pequeño arriba a
la izquierda del número. Se agrupan en `StatCardGrid` de 2 a 4 columnas según ancho de
pantalla (responsive: 2 columnas en mobile angosto, hasta 4 en tablet/landscape). Usado en
Dashboard (Profesional) e Historial de Paciente.

### 7.4 Stepper numérico (`NumericStepperField`)

Patrón "− valor +": dos botones circulares/redondeados (− / +) a los lados de un valor
central bold, con soporte de `min`, `max`, `step` y sufijo de unidad opcional (ej. "30 min",
"5 citas", "2 días"). Reemplaza a un input de texto libre en toda pantalla de configuración
cuantitativa (duración de cita, máximo de citas por día, días de anticipación para reservar,
duración del descanso). Los botones se deshabilitan (no desaparecen) al llegar a `min`/`max`.

### 7.5 Calendar Picker (`MonthCalendarPicker`)

Grid mensual navegable con header `< Mes Año >`. Cada celda de día puede estar en uno de los
siguientes estados visuales (con leyenda fija debajo del grid):

| Estado visual | Color | Significado |
|---|---|---|
| Seleccionada | Fondo `primary` sólido, texto blanco | Día elegido activamente por el usuario |
| Disponible | Fondo `surface`, texto `textPrimary` | Día seleccionable, sin restricción |
| Hoy | Borde `primary` (anillo), fondo `surface` | Marca la fecha actual |
| Pasada | Texto `textDisabled`, sin interacción | Día ya transcurrido, no seleccionable |

Además, un día que ya tiene horario configurado (Gestión de Horarios) lleva un ícono pequeño
de reloj superpuesto en la celda (badge, no reemplaza el color de estado). Debajo del grid,
una fila de **chips removibles** muestra las fechas puntuales ya elegidas (para plantillas
recurrentes o excepciones puntuales), cada chip con una "✕" para quitar esa fecha sin reabrir
el calendario.

### 7.6 Navegación inferior (`AppBottomNavigationBar`)

Componente único y reutilizable, configurado con una lista de ítems según el rol (ver §7.6.1
y §7.6.2) — mismo estilo visual (fondo `surface`, ítem activo en `primary` con ícono filled +
label, ítems inactivos en `textSecondary` con ícono outline), pero **con conjuntos de ítems
distintos por rol** (decisión de UX/UI, ver relación con `mapa-pantallas.md` §3–4).

#### 7.6.1 Profesional (6 ítems, tal como en las capturas)

`Dashboard` · `Horarios` · `Pacientes` · `WhatsApp` · `Notificaciones` · `Configuración`

#### 7.6.2 Cliente (4 ítems — decisión de UX/UI, no estaba en las capturas)

Las capturas del CEO son todas del lado Profesional; para mantener coherencia de "una sola
app" (principio ya vigente en `mapa-pantallas.md` §1), el lado Cliente reutiliza el mismo
componente visual con su propio conjunto de ítems, más acotado porque el Cliente tiene menos
funciones de gestión:

`Buscar` (negocios, home) · `Mis Turnos` · `Notificaciones` · `Configuración`

### 7.7 Header / AppBar (`AppHeader`)

Fondo `primary` sólido, texto de título en blanco bold (`sectionTitle` sobre `onPrimary`),
ícono de volver a la izquierda si aplica, acciones a la derecha en blanco (máx. 2 íconos).
Usado en la mayoría de pantallas principales (Dashboard, Horarios, Pacientes, etc.). Las
pantallas de detalle/ficha anidadas pueden usar header blanco (`surface`) con texto
`textPrimary` si se prioriza continuidad visual con el contenido — a definir puntualmente en
`mapa-pantallas.md` por pantalla.

### 7.8 Modal (`AppModalSheet`)

Bottom sheet o dialog con: header (`sectionTitle` + botón "✕" para cerrar, alineado a la
derecha), contenido central scrolleable, footer fijo (no scrollea) con dos botones — un
`OutlineButton` ("Cancelar") a la izquierda/abajo y un `PrimaryButton` (acción, ej. "Guardar",
"Agendar") a la derecha/arriba, o ambos en fila si el ancho lo permite. Esquinas superiores
`radius.modalTop`. Usado en: Agregar Horario, Agendar Cita manual, Editar Paciente,
Configuración de Citas, Tiempo de Descanso, Replicar en semanas.

### 7.9 Buscador y filtros (`SearchFilterBar`)

Campo de búsqueda con `radius.input`, ícono de lupa, placeholder en `textDisabled`. Debajo o
al costado, fila horizontal scrolleable de chips de filtro: chip seleccionado = fondo
`primary`, texto blanco; chip no seleccionado = fondo `primaryContainer` o `surface` con
borde `border`, texto `textPrimary`. Usado en Gestión de Pacientes (buscador + filtro por
estado Activo/Inactivo, y otros filtros que defina Product Manager).

### 7.10 Fila de lista con acciones (`ActionListTile` / `PatientListTile`)

Card `surface`, `radius.card`, contenido: avatar/inicial circular a la izquierda, nombre
(`subtitle` bold) + línea secundaria gris (`caption`, ej. teléfono o última visita),
`StatusPill` a la derecha, y una fila de hasta 4 acciones rápidas (íconos, ej. ver
historial ✱/🩺, editar ✎, contactar 💬/📞, eliminar/desactivar 🗑) alineadas al pie o al
costado de la card según ancho disponible. Usado en Gestión de Pacientes.

### 7.11 Estado vacío (`EmptyState`)

*(Adición de UX/UI — buena práctica no descripta en la transcripción original.)* Ícono o
ilustración simple + título corto bold + texto de ayuda gris + botón opcional de acción
("Agregar tu primer paciente", "Aún no configuraste tus horarios"). Usado en cualquier
listado que pueda estar vacío (Pacientes, Notificaciones, Historial).

## 8. Theming claro/oscuro

Todos los tokens de §3 están definidos para ambos temas. Regla de implementación para Mobile:
ninguna pantalla ni componente debe referenciar un valor hex directamente — siempre a través
de `Theme.of(context)` / `ColorScheme` + una `ThemeExtension` propia para los tokens que no
tienen equivalente directo en `ColorScheme` de Material (los cuatro estados de §3.3/3.4, y los
tokens de stat card / status pill). El cambio de tema (claro/oscuro) debe poder alternarse sin
reiniciar la app y respetar la preferencia del sistema operativo por defecto (estándar ya
establecido en `docs/07-portal-ceo.md` §10 para el Portal del CEO, aplicado aquí también).

## 9. Accesibilidad y responsive

- Tamaño mínimo de área táctil: 44x44dp (botones del stepper, "✕" de modales y de chips,
  íconos de acción en `ActionListTile`).
- Contraste mínimo AA (4.5:1) para texto sobre fondo, verificado para ambos temas en §3.
- Ningún estado se comunica solo por color (siempre texto en el `StatusPill`, nunca un punto
  de color solo).
- Soporte de escalado de texto del sistema (no fijar alturas de línea que corten texto
  ampliado).
- Layout responsive: `StatCardGrid` y `SearchFilterBar` se adaptan de mobile angosto a
  pantallas más anchas (tablet); el `MonthCalendarPicker` mantiene proporción de celda
  cuadrada en cualquier ancho.

## 10. Convenciones de nombres sugeridas para Flutter (Mobile)

Solo nombres de referencia — la implementación (Dart) es responsabilidad de Mobile:

- `AppColors` (tokens de §3, con getters que resuelven claro/oscuro vía `Theme.of(context)`).
- `AppTypography` (`TextStyle`s de §4).
- `AppSpacing`, `AppRadius` (constantes de §5).
- `PrimaryButton`, `WarningButton`, `OutlineButton`, `DestructiveButton` (§7.1).
- `StatusPill` + enums `TurnoEstado`, `PacienteEstado` (§7.2).
- `StatCard`, `StatCardGrid` (§7.3).
- `NumericStepperField` (§7.4).
- `MonthCalendarPicker` + enum `CalendarDayState` (§7.5).
- `AppBottomNavigationBar` + `NavItem` (configurable por rol, §7.6).
- `AppHeader` (§7.7).
- `AppModalSheet` (§7.8).
- `SearchFilterBar` (§7.9).
- `ActionListTile` / `PatientListTile` (§7.10).
- `EmptyState` (§7.11).

## 11. Trazabilidad y notas de decisión

### 11.1 Relación con historias de usuario

Este documento es transversal (no pertenece a una sola pantalla); su aplicación pantalla por
pantalla y la trazabilidad HU se documentan en `04-diseno/mapa-pantallas.md` §7 (tabla de
trazabilidad).

### 11.2 Decisiones de diseño que exceden la transcripción original

Documentadas para que Product Manager, Arquitecto y Security las validen antes de
implementación:

1. Estado `neutral` (Completada/Pasada) y refuerzo de `danger` para "Cancelada" — agregados
   por UX/UI porque el dominio de Turnos Profesionales ya contempla cancelación (RN8, HU-12)
   y turnos pasados, no vistos en las capturas originales.
2. Posible ambigüedad entre "Programada" y "Confirmada" (mismo color `warning` en la
   transcripción original) — ver pregunta abierta en §3.4, a resolver con Product Manager.
3. Bottom nav de 4 ítems para Cliente — no existía en las capturas (todas del lado
   Profesional); se define por coherencia de "una sola app" (§7.6.2).
4. Los steppers de "duración de cita", "máximo de citas por día" y "días de anticipación"
   introducen configuración cuantitativa que podría solapar o entrar en tensión con reglas de
   negocio ya definidas (RN3 — la duración la determina el servicio, no una configuración
   general; RN1/RN2 — solapamiento y disponibilidad). **No es rol de UX/UI resolver esta
   tensión de negocio** — se documenta como riesgo/pregunta abierta para Product Manager y
   Arquitecto en `04-diseno/mapa-pantallas.md` §6.
5. `DestructiveButton` y `EmptyState` son componentes agregados por buena práctica de UX/UI,
   no observados en la transcripción.
