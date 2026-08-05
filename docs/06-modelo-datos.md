# Documento 006
AI Software Factory
Modelo de Datos v1.0
Autor: Matías SayagoFecha: Agosto 2026

## 1. Objetivo
Definir las entidades principales, sus relaciones y responsabilidades para soportar la operación de la AI Software Factory.

## 2. Entidades principales

## 3. Reglas de diseño
- Todas las entidades utilizan GUID como clave primaria.
- Auditoría completa de creación y modificación.
- Soft delete cuando corresponda.
- Control de versiones para documentos y prompts.
- Separación entre datos transaccionales y conocimiento semántico.

## 4. Diagrama conceptual
Organization ├── Users ├── Projects │     ├── Tasks │     ├── Documents │     ├── Repository │     ├── Knowledge │     └── Memory └── Agents       ├── Skills       ├── Executions       └── Notifications

## 5. Evolución
En versiones futuras se incorporarán entidades para Marketplace, Facturación, Clientes, Plugins, Modelos IA, Costos por token, Catálogo de Herramientas y Analítica avanzada.
Entidad
Descripción
Relaciones
Organization
Empresa propietaria de proyectos y usuarios.
1:N Users, Projects
User
Usuarios humanos (CEO, administradores y colaboradores).
N:1 Organization
Project
Proyecto de software administrado por la plataforma.
N:1 Organization, 1:N Tasks, Documents
Agent
Empleado IA con rol, skills y estado.
N:M Skills, 1:N Tasks
Role
Rol organizacional del agente o usuario.
1:N Agents
Skill
Capacidad técnica de un agente.
N:M Agents
Task
Unidad de trabajo asignada a un agente.
N:1 Project, N:1 Agent
Sprint
Agrupación de tareas por iteración.
1:N Tasks
KnowledgeItem
Elemento de la base de conocimiento.
N:1 Project (opcional)
MemoryEntry
Registro de memoria organizacional.
N:1 Project, N:1 Agent
Document
Artefacto funcional o técnico.
N:1 Project
Repository
Repositorio Git asociado al proyecto.
1:1 Project
PromptTemplate
Plantillas de prompts.
N:M Agents
Execution
Ejecución realizada por un agente.
N:1 Agent, N:1 Task
AuditLog
Registro de auditoría.
N:1 User/Agent
Notification
Notificaciones internas.
N:1 User/Agent
