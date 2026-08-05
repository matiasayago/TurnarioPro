# Proyecto: Turnos Profesionales

**Identificador:** TURNOS-2026-001
**Fecha de registro:** 2026-08-05
**Registrado por:** CEO (Matías Sayago)
**Fase actual:** 4 — Desarrollo (backend completo y verificado; mobile escrito, sin compilar)

## Objetivo

Aplicación mobile para la reserva de turnos con distintos profesionales, con dos vistas:

### Vista Profesional
- Gestión de calendario propio.
- Definición de horarios de disponibilidad.
- Listado de sus clientes.
- Historial de visitas por cliente.

### Vista Cliente
- Selección de servicio o consultorio.
- Selección de profesional.
- Selección de horario disponible.
- Reserva del turno.

## Alcance inicial (brief del CEO, sin refinar aún)

> "Necesito crear una aplicación mobile que realice turnos a diferentes profesionales que
> maneje calendario, horarios de disponibilidad del profesional, que tenga la opción el
> profesional de ver sus clientes y su historial de visitas. En modo del cliente pueda
> seleccionar el servicio o consultorio y seleccionar el profesional y los horarios
> disponibles para poder reservar un turno."

## Estado de las fases

| Fase | Responsable | Estado |
|---|---|---|
| 1. Inicio | CEO | ✅ Completa |
| 2. Descubrimiento | Business Analyst → Product Manager | ✅ Completa (decisiones D1–D5 confirmadas por el CEO) |
| 3. Diseño | CTO IA, Arquitecto, UX/UI, DBA | ✅ Completa (aprobada por el CEO) |
| 4. Desarrollo | Backend, Mobile | 🔄 Backend completo (incl. HU-13 reprogramación, expiración automática, RLS de Postgres) y probado end-to-end; Mobile escrito, incl. reprogramar, pero sin compilar (sin Flutter SDK en el entorno) |
| 5. Calidad | QA, Security | ⏳ Pendiente |
| 6. Despliegue | DevOps | ⏳ Pendiente |
| 7. Cierre | Technical Writer, Director General IA, CEO | ⏳ Pendiente |

Ver ciclo de vida completo en [`docs/04-manual-operativo.md`](../../docs/04-manual-operativo.md) §3.
