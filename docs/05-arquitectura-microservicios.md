# Documento 005
AI Software Factory
Arquitectura de Microservicios v1.0
Autor: Matías SayagoFecha: Agosto 2026

## 1. Objetivo
Definir la arquitectura de microservicios de la plataforma AI Software Factory y las responsabilidades de cada servicio.

## 2. Principios
Servicios desacoplados, APIs bien definidas, despliegue independiente, observabilidad, resiliencia y escalabilidad horizontal.

## 3. Microservicios
• CEO Portal Service• Identity Service• Project Service• Orchestrator Service• Agent Management Service• Knowledge Service• Memory Service• Prompt Service• Task Service• Notification Service• Git Integration Service• CI/CD Service• Audit Service• Metrics Service

## 4. Responsabilidades
Cada microservicio posee su propia lógica, API, persistencia (cuando corresponda) y contratos de integración.

## 5. Flujo
CEO Portal → Orchestrator → Task Service → Agentes → Memory/Knowledge → Git → QA → CI/CD → Deployment.

## 6. Persistencia
PostgreSQL para datos transaccionales, Vector DB para conocimiento semántico, almacenamiento de documentos para artefactos y Git para código fuente.

## 7. Integraciones
OpenAI API, GitHub, servicios de correo, mensajería y proveedores cloud.

## 8. Seguridad
OAuth2/OIDC, JWT, RBAC, gestión de secretos, cifrado en tránsito y auditoría.

## 9. Observabilidad
Logs centralizados, métricas, trazas distribuidas y paneles de monitoreo.

## 10. Escalabilidad
Cada servicio puede escalar de forma independiente mediante contenedores y orquestación.

## 11. Roadmap
V1: Servicios esenciales. V2: Autoescalado. V3: Multiempresa. V4: Marketplace de agentes.

## Anexo A - Catálogo Inicial de APIs
Servicio
API Principal
Función
Project
/projects
Gestión de proyectos
Task
/tasks
Gestión de tareas
Agent
/agents
Administración de agentes
Knowledge
/knowledge
Base de conocimiento
Memory
/memory
Memoria organizacional
Git
/repositories
Repositorios y commits
Metrics
/metrics
KPIs y monitoreo
