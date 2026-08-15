# Backlog Priorizado — Turnos Profesionales

**Proyecto:** TURNOS-2026-001
**Rol:** Product Manager
**Fase:** 2 — Descubrimiento
**Entradas:** `proyectos/turnos-profesionales/01-requisitos/documento-funcional.md` (Business Analyst)

## Visión de producto

App mobile que conecta clientes con profesionales para la reserva de turnos, permitiendo a
cada profesional gestionar su propia agenda y cartera de clientes, y al cliente reservar sin
fricción en tres pasos: servicio → profesional → horario.

> **Actualizado tras decisiones del CEO** (ver `01-requisitos/documento-funcional.md` §1,
> D1–D5): la plataforma es **multi-negocio**, el pago/seña es **configurable por
> profesional**, el historial es **privado por profesional**, las **notificaciones entran al
> MVP**, y **no hay lista de espera** (se muestra el próximo disponible).

## Roadmap de producto

> **Actualizado 2026-08-06 — alcance de v1 confirmado por el CEO.** Las 15 decisiones que
> resuelven las preguntas abiertas de la ampliación de 2026-08-05 quedaron aplicadas en todo
> este documento (detalle en cada HU y en la sección "Ampliación del backlog"). La separación
> anterior "V1 (MVP) / V2 / V3 / V4 (ampliación futura)" se retira: el CEO confirmó que **todo
> el backlog (E0–E14) forma parte de una única v1** — nada de lo que antes era "V4" se difiere a
> una release posterior. Lo que sigue es una sola distinción de secuenciación de release
> (v1 vs. fast-follow), no de alcance.

- **v1 (release inicial, alcance completo confirmado):** descubrimiento de negocio; flujo
  completo de reserva cliente↔profesional; multi-tenant; seña configurable por profesional;
  notificaciones (push/email como base, D4, + WhatsApp como canal adicional por negocio, HU-24);
  cancelación/reprogramación; excepciones de disponibilidad; dashboard del profesional;
  configuración avanzada de disponibilidad y plantillas recurrentes; ficha de paciente extendida
  (solo negocios de rubro salud) e historial clínico; documentos adjuntos por paciente; alta
  manual de turnos con seña omitible; reportes básicos; configuración de pagos (Mercado Pago) y
  de consultorio; privacidad y notificaciones granulares; y suscripción "Turnario Pro"
  (freemium). Épicas **E0–E14 completas**. **Plataforma: solo Android (Google Play)** — iOS/App
  Store queda fuera de v1 (ver E11/HU-29).
- **Fast-follow (post-lanzamiento, sin épica asignada todavía):** iOS/App Store; medios de pago
  adicionales a Mercado Pago; reportes/analítica más avanzada que el alcance básico de E10 hoy
  (ocupación, ausentismo, recurrencia de clientes, exportación); las funcionalidades hoy
  placeholder en HU-26 (mensajería in-app, reseñas/calificaciones, promociones) si el CEO decide
  construirlas más adelante.

**Notas operativas de rollout** (no son historias nuevas, quedan documentadas acá para que no se
pierdan al planificar el lanzamiento):

- **Mercado Pago (E12/HU-30):** el lanzamiento inicial puede salir con todos los servicios
  configurados "sin seña" (`requiere_sena = false`, RN10, ya soportado hoy) mientras se tramita
  la habilitación de la cuenta de Mercado Pago del negocio — no bloquea el lanzamiento de v1.
- **Datos de salud / HU-20 — bloqueante de LANZAMIENTO, no de desarrollo.** El CEO va a
  consultar a un abogado sobre la Ley 25.326 (datos sensibles/de salud) antes de habilitar HU-20
  con datos reales de pacientes en producción. HU-20 se construye y prueba con normalidad en
  Fases 3–5; su salida a producción con datos reales queda condicionada a luz verde legal
  explícita del CEO — es un bloqueante de Fase 6 (Despliegue), no de desarrollo.
- **Import/export de pacientes en lote / HU-22 — bloqueante de DESARROLLO** (a diferencia de
  HU-20 arriba, que solo bloquea el lanzamiento). UX/UI pidió explícitamente revisión de
  Security antes de implementar, por moverse PII en lote. El Director General IA decidió
  (2026-08-10) dejarla fuera de la tanda de desarrollo en curso (Gestión de Pacientes, Ficha,
  Historial, Configuración) — no se construye en Backend ni Mobile hasta que Security dé luz
  verde explícita. Sigue siendo parte del alcance de v1 (E0–E14) — solo cambia cuándo se
  construye, no si se construye. Detalle completo en HU-22.

## Épicas

| # | Épica | Prioridad |
|---|---|---|
| E0 | Alta y descubrimiento de negocios (multi-tenant) | P0 |
| E1 | Alta de servicios y profesionales por negocio | P0 |
| E2 | Gestión de disponibilidad del profesional | P0 (extendida, ver HU-16 a HU-18) |
| E3 | Reserva de turno (cliente), con seña opcional por profesional | P0 |
| E4 | Autenticación y perfiles | P0 (extendida, ver HU-35) |
| E7 | Notificaciones (confirmación y recordatorio) | P0 (extendida, ver HU-24 a HU-26) |
| E5 | Gestión de clientes e historial (profesional) | P1 (extendida, ver HU-19 a HU-23 y HU-33; HU-22 diferida, ver nota) |
| E6 | Cancelación y reprogramación de turnos | P1 |
| E9 | Dashboard del profesional (resumen del día) | P1 |
| E10 | Reportes y estadísticas (negocio/profesional) | P1 (repriorizada 2026-08-06, ver nota) |
| E11 | Suscripción "Turnario Pro" (monetización) | P1 (repriorizada y desbloqueada 2026-08-06, ver nota) |
| E12 | Configuración de pagos del negocio (Mercado Pago) | P1 (repriorizada 2026-08-06, ver nota) |
| E8 | Excepciones de disponibilidad (feriados/licencias) | P2 |
| E13 | Configuración extendida de consultorio (negocio) | P2 |
| E14 | Privacidad y seguridad de la cuenta (transversal) | P2 |
| E15 | Modo Administrador v1 (Mobile) — cierra el gap de UI para HU-02/HU-03/HU-29/HU-31 (acotada) | P1 (nueva 2026-08-14, ver sección al final del documento) |

> Nota: E9–E14 y las historias nuevas dentro de E0/E2/E5/E7 (HU-16 a HU-34) se agregaron el
> 2026-08-05 a partir de capturas de pantalla de otra app del CEO (turnos/citas, de su
> propiedad, aún no en producción); el CEO autorizó tomar tanto el estilo visual como las
> funcionalidades nuevas que mostraban. No hubo acceso a los archivos de imagen — la Director
> General IA transcribió cada pantalla en detalle y esta ampliación se elaboró sobre esa
> transcripción. **Actualización 2026-08-06:** el CEO respondió las 15 decisiones/preguntas que
> condicionaban esta ampliación (duración de cita, ficha de paciente por rubro, documentos
> adjuntos, WhatsApp, Turnario Pro, plataformas, seña omitible, import/export, reportes/pagos,
> toggles placeholder, estado activo/inactivo, alcance de v1) — aplicadas en todas las HU
> correspondientes, con repriorización justificada de E10–E12 a P1. Detalle completo al final de
> este documento, en la sección "Ampliación del backlog".
>
> **Reconciliación (Product Manager, 2026-08-10):** verificado — esta nota, tal como quedó
> redactada el 2026-08-06, ya resuelve la ambigüedad: "alcance de v1" es una de las 15
> decisiones aplicadas de la lista de arriba, y **E9–E14 sí forman parte del alcance confirmado
> de v1**, igual que E0–E8, aunque se hayan incorporado más tarde (2026-08-05, posterior al
> cierre de la Fase 2 original de E0–E8). Esa conclusión quedaba implícita en el texto de arriba
> y explícita solo en la sección "Roadmap de producto" al inicio del documento — se deja
> explícita también acá para que nadie que lea únicamente esta tabla de épicas quede con la duda.
> Única excepción puntual dentro de ese alcance: **HU-22** (import/export de pacientes) queda
> diferida para revisión de Security antes de construirse (ver esa historia y "Notas operativas
> de rollout" en el Roadmap) — sigue siendo v1, solo cambia cuándo se construye, no si se
> construye.

---

## E4 — Autenticación y perfiles (P0, bloquea todo lo demás)

**HU-01.** Como cliente o profesional, quiero registrarme e iniciar sesión, para poder
acceder a las funciones de la app según mi rol.
- Criterios de aceptación:
  - Registro con email/teléfono + contraseña (o proveedor externo, a definir con Arquitecto).
  - Al iniciar sesión, la app distingue si soy Cliente, Profesional o Administrador de negocio
    y muestra la vista correspondiente.
  - Un profesional y un administrador quedan asociados a exactamente un negocio (RN9).

**HU-02.** Como administrador de un negocio, quiero dar de alta profesionales, para que
puedan gestionar su propia agenda dentro de mi negocio.

**HU-35 (v1, P1 — nueva, extiende HU-01).** Como cliente o profesional, quiero poder iniciar
sesión o registrarme con mi cuenta de Google, además de con email y contraseña, para acceder a
la app sin depender de crear y recordar una contraseña propia.
- Criterios de aceptación:
  - **Origen y aprobación (CEO, 2026-08-09):** a partir de una captura real de la app de
    referencia "Turnario Pro" (`Screenshot_20260805_202552_Turnario.jpg`), documentada por
    UX/UI en `04-diseno/mapa-pantallas.md` §5.17 (pantalla de Login/Registro) y su tabla de
    trazabilidad (§7). Resuelve el paréntesis que HU-01 dejaba abierto desde el origen del
    backlog ("Registro con email/teléfono + contraseña (o proveedor externo, a definir con
    Arquitecto)"): el proveedor externo es Google. Es una incorporación nueva y puntual,
    independiente de la ampliación de 2026-08-05/06 (E9–E14, HU-16 a HU-34).
  - **Prioridad P1, no P0 (justificación de Product Manager):** aunque la historia vive dentro
    de E4 (P0, "bloquea todo lo demás"), esta historia puntual no bloquea nada — el flujo de
    email/contraseña (HU-01/HU-02) ya está implementado y en uso, y sigue funcionando sin
    cambios con o sin esta historia. Se prioriza P1 (valiosa, reduce fricción de registro/
    login; mismo criterio que otras extensiones sobre funcionalidad ya construida, ej. HU-16,
    HU-23) en vez de P0 porque su ausencia no impide operar ninguna otra historia de v1.
  - **Es una opción ADICIONAL, no un reemplazo:** el flujo de email/contraseña ya implementado
    en Backend (`05-codigo/backend/src/routes/auth.ts` — `/login`, `/registro-cliente`,
    `/registro-negocio`) debe seguir funcionando exactamente igual que hoy para quien no usa
    Google. El botón "Google" (outline, con el logo de Google, debajo del botón principal
    "Iniciar sesión") ya está wireframeado por UX/UI en §5.17 — esta historia no repite ese
    detalle visual.
  - Al autenticarse con Google, la app debe seguir distinguiendo el rol del usuario (Cliente,
    Profesional, Administrador) y mostrar la vista correspondiente, con el mismo criterio que
    ya exige HU-01 para el login con contraseña. UX/UI ya dejó abierto en §5.17 en qué momento
    se determina ese rol para esta pantalla (antes o después del login) — es la misma incógnita
    que ya existe para el flujo de contraseña, no una pregunta nueva de esta historia.
  - **Resuelto (DBA, 2026-08-10) — la tabla `usuario` no contemplaba un alta sin contraseña
    propia:** el esquema hasta este ciclo (`03-arquitectura/modelo-datos.md` §2;
    `05-codigo/backend/migrations/001_init.sql`, `CREATE TABLE usuario`) definía `password_hash
    TEXT NOT NULL` — un usuario que se registra ÚNICAMENTE con Google no tendría una contraseña
    propia que hashear. **Decisión tomada:** `password_hash` pasa a nullable, se agrega
    `google_id TEXT UNIQUE` (nullable, el claim `sub`/subject del ID token de Google — estable e
    inmutable, no el email) y un `CHECK (password_hash IS NOT NULL OR google_id IS NOT NULL)` que
    garantiza a nivel de base de datos que ninguna cuenta quede sin ningún método de login válido.
    Se descartó explícitamente un hash placeholder no utilizable (queda como un caso especial
    invisible en el esquema) y también descartó agregar una columna separada "proveedor_auth"
    (redundante: puede desincronizarse de qué columnas están realmente pobladas) — la combinación
    `password_hash`/`google_id` deriva el/los métodos disponibles directamente de qué columnas
    tienen valor, sin flag adicional que mantener sincronizado. Razonamiento completo, columna por
    columna, y la recomendación para Backend sobre el flujo de login/vinculación de cuentas por
    email en `03-arquitectura/modelo-datos.md` §2sexies y en los comentarios de
    `05-codigo/database/migrations/001_init.sql` (`CREATE TABLE usuario`). Aplicado en esa
    migración y, para el ambiente de Render ya migrado, en la migración incremental
    `05-codigo/database/migrations/002_pacientes_historial_auth_google.sql` (pendiente de correr
    a mano contra Render — ver el header de ese archivo). **Pendiente real para Backend, no
    cerrado por DBA:** implementar el endpoint de login/registro con Google en sí
    (`src/routes/auth.ts`) sigue sin construirse — esta resolución es solo el modelo de datos que
    lo habilita.
  - **Resuelto (Security, 2026-08-10) — vinculación de cuentas si el email ya está registrado
    por contraseña:** un único botón "Google" (login + alta en una sola acción, como sugiere la
    captura) es viable con este diseño, siempre que el backend distinga los casos de abajo — no
    hace falta un botón separado por caso. **Regla general: nunca vincular ni loguear
    automáticamente por la sola coincidencia de email** — ni siquiera si Google confirma
    `email_verified: true`. Justificación completa (por qué no alcanza con `email_verified`
    solo, alternativas evaluadas) en `07-seguridad/informe-seguridad.md` (adenda 2026-08-10);
    reglas concretas para Backend:
    1. **Sin cuenta previa con ese email:** dar de alta una cuenta nueva vía Google solo si el
       ID token trae `email_verified: true`. Si viene `false`, rechazar el alta y pedir otro
       método — nunca crear una cuenta sobre un email que ni el propio proveedor verificó.
    2. **Ya existe una cuenta creada por contraseña con ese email:** nunca autovincular, sin
       importar `email_verified`. Mostrar "Ya existe una cuenta con este email — iniciá sesión
       con tu contraseña para vincular Google" y exigir esa contraseña en el mismo flujo; solo
       tras validarla se persiste la asociación Google↔usuario_id.
    3. Una vez vinculada sigue existiendo una única fila `usuario` (mismo `id`/`rol`/membresías
       de negocio) — Google pasa a ser un método de acceso adicional de ese `usuario_id`, nunca
       un usuario nuevo. Implica persistir, por usuario, qué proveedor(es) tiene habilitados y
       el `sub` de Google (no el email, que puede cambiar del lado de Google) — la forma
       concreta (tabla propia vs. columna nullable en `usuario`) queda para Backend/DBA junto
       con la pregunta abierta de arriba sobre `password_hash NOT NULL`; lo que fija esta
       decisión es que la vinculación debe quedar registrada explícitamente, nunca inferida en
       cada login por coincidencia de string de email.
    4. El paso de confirmación con la contraseña existente reutiliza el rate limiting que ya
       exige HIGH-1 (`07-seguridad/informe-seguridad.md`) — mismo endpoint/lógica que el login
       normal, no abre superficie nueva de fuerza bruta.
    5. Recomendado, no bloqueante: loguear el evento de vinculación (usuario_id, proveedor,
       fecha) para auditoría, y ofrecer además "vincular Google" desde "Seguridad de la cuenta"
       (`04-diseno/mapa-pantallas.md` §5.13) para quien ya está logueado por contraseña — ahí no
       hace falta repedirla, la sesión activa ya es prueba suficiente de identidad.
  - **Resuelto (DevOps, con Arquitecto, 2026-08-11) — administración de credenciales OAuth de
    Google:** un único proyecto de Google Cloud (gratis, cualquier cuenta de Google — no tiene
    relación con las cuentas pagas de Google Play/Apple Developer de
    `03-arquitectura/plan-produccion.md` §8) con dos Client ID (tipo "Web application" y tipo
    "Android"; iOS queda sin crear por ahora, ver D15 en `01-requisitos/documento-funcional.md`)
    es la única credencial de aplicación que hace falta — la administra el CEO, ningún agente de
    IA puede crearla (mismo tipo de límite que las cuentas de tiendas de apps). Se gestiona como
    una única variable de entorno nueva, `GOOGLE_CLIENT_ID` (sin `GOOGLE_CLIENT_SECRET`: el flujo
    de verificación de ID token del lado del servidor con `google-auth-library` no lo necesita),
    con el mismo valor en todos los entornos (a diferencia de `JWT_SECRET`) — presente en
    `.env` local (gitignorado), deliberadamente ausente en CI (el endpoint responde 503 sin
    necesitar ningún mock, HU-35 no bloquea el resto del backlog), y declarada con `sync: false`
    en `05-codigo/backend/render.yaml` para que el CEO la cargue a mano desde el dashboard de
    Render cuando tenga el valor real. Instructivo completo paso a paso para el CEO (con los
    nombres exactos de los menús de Google Cloud Console), el razonamiento técnico completo, y
    el criterio de gateo para que Backend/Mobile construyan ya sin esperar credenciales reales
    (el endpoint responde 503 si `GOOGLE_CLIENT_ID` no está seteada, mismo criterio que
    `ENABLE_DEV_ROUTES`) en `08-despliegue/google-oauth.md`.
    **Bloqueo real encontrado para el Client ID Android en particular (no para el Web, que no
    depende de esto):** hace falta un nombre de paquete Android definitivo y al menos un SHA-1
    de un keystore de firma — ninguno de los dos existe hoy (`05-codigo/mobile` nunca corrió
    `flutter create` con una organización propia ni generó ningún keystore, ver su README.md) —
    pendiente de Arquitecto/Mobile, detallado en ese mismo documento; no bloquea nada de lo
    demás.
  - Las tres preguntas quedaron resueltas (DBA/Security/DevOps, ver arriba) — Backend y Mobile
    ya pueden construir el flujo real de HU-35 en paralelo, sin esperar a que existan
    credenciales reales de Google (el endpoint queda gateado mientras tanto, ver
    `08-despliegue/google-oauth.md` §5). Ninguna de las tres bloqueó nunca el resto del backlog
    ni el resto de E4 (HU-01/HU-02 siguieron funcionando sin cambios) — condicionaban únicamente
    el diseño detallado e implementación de esta historia puntual.

---

## E0 — Alta y descubrimiento de negocios (multi-tenant) (P0)

**HU-00a.** Como administrador, quiero registrar mi negocio en la plataforma (nombre,
rubro/categoría, ubicación), para empezar a operar de forma aislada de otros negocios (D1, RN9).

**HU-00b.** Como cliente, quiero buscar o navegar negocios disponibles en la plataforma, para
elegir dónde quiero reservar un turno. (CU3)
- Criterios de aceptación: el listado no mezcla datos entre negocios (RN9); el mecanismo de
  búsqueda concreto (ubicación, categoría, texto) lo define UX/UI en Fase 3.

---

## E1 — Alta de servicios y profesionales por negocio (P0)

**HU-03.** Como administrador, quiero cargar los servicios que ofrece mi negocio (nombre,
duración, precio de referencia), para que los profesionales puedan asociarlos a su agenda.
- Criterios de aceptación:
  - Un servicio tiene nombre, duración en minutos y precio de referencia (RN3).
  - Un servicio puede asociarse a uno o más profesionales del mismo negocio (RN4).

**HU-04.** Como administrador, quiero asociar uno o más servicios a cada profesional de mi
negocio, para que el cliente solo vea combinaciones válidas al reservar.

**HU-04b.** Como profesional, quiero configurar si un servicio que ofrezco requiere seña/pago
anticipado para reservarse, para reducir ausencias en los servicios que elijo. (D2, RN10)

---

## E2 — Gestión de disponibilidad del profesional (P0)

**HU-05.** Como profesional, quiero definir bloques de disponibilidad recurrentes por
servicio, para que el sistema calcule los horarios reservables. (CU1)
- Criterios de aceptación:
  - Puedo definir días y rangos horarios semanales por servicio.
  - El sistema genera slots según la duración del servicio (RN3) sin solaparse entre sí (RN2).

**HU-06.** Como profesional, quiero ver mi calendario con los turnos ya reservados y los
slots libres, para tener visibilidad completa de mi agenda.

**HU-16 (v1, P1 — extiende HU-05).** Como profesional, quiero configurar mi propia duración de
cita, máximo de citas por día y anticipación de reserva, para adaptar la agenda a cómo trabajo
en vez de depender de un valor fijo para todos los profesionales.
- Criterios de aceptación:
  - Duración de cita, máximo de citas por día y anticipación de reserva son configurables por
    profesional, no un valor global de la plataforma (hoy son fijos).
  - **Precedencia resuelta (CEO, 2026-08-06):** cuando el profesional configura su propia
    duración general de cita, esa duración **reemplaza** a la duración del servicio (RN3) para
    **todos** los turnos de ese profesional — no es un default sugerido, es el valor que se usa
    para calcular slots. Si el profesional no configuró una duración propia, se sigue usando la
    duración del servicio, como hoy.
  - **Marcada explícitamente como cambio sobre Backend ya implementado, no historia nueva
    aislada:** el cálculo de slots por duración de servicio (RN3) ya está implementado y probado
    de punta a punta en HU-05 (generación de disponibilidad) y HU-09 (reserva del cliente).
    Construir HU-16 implica **modificar esa lógica ya construida**, con su propio análisis de
    impacto y batería de regresión (RN1, RN2) antes de tocarse — a planificar y estimar como
    historia técnica de modificación, separada de las historias de esta ampliación que sí son de
    alcance limpio (ej. HU-17, HU-18, HU-19). Ver también la nota cruzada en HU-09.

**HU-17 (v1, P1 — extiende HU-05).** Como profesional, quiero definir una plantilla semanal de
horarios y "replicarla" hacia adelante (4/8/12 semanas o ~6 meses), eligiendo los días de la
semana que aplican y si sobrescribe los días que ya tienen horario cargado o solo completa los
huecos, para no tener que cargar disponibilidad día por día.
- Criterios de aceptación:
  - La plantilla solo afecta los días de la semana seleccionados dentro del alcance elegido.
  - El modo "no sobrescribir" no borra ni modifica horarios ya cargados manualmente.
  - Respeta las mismas reglas de generación de slots ya implementadas (RN1, RN2, RN3) — no es
    un camino alternativo que las evite.

**HU-18 (v1, P2 — extiende HU-06).** Como profesional, quiero ver un calendario mensual con
indicador visual en las fechas que ya tienen horario configurado y un contador de fechas
configuradas, y definir un bloque de descanso (ej. almuerzo) dentro de mi jornada, para tener
visibilidad rápida de mi disponibilidad cargada.
- Criterios de aceptación:
  - El bloque de descanso no genera slots reservables dentro de su rango horario.
  - Es una vista complementaria a HU-06 (turnos + slots libres), no la reemplaza.

---

## E3 — Reserva de turno (cliente), con seña opcional por profesional (P0)

**HU-07.** Como cliente, quiero elegir un servicio dentro del negocio que elegí, para filtrar
los profesionales disponibles para eso. (CU4, paso 1)

**HU-08.** Como cliente, quiero elegir un profesional entre los que ofrecen el servicio
elegido dentro de ese negocio, para ver sus horarios disponibles. (CU4, paso 2)

**HU-09.** Como cliente, quiero ver los horarios disponibles del profesional elegido y
reservar uno, para confirmar mi turno. (CU4, pasos 3–4, 6)
- Criterios de aceptación:
  - Solo se muestran slots dentro de la disponibilidad publicada y no ocupados (RN1).
  - Si dos clientes intentan reservar el mismo slot al mismo tiempo, solo uno de los dos
    obtiene la reserva; el otro ve el slot como no disponible (requisito no funcional →
    Arquitecto/Backend deben resolver la concurrencia).
  - Si no hay horarios en el rango consultado, se muestra el próximo disponible (D5, sin lista
    de espera).
  - **Nota (CEO, 2026-08-06) — cambio pendiente sobre lógica ya implementada:** HU-16 (E2)
    cambia cómo se calcula la duración del turno cuando el profesional configuró una duración
    general propia (esa duración REEMPLAZA a la del servicio, RN3, para todos sus turnos). Esta
    historia (HU-09) ya está implementada y probada en Backend usando únicamente la duración del
    servicio para calcular slots — aplicar HU-16 requiere MODIFICAR esa lógica ya construida y
    probada (no es una historia nueva de alcance aislado), con su propio análisis de regresión
    sobre RN1/RN2. Ver HU-16 para el detalle completo.

**HU-09b.** Como cliente, quiero pagar la seña cuando el profesional la requiere para el
servicio elegido, para poder confirmar la reserva. (CU4, paso 5, D2/RN10)
- Criterios de aceptación:
  - Si el profesional no requiere seña para ese servicio, el turno se confirma sin pedir pago.
  - Si la requiere, el turno queda "pendiente de pago" hasta que el pago se acredite; si el
    pago falla o se abandona, el slot vuelve a estar libre.
  - El medio de pago concreto lo define Arquitecto/CTO IA (Fase 3).

---

## E5 — Gestión de clientes e historial (profesional) (P1)

**HU-10.** Como profesional, quiero ver el listado de mis clientes, para identificar
rápidamente a quién atendí. (CU2)

**HU-11.** Como profesional, quiero ver el historial de visitas de un cliente (fecha,
servicio), para dar continuidad a la atención. (CU2, RN7/D3 — el historial es privado, solo
lo ve el profesional que atendió cada visita).

**HU-19 (v1, P2 — extiende HU-10).** Como profesional, quiero ver estadísticas de mi cartera de
pacientes (total, activos, inactivos, nuevos) y filtrar/buscar en el listado (por nombre, o por
chip Todos/Activos/Inactivos/Recientes), para encontrar rápidamente a un paciente en carteras
grandes.
- Criterios de aceptación:
  - **Alcance resuelto (CEO, 2026-08-06):** "activo/inactivo" es un estado que el profesional
    carga/cambia **manualmente** sobre cada paciente (ej. un toggle en la ficha) — no se calcula
    automáticamente por antigüedad de la última visita. Esto simplifica el alcance: no hace
    falta un job/cálculo periódico, alcanza con guardar el estado como un atributo propio del
    paciente (scope por profesional, mismo criterio de privacidad que el resto de la ficha,
    RN7/D3) y filtrar sobre él.
  - **Nota de reconciliación (Product Manager, 2026-08-10):** `04-diseno/mapa-pantallas.md`
    §5.8 y §5.8bis todavía describen "manual vs. calculado" como algo sin confirmar contra
    capturas reales (verificación del 2026-08-07) — quedó desactualizado sin querer, no es una
    contradicción de negocio real: la decisión del CEO del bullet anterior es del 2026-08-06,
    anterior a esa verificación, y ya la resuelve. DBA/Backend/Mobile deben implementar contra
    esta versión (backlog), no contra la pregunta que quedó sin tachar en el documento de UX/UI.
  - **"Nuevos" y "Recientes" — criterio resuelto (Product Manager, 2026-08-10), para que
    DBA/Backend lo implementen sin ambigüedad:** son dos métricas derivadas, independientes
    entre sí y del estado manual Activo/Inactivo (no lo sobrescriben ni dependen de él),
    calculadas al momento de la consulta — sin columna propia ni job periódico, mismo criterio
    que evitó el job para Activo/Inactivo:
    - **Nuevo** (4ta stat card, confirmada contra capturas reales en §5.8bis): paciente cuya
      fecha de alta en la cartera de este profesional (fecha del primer turno con él, o de
      creación del vínculo profesional-paciente — DBA define la fuente exacta según cómo modele
      la relación) cae dentro de los últimos **30 días**.
    - **Reciente** (chip de filtro): paciente que tuvo al menos un turno con estado completado
      en los últimos **30 días**, con el mismo scope por profesional (RN7/D3) que el resto de la
      ficha.
    - **30 días es un valor propuesto por Product Manager, sujeto a ajuste** (mismo criterio que
      otros valores concretos de esta ampliación, ej. el límite de HU-29) — no bloquea el
      desarrollo; si el uso real pide otro umbral, es un cambio de configuración, no de diseño.

**HU-20 (v1, P1 — nueva ficha de detalle, relacionada con HU-10).** Como profesional de un
negocio de **rubro salud**, quiero registrar datos ampliados de cada paciente (fecha de
nacimiento, género, dirección, alergias, contacto de emergencia con nombre/teléfono/relación,
notas libres) además de los datos básicos actuales (nombre, email, teléfono), para tener una
ficha clínica más completa que la de un simple contacto.
- Criterios de aceptación:
  - **Alcance resuelto (CEO, 2026-08-06):** estos campos ampliados aplican **solo a negocios de
    rubro salud** (rubro/categoría definido en HU-00a) — no a todos los rubros de la plataforma
    (D1, multi-rubro). Un negocio de otro rubro (ej. peluquería, estética) no ve estos campos en
    la ficha de paciente. Requiere que el `rubro` de Negocio sea un valor consultable de forma
    fiable en el momento de mostrar/ocultar estos campos — a confirmar con DBA/Backend si hoy se
    guarda como texto libre o como catálogo cerrado, porque condiciona cómo se implementa esta
    verificación.
  - **Nota de reconciliación y formalización (Product Manager, 2026-08-10):** este alcance
    quedó resuelto arriba desde el 2026-08-06 (D11/RN15 en `01-requisitos/documento-funcional.md`
    §1/§3) — no es una pregunta nueva de esta ronda. Se formaliza acá porque
    `04-diseno/mapa-pantallas.md` §5.9 todavía dice "HU-20 también deja abierto si estos campos
    aplican a todos los rubros de negocio... este wireframe los muestra todos, sin ocultamiento
    condicional, a la espera de esa definición" — ese texto de UX/UI quedó desactualizado (la
    decisión del CEO es anterior y no se sincronizó ahí), no hay ninguna decisión de negocio
    nueva pendiente. Para que Mobile no construya la Ficha de Paciente contra la versión vieja
    del wireframe:
    - Los campos de salud **no son "opcionales pero visibles" para todos los rubros** — son
      **condicionales**: se muestran y son editables únicamente cuando `negocio.rubro` es salud;
      para cualquier otro rubro, la sección completa (Contacto de emergencia + ✱ Salud, §5.9 de
      `mapa-pantallas.md`) no se renderiza en absoluto, no solo se deja vacía.
    - A nivel de datos esto no requiere una entidad separada por rubro: `Cliente` sigue siendo
      una única entidad compartida por todos los rubros (ya confirmado en
      `01-requisitos/documento-funcional.md` §5, glosario) con estas columnas nullable — para un
      paciente de un negocio no-salud simplemente quedan en `NULL` siempre (nunca se completan
      ni se muestran); no hace falta modelar nada distinto por rubro más allá de esa condición
      de lectura/escritura.
    - **Dependencia para esta tanda (Mobile/Backend):** la pregunta de implementación que ya
      tenía DBA pendiente (si `negocio.rubro` sigue siendo texto libre o pasa a catálogo
      cerrado/flag `es_rubro_salud` para condicionar de forma confiable, ver
      `01-requisitos/documento-funcional.md` §1/D11) sigue sin resolver y ahora sí es bloqueante
      para el condicional de mostrar/ocultar de la Ficha de Paciente — DBA está trabajando en
      paralelo sobre esta misma rama; coordinar antes de dar por cerrado el diseño detallado de
      esta pantalla.
  - Todos los campos nuevos son opcionales salvo los que ya son requeridos hoy.
  - **Nota de seguridad:** alergias y contacto de emergencia son datos de salud/sensibles;
    requieren revisión de Security antes de habilitarse en producción, con el mismo criterio
    de privacidad que ya aplica al historial (RN7/D3).
  - **Revisión de Security (2026-08-10) — resultado:** el aislamiento estándar por negocio (RLS
    multi-tenant, RN9) es necesario pero **no alcanza solo** para estos campos. RN7/D3 exige que
    sean visibles únicamente para el profesional que atendió/registró a ese paciente — más
    estricto que "cualquier staff del negocio", que es el nivel que ya cubren las policies de
    RLS existentes hoy (`05-codigo/database/migrations/001_init.sql`); esa restricción más fina
    hoy se aplica a nivel de query de aplicación (`GET /clientes/:id/historial`), no de RLS —
    mismo patrón que debe replicarse (o reforzarse con una policy propia) para estos campos
    nuevos. **Importante para DBA, que está modelando esto en paralelo ahora mismo:** que
    `Cliente` sea conceptualmente "una única entidad compartida por todos los rubros" (nota de
    reconciliación de arriba) resuelve la condicionalidad por rubro, pero no implica que estas
    columnas deban vivir como atributos del `usuario` global — si se agregan ahí, quedan
    visibles para cualquier profesional que alguna vez atendió a esa persona, en cualquier
    negocio, rompiendo RN7/D3. Necesitan quedar scopeadas por `(profesional_id, cliente_id)`,
    igual que ya se resolvió para el estado Activo/Inactivo (HU-19) y para "Reciente" (nota de
    arriba, 2026-08-10). Checklist técnico completo antes de producción con datos reales
    (detalle y justificación en `07-seguridad/informe-seguridad.md`, adenda 2026-08-10): (1) el
    scope por `(profesional_id, cliente_id)` de arriba, con una prueba de regresión dedicada
    (mismo espíritu que `scripts/test-autorizacion-cruzada.mjs`); (2) log de auditoría de
    accesos (lectura/escritura) a estos campos; (3) confirmar que el export de HU-22 reusa el
    mismo control de acceso. El cifrado a nivel de columna se recomienda como capa adicional
    pero no se exige como bloqueante de este ciclo. Nada de esto reemplaza ni adelanta el gate
    legal de Ley 25.326 de la nota siguiente — es la lista técnica que debe quedar resuelta para
    cuando ese gate se levante.
  - **Nota de riesgo de LANZAMIENTO, no de desarrollo (CEO, 2026-08-06):** el CEO va a consultar
    a un abogado sobre la Ley 25.326 (datos sensibles/de salud) antes de habilitar esta historia
    con datos reales de pacientes en producción. Puede construirse y probarse con normalidad en
    Fases 3–5; su salida a producción queda condicionada a luz verde legal explícita — bloqueante
    de Fase 6 (Despliegue), no de desarrollo. Ver también Roadmap de producto.

**HU-21 (v1, P1 — extiende HU-11).** Como profesional, quiero ver en el historial de un
paciente, además de sus turnos (fecha, hora, estado, servicio, profesional, duración, costo,
estado de pago), sus tratamientos y notas médicas como registros propios —no atados a un turno
puntual— junto con un resumen general (citas totales, completadas, tratamientos, notas
médicas), para llevar seguimiento clínico/de servicio más allá de la agenda.
- Criterios de aceptación:
  - Tratamientos y notas médicas heredan la misma privacidad por profesional que el historial
    de visitas (RN7/D3) — no se comparten entre profesionales del mismo negocio.
  - El estado de pago mostrado reutiliza el estado ya definido en HU-09b (pendiente/
    confirmado); no introduce un estado de pago nuevo.
  - Implica nuevas entidades de datos (Tratamiento, Nota médica) que hoy no existen en el
    modelo — a modelar por DBA antes de desarrollarse (hoy el historial es una consulta sobre
    Turno, sin entidad propia).

**HU-22 (v1, P2 — DIFERIDA, bloqueada para desarrollo — ver nota).** Como profesional, quiero
importar y exportar mi listado de pacientes, para migrar datos desde otra herramienta o hacer un
respaldo propio.
- Criterios de aceptación:
  - **Diferida — bloqueada para desarrollo (Director General IA, 2026-08-10):** UX/UI marcó
    explícitamente en `04-diseno/mapa-pantallas.md` §5.8 y §6 que Importar/Exportar mueve datos
    personales (PII) de pacientes **en lote** y pidió "marcar para revisión de Security antes de
    implementar". El Director General IA decidió excluir esta historia de la tanda de desarrollo
    que arranca ahora (Gestión de Pacientes, Ficha de Paciente, Historial, Configuración) — se
    formaliza acá para que quede trazado y **nadie la implemente por error** mientras tanto.
    Sigue siendo parte del alcance de v1 confirmado (no se cancela, no sale de E0–E14, ver nota
    de reconciliación en la tabla de épicas más arriba) — lo único que cambia es la secuencia: su
    desarrollo queda bloqueado hasta que Security complete la revisión de manejo de PII en lote
    (cifrado en tránsito/reposo, límites de tamaño y rate limiting del export, validación de la
    importación, alcance de auditoría) y dé luz verde explícita. Mismo patrón que ya usa HU-20
    para su gate legal de lanzamiento, pero acá el bloqueo es de **desarrollo**, no solo de
    salida a producción: ni Backend ni Mobile deben empezar a construirla hasta esa luz verde.
  - **Formato resuelto (CEO, 2026-08-06):** soporta **CSV y Excel (.xlsx)**, en **ambos
    sentidos** — importación y exportación. Queda documentado para cuando Security habilite la
    historia; no habilita por sí solo a empezar a construirla.
  - La exportación genera un archivo con todos los pacientes de la cartera del profesional
    (mismos campos que la ficha, básica + extendida donde aplique por rubro, HU-20 — RN7/D3:
    solo su propia cartera).
  - La importación ofrece una **plantilla descargable** (CSV/Excel) con las columnas esperadas,
    para reducir errores de formato al cargar.
  - Manejo de filas inválidas/incompletas en la importación (rechazar el archivo completo vs.
    importar el resto y reportar un listado de filas con error) queda para diseño detallado
    (UX/Backend) — no asumido acá.

**HU-23 (v1, P1 — nueva, relacionada con E3/CU4).** Como profesional, quiero agendar
manualmente un turno para un paciente (por ejemplo, si me lo pidió por teléfono o se presentó
sin reserva previa), eligiendo servicio, fecha, hora y agregando notas, para registrar turnos
que no pasan por el flujo de autoreserva del cliente.
- Criterios de aceptación:
  - Se aplican las mismas reglas de no solapamiento y duración por servicio que en la reserva
    del cliente (RN1, RN2, RN3) — no es un camino que evite esas garantías.
  - **Seña resuelta (CEO, 2026-08-06):** el profesional puede decidir **no cobrar la seña** al
    agendar el turno manualmente, aunque el servicio tenga `requiere_sena = true` configurado
    (RN10/HU-04b) — es una decisión puntual del profesional en el momento de la carga manual, no
    una anulación de la configuración general del servicio (que sigue aplicando normalmente en
    la autoreserva del cliente, CU4). El formulario debe incluir una opción explícita para esto
    (ej. checkbox/toggle "cobrar seña"), no un valor implícito.
  - **Pregunta abierta (sigue sin resolver):** en la captura, el campo "Hora" acepta texto libre
    con más de un horario de ejemplo ("Ej: 10:00, 14:30") — ¿permite agendar varios turnos en
    una sola acción (uno por horario ingresado)? No asumido; a confirmar con el CEO antes de
    diseñar el formulario. Esto no bloquea el resto de esta ampliación — solo el diseño detallado
    de este formulario puntual.

**HU-33 (v1, P2 — nueva, relacionada con HU-20/HU-21).** Como profesional, quiero subir y ver
documentos adjuntos de un paciente (estudios, órdenes médicas, autorizaciones escaneadas), para
tener a mano la documentación asociada a su atención sin salir de la app.
- Criterios de aceptación:
  - **Resuelve "Autorizaciones Médicas" (CEO, 2026-08-06):** el ítem observado en las capturas
    se resuelve como documentos adjuntos por paciente — **subir/ver archivos únicamente**. No
    incluye firma digital ni flujo de consentimiento/aprobación en este alcance.
  - **Pregunta abierta (detectada en cruce con Business Analyst, no resuelta por el CEO en esta
    ronda):** si estos documentos son privados por profesional (mismo criterio que el historial,
    RN7/D3) o compartidos entre los profesionales del negocio — no asumido; a confirmar con el
    CEO antes de diseñar el modelo de acceso. Tratarlo como privado por profesional mientras
    tanto es la opción más conservadora (no expone de más), pero no está confirmado como
    decisión final.
  - Formatos aceptados, tamaño máximo por archivo y mecanismo de almacenamiento (ej. object
    storage) los define Arquitecto en Fase 3 — no asumido acá.
  - **Nota abierta de alcance (no asumida):** a diferencia de HU-20, el CEO no indicó que esta
    historia se restrinja solo a negocios de rubro salud — los ejemplos dados (estudios, órdenes
    médicas) son de salud, pero "documento adjunto" es un concepto más general que podría aplicar
    a cualquier rubro (ej. un contrato firmado). Si aplica a todos los rubros o solo a salud
    queda para confirmar en Fase 3 (UX/Arquitecto) antes de diseñar la pantalla; no bloquea la
    prioridad ni la existencia de esta historia.

---

## E6 — Cancelación y reprogramación de turnos (P1)

**HU-12.** Como cliente, quiero cancelar un turno reservado, para liberar el horario si ya no
lo necesito. (CU4)
- Criterios de aceptación: solo permitido fuera de la ventana mínima de cancelación (RN8,
  supuesto A3); fuera de esa ventana, la app indica contactar al negocio.

**HU-13.** Como cliente, quiero reprogramar un turno a otro horario disponible del mismo
profesional/servicio, sin tener que cancelar y volver a reservar desde cero. (CU4)

---

## E7 — Notificaciones (P0, confirmado en MVP — D4)

**HU-14.** Como cliente, quiero recibir una confirmación al reservar y un recordatorio antes
del turno, para no olvidarlo. (D4)

**HU-14b.** Como profesional, quiero recibir una notificación cuando un cliente reserva,
cancela o reprograma un turno, para mantener mi agenda actualizada sin tener que revisarla
constantemente.

**HU-24 (v1, P2 — relacionada con D4/HU-14/HU-14b).** Como cliente o profesional, quiero
recibir las notificaciones de turno (confirmación, recordatorio, cancelación/reprogramación)
también por WhatsApp, para enterarme por el canal que ya uso a diario.
- Criterios de aceptación:
  - **Alcance resuelto (CEO, 2026-08-06):** WhatsApp es un canal **adicional**, no reemplaza
    push/email (D4/HU-14/HU-14b) — el usuario elige recibir por uno, varios o todos los canales
    disponibles (ver también HU-26, preferencias de notificación).
  - **Cuenta de WhatsApp Business API resuelta:** cada negocio gestiona y carga su **propia**
    cuenta/credenciales de WhatsApp Business API (Meta) — no es una cuenta centralizada de la
    Factory. Depende de la nueva historia **HU-34** (E13) para que el administrador del negocio
    cargue esas credenciales antes de poder activar este canal.
  - Si un negocio no cargó credenciales de WhatsApp (HU-34), el canal WhatsApp no está
    disponible para sus clientes/profesionales — el sistema no debe fallar la notificación
    completa, solo omitir ese canal y seguir enviando por los demás.
  - El envío real requiere integración con la API de WhatsApp Business (Meta) — el proveedor/SDK
    concreto (API oficial de Meta vs. proveedor intermediario tipo Twilio/Gupshup) lo define
    Arquitecto/Integraciones en Fase 3.

**HU-25 (v1, P2 — nueva).** Como profesional, quiero ver un historial/centro de notificaciones
dentro de la app (no solo recibir el push puntual), para revisar alertas pasadas si no las vi
en el momento. Corresponde al ítem "Notificaciones" de la barra de navegación principal
observado en las capturas.

**HU-26 (v1, P2 — nueva).** Como cliente o profesional, quiero elegir qué tipos de notificación
recibo (citas y recordatorios, mensajes, reseñas y calificaciones, promociones y ofertas) y
configurar sonido y vibración, para no recibir alertas que no me interesan.
- Criterios de aceptación:
  - **Alcance resuelto (CEO, 2026-08-06):** los toggles "Mensajes", "Reseñas y Calificaciones" y
    "Promociones y Ofertas" se muestran **ya en la UI** aunque las funcionalidades de fondo
    (mensajería in-app, reseñas/calificaciones, marketing/promociones) **no existen todavía** en
    este backlog. Este es el comportamiento esperado, no un defecto: cada toggle es un
    **placeholder visual** — guarda la preferencia del usuario por si la funcionalidad se
    construye más adelante, pero **no tiene ningún efecto funcional hoy** (no hay mensajes,
    reseñas ni promociones que enviar). QA no debe reportarlo como defecto; UX/Technical Writer
    deberían dejar claro en el copy si corresponde marcarlos como "próximamente".
  - El toggle "Citas y recordatorios" sí tiene efecto funcional real: controla D4/HU-14/HU-14b y
    HU-24 (si el negocio activó WhatsApp).

---

## E8 — Excepciones de disponibilidad (P2)

**HU-15.** Como profesional, quiero bloquear puntualmente parte de mi agenda (feriado,
licencia), para que no se generen turnos en ese rango. (CU1, RN5)
- Criterios de aceptación: si ya existen turnos reservados en el rango bloqueado, el sistema
  advierte y requiere gestionar la reprogramación antes de confirmar el bloqueo (RN6).

---

## Ampliación del backlog — funcionalidades de una app hermana del CEO (2026-08-05, decisiones aplicadas 2026-08-06)

**Origen.** El CEO compartió capturas de pantalla de otra app de su propiedad (turnos/citas,
ya construida, todavía no en producción) y autorizó explícitamente tomar tanto el estilo
visual como las funcionalidades nuevas que allí se muestran e incorporarlas a este proyecto.
No hubo acceso a los archivos de imagen originales — el Director General IA transcribió cada
pantalla en detalle (pantalla por pantalla) y esta ampliación se elaboró a partir de esa
transcripción, sin inventar alcance más allá de lo descripto. Esta entrega cubre el lado
**funcional** del pedido (épicas, historias y criterios de aceptación); la réplica del
**estilo visual** de la app hermana es responsabilidad de UX/UI cuando esta ampliación pase a
diseño (Fase 3), y no se anticipa aquí ninguna decisión de paleta, tipografía o layout.

**Actualización 2026-08-06 — decisiones del CEO aplicadas.** El CEO respondió, una por una, las
11 preguntas abiertas que condicionaban esta ampliación (ver "Preguntas abiertas — RESUELTAS"
más abajo) y confirmó además que **todo este alcance (E9–E14, HU-16 a HU-34) forma parte de
v1**, sin diferirse a una release posterior. Eso resuelve dos puntos que habían quedado
documentados como pendientes: se creó la historia **HU-33** (documentos adjuntos por paciente)
para lo que antes era "Autorizaciones Médicas", y el ícono "cambiar de vista" del dashboard
(**HU-27**) quedó resuelto — el backend ya lo soporta (ver nota en esa historia).

**Criterio de priorización — original (2026-08-05) y repriorización (2026-08-06).** El criterio
original priorizó **P1** lo que mejoraba directamente el flujo diario del profesional con
esfuerzo bajo/medio y sin decisiones de negocio pendientes (dashboard, configuración avanzada de
disponibilidad, plantillas recurrentes, ficha de paciente extendida, agendar turno manualmente,
historial clínico enriquecido), y dejó en **P2** lo que era una funcionalidad de negocio nueva y
de mayor tamaño, o que dependía de una decisión de negocio que el CEO todavía no había tomado
(reportes, configuración de pagos/consultorio, privacidad/notificaciones, suscripción paga,
canal WhatsApp).

Con las decisiones del CEO ya tomadas, ese segundo motivo de P2 ("depende de una decisión
pendiente") dejó de aplicar a varias épicas — se repriorizaron a **P1**:

- **E10 (Reportes) → P1.** El alcance ahora es básico y acotado (turnos por estado + monto
  facturado, filtrable por período/profesional/servicio, ver HU-28) — ya no es el alcance
  abierto original que podía incluir ocupación, ausentismo o analítica avanzada. Al ser chico y
  no depender de ninguna definición pendiente, no hay motivo para posponerlo dentro de v1.
- **E11 (Turnario Pro) → P1.** El propio CEO lo nombra explícitamente, junto con la ficha de
  paciente extendida, al confirmar el alcance de v1 (ver decisión de alcance más abajo). Es
  además la única fuente de monetización definida del producto hoy, y ya cuenta con una
  propuesta concreta para avanzar (HU-29).
- **E12 (Configuración de pagos) → P1.** El alcance quedó acotado a un único dato de
  integración (cuenta de Mercado Pago del negocio, HU-30) y está funcionalmente ligado a
  E3/HU-09b (P0): sin esta configuración, la seña cobrada nunca llega a la cuenta correcta del
  negocio — aunque el rollout inicial pueda salir sin seña (ver nota operativa en el Roadmap).

**E13 (Configuración extendida de consultorio) y E14 (Privacidad y seguridad) permanecen en
P2**: su alcance no cambió con las decisiones del CEO, no fueron nombradas explícitamente, son
configuración descriptiva/transversal que no bloquea el flujo core de reserva/cobro, y no surgió
una razón nueva para adelantarlas dentro de la secuencia de v1. HU-34 (credenciales de WhatsApp,
nueva bajo E13) hereda la prioridad P2 de su épica — solo importa una vez que el negocio decide
activar el canal WhatsApp (HU-24).

### E9 — Dashboard del profesional (resumen del día) (P1, nueva)

**HU-27.** Como profesional, quiero ver al abrir la app un dashboard con saludo personalizado,
un resumen del día (pacientes hoy, citas pendientes, completadas) y mis próximas citas con su
estado (por confirmar/confirmada) y una acción rápida para marcarlas como completadas, para
arrancar el día sin tener que navegar a varias pantallas.
- Criterios de aceptación:
  - Las métricas del resumen del día se calculan sobre los turnos del profesional autenticado
    dentro del negocio actualmente seleccionado (ver nota de "cambiar de vista" abajo).
  - "Marcar como completada" actualiza el estado del turno sin abrir el detalle completo.
  - La navegación principal fija (accesos a Horarios, Pacientes, WhatsApp/Notificaciones,
    Configuración) la define UX/UI en el diseño detallado de esta ampliación.
  - **Ícono "cambiar de vista" — RESUELTO Y YA IMPLEMENTADO EN BACKEND (CEO/DBA, 2026-08-06):**
    el CEO confirmó que un mismo profesional/administrador puede pertenecer a más de un negocio,
    y que el ícono alterna **entre esos negocios** (no entre roles Cliente/Profesional). DBA y
    Backend ya generalizaron el modelo de datos de 1:1 a N:M para soportarlo
    (`negocio_administrador`/`negocio_profesional`, ver `03-arquitectura/modelo-datos.md` §2ter)
    — la base de datos y las recomendaciones de query ya están listas. **Estado de esta
    historia: implementada en Backend, falta Mobile** (pantalla/selector de "cambiar de vista" y
    su integración con la forma final del claim de negocio que elija Arquitecto entre las
    opciones ya evaluadas en `modelo-datos.md` §2ter).

### E10 — Reportes y estadísticas (negocio/profesional) (P1, nueva — repriorizada 2026-08-06)

**HU-28.** Como administrador o profesional, quiero acceder a reportes básicos de mi
negocio/agenda, para tomar decisiones basadas en datos en vez de revisar turno por turno.
- Criterios de aceptación:
  - **Alcance básico resuelto (CEO, 2026-08-06):**
    - Métricas: turnos totales, turnos completados, turnos cancelados, y monto facturado (suma
      del precio de servicio de los turnos completados/pagados).
    - Filtrable por período (rango de fechas), por profesional y por servicio.
    - El administrador ve el reporte de todo su negocio (todos los profesionales); un
      profesional ve el reporte acotado a su propia agenda (mismo criterio de privacidad que el
      resto de E5, RN7/D3 — no ve datos de otros profesionales del negocio).
  - Exportable: fuera de este alcance básico — candidato a una iteración posterior (ver
    Roadmap, fast-follow).
  - Métricas más avanzadas (ocupación, ausentismo, pacientes nuevos vs. recurrentes) también
    quedan fuera de este alcance básico — no bloquean esta historia.

### E11 — Suscripción "Turnario Pro" (monetización) (P1, nueva — repriorizada y desbloqueada 2026-08-06)

**HU-29.** Como administrador de negocio, quiero poder suscribirme a un plan pago ("Turnario
Pro") que desbloquee funciones y límites adicionales, para acceder a capacidades avanzadas si
mi negocio las necesita. Esta es una decisión de modelo de negocio (monetización), no solo una
feature técnica.
- Criterios de aceptación:
  - **Modelo resuelto por el CEO (2026-08-06):** freemium por límite de uso — existe un plan
    gratuito con límites de uso, y "Turnario Pro" levanta esos límites y desbloquea funciones
    adicionales.
  - **Propuesta inicial de Product Manager, sujeta a ajuste.** El CEO confirmó el criterio
    general (freemium por límite de uso) pero no dio números exactos — lo siguiente es un punto
    de partida concreto para validar con el CEO antes de construir, no una cifra cerrada:

    | Ítem | Plan gratis | Turnario Pro |
    |---|---|---|
    | Profesionales por negocio | 1 | Ilimitados |
    | Turnos confirmados por mes (por negocio) | 60 (~2/día) | Ilimitados |
    | Reserva, agenda, ficha de paciente (básica + extendida si aplica el rubro, HU-20), historial, notificaciones push/email | Incluido | Incluido |
    | Reportes (E10/HU-28) | No disponible | Incluido |
    | Notificaciones por WhatsApp (HU-24) | No disponible | Incluido |
    | Plantillas de horario recurrente (HU-17) | No disponible (carga día por día) | Incluido |
    | Import/export de pacientes (HU-22) | No disponible | Incluido |

  - **Suscripción por negocio**, no por profesional individual — coherente con que los límites
    (cantidad de profesionales, turnos/mes) se miden a nivel negocio.
  - **Precio propuesto (inicial, sujeto a ajuste):** equivalente a **USD 9/mes por negocio** (o
    su conversión a moneda local vigente), con **20% de descuento** pagando anual. Cifra de
    referencia orientativa para una app de agenda/turnos de nicho similar — a validar con el CEO
    antes de comprometerse comercialmente.
  - **Plataforma (CEO, 2026-08-06):** **solo Android** en v1 — la suscripción se cobra vía
    Google Play Billing. iOS/App Store queda **fuera de v1** (épica futura, no HU activa); no se
    implementa StoreKit en este alcance.
  - Comportamiento exacto al alcanzar el límite del plan gratis (ej. bloquear nuevas reservas al
    llegar a 60 en el mes, avisar con anticipación, o degradar de otra forma) queda para diseño
    detallado de UX — no asumido acá.

### E12 — Configuración de pagos del negocio (P1, nueva — repriorizada 2026-08-06)

**HU-30.** Como administrador, quiero configurar los datos de la cuenta de Mercado Pago de mi
negocio (más allá de si un profesional pide seña o no, HU-04b/RN10), para que los pagos de
seña de mis clientes lleguen a la cuenta correcta.
- Criterios de aceptación:
  - **Alcance básico resuelto (CEO, 2026-08-06):** la configuración se limita a los datos/
    credenciales de la **cuenta de Mercado Pago del negocio** (mecanismo concreto de integración
    a definir por Arquitecto/Integraciones en Fase 3). No incluye otros medios de pago, CBU
    manual ni datos de facturación electrónica en este alcance — quedan fuera de v1.
  - Es una configuración **por negocio** (no por profesional dentro del negocio) — todos los
    profesionales del negocio que cobran seña (HU-04b) usan la misma cuenta de cobro del negocio.
  - **Nota operativa de rollout (CEO, 2026-08-06):** el lanzamiento inicial puede salir con
    todos los servicios configurados "sin seña" (`requiere_sena = false`, RN10, ya soportado)
    mientras se tramita la habilitación de la cuenta de Mercado Pago — no bloquea el lanzamiento
    de v1. Ver Roadmap de producto.

### E13 — Configuración extendida de consultorio (negocio) (P2, extiende HU-00a)

**HU-31.** Como administrador, quiero completar datos operativos de mi negocio más allá del
alta inicial (horario general de atención, dirección detallada, teléfono/contacto, logo o
imagen), para que el cliente vea información completa y actualizada al elegir mi negocio.
- Criterios de aceptación:
  - No reemplaza la disponibilidad por profesional (E2); es información descriptiva del
    negocio como conjunto.
  - **Pregunta abierta:** ¿un negocio puede tener más de una sucursal/dirección, o se mantiene
    la relación 1:1 negocio-consultorio de hoy?

**HU-34 (v1, P2 — nueva, relacionada con HU-24/E7).** Como administrador de negocio, quiero
cargar las credenciales de mi propia cuenta de WhatsApp Business API, para que mis clientes y
profesionales puedan recibir notificaciones de turno por ese canal (HU-24).
- Criterios de aceptación:
  - **Resuelve una parte de la pregunta abierta de WhatsApp (CEO, 2026-08-06):** cada negocio
    gestiona y carga su propia cuenta — no hay una cuenta centralizada de la Factory.
  - Las credenciales (token/cuenta) se guardan por negocio (aislamiento multi-tenant, RN9) —
    nunca se comparten entre negocios.
  - Mientras un negocio no cargue credenciales válidas, el canal WhatsApp permanece inactivo
    para ese negocio sin afectar los demás canales (push/email, HU-24).
  - Igual que la configuración de Mercado Pago (E12/HU-30), es un dato sensible de integración
    — requiere el mismo criterio de manejo seguro de secretos que definan Security/Arquitecto
    (no se guarda en texto plano).

### E14 — Privacidad y seguridad de la cuenta (transversal) (P2, nueva)

**HU-32.** Como cliente o profesional, quiero controlar la visibilidad de mi perfil (público/
solo contactos/privado), si muestro mi estado en línea, y si comparto datos de uso con la
plataforma, para tener control sobre mi privacidad. Es transversal a ambos roles, no una
funcionalidad específica de un negocio.

### Preguntas abiertas de esta ampliación — RESUELTAS (CEO, 2026-08-06)

Las 11 preguntas de abajo fueron respondidas por el CEO, una por una, y ya están aplicadas en
las HU correspondientes en este documento (detalle completo en cada historia). Se conservan acá
como registro de trazabilidad, no como pendientes.

1. **Precedencia de duración de cita (HU-16):** la duración configurada por el profesional
   **reemplaza** a la del servicio (RN3) para todos sus turnos — no es un default sugerido.
   Cambia el comportamiento de HU-09, ya implementada en Backend con la duración del servicio;
   ver nota de modificación en HU-16 y en HU-09.
2. **Alcance de campos de salud (HU-20):** aplican **solo a negocios de rubro salud**, no a
   todos los rubros de la plataforma.
3. **Autorizaciones Médicas:** se resuelve como **HU-33** (documentos adjuntos por paciente —
   subir/ver archivos), sin firma digital ni flujo de consentimiento. Queda una sub-pregunta
   nueva sin resolver: si son privados por profesional o compartidos en el negocio (ver nota en
   HU-33 y callout de "sigue genuinamente abierta" más abajo).
4. **Canal WhatsApp (HU-24):** es un canal **adicional**, no reemplaza push/email. Cada negocio
   carga su propia cuenta/credenciales de WhatsApp Business API (**HU-34**, nueva, E13).
5. **Suscripción "Turnario Pro" (HU-29):** freemium por límite de uso; propuesta inicial de
   Product Manager con valores concretos en HU-29 (sujeta a ajuste). Solo Android en v1.
6. **Ícono "cambiar de vista" del dashboard (HU-27):** alterna entre negocios (un
   profesional/administrador puede pertenecer a más de uno). Ya implementado en Backend (DBA
   generalizó el modelo 1:1 → N:M, ver `03-arquitectura/modelo-datos.md` §2ter); falta Mobile.
7. **Import/export de pacientes (HU-22):** formato CSV/Excel, ambos sentidos, con plantilla
   descargable. **Actualización 2026-08-10:** el Director General IA diferió el desarrollo de
   esta historia hasta que Security revise el manejo de PII en lote — sigue siendo v1, no se
   construye todavía; ver nota completa en la propia HU-22 y en "Notas operativas de rollout"
   del Roadmap.
8. **Reportes (HU-28) y Configuración de pagos del negocio (HU-30):** alcance básico definido
   — reportes: turnos por estado + monto facturado, filtrable por período/profesional/servicio;
   pagos: solo datos de la cuenta de Mercado Pago del negocio.
9. **Toggles de notificación "Mensajes", "Reseñas y Calificaciones", "Promociones y Ofertas"
   (HU-26):** se muestran ya en la UI como placeholder visual — guardan preferencia, sin efecto
   funcional hasta que esas funcionalidades existan. No es un defecto.
10. **Estado activo/inactivo de paciente (HU-19):** **manual**, cargado por el profesional — no
    se calcula automáticamente por antigüedad de última visita.
11. **Seña en turnos agendados manualmente (HU-23):** el profesional **puede omitirla** al
    cargar el turno él mismo, aunque el servicio la tenga configurada.

**Siguen genuinamente abiertas** (no formaban parte de las 11 anteriores, no resueltas por el
CEO en esta ronda):

- En HU-23, si el campo "Hora" del formulario de carga manual (que en la captura acepta texto
  libre con más de un horario de ejemplo, "Ej: 10:00, 14:30") permite agendar varios turnos en
  una sola acción.
- En HU-33 (documentos adjuntos), si son privados por profesional (RN7/D3) o compartidos entre
  los profesionales del negocio — detectada en cruce con Business Analyst, que la dejó registrada
  de forma independiente en `01-requisitos/documento-funcional.md` §7.

Ninguna de las dos bloquea el resto de esta ampliación — solo el diseño detallado de esas dos
historias puntuales en Fase 3.

**Adicionalmente resuelto en esta misma ronda, fuera de las 11 preguntas originales:** el
alcance de v1 queda confirmado como **E0–E14 completo** (nada se difiere a una release
posterior) y la plataforma objetivo de v1 es **solo Android** — ver Roadmap de producto al
inicio de este documento y la repriorización de E10–E12 más arriba.

---

## Siguiente paso

Con las 5 decisiones de negocio originales confirmadas (D1–D5), el alcance base (E0–E8) ya
completó Fases 3–6 (diseño aprobado, backend probado end-to-end, mobile escrito pendiente de
compilar/verificar, y el plan de producción de CTO IA en `03-arquitectura/plan-produccion.md`).

**Sobre la ampliación de 2026-08-05/06 (E9–E14, HU-16 a HU-34):** con las 15 decisiones del CEO
ya aplicadas en este documento (2026-08-06), esta ampliación queda **sin bloqueos de negocio
pendientes** — salvo el ítem menor y genuinamente abierto sobre el campo "Hora" de HU-23, y el
condicionante legal de HU-20 antes de producción (ambos documentados en sus respectivas
historias y en el Roadmap). Puede pasar a Fase 3 (Diseño detallado):

- **Prioridad de diseño técnico:** HU-16 (precedencia de duración) requiere que Arquitecto/
  Backend analicen el impacto de modificar la lógica de cálculo de slots ya implementada y
  probada en HU-05/HU-09 (RN1, RN2, RN3) — tratarla como cambio de alto cuidado con su propia
  batería de regresión, no como una feature nueva de alcance aislado.
- DBA modela las entidades nuevas: Tratamiento y Nota médica (HU-21), Documento adjunto
  (HU-33); y, junto con Backend, define cómo representar la duración de cita del profesional
  (HU-16) y cómo condicionar HU-20 a que el `rubro` del Negocio sea salud de forma consultable.
- Arquitecto/Integraciones definen el mecanismo concreto de integración con WhatsApp Business
  API (HU-24/HU-34) y con Google Play Billing (HU-29/E11 — solo Android en v1).
- UX/UI diseña las pantallas de toda la ampliación, incluyendo el estilo visual de la app
  hermana del CEO (pendiente desde el origen de esta ampliación, 2026-08-05).

---

## E15 — Modo Administrador v1 (Mobile) (P1, nueva 2026-08-14)

**Origen y encargo.** El rol `administrador` tiene 6 endpoints en Backend (`negocios.ts`) que
exigen `requireAuth('administrador')` y hoy no tienen NINGÚN consumidor: `main.dart` (`_Router`,
líneas ~72-76) manda a cualquier usuario con `rol == administrador` directo a `LoginScreen()`,
igual que a un usuario no autenticado, con el comentario "queda para una fase posterior". Esta
sección consolida y prioriza una PRIMERA versión ("modo Administrador v1") para cerrar ese gap,
priorizando lo que Backend ya soporta sin cambios. No rediseña pantallas (responsabilidad de
UX/UI en Fase 3) ni redefine las HU ya redactadas en E0/E1/E10/E11/E13 más arriba — donde esas HU
ya cubren el alcance necesario, esta sección solo señala qué parte se construye en esta ronda y
qué parte queda para otra; donde hace falta una historia nueva (el shell en sí), se agrega acá.

### Mapeo — los 6 endpoints de administrador sin consumidor, HU asociada y cobertura real

| Endpoint (Backend, ya existe) | HU | Cobertura hoy | Decisión v1-Administrador |
|---|---|---|---|
| `POST /negocios/:id/servicios` | HU-03 | Completa: alta (este endpoint) + listado ya público (`GET /negocios/:id/servicios`, ya usado por HU-07) | **Entra en v1 — cero backend nuevo.** |
| `POST /negocios/:id/profesionales` | HU-02 | Alta cubierta; **no existe** `GET /negocios/:id/profesionales` (listado del staff) — el único listado hoy (`GET /negocios/:id/servicios/:servicioId/profesionales`) es público y está acotado a un servicio puntual, no sirve como roster (un profesional recién dado de alta sin servicios propios no aparecería, ver `03-arquitectura/modelo-datos.md` §2ter) | **Entra en v1 — con 1 endpoint nuevo, trivial y simétrico a lo ya construido** (ver nota HU-02 abajo). Único ítem de esta épica que no es "cero backend nuevo". |
| `PATCH /negocios/:id` | HU-31 (y el prometido por HU-00a) | Cubre exactamente `nombre`/`rubro`/`ubicacion` — el resto del alcance original de HU-31 (horario general, dirección detallada, teléfono, logo) no tiene columnas ni endpoint | **Entra en v1, ACOTADA a esos 3 campos.** El resto de HU-31 queda fuera (ver sección de exclusiones). |
| `GET /negocios/:id/plan` | HU-29 | Completa | **Entra en v1 — cero backend nuevo.** |
| `POST /negocios/:id/suscripcion` | HU-29 | Completa (activación simulada/mock, ver comentario del endpoint) | **Entra en v1 — cero backend nuevo.** |
| `PATCH /negocios/:id/suscripcion/cancelar` | HU-29 | Completa | **Entra en v1 — cero backend nuevo.** |

Dos hallazgos adicionales, fuera de la lista de 6 pero relevantes para esta ronda:

- **HU-04** ("Como administrador, quiero asociar servicios a cada profesional") **ya está resuelta
  en producción, pero por un camino distinto al redactado**: la asociación servicio↔profesional la
  hace el propio PROFESIONAL (`POST /profesionales/:id/servicios`, `requireAuth('profesional')`,
  comentario explícito en el código: "HU-04 / HU-04b: el profesional asocia un servicio a su
  agenda..."), no el administrador — y ya tiene pantalla Mobile (`precios_senas_screen.dart`). No
  requiere ninguna acción de esta épica; se deja registrado para que una futura reconciliación de
  Product Manager ajuste el texto de HU-04 a lo realmente implementado, sin tocarlo desde acá.
- **`GET/PATCH /usuario/perfil` y `GET/PATCH /usuario/privacidad`** (HU-32, `usuario.ts`) son
  **rol-agnósticos a propósito** ("tanto 'Editar Perfil' como 'Privacidad y Seguridad' son
  transversales a cualquier rol autenticado (cliente/profesional/administrador)", comentario de
  cabecera del archivo) — ya usados por `editar_perfil_screen.dart`/`privacidad_screen.dart` del
  lado Profesional. Se pueden reusar tal cual para la cuenta del administrador, cero backend
  nuevo — incluido como bonus de bajo costo en el alcance de abajo, no como núcleo de la épica.

### Historias de esta épica

**HU-36 (v1, P1 dentro del backlog global — pero P0 interno de esta épica: nada más de E15 es
alcanzable sin ella).** Como administrador de negocio, quiero ver un panel propio al iniciar
sesión (con acceso a los datos de mi negocio, mis profesionales y mi plan Turnario Pro), para
poder operar mi negocio desde la app en vez de quedar redirigido al login como si no tuviera
cuenta.
- Criterios de aceptación:
  - `main.dart` (`_Router`) deja de mandar `Rol.administrador` a `LoginScreen()` y lo manda a un
    shell propio (nombre/estructura de navegación a definir por UX/UI en Fase 3 — esta historia
    no fija layout, solo el punto de entrada funcional).
  - Si el administrador pertenece a 2+ negocios (`negocio_administrador`, N:M ya soportado,
    `modelo-datos.md` §2ter), reusa el mismo mecanismo ya construido para HU-27 ("cambiar de
    vista": `NegocioMembresia`, `Sesion.entrarANegocio`, `widgets/selector_negocio.dart`) — no se
    diseña un selector nuevo.
  - Backend: ninguno nuevo — se apoya en endpoints ya existentes (`GET /negocios`,
    `GET /negocios/:id`, `GET /negocios/:id/plan`).

**Nota de alcance — HU-31 en v1-Administrador (sin reescribir la HU original de E13, arriba).**
Se construye reutilizando `configuracion_consultorio_screen.dart` (`05-codigo/mobile/lib/screens/
profesional/`), habilitando modo edición cuando la sesión es de rol `administrador`, en vez de
duplicar la pantalla — tal como ya lo dejó anotado el propio doc comment de esa clase y
`memory/proyectos/turnos-profesionales/decisiones.md` (2026-08-12): "el backend ya soporta la
edición completa, solo falta la UI del lado correcto". Acotada a `nombre`/`rubro`/`ubicacion`
(lo único que acepta `PATCH /negocios/:id` hoy); horario general de atención, dirección
detallada, teléfono/contacto y logo (resto del texto original de HU-31) quedan fuera de v1 (ver
exclusiones).

**Nota de alcance — HU-02 en v1-Administrador.** Pantalla de "Profesionales de mi negocio":
alta (formulario email/password/nombre contra `POST /negocios/:id/profesionales`, ya cubre los
casos 201/409 email tomado/402 límite de plan/409 ya activo documentados en el propio endpoint)
+ listado del roster actual. El listado **requiere un endpoint nuevo**,
`GET /negocios/:id/profesionales` (`requireAuth('administrador')`, RN9 vía claim igual que el
resto de este archivo — join trivial `negocio_profesional` + `profesional` + `usuario`, mismo
patrón ya usado en otras lecturas de este mismo router). Se marca como recomendación para
Backend, no como bloqueante de todo E15: si Backend no llega a esta ronda, HU-36/HU-31/HU-03/
HU-29 igual pueden construirse y entregar valor con esta única pantalla acotada a "alta sin
listado" como fallback temporal.

**Nota de alcance — HU-03 en v1-Administrador.** Pantalla de "Servicios de mi negocio": alta
(`POST /negocios/:id/servicios`) + listado (`GET /negocios/:id/servicios`, público, ya en uso
por el flujo de reserva del cliente — HU-07). Sin gaps de backend; el más simple de los 5 flujos
de esta épica.

**Nota de alcance — HU-29 en v1-Administrador.** Pantalla de "Turnario Pro": ver plan actual y
uso (`GET /negocios/:id/plan`), activar (`POST /negocios/:id/suscripcion`, body
`{periodo: 'mensual'|'anual'}`, activación simulada/mock — sin cobro real todavía, ver comentario
del endpoint) y cancelar (`PATCH /negocios/:id/suscripcion/cancelar`). Sin gaps de backend.
**Nota separada, NO incluida en el alcance de esta épica sin aprobación:** el menú de
Configuración del Profesional ya tiene un ítem "Turnario Pro · Suscripción" que hoy apunta a
`ProximamenteScreen` (`configuracion_screen.dart`) pese a que `GET /negocios/:id/plan` también
admite rol `profesional` (solo lectura — activar/cancelar siguen siendo exclusivos de
administrador). Conectar ese ítem existente a una vista de solo lectura de la misma pantalla
sería una mejora barata y coherente, pero **modifica una pantalla del lado Profesional ya
entregada** — por la regla de gobierno de este proyecto ("ningún entregable aprobado se modifica
sin autorización del Director General IA"), queda propuesta acá pero no incluida en el alcance
sin ese visto bueno explícito.

### Pantallas/flujos Mobile de v1-Administrador (resumen para Arquitecto/UX/UI — sin diseño acá)

1. **Shell/Dashboard de Administrador** (HU-36, nueva) — punto de entrada, reemplaza el fallback
   a `LoginScreen` en `main.dart`. Incluye selector multi-negocio si aplica (reuso de HU-27).
2. **Datos del negocio** (HU-31 acotada) — reusa `configuracion_consultorio_screen.dart` en modo
   edición.
3. **Servicios del negocio** (HU-03) — alta + listado, cero backend nuevo.
4. **Profesionales del negocio** (HU-02) — alta ya cubierta; listado sujeto al endpoint nuevo
   recomendado arriba.
5. **Turnario Pro** (HU-29) — ver plan/uso, activar, cancelar.
6. *(Bonus, costo marginal)* **Mi Perfil / Privacidad y Seguridad** (HU-32) — reuso literal de
   `editar_perfil_screen.dart`/`privacidad_screen.dart`, cero backend nuevo (rutas rol-agnósticas).

### Fuera de alcance de v1-Administrador (con motivo)

- **HU-28 (Reportes) — vista agregada de negocio/administrador.** La mitad "profesional"
  (`GET /profesionales/:id/reportes`) ya está construida y tiene pantalla (`reportes_screen.dart`,
  ver `memory/proyectos/turnos-profesionales/decisiones.md`). La vista de negocio completo (todos
  los profesionales a la vez) que pide HU-28 para el administrador **no tiene backend** — el
  propio código de Backend lo deja explícito: "Vista de negocio/administrador (todos los
  profesionales a la vez): HU-28 la pide, pero la consigna de este ciclo la difiere
  explícitamente. Cuando se construya, es un endpoint nuevo (ej. `GET /negocios/:id/reportes`), no
  una extensión de este" (`profesionales.ts`). Requiere backend nuevo — fuera de v1-Administrador.
- **HU-30 (Configuración de pagos — Mercado Pago).** Sin ningún endpoint hoy; su propio texto en
  este backlog dice "mecanismo concreto de integración a definir por Arquitecto/Integraciones en
  Fase 3". Requiere backend nuevo (y una definición de integración que todavía no existe) — fuera
  de v1-Administrador. No bloquea el lanzamiento general (nota operativa ya registrada en el
  Roadmap: se puede lanzar con todos los servicios en `requiere_sena = false`).
- **HU-34 (credenciales de WhatsApp Business).** Sin backend; depende de HU-24 (canal WhatsApp),
  hoy P2/no construido. Fuera de v1-Administrador.
- **Resto del alcance original de HU-31** (horario general de atención, dirección detallada más
  allá de "ubicación", teléfono/contacto, logo o imagen). Sin columnas de datos ni endpoint —
  requiere DBA + Backend antes de poder construirse. Fuera de v1-Administrador.
- **Baja/pausa de un profesional del negocio, o remoción de un servicio.** Ninguno de los dos
  tiene endpoint (`negocios.ts` solo tiene alta para ambos recursos). Fuera de v1-Administrador.
- **Import/export de pacientes (HU-22).** Ya diferida globalmente desde 2026-08-10 (ver Roadmap);
  no es específica de administrador, se reafirma acá solo para que no se confunda con el resto de
  exclusiones de esta épica.
- **Nota relacionada, no una exclusión de esta épica — registro de negocio (HU-00a) sin pantalla
  Mobile.** `POST /auth/registro-negocio` ya existe en Backend, pero ningún cliente Mobile lo
  consume (ni para alta de negocio ni de cliente) — gap ya documentado desde antes de esta ronda
  en `05-codigo/mobile/README.md` ("No hay registro de negocio/cliente desde la app... falta la
  pantalla de registro"). No es uno de los 6 endpoints de este encargo y por eso no se incluye en
  el alcance de v1-Administrador, pero se deja señalado: sin esa pantalla, un administrador nuevo
  no puede autoregistrarse — hoy las cuentas de administrador para pruebas se crean vía API
  directa. No bloquea construir ni demostrar E15 (alcanza con cuentas ya existentes o creadas por
  API), pero si el objetivo es lanzar con negocios reales autoregistrándose, esta pantalla es un
  prerrequisito aparte, no cubierto por esta entrega.

### Preguntas abiertas — a validar con el CEO (Director General IA) antes de implementar

**No se resuelven acá — son decisiones de producto/arquitectura que exceden el alcance de este
Product Manager actuando solo.**

1. **¿"Doble investidura" — un mismo usuario puede ser Profesional Y Administrador a la vez?**
   Pregunta dejada abierta en `04-diseno/mapa-pantallas.md` §5.11 ("a confirmar con Product
   Manager/Arquitecto si el modelo de datos actual lo permite"). **Hallazgo concreto de este
   relevamiento: HOY NO — y no es una limitación de la app, es del modelo de datos.**
   `usuario.rol` es un único valor (`cliente`/`profesional`/`administrador`,
   `03-arquitectura/modelo-datos.md` fila "Usuario"), y la identidad está atada al email de forma
   excluyente: el propio código de `POST /negocios/:id/profesionales` rechaza con 409 el alta de
   un profesional si ese email ya pertenece a un usuario de otro rol ("un email es una única
   identidad con un único rol, no se puede reusar como profesional"). En consecuencia, hoy una
   persona que además de trabajar como profesional es dueña de su propio consultorio necesita DOS
   cuentas (dos emails) — una por rol — y cada una entra a exactamente un shell (Cliente/
   Profesional/Administrador), sin superposición posible. **Propuesta de Product Manager, sujeta a
   aprobación:** (a) para v1-Administrador no hace falta resolver nada — el caso no es alcanzable
   con el modelo actual, cero riesgo de dejar un caso a medio cubrir; (b) SI en el futuro el CEO
   quiere que una misma persona/login sea ambas cosas a la vez, es un cambio de modelo de datos
   (Arquitecto + DBA: por ejemplo, permitir que una identidad `profesional` también aparezca en
   `negocio_administrador`, o generalizar `rol` a multivaluado) que excede esta entrega; de
   aprobarse, la recomendación es modelarlo con el MISMO patrón ya construido para elegir negocio
   (HU-27: "vista activa" con selector — `entrarANegocio`/`selector_negocio.dart`), es decir
   "entrar como Administrador" o "entrar como Profesional" como una elección de sesión más, nunca
   una pantalla fusionada. **Esto queda marcado como pregunta abierta para que el Director General
   IA la valide con el CEO — Product Manager no la resuelve unilateralmente.**
2. **¿El administrador debe tener acceso al historial de clientes/pacientes?** Pregunta abierta
   desde el documento funcional original (`01-requisitos/documento-funcional.md` §6, punto 2:
   "A7/D3 dejan al administrador sin acceso al historial por defecto — confirmar si es correcto"),
   nunca revisitada en ninguna de las rondas de decisiones posteriores del CEO. **Propuesta de
   Product Manager, sujeta a aprobación:** mantener el default actual (administrador SIN acceso
   directo a la ficha/historial de un cliente puntual) para v1-Administrador — solo ve agregados
   de negocio (HU-28, cuando se construya: turnos totales/completados/cancelados y monto
   facturado, sin datos de un cliente en particular). Motivos: (1) es el status quo ya documentado
   y ya reforzado técnicamente por Security en HU-20 (scope `(profesional_id, cliente_id)`,
   `07-seguridad/informe-seguridad.md` adenda 2026-08-10) — cambiarlo requeriría RLS/backend
   nuevo, contra el criterio de esta épica de no abrir otra ronda de Backend; (2) es la opción más
   conservadora en privacidad, mismo criterio que Security ya aplicó a la pregunta análoga de
   HU-33; (3) es consistente con el propio criterio ya resuelto por el CEO para HU-28 ("el
   administrador ve el reporte de todo su negocio", en agregado — no historial individual). **Esto
   queda marcado como pregunta abierta para que el Director General IA la valide con el CEO** — si
   la respuesta es "sí debe verlo", es alcance nuevo de backend para una ronda futura, no de
   v1-Administrador.

### Siguiente paso de esta épica

Con las 2 preguntas de arriba resueltas por el CEO (o confirmadas como "no bloquean, se mantiene
el default propuesto"), E15 puede pasar a Fase 3: UX/UI diseña las 5-6 pantallas listadas arriba
(puede reusar layout/lenguaje visual ya aprobado para `ProfesionalShell`/`ConfiguracionScreen`
como punto de partida, no un sistema visual nuevo); Backend evalúa si suma el único endpoint
nuevo recomendado (`GET /negocios/:id/profesionales`) a esta misma ronda o si Mobile arranca con
el fallback "alta sin listado" mientras tanto; Arquitecto confirma que el patrón de shell/
selector de HU-27 es reusable tal cual para el rol administrador antes de que Mobile empiece.
