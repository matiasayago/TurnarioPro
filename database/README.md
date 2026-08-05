# Database

Modelo de datos de la plataforma. Ver [`docs/06-modelo-datos.md`](../docs/06-modelo-datos.md) para entidades y relaciones.

- `modelo/` — diagramas y definición conceptual del modelo de datos.
- `migrations/` — migraciones SQL versionadas (PostgreSQL).
- `scripts/` — scripts auxiliares (seed data, mantenimiento, optimización).

## Reglas de diseño (obligatorias, ver `docs/06-modelo-datos.md` §3)
- Todas las entidades usan GUID como clave primaria.
- Auditoría completa de creación y modificación.
- Soft delete cuando corresponda.
- Control de versiones para documentos y prompts.
- Separación entre datos transaccionales (PostgreSQL) y conocimiento semántico (Vector DB).

Propiedad del agente **DBA**.
