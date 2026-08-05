# Microservicios

Backend de la plataforma AI Software Factory, organizado como microservicios desacoplados. Especificación completa en [`docs/05-arquitectura-microservicios.md`](../docs/05-arquitectura-microservicios.md).

| Servicio | API principal | Función |
|---|---|---|
| `identity-service` | — | Autenticación, autorización (OAuth2/OIDC, JWT, RBAC) |
| `project-service` | `/projects` | Gestión de proyectos |
| `orchestrator-service` | — | Orquestador IA / Director General IA — planificación y coordinación de agentes |
| `agent-management-service` | `/agents` | Administración de agentes |
| `knowledge-service` | `/knowledge` | Base de conocimiento |
| `memory-service` | `/memory` | Memoria organizacional |
| `prompt-service` | — | Plantillas de prompts versionadas |
| `task-service` | `/tasks` | Gestión de tareas |
| `notification-service` | — | Notificaciones internas |
| `git-integration-service` | `/repositories` | Repositorios y commits |
| `cicd-service` | — | Integración/despliegue continuo |
| `audit-service` | — | Registro de auditoría |
| `metrics-service` | `/metrics` | KPIs y monitoreo |

## Principios
Servicios desacoplados, APIs bien definidas, despliegue independiente, observabilidad, resiliencia y escalabilidad horizontal. Cada microservicio posee su propia lógica, API y persistencia (cuando corresponda) — ver `docs/05-arquitectura-microservicios.md` §2-4.

Cada subcarpeta se implementa cuando el proyecto correspondiente del roadmap la requiera (ver roadmap en `docs/05-arquitectura-microservicios.md` §11).
