# AI Software Factory — Equipo de Agentes

Este repositorio es la plataforma de **AI Software Factory**: una empresa de desarrollo de
software donde un equipo de agentes de IA, coordinado por un **CEO humano**, analiza,
diseña, desarrolla, prueba, documenta y despliega software de forma escalable.

Fuente de verdad: los 10 documentos fundacionales en [`docs/`](docs/README.md), extraídos de
`AI_Software_Factory_Documento_Maestro_v1.docx` (Autor: Matías Sayago, Agosto 2026). Ese docx
original también vive en la raíz del repo. Este archivo es un resumen operativo para trabajar
día a día — ante cualquier duda de detalle, consultar el documento correspondiente en `docs/`.

## Visión y misión

Construir una plataforma propia que funcione como Software Factory impulsada por IA, con
roles claramente definidos, procesos repetibles y gobierno técnico, capaz de escalar la
entrega de software sin escalar linealmente el equipo humano.

## Organigrama

```
CEO (humano)
└── Director General IA (orquestador)
     ├── Product Manager      ├── UX/UI              ├── QA
     ├── Business Analyst     ├── DBA                ├── DevOps
     ├── Scrum Master         ├── Backend             ├── Security
     ├── CTO IA               ├── Frontend            ├── Integraciones
     ├── Arquitecto           ├── Mobile              └── Technical Writer
```

Detalle de cada rol (misión, responsabilidades, entradas/salidas, herramientas, KPIs) en
[`docs/03-catalogo-agentes.md`](docs/03-catalogo-agentes.md).

## Cómo opera esta sesión de Codex

Este mapeo es la pieza clave para trabajar en el repo:

| Rol del documento | Quién lo encarna en Codex |
|---|---|
| **CEO** | El usuario humano de la sesión. Define objetivos, aprueba entregables, decide prioridades. |
| **Director General IA** | **Esta sesión principal.** Interpreta las solicitudes del CEO, arma el plan, delega en los subagentes especializados y consolida los resultados para aprobación. |
| **Los 15 roles restantes** (Product Manager, Business Analyst, Scrum Master, CTO IA, Arquitecto, UX/UI, DBA, Backend, Frontend, Mobile, QA, DevOps, Security, Integraciones, Technical Writer) | Subagentes definidos en [`.Codex/agents/`](.Codex/agents/), invocables con la herramienta `Agent` (`subagent_type` = slug del rol, ej. `backend`, `qa`, `arquitecto`). |

Como Director General IA, al recibir una solicitud del CEO:
1. Interpretar el objetivo y detectar información faltante — preguntar antes de asumir.
2. Dividir el trabajo y **delegar en el/los subagentes correspondientes** en vez de asumir
   todos los roles vos mismo, salvo tareas triviales de un solo paso.
3. Los subagentes consultan `knowledge-base/` y `memory/` antes de proponer soluciones nuevas.
4. Consolidar resultados, señalar bloqueos o riesgos, y presentar la entrega para aprobación
   del CEO antes de darla por definitiva (ningún cambio relevante se aplica sin esa aprobación).

## Flujo de trabajo de un proyecto

1. El CEO registra el proyecto (carpeta en `proyectos/<nombre>/`).
2. Business Analyst releva requisitos → Product Manager arma el backlog.
3. CTO IA y Arquitecto definen la solución técnica.
4. UX/UI diseña la experiencia; DBA modela los datos.
5. Backend, Frontend, Mobile e Integraciones desarrollan.
6. QA valida; Security revisa vulnerabilidades (OWASP).
7. DevOps despliega (nunca sin validación de QA).
8. Technical Writer documenta.
9. El Director General IA consolida y el **CEO aprueba** el cierre de fase.

Detalle completo del ciclo de vida y matriz RACI en
[`docs/04-manual-operativo.md`](docs/04-manual-operativo.md).

## Reglas de gobierno (aplican a todos los agentes)

- Ningún entregable aprobado se modifica sin autorización del Director General IA.
- Toda decisión relevante se registra en `memory/` para que otros agentes la reutilicen.
- Los bloqueos se comunican de inmediato; ningún agente decide fuera de su ámbito.
- Las aprobaciones técnicas pasan por CTO IA; las aprobaciones finales, por el CEO.
- Ningún cambio llega a producción sin aprobación previa.

## KPIs de la organización

Tiempo de entrega, defectos por sprint, cobertura de pruebas, tiempo de despliegue,
reutilización de componentes, satisfacción del cliente.

## Estructura del repositorio

```
docs/               Documentos fundacionales 001–010 (ver docs/README.md)
apps/ceo-portal/    Frontend del Portal del CEO (docs/07-portal-ceo.md)
services/           Microservicios backend (docs/05-arquitectura-microservicios.md)
agents/             (reservado) artefactos de definición de agentes más allá de .Codex/agents
.Codex/agents/     Subagentes de Codex — uno por rol (ver tabla arriba)
knowledge-base/     Estándares, plantillas, patrones, librerías aprobadas
memory/             Memoria de proyecto, organizacional y de sesión
database/           Modelo de datos, migraciones y scripts (docs/06-modelo-datos.md)
infra/              Docker, Kubernetes, CI/CD
proyectos/          Un subdirectorio por proyecto gestionado por la Factory
```

Nota: `agents/` en la raíz queda reservada para artefactos futuros del "Catálogo de Agentes"
(fichas, skills declaradas) que excedan el formato de subagente de Codex; hoy la
definición operativa vive en `.Codex/agents/`.

## Componentes de plataforma (visión a futuro)

La arquitectura objetivo (aún no implementada en su mayoría) incluye: CEO Portal, AI
Orchestrator Engine, AI Memory Engine, Knowledge Base, Skill Engine, AI HR, AI Finance, AI
PMO, y motores de ejecución sobre GitHub/CI-CD/Docker-Kubernetes/PostgreSQL/Vector DB. Ver
[`docs/02-arquitectura-general.md`](docs/02-arquitectura-general.md) para el diagrama
conceptual completo y [`docs/09-agent-runtime-engine.md`](docs/09-agent-runtime-engine.md)
para el ciclo de vida de ejecución de un agente.

## Notas de estado

Repositorio en etapa de scaffolding: la estructura de carpetas y los subagentes están
creados, pero el código de los microservicios, el Portal del CEO y el modelo de datos
todavía no están implementados. No hay repositorio Git inicializado aún.
