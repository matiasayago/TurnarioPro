# Documento de Arquitectura — Turnos Profesionales

**Rol:** Arquitecto
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md`, `02-backlog/backlog.md`,
`03-arquitectura/lineamientos-tecnicos.md` (CTO IA)

## 1. Componentes (modular monolito, ver lineamientos-tecnicos.md §2)

```
Flutter App (Cliente / Profesional)
        │  REST + JWT
        ▼
┌─────────────────────────── Backend (modular monolito) ───────────────────────────┐
│  Identity Module   │ Negocios Module │ Catálogo Module │ Disponibilidad Module   │
│  Reservas Module   │ Pagos Module    │ Notificaciones Module                     │
└─────────────────────────────────────────────────────────────────────────────────┘
        │                                   │                    │
        ▼                                   ▼                    ▼
   PostgreSQL (RLS por negocio_id)     Mercado Pago API      Firebase Cloud Messaging
```

- **Identity Module:** registro/login, emisión de JWT con claims `rol` y `negocio_id`.
- **Negocios Module:** alta de negocio, búsqueda/listado para el cliente (CU3).
- **Catálogo Module:** servicios por negocio, asociación servicio↔profesional, configuración
  de seña por servicio/profesional (D2/RN10).
- **Disponibilidad Module:** bloques recurrentes y excepciones del profesional (CU1); genera
  los slots reservables.
- **Reservas Module:** el módulo crítico — crea, cancela y reprograma turnos; dueño de la
  garantía de no-doble-reserva (§4).
- **Pagos Module:** crea intención de pago con Mercado Pago cuando el servicio la requiere;
  escucha el webhook de confirmación y actualiza el estado del turno.
- **Notificaciones Module:** confirmaciones y recordatorios (D4) vía FCM.

## 2. Contratos de API (nivel conceptual — REST)

| Recurso | Endpoints principales |
|---|---|
| Negocios | `GET /negocios`, `GET /negocios/{id}/servicios` |
| Servicios | `POST /negocios/{id}/servicios`, `PATCH /servicios/{id}` (incluye flag `requiere_sena`) |
| Profesionales por servicio | `GET /negocios/{id}/servicios/{servicioId}/profesionales` (HU-08) |
| Profesionales | `POST /negocios/{id}/profesionales`, `GET /profesionales/{id}` |
| Disponibilidad | `POST /profesionales/{id}/disponibilidad`, `POST /profesionales/{id}/excepciones` |
| Turnos | `GET /profesionales/{id}/slots?servicio_id=&desde=`, `GET /profesionales/{id}/turnos` (agenda, HU-06), `POST /turnos`, `GET /turnos/mios`, `PATCH /turnos/{id}/cancelar`, `PATCH /turnos/{id}/reprogramar` (pendiente) |
| Clientes (vista profesional) | `GET /profesionales/{id}/clientes`, `GET /clientes/{id}/historial` (filtrado por `profesional_id` del JWT — D3) |
| Pagos | `POST /turnos/{id}/pago`, webhook `POST /webhooks/mercadopago` |

Todos los endpoints de alcance de negocio filtran server-side por `negocio_id` del JWT (RN9),
nunca por parámetro confiado del cliente.

## 3. Modelo de estados de un turno

```
DISPONIBLE (slot libre)
   │  POST /turnos
   ▼
PENDIENTE_DE_PAGO ──(sin seña requerida)──► CONFIRMADO
   │  pago acreditado (webhook)                  │
   ▼                                              │
CONFIRMADO ◄─────────────────────────────────────┘
   │  cancelar/reprogramar (RN8, ventana A3)
   ▼
CANCELADO / REPROGRAMADO
```

- `PENDIENTE_DE_PAGO` expira a los 15 minutos (parametrizable) si el webhook de Mercado Pago
  no confirma el pago; al expirar, el slot vuelve a `DISPONIBLE` (mitiga el riesgo de
  "turno colgado" identificado por CTO IA).

## 4. Estrategia de concurrencia (garantiza RN2 — no doble reserva)

Requisito no funcional de HU-09: si dos clientes intentan reservar el mismo slot al mismo
tiempo, solo uno debe tener éxito.

**Decisión:** constraint único a nivel de base de datos, no solo lógica de aplicación.

```sql
-- Un profesional no puede tener dos turnos activos que se solapen en el mismo horario exacto
CREATE UNIQUE INDEX uq_turno_slot_activo
  ON turnos (profesional_id, inicio)
  WHERE estado IN ('PENDIENTE_DE_PAGO', 'CONFIRMADO');
```

El flujo de reserva hace `INSERT` directo (no "verificar y luego insertar"); si el índice
único rechaza el insert por violación, el Backend responde `409 Conflict` y el Frontend
refresca los slots disponibles para ese profesional. Esto es más robusto que un `SELECT` de
verificación previo, que sigue siendo vulnerable a condiciones de carrera entre el `SELECT` y
el `INSERT`.

## 5. Seguridad (a validar por Security antes de despliegue)

- JWT con expiración corta + refresh token.
- RBAC: scopes `cliente`, `profesional`, `administrador`, siempre acotados por `negocio_id`.
- Row Level Security en PostgreSQL como segunda barrera de aislamiento multi-tenant (RN9).
- Webhook de Mercado Pago validado por firma, no solo por IP de origen.
- Ningún dato de historial de un cliente se expone a un profesional que no lo atendió (D3) —
  se valida a nivel de query, no solo de UI.

## 6. Alineación con el backlog

| Épica | Módulo responsable |
|---|---|
| E0 Alta y descubrimiento de negocios | Negocios Module |
| E1 Servicios y profesionales | Catálogo Module |
| E2 Disponibilidad | Disponibilidad Module |
| E3 Reserva + seña | Reservas Module + Pagos Module |
| E4 Autenticación | Identity Module |
| E5 Clientes e historial | Reservas Module (consulta filtrada) |
| E6 Cancelación/reprogramación | Reservas Module |
| E7 Notificaciones | Notificaciones Module |
| E8 Excepciones de disponibilidad | Disponibilidad Module |

## 7. Pendiente para Fase 4

- DBA: modelo de datos detallado (`06-modelo-datos` de este proyecto, ver `04-diseno` una vez
  UX/UI entregue mockups y este documento quede aprobado).
- Backend: implementación por módulo, empezando por Identity + Negocios + Catálogo
  (bloqueantes de todo lo demás).
