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

## 3bis. Verificación de color contra capturas reales (2026-08-07)

> **Origen.** Hasta esta fecha, todo este documento se redactó a partir de una transcripción
> escrita de 20 capturas, sin acceso a los píxeles reales. El CEO cargó 37 capturas reales de su
> app "Turnario Pro" (`04-diseno/referencias/`) que permiten verificar lo ya documentado en vez
> de solo confiar en la transcripción. Esta sección corrige/confirma puntualmente lo de §3; la
> metodología completa y los hallazgos que no encajan en una sección puntual están en **§12**.

- **Confirmado:** la familia de color índigo/periwinkle de `primary` en headers, botones
  primarios, ítem activo de bottom nav y chips seleccionados es correcta cualitativamente (no se
  pudo hacer un muestreo de píxel exacto, así que los valores hex de §3.1 no se tocan). `success`
  (verde), `warning` (ámbar/naranja) y `danger` (rojo/coral) también son cualitativamente
  correctos para Activo/Inactivo (Pacientes). "Programada" (turno) se confirmó como estado real
  usado en la app, con el mismo color ámbar que "Por confirmar" — la pregunta abierta de arriba
  sigue sin resolver, ahora con evidencia real de que el estado existe
  (`Screenshot_20260427_142016_Turnario.jpg`).
- **Corrección — anillo de "Hoy" en el calendario:** §7.5 documentaba el anillo de "Hoy" en
  `primary`. Las capturas muestran el anillo de "Hoy" en **`warning` (ámbar/naranja)**, no en
  `primary`. Detalle completo en §7.5bis.
- **Nuevo hallazgo — botones "verdes" de acción constructiva:** en múltiples pantallas (Gestión
  de Horarios → "Aplicar plantilla al calendario"; Gestión de Pacientes → "Agregar Paciente" /
  "Importar" / "Exportar"; Configuración de Notificaciones y Privacidad y Seguridad → "Guardar";
  una variante de "Guardar Cambios" en Editar Paciente) aparece un botón sólido en **`success`**
  (el verde ya definido en §3.3, no un color nuevo) para acciones de crear/guardar/aplicar —
  coexistiendo, de forma inconsistente, con `PrimaryButton` (índigo) para acciones equivalentes
  en otras pantallas (ej. "Guardar 43 Fechas", "Crear Cita y Notificar Cliente", "Actualizar
  Paciente", "Iniciar sesión"). Ver propuesta de `SuccessButton` en §7.1bis — no se resuelve acá
  cuál debe ser el estándar único; se documenta la inconsistencia real como pregunta para el
  CEO/Product Manager antes de que Mobile fije un único criterio.
- **Nuevo hallazgo — botones "naranja" ligados a edición:** el botón de guardar de una de las dos
  variantes de "Editar Paciente", y el header de esa misma variante, usan `warning` (el mismo
  ámbar/naranja de "Restablecer", ya documentado). Ver §7.1bis y §7.7bis.
- **Confirmado:** ningún estado se comunica solo por color — todo `StatusPill` observado en las
  capturas lleva texto además del color, consistente con §9.

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

## 6bis. Verificación de iconografía contra capturas reales (2026-08-07)

- **Confirmado:** Material Icons para navegación/acciones + emojis decorativos en headers de
  sección aparecen tal como se documentó, de forma consistente en las 37 capturas: ⏰ (Gestión
  de Horarios), 📋 (Configuración de Citas / Información Personal), 🗓️/📅 (Replicar, fechas),
  ⚙️ (Configuración General), 🏥 (Gestión de Pacientes), y el asterisco **"✱"** para Historial
  (`Screenshot_20260427_142016_Turnario.jpg` lo confirma literalmente en el header "Historial de
  [Paciente]", tal como ya anticipaba la nota de §6). También aparecen ☕ (Tiempo de Descanso —
  la transcripción original había usado 🍽️; la app real usa ☕, ambos válidos conceptualmente, se
  deja constancia del emoji real observado), 🚨 (Contacto de Emergencia, nuevo) y 👤
  (Información Personal / Paciente, nuevo).
- **Nuevo — color por categoría en íconos de lista/menú:** en el menú de Configuración
  (`Screenshot_20260423_235930_Turnario.jpg`), los ítems de "Panel Profesional" y "Pagos y
  Señas" usan un color de ícono **distinto por función** (verde para Gestionar Horarios, naranja
  para Nueva Cita, azul para Gestionar Pacientes, naranja para Reportes, magenta para Pagos, gris
  azulado para Consultorio, rosa/rojo para Autorizaciones Médicas) en vez de un color único
  (`primary` o `textSecondary`) para todos los íconos de fila. Se documenta como patrón válido
  para `ActionListTile` en contexto de menú — ver §7.10bis.
- **Bug de encoding a corregir en implementación (no es un patrón de diseño a replicar):** en
  las 8 capturas de `MonthCalendarPicker` revisadas (sesiones del 23 y 25 de abril), el
  encabezado de la semana muestra `MI?` y `S?B` en vez de `MIÉ` y `SÁB` — es un problema de
  codificación de caracteres acentuados en la app de referencia (mojibake), no una decisión de
  diseño. Mobile debe usar las abreviaturas correctas con acentos y no replicar este bug.

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

### 7.1bis. Verificación de Botones contra capturas reales (2026-08-07)

- **Confirmado:** forma píldora, `WarningButton` en `warning` para "Restablecer" (visible en las
  8 capturas de Gestión de Horarios), `OutlineButton` para "Cancelar" en modales.
- **Corrección — `DestructiveButton` es sólido, no outline:** §7.1 especulaba "outline o texto en
  `danger`" por no tener evidencia directa. La captura `Screenshot_20260423_235935_Turnario.jpg`
  (botón "Cerrar Sesión" del menú Configuración) muestra un botón **sólido** `danger`, ancho
  completo, texto blanco bold — no outline. Se corrige la especificación: `DestructiveButton`
  para acciones de alto impacto (cerrar sesión, eliminar cuenta) usa fondo `danger` sólido; queda
  abierto si una variante outline sigue siendo válida para acciones destructivas de menor impacto
  (ej. "Eliminar" en una fila de lista) — no hay evidencia directa de esa variante en las
  capturas, no se fuerza.
- **Corrección — el radio de esquina no es uniformemente píldora:** además de la píldora completa
  (`radius.chip`, 999dp) confirmada en botones de barra de acción standalone (ej. "Guardar 43
  Fechas", "Restablecer", "Aplicar plantilla al calendario", "Agregar Paciente"/"Importar"/
  "Exportar"), los footers de modal/formulario y la pantalla de login
  (`Screenshot_20260427_095249_Turnario.jpg` "Crear Cita y Notificar Cliente";
  `Screenshot_20260427_133828_Turnario.jpg` "Actualizar Paciente";
  `Screenshot_20260423_235935_Turnario.jpg` "Cerrar Sesión";
  `Screenshot_20260805_202552_Turnario.jpg` "Iniciar sesión"/"Google"/"Crear Cuenta") usan un
  radio **moderado, más cercano a `radius.card` (16dp)** que a la píldora completa. Se
  documentan como dos variantes válidas según contexto: `radius.chip` para botones de barra de
  acción/footer de pantalla completa, `radius.card` para botones de footer de modal/formulario y
  pantallas de autenticación — Mobile debe confirmar con UX/UI el caso ambiguo, no asumir
  siempre píldora.
- **Nuevo componente propuesto — `SuccessButton`:** mismo tratamiento que `PrimaryButton` pero
  con fondo `success` sólido (reutiliza el token ya definido en §3.3, no es un color nuevo). Ver
  evidencia y advertencia sobre su uso inconsistente en §3bis y §12.
- **Nuevo — asterisco de campo obligatorio:** todas las capturas de formularios (Crear Nueva
  Cita, Editar Paciente) marcan los campos requeridos con un **"\*"** pegado al label (ej.
  "Servicio \*", "Nombre completo \*"). No había convención documentada — se adopta como
  estándar de formularios para toda la app.

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

### 7.4bis. Verificación de Stepper numérico contra capturas reales (2026-08-07)

- **Confirmado:** el patrón "− valor +" con botones circulares se usa para Duración de Cita,
  Máximo de Citas por Día, Anticipación de Reservas y para los bloques de "Horarios por Defecto"
  (Inicio/Fin en formato hora); confirmado también el deshabilitado de botón (no desaparición)
  al llegar al máximo (ej. "Citas Máximas por Día" con "+" atenuado al llegar a 20,
  `Screenshot_20260423_235154_Turnario.jpg`).
- **Nuevo — variante de flechas arriba/abajo para horas de Tiempo de Descanso:** el control de
  "Hora de Inicio"/"Hora de Fin" de "Tiempo de Descanso" no usa "− valor +" sino un par de
  **chevrons arriba/abajo (▾/▴)** a los lados del valor de hora — visto de forma consistente
  tanto en la versión elaborada del 23 de abril como en la compacta del 25/27 de abril. Se
  documenta como una **variante de `NumericStepperField`** específica para valores de hora del
  día (a diferencia de duraciones/cantidades, que usan −/+) — Mobile puede implementarla como un
  parámetro de variante (`stepperGlyph: minusPlus | chevron`) del mismo widget en vez de un
  widget aparte, ya que el resto del comportamiento (deshabilitar en límite, valor central bold)
  es el mismo.

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

### 7.5bis. Verificación de Calendar Picker contra capturas reales (2026-08-07)

Esta es la corrección más importante de toda la revisión de color/estado — verificada contra 8
capturas de `MonthCalendarPicker` (dos sesiones independientes: 23 y 25 de abril, esta última
con una captura de leyenda completa, `Screenshot_20260425_040258_Expo Go.jpg`).

- **Corrección — "Hoy" usa `warning`, no `primary`:** la leyenda real dice "Seleccionada · 
  Disponible · Hoy · Pasada" con swatches azul/verde/**ámbar**/gris, y la celda del día actual se
  renderiza con un anillo **ámbar/naranja** (`warning`), no índigo. Confirmado dos veces: en la
  leyenda y en la celda real del día 25 (`Screenshot_20260425_040313_Expo Go.jpg` y su duplicado
  con anotación en rojo del CEO, `Screenshot_20260425_043732_Expo Go~2 (1).jpg` — la fecha de
  captura, 25 de abril, coincide con el día marcado como "Hoy"). **Se corrige la tabla de arriba:
  "Hoy" → borde `warning` (anillo), fondo `surface`.**
- **Ajuste — "Disponible" no se observó renderizada en una celda real** en las capturas
  disponibles, solo en el swatch de la leyenda (círculo con borde verde/`success`). Toda fecha
  dentro del mes que no estaba ya guardada se veía con **borde lavanda claro (no verde), fondo
  transparente/blanco** — un estado intermedio de "elegible, aún no seleccionada" sin fila propia
  en la tabla de arriba. Se agrega como estado nuevo: **"Elegible (no seleccionada)"** — borde
  `primaryContainer` o similar, fondo `surface`, usado mientras el usuario arma una selección
  múltiple antes de guardar. No se afirma que reemplace al "Disponible" documentado (podría
  aplicar a una vista de solo lectura no capturada en esta tanda, ej. el calendario de reservas
  del lado Cliente) — se deja como ampliación, no como reemplazo.
- **Confirmado con matiz — celda "Seleccionada":** fondo `primary` sólido con **dos badges
  superpuestos**, no uno: el ícono de reloj ya documentado ("día con horario configurado") y,
  además, un pequeño círculo/check blanco que indica que la fecha está marcada en la selección
  múltiple de esta sesión de edición — dos señales independientes que pueden convivir en la
  misma celda.
- **Corrección — chips de fechas seleccionadas SIN "✕":** en las 8 capturas del bloque "Fechas
  Seleccionadas:" (ej. `Screenshot_20260423_235137_Turnario.jpg`), **ningún chip muestra una "✕"
  para quitarlo** — son chips de solo lectura/resumen, no removibles individualmente desde ahí.
  El patrón removible con "✕" documentado arriba no se observó en el flujo de "Gestión de
  Horarios" tal como está — se conserva la especificación original por si aplica en otro punto de
  la app (no hay evidencia que la contradiga activamente salvo su ausencia acá), pero queda
  marcada como no confirmada.
- **No confirmado / captura incompleta:** al pie de dos capturas
  (`Screenshot_20260425_040313_Expo Go.jpg`, `Screenshot_20260425_043732_Expo Go~2 (1).jpg`) se
  alcanza a ver el inicio de una fila adicional de leyenda — "Con citas" y "Disponible" — tapada
  por la barra de navegación del sistema Android, sin poder leer su color/ícono real. Se deja
  constancia explícita en vez de inventar su estilo.

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

### 7.7bis. Verificación de Header contra capturas reales (2026-08-07)

§7.7 documentaba `AppHeader` como uniformemente `primary` sólido "en la mayoría de pantallas
principales". Las 37 capturas muestran **tres tratamientos de header distintos**, no uno:

| Tratamiento | Dónde se observó | Ejemplo |
|---|---|---|
| `primary` sólido, texto blanco | Gestión de Horarios (6 capturas), modal "Crear Nueva Cita" | `Screenshot_20260423_235124_Turnario.jpg`, `Screenshot_20260427_095249_Turnario.jpg` |
| `surface` (blanco), texto `textPrimary`, con un ícono de color como acento junto al título | Dashboard, la mayoría de modales de Pacientes (Agregar Nuevo Horario, Configuración de Notificaciones, Privacidad y Seguridad, Agendar Cita, Detalles del Paciente, Historial), una de las dos variantes de "Editar Paciente" | `Screenshot_20260410_190938_Expo Go.jpg` (Dashboard), `Screenshot_20260427_133828_Turnario.jpg` (Editar Paciente) |
| `warning` (ámbar/naranja) sólido, texto blanco | Una de las dos variantes de "Editar Paciente" | `Screenshot_20260427_102356_Turnario.jpg` |

El tratamiento **`surface` + ícono de acento** es el más frecuente de los tres en esta muestra.
Se corrige §7.7: `AppHeader` debe soportar (al menos) estas dos variantes con un parámetro de
color de fondo (`primary | surface | warning`), y **Dashboard específicamente usa `surface`, no
`primary`** (corrección puntual, ver también `mapa-pantallas.md` §5.2bis). La variante `warning`
se observó una sola vez — no hay evidencia suficiente para afirmar que "editar" siempre deba
llevar header `warning`; se documenta como variante observada, no como regla.

**Corrección adicional — Dashboard sí tiene ícono de "cambiar de vista":** la captura
`Screenshot_20260410_190938_Expo Go.jpg` muestra un botón cuadrado redondeado con ícono de
flechas cruzadas (⇄) arriba a la derecha del header del Dashboard — el mismo ícono que
`mapa-pantallas.md` §5.2 había decidido **no** incluir por ser HU-27 ambigua en ese punto. El
ícono existe visualmente en la app de referencia; su comportamiento (a qué cambia) no se puede
inferir de una captura estática. Ver corrección completa en `mapa-pantallas.md` §5.2bis — no se
resuelve acá qué hace el ícono, solo se corrige que su existencia visual sí está evidenciada.

### 7.8 Modal (`AppModalSheet`)

Bottom sheet o dialog con: header (`sectionTitle` + botón "✕" para cerrar, alineado a la
derecha), contenido central scrolleable, footer fijo (no scrollea) con dos botones — un
`OutlineButton` ("Cancelar") a la izquierda/abajo y un `PrimaryButton` (acción, ej. "Guardar",
"Agendar") a la derecha/arriba, o ambos en fila si el ancho lo permite. Esquinas superiores
`radius.modalTop`. Usado en: Agregar Horario, Agendar Cita manual, Editar Paciente,
Configuración de Citas, Tiempo de Descanso, Replicar en semanas.

### 7.8bis. Verificación de Modal contra capturas reales (2026-08-07)

- **Corrección estructural — no es (solo) bottom sheet:** casi todos los modales observados
  (Crear Nueva Cita, Agregar Nuevo Horario, Configuración de Notificaciones, Privacidad y
  Seguridad, Editar Paciente, Agendar Cita, Detalles del Paciente, Historial de Paciente, Gestión
  de Autorizaciones Médicas) se renderizan como **página completa de borde a borde** (header
  propio pegado al status bar + botón "✕" circular a la derecha + footer fijo), no como una hoja
  parcial que deja ver el fondo atenuado detrás. Se corrige: el patrón principal de
  `AppModalSheet` en esta app es de **pantalla completa (full-screen route)** con header y footer
  fijos; un bottom sheet parcial no se observó en ninguna de las 37 capturas. `radius.modalTop`
  deja de aplicar como default si el contenedor es pantalla completa — Mobile debe confirmar con
  UX/UI si se mantiene algún caso de bottom sheet parcial real o si se simplifica todo a rutas de
  pantalla completa.
- **Corrección — el footer no siempre tiene 2 botones:** "Configuración de Notificaciones"
  (`Screenshot_20260427_095405_Turnario.jpg`) y "Privacidad y Seguridad"
  (`Screenshot_20260427_095421_Turnario.jpg`) muestran **3 botones**: "Cancelar" (outline) +
  "Guardar" (`success`, verde) + "Restablecer" (`warning`, naranja). Con 3 botones compartiendo
  el ancho se observó un **bug real de recorte de texto** ("Restablecer" partido en
  "Restablece/r" en ambas capturas) — advertencia para QA: probar el footer de 3 botones en
  anchos angostos antes de dar por buena esa composición.
- **Confirmado — patrón de 2 botones:** Crear Nueva Cita, Agregar Nuevo Horario, Editar Paciente,
  Agendar Cita usan "Cancelar" (outline, izquierda) + acción primaria (derecha), aunque el color
  de la acción primaria varía entre `primary` y `success` según la pantalla (ver §7.1bis).
- **Corrección de copy:** el modal de Agendar Cita manual (HU-23) se llama en la app real
  **"Crear Nueva Cita"** (no "Agendar Cita" a secas — ese título se reserva para la variante que
  parte de un paciente ya elegido, ver `mapa-pantallas.md` §5.7bis) y su botón de acción dice
  **"Crear Cita y Notificar Cliente"**, más largo que "Agendar Cita" del wireframe original
  (ocupa 2 líneas). Detalle completo en `mapa-pantallas.md` §5.7bis.
- **Advertencia — artefactos de debug a NO replicar:** una captura de "Editar Paciente"
  (`Screenshot_20260427_102356_Turnario.jpg`) muestra un botón rojo "🔍 Debug: Ver Datos" debajo
  del header, y "Detalles del Paciente" (`Screenshot_20260427_121228_Turnario.jpg`) expone el ID
  crudo de base de datos como si fuera un dato de producto. Son artefactos de una app todavía en
  desarrollo (consistente con lo que ya avisó el CEO), no parte del lenguaje visual a copiar; el
  ID crudo además es un dato a revisar con Security si se replica esa pantalla (ya hay una nota
  de privacidad general en `mapa-pantallas.md` §6 para Ficha de Paciente).

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

### 7.10bis. Verificación de ActionListTile / PatientListTile contra capturas reales (2026-08-07)

`Screenshot_20260427_095459_Turnario.jpg` (Gestión de Pacientes) da evidencia directa de esta
fila de card. Corrige varios puntos de arriba:

- **Acciones rápidas reales: Ver, Editar, Agendar, Historial** (no "historial / editar /
  contactar / eliminar"). Cada acción es un ícono + label de texto debajo (mini-botón vertical),
  en un chip de fondo suave de color propio por acción (azul=Ver, naranja=Editar, verde=Agendar,
  violeta=Historial) — no son 4 íconos monocromáticos en línea. No hay acción de "contactar" ni
  de "eliminar/desactivar" visible en la fila.
- **`StatusPill` real lleva borde + punto de color, no solo relleno pastel:** "🔴 Inactivo" y
  "🟢 Activo" se ven como píldora con borde del color del estado + fondo pastel muy claro + punto
  de color sólido antes del texto — un refinamiento sobre "fondo pastel, texto bold en color
  base" (§7.2), que se mantiene válido sumándole el borde y el punto.
- **El fondo de la card cambia según estado:** la card de un paciente Inactivo tiene fondo gris
  claro (no blanco/`surface` puro), mientras que un paciente Activo mantiene `surface` blanco. No
  estaba documentado que el estado afectara el fondo de la card entera, solo el pill.
- **Avatar es un ícono de silueta genérico, no iniciales:** círculo `primary` sólido con ícono de
  persona en blanco — se corrige la redacción de arriba ("avatar/inicial circular") a "avatar
  (ícono de persona genérico; iniciales quedan como alternativa válida, no confirmada en
  capturas)".
- **Confirmado — más campos visibles de lo documentado:** email y teléfono se muestran como texto
  plano (no ocultos tras un ícono), más una línea "Notas:" en itálica y "Última visita:" en
  itálica gris — más rico que la única línea secundaria documentada arriba.
- **Confirmado — stat row de 4, no 3:** el resumen de Gestión de Pacientes muestra Total /
  Activos / Inactivos / **Nuevos** (4 valores) en una sola card blanca con 4 columnas (sin sombra
  individual por columna) — no 4 `StatCard` separadas con sombra propia. Se agrega "Nuevos" como
  cuarta métrica observada — ver corrección completa del wireframe en `mapa-pantallas.md`
  §5.8bis.

### 7.11 Estado vacío (`EmptyState`)

*(Adición de UX/UI — buena práctica no descripta en la transcripción original.)* Ícono o
ilustración simple + título corto bold + texto de ayuda gris + botón opcional de acción
("Agregar tu primer paciente", "Aún no configuraste tus horarios"). Usado en cualquier
listado que pueda estar vacío (Pacientes, Notificaciones, Historial).

### 7.12 Card de configuración con ícono (`SettingCard`) — nuevo, confirmado en capturas (2026-08-07)

Card `surface`, `radius.card`, contenido vertical: ícono circular de color (ej. azul para
duración, naranja para cantidad, verde para anticipación) arriba a la izquierda, título bold
debajo, texto de ayuda gris debajo del título, y el control (típicamente `NumericStepperField`)
ocupando el ancho completo al final. Observado en la versión "elaborada" de Gestión de Horarios
del 23 de abril (Duración de Citas, Citas Máximas por Día, Anticipación de Reservas, Descanso
para Almuerzo, cada uno en su propia `SettingCard`). **Nota de vigencia:** las capturas más
recientes del mismo flujo (25 y 27 de abril) muestran una versión más compacta de las mismas
configuraciones, sin ícono circular ni card propia por ítem — ver `mapa-pantallas.md` §5.4bis
para el detalle de esta diferencia entre capturas de distinta fecha. Se documenta igual
`SettingCard` por ser un patrón real y reutilizable, pero el equipo debe confirmar con el CEO
cuál de las dos versiones es la vigente antes de que Mobile la implemente.

**Resuelto (2026-08-09): el CEO eligió la versión compacta — `SettingCard` NO se implementa en
v1.** Se conserva esta documentación como referencia histórica del patrón observado, no como
componente a construir.

### 7.13 Card de resumen calculado (`ResumenCard` / `SummaryCallout`) — nuevo, confirmado en capturas (2026-08-07)

Card con fondo tintado (celeste/azul muy claro, distinto de `primaryContainer`) y borde sutil del
mismo tono, título con ícono (ej. 🕐 "Resumen del Descanso"), y dentro una sub-card blanca con 2
(o más) mini-stats en columna: ícono circular pequeño, valor bold, etiqueta gris — usado para
mostrar un resultado **calculado en vivo** a partir de otros controles de la misma pantalla (ej.
"Duración Total: 2h 0min" y "Período: 12:00–14:00", calculados a partir de los steppers de Hora
de Inicio/Fin). Requiere un token de color nuevo no definido en §3 (`infoContainer`/`info`,
celeste, distinto de los 4 estados de §3.3) — se deja sin hex hasta poder hacer un muestreo de
color más preciso; por ahora usar un azul/celeste claramente distinguible de `primary` y
`primaryContainer`. Misma nota de vigencia que §7.12: observado en la versión elaborada del 23 de
abril, no confirmado en las capturas más recientes del mismo flujo.

**Resuelto (2026-08-09): mismo motivo que §7.12 — el CEO eligió la versión compacta,
`ResumenCard`/`SummaryCallout` NO se implementa en v1.**

### 7.14 Barra de pestañas (`SegmentedTabBar`) — nuevo, confirmado en capturas (2026-08-07)

Fila horizontal de labels de texto (sin íconos), la pestaña activa en `primary` bold con
subrayado/indicador inferior en `primary`, las inactivas en `textSecondary`. Observado en
"Gestión de Autorizaciones Médicas" (pestañas "Autorizaciones", "Relaciones", "Registro de
Accesos", `Screenshot_20260427_095602_Turnario.jpg`) — única pantalla de las 37 capturas que usa
este patrón de navegación. Se documenta el componente por si Product Manager decide llevar
adelante esa pantalla (ver `mapa-pantallas.md` §9 — candidata a sección nueva, no diseñada en
profundidad todavía).

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
- `PrimaryButton`, `WarningButton`, `OutlineButton`, `DestructiveButton`, `SuccessButton`
  (§7.1, §7.1bis — `SuccessButton` y el relleno sólido de `DestructiveButton` son hallazgos de
  la verificación contra capturas reales del 2026-08-07, a confirmar como estándar con Product
  Manager/CEO antes de fijarlos en código).
- `StatusPill` + enums `TurnoEstado`, `PacienteEstado` (§7.2, refinado en §7.10bis).
- `StatCard`, `StatCardGrid` (§7.3).
- `NumericStepperField` (con variante `stepperGlyph: minusPlus | chevron`, §7.4, §7.4bis).
- `MonthCalendarPicker` + enum `CalendarDayState` (§7.5, corregido en §7.5bis — agregar el
  estado `elegible` y corregir el color de `hoy` a `warning`).
- `AppBottomNavigationBar` + `NavItem` (configurable por rol, §7.6).
- `AppHeader` (§7.7, con parámetro de variante `primary | surface | warning`, §7.7bis).
- `AppModalSheet` (§7.8, mayormente full-screen en vez de bottom sheet parcial, §7.8bis).
- `SearchFilterBar` (§7.9).
- `ActionListTile` / `PatientListTile` (§7.10, refinado en §7.10bis).
- `EmptyState` (§7.11).
- `SettingCard` (§7.12, nuevo — confirmar vigencia, ver nota de §7.12).
- `ResumenCard` / `SummaryCallout` (§7.13, nuevo — requiere token de color `info` sin definir).
- `SegmentedTabBar` (§7.14, nuevo — usado solo en la pantalla candidata de §9 de
  `mapa-pantallas.md`).

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

## 12. Verificación contra capturas reales de la app de referencia (2026-08-07)

### 12.1 Origen y metodología

Hasta esta fecha, todo este documento (y `mapa-pantallas.md`) se redactó a partir de una
transcripción escrita que hizo el Director General IA de 20 capturas que el CEO pegó en el chat
— ni la sesión principal ni UX/UI habían tenido acceso directo a los píxeles reales. El CEO
cargó 37 capturas reales de "Turnario Pro" (su app personal, en pre-producción, autorizada
explícitamente como referencia sin restricciones) en `04-diseno/referencias/`: 29 son capturas
directas de la app ("Turnario"), 8 son la misma app corriendo dentro de Expo Go (cliente de
desarrollo — mismo contenido de app, distinto "chrome" del sistema alrededor, y en varios casos
con la fuente del sistema agrandada, útil como evidencia adicional de que el layout tolera
escalado de texto, ver §9). Las capturas abarcan un rango de fechas amplio: 10, 23, 25 y 27 de
abril y 5 de agosto de 2026 — con **evolución real de la UI entre capturas de distinta fecha** en
al menos una pantalla (Gestión de Horarios, ver §12.3). Esta sección resume la revisión completa;
las correcciones puntuales están en las secciones "bis" ya insertadas junto a cada tema (§3bis,
§6bis, §7.1bis, §7.4bis, §7.5bis, §7.7bis, §7.8bis, §7.10bis) y en los nuevos componentes
§7.12–§7.14. Las correcciones de pantallas/navegación (fuera del alcance de este documento) están
en `mapa-pantallas.md` §9.

### 12.2 Confirmado sin cambios

- Paleta cualitativa (`primary` índigo/periwinkle, `success` verde, `warning` ámbar, `danger`
  rojo/coral) para headers, botones, estados y navegación.
- Navegación inferior de 6 ítems del lado Profesional, orden e íconos exactos: Dashboard,
  Horarios, Pacientes, WhatsApp, Notificaciones, Configuración
  (`Screenshot_20260423_235924_Turnario.jpg` y todas las capturas con bottom nav visible).
- Emojis decorativos en headers de sección, nunca como único indicador (§6, confirmado en las 37
  capturas).
- El ícono "✱" para Historial (la transcripción original ya lo había capturado bien).
- `NumericStepperField` "− valor +" para configuración cuantitativa, con deshabilitado (no
  desaparición) de botón en el límite.
- Los stat cards de Historial de Paciente (Citas Totales, Completadas, Tratamientos, Notas
  Médicas) y los campos por turno (fecha, hora, servicio, profesional, duración, costo, estado de
  pago) del wireframe de Historial — coinciden de forma cercana con
  `Screenshot_20260427_142016_Turnario.jpg`.
- Los campos de Ficha de Paciente (nombre, fecha de nacimiento, género, teléfono, email,
  dirección, alergias, contacto de emergencia con nombre/teléfono/relación) — coinciden con
  `Screenshot_20260427_133817_Turnario.jpg` y `_141933_`.
- El campo de texto libre "Hora" con placeholder tipo "10:00, 14:30" en el modal de agendar cita
  manual **sí existe tal cual** en la app real (`Screenshot_20260427_133838_Turnario.jpg`) — la
  transcripción original que dio origen a este documento no se equivocó en ese punto; la
  alternativa de chips propuesta en `mapa-pantallas.md` §5.7 sigue siendo una recomendación de
  UX/UI, no una corrección de un malentendido.
- El bloque "Seguridad de la cuenta" de Privacidad y Seguridad (`mapa-pantallas.md` §5.13), ya
  marcado ahí como "adición de UX/UI, pendiente de HU", **no aparece en la app real**
  (`Screenshot_20260427_095421_Turnario.jpg` termina en "Compartir Datos de Uso", sin sección de
  seguridad de cuenta) — confirma que efectivamente era una adición de UX/UI y no algo que la
  transcripción hubiera pasado por alto.
- El CEO usa su propia app con un rubro no médico ("Entrenamiento Personal",
  `Screenshot_20260423_235924_Turnario.jpg`) — confirma en la práctica el supuesto multi-rubro
  (D1) que ya asumía este documento.

### 12.3 Deriva de versión detectada — Gestión de Horarios

Dentro de las propias capturas (no contra este documento) hay dos versiones visiblemente
distintas de la sección "Configuración General" / "Tiempo de Descanso" de Gestión de Horarios:

- **23 de abril** (`Screenshot_20260423_235154_Turnario.jpg` a `_235203_`): versión "elaborada" —
  3 `SettingCard` con ícono propio (Duración de Citas, Citas Máximas por Día, Anticipación de
  Reservas), sección "Tiempo de Descanso" aparte con su propia card grande ("Descanso para
  Almuerzo", íconos de sol/luna, `ResumenCard` de duración total y período), y **una sección "📋
  Configuración de Citas" adicional más abajo que repite los mismos 3 valores** en un formato de
  lista compacta sin íconos — aparenta ser contenido duplicado dentro de la misma pantalla.
- **25 y 27 de abril** (`Screenshot_20260425_040313_Expo Go.jpg`,
  `Screenshot_20260427_095441_Turnario.jpg`, dos sesiones independientes que coinciden entre sí):
  versión "compacta" — una sola card "Configuración General" con los 3 valores en fila simple
  (sin ícono, sin card individual) seguida directamente de "☕ Tiempo de Descanso" con los
  steppers de chevron, sin `ResumenCard` y sin la sección duplicada "Configuración de Citas".

Dado que dos sesiones independientes y posteriores coinciden en la versión "compacta", esta
revisión trató esa versión como la más representativa del estado actual de la app de referencia,
pero **no se descarta la versión "elaborada"** — se documenta igual (`SettingCard`, `ResumenCard`
en §7.12/§7.13) por si es la dirección que el CEO prefiere.

**Resuelto — el CEO confirmó (2026-08-09) la versión compacta como definitiva.** `SettingCard` y
`ResumenCard` (§7.12/§7.13) quedan documentados como referencia histórica, sin implementarse en
v1.

### 12.4 Ambigüedades a resolver con el CEO antes de avanzar

- **Dos pantallas "Detalles del Paciente" distintas** (header índigo con ID crudo/Historial de
  Visitas/Notas vs. header blanco con datos personales completos/Contacto de Emergencia) — ver
  detalle en `mapa-pantallas.md` §5.9bis. **Resuelto (2026-08-09): CEO eligió la Variante B
  (datos personales) — ver mapa-pantallas.md §5.9bis.**
- **Posible duplicación de navegación:** "Configurar Disponibilidad" (menú Cuenta) y "Gestionar
  Horarios" (menú Panel Profesional) podrían llevar al mismo lugar o ser flujos distintos — no se
  puede determinar con capturas estáticas.
- **Botón "Guardar"/acción constructiva:** `success` (verde) vs. `primary` (índigo) usados de
  forma intercambiable para lo que parece la misma acción en distintas pantallas — ver §3bis y
  §7.1bis.
- **Franja de color a la izquierda de las cards de turno** (Dashboard y "Crear Nueva Cita") se ve
  siempre verde en las capturas disponibles, incluso en una card con estado "Por confirmar"
  (ámbar) — no se pudo confirmar si esa franja está pensada para llevar el color del estado o si
  es puramente decorativa. Se documenta el elemento sin asignarle una regla de color, a falta de
  más evidencia.
- Una de las 37 capturas (`Screenshot_20260425_043732_Expo Go~2 (1).jpg`) tiene un **círculo
  dibujado a mano en rojo** sobre el header (ícono, título y subtítulo "Gestión de Horarios /
  Primera de Abril") — parece una anotación del propio CEO marcando algo de interés, pero no se
  puede inferir qué específicamente sin preguntarle directamente. **Consultado con el CEO
  (2026-08-09): no aplica.**

### 12.5 Capturas parcialmente ilegibles

- `Screenshot_20260425_040313_Expo Go.jpg` y `Screenshot_20260425_043732_Expo Go~2 (1).jpg`: la
  fila de leyenda "Con citas" / "Disponible" al pie del calendario queda tapada por la barra de
  navegación del sistema Android — no se pudo leer su estilo (ver §7.5bis).
- Ninguna otra de las 37 capturas presentó recorte, desenfoque u overlay que impidiera leer su
  contenido — el resto de esta revisión se basa en lectura directa, no en inferencia.
