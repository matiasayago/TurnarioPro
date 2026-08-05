# Lineamientos Técnicos — Turnos Profesionales

**Rol:** CTO IA
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md`, `02-backlog/backlog.md`

## 1. Stack aprobado

| Capa | Tecnología | Motivo |
|---|---|---|
| Mobile (cliente y profesional) | **Flutter** | Una sola base de código para iOS/Android; catálogo de la empresa lo lista como stack de Mobile (`docs/03-catalogo-agentes.md`). Cliente y Profesional son dos *modos* de la misma app, no dos apps separadas — comparten componentes de calendario/reserva. |
| Backend | **Node.js (NestJS) o .NET** — a confirmar con Backend según disponibilidad del equipo; ambos aprobados por catálogo de la empresa | Cualquiera de los dos soporta bien el patrón modular monolito recomendado en §2. |
| Base de datos | **PostgreSQL** | Estándar de la empresa (`docs/06-modelo-datos.md`); soporta Row Level Security, útil para el aislamiento multi-tenant (§3). |
| Autenticación | **OAuth2/OIDC + JWT** | Estándar de seguridad de la empresa (`docs/05-arquitectura-microservicios.md` §8). |
| Notificaciones push | **Firebase Cloud Messaging (FCM)** | Integra nativamente con Flutter en ambas plataformas. |
| Pagos/seña | **Mercado Pago (Checkout API)** | Procesador con soporte fuerte en la región; permite pagos "por comercio" (necesario para D2 — seña configurable por profesional/negocio). |
| CI/CD | GitHub Actions + Docker | Estándar de la empresa (`docs/05-arquitectura-microservicios.md`). |

## 2. Patrón de arquitectura: modular monolito (no microservicios completos en V1)

La empresa usa microservicios para su propia plataforma interna (Orquestador, Knowledge
Service, etc. — ver `docs/05-arquitectura-microservicios.md`), pero **ese catálogo es para
la AI Software Factory, no para cada producto de cliente**. Para este proyecto se recomienda:

- **V1 (MVP):** un backend modular monolito con límites de módulo claros (Identidad, Negocios,
  Catálogo de servicios, Disponibilidad, Reservas, Pagos, Notificaciones). Reduce complejidad
  operativa y acelera el MVP sin sacrificar la posibilidad de dividir en servicios después.
- **V2+:** si el volumen lo justifica, extraer **Reservas** y **Pagos** como servicios
  independientes primero (son los módulos con mayor carga y mayor necesidad de escalar
  independientemente).

Esta decisión debe validarla el Arquitecto en el documento de arquitectura (§ de este
proyecto en `documento-arquitectura.md`) antes de pasar a desarrollo.

## 3. Multi-tenancy (D1)

- Estrategia: **base de datos compartida, esquema compartido**, con `negocio_id` como columna
  obligatoria en toda tabla de alcance de negocio (Profesional, Servicio, Disponibilidad,
  Turno, historial).
- Reforzar el aislamiento con **Row Level Security de PostgreSQL** por `negocio_id` como
  defensa en profundidad, además del filtro a nivel de aplicación (RN9).
- El JWT de Profesional/Administrador lleva el claim `negocio_id`; el Backend nunca confía en
  un `negocio_id` recibido del cliente sin validarlo contra el JWT.

## 4. Librerías y estándares

- Todo el código sigue las convenciones que se registren en `knowledge-base/estandares/` a
  medida que se definan (primera vez que este proyecto genera un estándar reusable, debe
  quedar ahí, no solo en este documento).
- Autorizado usar librerías de calendario/scheduling existentes para el cálculo de slots en
  vez de reimplementar lógica de recurrencia desde cero (a elección de Backend, validado por
  Arquitecto).

## 5. Riesgos técnicos identificados

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Doble reserva del mismo slot bajo concurrencia | Alto — rompe confianza del negocio | Ver estrategia de concurrencia en `documento-arquitectura.md` §4 |
| Fuga de datos entre negocios (multi-tenant) | Alto — issue de seguridad/privacidad | RLS + validación de `negocio_id` por JWT, revisado por Security antes de despliegue |
| Pago de seña abandonado dejando turno "colgado" | Medio | Expiración automática del estado "pendiente de pago" (ver documento de arquitectura) |
