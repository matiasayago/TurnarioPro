# Cobro de señas con Mercado Pago (HU-29/RN10/D2) — credenciales y webhook

**Rol:** Backend
**Fase:** 4 — Desarrollo. `POST /turnos/:id/pago` y `POST /webhooks/mercadopago` ya están
implementados (`../05-codigo/backend/src/routes/turnos.ts` y
`../05-codigo/backend/src/routes/webhooks.ts`) y funcionan sin credenciales reales (§4) —
este documento resuelve el paso que falta para poder probarlos de punta a punta: de dónde salen
`MP_ACCESS_TOKEN`/`MP_WEBHOOK_SECRET`.
**Entradas:** `../03-arquitectura/lineamientos-tecnicos.md` §1 (decisión ya tomada: Mercado Pago,
Checkout API/Pro); `../03-arquitectura/documento-arquitectura.md` §1/§2/§5 (contrato de los 2
endpoints y "webhook validado por firma, no solo por IP"); `../03-arquitectura/plan-produccion.md`
ítem B7 (KYC de Mercado Pago, ya señalado como bloqueante 100% del CEO); `./google-oauth.md` §0
(mismo precedente de qué puede y no puede hacer un agente de IA acá).
**Salidas:** este documento; `../05-codigo/backend/.env.example` y `../05-codigo/backend/render.yaml`
(variables nuevas documentadas/declaradas, sin valor real).
**No incluye credenciales reales de Mercado Pago** — ver §0.

## 0. Qué resuelve este documento y qué NO

Mismo criterio ya establecido en `./google-oauth.md` §0 para Google, y ya anticipado en
`../03-arquitectura/plan-produccion.md` (ítem B7): **ningún agente de IA puede crear la cuenta de
Mercado Pago ni cargar sus credenciales** — a diferencia de Google (gratis, cualquier cuenta
alcanza), Mercado Pago exige verificación de identidad/cuenta bancaria (KYC, CUIT) de una persona
real. Este documento es el instructivo para que el CEO lo haga (§2) más la infraestructura de
configuración para recibir el resultado sin que ningún valor real quede commiteado (§3).

**No implementa código** — `POST /turnos/:id/pago` (crea la intención de pago) y
`POST /webhooks/mercadopago` (confirma el pago y, si corresponde, el turno) ya están
implementados, sin esperar a que existan credenciales reales — ver §5 para el criterio de gateo
que lo permite. El cliente real de Mercado Pago detrás de `pagoProvider`
(`../05-codigo/backend/src/integraciones/pagos.ts`) lo implementa el rol Integraciones, en
paralelo — no es parte de este documento.

**Alcance de este ciclo: credenciales de PRUEBA (sandbox), no de producción.** El objetivo es
poder verificar el flujo completo (crear intención → pagar con una tarjeta de prueba → recibir el
webhook → turno confirmado) antes de manejar dinero real. Pasar a credenciales de producción es un
paso deliberadamente posterior (§2, paso 4) — mismo criterio que `./google-oauth.md` §2 Paso 5 usa
para no crear todavía el Client ID de iOS.

## 1. Enfoque técnico (ya decidido, no se reabre acá)

`../03-arquitectura/lineamientos-tecnicos.md` §1 ya fijó **Mercado Pago (Checkout Pro/API)** como
procesador ("soporte fuerte en la región... permite pagos 'por comercio', necesario para D2 — seña
configurable por profesional/negocio"). El contrato entre este backend y `pagoProvider`
(`crearIntencion`, `validarWebhook`, `obtenerPagoMercadoPago`) ya está congelado e implementado en
ambos extremos (Backend consume, Integraciones provee) — ver
`../05-codigo/backend/src/integraciones/pagos.ts` para el detalle real de la integración (qué
API de Mercado Pago usa cada función, cómo arma la validación de firma del header `x-signature`).
Este documento no repite eso — solo resuelve de dónde salen las 2 variables de entorno que ese
archivo necesita.

## 2. Qué tiene que hacer el CEO en el dashboard de Mercado Pago (instructivo paso a paso)

Nombres de menú vigentes al momento de escribir este documento — igual que
`./google-oauth.md` §2, si algún nombre no coincide exactamente con lo que se ve en pantalla,
es el mismo tipo de limitación ya documentada ahí (este entorno no tiene acceso a un navegador
para confirmar la UI en vivo contra una cuenta real). Tiempo estimado para los pasos 1 a 3: 15–20
minutos, sin esperar ningún trámite de KYC (eso solo hace falta para el paso 4, producción).

### Paso 1 — Cuenta de Mercado Pago

Si el negocio/plataforma todavía no tiene una cuenta de Mercado Pago, crearla en
[mercadopago.com.ar](https://www.mercadopago.com.ar/) (o el dominio del país correspondiente) con
los datos reales de quien va a cobrar. No hace falta completar el KYC completo (cuenta
bancaria/CUIT verificado) para los pasos 2–3 de abajo — las credenciales de PRUEBA están
disponibles apenas existe la cuenta; el KYC completo recién es un prerrequisito real para el paso 4
(producción) y para poder retirar el dinero cobrado.

### Paso 2 — Crear una aplicación y obtener credenciales de PRUEBA

1. Entrar a **"Tus integraciones"** (el panel de desarrolladores, dentro de la cuenta de Mercado
   Pago — buscar "Developers"/"Tus integraciones" si el menú cambió de nombre).
2. **"Crear aplicación"** — nombre sugerido: "Turnario Pro" o similar (nombre interno, no lo ve
   ningún cliente final). Al elegir el modelo de integración, seleccionar el que corresponde a
   **Checkout Pro / Checkout API** (pagos únicos con `external_reference`, no suscripciones — HU-29
   "Turnario Pro" es un nombre de producto de este proyecto, no tiene relación con las
   suscripciones nativas de Mercado Pago).
3. Dentro de la aplicación, ir a **"Credenciales de prueba"** (Test credentials) — ahí aparecen un
   **Public Key** (no lo usa este backend, es para el lado cliente/checkout) y un **Access Token**
   con prefijo `TEST-...`. **Ese Access Token de prueba es el valor de `MP_ACCESS_TOKEN`** para
   este paso del ciclo (§3) — nunca el de producción todavía (§0).
4. **Usuarios de prueba** (Test users): para poder completar un pago de punta a punta sin dinero
   real, Mercado Pago pide operar con 2 cuentas de prueba — un "vendedor" de prueba (cuyo Access
   Token de prueba es el que se carga acá) y un "comprador" de prueba (con el que se inicia sesión
   en el checkout para pagar). Se crean desde la misma sección "Tus integraciones" →
   "Usuarios de prueba" ("Test users"), o vía la API que documenta Mercado Pago — cualquiera de los
   2 caminos alcanza. Mercado Pago también documenta tarjetas de prueba con resultado determinístico
   (aprobado/rechazado/pendiente) para simular cada caso sin usar una tarjeta real.

### Paso 3 — Configurar la URL de notificaciones (webhook) y obtener `MP_WEBHOOK_SECRET`

Dentro de la misma aplicación ("Tus integraciones" → la app creada en el Paso 2), buscar la
sección **"Webhooks"** (o "Notificaciones"):

1. Configurar la **URL de notificaciones** a nivel de la aplicación:
   `https://<host-del-backend-en-Render>/webhooks/mercadopago` (ej.
   `https://turnos-profesionales-backend.onrender.com/webhooks/mercadopago` — confirmar el host
   real contra `./README.md`/`memory/proyectos/turnos-profesionales/decisiones.md` al momento de
   configurarlo). Para probar en desarrollo local (`localhost` no es alcanzable desde los
   servidores de Mercado Pago) hace falta exponerlo con un túnel (ej. `ngrok`) y usar esa URL
   pública temporal en su lugar — no se documenta un paso a paso de esa herramienta acá, es
   standard de cualquier webhook local.
2. Esta pantalla también genera/muestra una **"Firma secreta"** (Secret signature) — **ese valor es
   `MP_WEBHOOK_SECRET`** (§3), usado por `pagoProvider.validarWebhook`
   (`../05-codigo/backend/src/integraciones/pagos.ts`) para validar el header `x-signature` de cada
   notificación entrante.
3. **Esta configuración a nivel de APLICACIÓN es obligatoria, no opcional** — confirmado por
   Integraciones (`../05-codigo/backend/src/integraciones/pagos.ts`, 2026-08-17, verificado contra
   el código fuente del SDK oficial de Mercado Pago): `crearIntencion` (la función que arma cada
   preferencia de pago) **no manda ningún `notification_url` propio por preferencia** — a
   propósito, porque una URL puesta ahí tendría prioridad sobre la de la aplicación. Como
   consecuencia, la URL que se configure en este Paso 3 es la ÚNICA que Mercado Pago va a usar para
   avisarle a este backend — si este paso queda sin hacer, `POST /webhooks/mercadopago` nunca va a
   recibir ninguna notificación y todo turno con seña va a quedar `pendiente_de_pago` para siempre
   (hasta expirar, ver `src/jobs/expirarPagosPendientes.ts`), sin importar que el cliente sí haya
   pagado.
4. Esta misma pantalla suele tener un botón para **simular una notificación de prueba** contra la
   URL configurada — útil para confirmar que el backend responde `200` antes de probar un pago real
   de punta a punta.

### Paso 4 — Credenciales de producción: no crear/cargar todavía

Mismo criterio que `./google-oauth.md` §2 Paso 5 (Client ID iOS): este ciclo pide cerrar con una
intención de pago de PRUEBA funcionando de punta a punta (§0), no lanzar cobros reales. Cuando ese
resultado esté validado y el CEO haya completado el KYC de la cuenta (ítem B7 de
`../03-arquitectura/plan-produccion.md`, con su propio lead time externo fuera del control de la
Factory), un ciclo posterior repite el Paso 2 con **"Credenciales de producción"** (prefijo
`APP_USR-...`) y actualiza `MP_ACCESS_TOKEN` en el dashboard de Render (§4) — sin volver a tocar
código.

## 3. Variables de entorno

| Variable | ¿Hace falta? | Valor | Notas |
|---|---|---|---|
| `MP_ACCESS_TOKEN` | Sí (nueva) | Access Token de PRUEBA (`TEST-...`, Paso 2) — luego de producción (`APP_USR-...`, Paso 4) | Usado por `crearIntencion`/`obtenerPagoMercadoPago` (`../05-codigo/backend/src/integraciones/pagos.ts`). SÍ es secreto — mismo nivel de cuidado que `JWT_SECRET`, a diferencia de `GOOGLE_CLIENT_ID`. |
| `MP_WEBHOOK_SECRET` | Sí (nueva) | Firma secreta de la sección Webhooks (Paso 3) | Usado por `pagoProvider.validarWebhook` para validar el header `x-signature` de `POST /webhooks/mercadopago`. También secreto. |

`../05-codigo/backend/.env.example` ya quedó actualizado con ambas variables, documentadas con el
mismo nivel de detalle que el resto de ese archivo.

## 4. Gestión del secreto por entorno (resumen — mismo mecanismo que `./google-oauth.md` §4)

- **Local (`.env`):** sin cambios de mecanismo — gitignorado, cada desarrollador completa su
  propio valor de prueba una vez que exista.
- **CI:** no se configuran en el workflow de CI (mismo criterio que `GOOGLE_CLIENT_ID`, ver
  `./google-oauth.md` §4.2) — sin credenciales reales disponibles ahí, pegarle a
  `POST /turnos/:id/pago`/`POST /webhooks/mercadopago` da `503` de forma determinística, que es
  justamente el comportamiento que confirma el criterio de gateo (§5) sin necesitar ningún mock de
  Mercado Pago.
- **Render (producción/staging):** `../05-codigo/backend/render.yaml` ya declara `MP_ACCESS_TOKEN`
  y `MP_WEBHOOK_SECRET` con `sync: false` (mismo mecanismo que `GOOGLE_CLIENT_ID`) — pendientes de
  cargar a mano en el dashboard del servicio una vez que el CEO tenga los valores del Paso 2/3.

## 5. Criterio de gateo mientras no existan credenciales — ya implementado

A diferencia de `./google-oauth.md` (que dejaba esto como recomendación para cuando Backend
implementara el endpoint), acá ya está resuelto: `POST /turnos/:id/pago`
(`../05-codigo/backend/src/routes/turnos.ts`) y `POST /webhooks/mercadopago`
(`../05-codigo/backend/src/routes/webhooks.ts`) atrapan el error que tira `pagoProvider`/
`obtenerPagoMercadoPago` cuando `MP_ACCESS_TOKEN` no está configurado (nunca falla al arrancar el
proceso, solo al invocarse — mismo criterio que `GOOGLE_CLIENT_ID` en `src/routes/auth.ts`) y
responden **503** con un mensaje claro. El resto del backend (incluida la reserva de un turno CON
seña, que queda en `pendiente_de_pago`) sigue funcionando con normalidad sin esto.

## 6. Checklist para el CEO (resumen ejecutivo)

- [ ] Tener (o crear) una cuenta de Mercado Pago para la plataforma (§2, Paso 1) — el KYC completo
      no bloquea los pasos siguientes.
- [ ] Crear una aplicación en "Tus integraciones" y copiar el **Access Token de PRUEBA**
      (`TEST-...`, §2 Paso 2) — ese es `MP_ACCESS_TOKEN` por ahora.
- [ ] Crear al menos un usuario de prueba comprador (§2, Paso 2, punto 4) para poder simular un
      pago completo.
- [ ] Configurar la URL de webhook (`https://<host>/webhooks/mercadopago`) y copiar la **Firma
      secreta** (§2, Paso 3) — ese es `MP_WEBHOOK_SECRET`.
- [ ] Entregar ambos valores a Backend/DevOps para cargarlos en el dashboard de Render (§4).
- [ ] Validar con Backend/QA una intención de pago de prueba de punta a punta antes de considerar
      este ítem cerrado (§0).
- [ ] Recién después: iniciar el trámite de KYC/cuenta bancaria para credenciales de producción
      (§2, Paso 4) — ya señalado como pendiente 100% del CEO en
      `../03-arquitectura/plan-produccion.md`, ítem B7.
