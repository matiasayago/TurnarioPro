# Mapa de Pantallas y Flujos — Turnos Profesionales

**Rol:** UX/UI
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md` (casos de uso), `02-backlog/backlog.md`,
descripción detallada de capturas de otra app del CEO (base de estilo visual y
funcionalidades nuevas, ver `04-diseno/sistema-diseno.md` §0).

> **Actualización (rediseño visual + funcional):** el CEO pidió tomar como base el estilo
> visual y las funcionalidades de otra app de su propiedad. Esto generó `sistema-diseno.md`
> (tokens y componentes) y una ampliación importante del lado Profesional de este mapa
> (Dashboard, Gestión de Horarios avanzada, Gestión de Pacientes avanzada, WhatsApp,
> Configuración). Product Manager incorporó en paralelo las épicas E9–E14 y las historias
> HU-16 a HU-32 en `02-backlog/backlog.md` — este documento ya referencia esos números
> directamente en la tabla de trazabilidad (§7) en vez de dejarlos genéricos. Donde una
> pantalla o un detalle de interacción excede lo que cubre la HU asignada (ej. algunos ítems
> de "Seguridad de la cuenta" más allá de HU-32), se marca explícitamente como **"adición de
> UX/UI, pendiente de HU"** para no dar por aprobado algo que Product Manager todavía no
> escribió.

## 1. Principio de diseño

Una sola app Flutter con **dos modos** según el rol del usuario autenticado (Cliente /
Profesional) — no dos apps separadas. El modo se determina en el login y no es
intercambiable por el usuario (un profesional no "cambia" a modo cliente en este alcance).

## 2. Sistema de diseño

La paleta de colores, tipografía, espaciado y los componentes reutilizables (stat card,
status pill, stepper numérico, calendar picker, bottom nav, botones, modal, etc.) están
documentados por separado en **[`04-diseno/sistema-diseno.md`](sistema-diseno.md)**. Todas
las pantallas de este mapa se apoyan en esos componentes; no se redefine su estilo pantalla
por pantalla.

## 3. Mapa de navegación — modo Cliente

Navegación inferior de 4 ítems (`AppBottomNavigationBar`, ver `sistema-diseno.md` §7.6.2) —
decisión de UX/UI para unificar el patrón de navegación con el lado Profesional, ya que las
capturas del CEO no cubrían el lado Cliente:

```
[ Buscar ]   [ Mis Turnos ]   [ Notificaciones ]   [ Configuración ]
```

```
Login / Registro
   │
   ▼
Buscar (tab) ──► Buscar Negocios ──► Detalle de Negocio (servicios) ──► Elegir Profesional
                                                                              │
                                                                              ▼
                                                                    Horarios Disponibles
                                                                              │
                                                                              ▼
                                                              Confirmar Turno (+ pago si aplica, D2)
                                                                              │
                                                                              ▼
Mis Turnos (tab) ───────────────────────────────────────────────────► Detalle de Turno
                                                                                  │
                                                                    ┌─────────────┴─────────────┐
                                                                    ▼                           ▼
                                                               Cancelar                  Reprogramar

Notificaciones (tab) ──► Bandeja de notificaciones ──► [⚙] Configuración de Notificaciones

Configuración (tab) ──► Menú de Configuración (Cliente) ──► Privacidad y Seguridad
                                                        └──► Configuración de Notificaciones
```

Pantallas: **Buscar Negocios** (HU-00b), **Detalle de Negocio** (HU-07), **Elegir
Profesional** (HU-08), **Horarios Disponibles** (HU-09), **Confirmar Turno / Pago** (HU-09b),
**Mis Turnos** (HU-12, HU-13), **Bandeja de Notificaciones** (HU-14, nueva pantalla — antes
solo se especificaba el envío de la notificación, no dónde consultarlas), **Configuración de
Notificaciones** (HU-26, granular, nueva), **Menú de Configuración** (nueva, hub de
navegación) y **Privacidad y Seguridad** (HU-32 para el bloque de privacidad; el bloque
"Seguridad de la cuenta" es adición de UX/UI pendiente de HU — ver §7).

El menú de Configuración del Cliente es una versión reducida del menú del Profesional (§4):
solo trae las secciones "Cuenta" y "Aplicación" (ver §5.12) — no existe "Panel Profesional"
del lado Cliente.

## 4. Mapa de navegación — modo Profesional

Navegación inferior de 6 ítems, tal como en las capturas del CEO (`sistema-diseno.md`
§7.6.1):

```
[ Dashboard ]   [ Horarios ]   [ Pacientes ]   [ WhatsApp ]   [ Notificaciones ]   [ Configuración ]
```

```
Login
   │
   ▼
Dashboard (tab) ──► Resumen del día + próximas citas ──► Detalle de Turno
   │                                                            │
   │                                                            └──► (ver ficha del paciente)
   ├──► [Ver agenda >] Agenda semanal completa (HU-06) ──► [Bloquear rango] Excepciones (HU-15)
   │
   └──► [+] Agendar Cita manual (modal, HU-23)

Horarios (tab) ──► Gestión de Horarios (HU-05, calendario + plantillas)
   ├──► Modal: Agregar Horario
   ├──► Modal: Replicar en Semanas/Meses (HU-17)
   └──► ⚙️ Configuración General ──► 📋 Configuración de Citas (HU-16) + 🍽️ Tiempo de
                                     Descanso (HU-18) — ver riesgo de precedencia en §6

Pacientes (tab) ──► Gestión de Pacientes (HU-10 + HU-19, extendida)
   ├──► Ficha de Paciente (ver/editar) (HU-20)
   └──► Historial de Paciente enriquecido (HU-11 + HU-21, extendida)

WhatsApp (tab) ──► Estado de conexión + log de mensajes (HU-24 — bloqueada, ver §6)
                    └──► [Ir a Configuración >] Configuración de Notificaciones

Notificaciones (tab) ──► Bandeja de notificaciones (HU-14b + HU-25)
                          └──► [⚙] Configuración de Notificaciones (HU-26, granular)

Configuración (tab) ──► Menú de Configuración (Profesional)
   ├──► Cuenta: Mi Perfil, Privacidad y Seguridad (HU-32 + adición de UX/UI, ver §5.13),
   │    Cerrar sesión
   ├──► Aplicación: Tema, Idioma, Configuración de Notificaciones
   └──► Panel Profesional (solo si el usuario también es Administrador del negocio, ver §6):
        Datos del Consultorio (HU-31), Configuración de Servicios (HU-04b),
        Configuración de Pagos y Cobros (HU-30), Reportes (HU-28),
        Mi Plan — Suscripción Pro (HU-29 — bloqueada, decisión de negocio pendiente)
```

Pantallas: **Dashboard** (nueva, HU-27), **Agenda semanal completa** (HU-06, reubicada),
**Excepciones** (HU-15, reubicada dentro de Agenda), **Gestión de Horarios** (HU-05 + HU-16 +
HU-18, reemplaza "Definir Disponibilidad"), **Agendar Cita manual** (nueva, HU-23), **Gestión
de Pacientes** (HU-10 + HU-19, extendida, reemplaza "Mis Clientes"), **Ficha de Paciente**
(nueva, HU-20), **Historial de Paciente** (HU-11 + HU-21, extendida), **Configuración de
Servicios** (HU-04b, sin cambios de contenido, reubicada dentro del menú de Configuración),
**WhatsApp** (nueva, HU-24 — bloqueada), **Configuración** (menú, nueva), **Privacidad y
Seguridad** (nueva, HU-32 para el bloque de privacidad; el bloque de "Seguridad de la cuenta"
es adición de UX/UI pendiente de HU), **Configuración de Notificaciones** (HU-26, granular),
**Bandeja de Notificaciones** (HU-14b + HU-25).

## 5. Wireframes conceptuales

### 5.1 Horarios Disponibles (Cliente) — HU-09

Sin cambios respecto de la versión anterior de este documento.

```
+-----------------------------------------------------+
| < Volver          Dr. García — Consulta general      |
+-----------------------------------------------------+
| Jue 7 ago  | Vie 8 ago  | Lun 11 ago | Mar 12 ago    |
+-----------------------------------------------------+
|  10:00     |  09:30     |  (sin lugar)| 14:00        |
|  10:30     |  11:00     |             | 14:30        |
|  ...       |  ...       |             | ...          |
+-----------------------------------------------------+
| ⓘ No hay lugar en los próximos días elegidos —       |
|   próximo horario disponible: Mar 12, 14:00 (D5)     |
+-----------------------------------------------------+
|              [ Reservar 10:00 - Jue 7 ]              |
+-----------------------------------------------------+
```

### 5.2 Dashboard (Profesional) — HU-27

Header con `AppHeader` (fondo `primary`). Stat cards con `StatCardGrid` (2–4 columnas, ver
`sistema-diseno.md` §7.3). Cada card de "Próximas citas" usa `StatusPill` para el estado, más
una acción rápida "Completar" (HU-27: marcar el turno como completado sin abrir el detalle).

```
+-----------------------------------------------------+
| Hola, Dr. García              Jue 7 de agosto        |
+-----------------------------------------------------+
| [ 8 ]           | [ 2 ]             | [ 5 ]          |
| Pacientes hoy    | Citas pendientes  | Completadas    |
+-----------------------------------------------------+
| Próximas citas                    [ Ver agenda > ]   |
+-----------------------------------------------------+
| 10:00 María Pérez   Consulta general (Confirmada)  [✓ Completar]|
| 11:30 Juan Ramírez  Control        (Por confirmar) [✓ Completar]|
| 14:00 Sofía Cano    Consulta general (Confirmada)  [✓ Completar]|
+-----------------------------------------------------+
|                                                 [ + ]| ← FAB, abre Agendar Cita (5.7, HU-23)
+-----------------------------------------------------+
```

Las 3 métricas ("Pacientes hoy", "Citas pendientes", "Completadas") son las que especifica
HU-27; `StatCardGrid` admite hasta 4 columnas si Product Manager suma una cuarta métrica más
adelante. **No se incluye ningún ícono de "cambiar de vista"** en este header: HU-27 deja
explícitamente abierto su alcance (¿alterna Cliente/Profesional? ¿entre negocios?) y no se
diseña hasta que esa pregunta se resuelva (backlog, pregunta abierta #6; ver también la nota
sobre RN9 en §6).

#### 5.2bis Verificación contra capturas reales (2026-08-07)

`Screenshot_20260410_190938_Expo Go.jpg` es la única captura de Dashboard disponible en esta
revisión. Confirma el resumen de 3 stat cards y "Próximas Citas", pero corrige varios puntos:

- **El header es blanco (`surface`), no `primary` sólido:** "¡Hola, Dr. [Nombre]!" en negro bold
  + fecha en gris debajo, sobre fondo claro — no el header de color sólido que usa `AppHeader` en
  Horarios/Pacientes. Ver corrección de componente en `sistema-diseno.md` §7.7bis.
- **El ícono de "cambiar de vista" sí existe visualmente:** hay un botón cuadrado redondeado con
  ícono de flechas cruzadas (⇄) arriba a la derecha del header. Esto **no resuelve** la pregunta
  abierta #6 del backlog (a qué cambia el ícono no se puede saber de una captura estática) — se
  corrige únicamente que el ícono existe en la app de referencia, algo que este wireframe había
  decidido omitir por falta de evidencia. Se restituye el ícono al wireframe, sin especificar su
  acción (sigue bloqueado hasta que Product Manager resuelva el alcance de HU-27).
- **Las cards de "Próximas citas" son más ricas que el wireframe:** cada card tiene (a) una
  franja de color vertical a la izquierda (verde en las dos citas observadas, incluida una en
  estado "Por confirmar" — no se pudo confirmar si esa franja está pensada para llevar el color
  del estado del turno o es decorativa fija; se documenta el elemento sin asignarle regla de
  color), (b) el `StatusPill` acompañado de una flecha hacia abajo (˅, posible affordance de
  expandir/colapsar el detalle in-line, no confirmado), (c) fecha y hora en texto verde bold (no
  gris/negro por defecto), y (d) la acción de completar es un **botón ancho completo**
  "✓✓ Marcar como completada" (azul sólido, con ícono de doble check) debajo del contenido de la
  card — no un chip pequeño "[✓ Completar]" en línea como mostraba el wireframe original.
- **Confirmado:** 3 stat cards (Pacientes Hoy / Citas Pendientes / Completadas — el texto de la
  tercera se corta en la captura, probablemente "Completadas Hoy") con íconos de persona/reloj/
  check en verde-azul-verde.

Wireframe actualizado (reemplaza al de arriba en lo que difiere; lo no mencionado sigue igual):

```
+-----------------------------------------------------+
| ¡Hola, Dr. García!                            [ ⇄ ] | ← header blanco, no primary
| Jueves, 7 de agosto de 2026                          |
+-----------------------------------------------------+
| [ 8 ]           | [ 2 ]             | [ 5 ]          |
| Pacientes hoy    | Citas pendientes  | Completadas    |
+-----------------------------------------------------+
| Próximas citas                    [ Ver agenda > ]   |
+-----------------------------------------------------+
| ┃ María Pérez         (Confirmada) ˅                 |
| ┃ Consulta general                                   |
| ┃ 2026-08-07 · 10:00  (verde bold)                   |
| ┃ [   ✓✓ Marcar como completada   ]                  |
+-----------------------------------------------------+
|                                                 [ + ]|
+-----------------------------------------------------+
```

### 5.3 Agenda semanal completa (Profesional) — HU-06

Se accede desde el botón "Ver agenda >" del Dashboard (ya no es una pantalla de nivel raíz
del bottom nav, para no duplicar la vista de "próximas citas" del Dashboard).

```
+-----------------------------------------------------+
| < Dashboard     Agenda semanal    [ Bloquear rango ] |
+-----------------------------------------------------+
| Lun | Mar | Mié | Jue | Vie | Sáb | Dom              |
|-----+-----+-----+-----+-----+-----+------            |
| 9:00 María P.   |     |Juan R.|    |     |            |
| 9:30 (libre)    |     |(libre)|    |     |            |
| ...                                                   |
+-----------------------------------------------------+
```

"Bloquear rango" abre el flujo de **Excepciones** (HU-15) reutilizando `MonthCalendarPicker`
en modo selección de rango; sin cambios de comportamiento respecto de la versión anterior de
este documento, solo cambia dónde se accede.

### 5.4 Gestión de Horarios (Profesional) — HU-05 + HU-16 + HU-18, extendida

Reemplaza a "Definir Disponibilidad". Usa `MonthCalendarPicker` (`sistema-diseno.md` §7.5)
para navegar el mes y ver qué días ya tienen horario configurado (ícono de reloj). Debajo, los
bloques configurados del día seleccionado. Más abajo, la sección "⚙️ Configuración General"
agrupa dos bloques de configuración cuantitativa con `NumericStepperField` cada uno.

```
+-----------------------------------------------------+
| ⏰ Gestión de Horarios              [ 📅 Replicar ]  |
+-----------------------------------------------------+
| < Agosto 2026 >                                      |
|  L   M   M   J   V   S   D                           |
|  .   .   1   2🕐  3   4   5                           |
|  6  7🕐  8   9  10  11  12                            |
|  ...                                                  |
| ● Seleccionada  ○ Disponible  ◎ Hoy  ✕ Pasada         |
| 🕐 día con horario configurado — 8 fechas este mes    |
+-----------------------------------------------------+
| Jue 7 de agosto — bloques configurados                |
|  09:00–13:00   Consulta general        [ ✎ ] [ 🗑 ]   |
|  14:00–18:00   Control                 [ ✎ ] [ 🗑 ]   |
+-----------------------------------------------------+
|              [ + Agregar Horario ]                   |
+-----------------------------------------------------+
| ⚙️ Configuración General (HU-16)                      |
+-----------------------------------------------------+
| 📋 Configuración de Citas                             |
|   Duración de cita         [ − ]  30 min  [ + ]       |
|   Máximo de citas por día  [ − ]   12     [ + ]       |
|   Días de anticipación     [ − ]    2     [ + ]       |
+-----------------------------------------------------+
| 🍽️ Tiempo de Descanso (HU-18)                         |
|   Inicio de descanso       [ − ]  13:00   [ + ]       |
|   Duración de descanso     [ − ]  60 min  [ + ]       |
+-----------------------------------------------------+
|        [ Cancelar ]            [ Restablecer ]        |
+-----------------------------------------------------+
```

El contador "N fechas este mes" implementa el requisito de HU-18 de mostrar cuántas fechas ya
tienen horario cargado. Ver riesgo de solapamiento con reglas de negocio existentes (RN3,
RN1/RN2) marcado en §6 — Product Manager ya dejó esta misma tensión como pregunta abierta #1
de HU-16 en `02-backlog/backlog.md`; Arquitecto debe confirmar la precedencia antes de que
Backend implemente estos steppers.

#### 5.4bis Verificación contra capturas reales (2026-08-07) — reestructuración importante

18 de las 37 capturas corresponden a esta pantalla (dos sesiones: 23 de abril y 25/27 de abril).
La corrección es estructural, no solo visual: **"Gestión de Horarios" es una sola página larga
con scroll, no una pantalla corta con modales separados para replicar/configurar** como asumía
el wireframe original. Orden real de secciones, de arriba a abajo, todas dentro de la misma
página y bajo el mismo footer fijo ("Restablecer" + "Guardar N Fechas"):

1. **Seleccionar Fechas Disponibles** — `MonthCalendarPicker`, como ya documentado, con las
   correcciones de estado/color de `sistema-diseno.md` §7.5bis.
2. **Fechas Seleccionadas** — chips de solo lectura (sin "✕", ver §7.5bis), no un control
   editable.
3. **Horarios por Defecto** — dos rangos Inicio/Fin con `NumericStepperField` "− / +" (no
   chevrons acá — los chevrons son solo para Tiempo de Descanso, punto 5).
4. **Replicar en semanas / meses** — **inline en la misma página, no un modal aparte.** Ver
   corrección completa en §5.6bis (controles totalmente distintos a los del wireframe original).
5. **Configuración General** — Duración de Citas / Citas Máximas por Día / Anticipación de
   Reservas (steppers "− / +") y, dentro de la misma sección, **Tiempo de Descanso** con
   steppers de chevron (▾/▴) para Inicio/Fin.

**Deriva de versión entre capturas de distinta fecha** (no es una corrección contra este
documento, es una diferencia real dentro de las propias capturas — ver `sistema-diseno.md`
§12.3 para el detalle completo): las capturas del 23 de abril muestran una variante más
elaborada (cards con ícono propio por configuración, más una sección "📋 Configuración de
Citas" que **repite** los mismos 3 valores de "Configuración General" en un formato distinto,
más abajo en la misma página) mientras que las capturas del 25 y 27 de abril (dos sesiones
independientes que coinciden entre sí) muestran una versión más compacta y **sin** esa
repetición. Esta revisión toma la versión compacta (25/27 abril) como más representativa por
estar corroborada dos veces, pero **se recomienda confirmar con el CEO** cuál de las dos
versiones es la vigente antes de que Mobile la implemente — no se descarta la elaborada.

**Aparte, existe un modal real y mucho más simple llamado "Agregar Nuevo Horario"** (no
capturado como parte del scroll de esta pantalla, así que probablemente se accede desde otro
punto no cubierto en estas 37 capturas) — ver corrección completa en §5.5bis: no tiene selector
de servicio, ni alternativa semanal/fechas puntuales, ni selector de días múltiple — es para UN
slot a la vez, y la recurrencia se resuelve aparte con "Replicar en semanas/meses" (punto 4
arriba).

Wireframe corregido (reemplaza al original; ver §5.5bis y §5.6bis para el detalle de los modales
mencionados):

```
+-----------------------------------------------------+
| ⏰ Gestión de Horarios              (header primary)  |
+-----------------------------------------------------+
| 🗓️ Seleccionar Fechas Disponibles                    |
| < Agosto 2026 >                                       |
|  DOM LUN MAR MIÉ JUE VIE SÁB                          |
|  (celdas: borde lavanda=elegible · relleno primary +  |
|   🕐 + ✓ =seleccionada con horario · anillo warning=hoy|
|   · gris plano=pasada/fuera de mes)                   |
| 📅 N fechas con horarios configurados                 |
+-----------------------------------------------------+
| Fechas Seleccionadas: [3 ago] [10 ago] [17 ago] ...   |
|   (chips de solo lectura, sin "✕")                    |
+-----------------------------------------------------+
| ⏰ Horarios por Defecto                                |
|  Inicio [ − ] 09:00 [ + ]   Fin [ − ] 12:00 [ + ]     |
|  Inicio [ − ] 14:00 [ + ]   Fin [ − ] 18:00 [ + ]     |
+-----------------------------------------------------+
| 🗓️ Replicar en semanas / meses     — ver §5.6bis      |
+-----------------------------------------------------+
| ⚙️ Configuración General                              |
|  Duración de Citas         [ − ]  60 min  [ + ]       |
|  Citas Máximas por Día     [ − ]   20     [ + ]       |
|  Anticipación de Reservas  [ − ]   30     [ + ]       |
|  ☕ Tiempo de Descanso  [▾]12:00[▴]   [▾]14:00[▴]      |
+-----------------------------------------------------+
|        [ Restablecer ]      [ Guardar N Fechas ]      | ← footer fijo, warning + primary
+-----------------------------------------------------+
```

### 5.5 Modal — Agregar Horario (Profesional)

```
+-----------------------------------------------------+
| Agregar Horario                              [ ✕ ]  |
+-----------------------------------------------------+
| Servicio             [ Consulta general        ▾ ]   |
| Repetir              (•) Semanal   ( ) Fechas puntuales|
| Días (si Semanal)    [L][M][X][J][V][S][D]           |
| Fechas (si puntuales) < Agosto 2026 >                 |
|                       (grid de selección múltiple)    |
|                       Seleccionadas:                  |
|                       [3 ago ✕] [10 ago ✕] [17 ago ✕] |
| Hora inicio           [ − ]  09:00  [ + ]             |
| Hora fin               [ − ]  13:00  [ + ]            |
+-----------------------------------------------------+
|        [ Cancelar ]          [ Guardar Horario ]      |
+-----------------------------------------------------+
```

#### 5.5bis Verificación contra capturas reales (2026-08-07) — el modal real es mucho más simple

`Screenshot_20260427_095317_Turnario.jpg` muestra el modal real, titulado **"Agregar Nuevo
Horario"** (no "Agregar Horario"). Es notablemente más simple que este wireframe — no tiene
selector de Servicio, ni alternativa Semanal/Fechas puntuales, ni selector de múltiples días, ni
grid de calendario embebido. Es un formulario para **un solo bloque horario de un solo día de la
semana**:

```
+-----------------------------------------------------+
| Agregar Nuevo Horario                         [ ✕ ]  | ← header blanco
+-----------------------------------------------------+
| Día de la Semana      [ Lunes                    ▾ ] |
| Período del Día       [ Mañana                   ▾ ] | ← campo nuevo, no estaba documentado
| Hora de Inicio        [ 09:00                    🕐 ] | ← campo tap-to-pick, no stepper
| Hora de Fin           [ 10:00                    🕐 ] |
| Disponibilidad        ( Disponible ✓ )                | ← chip grande seleccionable, no radio
+-----------------------------------------------------+
|        [ Cancelar ]          [ Agregar Horario ]      |
+-----------------------------------------------------+
```

Diferencias puntuales con el wireframe original:
- No hay campo "Servicio" en este modal (a diferencia de "Crear Nueva Cita", §5.7bis, que sí lo
  tiene).
- "Repetir Semanal / Fechas puntuales" **no existe acá** — la recurrencia se resuelve aparte, en
  la sección "Replicar en semanas / meses" de la misma pantalla de Gestión de Horarios (§5.4bis,
  §5.6bis). Este modal es solo para un bloque puntual de un día de la semana.
- "Período del Día" (Mañana/Tarde/Noche, a confirmar valores exactos) es un campo nuevo no
  contemplado en el wireframe original.
- Hora de Inicio/Fin son campos que se tocan para abrir un selector de hora (ícono de reloj), no
  el stepper "− / +" que sí se usa en la sección "Horarios por Defecto" de la pantalla
  contenedora — confirma que el mismo dato (hora) puede pedirse con distintos controles según el
  contexto, no hay una regla única.
- "Disponibilidad" se resuelve con un chip grande verde seleccionable ("Disponible" con check),
  sugiriendo que existe al menos otra opción (ej. "No disponible"/bloqueado) no visible en esta
  captura puntual.
- El botón "Agregar Horario" se ve con una tonalidad de `primary` más clara/atenuada que otros
  botones primarios de la app — no se pudo confirmar si es un estado deshabilitado o solo una
  variante de color; se marca como observación, no como corrección firme.

### 5.6 Modal — Replicar en Semanas/Meses (Profesional) — HU-17

```
+-----------------------------------------------------+
| 📅 Replicar Horario                           [ ✕ ]  |
+-----------------------------------------------------+
| Replicar el horario de: Jue 7 de agosto               |
| Repetir cada          [ − ]   1 semana   [ + ]        |
| Cantidad de repeticiones [ − ]    4      [ + ]        |
|   (hasta ~6 meses, según HU-17)                       |
| Hasta (fecha límite, opcional)   [ 30/09/2026 ]       |
| Si el día ya tiene horario cargado:                    |
|   (•) No sobrescribir — solo completa huecos          |
|   ( ) Sobrescribir horario existente                  |
| Vista previa: se crearán bloques en 4 jueves más      |
|   (14, 21, 28 ago; 4 sep)                             |
+-----------------------------------------------------+
|        [ Cancelar ]        [ Confirmar Replicado ]    |
+-----------------------------------------------------+
```

"No sobrescribir" es el modo por defecto, tal como pide HU-17 (no debe borrar ni modificar
horarios ya cargados manualmente). El modo aplica solo a los días de la semana seleccionados
dentro del alcance elegido, y respeta las mismas reglas de generación de slots (RN1, RN2,
RN3) que la carga manual — no es un camino alternativo que las evite.

#### 5.6bis Verificación contra capturas reales (2026-08-07) — no es modal, y los controles son distintos

Confirmado en 3 capturas (`Screenshot_20260423_235159_Turnario.jpg` a `_235203_`, y de nuevo en
`Screenshot_20260425_040308_Expo Go.jpg`/`_040313_`, dos sesiones independientes que coinciden):
"Replicar en semanas / meses" **no es un modal** — es una sección más dentro del scroll de
Gestión de Horarios (§5.4bis), entre "Horarios por Defecto" y "Configuración General". Los
controles reales también son distintos a los del wireframe original:

```
+-----------------------------------------------------+
| 🗓️ Replicar en semanas / meses    (sección inline)   |
+-----------------------------------------------------+
| Días de la semana                                     |
| (Dom)(Lun✓)(Mar✓)(Mié✓)(Jue✓)(Vie✓)(Sáb)              | ← chips, no checkboxes [L][M][X]...
| Alcance desde hoy                                      |
| (4 sem.)(8 sem.)( 12 sem. ✓ )(~6 meses)                | ← 4 chips preestablecidos, no steppers
| Sobrescribir días que ya tienen horario        ( ⚪ )  | ← 1 switch, no 2 radios
| Desactivado: solo completa días vacíos. Activado:      |
| reemplaza también los ya guardados.                    |
+-----------------------------------------------------+
|        [ 📋 Aplicar plantilla al calendario ]         | ← 1 botón verde (success), ancho completo
+-----------------------------------------------------+
```

Diferencias con el wireframe original:
- **"Repetir cada N semana" × "cantidad de repeticiones" (dos steppers) no existe.** En su lugar
  hay **4 opciones preestablecidas en chips**: "4 sem.", "8 sem.", "12 sem.", "~6 meses" — más
  simple, sin combinar frecuencia y cantidad por separado. No hay campo de fecha límite ("Hasta")
  independiente ni vista previa de fechas concretas ("se crearán bloques en...").
- **"No sobrescribir / Sobrescribir" es un solo interruptor** ("Sobrescribir días que ya tienen
  horario", apagado por defecto — mismo comportamiento por defecto que ya pedía HU-17, solo
  cambia el control de 2 radios a 1 switch), con el mismo texto de ayuda que ya documentaba la
  intención ("Desactivado: solo completa días vacíos. Activado: reemplaza también los ya
  guardados.").
- El botón de confirmación es **"📋 Aplicar plantilla al calendario"**, sólido verde (`success`,
  no `primary`), no "Confirmar Replicado". No hay botón "Cancelar" separado en esta sección (al
  ser inline y no modal, "Cancelar" no aplica de la misma forma — el usuario simplemente no toca
  "Aplicar").
- El selector de "Días de la semana" usa chips de 3 letras (Dom/Lun/Mar/Mié/Jue/Vie/Sáb), no
  checkboxes de una sola letra.

### 5.7 Modal — Agendar Cita manual (Profesional) — HU-23

Permite al profesional crear un turno en nombre de un paciente (ej. llamada telefónica,
paciente sin la app). **Debe reutilizar la misma lógica de disponibilidad que el flujo de
reserva del Cliente** (RN1/RN2) — solo se listan slots realmente libres, para no crear
solapamientos por esta vía alternativa (mismo criterio que ya exige HU-23).

```
+-----------------------------------------------------+
| Agendar Cita                                  [ ✕ ]  |
+-----------------------------------------------------+
| Paciente          [ Buscar paciente...        🔍 ]   |
|                   ( + Nuevo paciente )                |
| Servicio          [ Consulta general           ▾ ]   |
| Fecha             < Agosto 2026 > (selección única)   |
| Horario           [10:00] [10:30] [11:00] ...         |
|                   (multi-selección de chips sobre     |
|                    slots Disponibles — ver nota)       |
| Nota (opcional)   [                              ]   |
| ¿Requiere seña?   ( Sí )  ( No )   — ver nota          |
+-----------------------------------------------------+
|        [ Cancelar ]           [ Agendar Cita ]        |
+-----------------------------------------------------+
```

**Nota de diseño:** la descripción recibida menciona un campo de texto libre "Hora" con
ejemplo "10:00, 14:30", lo que sugeriría poder agendar más de un turno en una sola acción.
Product Manager dejó esto como pregunta abierta en HU-23 (no asumido). Este wireframe propone
en su lugar **multi-selección de chips sobre los slots realmente disponibles** en vez de
texto libre, porque valida contra RN1/RN2 en la propia UI y evita errores de formato — es una
recomendación de UX/UI, no una resolución de esa pregunta de negocio; si Product Manager
confirma que debe ser un único turno por acción, el control se simplifica a selección única.
El control "¿Requiere seña?" queda a la espera de la segunda pregunta abierta de HU-23 (si
RN10 aplica también al turno cargado manualmente por el profesional) — se incluye en el
wireframe para no bloquear el layout, pero su lógica de negocio depende de esa definición.

#### 5.7bis Verificación contra capturas reales (2026-08-07)

Hay evidencia directa de **dos modales distintos** para crear un turno, no uno solo:

**"Crear Nueva Cita"** (general — desde Dashboard/menú, sin paciente preseleccionado; capturas
`Screenshot_20260427_095249_Turnario.jpg` y `_121400_`, dos capturas idénticas en sesiones
distintas):

```
+-----------------------------------------------------+
| Crear Nueva Cita                              [ ✕ ]  | ← header primary sólido
+-----------------------------------------------------+
| ┃ Servicio *                                          | ← cada grupo es su propia card con
| ┃ [ Entrenamiento Personal              ✓ ]           |   franja de acento izquierda (primary)
+-----------------------------------------------------+
| ┃ Paciente *                                          |
| ┃ [ Seleccionar paciente...             ▾ ]           | ← dropdown, no buscador con chips
+-----------------------------------------------------+
| ┃ Fecha *                                              |
| ┃ [ Seleccionar fecha disponible...     📅 ]           | ← dropdown, no MonthCalendarPicker inline
+-----------------------------------------------------+
| ┃ Hora *                                               |
| ┃ [ Seleccionar horario disponible...   🕐 ]           |
| ┃   No hay horarios disponibles (si no eligió fecha)   |
+-----------------------------------------------------+
| ┃ Notas                                                |
| ┃ (campo de texto, contenido no capturado)             |
+-----------------------------------------------------+
|      [ Cancelar ]   [ Crear Cita y Notificar Cliente ] |
+-----------------------------------------------------+
```

**"Agendar Cita"** (contextual — desde un paciente ya elegido, ej. acción "Agendar" en Gestión de
Pacientes o desde su ficha; capturas `Screenshot_20260427_133838_Turnario.jpg` y `_141951_`):

```
+-----------------------------------------------------+
| Agendar Cita                                  [ ✕ ]  | ← header blanco, ícono calendario verde
+-----------------------------------------------------+
| 👤 Paciente                                            |
| [ 🔵 Silvia · silvia@gmail.com · +1111111 ]            | ← card de solo lectura, ya elegido
+-----------------------------------------------------+
| 🗓️ Detalles de la Cita                                |
| Servicio *  [ Entrenamiento Personal          ✎ ]     |
|   💡 Servicio predeterminado: Entrenamiento Personal   |
| Fecha *              |  Hora *                         |
| [ 📅 Seleccionar  ▾ ]|  [ Ej: 10:00, 14:30         ]   | ← confirma: campo de texto libre
| Notas Adicionales                                       |
| [ Notas sobre la cita, recordatorios especiales, etc. ] |
+-----------------------------------------------------+
|          [ Cancelar ]         [ Agendar Cita ]         |
+-----------------------------------------------------+
```

Puntos a corregir/confirmar respecto del wireframe original de HU-23:
- **Confirmado — el campo "Hora" de texto libre con ejemplo "10:00, 14:30" existe tal cual** en
  la variante "Agendar Cita" — la transcripción original que dio origen a este documento describía
  esto correctamente. La alternativa de "multi-selección de chips sobre slots disponibles" sigue
  siendo una **recomendación de UX/UI** (no una corrección de la transcripción) a validar con
  Product Manager antes de implementar — sin cambios en esa recomendación.
- El control "¿Requiere seña? (Sí/No)" **no aparece en ninguna de las dos variantes capturadas**
  — sigue sin evidencia directa, se mantiene como estaba (a la espera de la definición de negocio
  ya señalada).
- No hay buscador de paciente con chips ni acceso a "+ Nuevo paciente" inline en "Crear Nueva
  Cita" — es un dropdown simple ("Seleccionar paciente...").
- El botón de confirmación de "Crear Nueva Cita" dice **"Crear Cita y Notificar Cliente"**
  (2 líneas) — más explícito que "Agendar Cita" sobre el envío de notificación al cliente.
- Todos los campos obligatorios llevan un asterisco "\*" junto al label — convención a adoptar
  (ver `sistema-diseno.md` §7.1bis).
- Cada grupo de campo es una card `surface` con una **franja de acento de color a la izquierda**
  (no documentado en ningún componente existente) — mismo elemento visual que las cards de
  "Próximas citas" del Dashboard (§5.2bis); se deja constancia, sin agregar un componente nuevo
  formal porque no hay evidencia suficiente de su regla de color en ningún caso (ver pregunta
  abierta en `sistema-diseno.md` §12.4).

### 5.8 Gestión de Pacientes (Profesional) — HU-10 + HU-19 + HU-22, extendida

Reemplaza a "Mis Clientes". Usa `StatCardGrid`, `SearchFilterBar` y `ActionListTile` /
`PatientListTile` (`sistema-diseno.md` §7.3, §7.9, §7.10).

```
+-----------------------------------------------------+
| 🏥 Gestión de Pacientes                              |
+-----------------------------------------------------+
| [ 48 ]           | [ 41 ]           | [ 7 ]           |
| Total             | Activos          | Inactivos       |
+-----------------------------------------------------+
| [ 🔍 Buscar paciente...                       ]      |
| ( Todos )( Activos )( Inactivos )( Recientes )        |
|                                     [Importar][Exportar]|
+-----------------------------------------------------+
| María Pérez        Últ. visita 28 jul     (Activo)   |
|   [ ✱ Historial ][ ✎ Editar ][ 💬 Contactar ][ 🗑 ]   |
+-----------------------------------------------------+
| Juan Ramírez        Últ. visita 02 jun   (Inactivo)  |
|   [ ✱ Historial ][ ✎ Editar ][ 💬 Contactar ][ 🗑 ]   |
+-----------------------------------------------------+
|                                                 [ + ]| ← FAB, abre Ficha de Paciente (nueva)
+-----------------------------------------------------+
```

Nota de privacidad: "Importar/Exportar" (HU-22) mueve datos personales (PII) de pacientes en
lote — marcar para revisión de Security antes de implementar (ver §6); el formato de archivo
concreto queda como pregunta abierta de HU-22 en el backlog, no es una decisión de UX/UI. El
criterio de "Activo/Inactivo/Recientes" (HU-19) también está abierto (manual vs. calculado
por antigüedad de la última visita) — este wireframe muestra el `StatusPill` y los chips de
filtro sin asumir cuál de las dos reglas aplica.

#### 5.8bis Verificación contra capturas reales (2026-08-07)

`Screenshot_20260427_095459_Turnario.jpg` confirma la estructura general (stats + buscador +
filtros + fila de paciente con acciones) pero corrige varios detalles:

```
+-----------------------------------------------------+
| 🏥 Gestión de Pacientes                              | ← header primary
| Administra tu lista de pacientes                     |
+-----------------------------------------------------+
| [ 30 ] [ 25 ] [ 5 ] [ 8 ]                             | ← 1 sola card, 4 columnas
| TOTAL  ACTIVOS INACTIVOS NUEVOS                       | ← "Nuevos" es 4ta métrica, no en wireframe
+-----------------------------------------------------+
| [+Agregar Paciente] [⬇ Importar] [⬆ Exportar]         | ← 3 botones verdes arriba, no FAB
+-----------------------------------------------------+
| [ 🔍 Buscar pacientes...                        ]     |
| ( Todos )( Activos )( Inactivos )( Recientes )        |
+-----------------------------------------------------+
| 🔵 Carlos Silva              🔴 Inactivo              | ← card con fondo gris si Inactivo
|    carlos.silva@email.com          3 visitas          |
|    +54 9 11 4567-8901                                 |
|    Notas: No ha asistido últimamente                  |
|    Última visita: 2023-12-20                          |
|    [👁 Ver][✎ Editar][📅 Agendar][🕐 Historial]        | ← acciones reales, no las del wireframe
+-----------------------------------------------------+
```

- **No hay FAB.** "Agregar Paciente" es un botón verde de texto arriba de la lista, junto con
  "Importar" y "Exportar" (también verdes) — no un "+" flotante abajo a la derecha.
- **Acciones reales de la fila: Ver, Editar, Agendar, Historial** — reemplaza al set que
  proponía este wireframe ("Historial / Editar / Contactar / Eliminar"). No se observó acción de
  contactar ni de eliminar/desactivar directamente en la fila.
- **Cuarta métrica "Nuevos"** además de Total/Activos/Inactivos.
- El `StatusPill` real lleva borde + punto de color (no solo relleno pastel) — ver
  `sistema-diseno.md` §7.10bis para el detalle del componente.
- La card completa cambia de fondo (gris claro) cuando el paciente está Inactivo, no solo el
  pill.
- Email, teléfono, notas y última visita se muestran siempre visibles como texto plano, no
  ocultos.

No se pudo confirmar contra capturas el criterio Activo/Inactivo/Recientes ni el formato de
Importar/Exportar — esas preguntas abiertas del wireframe original siguen sin resolver, sin
cambios.

### 5.9 Ficha de Paciente (ver/editar) — HU-20

```
+-----------------------------------------------------+
| < Volver          Ficha de Paciente        [Guardar] |
+-----------------------------------------------------+
| Datos personales                                      |
|  Nombre completo    [ María Pérez                 ]  |
|  Fecha de nacimiento [ 12/04/1990                 ]  |
|  Género              [ Prefiero no decir        ▾ ]  |
|  Teléfono            [ +54 9 11 xxxx-xxxx         ]  |
|  Email               [ maria@ejemplo.com          ]  |
|  Dirección           [ ...                        ]  |
+-----------------------------------------------------+
| Contacto de emergencia                                |
|  Nombre              [ ...                        ]  |
|  Teléfono            [ ...                        ]  |
|  Relación            [ Familiar                 ▾ ]  |
+-----------------------------------------------------+
| ✱ Salud                                               |
|  Alergias            [ ...                        ]  |
|  Notas médicas generales [ ...                    ]  |
|  Estado          ( Activo )  ( Inactivo )            |
+-----------------------------------------------------+
|        [ Cancelar ]              [ Guardar ]          |
+-----------------------------------------------------+
```

Datos personales básicos (nombre, contacto) ya están implícitos en HU-10/HU-11; los campos
ampliados (fecha de nacimiento, género, dirección, alergias, contacto de emergencia, notas
libres) corresponden a **HU-20**. Alergias y contacto de emergencia son datos de
salud/sensibles — HU-20 ya exige revisión de Security antes de producción (ver §6). HU-20
también deja abierto si estos campos aplican a todos los rubros de negocio (multi-rubro, D1)
o solo a profesionales de salud; este wireframe los muestra todos, sin ocultamiento
condicional, a la espera de esa definición.

#### 5.9bis Verificación contra capturas reales (2026-08-07)

**Confirmado, con matices:** el set de campos de este wireframe (nombre, fecha de nacimiento,
género, teléfono, email, dirección, alergias, contacto de emergencia con nombre/teléfono/
relación) coincide de cerca con lo observado — es el punto de esta revisión con mejor
correspondencia entre transcripción original y captura real. Correcciones puntuales:

- El nombre real de la pantalla de edición es **"Editar Paciente"** (no "Ficha de Paciente"), y
  el orden real de campos es: Nombre completo* → Email* → Teléfono* → (Fecha de Nacimiento |
  Género, en 2 columnas) → Dirección → Contacto de Emergencia (Nombre del contacto → …). No se
  llegó a capturar si "Alergias", "Notas médicas generales" o el toggle Activo/Inactivo (que sí
  aparecen en la vista de solo lectura, ver abajo) están más abajo en el formulario de edición —
  las capturas disponibles se cortan después de "Nombre del contacto de emergencia". Se conserva
  el wireframe original para esa parte por falta de evidencia que lo contradiga, no se borra.
- Los 3 primeros campos (Nombre, Email, Teléfono) llevan asterisco "\*" de obligatorio; el resto
  no.
- "Fecha de Nacimiento" muestra el placeholder **"YYYY-MM-DD"** — formato ISO expuesto
  directamente al usuario, no un date picker localizado. A confirmar con UX/UI si Turnos
  Profesionales debe usar un formato más local (DD/MM/AAAA) con un `MonthCalendarPicker` en vez
  de texto libre.
- **Dos tratamientos visuales distintos para "Editar Paciente"** en las capturas: header naranja
  (`warning`) sólido de borde a borde (`Screenshot_20260427_102356_Turnario.jpg`) vs. header
  blanco con ícono de lápiz en naranja (`Screenshot_20260427_133828_Turnario.jpg` y `_141941_`,
  este último más frecuente — 2 de 3 capturas). Ver `sistema-diseno.md` §7.7bis.
- El botón de guardar también varía: "💎 Guardar Cambios" (verde, con un emoji de diamante que
  probablemente es un error de copiar/pegar del ícono de "Turnario Pro" en la app de referencia
  — no replicar el emoji) en una captura, **"Actualizar Paciente" (índigo, sin emoji)** en las
  otras dos — se recomienda este último por ser el más consistente.
- **Advertencia — no replicar:** `Screenshot_20260427_102356_Turnario.jpg` muestra un botón rojo
  de depuración "🔍 Debug: Ver Datos" debajo del header. Es un artefacto de desarrollo de la app
  de referencia (coherente con que el CEO ya avisó que está en pre-producción), no parte del
  diseño a copiar.

**Nuevo hallazgo — dos pantallas distintas de solo-lectura, ambas tituladas "Detalles del
Paciente":** no hay evidencia de que este wireframe (que mezcla edición y vista) corresponda a
ninguna de las dos tal cual — en la app real, "ver" y "editar" son pantallas separadas, y "ver"
tiene dos variantes:

| | Variante A (`Screenshot_20260427_121228_Turnario.jpg`) | Variante B (`Screenshot_20260427_133817_Turnario.jpg`, `_141933_`) |
|---|---|---|
| Header | `primary` sólido, ícono de persona | Blanco, ícono de ojo |
| Contenido | ID interno (string crudo de base de datos — ver nota de privacidad abajo), Última Visita, Estado (punto + texto), "Historial de Visitas" (2 cajas: N° total, "Reciente" como texto no fecha), "Notas y Comentarios" | Nombre/Email/Teléfono/Fecha Nacimiento/Dirección/Género/Alergias + Contacto de Emergencia (Nombre/Teléfono/Relación) — coincide con este wireframe |
| Footer | "Editar Paciente" (`warning`, naranja) + "Agendar Cita" (`success`, verde) | "Cerrar" (outline) + "Editar Paciente" (`primary`, índigo) |

No se puede determinar con capturas estáticas si son dos pantallas intencionalmente distintas
(ej. resumen rápido vs. ficha completa) o una duplicación a resolver — se documentan ambas tal
cual y se deja como pregunta para el CEO (ver `sistema-diseno.md` §12.4) en vez de que UX/UI
elija una unilateralmente. La Variante B es la que más se parece a este wireframe (§5.9) y a
HU-20; si hay que elegir una sola pantalla de "ver" como definitiva, esta revisión sugiere la B
como punto de partida, sujeto a confirmación.

**Nota de privacidad (además de la ya registrada en §6):** que la Variante A muestre el ID
interno de base de datos como dato de pantalla ("ID: 69dfd29a5782645e0a753114") es,
probablemente, otro artefacto de desarrollo — de todos modos, se marca para que Security lo
tenga en cuenta si esa pantalla se toma como base: un identificador interno no debería quedar
expuesto a un usuario final en producción.

### 5.10 Historial de Paciente enriquecido — HU-11 + HU-21

```
+-----------------------------------------------------+
| < Volver        Historial — María Pérez               |
+-----------------------------------------------------+
| [ 12 ]        | [ 9 ]           | [ 4 ]         | [ 6 ]|
| Citas totales  | Completadas     | Tratamientos  | Notas|
|                |                 |               |médicas|
+-----------------------------------------------------+
| Turnos                                                 |
+-----------------------------------------------------+
| 28 jul 2026  10:00  Consulta general   (Completada)   |
|   Profesional: Dr. García · Duración: 30 min           |
|   Costo: $ ...  · Estado de pago: (Confirmada, HU-09b) |
+-----------------------------------------------------+
| 15 jun 2026  09:30  Control            (Completada)   |
|   Profesional: Dr. García · Duración: 20 min           |
+-----------------------------------------------------+
| Tratamientos                                           |
+-----------------------------------------------------+
| Control de rutina — iniciado 28 jul 2026               |
+-----------------------------------------------------+
| Notas médicas                                          |
+-----------------------------------------------------+
| 28 jul 2026 — Sin novedad                              |
+-----------------------------------------------------+
```

Los 4 stat cards y los campos por turno (fecha, hora, estado, servicio, profesional,
duración, costo, estado de pago) son los que especifica **HU-21**. "Tratamientos" y "Notas
médicas" pasan a ser secciones/registros propios —no solo una nota inline del turno— porque
HU-21 los define como entidades nuevas (Tratamiento, Nota médica) a modelar por DBA; esta
pantalla asume que esas entidades existen, no las modela (fuera del alcance de UX/UI). El
estado de pago reutiliza el `StatusPill` ya definido para HU-09b, sin introducir un estado
nuevo, tal como exige el criterio de aceptación de HU-21.

### 5.11 Configuración — menú principal (Profesional) — nueva

```
+-----------------------------------------------------+
| Configuración                                         |
+-----------------------------------------------------+
| 👤 Cuenta                                             |
|   Mi Perfil                                      >   |
|   Privacidad y Seguridad (HU-32 + adición UX)    >   |
|   Cerrar sesión                                       |
+-----------------------------------------------------+
| 📱 Aplicación                                         |
|   Tema (Claro / Oscuro / Sistema)                >   |
|   Idioma                                          >   |
|   Configuración de Notificaciones (HU-26)         >   |
+-----------------------------------------------------+
| 🩺 Panel Profesional (solo si además es Administrador  |
|    del negocio — ver nota abajo)                       |
|   Datos del Consultorio / Negocio (HU-31)         >   |
|   Configuración de Servicios (HU-04b)             >   |
|   Configuración de Pagos y Cobros (HU-30)         >   |
|   Reportes (HU-28)                                >   |
|   Mi Plan — Suscripción Pro (HU-29 — bloqueada)   >   |
+-----------------------------------------------------+
```

Los cinco ítems de "Panel Profesional" ya tienen historia asignada (HU-28, HU-29, HU-30,
HU-31, más HU-04b existente) — son **solo entradas de navegación (stubs)** en este mapa; su
contenido detallado lo define Product Manager al escribir cada pantalla, no se rediseñan aquí
para no duplicar ese trabajo. **Nota de arquitectura de información:** HU-28, HU-30 y HU-31
están redactadas "Como administrador" (no "Como profesional") en el backlog — se muestran
condicionadas a que el usuario autenticado también tenga el rol Administrador del negocio
(`documento-funcional.md` §2, supuesto A7), para no exponer configuración de negocio a un
profesional que solo es empleado. Esto asume que un mismo usuario puede tener ambos roles a
la vez (caso típico: profesional independiente dueño de su propio consultorio) — a confirmar
con Product Manager/Arquitecto si el modelo de datos actual (RN9: "un profesional... queda
asociado a exactamente un negocio") permite esa doble investidura o si requiere ajuste.

#### 5.11bis Verificación contra capturas reales (2026-08-07)

Confirmado en 3 capturas consecutivas del menú (`Screenshot_20260423_235924_Turnario.jpg` a
`_235935_`). El contenido real es más rico que este wireframe stub, con correcciones de
ubicación:

```
+-----------------------------------------------------+
| 🔵 Matias Sayago                    (header primary) | ← header con perfil, no solo título
|    matiasayago@gmail.com                              |
|    Profesional                                        |
|    Entrenamiento Personal (rubro/especialidad)         |
+-----------------------------------------------------+
| Cuenta                                                 |
|   Editar Perfil                                    >   |
|   Notificaciones                                   >   |
|   Turnario Pro · Suscripción · Google Play         >   | ← HU-29 vive ACÁ, no en Panel Profesional
|   Configurar Disponibilidad                        >   | ← nuevo, posible duplicado de "Gestionar
|                                                         |    Horarios" de Panel Profesional (no
|                                                         |    se pudo confirmar si es lo mismo)
|   Privacidad y Seguridad                           >   |
+-----------------------------------------------------+
| Aplicación                                             |
|   Ayuda y Soporte                                  >   | ← confirmado
|   Acerca de                                        >   | ← confirmado
|   (Tema/Idioma/Config. de Notificaciones NO se        |
|    observaron en esta sección en las capturas —        |
|    ver nota abajo)                                     |
+-----------------------------------------------------+
| Panel Profesional                                      |
|   Gestionar Horarios (ícono verde)                 >   |
|   Nueva Cita (ícono naranja, HU-23)                >   | ← nuevo acá, acceso directo
|   Gestionar Pacientes (ícono azul)                 >   |
|   Reportes y Estadísticas (ícono naranja, HU-28)   >   | ← nombre completo, no solo "Reportes"
|   Configuración de Pagos (ícono magenta, HU-30)    >   |
|   Configuración de Consultorio (ícono gris, HU-31) >   |
|   Autorizaciones Médicas (ícono rosa)              >   | ← nuevo, ver §9 — candidata a HU
+-----------------------------------------------------+
| Pagos y Señas                                          | ← sección propia, no parte de HU-30 stub
|   Reservas online con seña                    (⚪)     |
|   "Si está activo, el cliente paga la seña en la app   |
|    para confirmar. Si lo desactivás, la reserva queda  |
|    como solicitud y vos la confirmás en                |
|    notificaciones."                                     |
|   Historial de Señas                               >   |
|   Precios y Señas                                  >   |
+-----------------------------------------------------+
|             [       Cerrar Sesión       ]             | ← ancho completo, danger sólido
|                    Turnario v1.0.0                     |
+-----------------------------------------------------+
```

Puntos a corregir/incorporar:
- **El header lleva el perfil del usuario** (avatar, nombre, email, rol, rubro/especialidad), no
  es un título simple "Configuración" — corrige el wireframe original.
- **"Mi Plan — Suscripción Pro" (HU-29) aparece en "Cuenta"**, no en "Panel Profesional" como
  asumía este wireframe — reubicar en la próxima revisión del wireframe si Product Manager
  confirma que es el lugar correcto.
- **"Configurar Disponibilidad"** es un ítem nuevo en "Cuenta" — no se pudo confirmar si es un
  acceso directo a la misma pantalla que "Gestionar Horarios" (Panel Profesional) o algo
  distinto; se marca como posible duplicación a resolver, no se asume ninguna de las dos
  opciones.
- **"Aplicación" solo mostró "Ayuda y Soporte" y "Acerca de"** en las capturas disponibles — no
  se vieron ahí los controles de Tema/Idioma/Configuración de Notificaciones que este wireframe
  ubicaba en esa sección. No se borran del wireframe (pueden vivir en otro lado no capturado, y
  siguen siendo necesarios como funcionalidad), pero se marca que su ubicación exacta no está
  confirmada por evidencia directa.
- **"Autorizaciones Médicas"** es una pantalla nueva y con contenido real (no solo un stub) — ver
  §9, candidata a nueva sección para el backlog de Product Manager.
- **"Pagos y Señas" es su sección propia**, con el toggle "Reservas online con seña" (texto
  exacto capturado arriba, directamente relevante para HU-09b/RN10) + "Historial de Señas" +
  "Precios y Señas" — más rico que el stub actual de "Configuración de Pagos y Cobros" (HU-30);
  se recomienda que Product Manager lo revise como insumo para esa historia.
- Cada ítem de "Panel Profesional" y "Pagos y Señas" lleva un color de ícono propio (no
  monocromático) — ver `sistema-diseno.md` §6bis.
- "Cerrar Sesión" es un botón ancho completo, `danger` sólido, radio moderado (no píldora) — ver
  `sistema-diseno.md` §7.1bis.

### 5.12 Menú de Configuración (Cliente) — nueva, versión reducida

```
+-----------------------------------------------------+
| Configuración                                         |
+-----------------------------------------------------+
| 👤 Cuenta                                             |
|   Mi Perfil                                      >   |
|   Privacidad y Seguridad                         >   |
|   Cerrar sesión                                       |
+-----------------------------------------------------+
| 📱 Aplicación                                         |
|   Tema (Claro / Oscuro / Sistema)                >   |
|   Idioma                                          >   |
|   Configuración de Notificaciones                 >   |
+-----------------------------------------------------+
```

Mismas secciones "Cuenta" y "Aplicación" que el Profesional, sin "Panel Profesional" (no
aplica al rol Cliente).

### 5.13 Privacidad y Seguridad — compartida Cliente/Profesional (HU-32 + adición de UX/UI)

```
+-----------------------------------------------------+
| < Volver       Privacidad y Seguridad                 |
+-----------------------------------------------------+
| Privacidad (HU-32)                                     |
|  Visibilidad de mi perfil     [ Público           ▾ ]  |
|    (Público / Solo contactos / Privado)                |
|  Mostrar mi estado en línea                   ( on )   |
|  Compartir datos de uso con la plataforma     ( on )   |
+-----------------------------------------------------+
| Seguridad de la cuenta (adición de UX/UI — ver nota)   |
|  Cambiar contraseña                               >   |
|  Verificación en dos pasos                   ( off )  |
|  Inicio de sesión biométrico                 ( off )  |
|  Sesiones activas                                 >   |
|  Descargar mis datos                              >   |
|  Eliminar mi cuenta                               >   |
+-----------------------------------------------------+
```

Pantalla y contenido idénticos para ambos roles (misma cuenta, mismas garantías de
privacidad). El bloque "Privacidad" implementa exactamente lo que pide **HU-32** (visibilidad
de perfil, estado en línea, datos de uso). El bloque "Seguridad de la cuenta" (contraseña,
2FA, biometría, sesiones, exportar/eliminar datos) es una **adición de buena práctica de
UX/UI**, no derivada de las capturas ni de una HU existente — se agrupa en la misma pantalla
por afinidad temática, pero Product Manager debe decidir si amplía el alcance de HU-32 para
cubrirlo o si crea una historia separada antes de que Backend/Security lo implementen.

#### 5.13bis Verificación contra capturas reales (2026-08-07)

`Screenshot_20260427_095421_Turnario.jpg` confirma el bloque "Privacidad" con correcciones de
control, y confirma positivamente que "Seguridad de la cuenta" **no existe** en la app real (la
captura termina en "Compartir Datos de Uso", directo al footer) — valida que ese bloque era, tal
como ya decía este documento, una adición de UX/UI y no algo perdido en la transcripción
original.

- **"Visibilidad de mi perfil" es un grupo de radio buttons** (Público ● / Solo Contactos ○ /
  Privado ○, apilados verticalmente), no un dropdown como mostraba este wireframe.
- Aparece un toggle **"Permitir Notificaciones"** (activado por defecto) entre "Mostrar Estado en
  Línea" y "Compartir Datos de Uso" — no estaba en este wireframe. Se solapa temáticamente con la
  pantalla dedicada "Configuración de Notificaciones" (§5.14) — posible duplicación de control,
  no se resuelve acá cuál debe ser la fuente de verdad.
- El footer real tiene **3 botones**: "Cancelar" (outline) + "Guardar" (`success`, verde) +
  "Restablecer" (`warning`, naranja) — no 2 como mostraba este wireframe. Con los 3 botones
  compartiendo el ancho se observó recorte de texto en "Restablecer" (bug de la app de
  referencia, advertencia para QA — ver `sistema-diseno.md` §7.8bis).

### 5.14 Configuración de Notificaciones (granular) — HU-26, compartida Cliente/Profesional

```
+-----------------------------------------------------+
| < Volver    Configuración de Notificaciones           |
+-----------------------------------------------------+
| Canal                                                  |
|   Push                                        ( on )  |
|   Email                                       ( on )  |
|   WhatsApp (HU-24)                            ( on )  |
+-----------------------------------------------------+
| Tipo de aviso (HU-26)                                  |
|   Citas y recordatorios                       ( on )  |
|     (confirmación, recordatorio, cancelación/          |
|      reprogramación, nueva reserva [solo Profesional]) |
|   Mensajes                       [oculto — ver nota]    |
|   Reseñas y Calificaciones       [oculto — ver nota]    |
|   Promociones y Ofertas                       ( off )  |
+-----------------------------------------------------+
| Sonido y vibración                                     |
|   Sonido                                      ( on )  |
|   Vibración                                   ( on )  |
+-----------------------------------------------------+
```

Mismo componente para ambos roles; el sub-ítem "nueva reserva" dentro de "Citas y
recordatorios" solo se renderiza en modo Profesional (HU-14b). "Mensajes" y "Reseñas y
Calificaciones" aparecen en la descripción original pero corresponden a funcionalidades que
hoy no existen en el backlog (mensajería in-app, reseñas/calificaciones) — HU-26 deja abierto
si se construyen o si el toggle debe ocultarse; este wireframe los muestra **ocultos por
defecto** (opción más segura, no promete una función inexistente) hasta que Product Manager
resuelva esa pregunta. **Este es el único lugar de la app donde se activan/desactivan tipos
de aviso y canales** — la pantalla de WhatsApp (§5.16) no duplica estos switches, solo enlaza
acá.

#### 5.14bis Verificación contra capturas reales (2026-08-07)

`Screenshot_20260427_095405_Turnario.jpg` confirma "Tipos de Notificaciones" (Citas y
Recordatorios / Mensajes / Reseñas y Calificaciones / Promociones y Ofertas) y "Configuración de
Sonido" (Sonido de Notificaciones / Vibración), pero con dos correcciones:

- **"Mensajes" y "Reseñas y Calificaciones" se muestran como toggles visibles** en la app real
  (los 4 toggles de "Tipos de Notificaciones" aparecen igual de visibles en la captura, todos
  apagados en ese estado de cuenta particular). Esto es evidencia nueva a favor de mostrarlos en
  vez de ocultarlos — pero **no se revierte unilateralmente** la decisión ya documentada acá
  (ocultarlos por no existir esas funciones en el backlog todavía): se deja la evidencia
  registrada para que Product Manager decida con este dato en la mano, la razón original (evitar
  prometer una función inexistente) sigue siendo válida independientemente de lo que haga la app
  de referencia.
- El footer real tiene **3 botones** ("Cancelar" + "Guardar" verde + "Restablecer" naranja), con
  el mismo bug de recorte de texto en "Restablecer" que en Privacidad y Seguridad — ver
  `sistema-diseno.md` §7.8bis. Se corrige el footer de este wireframe de 2 a 3 botones.

### 5.15 Bandeja de Notificaciones (tab "Notificaciones") — HU-14b + HU-25, compartida

```
+-----------------------------------------------------+
| Notificaciones                                 [ ⚙ ] |
+-----------------------------------------------------+
| Hoy                                                    |
|  🔔 María Pérez confirmó su turno de las 10:00         |
|  🔔 Recordatorio: turno con Juan Ramírez en 1 hora     |
+-----------------------------------------------------+
| Ayer                                                   |
|  🔔 Sofía Cano canceló su turno de las 16:00           |
+-----------------------------------------------------+
```

Decisión de diseño: el ítem de bottom nav "Notificaciones" es la **bandeja/histórico** de
avisos recibidos (no la pantalla de configuración). El ícono ⚙ del header abre la
Configuración de Notificaciones granular (§5.14). Esto evita ambigüedad entre "ver mis
notificaciones" y "configurar qué notificaciones quiero recibir", que en la descripción
original aparecían mencionadas de forma conjunta.

### 5.16 WhatsApp (tab, Profesional) — HU-24 (bloqueada, ver nota)

```
+-----------------------------------------------------+
| 💬 WhatsApp                                           |
+-----------------------------------------------------+
| Estado: Conectado — +54 9 11 xxxx-xxxx      (Activo) |
|                                    [ Reconectar ]     |
+-----------------------------------------------------+
| Mensajes enviados recientemente                        |
|  María Pérez      Confirmación    Entregado   10:02   |
|  Juan Ramírez     Recordatorio    Leído       09:00   |
|  Sofía Cano       Cancelación     Entregado   Ayer    |
+-----------------------------------------------------+
| Los tipos de mensaje que se envían por WhatsApp se     |
| controlan desde Configuración de Notificaciones.        |
|                             [ Ir a Configuración > ]   |
+-----------------------------------------------------+
```

**Decisión de diseño (WhatsApp como pantalla propia vs. configuración dentro de
Notificaciones):** se diseña como **pantalla propia en el bottom nav** (tal como en las
capturas del CEO) porque su responsabilidad es distinta de una simple preferencia: mostrar el
**estado de la conexión** de la cuenta de WhatsApp Business y el **log/histórico de mensajes
enviados** por ese canal (con estado de entrega/lectura) — información operativa, no una
preferencia binaria. Los **switches de qué se envía** (por tipo de aviso y por canal,
incluido WhatsApp) viven en un solo lugar, Configuración de Notificaciones (§5.14), para
evitar tener dos fuentes de verdad para el mismo toggle. La integración técnica con WhatsApp
Business API queda fuera del alcance de UX/UI (a definir por Arquitecto/Integraciones);
Backend ya tiene un módulo `integraciones/notificaciones.ts` que sería el punto de extensión
natural. Este wireframe asume el modelo "WhatsApp como canal adicional" (el usuario lo activa
o no desde §5.14, sin reemplazar push/email) por ser la opción reversible y de menor riesgo
para diseñar hoy; HU-24 deja explícitamente abierto si en cambio debería **reemplazar** los
canales del MVP (D4) y quién administra/paga la cuenta de WhatsApp Business (Meta) — mientras
el CEO no resuelva esa pregunta, HU-24 queda bloqueada para desarrollo (no para diseño).

### 5.17 Login / Registro — nueva, a partir de capturas (adición de UX/UI, pendiente de HU)

No estaba especificada en ningún documento anterior — el mapa de navegación (§3, §4) solo
mencionaba "Login / Registro" como nodo de entrada sin diseño propio. `Screenshot_20260805_202552_Turnario.jpg`
(la captura más reciente de las 37, 5 de agosto) muestra la pantalla real:

```
+-----------------------------------------------------+
|                    [ logo Turnario ]                  |
|                     Turnario                          |
|          Gestiona tus citas de manera fácil           |
+-----------------------------------------------------+
| [ ✉  Email                                    ]       |
+-----------------------------------------------------+
| [ 🔒 Contraseña                            👁 ]       |
+-----------------------------------------------------+
|                              ¿Olvidaste tu contraseña? |
+-----------------------------------------------------+
|             [        Iniciar sesión        ]          | ← primary sólido
+-----------------------------------------------------+
|             [ G  Google                     ]         | ← outline, login social
+-----------------------------------------------------+
|                          o                             |
+-----------------------------------------------------+
|             [        Crear Cuenta           ]         | ← outline, primary
+-----------------------------------------------------+
|   Al continuar, aceptas nuestros Términos y            |
|   Condiciones (link)                                   |
+-----------------------------------------------------+
```

Notas:
- Campo de contraseña con ícono de mostrar/ocultar (👁).
- Login social con Google como opción adicional al email/contraseña — no estaba contemplado en
  ningún documento de este proyecto hasta ahora; a confirmar con Product Manager/Arquitecto si
  Turnos Profesionales debe soportarlo (impacto en Backend/Security: OAuth, no solo
  email+password).
- Los botones de esta pantalla usan radio moderado (`radius.card`), no píldora — ver
  `sistema-diseno.md` §7.1bis.
- No se capturó la pantalla de "Crear Cuenta" en sí (solo el botón de acceso desde acá), ni el
  flujo de "¿Olvidaste tu contraseña?" — quedan sin wireframe por falta de evidencia, no se
  inventan.
- Esta pantalla es previa al split Cliente/Profesional (§1) — no se pudo determinar de la
  captura si el rol se elige en un paso posterior al login o si depende del email usado; no se
  asume ninguna de las dos opciones.

## 6. Consideraciones de diseño

- Soporte de tema claro/oscuro y diseño responsive (estándar de la empresa, ver
  `docs/07-portal-ceo.md` §10, aplicado también aquí como buena práctica transversal) — ver
  tokens concretos en `sistema-diseno.md` §3 y §8.
- El flag "requiere seña" de un servicio debe ser visible para el cliente **antes** de elegir
  el horario, no como sorpresa al confirmar (transparencia de precio).
- El estado "pendiente de pago" debe mostrarse explícitamente en "Mis Turnos" con un
  contador/aviso de expiración (ver `documento-arquitectura.md` §3, expira en 15 min).
- Los emojis usados como decoración de headers de sección (⏰, 📋, 🍽️, 🏥, ⚙️, 📅, 💬) nunca
  son el único indicador de una acción o estado — siempre acompañan texto, y deben marcarse
  como decorativos para lectores de pantalla (ver `sistema-diseno.md` §6).
- **Riesgo/pregunta abierta (ya registrada por Product Manager como pregunta abierta #1 de
  HU-16 en `02-backlog/backlog.md`):** los steppers de "Duración de cita", "Máximo de citas
  por día" y "Días de anticipación" (§5.4) introducen configuración cuantitativa general que
  podría entrar en tensión con reglas de negocio ya definidas — RN3 dice que la duración del
  turno la determina el **servicio** elegido, no una configuración general del profesional;
  RN1/RN2 rigen disponibilidad y solapamiento. UX/UI no resuelve esta tensión de negocio, solo
  deja el componente (`NumericStepperField`) listo para cuando Arquitecto defina la
  precedencia.
- **Riesgo/pregunta abierta:** en la descripción recibida, "Por confirmar" y "Programada" (los
  dos estados de turno color ámbar) parecen conceptos distintos pero visualmente idénticos —
  ver nota en `sistema-diseno.md` §3.4; Product Manager debe confirmar si son el mismo estado
  del dominio o si "Programada" debería representarse como variante de `success` (confirmada,
  a futuro).
- **Nota de privacidad/seguridad:** Importar/Exportar en Gestión de Pacientes (HU-22, §5.8) y
  los campos de salud en Ficha de Paciente (HU-20 — alergias, notas médicas, §5.9) mueven
  datos personales y de salud; ambas HU ya piden revisión de Security antes de producción
  (consentimiento, cifrado en reposo, alcance de "Descargar mis datos" de §5.13).
- **Nota de arquitectura de información** (relacionada con la pregunta abierta #6 del
  backlog — ícono "cambiar de vista" de HU-27 — y con RN9): el menú "Panel Profesional"
  (§5.11) asume que un mismo usuario puede ser Profesional y Administrador del mismo negocio a
  la vez; si Arquitecto confirma que el modelo de datos no permite esa doble investidura, hay
  que revisar tanto ese menú como el ícono de "cambiar de vista" del Dashboard antes de
  implementarlos.
- La mayoría de las pantallas nuevas de este mapa ya tienen historia asignada por Product
  Manager (HU-16 a HU-32, `02-backlog/backlog.md`) — queda **sin** número de historia
  únicamente el bloque "Seguridad de la cuenta" de Privacidad y Seguridad (§5.13, más allá de
  HU-32). Ninguna de estas pantallas bloquea el resto del desarrollo — el backlog ya aprobado
  (E0–E8) no depende de ellas.
- **Verificación contra capturas reales (2026-08-07):** este mapa se contrastó contra 37
  capturas reales de la app de referencia (antes solo había una transcripción escrita). El
  detalle completo está en **§9**; los hallazgos más importantes para priorizar son: (a)
  "Gestión de Horarios" es una sola página con scroll, no una pantalla con modales separados
  para replicar/configurar (§5.4bis); (b) existe una pantalla real y con contenido, "Gestión de
  Autorizaciones Médicas", no contemplada en ningún documento hasta ahora (§9); (c) hay una
  pantalla de Login real no diseñada hasta ahora (§5.17); (d) hay dos pantallas distintas
  llamadas "Detalles del Paciente" en la app de referencia, sin poder determinar cuál es la
  vigente (§5.9bis).
- **Riesgo/pregunta abierta (nueva):** dos ítems del menú de Configuración del Profesional
  parecen apuntar a lo mismo — "Configurar Disponibilidad" (sección Cuenta) y "Gestionar
  Horarios" (sección Panel Profesional) — ver §5.11bis. No se resuelve acá si son la misma
  pantalla con dos accesos o dos pantallas distintas.

## 7. Trazabilidad — pantalla ↔ historia de usuario

| Pantalla | Rol | HU relacionada | Estado |
|---|---|---|---|
| Buscar Negocios | Cliente | HU-00b | Sin cambios |
| Detalle de Negocio | Cliente | HU-07 | Sin cambios |
| Elegir Profesional | Cliente | HU-08 | Sin cambios |
| Horarios Disponibles | Cliente | HU-09 | Sin cambios |
| Confirmar Turno / Pago | Cliente | HU-09b | Sin cambios |
| Mis Turnos | Cliente | HU-12, HU-13 | Sin cambios |
| Dashboard | Profesional | HU-27 (E9) | Nueva pantalla |
| Agenda semanal completa | Profesional | HU-06 | Reubicada (antes pantalla raíz, ahora accesible desde Dashboard) |
| Gestión de Horarios (calendario + bloques) | Profesional | HU-05 | Extiende "Definir Disponibilidad" |
| Modal Agregar Horario | Profesional | HU-05 | Nuevo modal |
| Modal Replicar en Semanas/Meses | Profesional | HU-17 (E2) | Nueva |
| ⚙️ Configuración General — Configuración de Citas | Profesional | HU-16 (E2) | Nueva — ver riesgo RN3 en §6 |
| ⚙️ Configuración General — Tiempo de Descanso + contador de fechas | Profesional | HU-18 (E2) | Nueva |
| Excepciones / Bloquear rango | Profesional | HU-15 | Sin cambios funcionales, reubicada |
| Modal Agendar Cita manual | Profesional | HU-23 (E5) | Nueva — ver notas de diseño en §5.7 |
| Gestión de Pacientes (stats + buscador + filtros) | Profesional | HU-10 + HU-19 (E5) | Extiende "Mis Clientes" |
| Importar/Exportar pacientes | Profesional | HU-22 (E5) | Nueva — formato de archivo abierto |
| Ficha de Paciente | Profesional | HU-20 (E5) | Nueva |
| Historial de Paciente enriquecido | Profesional | HU-11 + HU-21 (E5) | Extiende |
| Configuración de Servicios | Profesional | HU-04b | Sin cambios, reubicada dentro del menú Configuración |
| Configuración (menú, Profesional) | Profesional | — (hub de navegación) | Nueva pantalla |
| Configuración (menú, Cliente) | Cliente | — (hub de navegación) | Nueva pantalla |
| Privacidad y Seguridad — bloque Privacidad | Cliente y Profesional | HU-32 (E14) | Nueva |
| Privacidad y Seguridad — bloque Seguridad de la cuenta | Cliente y Profesional | — | Adición de UX/UI, pendiente de HU |
| Configuración de Notificaciones | Cliente y Profesional | HU-26 (E7) | Nueva, granular |
| Bandeja de Notificaciones | Cliente y Profesional | HU-14 (Cliente) / HU-14b + HU-25 (Profesional, E7) | Nueva |
| WhatsApp | Profesional | HU-24 (E7) | Nueva — bloqueada para desarrollo, ver §5.16 |
| Reportes | Profesional (+Administrador) | HU-28 (E10) | Stub de navegación — contenido a diseñar cuando Product Manager cierre alcance |
| Mi Plan — Suscripción Pro | Profesional (+Administrador) | HU-29 (E11) | Stub de navegación — bloqueada, decisión de negocio pendiente |
| Configuración de Pagos y Cobros | Administrador | HU-30 (E12) | Stub de navegación |
| Datos del Consultorio / Negocio | Administrador | HU-31 (E13, extiende HU-00a) | Stub de navegación |
| Login / Registro | Cliente y Profesional | — | Adición de UX/UI a partir de capturas reales (§5.17), pendiente de HU |
| Gestión de Autorizaciones Médicas | Profesional (+Administrador) | — | Candidata nueva, evidenciada en capturas reales (§9) — sin HU, sin diseñar en profundidad, a validar con el CEO antes de escribir HU |

## 8. Pendiente

- Mockups visuales de alta fidelidad (Figma) quedan fuera de este documento — este mapa y
  `sistema-diseno.md` habilitan a Frontend/Mobile a arrancar la maquetación funcional
  mientras se producen los mockups de alta fidelidad.
- El único ítem de §7 sin historia asignada es el bloque "Seguridad de la cuenta" de
  Privacidad y Seguridad (§5.13) — Product Manager debe decidir si amplía HU-32 o crea una
  historia nueva antes de que pase a desarrollo; UX/UI ya dejó wireframe listo para no
  bloquear ese trabajo.
- Las historias HU-16 a HU-32 tienen preguntas abiertas propias registradas por Product
  Manager en `02-backlog/backlog.md` (sección "Preguntas abiertas de esta ampliación") que
  condicionan el desarrollo, no el diseño — esta entrega de UX/UI no depende de que el CEO las
  responda, pero Backend/Arquitecto sí antes de implementar.
- Las preguntas abiertas de negocio detectadas por UX/UI en §6 (precedencia RN3 vs. HU-16,
  ambigüedad Programada/Confirmada, doble rol Profesional/Administrador frente a RN9)
  requieren respuesta de Product Manager/Arquitecto antes de que Backend implemente esas
  reglas.
- **Verificación contra capturas reales (2026-08-07):** ver §9 — resumen de qué se confirmó, qué
  se corrigió, y qué aparece en las capturas y todavía no tiene HU (a validar con el CEO antes de
  construir más UI sobre esta base).

## 9. Verificación contra capturas reales (2026-08-07)

### 9.1 Origen y metodología

Hasta esta fecha, este mapa (y `sistema-diseno.md`) se redactó a partir de una transcripción
escrita de 20 capturas que el CEO pegó en el chat — sin acceso directo a los píxeles. El CEO
cargó 37 capturas reales de "Turnario Pro" (su app personal, en pre-producción, autorizada
explícitamente como referencia) en `04-diseno/referencias/`, con fechas entre el 10 de abril y el
5 de agosto de 2026. El detalle punto por punto está en las secciones "bis" ya insertadas junto a
cada wireframe corregido (§5.2bis, §5.4bis, §5.5bis, §5.6bis, §5.7bis, §5.8bis, §5.9bis,
§5.11bis, §5.13bis, §5.14bis) y en la nueva §5.17 (Login). Las correcciones de tokens/componentes
(color, tipografía, radio, íconos) están en `sistema-diseno.md` §12. Esta sección resume lo más
importante, priorizado.

### 9.2 Confirmado (la transcripción original acertó)

- Los 4 roles de estado de turno/paciente y su codificación de color (§3.4 de
  `sistema-diseno.md`).
- Bottom nav de 6 ítems del Profesional, orden e íconos exactos.
- El wireframe de Horarios Disponibles (Cliente, §5.1) y de Historial de Paciente (§5.10) —
  ningún cambio necesario, coinciden de cerca con las capturas reales.
- El campo de texto libre "Hora" (ej. "10:00, 14:30") del modal de agendar cita manual — existe
  tal cual en la app real (§5.7bis); la alternativa de chips que propone este documento sigue
  siendo una recomendación de UX/UI, no una corrección de un malentendido.
- El bloque "Seguridad de la cuenta" de Privacidad y Seguridad, ya marcado como adición de UX/UI
  sin HU — se confirma que no existe en la app real, validando que efectivamente era una
  adición y no algo mal transcripto.
- El supuesto multi-rubro (D1): la cuenta del propio CEO en la app de referencia es de
  "Entrenamiento Personal", no de un rubro médico.

### 9.3 Corregido (ver el detalle en cada "bis" referenciado arriba)

Los cambios de mayor impacto para el equipo, de mayor a menor prioridad:

1. **Gestión de Horarios es una sola página con scroll**, no una pantalla corta con modales
   separados de "Agregar Horario"/"Replicar" — reestructura significativa, ver §5.4bis. Además,
   las propias capturas muestran dos versiones de esta pantalla en fechas distintas (23 de abril
   vs. 25/27 de abril) — recomendamos confirmar con el CEO cuál es la vigente antes de que Mobile
   la construya.
2. Los controles de "Replicar en semanas/meses" son chips preestablecidos (4/8/12 semanas, ~6
   meses) + 1 switch, no dos steppers + dos radios (§5.6bis).
3. El modal real de agregar un horario puntual ("Agregar Nuevo Horario") es mucho más simple que
   el wireframe original: sin selector de servicio ni de recurrencia (§5.5bis).
4. Dashboard usa header blanco, no de color sólido, y sí tiene el ícono de "cambiar de vista" que
   este mapa había decidido omitir (§5.2bis).
5. Gestión de Pacientes: sin FAB (son botones de texto arriba), acciones de fila reales distintas
   (Ver/Editar/Agendar/Historial, no Historial/Editar/Contactar/Eliminar), 4ta métrica "Nuevos"
   (§5.8bis).
6. El menú de Configuración tiene un header de perfil (no solo un título), reubica "Mi Plan" en
   Cuenta, y trae una sección "Pagos y Señas" completa con texto exacto del toggle de seña —
   insumo directo para HU-30/HU-09b (§5.11bis).
7. Varios modales tienen 3 botones de footer (Cancelar + Guardar verde + Restablecer naranja), no
   2 — con un bug de recorte de texto real a evitar en QA (§5.13bis, §5.14bis,
   `sistema-diseno.md` §7.8bis).

### 9.4 Nuevo en las capturas, sin documentar todavía — candidatos para el CEO

1. **"Gestión de Autorizaciones Médicas"** (menú Configuración → Panel Profesional). Pantalla
   real, no un stub: 3 pestañas ("Autorizaciones", "Relaciones", "Registro de Accesos"); la
   pestaña capturada ("Registro de Accesos Recientes") muestra un log de intentos de acceso
   denegados a datos de salud de un paciente, identificado por ID crudo de base de datos en vez
   de nombre — probablemente una vista de datos de desarrollo/depuración más que una pantalla
   final pulida, pero el **concepto de fondo** (control de acceso/autorizaciones sobre datos de
   salud, con auditoría) es real y sustancial — no es algo que UX/UI pueda diseñar sin que
   Product Manager primero defina qué problema de negocio resuelve y escriba la(s) historia(s)
   correspondiente(s). Se marca como la novedad más importante de esta revisión — recomendamos
   presentarla al CEO antes de invertir tiempo de diseño ahí.
2. **Pantalla de Login/Registro real** (§5.17) — email/contraseña + login social con Google +
   "Crear Cuenta" + recuperación de contraseña. El login social con Google no estaba contemplado
   en ningún documento del proyecto — impacto potencial en Backend (OAuth) y Security a evaluar
   si se decide incluirlo.
3. **"Configurar Disponibilidad"** como ítem de menú separado de "Gestionar Horarios" — posible
   duplicado, no una pantalla nueva confirmada (§5.11bis).
4. **"Agendar Cita" como modal separado de "Crear Nueva Cita"** — variante contextual (parte de
   un paciente ya elegido) del flujo de HU-23, con servicio predeterminado y patrón de tarjeta de
   paciente de solo lectura (§5.7bis).
5. **Sección "Pagos y Señas"** completa (toggle de seña con copy exacto + Historial de Señas +
   Precios y Señas) como posible base para desarrollar HU-30 más allá del stub actual (§5.11bis).
6. **Dos pantallas "Detalles del Paciente" distintas** — a resolver cuál es la vigente antes de
   construir cualquiera de las dos en Turnos Profesionales (§5.9bis).

### 9.5 Capturas no del todo legibles

- `Screenshot_20260425_040313_Expo Go.jpg` y `Screenshot_20260425_043732_Expo Go~2 (1).jpg`: una
  fila de leyenda del calendario ("Con citas"/"Disponible") queda tapada por la barra de
  navegación del sistema Android — no se pudo leer su estilo real (`sistema-diseno.md` §7.5bis).
- `Screenshot_20260425_043732_Expo Go~2 (1).jpg` tiene además un círculo dibujado a mano en rojo
  sobre el header, aparentemente una anotación del CEO — no se puede inferir qué estaba marcando
  sin preguntarle directamente.
- El resto de las 37 capturas se pudo leer con claridad; no hubo más casos de desenfoque, corte
  o overlay que impidiera la lectura.
