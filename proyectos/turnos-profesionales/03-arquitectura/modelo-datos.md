# Modelo de Datos — Turnos Profesionales

**Rol:** DBA
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md` §5 (glosario), `documento-arquitectura.md`

## 1. Reglas de diseño aplicadas

Siguiendo el estándar de la empresa (`docs/06-modelo-datos.md` §3):
- Todas las entidades usan **GUID** como clave primaria.
- Auditoría completa: `creado_en`, `creado_por`, `modificado_en`, `modificado_por` en toda tabla.
- **Soft delete** (`eliminado_en`) en Negocio, Profesional, Servicio (para no romper el
  historial de turnos ya realizados si se da de baja un profesional o servicio).
- Aislamiento multi-tenant: `negocio_id` obligatorio y no nulo en toda tabla de alcance de
  negocio, reforzado con Row Level Security (ver `documento-arquitectura.md` §3, §5).

## 2. Entidades principales

| Entidad | Descripción | Relaciones |
|---|---|---|
| **Negocio** | Comercio/consultorio, raíz de aislamiento multi-tenant (D1). | 1:N Profesional, Servicio, Cliente-en-negocio |
| **Usuario** | Identidad base (email, hash de contraseña, rol: cliente/profesional/administrador). | 1:1 Profesional (si rol=profesional) |
| **Profesional** | Extiende Usuario; pertenece a un Negocio. | N:1 Negocio, N:M Servicio (vía ProfesionalServicio), 1:N Disponibilidad, 1:N Turno |
| **Servicio** | Prestación ofrecida por un Negocio (nombre, duración, precio). | N:1 Negocio, N:M Profesional |
| **ProfesionalServicio** | Tabla de asociación N:M; lleva el flag `requiere_sena` y `monto_sena` (D2/RN10) — la seña se configura por combinación profesional+servicio, no globalmente. | N:1 Profesional, N:1 Servicio |
| **Disponibilidad** | Bloque recurrente (día de semana, hora inicio/fin) de un profesional para un servicio. | N:1 Profesional, N:1 Servicio |
| **ExcepcionDisponibilidad** | Bloqueo puntual (fecha/hora inicio-fin) que anula disponibilidad general (RN5). | N:1 Profesional |
| **Turno** | Reserva concreta: cliente + profesional + servicio + horario + estado (ver máquina de estados en `documento-arquitectura.md` §3). | N:1 Negocio, N:1 Profesional, N:1 Servicio, N:1 Usuario (cliente) |
| **Pago** | Registro de intención/confirmación de pago de seña asociado a un Turno (D2). | 1:1 Turno (cuando aplica) |
| **Notificacion** | Registro de notificaciones enviadas (confirmación, recordatorio) — D4. | N:1 Turno |

*(Historial de visitas no es una entidad propia: es una consulta de `Turno` filtrada por
`cliente_id` + `profesional_id` con estado "atendido", reforzando RN7/D3 — un profesional solo
puede filtrar por su propio `profesional_id`.)*

## 3. Diagrama conceptual

```
Negocio
 ├── Profesional ──┬── Disponibilidad
 │                  ├── ExcepcionDisponibilidad
 │                  └── ProfesionalServicio ── Servicio
 ├── Servicio
 └── Turno ── Usuario(cliente)
       ├── Pago
       └── Notificacion
```

## 4. Script de creación (DDL inicial)

Guardado en
[`05-codigo/database/migrations/001_init.sql`](../05-codigo/database/migrations/001_init.sql)
para que Backend/DevOps lo apliquen al levantar el entorno de desarrollo.

## 5. Row Level Security (Postgres, producción)

Implementado en el DDL (`05-codigo/database/migrations/001_init.sql`), **no verificado contra
un Postgres real** — este entorno de desarrollo no tiene `psql`/Docker instalados (ver
`memory/proyectos/turnos-profesionales/decisiones.md`). Antes de aplicarlo en un entorno real,
correrlo contra una instancia de prueba.

Diseño (no es un simple "todo por `negocio_id`" — hay una tensión real que había que resolver):

- **`profesional` y `servicio`**: `SELECT` público (el cliente descubre negocios sin login,
  CU3/HU-07/HU-08); `INSERT`/`UPDATE` acotados a `negocio_id = current_setting('app.negocio_id')`.
- **`turno`**: nunca es de lectura pública, pero lo consultan tanto el **staff del negocio**
  (scope por `negocio_id`) como el **cliente dueño de la reserva** (scope por `cliente_id`) —
  y un cliente reserva en varios negocios, así que su JWT no lleva `negocio_id` (ver
  `backend/src/auth.ts`). La política es un `OR` entre ambos scopes, no solo `negocio_id`.
- El backend debe ejecutar `SET LOCAL app.negocio_id = '...'` y/o `SET LOCAL app.usuario_id =
  '...'` al inicio de cada transacción autenticada — sin eso, `current_setting(..., true)`
  devuelve `NULL` y las políticas de escritura deniegan por defecto (fail-closed). **Esto
  todavía no está conectado en el backend actual** (que usa `node:sqlite` para desarrollo, sin
  RLS) — es trabajo pendiente para cuando el backend apunte a Postgres.
- Pendiente para una próxima iteración: `disponibilidad`, `excepcion_disponibilidad`,
  `profesional_servicio`, `pago` y `notificacion` no tienen `negocio_id` propio (se llega por
  join a través de `profesional_id`/`turno_id`); necesitarían una política basada en subquery,
  no incluida en este slice.

## 6. Índices críticos

- `uq_turno_slot_activo` sobre `(profesional_id, inicio)` filtrado por estado activo —
  garantiza RN2 (no doble reserva), definido y justificado en
  `documento-arquitectura.md` §4.
- Índice sobre `(negocio_id)` en toda tabla de alcance de negocio, para que los filtros de
  aislamiento multi-tenant (RN9) sean eficientes.
- Índice sobre `(cliente_id, profesional_id)` en Turno, para las consultas de historial (CU2).
