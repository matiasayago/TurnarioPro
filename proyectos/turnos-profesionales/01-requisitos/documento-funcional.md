# Documento Funcional — Turnos Profesionales

**Proyecto:** TURNOS-2026-001
**Rol:** Business Analyst
**Fase:** 2 — Descubrimiento
**Entradas:** Brief del CEO (ver `proyectos/turnos-profesionales/00-resumen.md`)

## 1. Alcance y decisiones confirmadas por el CEO

El CEO respondió las preguntas abiertas de la primera versión de este documento. Decisiones
vigentes:

- **D1 (confirmado — reemplaza A1). Multi-negocio.** La plataforma es multi-tenant: varios
  negocios/comercios independientes, cada uno con sus propios profesionales, servicios y
  clientes, conviven en la misma app. "Seleccionar el servicio o consultorio" ahora se
  interpreta en dos niveles: el cliente primero encuentra/selecciona el **negocio o
  consultorio** (entre varios negocios dados de alta en la plataforma) y luego el servicio
  dentro de ese negocio. Esto es la decisión de mayor impacto en arquitectura y modelo de
  datos — introduce una entidad **Negocio (tenant)** como raíz de aislamiento de datos.
- **D2 (confirmado — reemplaza A4). Pago/seña configurable por profesional.** El cobro de
  seña al reservar **no es una regla global**: cada profesional configura si su servicio
  requiere seña/pago anticipado o no. Un mismo negocio puede tener profesionales que cobran
  seña y otros que no.
- **D3 (confirmado — reemplaza RN7 abierta). Historial privado por profesional.** El
  historial de visitas de un cliente lo ve únicamente el profesional que lo atendió; no se
  comparte entre profesionales del mismo negocio, ni siquiera con el administrador (salvo que
  una fase futura defina permisos de administrador — no incluido en este alcance).
- **D4 (confirmado — reemplaza A6). Notificaciones en el MVP.** Confirmaciones y recordatorios
  de turno son parte del alcance del MVP, no de una fase futura.
- **D5 (confirmado — reemplaza A5). Próximo disponible, sin lista de espera.** Si no hay
  horarios en el rango consultado, se muestra el próximo horario libre. No hay lista de
  espera en este alcance.

### Ampliación de alcance (2026-08-05) — funcionalidades de una app hermana del CEO

El CEO compartió capturas de otra app de su propiedad (turnos/citas, ya construida, aún no en
producción) y autorizó tomar tanto el estilo visual como las funcionalidades nuevas que
muestra. Esto agrega las siguientes decisiones sobre el alcance funcional (detalle de
historias en `02-backlog/backlog.md`, sección "Ampliación del backlog"):

- **D6 (confirmado — matiza A2/RN3). Configuración de agenda por profesional.** Además de la
  duración fija por servicio (RN3), el profesional puede configurar de forma general su propia
  duración de cita, máximo de turnos por día y anticipación de reserva (hoy son valores fijos/
  no configurables). También puede definir plantillas de horario recurrentes ("replicar" varias
  semanas o meses hacia adelante) en vez de cargar disponibilidad día por día. **Precedencia
  resuelta por D10 (2026-08-06):** la duración configurada por el profesional prevalece sobre
  la del servicio (RN3) cuando ambas existen — ver D10 más abajo y RN3/RN11 en §3 (este párrafo
  decía antes "queda pendiente de definir la precedencia").
- **D7 (confirmado). Ficha de paciente extendida.** El perfil de un cliente puede incluir datos
  adicionales: fecha de nacimiento, género, dirección, alergias, y un contacto de emergencia
  (nombre, teléfono, relación), además de los datos básicos (nombre, email, teléfono). Al
  incorporar datos de salud, requiere el mismo nivel de protección que el historial de visitas
  (RN7) y revisión de Security antes de habilitarse en producción. **Alcance por rubro resuelto
  por D11 (2026-08-06):** solo aplica a negocios de rubro salud, con un gate legal adicional
  (Ley 25.326) — ver D11 más abajo y RN15 en §3 (este párrafo decía antes "queda pendiente
  confirmar si estos campos aplican a todos los rubros...").
- **D8 (confirmado). Historial clínico como entidades propias.** Además del historial de
  turnos, el profesional puede registrar tratamientos y notas médicas asociados a un paciente
  que no están atados a un turno puntual. Mantienen la misma privacidad por profesional que el
  historial de visitas (RN7/D3): no se comparten entre profesionales del mismo negocio.
- **D9 (confirmado). Alta manual de turnos por el profesional.** Un turno puede originarse
  tanto por autoreserva del cliente (CU4) como por carga manual del profesional para un
  paciente (nuevo CU6, ej. turno pedido por teléfono o presencial sin reserva previa). En ambos
  casos rigen las mismas reglas de no solapamiento y duración (RN1, RN2, RN3).

Otras funcionalidades observadas en las capturas (dashboard del profesional, notificaciones por
WhatsApp, reportes y estadísticas, suscripción paga "Turnario Pro", configuración de pagos y de
consultorio a nivel negocio, privacidad/notificaciones granulares) se incorporaron al backlog
(épicas E9–E14). **Actualización 2026-08-06:** las que dependían de definiciones de negocio del
CEO ya tienen decisión confirmada — ver D12 (Autorizaciones Médicas, que en la versión anterior
de este documento se había dejado explícitamente sin incorporar por alcance ambiguo), D13
(WhatsApp), D14/D15 (Turnario Pro), D18 (reportes y configuración de pagos) más abajo. El
dashboard del profesional (E9/HU-27) y la configuración extendida de consultorio (E13/HU-31) no
estaban entre las 16 decisiones de esta ronda y siguen sin cambios respecto de lo ya incorporado
al backlog (incluidas las preguntas menores propias de cada historia puntual, fuera del alcance
de este documento).

Supuestos que se mantienen sin cambios (no formaban parte de las 5 preguntas priorizadas):

- **A2.** Cada servicio tiene una duración fija (usada para calcular slots de calendario) y
  un precio de referencia informativo.
- **A3.** El cliente puede cancelar o reprogramar un turno hasta una ventana mínima antes del
  horario reservado (valor por defecto propuesto: 2 horas); el profesional puede bloquear
  horarios en cualquier momento. *(Sigue abierto a confirmación si 2 horas es el valor
  correcto — no bloquea el diseño, es parametrizable.)*
- **A7.** Existe un rol de administración por negocio (da de alta profesionales y servicios
  de su propio negocio; no ve datos de otros negocios — reforzado por D1).

### Decisiones D10–D21 (2026-08-06) — respuestas del CEO a las preguntas abiertas de §7

El CEO respondió, una por una, las 11 preguntas que había dejado abiertas la ampliación de
2026-08-05 (§7 de este documento), más 5 preguntas relacionadas del plan de producción de
CTO IA con implicancia funcional (`03-arquitectura/plan-produccion.md` §10). Numeración
continua desde D9.

- **D10 (confirmado — AMENDA RN3 directamente; resuelve §7 punto 1 y la precedencia pendiente
  de D6/RN11). Precedencia de duración de cita: el profesional manda siempre.** La duración
  general que el profesional configura en su agenda (D6/RN11) **reemplaza** la duración del
  servicio (RN3) para **todos** sus turnos, sin importar cuál sea el servicio — no es una
  excepción puntual por servicio, es la regla general una vez que el profesional configuró su
  propia duración. Ver RN3 (amendada) y RN11 (actualizada) en §3.
  - **CAMBIO DE COMPORTAMIENTO sobre lógica ya implementada y probada — no es solo una
    definición nueva.** RN3, hasta hoy, dice "la duración del turno la determina el servicio
    elegido, no el cliente", y es exactamente la lógica que Backend ya implementó y probó:
    `calcularSlotsDisponibles` (`05-codigo/backend/src/dominio/disponibilidad.ts`) calcula
    `duracionMs` únicamente a partir de `servicio.duracion_min`, sin mirar ninguna
    configuración del profesional, y la reutilizan tanto `GET /profesionales/:id/slots` como
    `POST /turnos` para calcular y validar slots. Esta decisión **modifica un comportamiento
    que ya funciona distinto hoy** en el backend construido y probado (Fase 4) — a diferencia
    de la mayoría de D10–D21, que son definiciones sobre funcionalidad todavía no construida.
    Implementarla requiere, como mínimo: (a) el campo de duración general configurable por
    profesional que D6/RN11 ya había anticipado (no existe hoy en el modelo de datos — a
    confirmar con DBA), (b) cambiar `calcularSlotsDisponibles` para preferir esa duración
    sobre `servicio.duracion_min` cuando esté configurada, y (c) revisar los tests existentes
    que hoy validan la regla vieja (ej. `scripts/test-rn1-disponibilidad-y-solapamiento.mjs`).
    **No implementado en esta entrega** — queda para un ciclo posterior de Backend/DBA; este es
    un documento funcional, no toca código.
- **D11 (confirmado — acota D7/RN12; resuelve §7 punto 2). Campos de salud: solo rubros de
  salud.** Los campos ampliados de la ficha de paciente que son datos de salud/sensibles
  (fecha de nacimiento, alergias, contacto de emergencia — D7/RN12) **no aplican a todos los
  rubros de la plataforma** (la plataforma es multi-rubro, D1) — solo a negocios cuyo rubro sea
  de salud. Ver RN15 (nueva, §3).
  - **Pregunta de implementación para DBA (no se resuelve en este documento).** Hoy
    `negocio.rubro` es texto libre (ej. "Salud" en los ejemplos usados hasta ahora en este
    proyecto) — hace falta un criterio determinístico para decidir "es rubro de salud": por
    ejemplo, una lista cerrada de rubros válidos, o un flag booleano dedicado en `negocio`
    (ej. `es_rubro_salud`). Queda como pregunta de implementación para DBA; este documento no
    elige entre las dos opciones.
  - **Gate legal (decisión del CEO, aplica también a D21 más abajo).** Antes de habilitar
    estos campos en producción con datos reales de salud, el CEO va a consultar a un abogado
    sobre la Ley 25.326 de Protección de Datos Personales (datos sensibles). Esta decisión se
    puede **diseñar y construir** con normalidad — no bloquea a DBA/Arquitecto/Backend — pero
    **no debe salir a producción con datos reales de salud** hasta que exista esa confirmación
    legal.
- **D12 (confirmado; resuelve §7 punto 3). "Autorizaciones Médicas" = documentos adjuntos por
  paciente.** Se resuelve como archivos que el profesional sube y consulta contra la ficha de
  un paciente (ej. estudios, órdenes médicas, autorizaciones de obra social escaneadas) — **sin
  firma digital y sin flujo de consentimiento**: son documentos de consulta/respaldo, no
  documentos con validez legal de firma. Entra al alcance por primera vez con esta decisión —
  la versión anterior de este documento lo había dejado explícitamente afuera por alcance
  ambiguo. Ver RN16 (nueva, §3), que además deja registrada una pregunta nueva sobre a quién es
  visible cada documento (§7, "Preguntas nuevas").
- **D13 (confirmado; resuelve §7 punto 4). Canal WhatsApp: adicional, con cuenta propia por
  negocio.** WhatsApp es un **canal adicional** de notificación — no reemplaza push/email (D4,
  ya en alcance). **Cada negocio gestiona y paga su propia cuenta de WhatsApp Business API**
  (no es una cuenta centralizada de la Factory). **Dato nuevo a nivel negocio, para DBA:** la
  configuración de un negocio necesita guardar sus propias credenciales/número de WhatsApp
  Business — ver glosario (§5, "Credencial WhatsApp del negocio") y RN17 (nueva, §3).
- **D14 (confirmado; resuelve §7 punto 5 — parcialmente, ver D15). Suscripción "Turnario Pro":
  freemium por límite de uso.** Modelo freemium: uso gratuito hasta cierto límite, la versión
  Pro desbloquea uso ilimitado más funciones avanzadas. **Los valores exactos del límite
  gratuito, el precio y qué funciones son "avanzadas" los define Product Manager en el
  backlog** (`02-backlog/backlog.md`), no este documento.
- **D15 (confirmado; resuelve la segunda mitad de §7 punto 5 y la pregunta 4 del plan de
  producción de CTO IA, `03-arquitectura/plan-produccion.md` §10). Plataformas: solo Android
  por ahora.** El lanzamiento — tanto el general como la suscripción paga (D14) — es **solo
  Android (Google Play)**; iOS/App Store queda para una release posterior.
- **D16 (confirmado — excepción explícita a RN10; resuelve §7 punto 7). Seña omitible en
  turnos agendados manualmente por el profesional (CU6).** A diferencia de la autoreserva del
  cliente (CU4), donde RN10 aplica siempre, cuando el **profesional** carga un turno
  manualmente (CU6, D9) puede decidir caso por caso si cobra la seña configurada para ese
  servicio o no. Ver RN18 (nueva, §3) y CU6 actualizado (§4).
- **D17 (confirmado; resuelve §7 punto 8). Import/export de pacientes: CSV/Excel genérico.**
  Formato CSV/Excel genérico, disponible en ambos sentidos (import y export), con una plantilla
  descargable provista por la plataforma para el import.
- **D18 (confirmado; resuelve §7 punto 9). Reportes y Configuración de Pagos: alcance básico.**
  **Reportes:** turnos totales/completados/cancelados y monto facturado por período (semana/
  mes), desglosado por profesional y por servicio. **Configuración de pagos del negocio:** solo
  los datos necesarios para cobrar señas — la cuenta de Mercado Pago del negocio. Ver glosario
  §5.
- **D19 (confirmado; resuelve §7 punto 10). Toggles de notificación "Mensajes", "Reseñas y
  Calificaciones", "Promociones y Ofertas": placeholder visual.** Se muestran ya en la UI como
  funcionalidad futura, aunque mensajería in-app, reseñas y marketing no existen todavía como
  funcionalidades reales en este alcance. El toggle guarda la preferencia del usuario, pero no
  activa ningún comportamiento real todavía. Ver RN19 (nueva, §3) — es explícito para que QA no
  lo reporte como defecto al no observar ningún efecto real detrás del toggle.
- **D20 (confirmado; resuelve §7 punto 11). Estado activo/inactivo de paciente: manual.** Lo
  marca el profesional a mano; no se calcula automáticamente por antigüedad de la última
  visita. Ver RN20 (nueva, §3).
- **D21 (confirmado — decisión propia, relacionada con D11/D14/D15 y con el plan de producción
  de CTO IA, `03-arquitectura/plan-produccion.md` §3/§10 pregunta 1). Alcance de v1 incluye la
  ficha de paciente extendida y "Turnario Pro" (antes llamado "V4").** El CEO confirmó que el
  lanzamiento v1 **sí incluye** lo que el plan de producción de CTO IA y el roadmap del backlog
  venían llamando "V4" — ficha de paciente extendida (D7/D11/RN12/RN15) y suscripción "Turnario
  Pro" (D14/D15) — y **no queda diferido** a una release posterior. Ya estaba implícito en D11
  y D14 de arriba; se deja explícito acá como decisión propia porque cambia la planificación de
  release que el plan de producción de CTO IA había asumido como escenario de trabajo
  (v1 = solo E0–E8).

Notas de cierre de esta tanda de decisiones:

- **RN9 y el ícono "cambiar de vista" (§7 punto 6): confirmado antes de esta tanda, no genera
  un número D nuevo.** El CEO ya había confirmado el 2026-08-06, previo a esta ronda de 16
  respuestas, que un profesional o administrador **puede pertenecer a más de un negocio** —
  resuelve §7 punto 6. Esa confirmación no suma un D nuevo acá porque no se decidió en esta
  ronda: ya está **implementada** a nivel de modelo de datos (tablas de asociación N:M
  `negocio_administrador`/`negocio_profesional`, que generalizan el 1:1 anterior) — ver
  `03-arquitectura/modelo-datos.md` §2ter para el detalle completo, incluidas las
  recomendaciones para que Backend reconstruya los endpoints afectados (trabajo pendiente de
  Backend, no de este documento). Lo que sí correspondía a este documento — y se hace acá — es
  corregir **RN9** (§3), que había quedado con texto desactualizado ("un profesional...
  pertenece a un único negocio"), además de los actores (§2) y el glosario (§5), que asumían lo
  mismo.
- **Mercado Pago (contexto de rollout, no es una regla de negocio nueva).** El CEO va a lanzar
  con **todos los servicios configurados "sin seña"** mientras tramita la cuenta de Mercado
  Pago habilitada para cobrar. RN10 ya permite `requiere_sena = false` por servicio, así que
  esto no requiere una decisión D nueva — se deja registrado acá solo como contexto operativo
  para Arquitecto/DevOps al planificar el rollout (relacionado con la pregunta 3 del plan de
  producción de CTO IA, `03-arquitectura/plan-produccion.md` §10).
- La autorización de CI de Mobile con Flutter SDK real (pregunta 6 del mismo plan de
  producción) no tiene implicancia funcional — no se documenta en este archivo.

## 2. Actores / roles de usuario

| Rol | Descripción |
|---|---|
| **Cliente** | Usuario final que busca y reserva turnos. |
| **Profesional** | Presta el servicio; gestiona su disponibilidad, ve sus clientes y el historial de visitas. Puede pertenecer a más de un negocio (RN9 corregida, §3). |
| **Administrador del negocio** | (Supuesto A7) Da de alta/baja profesionales, servicios y consultorios; no necesariamente atiende turnos. Puede administrar más de un negocio (RN9 corregida, §3). |

## 3. Reglas de negocio

- **RN1.** Un turno solo puede reservarse dentro de un bloque de disponibilidad publicado por
  el profesional para ese servicio.
- **RN2.** Dos turnos del mismo profesional no pueden solaparse en el tiempo.
- **RN3 (AMENDADA — D10, 2026-08-06; cambio de comportamiento sobre lógica ya implementada, ver
  nota).** La duración del turno la determina el servicio elegido, **salvo que el profesional
  tenga configurada una duración general propia (D6/RN11), en cuyo caso esa duración prevalece
  sobre la del servicio para todos los turnos de ese profesional** (D10), sin importar cuál sea
  el servicio. El cliente sigue sin poder elegir la duración en ningún caso — eso no cambió.
  - **Texto original (vigente hasta el 2026-08-05):** "La duración del turno la determina el
    servicio elegido, no el cliente."
  - **Impacto técnico (detalle completo en D10, §1):** esta no es una regla nueva sobre algo
    por construir — es una modificación de un comportamiento **ya implementado y probado** en
    Backend. `calcularSlotsDisponibles` (`05-codigo/backend/src/dominio/disponibilidad.ts`) hoy
    calcula la duración de cada slot únicamente a partir de `servicio.duracion_min`, sin mirar
    ninguna configuración del profesional. Aplicar esta regla requiere cambios de modelo de
    datos (DBA) y de código (Backend) fuera del alcance de esta entrega.
- **RN4.** Un profesional puede ofrecer uno o más servicios; un servicio puede ser ofrecido
  por uno o más profesionales (relación N:M).
- **RN5.** El profesional puede definir excepciones puntuales a su disponibilidad general
  (feriados, licencias, bloqueos de agenda) que anulan slots ya publicados pero sin turno
  reservado.
- **RN6.** Un turno reservado no puede eliminarse por una excepción de disponibilidad sin
  antes notificar y ofrecer reprogramación al cliente.
- **RN7.** El historial de visitas de un cliente es visible únicamente para el profesional
  que lo atendió (D3). No se comparte entre profesionales del mismo negocio.
- **RN8.** Cancelaciones y reprogramaciones fuera de la ventana mínima definida (supuesto A3)
  requieren contacto directo con el negocio (fuera del flujo automático de la app en el MVP).
- **RN9 (CORREGIDA — 2026-08-06, ver nota).** Cada negocio opera de forma aislada: un
  **servicio, turno, o el dato de un cliente dentro de un negocio** pertenece a un único
  negocio; ningún dato de un negocio es visible desde otro (D1). **Un profesional o
  administrador, en cambio, SÍ puede pertenecer a más de un negocio a la vez** (ej. un
  profesional que atiende en dos consultorios, o un administrador que gestiona varias
  sucursales) — cada membresía es independiente, y el aislamiento de datos (turnos, clientes,
  historial) sigue aplicando estrictamente por negocio incluso para un profesional que trabaja
  en varios: ver el turno/cliente/historial de un negocio no da visibilidad sobre los de otro
  negocio donde ese mismo profesional también trabaja.
  - **Texto original (vigente hasta el 2026-08-05):** "Cada negocio opera de forma aislada: un
    profesional, servicio, cliente o turno pertenece a un único negocio; ningún dato de un
    negocio es visible desde otro (D1)."
  - **Nota de corrección — no es una decisión nueva de esta tanda:** formaliza en este
    documento una decisión que el CEO ya había confirmado el 2026-08-06, previa a esta ronda de
    16 respuestas (resuelve §7 punto 6, "ícono cambiar de vista"), y que ya está implementada a
    nivel de modelo de datos — ver `03-arquitectura/modelo-datos.md` §2ter (tablas de
    asociación N:M `negocio_administrador`/`negocio_profesional`, que generalizan el 1:1
    anterior). Ver también §2 (actores) y §5 (glosario, entrada "Profesional"), actualizados en
    consecuencia.
- **RN10.** Cada profesional configura, por servicio, si requiere seña/pago anticipado para
  confirmar la reserva (D2). Si lo requiere, el turno queda en estado "pendiente de pago"
  hasta confirmarse (el mecanismo de pago concreto lo define Arquitecto/CTO IA en Fase 3).
- **RN11 (D6).** Además de la duración fija por servicio (RN3), el profesional puede
  configurar de forma general su propia duración de cita, máximo de turnos por día y
  anticipación de reserva. **Precedencia resuelta (D10, 2026-08-06):** cuando el profesional
  tiene esa duración general configurada, prevalece sobre la duración del servicio (RN3) para
  todos sus turnos — ya no está pendiente de definir (este párrafo decía antes "precedencia
  pendiente de definir"; ver RN3 amendada arriba y D10 en §1).
- **RN12 (D7).** La ficha de un paciente puede incluir datos de salud/sensibles (fecha de
  nacimiento, alergias, contacto de emergencia) además de los datos básicos de contacto. Estos
  datos requieren el mismo nivel de protección que el historial de visitas (RN7) y revisión de
  Security antes de exponerse en producción.
- **RN13 (D8).** Los tratamientos y notas médicas asociados a un paciente son visibles
  únicamente para el profesional que los registró, con el mismo criterio de privacidad que el
  historial de visitas (RN7/D3).
- **RN14 (D9).** Un turno puede originarse tanto por autoreserva del cliente (CU4) como por
  carga manual del profesional (CU6); en ambos casos rigen las mismas reglas de no
  solapamiento y duración (RN1, RN2, RN3) — la vía de creación no exime ninguna garantía.
- **RN15 (D11) — acota RN12 a negocios de rubro salud.** Los campos de salud/sensibles de la
  ficha de paciente (RN12: fecha de nacimiento, alergias, contacto de emergencia) aplican
  únicamente a negocios cuyo rubro sea de salud — no a todos los rubros de la plataforma (D1,
  multi-rubro). Queda pendiente para DBA definir el criterio determinístico para reconocer
  "rubro de salud" (lista cerrada de rubros o flag booleano en `negocio`); no se resuelve en
  este documento (ver D11, §1).
  - **Gate legal (D11):** además, estos campos no deben salir a producción con datos reales de
    salud hasta que el CEO confirme con un abogado el cumplimiento de la Ley 25.326 — se pueden
    diseñar y construir antes de esa confirmación, no lanzar con datos reales sin ella.
- **RN16 (D12).** El profesional puede adjuntar y consultar documentos asociados a un paciente
  ("Autorizaciones Médicas": estudios, órdenes médicas, autorizaciones de obra social
  escaneadas, entre otros), sin firma digital ni flujo de consentimiento — son archivos de
  consulta/respaldo, sin validez legal de documento firmado.
  - **Pregunta abierta nueva (no resuelta por el CEO en esta tanda; no bloquea el diseño básico
    de subir/listar archivos — ver §7):** ¿estos documentos son visibles solo para el
    profesional que los sube (mismo criterio de privacidad que el historial de visitas, RN7, y
    las notas médicas, RN13), o para cualquier profesional/administrador del negocio?
- **RN17 (D13).** El canal de notificación por WhatsApp es adicional a los ya implementados en
  el MVP (push/email, D4) — no los reemplaza. Cada negocio gestiona y paga su propia cuenta de
  WhatsApp Business API — no es una cuenta centralizada de la Factory ni de la plataforma.
- **RN18 (D16) — excepción explícita a RN10, solo aplica en CU6.** Cuando el profesional
  agenda un turno manualmente (CU6, D9) para un servicio con seña configurada (RN10), puede
  decidir caso por caso si la cobra o la omite. En la autoreserva del cliente (CU4), RN10
  aplica siempre, sin esta excepción — omitir la seña es una facultad exclusiva del flujo de
  carga manual del profesional.
- **RN19 (D19).** Los toggles de notificación "Mensajes", "Reseñas y Calificaciones" y
  "Promociones y Ofertas" se muestran en la UI como funcionalidad futura: guardan la
  preferencia elegida por el usuario, pero no activan ningún comportamiento real todavía
  (mensajería in-app, reseñas/calificaciones y marketing no existen en este alcance). No es un
  defecto que el toggle no tenga efecto observable — es el comportamiento esperado hasta que
  esas funcionalidades se construyan.
- **RN20 (D20).** El estado activo/inactivo de un paciente lo marca manualmente el
  profesional; no se calcula ni actualiza automáticamente por antigüedad de la última visita.

## 4. Casos de uso

### CU1 — Profesional define su disponibilidad
- **Actor:** Profesional.
- **Precondición:** El profesional está autenticado y tiene al menos un servicio asignado.
- **Flujo principal:**
  1. El profesional accede a su calendario.
  2. Define bloques de disponibilidad recurrentes (ej. días y horarios semanales) por servicio.
  3. El sistema genera los slots reservables según la duración de cada servicio.
- **Flujos alternativos:**
  - El profesional agrega una excepción puntual (bloqueo/feriado) → el sistema retira los
    slots libres afectados y advierte si hay turnos ya reservados en ese rango (RN6).

### CU2 — Profesional ve sus clientes y el historial de visitas
- **Actor:** Profesional.
- **Precondición:** El profesional tiene al menos un turno atendido.
- **Flujo principal:**
  1. El profesional accede al listado de sus clientes.
  2. Selecciona un cliente y ve el historial de visitas (fecha, servicio, notas si existieran).
- **Flujo alternativo:** Cliente nuevo sin historial previo → se muestra listado vacío.

### CU3 — Cliente descubre y elige un negocio
- **Actor:** Cliente.
- **Precondición:** Ninguna (puede ocurrir antes de registrarse).
- **Flujo principal:**
  1. El cliente busca o navega el listado de negocios/consultorios disponibles en la plataforma.
  2. Selecciona un negocio.
  3. El sistema muestra los servicios que ofrece ese negocio (RN9 — datos aislados por negocio).
- **Nota:** el mecanismo de búsqueda (por ubicación, categoría, nombre) lo define UX/UI en Fase 3.

### CU4 — Cliente reserva un turno
- **Actor:** Cliente.
- **Precondición:** El cliente eligió un negocio (CU3) y está registrado (o se registra en el
  flujo, según defina UX/UI).
- **Flujo principal:**
  1. El cliente selecciona el servicio dentro del negocio elegido.
  2. El cliente selecciona un profesional (filtrado por servicio elegido).
  3. El sistema muestra los horarios disponibles del profesional para ese servicio.
  4. El cliente selecciona un horario.
  5. Si el profesional requiere seña para ese servicio (RN10), el sistema solicita el pago
     antes de confirmar; si no, confirma directamente.
  6. El sistema bloquea el slot y confirma el turno (RN1, RN2).
  7. El sistema dispara la notificación de confirmación (D4).
- **Flujos alternativos:**
  - No hay horarios disponibles en los próximos días → se muestra el próximo disponible (D5).
  - Dos clientes intentan reservar el mismo slot simultáneamente → el sistema debe garantizar
    que solo uno de los dos obtenga la reserva (requisito no funcional para Arquitecto/Backend).
  - El pago de la seña falla o se abandona → el turno no se confirma y el slot permanece libre.

### CU5 — Cliente cancela o reprograma un turno
- **Actor:** Cliente.
- **Precondición:** El cliente tiene un turno reservado a futuro.
- **Flujo principal:**
  1. El cliente selecciona el turno desde su listado de reservas.
  2. Cancela o solicita reprogramar (elige nuevo horario disponible del mismo profesional/servicio).
  3. El sistema libera el slot original y, si aplica, reserva el nuevo.
- **Flujo alternativo:** Intento fuera de la ventana mínima de cancelación (RN8) → el sistema
  informa que debe contactar al negocio directamente.

### CU6 — Profesional agenda un turno manualmente para un paciente (D9, nuevo)
- **Actor:** Profesional.
- **Precondición:** El profesional está autenticado y el paciente ya existe en su cartera (o
  se da de alta en el mismo flujo, a definir en diseño detallado).
- **Flujo principal:**
  1. El profesional selecciona un paciente desde su listado (HU-10/HU-19).
  2. Elige servicio (editable, con el servicio predeterminado del paciente como sugerencia),
     fecha, hora y notas adicionales.
  3. El sistema aplica las mismas reglas de no solapamiento y duración que en la autoreserva
     del cliente (RN1, RN2, RN3 — incluida la precedencia de D10 si el profesional tiene
     configurada su propia duración general —, RN14).
  4. **Si el servicio elegido tiene seña configurada (RN10), el profesional decide en este
     turno puntual si la cobra o la omite** (D16/RN18) — a diferencia de CU4 (autoreserva del
     cliente), donde RN10 aplica siempre sin excepción.
  5. El sistema confirma el turno y dispara la notificación correspondiente (D4/E7).
- **Flujos alternativos:**
  - El profesional omite la seña pese a que el servicio la tiene configurada (paso 4) → el
    turno se confirma directamente, sin pasar por el estado "pendiente de pago" de RN10, aun
    cuando la autoreserva del cliente para ese mismo servicio sí lo exigiría.
- **Nota:** a diferencia de CU4, en este flujo la decisión de cobrar seña la toma el
  profesional turno por turno (D16/RN18) — no es una configuración fija por servicio como en la
  autoreserva del cliente.

## 5. Glosario de entidades de negocio

*(Sin diseño de modelo de datos — corresponde a DBA en Fase 3)*

- **Negocio (tenant)** — comercio/consultorio dado de alta en la plataforma; raíz de
  aislamiento de datos (D1, RN9). Tiene profesionales (N:M, RN9 corregida), servicios y
  clientes propios. El campo `rubro` es texto libre hoy; determina si aplican los campos de
  salud de la ficha de paciente (D11/RN15) — falta definir con DBA el criterio determinístico
  para "rubro de salud" (no resuelto en este documento). A partir de D13 también guarda sus
  propias credenciales de WhatsApp Business (ver "Credencial WhatsApp del negocio" más abajo) y
  sus datos de cobro de seña (ver "Cuenta de Mercado Pago del negocio").
- **Cliente** (llamado "Paciente" en las pantallas de la app hermana cuando el rubro es de
  salud) — persona que reserva turnos; puede reservar en más de un negocio. Datos básicos:
  nombre, email, teléfono. Datos ampliados (D7/RN12, opcionales; aplican solo a negocios de
  rubro salud — D11/RN15, sujeto al gate legal de Ley 25.326 antes de producción con datos
  reales, ver D11): fecha de nacimiento, género, dirección, alergias, contacto de emergencia
  (nombre, teléfono, relación), notas libres del profesional, estado activo/inactivo (D20/RN20
  — manual, lo marca el profesional).
- **Profesional** — persona que presta servicios y gestiona su disponibilidad; puede
  pertenecer a uno o más negocios (RN9 corregida — ver §3; modelo N:M implementado en
  `03-arquitectura/modelo-datos.md` §2ter). Puede configurar una duración de cita general
  propia que, cuando existe, prevalece sobre la duración del servicio para todos sus turnos
  (D10, amenda RN3).
- **Servicio** — prestación ofrecida por un negocio (nombre, duración, precio de referencia,
  configuración de seña por profesional — D2). La duración puede ser reemplazada por la
  configuración general del profesional (D10/RN3, ver nota de cambio de comportamiento en §1).
- **Disponibilidad** — bloques de tiempo en que un profesional ofrece un servicio.
- **Excepción de disponibilidad** — bloqueo puntual sobre la disponibilidad general.
- **Turno** — reserva concreta de un cliente con un profesional, servicio y horario, dentro de
  un negocio; puede tener un pago/seña asociado (D2), salvo la excepción de CU6 (D16/RN18).
- **Historial de visitas** — registro histórico de turnos atendidos de un cliente, visible
  solo para el profesional que lo atendió (D3).
- **Tratamiento** (D8, entidad nueva) — registro de un tratamiento o proceso de seguimiento
  asociado a un paciente por un profesional, independiente de un turno puntual. Visible solo
  para el profesional que lo registró (RN13). No existe hoy en el modelo de datos — a modelar
  por DBA.
- **Nota médica** (D8, entidad nueva) — anotación clínica/de seguimiento que un profesional
  deja asociada a un paciente, independiente de un turno puntual. Visible solo para el
  profesional que la registró (RN13). No existe hoy en el modelo de datos — a modelar por DBA.
- **Documento de paciente** (D12/RN16, entidad nueva) — archivo adjunto que un profesional
  sube y consulta contra la ficha de un paciente (ej. estudios, órdenes médicas, autorizaciones
  de obra social escaneadas — "Autorizaciones Médicas" en las capturas originales). Sin firma
  digital ni flujo de consentimiento. **Visibilidad no resuelta todavía** (¿privado por
  profesional, como el historial y las notas médicas, o compartido dentro del negocio? — ver
  pregunta nueva en §7). No existe hoy en el modelo de datos — a modelar por DBA una vez
  resuelta la visibilidad.
- **Credencial WhatsApp del negocio** (D13, dato nuevo) — número y credenciales de WhatsApp
  Business API que cada negocio gestiona y paga por su cuenta, para el canal adicional de
  notificaciones (RN17). Dato de configuración a nivel negocio — a modelar por DBA.
- **Cuenta de Mercado Pago del negocio** (D18, dato nuevo) — datos de cobro que un negocio
  configura para recibir el pago de señas de sus turnos (Configuración de Pagos, alcance
  básico — D18). Dato de configuración a nivel negocio — a modelar por DBA.
- **Suscripción "Turnario Pro"** (D14/D15/D21) — plan pago con modelo freemium (uso gratuito
  hasta un límite, Pro desbloquea uso ilimitado y funciones avanzadas), solo Android (Google
  Play) por ahora. Valores exactos de límite gratuito y precio: responsabilidad de Product
  Manager en `02-backlog/backlog.md`, no de este documento.

*(Historial de visitas no es una entidad propia: es una consulta de `Turno` filtrada por
`cliente_id` + `profesional_id` con estado "atendido", reforzando RN7/D3 — un profesional solo
puede filtrar por su propio `profesional_id`. De la misma forma, los reportes de D18 tampoco
son una entidad propia: son agregaciones/consultas sobre `Turno` — y su `Pago` asociado —
filtradas por período, profesional y servicio.)*

## 6. Preguntas abiertas — resueltas

Las 5 preguntas originales fueron respondidas por el CEO y están incorporadas como decisiones
D1–D5 en la §1. Preguntas menores que quedan abiertas y no bloquean el diseño (parametrizables):

1. Valor exacto de la ventana mínima de cancelación (A3, propuesto 2 horas).
2. Alcance de permisos del administrador del negocio sobre el historial de clientes (A7/D3
   dejan al administrador sin acceso al historial por defecto — confirmar si es correcto).

Con las decisiones D1–D5 confirmadas, el proyecto avanza a Fase 3 (Diseño).

## 7. Preguntas abiertas de la ampliación de 2026-08-05 (app hermana del CEO) — RESUELTAS (2026-08-06)

Las 11 preguntas quedaron **resueltas**: el CEO las respondió una por una (más 5 preguntas
relacionadas del plan de producción de CTO IA con implicancia funcional, ver notas de cierre en
§1). Se conserva el texto original de cada pregunta como registro histórico, con un puntero a
la decisión que la resolvió.

1. **Precedencia de duración de cita (D6/RN11):** ¿la duración configurada por el profesional
   prevalece sobre la duración por servicio (RN3), o es al revés? → **RESUELTA — D10.** El
   profesional manda siempre: su duración general, cuando está configurada, prevalece sobre la
   del servicio para todos sus turnos. Amenda RN3 directamente (§3) — cambio de comportamiento
   sobre lógica ya implementada, ver nota en D10 (§1).
2. **Alcance de campos de salud (D7/RN12):** ¿aplican a todos los rubros de negocio (D1,
   multi-rubro) o solo a profesionales de salud? ¿deben ser opcionales/ocultables por rubro? →
   **RESUELTA — D11.** Solo a negocios de rubro salud. Ver RN15 (§3) — incluye pregunta de
   implementación pendiente para DBA (criterio de "rubro de salud") y gate legal de Ley 25.326
   antes de producción con datos reales.
3. **Autorizaciones Médicas:** ítem observado en el menú "Panel Profesional" de las capturas,
   alcance ambiguo (¿consentimientos legales, formularios firmados, documentos adjuntos?). No
   se incorporó como decisión ni como historia — se necesita definición del CEO. → **RESUELTA —
   D12.** Documentos adjuntos por paciente, sin firma digital ni flujo de consentimiento. Ver
   RN16 (§3) — queda una pregunta nueva sobre visibilidad (ver más abajo).
4. **Canal WhatsApp:** ¿reemplaza los canales ya implementados (push/email, D4) o es un canal
   adicional a elección del usuario? ¿quién gestiona/paga la cuenta de WhatsApp Business API? →
   **RESUELTA — D13.** Canal adicional; cada negocio gestiona y paga su propia cuenta. Ver RN17
   (§3).
5. **Suscripción "Turnario Pro":** qué funcionalidades quedan gratis vs. pagas, precio, quién
   paga (profesional o negocio), y si aplica también a iOS/App Store o solo a Android por ahora.
   → **RESUELTA — D14** (modelo freemium por límite de uso; valores exactos a cargo de Product
   Manager) **y D15** (solo Android/Google Play por ahora).
6. **Ícono "cambiar de vista" del dashboard del profesional:** ¿alterna entre roles Cliente/
   Profesional del mismo usuario, o entre negocios administrados? Impacta directamente en RN9
   (hoy un profesional/administrador pertenece a un único negocio). → **RESUELTA — confirmado
   por el CEO el 2026-08-06, antes de esta tanda de 16 respuestas, directamente con DBA (sin
   número D nuevo, ver nota de cierre en §1).** Alterna entre negocios que administra/donde
   trabaja el mismo usuario — un profesional/administrador SÍ puede pertenecer a más de un
   negocio. RN9 corregida en §3; ya implementado en el modelo de datos
   (`03-arquitectura/modelo-datos.md` §2ter).
7. **Seña en turnos agendados manualmente (CU6):** ¿aplica RN10 igual que en la autoreserva del
   cliente, o el profesional puede omitirla al cargar el turno él mismo? → **RESUELTA — D16.**
   El profesional puede omitirla, caso por caso; excepción explícita a RN10 solo en CU6. Ver
   RN18 (§3) y CU6 actualizado (§4).
8. **Import/export de pacientes:** formato de archivo y origen esperado. → **RESUELTA — D17.**
   CSV/Excel genérico, en ambos sentidos, con plantilla descargable para el import.
9. **Reportes y estadísticas, y configuración de pagos del negocio:** alcance funcional
   concreto, no derivable de las capturas. → **RESUELTA — D18.** Reportes: turnos por estado y
   monto facturado por período, desglosado por profesional y servicio. Configuración de pagos:
   solo la cuenta de Mercado Pago del negocio.
10. **Toggles de notificación "Mensajes", "Reseñas y Calificaciones", "Promociones y Ofertas":**
    corresponden a funcionalidades (mensajería in-app, reseñas, marketing) que hoy no existen
    en este backlog — ¿se construyen como parte de este alcance o el toggle queda oculto hasta
    que existan? → **RESUELTA — D19.** Se muestran ya, como placeholder visual — guardan
    preferencia, no activan nada todavía. Ver RN19 (§3).
11. **Estado activo/inactivo de paciente:** ¿manual o calculado automáticamente por antigüedad
    de última visita? → **RESUELTA — D20.** Manual, lo marca el profesional. Ver RN20 (§3).

Detalle de historias asociadas a cada pregunta en `02-backlog/backlog.md` (épicas E9–E14 e
historias HU-16 a HU-32) — Product Manager está aplicando estas mismas 16 decisiones al backlog
en paralelo a esta actualización.

Con las 11 preguntas resueltas (más las relacionadas del plan de producción de CTO IA —
formalizadas en D15, D21, el gate legal de D11 y la nota de Mercado Pago en §1; el punto sobre
CI de Mobile no tiene implicancia funcional), el diseño detallado de la ampliación (D6–D21)
puede continuar sin bloqueos de negocio pendientes. Quedan 2 preguntas nuevas y menores,
registradas a continuación — no bloquean el diseño básico, sí condicionan detalles de modelo de
datos/permisos.

### Preguntas nuevas, no bloqueantes (surgidas al formalizar estas decisiones, 2026-08-06)

1. **Para DBA (implementación, no requiere al CEO):** criterio determinístico para reconocer
   "rubro de salud" en `negocio.rubro` — ¿lista cerrada de rubros válidos, o un flag booleano
   dedicado? Ver D11/RN15. No se resuelve en este documento.
2. **Para el CEO:** los documentos adjuntos de un paciente ("Autorizaciones Médicas", D12/RN16)
   — ¿son visibles solo para el profesional que los sube (mismo criterio de privacidad que el
   historial de visitas, RN7, y las notas médicas, RN13), o para cualquier profesional/
   administrador del negocio? No asumido — no bloquea el diseño básico de subir/listar
   archivos, sí el diseño de permisos antes de que DBA modele la entidad "Documento de
   paciente" (§5).
