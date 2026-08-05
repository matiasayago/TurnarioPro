# Infra

Infraestructura y despliegue de la plataforma. Propiedad del agente **DevOps**.

- `docker/` — Dockerfiles e imágenes de cada servicio/app.
- `kubernetes/` — manifiestos de despliegue y orquestación.
- `ci-cd/` — pipelines de integración y despliegue continuo.

Ningún cambio llega a producción sin aprobación previa (principio operativo, ver [`docs/04-manual-operativo.md`](../docs/04-manual-operativo.md) §2), y ningún despliegue ocurre sin validación previa de QA.
