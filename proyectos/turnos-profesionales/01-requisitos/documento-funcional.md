# Documento Funcional — Turnos Profesionales

**Proyecto:** TURNOS-2026-001
**Rol:** Business Analyst
**Fase:** 2 — Descubrimiento
**Entradas:** Brief del CEO (ver `proyectos/turnos-profesionales/00-resumen.md`)

## 1. Alcance y decisiones confirmadas por el CEO

El CEO respondió las preguntas abiertas de la primera versión de este documento. Decisiones
vigentes:

- **D1 (confirmado — reemplaza A1). Multi-negocio.** La plataforma es multi-tenant: varios
  negocios/comercios independientes, cada uno con sus propios profesionales, servicios y
  clientes, conviven en la misma app. "Seleccionar el servicio o consultorio" ahora se
  interpreta en dos niveles: el cliente primero encuentra/selecciona el **negocio o
  consultorio** (entre varios negocios dados de alta en la plataforma) y luego el servicio
  dentro de ese negocio. Esto es la decisión de mayor impacto en arquitectura y modelo de
  datos — introduce una entidad **Negocio (tenant)** como raíz de aislamiento de datos.
- **D2 (confirmado — reemplaza A4). Pago/seña configurable por profesional.** El cobro de
  seña al reservar **no es una regla global**: cada profesional configura si su servicio
  requiere seña/pago anticipado o no. Un mismo negocio puede tener profesionales que cobran
  seña y otros que no.
- **D3 (confirmado — reemplaza RN7 abierta). Historial privado por profesional.** El
  historial de visitas de un cliente lo ve únicamente el profesional que lo atendió; no se
  comparte entre profesionales del mismo negocio, ni siquiera con el administrador (salvo que
  una fase futura defina permisos de administrador — no incluido en este alcance).
- **D4 (confirmado — reemplaza A6). Notificaciones en el MVP.** Confirmaciones y recordatorios
  de turno son parte del alcance del MVP, no de una fase futura.
- **D5 (confirmado — reemplaza A5). Próximo disponible, sin lista de espera.** Si no hay
  horarios en el rango consultado, se muestra el próximo horario libre. No hay lista de
  espera en este alcance.

Supuestos que se mantienen sin cambios (no formaban parte de las 5 preguntas priorizadas):

- **A2.** Cada servicio tiene una duración fija (usada para calcular slots de calendario) y
  un precio de referencia informativo.
- **A3.** El cliente puede cancelar o reprogramar un turno hasta una ventana mínima antes del
  horario reservado (valor por defecto propuesto: 2 horas); el profesional puede bloquear
  horarios en cualquier momento. *(Sigue abierto a confirmación si 2 horas es el valor
  correcto — no bloquea el diseño, es parametrizable.)*
- **A7.** Existe un rol de administración por negocio (da de alta profesionales y servicios
  de su propio negocio; no ve datos de otros negocios — reforzado por D1).

## 2. Actores / roles de usuario

| Rol | Descripción |
|---|---|
| **Cliente** | Usuario final que busca y reserva turnos. |
| **Profesional** | Presta el servicio; gestiona su disponibilidad, ve sus clientes y el historial de visitas. |
| **Administrador del negocio** | (Supuesto A7) Da de alta/baja profesionales, servicios y consultorios; no necesariamente atiende turnos. |

## 3. Reglas de negocio

- **RN1.** Un turno solo puede reservarse dentro de un bloque de disponibilidad publicado por
  el profesional para ese servicio.
- **RN2.** Dos turnos del mismo profesional no pueden solaparse en el tiempo.
- **RN3.** La duración del turno la determina el servicio elegido, no el cliente.
- **RN4.** Un profesional puede ofrecer uno o más servicios; un servicio puede ser ofrecido
  por uno o más profesionales (relación N:M).
- **RN5.** El profesional puede definir excepciones puntuales a su disponibilidad general
  (feriados, licencias, bloqueos de agenda) que anulan slots ya publicados pero sin turno
  reservado.
- **RN6.** Un turno reservado no puede eliminarse por una excepción de disponibilidad sin
  antes notificar y ofrecer reprogramación al cliente.
- **RN7.** El historial de visitas de un cliente es visible únicamente para el profesional
  que lo atendió (D3). No se comparte entre profesionales del mismo negocio.
- **RN8.** Cancelaciones y reprogramaciones fuera de la ventana mínima definida (supuesto A3)
  requieren contacto directo con el negocio (fuera del flujo automático de la app en el MVP).
- **RN9.** Cada negocio opera de forma aislada: un profesional, servicio, cliente o turno
  pertenece a un único negocio; ningún dato de un negocio es visible desde otro (D1).
- **RN10.** Cada profesional configura, por servicio, si requiere seña/pago anticipado para
  confirmar la reserva (D2). Si lo requiere, el turno queda en estado "pendiente de pago"
  hasta confirmarse (el mecanismo de pago concreto lo define Arquitecto/CTO IA en Fase 3).

## 4. Casos de uso

### CU1 — Profesional define su disponibilidad
- **Actor:** Profesional.
- **Precondición:** El profesional está autenticado y tiene al menos un servicio asignado.
- **Flujo principal:**
  1. El profesional accede a su calendario.
  2. Define bloques de disponibilidad recurrentes (ej. días y horarios semanales) por servicio.
  3. El sistema genera los slots reservables según la duración de cada servicio.
- **Flujos alternativos:**
  - El profesional agrega una excepción puntual (bloqueo/feriado) → el sistema retira los
    slots libres afectados y advierte si hay turnos ya reservados en ese rango (RN6).

### CU2 — Profesional ve sus clientes y el historial de visitas
- **Actor:** Profesional.
- **Precondición:** El profesional tiene al menos un turno atendido.
- **Flujo principal:**
  1. El profesional accede al listado de sus clientes.
  2. Selecciona un cliente y ve el historial de visitas (fecha, servicio, notas si existieran).
- **Flujo alternativo:** Cliente nuevo sin historial previo → se muestra listado vacío.

### CU3 — Cliente descubre y elige un negocio
- **Actor:** Cliente.
- **Precondición:** Ninguna (puede ocurrir antes de registrarse).
- **Flujo principal:**
  1. El cliente busca o navega el listado de negocios/consultorios disponibles en la plataforma.
  2. Selecciona un negocio.
  3. El sistema muestra los servicios que ofrece ese negocio (RN9 — datos aislados por negocio).
- **Nota:** el mecanismo de búsqueda (por ubicación, categoría, nombre) lo define UX/UI en Fase 3.

### CU4 — Cliente reserva un turno
- **Actor:** Cliente.
- **Precondición:** El cliente eligió un negocio (CU3) y está registrado (o se registra en el
  flujo, según defina UX/UI).
- **Flujo principal:**
  1. El cliente selecciona el servicio dentro del negocio elegido.
  2. El cliente selecciona un profesional (filtrado por servicio elegido).
  3. El sistema muestra los horarios disponibles del profesional para ese servicio.
  4. El cliente selecciona un horario.
  5. Si el profesional requiere seña para ese servicio (RN10), el sistema solicita el pago
     antes de confirmar; si no, confirma directamente.
  6. El sistema bloquea el slot y confirma el turno (RN1, RN2).
  7. El sistema dispara la notificación de confirmación (D4).
- **Flujos alternativos:**
  - No hay horarios disponibles en los próximos días → se muestra el próximo disponible (D5).
  - Dos clientes intentan reservar el mismo slot simultáneamente → el sistema debe garantizar
    que solo uno de los dos obtenga la reserva (requisito no funcional para Arquitecto/Backend).
  - El pago de la seña falla o se abandona → el turno no se confirma y el slot permanece libre.

### CU5 — Cliente cancela o reprograma un turno
- **Actor:** Cliente.
- **Precondición:** El cliente tiene un turno reservado a futuro.
- **Flujo principal:**
  1. El cliente selecciona el turno desde su listado de reservas.
  2. Cancela o solicita reprogramar (elige nuevo horario disponible del mismo profesional/servicio).
  3. El sistema libera el slot original y, si aplica, reserva el nuevo.
- **Flujo alternativo:** Intento fuera de la ventana mínima de cancelación (RN8) → el sistema
  informa que debe contactar al negocio directamente.

## 5. Glosario de entidades de negocio

*(Sin diseño de modelo de datos — corresponde a DBA en Fase 3)*

- **Negocio (tenant)** — comercio/consultorio dado de alta en la plataforma; raíz de
  aislamiento de datos (D1, RN9). Tiene profesionales, servicios y clientes propios.
- **Cliente** — persona que reserva turnos; puede reservar en más de un negocio.
- **Profesional** — persona que presta servicios y gestiona su disponibilidad, perteneciente
  a un único negocio.
- **Servicio** — prestación ofrecida por un negocio (nombre, duración, precio de referencia,
  configuración de seña por profesional — D2).
- **Disponibilidad** — bloques de tiempo en que un profesional ofrece un servicio.
- **Excepción de disponibilidad** — bloqueo puntual sobre la disponibilidad general.
- **Turno** — reserva concreta de un cliente con un profesional, servicio y horario, dentro de
  un negocio; puede tener un pago/seña asociado (D2).
- **Historial de visitas** — registro histórico de turnos atendidos de un cliente, visible
  solo para el profesional que lo atendió (D3).

## 6. Preguntas abiertas — resueltas

Las 5 preguntas originales fueron respondidas por el CEO y están incorporadas como decisiones
D1–D5 en la §1. Preguntas menores que quedan abiertas y no bloquean el diseño (parametrizables):

1. Valor exacto de la ventana mínima de cancelación (A3, propuesto 2 horas).
2. Alcance de permisos del administrador del negocio sobre el historial de clientes (A7/D3
   dejan al administrador sin acceso al historial por defecto — confirmar si es correcto).

Con las decisiones D1–D5 confirmadas, el proyecto avanza a Fase 3 (Diseño).
