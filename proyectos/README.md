# Proyectos

Cada proyecto de software gestionado por la AI Software Factory (interno o de cliente) vive en su propia subcarpeta aquí, creada cuando el CEO registra el proyecto (Fase 1 del ciclo de vida, ver [`docs/04-manual-operativo.md`](../docs/04-manual-operativo.md) §3).

Estructura sugerida por proyecto:

```
proyectos/<nombre-del-proyecto>/
  00-resumen.md          # objetivo, alcance, identificador único
  01-requisitos/         # entregables de Business Analyst
  02-backlog/            # entregables de Product Manager
  03-arquitectura/        # entregables de CTO IA + Arquitecto
  04-diseno/              # entregables de UX/UI
  05-codigo/               # o referencia al repo correspondiente
  06-qa/                   # reportes de QA
  07-seguridad/            # informes de Security
  08-despliegue/           # entregables de DevOps
  09-documentacion/        # entregables de Technical Writer
```

La memoria de decisiones de cada proyecto se registra en `memory/proyectos/<nombre-del-proyecto>/`, no aquí.
