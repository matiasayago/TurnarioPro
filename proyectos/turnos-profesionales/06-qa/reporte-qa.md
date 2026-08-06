# Reporte QA — Turnos Profesionales

**Proyecto:** TURNOS-2026-001 · **Rol:** QA · **Fase:** 5 — Calidad

## 0. Resumen ejecutivo

Se ejecutaron los 3 scripts de prueba existentes y se escribieron 6 scripts nuevos (~53
verificaciones de negocio adicionales) para cerrar los huecos de cobertura señalados: RN1, RN4,
camino sin seña (D2/RN10), rechazo real de RN8 dentro de ventana, validación de campos y
autorización cruzada. En total se ejecutaron 9 scripts / ~77 verificaciones automatizadas
contra el backend real corriendo en `http://localhost:3000`.

Se encontraron 4 defectos reales, 2 de severidad Alta, todos concentrados en el módulo de
Reservas (`src/routes/turnos.ts`): el endpoint `POST /turnos` no valida RN1 (disponibilidad
publicada) ni RN4 (asociación profesional↔servicio), la garantía anti-doble-reserva (RN2) no
cubre solapamientos con horarios de inicio distintos, y valores de fecha mal formados
(`inicio`/`nuevo_inicio`) producen un error 500 sin manejar en vez de una validación 400.

**Recomendación: el backend NO está listo para pasar a Security/DevOps todavía.** Los 2
defectos de severidad Alta (RN1 y RN4 no aplicadas) son violaciones directas de reglas de
negocio explícitas, explotables por cualquier cliente autenticado sin necesidad de vulnerar la
autenticación. El resto de la superficie probada (autenticación, aislamiento multi-tenant RN9,
historial privado D3/RN7, ventana de cancelación/reprogramación RN8, concurrencia RN2 en
igualdad exacta de horario, camino sin seña D2/RN10, autorización cruzada) funciona
correctamente.

## 1. Entorno de pruebas

Servidor compartido en `http://localhost:3000` (no se reinició ni se borró `dev.sqlite3`; se
detectó evidencia de otro agente — Security — trabajando en paralelo, ej. negocios
`Security-Test-Negocio-*`). Para dos verificaciones que requerían variables de entorno
específicas (`EXPIRACION_PAGO_MIN=0`, `VENTANA_CANCELACION_MIN=0`) que el servidor compartido no
tiene, se levantó una segunda instancia aislada y descartable del mismo código (puerto y SQLite
distintos, en scratchpad), solo para diagnóstico; se cerró al finalizar y se confirmó que el
servidor compartido no fue afectado en ningún momento. No se modificó ningún archivo del
backend ni de los 3 scripts existentes.

## 2. Casos ejecutados

| # | Script | Objetivo | Resultado |
|---|---|---|---|
| 1 | `scripts/smoke-test.mjs` (existente) | Golden path completo | **PASA** (13/13) |
| 2 | `scripts/test-concurrent-booking.mjs` (existente) | RN2 bajo concurrencia real | Falla contra el servidor compartido por fragilidad propia del script (ver O-1), no del backend. En instancia aislada limpia: **pasa completo**. |
| 3 | `scripts/test-reprogramacion-y-expiracion.mjs` (existente) | HU-13 + expiración automática | No ejecutable tal cual contra el servidor compartido (requiere env vars ausentes — O-2). En instancia aislada con env vars correctas: **pasa completo** (10/10). |
| 4 | `scripts/test-rn1-disponibilidad-y-solapamiento.mjs` (nuevo) | RN1 + solapamiento fino de RN2 | **FALLA** — 3/4 (DEF-01, DEF-02) |
| 5 | `scripts/test-rn4-servicio-no-asociado.mjs` (nuevo) | RN4 en descubrimiento y reserva | **FALLA** — 1/5 (DEF-03) |
| 6 | `scripts/test-turno-sin-sena.mjs` (nuevo) | Camino sin seña (D2/RN10/HU-09b) | **PASA** (6/6) |
| 7 | `scripts/test-rn8-ventana-cancelacion.mjs` (nuevo) | RN8 en ambas direcciones sin env vars especiales | **PASA** (4/4) |
| 8 | `scripts/test-validaciones-campos.mjs` (nuevo) | Validación de campos + auth mal formada | **FALLA** — 2/22 (DEF-04) |
| 9 | `scripts/test-autorizacion-cruzada.mjs` (nuevo) | Autorización cruzada + D3/RN7 | **PASA** (12/12) |

Verificación manual adicional (curl): excepciones de disponibilidad (RN5/HU-15) descuentan
correctamente los slots; un turno reservado en el rango de una excepción no se cancela
automáticamente, solo se informa `turnos_afectados` + aviso (consistente con el alcance MVP,
Notificaciones es mock).

## 3. Defectos encontrados

**DEF-01 — RN1 no se valida en `POST /turnos` (Alta).** No verifica que `inicio` caiga dentro
de un bloque de `disponibilidad` publicado. Repro: profesional con disponibilidad solo un día
de semana 09:00-11:00 → `POST /turnos` con `inicio` en otro día, o mismo día a las 15:00 →
esperado 4xx, obtenido `201 confirmado` en ambos casos. Script:
`test-rn1-disponibilidad-y-solapamiento.mjs`.

**DEF-02 — RN2 no cubre solapamientos con inicio distinto (Media-Alta).** El índice único solo
previene igualdad exacta de `inicio`. Repro: turno a las 09:00 (60 min) + turno a las 09:30
(mismo profesional) → ambos `201`, agenda solapada. Relacionado con DEF-01; recomendable un
chequeo explícito de rango, no solo de igualdad.

**DEF-03 — RN4 no se valida en `POST /turnos` (Alta).** Se puede reservar un servicio que el
profesional nunca asoció (`profesional_servicio` sin fila). La capa de descubrimiento (HU-08)
sí filtra bien; la reserva no. Además, al no existir la fila, `requiere_sena` se evalúa `false`
por defecto, eludiendo el control de seña. Script: `test-rn4-servicio-no-asociado.mjs`.

**DEF-04 — Fecha mal formada produce 500 (Media).** `new Date(inicio).toISOString()` sin
validar lanza `RangeError` no contemplado en el catch de la ruta → Express responde 500
genérico en `POST /turnos` y `PATCH /turnos/{id}/reprogramar`. El servidor no se cae (confirmado
con `/health`). Script: `test-validaciones-campos.mjs`.

## 4. Observaciones de entorno/herramental (no son defectos de producto)

**O-1:** `test-concurrent-booking.mjs` asume que `GET /negocios`[0] es el negocio recién creado
por `smoke-test.mjs` — falso en una DB compartida/persistente con negocios previos. Causa raíz
confirmada reproduciéndola en instancia aislada. No es defecto de backend.

**O-2:** `test-reprogramacion-y-expiracion.mjs` documenta en su encabezado que requiere
`EXPIRACION_PAGO_MIN=0`/`VENTANA_CANCELACION_MIN=0`; el servidor compartido corre con defaults
(120/15 min), por lo que falla ahí pero pasa limpio con las env vars correctas.

**O-3:** Node v26.6.0 (Windows) crashea con `process.exit()` tras varios `fetch()` abiertos
(assertion libuv `UV_HANDLE_CLOSING`, exit 127), reproducible con un script trivial ajeno a la
app. No afecta al servidor compartido; vale que DevOps lo tenga presente si CI depende del
exit code exacto.

## 5. Cobertura RN1-RN10 / CU1-CU5

RN1: **NO CUMPLE**. RN2: **PARCIAL** (cumple igualdad exacta + concurrencia real; no cumple
solapamiento fino). RN3: cumple. RN4: **PARCIAL** (descubrimiento sí, reserva no). RN5: cumple.
RN6: cumple con alcance MVP documentado. RN7/D3: cumple. RN8: cumple ambas direcciones. RN9:
cumple. RN10/D2: cumple ambos caminos. CU1: cumple (excepciones solo verificadas manualmente).
CU2: cumple. CU3: cumple. CU4: flujo principal funciona, controles de borde fallan
(DEF-01/02/03). CU5: cumple.

## 6. Recomendación final

No recomiendo pasar el backend a Security/DevOps en su estado actual. Sugiero a Backend
corregir en `POST /turnos`: (a) validación de `inicio` contra disponibilidad/excepciones/duración
(RN1), (b) chequeo de solapamiento por rango (RN2), (c) validación de asociación
`profesional_servicio` (RN4), y (d) validación temprana de fechas parseables (DEF-04).
Recomiendo re-ejecutar como mínimo `test-rn1-disponibilidad-y-solapamiento.mjs`,
`test-rn4-servicio-no-asociado.mjs` y `test-validaciones-campos.mjs` tras la corrección antes
de habilitar el paso a Security/DevOps.

**Archivos relevantes:**
`05-codigo/backend/scripts/test-rn1-disponibilidad-y-solapamiento.mjs`,
`05-codigo/backend/scripts/test-rn4-servicio-no-asociado.mjs`,
`05-codigo/backend/scripts/test-turno-sin-sena.mjs`,
`05-codigo/backend/scripts/test-rn8-ventana-cancelacion.mjs`,
`05-codigo/backend/scripts/test-validaciones-campos.mjs`,
`05-codigo/backend/scripts/test-autorizacion-cruzada.mjs`,
y el código revisado en `05-codigo/backend/src/routes/turnos.ts` (donde viven los 4 defectos).
