# Backend — Turnos Profesionales

Modular monolito (ver `../../03-arquitectura/documento-arquitectura.md`). Node.js + TypeScript
+ Express. Persistencia de desarrollo con **`node:sqlite`** (built-in de Node ≥22.5, sin
compilación nativa); producción apunta a **PostgreSQL** (ver
`../database/migrations/001_init.sql`, DBA).

> `better-sqlite3` (elección original) requiere compilar un addon nativo vía node-gyp, y este
> entorno no tiene Visual Studio Build Tools instalado. Se optó por `node:sqlite` para no
> bloquear el desarrollo — es un cambio de driver, no de diseño; el esquema y la lógica de
> negocio son los mismos que se documentaron para Postgres.

## Cómo correr

```bash
npm install
npm run dev        # http://localhost:3000, recrea dev.sqlite3 desde las migraciones
```

## Pruebas manuales (smoke tests)

Con el servidor corriendo:

```bash
npm run test:smoke          # flujo completo: alta de negocio -> servicio -> profesional ->
                             # disponibilidad -> slots -> reserva -> conflicto secuencial ->
                             # clientes/historial -> cancelación
npm run test:concurrencia   # dispara 2 reservas SIMULTÁNEAS al mismo slot (Promise.all) y
                             # verifica que solo una tenga éxito (RN2) — correr después de
                             # test:smoke, sobre la misma DB
node scripts/test-reprogramacion-y-expiracion.mjs   # HU-13 + expiración automática — correr
                             # el server con EXPIRACION_PAGO_MIN=0 VENTANA_CANCELACION_MIN=0
```

Los tres scripts corrieron exitosamente durante el desarrollo, incluida la prueba de
concurrencia real (no solo secuencial) y la reprogramación con conflicto de slot.

Preview interactiva en el navegador: con el servidor corriendo, abrir `http://localhost:3000`
(sirve `web-preview/`, solo fuera de `NODE_ENV=production`) — permite sembrar datos de
ejemplo (`POST /dev/seed`), loguearse, navegar el flujo de Cliente/Profesional y disparar la
prueba de concurrencia desde la UI, sin instalar Flutter.

## Implementado en este slice

- Auth: registro de negocio+administrador, registro de cliente, login (JWT con
  `rol`/`negocio_id`/`profesional_id`).
- Negocios: alta, listado público, alta de servicios y profesionales (RN9 — scoping por
  `negocio_id` del JWT, nunca por parámetro).
- Profesionales: asociar servicio con seña configurable (D2/RN10), disponibilidad,
  excepciones (RN5/RN6), cálculo de slots con "próximo disponible" (D5), listado de clientes.
- Turnos: reserva con garantía anti-doble-reserva a nivel de base de datos (RN2, índice único
  parcial), cancelación con ventana mínima (RN8/A3), **reprogramación (HU-13)** reutilizando la
  misma garantía anti-doble-reserva y conservando el estado de pago, listado de turnos propios.
- Clientes: historial de visitas filtrado por profesional (D3/RN7).
- Pagos y Notificaciones: **interfaces + Mock** (`src/integraciones/`) — no se creó ninguna
  cuenta de Mercado Pago ni de Firebase (fuera del alcance permitido de un agente de IA);
  Integraciones debe reemplazar el Mock por el proveedor real cuando el CEO provea credenciales.
- **Expiración automática** de turnos `pendiente_de_pago` (`src/jobs/expirarPagosPendientes.ts`,
  cada 60s, ventana configurable con `EXPIRACION_PAGO_MIN`) — libera el slot si Mercado Pago no
  confirma el pago a tiempo.
- Endpoints `/dev/*` (seed + forzar expiración) solo activos fuera de `NODE_ENV=production`.

## Row Level Security (Postgres)

Implementada en `../database/migrations/001_init.sql` (ver
`../../03-arquitectura/modelo-datos.md` §5) — **no verificable en este entorno** (sin
psql/Docker). El backend actual (`node:sqlite`) no necesita `SET LOCAL app.*` porque el
aislamiento multi-tenant ya se aplica en cada route handler; cuando el backend pase a
Postgres, hay que agregar `SET LOCAL app.negocio_id` / `app.usuario_id` al inicio de cada
transacción autenticada para que las políticas RLS tengan efecto.

## Pendiente (fuera de este slice)

- Frontend/Mobile — ver `../mobile/` (Flutter) y las pantallas de `04-diseno/mapa-pantallas.md`.
- Revisión de Security y despliegue de DevOps (fases 5 y 6 del proyecto).
- Conectar `SET LOCAL app.*` cuando el backend migre de `node:sqlite` a Postgres real.
