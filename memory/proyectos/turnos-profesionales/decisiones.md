# Memoria de decisiones — Turnos Profesionales (TURNOS-2026-001)

## Decisiones de negocio (CEO, Fase 2)
- D1: plataforma multi-negocio (multi-tenant), no un solo consultorio.
- D2: seña/pago al reservar es configurable por profesional+servicio, no una regla global.
- D3: historial de visitas del cliente es privado por profesional, no compartido en el negocio.
- D4: notificaciones (confirmación + recordatorio) están en el alcance del MVP.
- D5: sin lista de espera — se muestra el próximo horario disponible.

## Decisiones técnicas (CTO IA/Arquitecto/DBA, Fase 3)
- Stack: Flutter (mobile único, dos modos Cliente/Profesional), backend modular monolito
  (Node/NestJS o .NET), PostgreSQL, JWT+OAuth2, FCM para push, Mercado Pago para seña.
- Multi-tenancy: base de datos compartida + `negocio_id` en toda tabla de alcance de negocio +
  Row Level Security como defensa en profundidad.
- No-doble-reserva (RN2): índice único parcial `(profesional_id, inicio)` filtrado por estado
  activo — la garantía vive en la base de datos, no solo en lógica de aplicación.
- Turno "pendiente_de_pago" expira a los 15 min si Mercado Pago no confirma el pago.
- Microservicios completos (catálogo de `docs/05-arquitectura-microservicios.md`) son para la
  plataforma interna de la AI Software Factory, no un requisito para productos de cliente —
  se evaluará dividir el monolito (empezando por Reservas y Pagos) si el volumen lo justifica.

## Decisiones de Fase 4 (Backend/Mobile)
- `better-sqlite3` requiere compilar un addon nativo (node-gyp + Visual Studio Build Tools);
  este entorno de desarrollo no los tiene. Se reemplazó por **`node:sqlite`** (built-in de
  Node ≥22.5) solo para la base de datos de desarrollo/pruebas — el diseño y el DDL de
  producción (PostgreSQL, ver `03-arquitectura/modelo-datos.md`) no cambiaron.
- Backend probado end-to-end con scripts de humo (`05-codigo/backend/scripts/`), incluida una
  prueba de concurrencia REAL (`Promise.all` con 2 requests simultáneas) que confirmó la
  garantía anti-doble-reserva (RN2) funcionando, no solo en teoría.
- Mobile (Flutter) se escribió sin poder compilar/correr — este entorno no tiene el SDK de
  Flutter ni Dart standalone instalado. Requiere verificación (`flutter analyze` + `flutter
  run`) antes de considerarse funcional. Se encontró y corrigió en revisión manual un bug de
  casteo de `Future` en el cliente HTTP (ver `05-codigo/mobile/README.md`).

## Decisiones de cierre de Fase 4 (pendientes implementados)
- HU-13 (reprogramación) implementada y probada: reutiliza el mismo índice único que el alta
  (el turno viejo pasa a estado `reprogramado`, sale del índice, y el nuevo INSERT reusa la
  garantía anti-doble-reserva sin código nuevo). El pago (si existe) se retarget al turno nuevo
  — no se vuelve a cobrar la seña en una reprogramación.
- Job de expiración de `pendiente_de_pago` implementado como `setInterval` en el proceso del
  backend (cada 60s, configurable) + endpoint `/dev/forzar-expiracion` para poder probarlo sin
  esperar los 15 min reales. Probado end-to-end.
- RLS de Postgres implementado en el DDL con un diseño no trivial: `profesional`/`servicio`
  necesitan lectura pública (catálogo) pero escritura acotada a `negocio_id`; `turno` necesita
  un OR entre scope de negocio (staff) y scope de cliente (`cliente_id`), porque un cliente
  reserva en múltiples negocios y su JWT no lleva `negocio_id`. **No verificado contra Postgres
  real** — este entorno no tiene psql/Docker. Falta conectar `SET LOCAL app.negocio_id` /
  `app.usuario_id` en el backend cuando deje de usar `node:sqlite` y pase a Postgres.

## Reutilizable para futuros proyectos de la Factory
- El patrón "modular monolito primero, extraer servicios cuando el volumen lo justifique" es
  candidato a plantilla en `knowledge-base/patrones-arquitectonicos/`.
- El patrón de índice único parcial para evitar doble-reserva bajo concurrencia es reutilizable
  en cualquier proyecto con lógica de scheduling/booking — candidato a
  `knowledge-base/patrones-arquitectonicos/`.
- `node:sqlite` como reemplazo de `better-sqlite3` para desarrollo local en entornos Windows
  sin Build Tools es reutilizable en cualquier proyecto backend Node — candidato a
  `knowledge-base/estandares/`.
- Nunca asumir Flutter/Dart/Docker/psql instalados en el entorno de ejecución de un agente —
  verificar con `--version` antes de planificar el alcance de un slice de desarrollo.
