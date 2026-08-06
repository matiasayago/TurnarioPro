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
