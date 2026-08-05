# Backlog Priorizado — Turnos Profesionales

**Proyecto:** TURNOS-2026-001
**Rol:** Product Manager
**Fase:** 2 — Descubrimiento
**Entradas:** `proyectos/turnos-profesionales/01-requisitos/documento-funcional.md` (Business Analyst)

## Visión de producto

App mobile que conecta clientes con profesionales para la reserva de turnos, permitiendo a
cada profesional gestionar su propia agenda y cartera de clientes, y al cliente reservar sin
fricción en tres pasos: servicio → profesional → horario.

> **Actualizado tras decisiones del CEO** (ver `01-requisitos/documento-funcional.md` §1,
> D1–D5): la plataforma es **multi-negocio**, el pago/seña es **configurable por
> profesional**, el historial es **privado por profesional**, las **notificaciones entran al
> MVP**, y **no hay lista de espera** (se muestra el próximo disponible).

## Roadmap de producto

- **V1 (MVP):** descubrimiento de negocio + flujo completo de reserva cliente↔profesional,
  multi-tenant desde el diseño de datos, seña configurable por profesional, notificaciones
  básicas. Épicas E0–E4, E7.
- **V2:** cancelación/reprogramación, historial enriquecido, excepciones de disponibilidad.
  Épicas E5–E6, E8.
- **V3:** medios de pago adicionales, panel de administración avanzado, analítica por negocio.

## Épicas

| # | Épica | Prioridad |
|---|---|---|
| E0 | Alta y descubrimiento de negocios (multi-tenant) | P0 |
| E1 | Alta de servicios y profesionales por negocio | P0 |
| E2 | Gestión de disponibilidad del profesional | P0 |
| E3 | Reserva de turno (cliente), con seña opcional por profesional | P0 |
| E4 | Autenticación y perfiles | P0 |
| E7 | Notificaciones (confirmación y recordatorio) | P0 |
| E5 | Gestión de clientes e historial (profesional) | P1 |
| E6 | Cancelación y reprogramación de turnos | P1 |
| E8 | Excepciones de disponibilidad (feriados/licencias) | P2 |

---

## E4 — Autenticación y perfiles (P0, bloquea todo lo demás)

**HU-01.** Como cliente o profesional, quiero registrarme e iniciar sesión, para poder
acceder a las funciones de la app según mi rol.
- Criterios de aceptación:
  - Registro con email/teléfono + contraseña (o proveedor externo, a definir con Arquitecto).
  - Al iniciar sesión, la app distingue si soy Cliente, Profesional o Administrador de negocio
    y muestra la vista correspondiente.
  - Un profesional y un administrador quedan asociados a exactamente un negocio (RN9).

**HU-02.** Como administrador de un negocio, quiero dar de alta profesionales, para que
puedan gestionar su propia agenda dentro de mi negocio.

---

## E0 — Alta y descubrimiento de negocios (multi-tenant) (P0)

**HU-00a.** Como administrador, quiero registrar mi negocio en la plataforma (nombre,
rubro/categoría, ubicación), para empezar a operar de forma aislada de otros negocios (D1, RN9).

**HU-00b.** Como cliente, quiero buscar o navegar negocios disponibles en la plataforma, para
elegir dónde quiero reservar un turno. (CU3)
- Criterios de aceptación: el listado no mezcla datos entre negocios (RN9); el mecanismo de
  búsqueda concreto (ubicación, categoría, texto) lo define UX/UI en Fase 3.

---

## E1 — Alta de servicios y profesionales por negocio (P0)

**HU-03.** Como administrador, quiero cargar los servicios que ofrece mi negocio (nombre,
duración, precio de referencia), para que los profesionales puedan asociarlos a su agenda.
- Criterios de aceptación:
  - Un servicio tiene nombre, duración en minutos y precio de referencia (RN3).
  - Un servicio puede asociarse a uno o más profesionales del mismo negocio (RN4).

**HU-04.** Como administrador, quiero asociar uno o más servicios a cada profesional de mi
negocio, para que el cliente solo vea combinaciones válidas al reservar.

**HU-04b.** Como profesional, quiero configurar si un servicio que ofrezco requiere seña/pago
anticipado para reservarse, para reducir ausencias en los servicios que elijo. (D2, RN10)

---

## E2 — Gestión de disponibilidad del profesional (P0)

**HU-05.** Como profesional, quiero definir bloques de disponibilidad recurrentes por
servicio, para que el sistema calcule los horarios reservables. (CU1)
- Criterios de aceptación:
  - Puedo definir días y rangos horarios semanales por servicio.
  - El sistema genera slots según la duración del servicio (RN3) sin solaparse entre sí (RN2).

**HU-06.** Como profesional, quiero ver mi calendario con los turnos ya reservados y los
slots libres, para tener visibilidad completa de mi agenda.

---

## E3 — Reserva de turno (cliente), con seña opcional por profesional (P0)

**HU-07.** Como cliente, quiero elegir un servicio dentro del negocio que elegí, para filtrar
los profesionales disponibles para eso. (CU4, paso 1)

**HU-08.** Como cliente, quiero elegir un profesional entre los que ofrecen el servicio
elegido dentro de ese negocio, para ver sus horarios disponibles. (CU4, paso 2)

**HU-09.** Como cliente, quiero ver los horarios disponibles del profesional elegido y
reservar uno, para confirmar mi turno. (CU4, pasos 3–4, 6)
- Criterios de aceptación:
  - Solo se muestran slots dentro de la disponibilidad publicada y no ocupados (RN1).
  - Si dos clientes intentan reservar el mismo slot al mismo tiempo, solo uno de los dos
    obtiene la reserva; el otro ve el slot como no disponible (requisito no funcional →
    Arquitecto/Backend deben resolver la concurrencia).
  - Si no hay horarios en el rango consultado, se muestra el próximo disponible (D5, sin lista
    de espera).

**HU-09b.** Como cliente, quiero pagar la seña cuando el profesional la requiere para el
servicio elegido, para poder confirmar la reserva. (CU4, paso 5, D2/RN10)
- Criterios de aceptación:
  - Si el profesional no requiere seña para ese servicio, el turno se confirma sin pedir pago.
  - Si la requiere, el turno queda "pendiente de pago" hasta que el pago se acredite; si el
    pago falla o se abandona, el slot vuelve a estar libre.
  - El medio de pago concreto lo define Arquitecto/CTO IA (Fase 3).

---

## E5 — Gestión de clientes e historial (profesional) (P1)

**HU-10.** Como profesional, quiero ver el listado de mis clientes, para identificar
rápidamente a quién atendí. (CU2)

**HU-11.** Como profesional, quiero ver el historial de visitas de un cliente (fecha,
servicio), para dar continuidad a la atención. (CU2, RN7/D3 — el historial es privado, solo
lo ve el profesional que atendió cada visita).

---

## E6 — Cancelación y reprogramación de turnos (P1)

**HU-12.** Como cliente, quiero cancelar un turno reservado, para liberar el horario si ya no
lo necesito. (CU4)
- Criterios de aceptación: solo permitido fuera de la ventana mínima de cancelación (RN8,
  supuesto A3); fuera de esa ventana, la app indica contactar al negocio.

**HU-13.** Como cliente, quiero reprogramar un turno a otro horario disponible del mismo
profesional/servicio, sin tener que cancelar y volver a reservar desde cero. (CU4)

---

## E7 — Notificaciones (P0, confirmado en MVP — D4)

**HU-14.** Como cliente, quiero recibir una confirmación al reservar y un recordatorio antes
del turno, para no olvidarlo. (D4)

**HU-14b.** Como profesional, quiero recibir una notificación cuando un cliente reserva,
cancela o reprograma un turno, para mantener mi agenda actualizada sin tener que revisarla
constantemente.

## E8 — Excepciones de disponibilidad (P2)

**HU-15.** Como profesional, quiero bloquear puntualmente parte de mi agenda (feriado,
licencia), para que no se generen turnos en ese rango. (CU1, RN5)
- Criterios de aceptación: si ya existen turnos reservados en el rango bloqueado, el sistema
  advierte y requiere gestionar la reprogramación antes de confirmar el bloqueo (RN6).

---

## Siguiente paso

Con las 5 decisiones de negocio confirmadas (D1–D5) y el backlog actualizado, la Fase 3
(Diseño) arranca sin bloqueos de negocio pendientes: CTO IA/Arquitecto definen la solución
técnica (multi-tenancy, concurrencia de reservas de HU-09, integración de pagos de HU-09b),
UX/UI diseña las pantallas de E0/E3/E2, y DBA modela las entidades del glosario del documento
funcional (incluyendo Negocio como entidad raíz).
