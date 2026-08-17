# Modelo de Datos — Turnos Profesionales

**Rol:** DBA
**Fase:** 3 — Diseño
**Entradas:** `01-requisitos/documento-funcional.md` §5 (glosario), `documento-arquitectura.md`

## 1. Reglas de diseño aplicadas

Siguiendo el estándar de la empresa (`docs/06-modelo-datos.md` §3):
- Todas las entidades usan **GUID** como clave primaria.
- Auditoría completa: `creado_en`, `creado_por`, `modificado_en`, `modificado_por` en toda tabla.
- **Soft delete** (`eliminado_en`) en Negocio, Profesional, Servicio (para no romper el
  historial de turnos ya realizados si se da de baja un profesional o servicio).
- Aislamiento multi-tenant: `negocio_id` obligatorio y no nulo en toda tabla de alcance de
  negocio, reforzado con Row Level Security (ver `documento-arquitectura.md` §3, §5).
- **Override nullable con fallback documentado** (introducido 2026-08-06, D10 — ver §2quater):
  un valor opcional que, cuando está seteado, reemplaza a otro valor ya existente en otra tabla,
  se modela como columna `NULL`able en la entidad dueña del override (no como una tabla de
  asociación aparte) — el `NULL` en sí mismo representa "sin override", sin necesitar un booleano
  adicional. El fallback y su semántica exacta se documentan junto al campo: no se resuelve en la
  base de datos, lo aplica la capa de aplicación.
- **Auditoría reducida en tablas de autogestión** (patrón ya presente desde Fase 3 en `Usuario`/
  `Profesional`, formalizado como regla explícita en 2026-08-11 al aplicarlo de nuevo en
  `UsuarioPreferencias` — ver §2septies): cuando una tabla solo puede ser escrita por el propio
  sujeto de la fila (reforzado por una policy de RLS de "acceso propio" o, en el caso de `Usuario`,
  por construcción del flujo de registro/login), se omiten `creado_por`/`modificado_por` — siempre
  serían idénticos al identificador del sujeto, dato 100% redundante. La auditoría completa
  (`creado_por`/`modificado_por` además de `creado_en`/`modificado_en`) se reserva para tablas
  donde quien escribe la fila puede ser distinto de a quién pertenece el dato (`Negocio`,
  `Servicio`, `Paciente`, `Tratamiento`, `NotaMedica`).
- **Preferencias de usuario — tabla nueva vs. extender una `usuario_preferencias*` existente**
  (introducido 2026-08-12, HU-26 — ver §2octies): una tabla `usuario_preferencias*` sirve para
  preferencias PLANAS (booleanos/enums escalares, 1:1 con `usuario`, sin sub-estructura ni
  historial propio). Extender una tabla existente de esta familia es la opción por defecto, SALVO
  que (a) la nueva familia de preferencias necesite algo con estado/historial propio (deja de ser
  plana), o (b) exista una dependencia operativa real que la tabla existente no pueda garantizar
  de forma independiente (ej. vive en una rama/migración todavía no integrada) — en cualquiera de
  los dos casos, tabla nueva con el mismo prefijo (`usuario_preferencias_<dominio>`), documentando
  el motivo puntual.
- **Estado por defecto seguro para filas existentes, cuando el concern nuevo puede LIMITAR una
  acción** (introducido 2026-08-14, HU-29 — ver §2novies): a diferencia de una preferencia inerte
  (`usuario_preferencias*`, sin efecto si falta la fila salvo mostrar otro valor), un concern que
  puede bloquear una acción (ej. un plan de suscripción con límites de uso) no se resuelve solo
  con la convención "sin fila = default seguro" documentada en un comentario — hay que
  garantizarlo con un mecanismo verificable: `DEFAULT` de columna en la tabla nueva (resuelve los
  INSERT futuros sin intervención) + backfill explícito, dentro de la propia migración incremental
  (no a mano), para las filas YA existentes del lado "dueño" que todavía no tienen fila en la
  tabla nueva.

## 2. Entidades principales

| Entidad | Descripción | Relaciones |
|---|---|---|
| **Negocio** | Comercio/consultorio, raíz de aislamiento multi-tenant (D1). `es_rubro_salud` (D11/RN15, ver §2quinquies) determina si sus profesionales ven los campos extendidos de `Paciente`. `ubicacion` (referencia corta de zona/ciudad, descubrimiento) convive desde 2026-08-17 con 4 columnas nuevas de perfil completo — `horario_atencion`, `direccion` (postal completa, distinta de `ubicacion`), `telefono`, `logo_url` (HU-31, todas nullable, ver §2undecies). | N:M Usuario (administradores, vía `NegocioAdministrador`); 1:N Servicio, Cliente-en-negocio, `Paciente`; N:M Profesional (vía `NegocioProfesional`) — ver §2ter, generalización N:M 2026-08-06; 1:1 `SuscripcionNegocio` (HU-29, ver §2novies) |
| **Usuario** | Identidad base (email, teléfono, hash de contraseña o `google_id` — al menos uno de los dos, ver §2sexies/HU-35 —, rol: cliente/profesional/administrador). | 1:1 Profesional (si rol=profesional, identidad — no implica pertenencia a un negocio); N:M Negocio (si rol=administrador, vía `NegocioAdministrador`) — ver §2ter |
| **Profesional** | Extiende Usuario; identidad profesional pura, sin negocio fijo propio (ver §2ter). `duracion_cita_min` opcional (D10, ver §2quater): si el profesional lo configuró, reemplaza `servicio.duracion_min` en todos sus turnos, sin importar el servicio ni el negocio. | N:M Negocio (vía `NegocioProfesional`), N:M Servicio (vía `ProfesionalServicio`), 1:N Disponibilidad, 1:N Turno |
| **NegocioAdministrador** | Tabla de asociación N:M; reemplaza a la antigua columna `negocio.admin_usuario_id` (1:1). PK compuesta `(negocio_id, usuario_id)`. Ver §2ter. | N:1 Negocio, N:1 Usuario |
| **NegocioProfesional** | Tabla de asociación N:M; reemplaza a la antigua columna `profesional.negocio_id` (1:1). PK compuesta `(negocio_id, profesional_id)`, lleva `activo` para pausar/reanudar la membresía sin perderla. NO es redundante con `ProfesionalServicio` — ver §2ter. | N:1 Negocio, N:1 Profesional |
| **Servicio** | Prestación ofrecida por un Negocio (nombre, duración, precio). | N:1 Negocio, N:M Profesional |
| **ProfesionalServicio** | Tabla de asociación N:M; lleva el flag `requiere_sena` y `monto_sena` (D2/RN10) — la seña se configura por combinación profesional+servicio, no globalmente. | N:1 Profesional, N:1 Servicio |
| **Disponibilidad** | Bloque recurrente (día de semana, hora inicio/fin) de un profesional para un servicio. | N:1 Profesional, N:1 Servicio |
| **ExcepcionDisponibilidad** | Bloqueo puntual (fecha/hora inicio-fin) que anula disponibilidad general (RN5). | N:1 Profesional |
| **Turno** | Reserva concreta: cliente + profesional + servicio + horario + estado (ver máquina de estados en `documento-arquitectura.md` §3). `negocio_id` se resuelve desde `servicio.negocio_id` (inequívoco), no desde el profesional — ver §2ter. | N:1 Negocio, N:1 Profesional, N:1 Servicio, N:1 Usuario (cliente) |
| **Pago** | Registro de intención/confirmación de pago de seña asociado a un Turno (D2). | 1:1 Turno (cuando aplica) |
| **Notificacion** | Bandeja de notificaciones (HU-14b/HU-25, 2026-08-12 — ver §2octies): además del log original (tipo, envío), ahora sabe A QUIÉN notifica (`destinatario_usuario_id`, nullable por compat con código existente) y si ya se leyó (`leido`). Un turno puede originar 0..N notificaciones (confirmación/nueva reserva, cancelación, reprogramación, recordatorio); el texto final ("María Pérez confirmó su turno de las 10:00") se arma en Backend a partir de `turno_id`, no se guarda armado. | N:1 Turno, N:1 Usuario (destinatario) |
| **Paciente** (HU-20, nueva 2026-08-10) | "Ficha" que un Profesional lleva de un Cliente, dentro de un Negocio — NO 1:1 con Usuario, ver §2quinquies (RN7/RN13/D3: privacidad por profesional). Campos básicos ya en Usuario (nombre/email/teléfono); acá viven fecha de nacimiento, género, dirección, alergias, contacto de emergencia, notas médicas generales (gateados a rubro salud, D11/RN15) y `activo` (D20/RN20, no gateado). Escritura exclusiva del profesional dueño de la fila; desde 2026-08-15 el administrador del negocio tiene además lectura completa (SOLO LECTURA, no escritura) — ver §5septies. | N:1 Negocio, N:1 Profesional, N:1 Usuario (cliente); 1:N Tratamiento, 1:N NotaMedica |
| **Tratamiento** (HU-21/D8, nueva 2026-08-10) | Proceso de seguimiento asociado a un Paciente, independiente de un turno puntual (descripción, fecha de inicio, fecha de fin opcional). Privado por profesional (RN13), heredado de `Paciente` — ver §2quinquies; administrador del negocio con lectura adicional desde 2026-08-15, mismo criterio que `Paciente` — ver §5septies. | N:1 Paciente |
| **NotaMedica** (HU-21/D8, nueva 2026-08-10) | Anotación clínica/de seguimiento asociada a un Paciente, independiente de un turno puntual (fecha, texto). Privado por profesional (RN13), heredado de `Paciente` — ver §2quinquies; administrador del negocio con lectura adicional desde 2026-08-15, mismo criterio que `Paciente` — ver §5septies. | N:1 Paciente |
| **UsuarioPreferencias** (HU-32, nueva 2026-08-11) | Preferencias de privacidad de la cuenta — tabla satélite 1:1 con Usuario (visibilidad de perfil, mostrar estado en línea, compartir datos de uso con la plataforma), transversal a ambos roles. NO gateada por negocio/profesional — ver §2septies. | 1:1 Usuario |
| **UsuarioPreferenciasNotificacion** (HU-26, nueva 2026-08-12) | Preferencias de notificación de un Usuario — 3 canales (push/email/whatsapp), 2 tipos de aviso (citas y recordatorios / promociones) y 2 de sonido/vibración, los 7 booleanos planos. Compartida Cliente/Profesional. Tabla propia, NO columnas en `UsuarioPreferencias` (HU-32, ciclo paralelo) — ver §2octies para el porqué. | 1:1 Usuario |
| **SuscripcionNegocio** (HU-29/E11, nueva 2026-08-14) | Plan/suscripción de un Negocio — freemium por límite de uso (columnas `plan` 'gratis'/'turnario_pro', `periodo` 'mensual'/'anual' nullable si es gratis, `vencimiento`, `estado` 'activa'/'vencida'/'cancelada'). Soporte de datos para la activación SIMULADA de "Turnario Pro" (mismo criterio que `MockPagoProvider`) — sin columnas todavía para la verificación real de Google Play (deliberado, ver §2novies). | 1:1 Negocio |
| **TokenRecuperacionPassword** (nueva 2026-08-16, pedido del CEO, prioridad alta) | Token de un solo uso para el flujo "olvidé mi contraseña" — siempre hasheado (`token_hash`, nunca en texto plano, mismo criterio que `usuario.password_hash`), con expiración corta (`expira_en`) e invalidación tras el primer uso o al pedirse uno nuevo (`usado_en`, ver §2decies). Deliberadamente SIN Row Level Security (§5octies) — es un artefacto pre-autenticación, el patrón de RLS de este esquema no aplica. | N:1 Usuario |

*(Historial de visitas sigue sin ser una entidad propia: es una consulta de `Turno` filtrada por
`cliente_id` + `profesional_id` con estado "atendido" — término conceptual, no un valor real del
ENUM `estado_turno`, que no tiene un estado "atendido"/"completado" propio, ver §2quinquies —,
reforzando RN7/D3: un profesional solo puede filtrar por su propio `profesional_id`. Tratamiento y
NotaMedica, en cambio, SÍ son entidades propias desde este ciclo — HU-21 las definió así
explícitamente, a diferencia del historial de visitas.)*

## 2bis. Corrección de esquema — CRITICAL-1 (login de administrador, cross-tenant)

> **Nota (2026-08-06):** la columna `negocio.admin_usuario_id` descripta en esta sección **ya
> no existe** — fue reemplazada por la tabla de asociación `negocio_administrador` al
> generalizar el esquema de 1:1 a N:M (un administrador/profesional puede pertenecer a más de
> un negocio). Ver **§2ter** para el detalle completo del reemplazo. Esta sección se conserva
> sin editar porque el diagnóstico de CRITICAL-1 (por qué el login sin correlación era
> explotable) sigue siendo la motivación de fondo de la relación persistida — el §2ter solo
> generaliza su cardinalidad, no reabre el hallazgo.

Security reportó (`07-seguridad/informe-seguridad.md` §CRITICAL-1) que `POST /auth/login`
resolvía el `negocio_id` del administrador con una query sin correlación real
(`JOIN negocio n ON u.id = ? ... LIMIT 1` sin `ORDER BY`), porque el esquema **no tenía
ninguna relación persistida** entre un usuario administrador y su negocio — la única vez que
se conocía esa relación era en el instante de `POST /auth/registro-negocio` (negocio y admin
se crean en la misma request), y no se guardaba para reconstruirla en logins posteriores. El
resultado: cualquier login de administrador recibía el `negocio_id` del primer negocio de toda
la base, habilitando escritura administrativa cross-tenant (violación de RN9/D1).

**Corrección:** se agrega `negocio.admin_usuario_id UUID NOT NULL UNIQUE REFERENCES
usuario(id)`. Se eligió una columna 1:1 en `negocio` (en vez de una tabla de asociación
`negocio_administrador`) porque el alcance MVP documentado es "1 administrador = 1 negocio"
(`01-requisitos/documento-funcional.md`, supuesto A7) y es la solución más simple que resuelve
el hallazgo sin sobre-diseñar; si en una iteración futura se necesita soportar más de un
administrador por negocio, migrar a una tabla de asociación es directo sin romper esta
columna (se puede derivar de ella). `NOT NULL` porque el alta de negocio siempre crea
negocio + administrador en la misma transacción, así que nunca debería existir un negocio sin
administrador resuelto. `UNIQUE` refuerza la relación 1:1 en ambos sentidos (un mismo
administrador no puede quedar asociado a más de un negocio).

Aplicado en ambas migraciones (`05-codigo/database/migrations/001_init.sql` y
`05-codigo/backend/migrations/001_init.sqlite.sql`), reordenando la creación de tablas
(`usuario` antes que `negocio`) porque la nueva columna referencia `usuario(id)`.

**Recomendación de query para Backend** (no implementada aquí — corresponde a
`src/routes/auth.ts`, rama `rol === 'administrador'` de `POST /auth/login`):

```sql
SELECT id FROM negocio WHERE admin_usuario_id = ?  -- ? = usuario.id del login
```

reemplazando el `JOIN` sin correlación actual. Devuelve como máximo una fila por la `UNIQUE`
de arriba, así que no hace falta `LIMIT`/`ORDER BY`. Backend debería además agregar el test de
regresión con 2+ negocios que sugiere Security, y decidir si recrea `dev.sqlite3` para tomar
la columna nueva (la migración usa `CREATE TABLE IF NOT EXISTS`, así que no altera una base ya
existente).

## 2ter. Generalización 1:1 → N:M (administrador/profesional pueden pertenecer a varios negocios)

**Origen.** El CEO confirmó (2026-08-06) un cambio de alcance: un mismo administrador o
profesional puede pertenecer a más de un negocio (ej. un entrenador que atiende en dos
gimnasios, o un dueño que administra varias sucursales). Esto resuelve la pregunta abierta que
había quedado registrada en `01-requisitos/documento-funcional.md` §7 punto 6 y
`02-backlog/backlog.md` (HU-27, ícono "cambiar de vista") — la respuesta es **SÍ, hay que
soportarlo**. RN9 (`documento-funcional.md` §3: "un profesional... pertenece a un único
negocio") queda desactualizada por esta decisión; su corrección de texto le corresponde a
Business Analyst en un próximo ciclo, no se edita ese documento desde acá.

Antes de diseñar se verificó activamente (no se asumió) que las tablas `negocio_administrador`/
`negocio_profesional` **no existían todavía** — un intento previo de este mismo trabajo había
quedado interrumpido antes de escribir esquema, así que el punto de partida real seguía siendo
el 1:1 original documentado en §2bis.

### Qué reemplaza a qué, y por qué

| Antes (1:1) | Ahora (N:M) | Motivo |
|---|---|---|
| `negocio.admin_usuario_id UUID NOT NULL UNIQUE REFERENCES usuario(id)` | Tabla `negocio_administrador(negocio_id, usuario_id, creado_en)`, PK compuesta | La columna 1:1 no puede expresar "este usuario administra 2 negocios" — es estructuralmente incompatible con la nueva regla de negocio, no solo insuficiente. |
| `profesional.negocio_id UUID NOT NULL REFERENCES negocio(id)` | Tabla `negocio_profesional(negocio_id, profesional_id, activo, creado_en)`, PK compuesta | Mismo motivo: un profesional puede trabajar en 2+ negocios; la columna fija en `profesional` lo impedía. |

`profesional` pasa a ser una identidad profesional pura (como `usuario`), sin negocio fijo
propio — sigue siendo 1:1 con `usuario` (una persona tiene una sola identidad profesional,
aunque trabaje en varios negocios con ella). Ambas tablas nuevas usan **PK compuesta, sin GUID
propio** — mismo criterio que ya tenía `profesional_servicio` en este esquema (Fase 3, ya
aprobado): son asociaciones puras, la clave es el par de columnas, y ninguna otra tabla necesita
referenciar una fila de asociación por un id propio. Detalle completo del razonamiento columna
por columna en los comentarios de ambas migraciones
(`05-codigo/database/migrations/001_init.sql` y
`05-codigo/backend/migrations/001_init.sqlite.sql`).

**Por qué esto no reabre CRITICAL-1.** El hallazgo original era "el login resuelve negocio_id
con una query sin correlacionar contra ninguna relación persistida". La corrección de fondo
—que exista una relación persistida real contra la cual correlacionar— **se mantiene
intacta**: `negocio_administrador`/`negocio_profesional` siguen siendo esa relación, solo que
ahora una query correlacionada correctamente puede devolver 0..N filas en vez de exactamente 1.
El riesgo estaba en confiar en un valor sin correlacionar, no en la cardinalidad — por eso la
generalización a N:M es segura siempre que ninguna query nueva vuelva a asumir "tomo la primera
fila / la única fila" donde ahora puede haber varias (ver recomendaciones de query para Backend
más abajo, y §5 para el mismo razonamiento aplicado a RLS).

### `negocio_profesional` vs. `profesional_servicio` — ¿son redundantes?

Se evaluó explícitamente y la conclusión es **NO son redundantes**, confirmado con un smoke
test funcional (no solo en teoría): se puede insertar una fila en `negocio_profesional` para un
profesional recién creado y verificar que `profesional_servicio` sigue en 0 filas para ese
mismo profesional — ambos hechos son independientes y coexisten válidamente.

- **`negocio_profesional`** responde "¿este profesional pertenece a este negocio?" (membresía/
  autorización — quién puede operar como staff de qué negocio).
- **`profesional_servicio`** responde "¿este profesional ofrece este servicio en particular, y
  con qué configuración de seña?" (catálogo/configuración operativa).

El caso concreto que separa ambos hechos en el tiempo es **HU-02 seguido de HU-04/HU-04b**: el
administrador da de alta a un profesional en su negocio (`POST /negocios/:id/profesionales`) —
en ese instante el profesional YA pertenece al negocio (debe poder loguearse, aparecer en el
roster del negocio, etc.) pero **todavía no configuró ningún servicio propio**, porque eso lo
hace el profesional mismo, después, en un paso separado (`POST /profesionales/:id/servicios`).
Si `negocio_profesional` no existiera y la pertenencia se derivara solo de
`profesional_servicio` (vía `servicio.negocio_id`), ese profesional recién dado de alta sería
indistinguible de "no pertenece a ningún negocio" durante esa ventana — un profesional con cero
servicios configurados en un negocio donde sí trabaja es un estado real y alcanzable, no
hipotético.

Adicionalmente, `activo` en `negocio_profesional` resuelve una necesidad que
`profesional_servicio` no cubre: pausar/reanudar la pertenencia completa a un negocio (ej.
licencia, cambio temporal) sin tener que iterar y revertir N filas de `profesional_servicio` una
por una, y sin recurrir a un soft-delete de toda la identidad `profesional` (que afectaría
incorrectamente a los demás negocios donde esa misma persona sigue activa).

### Recomendación para Backend — de dónde sale `turno.negocio_id`

Hoy Backend resuelve `turno.negocio_id` leyendo `profesional.negocio_id` al crear la reserva
(`src/routes/turnos.ts`, ver lista de endpoints más abajo). Esa columna ya no existe. La
recomendación es resolverlo desde **`servicio.negocio_id`**, no desde el profesional:

```sql
-- turnos.ts ya hace SELECT duracion_min FROM servicio WHERE id = ? — alcanza con agregar
-- negocio_id a esa misma query, no hace falta una consulta nueva.
SELECT negocio_id, duracion_min FROM servicio WHERE id = ?
```

Es inequívoco porque `servicio.negocio_id` sigue siendo 1:1 servicio→negocio (esa relación NO
cambia en esta generalización — un servicio sigue perteneciendo a un único negocio); el
servicio que el cliente eligió ya fija sin ambigüedad a qué negocio pertenece el turno,
independientemente de en cuántos negocios trabaje el profesional elegido.

**Recomendación adicional (integridad, no solo resolución de valor):** antes de esta
generalización era estructuralmente imposible que un `profesional_servicio` vinculara a un
profesional con un servicio de un negocio distinto al suyo (el profesional solo tenía un
negocio_id posible). Ahora que `profesional` no tiene negocio fijo, nada a nivel de base de
datos impide por sí solo que exista una fila de `profesional_servicio` para una combinación
donde el profesional no sea (o haya dejado de ser) miembro activo del negocio del servicio. Se
recomienda que Backend valide en `POST /turnos` (y en `POST /profesionales/:id/servicios` al
asociar el servicio) que exista una fila `negocio_profesional` con `activo = true` para
`(servicio.negocio_id, profesional_id)`. Expresar esto como una restricción declarativa de base
de datos requeriría un trigger (un `CHECK` de Postgres no puede hacer subquery entre tablas) —
no se implementa en este slice; queda documentado como recomendación, con la validación a nivel
de aplicación como alternativa más simple si no se justifica el trigger todavía.

### Recomendación para Backend — forma del claim `negocio_id` en el JWT

`src/auth.ts` define `negocio_id?: string` (un solo valor) en `JwtClaims`. Con N:M, un
administrador o profesional puede tener 0, 1 o varios negocio_id válidos, así que un claim
singular ya no alcanza. No es una decisión de DBA, pero se dejan tres opciones evaluadas para
que Backend/Arquitecto elijan (no excluyentes de a pares):

1. **Claim en array:** `negocio_ids: string[]` resuelto en el login desde
   `negocio_administrador`/`negocio_profesional`; cada endpoint acotado a negocio verifica
   `req.params.id` esté incluido en el array. Simple y sin queries extra por request, pero el
   token puede quedar desactualizado si la membresía cambia durante su vigencia (2h) — el mismo
   trade-off de staleness que ya existe hoy con cualquier claim de un JWT sin revocación.
2. **Sin claim de negocio en el JWT:** cada endpoint acotado a negocio hace un chequeo de
   membresía en vivo contra `negocio_administrador`/`negocio_profesional`. Siempre actualizado,
   sin staleness, mismo principio que las políticas RLS de §5 (re-derivar de la relación
   persistida en cada request en vez de confiar en un claim cacheado) — coherente de punta a
   punta, a costa de una consulta extra por request.
3. **"Vista activa" con endpoint de cambio (encaja con el ícono "cambiar de vista" del
   dashboard, HU-27):** el JWT sigue llevando un único `negocio_id` (como hoy), pero se valida
   contra la membresía real en el momento de emitirlo y cada vez que el usuario "cambia de
   vista" (nuevo endpoint que reemite el token con el negocio_id solicitado, solo si hay una
   fila de membresía real que lo respalde). Mantiene las políticas/checks actuales basados en
   igualdad simple, más simple de migrar desde el código de hoy, pero requiere ese endpoint
   nuevo y sigue teniendo staleness dentro de la vigencia del token.

### Endpoints/queries de Backend a revisar (asumen 1:1 hoy)

Relevado sobre el código actual, con archivo y línea aproximada (pueden correrse un poco si
Backend ya tocó el archivo):

- **`src/auth.ts:27`** — `JwtClaims.negocio_id?: string`: claim singular, ver opciones arriba.
- **`src/routes/auth.ts:36-47`** (`POST /registro-negocio`) — inserta `negocio` con
  `admin_usuario_id`; debe pasar a insertar además una fila en `negocio_administrador` en la
  misma transacción (y setear `SET LOCAL app.usuario_id` al id recién creado *antes* de ese
  INSERT si ya se conecta RLS, ver §5).
- **`src/routes/auth.ts:63-75`** (`POST /login`, rama profesional) — `profesional.negocio_id`
  (línea 71) ya no existe; reemplazar por `SELECT negocio_id FROM negocio_profesional WHERE
  profesional_id = ? AND activo = true` (0..N filas).
- **`src/routes/auth.ts:77-94`** (`POST /login`, rama administrador) — la query que resolvía
  CRITICAL-1 (línea 84, `SELECT id FROM negocio WHERE admin_usuario_id = ?`) pasa a `SELECT
  negocio_id FROM negocio_administrador WHERE usuario_id = ?` (0..N filas); el `if (!negocio)
  → 500` (líneas 86-91) hay que revisarlo porque ya no es necesariamente un caso "no debería
  poder pasar" bajo el nuevo esquema si en algún momento se permite un negocio sin admin
  transitoriamente (hoy sigue sin poder pasar vía `registro-negocio`, pero vale la pena
  reconfirmarlo, no asumirlo).
- **`src/routes/negocios.ts:71,88`** — `req.auth!.negocio_id !== req.params.id`: comparación
  contra claim singular en `POST /:id/servicios` y `POST /:id/profesionales`; depende de qué
  opción de claim elija Backend (ver arriba).
- **`src/routes/negocios.ts:54-65`** (`GET /:id/servicios/:servicioId/profesionales`, HU-08) —
  el `JOIN` usa `p.negocio_id = ?` (línea 61), columna eliminada; reescribir el join a través de
  `negocio_profesional np ON np.profesional_id = p.id AND np.negocio_id = ? AND np.activo = true`.
- **`src/routes/negocios.ts:97-107`** (`POST /:id/profesionales`, HU-02) — el `INSERT INTO
  profesional (..., negocio_id, ...)` (línea 105) referencia la columna eliminada; además hay
  que decidir qué pasa si el email ya pertenece a un profesional existente (de otro negocio):
  debería reusar esa fila de `profesional` (por `usuario_id`, que sigue siendo `UNIQUE`) e
  insertar solo la nueva fila de `negocio_profesional`, no fallar ni duplicar.
- **`src/routes/profesionales.ts`** — no referencia `negocio_id` directamente (confirmado por
  búsqueda en el código), pero `POST /:id/servicios` y `POST /:id/disponibilidad` no validan
  hoy que el `servicio_id` pertenezca a un negocio del que el profesional sea miembro activo;
  bajo 1:1 esto era estructuralmente imposible de violar, bajo N:M ya no — ver recomendación de
  integridad más arriba.
- **`src/routes/turnos.ts:47-49,114-120`** (`POST /turnos`) — `SELECT negocio_id FROM
  profesional WHERE id = ?` (línea 48) referencia la columna eliminada; reemplazar por
  `servicio.negocio_id` (ver recomendación arriba). La línea 226 (`PATCH /:id/reprogramar`, que
  copia `turno.negocio_id` del turno existente) **no** necesita cambios — no deriva de
  `profesional`.
- **`src/routes/dev.ts:30-51`** (`POST /dev/seed`) — mismo patrón que
  `registro-negocio`/`alta-profesional`: inserta `negocio.admin_usuario_id` (línea 38) y
  `profesional.negocio_id` (línea 50), ambas columnas eliminadas; necesita la misma
  restructuración transaccional.

### Nota operativa — `dev.sqlite3`

Este cambio, a diferencia del fix de CRITICAL-1 (que solo agregaba una columna), **elimina
columnas** de `negocio` y `profesional`. La migración usa `CREATE TABLE IF NOT EXISTS`, que no
altera una tabla ya existente — si algún entorno de desarrollo ya tiene un `dev.sqlite3`
generado con el esquema anterior, hay que borrarlo/recrearlo para que tome el esquema nuevo (no
alcanza con volver a correr la migración). En este entorno no había ningún `dev.sqlite3`
generado todavía (verificado), así que no aplica hoy, pero queda documentado para el próximo
`npm run dev`/CI que sí tenga uno persistido.

## 2quater. Campo `profesional.duracion_cita_min` — D10 amenda RN3 (2026-08-06)

**Origen.** El CEO resolvió (D10, ver `01-requisitos/documento-funcional.md` §1 y la RN3
amendada en §3) la pregunta de precedencia que D6/RN11 había dejado abierta: la duración de
turno que configura el profesional **reemplaza SIEMPRE** la duración del servicio (RN3
original), para **todos** sus turnos, sin importar cuál sea el servicio. El CEO eligió
explícitamente esta opción por ser la más simple de implementar, en vez de una alternativa más
granular (duración por combinación profesional+servicio, al estilo de
`profesional_servicio.monto_sena`) que se le había sugerido.

**No es una definición nueva sobre algo por construir — es un CAMBIO DE COMPORTAMIENTO sobre
lógica ya implementada y probada** (a diferencia de la mayoría de los campos de la ampliación
D6–D21): `calcularSlotsDisponibles` (`05-codigo/backend/src/dominio/disponibilidad.ts`) hoy
calcula la duración de cada slot únicamente a partir de `servicio.duracion_min`, sin mirar
ninguna configuración del profesional, y la reutilizan tanto `GET /profesionales/:id/slots` como
`POST /turnos` (ver recomendación de Backend más abajo). Ese cambio de código **no se hace en
este ciclo** — es trabajo de Backend en el próximo; acá solo se agrega el campo al esquema.

### Dónde vive el campo, y por qué no en otro lado

Se evaluaron las tres ubicaciones posibles antes de decidir:

| Ubicación candidata | ¿Por qué no? |
|---|---|
| `negocio_profesional.duracion_cita_min` | Variaría por negocio (un mismo profesional podría tener una duración distinta en cada negocio donde trabaja). El CEO no pidió esto — D10/RN11 hablan de "su duración de cita" en singular, un valor general del profesional, no una configuración por negocio. |
| `profesional_servicio.duracion_cita_min` | Es exactamente la alternativa más granular (por combinación profesional+servicio) que el CEO tuvo enfrente y **descartó explícitamente** a favor de la opción simple. |
| **`profesional.duracion_cita_min` (elegida)** | Es un valor de la **identidad profesional** — coherente con que, desde la generalización N:M de §2ter, `profesional` ya es una identidad pura sin negocio fijo propio. No depende de con qué negocio ni con qué servicio se cruce: aplica igual en todos los casos, que es exactamente lo que pide D10. |

`profesional.duracion_cita_min INTEGER`, **nullable**:
- `NULL` (default implícito, sin `DEFAULT` explícito ni falta que hace) = el profesional no
  configuró ningún override — se sigue usando `servicio.duracion_min` exactamente como hoy, sin
  ningún cambio de comportamiento. No hace falta un booleano "activar/desactivar" aparte (a
  diferencia de `profesional_servicio.requiere_sena`/`monto_sena`, que sí necesitan dos columnas
  porque "seña desactivada" y "monto sin definir" son dos estados distintos): acá `NULL` por sí
  solo ya representa sin ambigüedad "sin override".
- Un entero positivo = el profesional configuró su propia duración general; **reemplaza** (no
  promedia, no combina) `servicio.duracion_min` para todos sus turnos.
- `CHECK (duracion_cita_min IS NULL OR duracion_cita_min > 0)` — mismo criterio de "duración en
  minutos > 0" que ya usa `servicio.duracion_min INTEGER NOT NULL CHECK (duracion_min > 0)`, pero
  acá explícitamente nullable porque configurar el override no es obligatorio. Nota técnica: en
  Postgres y SQLite un `CHECK` sobre una columna en `NULL` ya pasa por sí solo (la expresión
  evalúa a desconocido, no a `FALSE`), así que `IS NULL OR ...` es redundante en términos
  estrictamente lógicos — se deja explícito de todas formas por ser la primera columna nullable
  con `CHECK` de este esquema, para que la intención quede clara sin depender de que el próximo
  agente que lea el DDL recuerde esa semántica de SQL.

Columna agregada en ambas migraciones (`05-codigo/database/migrations/001_init.sql` y
`05-codigo/backend/migrations/001_init.sqlite.sql`), dentro de la misma `CREATE TABLE profesional`
— no es una migración incremental nueva (`002_...`) porque el proyecto todavía no tiene ningún
entorno Postgres desplegado y ambos archivos siguen siendo el único `001_init` (mismo criterio ya
usado para la generalización N:M de §2ter). Es un cambio aditivo y reversible sin necesidad de un
script de rollback separado: agregar/quitar una columna nullable sin `DEFAULT` no rompe ninguna
fila existente ni ningún INSERT que ya no la mencione explícitamente.

**Nota operativa — `dev.sqlite3` (a diferencia de §2ter, esta vez SÍ aplica):** se verificó
activamente que `05-codigo/backend/dev.sqlite3` **ya existe** en este entorno. Como la migración
usa `CREATE TABLE IF NOT EXISTS`, no altera una tabla ya creada — ese archivo va a seguir sin la
columna nueva hasta que se borre y se regenere (o se corra un `ALTER TABLE profesional ADD COLUMN
duracion_cita_min INTEGER` manual). Queda como pendiente operativo para quien retome Backend en
el próximo ciclo — a diferencia de §2ter, donde en su momento se verificó que ningún
`dev.sqlite3` existía todavía y por eso esa nota no aplicaba en ese ciclo.

### Recomendación para Backend — dónde exactamente leer y aplicar el campo

No implementado en este ciclo (fuera del alcance de DBA) — ubicaciones concretas, archivo y línea
aproximada (pueden correrse un poco si Backend ya tocó el archivo):

- **`src/dominio/disponibilidad.ts:57-60`** — hoy `calcularSlotsDisponibles` solo hace
  `SELECT duracion_min FROM servicio WHERE id = ?`. Agregar ahí (o inmediatamente después) una
  segunda consulta `SELECT duracion_cita_min FROM profesional WHERE id = ?` usando el
  `profesionalId` que la función ya recibe como parámetro (línea 53) — no hace falta agregar un
  parámetro nuevo a la función.
- **`src/dominio/disponibilidad.ts:69`** — `const duracionMs = servicio.duracion_min * 60_000;`
  es la línea que fija la duración efectiva de cada slot de la grilla. Cambiar a algo como
  `const duracionEfectivaMin = profesional?.duracion_cita_min ?? servicio.duracion_min;` seguido
  de `const duracionMs = duracionEfectivaMin * 60_000;`. Este es el único lugar que decide el
  tamaño del paso de la grilla, así que corregirlo acá alcanza para arreglar tanto
  `GET /profesionales/:id/slots` (`src/routes/profesionales.ts:142-164`, que solo llama a esta
  función y no recalcula nada por su cuenta) como el uso interno que hace `POST /turnos` de esta
  misma función — no hace falta tocar `profesionales.ts` aparte.
- **`src/dominio/disponibilidad.ts:107`** — `return { duracionMin: servicio.duracion_min, slots
  };` también debe devolver la duración efectiva (`duracionEfectivaMin`), no siempre
  `servicio.duracion_min`, porque ese valor de retorno es justamente lo que `POST /turnos` puede
  reutilizar en el punto siguiente en vez de recalcular la duración por su cuenta (ver próximo
  ítem).
- **`src/routes/turnos.ts:122`** — `const finDate = new Date(inicioDate.getTime() +
  servicio.duracion_min * 60_000);` recalcula la duración de forma independiente, sin pasar por
  `calcularSlotsDisponibles`, así que el fix de arriba no lo cubre automáticamente. Dos formas
  válidas de resolverlo, ninguna cerrada por DBA:
  1. Reusar `slotsLibres.duracionMin` — el resultado de `calcularSlotsDisponibles` que la línea
     114 (inmediatamente arriba) ya calcula, y que con el fix anterior ya viene con el fallback
     aplicado. Evita una segunda fuente de verdad que se pueda desincronizar de la primera;
     requiere un ajuste de tipos menor porque `slotsLibres` es técnicamente nullable para
     TypeScript aunque en este punto ya se confirmó que el servicio existe (línea 57).
  2. Extender la consulta que ya existe en la línea 51 (`SELECT id FROM profesional WHERE id =
     ?`) a `SELECT id, duracion_cita_min FROM profesional WHERE id = ?` y aplicar el mismo
     `?? servicio.duracion_min` ahí mismo, sin depender del valor de retorno de
     `calcularSlotsDisponibles`. Más directo y sin fricción de tipos, a costa de repetir la
     misma regla de fallback en dos lugares del código (acá y en `disponibilidad.ts:69`).
- **Hallazgo adicional, fuera de lo pedido explícitamente pero con el mismo patrón exacto —
  `src/routes/turnos.ts:226-230`** (`PATCH /:id/reprogramar`): también calcula `nuevoFinDate` a
  partir de `servicio!.duracion_min` directamente, sin considerar `profesional.duracion_cita_min`.
  Si no se corrige junto con lo anterior, reprogramar el turno de un profesional con
  `duracion_cita_min` configurada le devolvería silenciosamente la duración del servicio en vez
  de mantener la duración con la que se reservó originalmente. Se deja documentado para que
  Backend lo resuelva en el mismo cambio si corresponde — no forma parte de lo pedido para este
  ciclo (`calcularSlotsDisponibles` + `POST /turnos`), pero comparte exactamente el mismo gap.

## 2quinquies. Ficha de paciente extendida + historial clínico (HU-20/HU-21) — 2026-08-10

**Origen.** El CEO aprobó avanzar con las pantallas de Gestión de Pacientes tras cerrar Dashboard
y Gestión de Horarios (rediseño Flutter). HU-20 (`02-backlog/backlog.md`) pide campos ampliados de
"ficha de paciente" (fecha de nacimiento, género, dirección, alergias, contacto de emergencia,
notas médicas, estado activo/inactivo); HU-21 pide 2 entidades nuevas, Tratamiento y Nota médica.
Ninguna de las dos existía en el modelo — el glosario (§5 de `documento-funcional.md`) ya las
listaba como "no existe hoy en el modelo de datos — a modelar por DBA".

### Dónde viven estos datos — no es 1:1 con `usuario`/`cliente`

La consigna de este ciclo planteaba la decisión como binaria: columnas nuevas en una tabla
`cliente` existente, o una tabla `paciente` separada 1:1 con `cliente`. Ninguna de las dos
alternativas es correcta tal cual — **no existe ninguna tabla `cliente` en este esquema** (el rol
"cliente" es un valor de `usuario.rol`; `turno.cliente_id UUID REFERENCES usuario(id)` ya es el
precedente de esa misma convención) y, más importante, **la cardinalidad correcta no es 1:1**.

Se evaluaron 3 alternativas antes de decidir:

| Alternativa | Por qué no |
|---|---|
| (a) Columnas nuevas en `usuario` | Un valor por persona en toda la plataforma — incompatible con que dos profesionales del mismo negocio, atendiendo al mismo cliente, lleven fichas independientes (ver evidencia abajo). |
| (b) Tabla `paciente` nueva, 1:1 con `usuario` | Mismo problema que (a): sigue guardando un único valor por persona, solo que en otra tabla. |
| **(c) ELEGIDA — tabla `paciente` nueva, 1 fila por `(negocio_id, profesional_id, cliente_id)`** | Es la única forma que representa correctamente que la ficha es propiedad del profesional, aislada además por negocio. |

**Evidencia textual explícita, no preferencia estilística.** RN7/RN13/D3 (`documento-funcional.md`
§3) exigen que el historial de visitas y los tratamientos/notas médicas sean "visible[s]
únicamente para el profesional que lo atendió/registró... No se comparte entre profesionales del
mismo negocio". HU-19 (`backlog.md`) extiende ese mismo criterio **a la ficha completa, no solo al
historial/notas**: "guardar el estado [activo/inactivo] como un atributo propio del paciente
(**scope por profesional**, mismo criterio de privacidad que el resto de **la ficha**, RN7/D3)".
HU-22 (import/export) confirma lo mismo: la ficha completa (básica + extendida de HU-20) se
exporta "solo su propia cartera" bajo RN7/D3. Es decir: dos profesionales del mismo negocio
atendiendo al mismo cliente llevan fichas **independientes**, que pueden divergir (ej. uno marca a
un cliente como "inactivo" en su cartera, el otro no) — una columna en `usuario` o una tabla 1:1
con `usuario` no puede representar eso.

`negocio_id` se suma además de `profesional_id` (no alcanza con `profesional_id` solo) por D1/RN9:
un mismo profesional puede pertenecer a 2+ negocios (§2ter) y el dato de un cliente "dentro de un
negocio" debe aislarse por negocio también — sin esto, el mismo profesional atendiendo al mismo
cliente en 2 consultorios distintos compartiría una única ficha entre ambos negocios, exactamente
el cruce que D1/RN9 prohíbe para cualquier otro dato de cliente.

`paciente` **no se limita a negocios de rubro salud** (a diferencia de sus columnas extendidas, ver
abajo): HU-19 (estado activo/inactivo) y HU-10/HU-11 (listado de clientes + historial) no están
condicionadas por rubro — son la base de "mi cartera" para cualquier profesional, de cualquier
rubro. Son específicamente las columnas de salud (fecha de nacimiento en adelante) las que quedan
sin usar para negocios que no son de rubro salud.

### Columnas — `paciente`

`id` (GUID propio, porque `tratamiento`/`nota_medica` lo referencian), `negocio_id` /
`profesional_id` / `cliente_id` (FK, ver arriba), campos extendidos de HU-20/D7/RN12 —todos
nullable, "todos los campos nuevos son opcionales salvo los que ya son requeridos hoy" (criterio
de aceptación de HU-20)— `fecha_nacimiento`, `genero`, `direccion`, `contacto_emergencia_nombre`,
`contacto_emergencia_telefono`, `contacto_emergencia_relacion`, `alergias`,
`notas_medicas_generales`; `activo` (BOOLEAN, D20/RN20, manual únicamente, mismo criterio que
`negocio_profesional.activo` — NO gateado por rubro, aplica a cualquier paciente); auditoría
completa (`creado_en/por`, `modificado_en/por`) más `eliminado_en` (soft delete, mismo motivo que
Negocio/Profesional/Servicio en el estándar de empresa — docs/06-modelo-datos.md §3: no romper
`tratamiento`/`nota_medica`, que referencian `paciente_id`, si se retira una ficha creada por
error). `UNIQUE (negocio_id, profesional_id, cliente_id)` — un profesional lleva una sola ficha
por cliente, por negocio; habilita `INSERT ... ON CONFLICT DO NOTHING/UPDATE` para el alta
perezosa que se recomienda a Backend abajo.

`genero` y `contacto_emergencia_relacion` son `TEXT` libre, sin `CHECK`/ENUM a propósito: los
wireframes (`mapa-pantallas.md` §5.9) muestran dropdowns ("Prefiero no decir", "Familiar") pero son
contenido de UI, no reglas de negocio que dependan de valores específicos (a diferencia de
`rol_usuario`/`estado_turno`, que sí son ENUM porque controlan lógica real) — así, cambiar las
opciones del dropdown nunca requiere una migración de esquema.

**Gate de rubro salud — a nivel de aplicación, no de base de datos.** No hay `CHECK` que impida
poblar los campos extendidos en un negocio que no es de rubro salud: Postgres no puede validar
contra una columna de OTRA tabla (`negocio.es_rubro_salud`) sin un trigger, y no se implementa uno
en este ciclo — mismo criterio ya usado en §2ter para la integridad profesional↔negocio
(documentada como recomendación, no como constraint). Backend/Mobile deciden mostrar/ocultar estos
campos consultando `SELECT es_rubro_salud FROM negocio WHERE id = ?`.

**Recomendación para Backend — cuándo se crea la fila `paciente`:** no implementado acá (fuera de
alcance de DBA) — dos opciones razonables, ninguna cerrada: (i) al vuelo, la primera vez que el
profesional abre/edita la ficha de un cliente; (ii) automáticamente al crear el primer turno entre
ese profesional y ese cliente en ese negocio (mismo momento en que HU-23/CU6 ya resuelven "el
paciente ya existe en su cartera, o se da de alta en el mismo flujo").

### `negocio.es_rubro_salud` — el criterio determinístico que D11/RN15 dejó pendiente para DBA

D11 (`documento-funcional.md` §1) dejó pendiente para DBA el "criterio determinístico" para
reconocer un negocio de rubro salud, ofreciendo 2 alternativas: lista cerrada de rubros válidos, o
un flag booleano dedicado ("ej. `es_rubro_salud`"). **Se elige el flag booleano** sobre la lista
cerrada: `rubro` ya tiene datos reales como texto libre (ej. "Salud", "Entrenamiento Personal", ver
capturas en `mapa-pantallas.md` §5.11bis) y forzar una migración a un catálogo cerrado arriesgaría
invalidar valores existentes o ser demasiado rígido para rubros futuros no anticipados — mismo
criterio de "la solución más simple que resuelve el hallazgo sin sobre-diseñar" ya usado en el fix
de CRITICAL-1 (§2bis). `rubro` se mantiene sin cambios (texto libre, para mostrar/describir el
negocio); `es_rubro_salud BOOLEAN NOT NULL DEFAULT false` es la señal consultable y determinística
que gatea los campos extendidos de `paciente`.

**Pendiente operativo (backfill de datos, no DDL, no ejecutado en este ciclo):** los negocios ya
existentes con `rubro` de salud en texto libre (ej. `'Salud'`) no van a tener
`es_rubro_salud = true` automáticamente — requiere criterio humano sobre qué valores de `rubro`
realmente califican (un `UPDATE ... WHERE rubro ILIKE '%salud%'` ciego podría clasificar mal casos
ambiguos), así que queda como corrección manual puntual para quien administre cada ambiente, no
como sentencia ejecutada por esta migración.

### Tratamiento / Nota médica — por qué no repiten `negocio_id`/`profesional_id`

Ambas tablas (HU-21/D8/RN13) referencian **únicamente** `paciente_id`. A diferencia de `turno`
(que puede resolver su `negocio_id` por más de un camino posible, ver razonamiento de §2ter sobre
`servicio.negocio_id`), acá el único padre posible es `paciente`, ya `NOT NULL` y sin ambigüedad —
repetir `negocio_id`/`profesional_id` sería una redundancia con una única fuente de verdad (la de
`paciente`) que podría desincronizarse. Se resuelven por `JOIN` en la policy de RLS (ver §5ter),
mismo criterio ya aceptado en este esquema para `disponibilidad`/`excepcion_disponibilidad`/
`profesional_servicio` (§5, "pendiente para una próxima iteración").

`tratamiento`: `descripcion` (NOT NULL), `fecha_inicio` (NOT NULL), `fecha_fin` (nullable — un
tratamiento puede seguir abierto/en curso; sin evidencia de wireframe de este campo, pero
"proceso de seguimiento" del glosario admite duración, y agregarlo nullable ahora evita otra
migración si se pide más adelante). `nota_medica`: `fecha` (NOT NULL, `DEFAULT CURRENT_DATE`),
`texto` (NOT NULL). Ambas con auditoría completa (`creado_en/por`, `modificado_en/por`), sin soft
delete (a diferencia de `paciente`) — son las hojas del sub-grafo, nada las referencia a su vez, así
que borrar una no rompe integridad de ningún otro registro.

### Los 4 stat cards de HU-21 (`mapa-pantallas.md` §5.10)

"Tratamientos"/"Notas médicas" son conteos triviales sobre las tablas nuevas
(`SELECT count(*) FROM tratamiento WHERE paciente_id = ?`, ídem `nota_medica`). "Citas
totales"/"Completadas" **no** salen de estas tablas nuevas — salen de `turno`, igual que el
historial de visitas ya lo hace hoy (RN7): `SELECT count(*) FROM turno WHERE cliente_id = ? AND
profesional_id = ?` para el total, y agregando `AND estado = 'confirmado' AND fin < now()` para
"Completadas". Esa derivación (confirmado + ya pasado) es necesaria porque **`estado_turno` no
tiene un valor `'atendido'`/`'completado'` propio** — un turno confirmado queda en `'confirmado'`
para siempre, incluso después de ocurrir (el "estado 'atendido'" que menciona la nota al pie de la
tabla de entidades en §2 de este documento es conceptual, no un valor real del ENUM). Agregar un
valor nuevo al ENUM sería la alternativa más prolija a mediano plazo, pero es un cambio de
comportamiento sobre la máquina de estados de `turno` (`documento-arquitectura.md` §3, ya
aprobada) — fuera del alcance de este ciclo, documentado como recomendación futura.

### Row Level Security, migraciones y demás detalle

Ver **§5ter** (RLS de las 3 tablas nuevas) y **§4** (nota operativa sobre la migración incremental
`002_pacientes_historial_auth_google.sql`, necesaria porque Render producción ya está migrado).
Razonamiento completo, columna por columna, en los comentarios de
`05-codigo/database/migrations/001_init.sql` (bloque "Ficha de paciente extendida + historial
clínico").

## 2sexies. Login con Google (HU-35) — `usuario.password_hash` nullable + `google_id` — 2026-08-10

**Origen.** HU-35 (ya aprobada por el CEO, `02-backlog/backlog.md`) agrega login/registro con
Google. `usuario.password_hash TEXT NOT NULL` no puede representar una cuenta dada de alta
únicamente por Google — backlog.md dejaba esto como pregunta abierta explícita para Backend/DBA,
con 3 alternativas sugeridas (columna nullable + una columna que distinga el proveedor; un hash
placeholder no utilizable; u otra alternativa a preferencia de DBA).

**Decisión — `password_hash` nullable + `google_id TEXT UNIQUE` nullable + `CHECK (password_hash
IS NOT NULL OR google_id IS NOT NULL)`, SIN una columna "proveedor_auth" separada.** Se descarta el
hash placeholder: es un caso especial invisible en el esquema (nada en el DDL documenta qué
constante es "falsa"; código que compare contra `password_hash` sin saber del placeholder puede
tratarlo como hash real) — `NULL` es autoexplicativo y el motor lo hace explícito por construcción.
Se descarta también agregar una columna "proveedor_auth" separada (la lectura más literal de la
alternativa sugerida por el backlog) por redundancia: puede desincronizarse de qué columnas están
realmente pobladas (ej. quedar en `'google'` con `password_hash` ya seteado, o viceversa) — la
combinación `password_hash`/`google_id` deriva el/los métodos disponibles directamente de qué
columnas tienen valor, una sola fuente de verdad por hecho. Además, el `CHECK` da una garantía
declarativa que un flag separado no da gratis: impide a nivel de base de datos que exista una
cuenta sin ningún método de login válido (huérfana, imposible de autenticar).

`google_id` guarda el claim `sub` (subject) del ID token de Google — identificador estable e
inmutable, no el email (mejor práctica estándar de OIDC). `UNIQUE`, nullable-safe (Postgres permite
múltiples `NULL` en una columna `UNIQUE`).

**Recomendación para Backend (no implementada acá) — corregida 2026-08-10/11 tras la revisión de
Security en paralelo (`07-seguridad/informe-seguridad.md`, Adenda 2026-08-10, parte A; ya
trasladada también a `02-backlog/backlog.md`, HU-35).** La primera versión de este párrafo
recomendaba vincular automáticamente por coincidencia de email verificado — es exactamente la
alternativa que Security evaluó y descartó (no cierra escenarios de email reciclado/cuenta Google
comprometida/Workspace), corregido acá para no dejar dos fuentes contradictorias. Regla real: el
endpoint de login con Google debe buscar primero por `google_id` (login recurrente, ya vinculada);
si no hay match y tampoco existe ninguna cuenta con ese email, dar de alta una fila nueva
(`password_hash = NULL`) solo si `email_verified: true`; si SÍ existe una cuenta previa por
contraseña con ese email, **nunca vincular ni loguear automáticamente** — exigir que confirme su
contraseña actual en el mismo flujo y solo entonces persistir `UPDATE usuario SET google_id = ...`
sobre esa fila existente. Además, `/login` de contraseña existente (`src/routes/auth.ts`) hoy hace
`bcrypt.compareSync(password ?? '', usuario.password_hash)` sin comprobar que `password_hash` no
sea `NULL` — con esta migración, una cuenta 100% Google que intente loguearse por contraseña
pasaría `NULL` a `bcrypt`; agregar un chequeo explícito antes de esa línea.

**De paso, en el mismo `CREATE TABLE usuario` — `telefono TEXT` (columna nueva, no relacionada con
HU-35).** El glosario de `documento-funcional.md` (§5) documenta "nombre, email, teléfono" como
datos básicos de Cliente desde el origen del proyecto, pero `telefono` nunca se agregó como
columna — brecha real encontrada al modelar HU-20 (la Ficha de Paciente, `mapa-pantallas.md`
§5.9bis, lo muestra como uno de los 3 campos obligatorios del formulario). Vive en `usuario` (no en
`paciente`) por el mismo motivo que nombre/email: es un dato de identidad de la persona, no de la
relación profesional↔paciente. **Nota abierta para Arquitecto/Backend:** editar nombre/email/
teléfono desde "Editar Paciente" (pantalla que vive dentro del contexto de un negocio/profesional)
escribe sobre la fila global de `usuario`, visible para cualquier otro negocio donde esa misma
persona también sea cliente — comportamiento que ya existe hoy para nombre/email (no lo introduce
esta migración) y coincide con la app de referencia, pero vale la pena señalarlo: `usuario` sigue
sin RLS habilitada, así que hoy esa escritura depende enteramente de que el endpoint la autorice
bien en código de aplicación.

## 2septies. Preferencias de privacidad de usuario (HU-32) — 2026-08-11

**Origen.** El CEO aprobó avanzar con las pantallas de Configuración del lado Profesional que
todavía faltaban. HU-32 (E14, `02-backlog/backlog.md`): "Como cliente o profesional, quiero
controlar la visibilidad de mi perfil (público/solo contactos/privado), si muestro mi estado en
línea, y si comparto datos de uso con la plataforma... Es transversal a ambos roles, no una
funcionalidad específica de un negocio." Wireframe en `mapa-pantallas.md` §5.13 (bloque
"Privacidad" de la pantalla "Privacidad y Seguridad"), verificado contra una captura real de la
app de referencia en §5.13bis (2026-08-07).

**Alcance — qué NO se modela en este ciclo, y por qué.** Esa misma verificación (§5.13bis)
confirma que el bloque "Seguridad de la cuenta" (cambiar contraseña, verificación en dos pasos,
biometría, sesiones activas, descargar/eliminar mis datos) que el wireframe original mostraba
junto a "Privacidad" **no existe en la app real** — ya estaba documentado como adición de UX/UI
sin HU propia; esta verificación lo confirma, así que no se modela nada de eso acá. Tampoco se
modela el 4to control que sí aparece en la captura real, "Permitir Notificaciones" (entre
"Mostrar Estado en Línea" y "Compartir Datos de Uso"): se superpone temáticamente con
HU-26/Configuración de Notificaciones (`mapa-pantallas.md` §5.14, todavía sin modelar) — hacerlo
acá adelantaría ese trabajo futuro. Cuando se modele HU-26 se decide si ese toggle vive junto a la
configuración granular de notificaciones o si necesita su propio campo; no se resuelve hoy.

### ¿Columnas en `usuario` o tabla `usuario_preferencias` separada 1:1?

A diferencia de la decisión equivalente para `Paciente` (§2quinquies), acá la cardinalidad **no
fuerza la respuesta**: HU-32 es explícitamente transversal ("no una funcionalidad específica de un
negocio") y `mapa-pantallas.md` §5.13 confirma "pantalla y contenido idénticos para ambos roles
(misma cuenta, mismas garantías de privacidad)" — un solo valor por `Usuario`, sin el scope por
negocio/profesional/cliente que sí necesitaba `Paciente`. Tanto "columnas en `usuario`" como
"tabla 1:1" son estructuralmente válidas acá (a diferencia de `Paciente`, donde una de las dos
alternativas era directamente incompatible con los hechos) — la decisión se toma por otro
criterio, no por cardinalidad forzada.

**Se elige tabla separada, `usuario_preferencias`** (1:1 vía `usuario_id UNIQUE REFERENCES
usuario(id)`), por 3 motivos:

1. **Separación de responsabilidades / crecimiento acotado.** `usuario` es la tabla de
   identidad/autenticación — se consulta en cada login y la referencian por FK casi todas las
   demás tablas del esquema. Sus columnas hoy son todas hechos de identidad (email,
   password_hash, google_id, telefono, nombre, rol). Las preferencias de privacidad/app son un
   concern independiente que ya se sabe va a seguir creciendo (HU-26 queda para la próxima ronda
   a propósito; el propio wireframe de §5.13 documenta un bloque adicional, "Seguridad de la
   cuenta", que si algún ciclo futuro recibe HU propia sería exactamente más columnas de este
   mismo tipo). Una tabla separada absorbe ese crecimiento sin seguir ensanchando `usuario`.
2. **Precedente ya establecido en este esquema.** `Profesional` (§2ter) es exactamente este mismo
   patrón: tabla satélite 1:1 con `usuario`, separada pese a ser 1:1, para no mezclar la identidad
   base con un concern distinto. `usuario_preferencias` sigue la misma forma estructural — GUID
   propio + `usuario_id UNIQUE`, mismo patrón que `Profesional`/`Pago` en este esquema, en vez de
   usar `usuario_id` directo como PK.
3. **RLS como motivo de fondo, no solo de estilo** — ver conclusión siguiente.

### Conclusión sobre RLS de `usuario` (pedida explícitamente antes de decidir, no asumida)

Confirmado leyendo `05-codigo/database/migrations/001_init.sql` completo: `usuario` **hoy no
tiene Row Level Security habilitada** — no hay ningún `ALTER TABLE usuario ENABLE ROW LEVEL
SECURITY` en ese archivo (a diferencia de profesional/negocio_administrador/negocio_profesional/
servicio/turno/paciente/tratamiento/nota_medica, que sí la tienen). Es una brecha real,
preexistente (ya señalada en el comentario junto al `CREATE TABLE usuario`, a propósito de editar
nombre/email/teléfono desde "Editar Paciente": "`usuario` sigue sin RLS habilitada... esa
escritura depende enteramente de que el endpoint la autorice bien en código de aplicación, sin
ninguna capa de RLS de respaldo"), no introducida por este ciclo.

Esa brecha aplicaría igual a las 3 columnas de HU-32 si vivieran directamente en `usuario`: misma
protección (ninguna a nivel de base de datos) que el resto de esa tabla, dependiendo 100% de que
Backend nunca introduzca un bug de autorización. Para HU-32 específicamente — que **es** la
funcionalidad de privacidad — dejar sus datos en la tabla con menos defensa en profundidad de todo
el esquema sería, como mínimo, una señal contradictoria. La tabla separada resuelve esto de forma
limpia: al ser nueva, aplica desde el primer commit la lección ya documentada en §5bis/§5ter
(`FORCE ROW LEVEL SECURITY` desde el día 1 — ver §5quater), sin necesitar auditar/blindar
retroactivamente los múltiples call sites de escritura que ya existen hoy sobre `usuario`
(registro-cliente, registro-negocio, alta-profesional, y el futuro login-google de HU-35) antes de
poder habilitarle RLS con seguridad — trabajo real, más grande, fuera del alcance de este ciclo.

**Habilitar RLS sobre `usuario` en sí (más allá de estas 3 columnas) queda documentado como
recomendación para un ciclo futuro de DBA/Backend — no resuelto ni bloqueado acá**, mismo
tratamiento que otras brechas ya reconocidas en este documento (`pago`/`notificacion` sin RLS,
§5bis "Qué no se tocó").

### Columnas

Mismo orden que el wireframe (`mapa-pantallas.md` §5.13):

- **`visibilidad_perfil`** — ENUM dedicado (`visibilidad_perfil_usuario`: `publico` /
  `solo_contactos` / `privado`), no TEXT libre. Se distingue a propósito del criterio ya usado
  para `paciente.genero`/`contacto_emergencia_relacion` (TEXT libre por ser "contenido de UI, no
  una regla de negocio que dependa de valores específicos"): acá el campo existe
  específicamente para controlar qué puede ver otro usuario — mismo tipo de campo que
  `rol_usuario`/`estado_turno`/`estado_pago` (conjunto cerrado que gobierna comportamiento real),
  reforzado por la app real (§5.13bis), que confirma exactamente 3 opciones fijas como radio
  buttons. **Dónde se aplica la restricción de visibilidad en sí no se implementa en este
  ciclo** — ningún endpoint del proyecto expone hoy un "perfil público" navegable más allá de
  `GET /negocios/:id/servicios/:servicioId/profesionales` (HU-08, que no filtra por esto); queda
  documentado para que Backend lo aplique cuando exista ese caso de uso, mismo patrón que el gate
  de `es_rubro_salud` o el fallback de `duracion_cita_min`.
- **`mostrar_estado_en_linea`** / **`compartir_datos_uso`** — `BOOLEAN` simples (toggles on/off
  tanto en el wireframe como en la captura real).

**Defaults — `visibilidad_perfil = 'publico'`, `mostrar_estado_en_linea = true`,
`compartir_datos_uso = true`. Supuesto explícito, NO verificado contra evidencia de "alta de
cuenta nueva":** no hay wireframe ni captura del estado de una cuenta recién creada — se toman los
mismos 3 valores "activado" que sí muestra la captura real de §5.13bis
(`Screenshot_20260427_095421_Turnario.jpg`) para una cuenta **existente**, asumiendo que reflejan
el default de fábrica de la app de referencia y no una elección explícita de ese usuario —
razonable pero no confirmable con la evidencia disponible hoy.

**Auditoría — solo `creado_en`/`modificado_en`, sin `creado_por`/`modificado_por`** (a diferencia
de `negocio`/`servicio`/`paciente`/`tratamiento`/`nota_medica`) — ver regla formalizada en §1
("Auditoría reducida en tablas de autogestión"): la policy de RLS de §5quater garantiza que quien
escribe una fila es siempre el propio `usuario_id` de esa fila, así que `creado_por`/
`modificado_por` serían siempre idénticos a `usuario_id` — dato redundante.

**Sin `eliminado_en` (soft delete):** a diferencia de `paciente` (que lo lleva porque
`tratamiento`/`nota_medica` referencian `paciente_id` y no hay que romper ese historial), ninguna
otra tabla de este esquema referencia `usuario_preferencias.id` — no hay historial que proteger.
El ciclo de vida de esta fila está atado por completo al de `usuario`.

**Recomendación para Backend — cuándo se crea/actualiza la fila** (no implementado acá, mismo
patrón ya usado para la creación perezosa de `Paciente`): no hace falta una fila para que una
cuenta nueva "tenga" estos valores — mientras no exista fila para un `usuario_id` dado, la
aplicación puede devolver los 3 `DEFAULT` de arriba sin tocar la base (0 filas = "todavía en
default de fábrica"). El botón "Guardar" del footer real (3 botones, ver `mapa-pantallas.md`
§5.13bis) es el punto natural para un `INSERT ... ON CONFLICT (usuario_id) DO UPDATE SET ...`
(upsert; el `UNIQUE` de `usuario_id` ya lo habilita). Qué hace exactamente "Restablecer" (el 3er
botón) no se resuelve acá — `DELETE` de la fila o `UPDATE` explícito a los mismos 3 valores son
ambos válidos contra este esquema; decisión de Backend.

Detalle línea por línea (columnas, tipo, defaults) en
`05-codigo/database/migrations/001_init.sql` (bloque "Preferencias de privacidad de usuario") y
en `05-codigo/database/migrations/003_privacidad_usuario.sql` (mismo contenido, delta para
aplicar a mano contra Render — ver **§4**). RLS en **§5quater**.

## 2octies. Bandeja de notificaciones + preferencias de notificación (HU-14b/HU-25/HU-26) — 2026-08-12


**Origen.** El CEO pidió explícitamente construir Notificaciones en este ciclo (había quedado
afuera de la ronda anterior de Configuración). Cubre 2 HU relacionadas pero distintas — UX/UI ya
las separó en 2 pantallas (`mapa-pantallas.md` §5.14/§5.15): la Bandeja (HU-14b/HU-25, lo que el
usuario RECIBE) y la Configuración granular (HU-26, qué avisos/canales quiere recibir).

### Investigación previa contra el código real (no asumido)

La tabla `notificacion` ya existía desde la Fase 3 original, pero como un LOG interno
(`turno_id`, `tipo`, `enviado_en`, `creado_en`) sin destinatario ni estado de leído — más cerca
de "se generó un aviso de tipo X" que de una bandeja consultable. Antes de modelar, se investigó
contra `backend/src/`:

- **¿Qué crea filas hoy?** Solo 2 call sites, los dos literal `tipo = 'confirmacion'`:
  `POST /turnos` (al reservar) y `PATCH /:id/reprogramar` (para el turno nuevo). `PATCH
  /:id/cancelar` NO inserta ninguna fila — gap real de Backend, no solo de modelado.
- **¿Existe un job de recordatorio?** No. `src/jobs/expirarPagosPendientes.ts` es el ÚNICO
  archivo en `src/jobs/` y expira pagos vencidos (turno/pago) — no envía avisos. El
  `tipo = 'recordatorio'` que ya anticipaba el comentario original de la columna, y la propia
  interfaz `NotificacionProvider.enviar(destinatarioUsuarioId, tipo, mensaje)` de
  `integraciones/notificaciones.ts` (que YA tiene un parámetro de destinatario, evidencia de que
  Backend/CTO IA ya habían anticipado la necesidad) nunca se invoca desde ningún endpoint.
- **¿Para quién son las filas `confirmacion` que sí se insertan?** El wireframe (§5.15) lo
  resuelve: los 3 ejemplos de la bandeja ("María Pérez confirmó su turno de las 10:00",
  "Recordatorio: turno con Juan Ramírez en 1 hora", "Sofía Cano canceló su turno de las 16:00")
  están redactados en 3ra persona sobre la acción del CLIENTE — es la bandeja del PROFESIONAL.
  HU-26 (§5.14) lista "nueva reserva" como sub-ítem "[solo Profesional]", distinto de
  "confirmación" (que HU-14 describe del lado del cliente). Conclusión aplicada: las filas
  `confirmacion` que ya insertan POST /turnos y PATCH /reprogramar SON, hoy, el aviso de "nueva
  reserva"/"turno reprogramado" para el PROFESIONAL de ese turno.

### Bandeja de notificaciones — `notificacion` extendida, no tabla nueva

Se extiende la tabla existente (no se crea una paralela): sigue siendo el mismo concepto de
fondo — "algo pasó con este turno que alguien debería saber" —, solo que ahora completo con a
quién y si ya lo vio. Columnas nuevas:

- **`destinatario_usuario_id` (UUID, NULLABLE — no NOT NULL)**: a quién notifica. NULLABLE por el
  mismo motivo que `usuario.telefono`/`usuario.google_id` (§2sexies) — los 2 call sites que ya
  insertan (POST /turnos, PATCH /:id/reprogramar) no se tocan en este ciclo y no van a pasar esta
  columna; si fuera NOT NULL sin default, esos 2 INSERT (hoy funcionando) empezarían a fallar en
  CUALQUIER ambiente apenas corriera esta migración, no solo Render. Postgres tampoco permite un
  `DEFAULT` que derive el valor de otra columna del mismo INSERT (haría falta resolver
  `turno_id -> profesional.usuario_id`) — se evaluó un trigger `BEFORE INSERT` para auto-
  completarlo y se descartó: sería el primer trigger de todo este esquema, y el proyecto viene
  resolviendo este tipo de derivación en la capa de aplicación de forma consistente (mismo
  criterio que `duracion_cita_min`/§2quater o `es_rubro_salud`). La policy de INSERT (ver §5quinquies)
  acepta explícitamente `IS NULL`; el SELECT de la bandeja nunca muestra una fila NULL a nadie
  (fail-closed). Backfill de las filas existentes de Render vía el mismo JOIN
  `turno -> profesional`, en `004_notificaciones.sql`.
- **`leido` (BOOLEAN NOT NULL DEFAULT false)** + `modificado_en` genérico (no un `leido_en`
  dedicado — es el único atributo mutable de la fila, `modificado_en` ya alcanza, mismo criterio
  que el resto del esquema).
- **NO se guarda texto/nombre/hora armados** (ej. un `mensaje` con el string final ya construido)
  — mismo criterio anti-duplicación que `tratamiento`/`nota_medica` (§2quinquies, no repiten
  `negocio_id`/`profesional_id` de `paciente`). Todo lo que necesita el texto de la bandeja ya es
  derivable vía `turno_id` (`turno` nunca se borra físicamente, solo cambia `estado`) — lo arma
  Backend, no la base de datos.
- **`tipo` pasa de `TEXT` libre a ENUM `tipo_notificacion`** (`'confirmacion'`, `'recordatorio'`,
  `'cancelacion'`, `'reprogramacion'` — los primeros 2 ya eran convención informal, los últimos 2
  son nuevos): a diferencia de `genero`/`contacto_emergencia_relacion` (TEXT a propósito, UI sin
  lógica), acá sí hay lógica real que depende del valor (qué plantilla arma Backend) — mismo
  criterio que `rol_usuario`/`estado_turno`/`estado_pago`. No se renombra `'confirmacion'` para no
  romper los 2 call sites existentes.
- **Índices nuevos**: `idx_notificacion_destinatario (destinatario_usuario_id, creado_en DESC)`
  para "mis notificaciones, más nuevas primero"; `idx_notificacion_destinatario_no_leida` parcial
  (`WHERE leido = false`) para el badge de no leídas, mismo patrón que `uq_turno_slot_activo`.

**Recomendación para Backend — 3 INSERT que faltan para que la bandeja tenga contenido real** (no
implementado acá, fuera de alcance de DBA):
1. `PATCH /:id/cancelar` (turnos.ts) — agregar, en la misma transacción que el `UPDATE turno SET
   estado = 'cancelado'`, un `INSERT INTO notificacion` con `tipo = 'cancelacion'` y
   `destinatario_usuario_id` = el `usuario_id` del profesional del turno.
2. `PATCH /:id/reprogramar` y `POST /turnos` — agregar `destinatario_usuario_id` al INSERT que ya
   existe (mismo JOIN `turno -> profesional`); evaluar si conviene `tipo = 'reprogramacion'` en
   vez de `'confirmacion'` para el caso de reprogramar (label ya disponible, decisión de Backend).
3. **Job de recordatorio nuevo** (no existe archivo todavía) — recorrer turnos próximos a
   iniciar (ventana ~1h, según wireframe) e insertar `tipo = 'recordatorio'` para el profesional;
   correr con `withTransaction(fn, { jobSistema: true })` (mismo patrón que
   `expirarPagosPendientes.ts`) — la policy `notificacion_insert_job_sistema` ya está lista. Falta
   además una guarda anti-duplicados (no resuelta acá, lógica de Backend).

### Preferencias de notificación — tabla nueva, `usuario_preferencias_notificacion`

HU-26 (§5.14): 3 secciones — Canal (`notif_canal_push`/`notif_canal_email`/
`notif_canal_whatsapp`, default `true`), Tipo de aviso (`notif_citas_recordatorios` default
`true`, `notif_promociones` default `false` — "Mensajes"/"Reseñas y Calificaciones" quedan
OCULTOS por decisión ya tomada de UX/UI, no se modelan), Sonido y vibración
(`notif_sonido`/`notif_vibracion`, default `true`). 7 booleanos planos, 1:1 con `Usuario`,
compartida Cliente/Profesional — mismo patrón que `UsuarioPreferencias` (HU-32, Privacidad).

**¿Tabla nueva o columnas en `UsuarioPreferencias`?** Se evalúa explícitamente extender, porque
`usuario_preferencias` ya tiene nombre genérico (no `preferencias_privacidad`) y ambas son
preferencias planas 1:1 con usuario — el caso más favorable para reusar. Se decide TABLA NUEVA
igual, por 2 motivos independientes (ver también la regla general en §1):

1. **Lógico — límite para no degradar en un "cajón de sastre".** Configuración ya tiene varias
   pantallas (Perfil/Privacidad/Consultorio/Pagos/Reportes, y ahora Notificaciones) y va a seguir
   creciendo. Visibilidad de perfil y canales de notificación no comparten ninguna relación
   funcional más allá de "son de configuración". Se traza acá el límite explícito:
   `usuario_preferencias*` sirve para preferencias PLANAS sin sub-estructura ni historial propio
   — el día que una pantalla necesite algo con estado/historial (ej. WhatsApp, §5.16: estado de
   conexión + log de mensajes, no un simple on/off) ya no calificaría para vivir acá.
2. **Operativo — el que decide en la práctica.** `usuario_preferencias` (HU-32) vive en
   `feature/configuracion-profesional`, todavía no mergeada a `main` al momento de este ciclo.
   `feature/notificaciones` (esta rama) parte de `main`, así que esa tabla NO EXISTE acá.
   Depender de ella (`ALTER TABLE usuario_preferencias ADD COLUMN ...`) habría acoplado esta
   migración al orden y al éxito de un merge ajeno todavía en curso — riesgo operativo real para
   una migración que además tiene que poder aplicarse a mano contra Render. Una tabla propia,
   sin ninguna referencia a `usuario_preferencias`, es 100% autocontenida.

Nombre `usuario_preferencias_notificacion` (comparte el prefijo de `usuario_preferencias` a
propósito — familia conceptual común, separada por los 2 motivos de arriba). Sin
`creado_por`/`modificado_por`/`eliminado_en` — mismo motivo que `usuario_preferencias`: la fila
es propiedad exclusiva de `usuario_id`, RLS ya solo permite que ese mismo usuario la escriba, y
un ajuste de preferencias no se "da de baja". **Nota de coordinación entre ramas:** cuando
`feature/configuracion-profesional` y `feature/notificaciones` se mergeen, si conviene
consolidar ambas tablas en una sola queda a criterio de un ciclo futuro (Director General
IA/DBA) — no se decide acá, ninguna de las dos depende de la otra para funcionar.

**Recomendación para Backend** (no implementada acá): ninguna fila se crea automáticamente al
registrarse un usuario — el endpoint de lectura debe devolver los defaults de arriba cuando no
exista fila todavía, o hacer un `INSERT ... ON CONFLICT (usuario_id) DO NOTHING` perezoso.

## 2novies. Suscripción "Turnario Pro" (HU-29/E11) — 2026-08-14

**Origen.** HU-29 (E11, `02-backlog/backlog.md`) — freemium **por negocio**, no por profesional
individual: plan gratis con límites de uso (1 profesional por negocio, 60 turnos confirmados/mes
por negocio); "Turnario Pro" los levanta y desbloquea Reportes (HU-28, ya construido), WhatsApp
(HU-24, todavía no), plantillas de horario recurrente (HU-17, ya construido) e import/export de
pacientes (HU-22, todavía no) — esos desbloqueos de otras features son responsabilidad de Backend
en cada endpoint, no de este modelado. Precio confirmado por el CEO esta ronda: USD 9/mes por
negocio, 20% off pagando anual (USD 86.40/año, calculado por DevOps en
`08-despliegue/google-play-billing.md` §5). Plataforma v1: solo Android, vía Google Play Billing —
integración real todavía inexistente (requiere que el CEO complete
`google-play-billing.md` §2/§6), así que este ciclo modela el soporte de datos para una
**activación simulada** (mismo criterio que `MockPagoProvider`,
`backend/src/integraciones/pagos.ts`), no verificación real de compra. Comportamiento al llegar al
límite del plan gratis, confirmado por el CEO esta ronda: **bloquear** nuevas reservas/turnos ese
mes (no solo avisar) — lo aplica Backend en el endpoint de reserva, no este modelado.

### ¿Columna `negocio.plan` o tabla `suscripcion_negocio` separada?

Evaluadas ambas antes de decidir, mismo criterio que ya usó este documento para
`UsuarioPreferencias`/`Paciente` (§2septies/§2quinquies): la cardinalidad no fuerza la respuesta
acá (1:1 con `Negocio` bajo cualquiera de las dos), así que decide otro criterio. Se descarta una
columna `negocio.plan` sola porque el plan pago necesita, además, 3 atributos que el plan gratis
no tiene sentido de tener (`periodo`, `vencimiento`, `estado` de esa suscripción puntual) — una
columna sola en `negocio` de todos modos habría necesitado sumar esas mismas 3 columnas ahí, con
el mismo resultado práctico que una tabla propia pero ensanchando `negocio` (identidad:
nombre/rubro/ubicación) con un concern de facturación ajeno — mismo razonamiento que ya separó
`UsuarioPreferencias` de `Usuario` ("un concern independiente que ya se sabe va a seguir
creciendo"). Se elige **tabla separada** (`suscripcion_negocio`, 1:1 con `negocio` vía
`negocio_id UNIQUE`), mismo patrón estructural que `Profesional`/`Pago`/`UsuarioPreferencias` (GUID
propio + `<dueño>_id UNIQUE REFERENCES <dueño>(id)`, no `negocio_id` como PK directamente).

### Columnas

3 ENUM dedicados (`plan`/`periodo`/`estado`), mismo criterio que `rol_usuario`/`estado_turno`/
`estado_pago`/`visibilidad_perfil_usuario`: gobiernan lógica real (qué límites aplica Backend, qué
desbloquea), no son contenido descriptivo de UI.

- **`plan` (`plan_negocio`: 'gratis' | 'turnario_pro')** — 'turnario_pro' coincide literalmente
  con el ID de producto de suscripción recomendado para Play Console (`turnario_pro`,
  `google-play-billing.md` §5) — mismo vocabulario en toda la cadena backlog → DevOps → DBA, no
  una coincidencia.
- **`periodo` (`periodo_suscripcion`: 'mensual' | 'anual'), NULLABLE** — solo tiene sentido con
  `plan = 'turnario_pro'`. Coincide, otra vez a propósito, con los 2 "planes base" recomendados
  dentro del producto de Play Console (mismo documento §5) — Backend combina `plan`+`periodo` para
  el identificador compuesto `turnario_pro_mensual`/`turnario_pro_anual` que va a necesitar contra
  Play Console; no se guarda ese string compuesto como columna propia para no duplicar lo que ya
  expresan `plan`+`periodo` juntos.
- **`vencimiento` (TIMESTAMPTZ, NULLABLE)** — igual que `periodo`, solo tiene sentido con
  `plan = 'turnario_pro'`.
- **`estado` (`estado_suscripcion_negocio`: 'activa' | 'vencida' | 'cancelada')** — el estado de
  ESE período pago puntual, independiente de si `plan` sigue diciendo 'turnario_pro': el diseño
  previsto (no forzado por ningún CHECK, ver más abajo) es que `plan` puede quedarse en
  'turnario_pro' de forma permanente una vez que un negocio se suscribe por primera vez (registro
  de "alguna vez pagó", útil para analítica futura) mientras `estado` refleja el momento actual
  ('vencida' = pasó `vencimiento` sin renovarse; 'cancelada' = el administrador pidió cancelar,
  pero puede seguir con acceso hasta que venza lo ya pagado — patrón común de SaaS). Bajo ese
  criterio, el **acceso efectivo** a las funciones Pro no es `plan = 'turnario_pro'` solo — es
  `plan = 'turnario_pro' AND estado = 'activa' AND vencimiento >= now()` (recomendación para
  Backend, no una regla de la base de datos — ningún job de este ciclo recalcula `estado`/`plan`
  automáticamente al pasar `vencimiento`, mismo criterio de resolver en la capa de aplicación ya
  usado en el resto de este esquema, ej. el fallback de `duracion_cita_min`, §2quater).
- **CHECK `ck_suscripcion_negocio_periodo_vencimiento_segun_plan`** — `periodo`/`vencimiento` NULL
  si y solo si `plan = 'gratis'`, mismo patrón de invariante cruzada entre columnas que
  `ck_usuario_password_o_google` (§2sexies): a nivel de base de datos, no solo de convención
  documentada.
- **Auditoría completa (`creado_por`/`modificado_por`, además de `creado_en`/`modificado_en`)** —
  a diferencia de `UsuarioPreferencias`/`UsuarioPreferenciasNotificacion` (las omiten porque el
  único actor posible es siempre el propio dueño de la fila, dato 100% redundante — regla general
  §1), acá el "dueño" es `negocio_id`, pero `NegocioAdministrador` es N:M — puede haber más de un
  administrador para el mismo negocio, así que quién activó/canceló Turnario Pro no es deducible
  de `negocio_id` solo. Mismo criterio que `Negocio`/`Paciente`/`Tratamiento`/`NotaMedica`, y
  particularmente apropiado acá por ser un dato de facturación (auditoría/soporte/disputas). Sin
  `eliminado_en`: ninguna otra tabla referencia `suscripcion_negocio.id`, y el ciclo de vida de
  esta fila es de estado mutable (activar/cancelar/vencer/reactivar in-place), no de alta/baja —
  mismo motivo que `UsuarioPreferencias`.

### Deliberadamente NO modelado en este ciclo

Mismo criterio de "no sobre-construir" ya aplicado en el resto de este esquema:

- **Ninguna columna para los datos de verificación real de Google Play** (`purchaseToken`/el
  resultado de la Android Publisher API, ver `google-play-billing.md` §6.2). Hay un precedente
  directo en este mismo esquema que en un primer momento parece sugerir lo contrario —
  `pago.referencia_externa TEXT` es exactamente ese patrón, una columna nullable agregada "por si
  hace falta después" para un dato externo de un proveedor que hoy solo tiene un Mock — pero,
  verificado contra el código real (`backend/src/`), esa columna tampoco tiene ningún consumidor
  hoy, ni siquiera el propio `MockPagoProvider` la escribe: ya es, en la práctica, el
  contraejemplo de "no sobre-construir" que este ciclo prefiere no repetir. La activación simulada
  (Backend, próxima ronda) no produce ningún `purchaseToken` real que guardar. Cuando la
  integración real exista, agregar recién ahí una columna nueva (ej. `purchase_token TEXT`,
  nullable) en una migración incremental futura.
- **Ningún campo de precio/monto** (a diferencia de `pago.monto`, que sí registra el importe real
  de cada pago de turno): USD 9/mes y USD 86.40/año son configuración de producto (Play
  Console/`backlog.md`), no un hecho transaccional por fila mientras la activación sea simulada.

### RLS, migraciones e índices

Detalle línea por línea de cada policy en
`05-codigo/database/migrations/001_init.sql` (bloque "Suscripción 'Turnario Pro'") y en
`005_suscripcion_negocio.sql` (mismas policies, envueltas en bloques `DO` con guard contra
`pg_policy`) — ver §5sexies para el resumen. Recomendación para Backend sobre cuándo se crea la
fila de un negocio nuevo (agregar el INSERT a la transacción de `POST /auth/registro-negocio`, o
resolverlo de forma perezosa como `UsuarioPreferencias`/`Paciente`) e índice nuevo sobre `Turno`
para el límite de 60 turnos/mes — ambos detallados en el propio `001_init.sql` y en §6.

## 2decies. Recuperación de contraseña — token de un solo uso (2026-08-16)

**Origen.** Pedido del CEO, prioridad alta. Verificado por grep antes de modelar (no asumido):
hoy no existe nada de este mecanismo ni en el esquema ni en el código — `usuario` solo tiene
`password_hash`/`google_id` para el login normal (HU-35, ver §2sexies), sin ningún mecanismo de
reset. Alcance de esta ronda ya decidido por el Director General IA (no se reabre acá — es la
base sobre la que Backend construye en un ciclo posterior, no implementado en este ciclo): Backend
genera un token de un solo uso, aleatorio y criptográficamente seguro (DISTINTO del JWT normal de
sesión, `src/auth.ts`), lo guarda SIEMPRE hasheado (nunca en texto plano — mismo criterio que
`usuario.password_hash`), con expiración corta, invalidable tras un solo uso o al expirar.

### ¿Tabla nueva o columnas en `usuario`?

Tabla nueva — a diferencia de la decisión equivalente para `UsuarioPreferencias`/
`SuscripcionNegocio` (§2septies/§2novies), acá la cardinalidad SÍ fuerza la respuesta, no es una
decisión de estilo: un usuario puede tener 0, 1 o varios tokens a lo largo del tiempo (ver "varias
recuperaciones seguidas" más abajo) — no es 1:1 con `Usuario`, columnas en `usuario` no podrían
representarlo sin perder el historial de tokens previos que la propia lógica de invalidación
necesita poder distinguir.

### Nombre

`token_recuperacion_password`, no `password_reset_token`: consistencia con el resto del esquema en
español ("password" se mantiene como préstamo ya establecido en este mismo esquema — ver
`usuario.password_hash`/`ck_usuario_password_o_google` — en vez de traducir a "contraseña", que no
aparece en ningún otro lado del DDL). Se evaluó explícitamente el prefijo `usuario_` (mirando la
ronda de Privacidad/Notificaciones como referencia de estilo reciente, `UsuarioPreferencias`/
`UsuarioPreferenciasNotificacion`, §2septies/§2octies) y se descarta: ese prefijo identifica
específicamente a la familia de tablas de PREFERENCIAS/configuración 1:1 con `Usuario` — "el
límite explícito" que traza §2octies ("`usuario_preferencias*` sirve para preferencias PLANAS...
sin sub-estructura ni historial propio"). Esta tabla no es una preferencia (es 1:N, no 1:1, y
tiene un ciclo de vida con estado propio) — es un artefacto de autenticación efímero, más cerca en
espíritu de `Turno`/`Pago`/`Notificacion` (sustantivo propio, sin anteponer el nombre de ninguna
tabla que referencia por FK) que de esa familia.

### Columnas

- **`usuario_id`** (UUID, NOT NULL, FK a `usuario`) — a quién pertenece el token. Resuelto por
  Backend ANTES del INSERT (`SELECT id FROM usuario WHERE email = ?`, lectura ya sin RLS — ver
  §5octies), nunca provisto crudo por quien pide la recuperación.
- **`token_hash`** (TEXT, NOT NULL, UNIQUE) — el hash del token, NUNCA el token en texto plano
  (mismo criterio que `password_hash`). A diferencia de `password_hash` (bcrypt, pensado para una
  contraseña de BAJA entropía elegida por una persona, donde el costo adaptativo de bcrypt es
  precisamente lo que dificulta la fuerza bruta), se **recomienda a Backend** (no implementado
  acá, ni impuesto por ningún CHECK — el algoritmo de hash es implementación, no esquema) un hash
  rápido no adaptativo (ej. SHA-256) en vez de bcrypt: el token en sí ya es de ALTA entropía
  (aleatorio, generado por el servidor, no elegido por una persona), no necesita costo
  computacional extra para resistir fuerza bruta, y usar bcrypt igual tendría 2 costos reales sin
  ningún beneficio — (a) CPU innecesaria en cada validación (spamear el endpoint de canje con
  hashes inválidos forzaría el costo adaptativo de bcrypt en cada intento, un vector de DoS barato
  que un hash rápido no abre) y (b) el límite de 72 bytes de entrada de bcrypt (no crítico para un
  token corto, pero una limitación real que un hash rápido no tiene). `UNIQUE` cubre además, por sí
  sola, el pedido explícito de este ciclo ("índice para que Backend pueda buscar eficientemente por
  el hash del token al validar") — mismo patrón que `usuario.email`/`usuario.google_id` (UNIQUE
  inline = constraint + índice a la vez, sin objeto nombrado aparte).
- **`expira_en`** (TIMESTAMPTZ, NOT NULL, sin DEFAULT) — Backend lo calcula y lo pasa siempre
  explícito (`now() + <TTL>`), mismo criterio que `turno.fin`/`excepcion_disponibilidad.fin` (el
  valor nace de una regla de aplicación, no de una constante de esquema). Duración recomendada (no
  impuesta acá — decisión de producto/seguridad de Backend, mismo criterio de "resolver en la capa
  de aplicación" ya aplicado sistemáticamente en este documento): 15–60 minutos.
- **`usado_en`** (TIMESTAMPTZ, nullable) — `NULL` = el token sigue vigente; con valor = ya no
  puede usarse, desde ese momento. A propósito UNA sola columna cubre DOS motivos de invalidación
  sin distinguir cuál fue (uso real, o supersedido por un pedido más nuevo — ver debajo): ninguna
  HU pide diferenciarlos; si hiciera falta a futuro, es aditivo. **Se evaluó explícitamente el
  patrón de `Notificacion.leido`** (BOOLEAN + `modificado_en` genérico, §2octies) por ser el
  precedente más cercano del esquema (una única columna mutable sobre una fila por lo demás de
  solo-creación) y se descarta a favor de un timestamp dedicado: a diferencia de `Notificacion`
  (que ya se anticipaba iba a seguir sumando campos mutables a futuro), esta fila tiene un ciclo de
  vida deliberadamente binario y cerrado (vigente → ya no vigente, para siempre) — una columna
  dedicada es más precisa que una genérica para un hecho de auditoría de seguridad, sin pagar el
  costo de una segunda columna redundante que siempre valdría exactamente lo mismo.
- **`creado_en`** (TIMESTAMPTZ, DEFAULT now()) — igual que el resto del esquema.

**Sin `creado_por`/`modificado_por` — pero NO por la regla de "auditoría reducida" de §1.** La
regla de §1 (`UsuarioPreferencias` y análogas) omite esas columnas porque son 100% redundantes con
`usuario_id`, dado que RLS GARANTIZA que el actor autenticado es el propio dueño de la fila. Acá no
aplica esa garantía porque no hay ningún actor autenticado en NINGUNA escritura de esta tabla —
crear el token es un pedido anónimo por email (antes de cualquier sesión) y canjearlo tampoco pasa
por un `usuario_id` de sesión (el token en sí ES la credencial, todavía sin JWT). `creado_por`
sería NULL el 100% de las veces, no por convención sino porque la naturaleza pre-autenticación de
este flujo nunca provee ese dato — mismo principio que ya reconoce este esquema para
`POST /auth/registro-cliente` sobre `usuario`. Sin `eliminado_en` (soft delete): nada referencia
`token_recuperacion_password.id`, y el ciclo de vida ya lo captura `usado_en`.

**CHECK `expira_en > creado_en`** — mismo patrón de invariante temporal que `turno.fin >
turno.inicio`/`disponibilidad.hora_fin > hora_inicio` (2 timestamps fijados juntos en el mismo
INSERT, deben quedar ordenados): guarda contra un bug de Backend que calculara mal el TTL y
emitiera un token ya vencido desde su creación.

### "Varias recuperaciones seguidas" — invalidar los tokens anteriores, no dejarlos expirar solos

Pregunta explícita de esta ronda ("un usuario puede pedir varias recuperaciones seguidas si no le
llegó el primer email — ¿invalidar los tokens anteriores del mismo usuario, o dejarlos expirar
solos?"). **Decisión de DBA: invalidar los anteriores**, por 2 motivos:

1. **Seguridad.** Con expiración corta pero varios pedidos seguidos dentro de esa ventana (el caso
   concreto que motiva la pregunta: "no me llegó el mail, pido de nuevo" 2-3 veces en pocos
   minutos), dejarlos expirar solos deja VARIOS tokens simultáneamente válidos para la misma
   cuenta durante el resto de la ventana — más secretos vivos a la vez de los necesarios, sin
   ningún beneficio para el caso de reenvío (que solo necesita que el ÚLTIMO link funcione).
   Invalidar los anteriores no perjudica en nada ese reenvío legítimo: el usuario simplemente usa
   el link más reciente que le llegó.
2. **Se puede garantizar a nivel de base de datos, no solo como convención que Backend tiene que
   recordar** (mismo valor que ya justifica `ck_usuario_password_o_google`/`uq_turno_slot_activo`
   en este esquema): el índice único parcial `uq_token_recuperacion_password_usuario_pendiente`
   sobre `(usuario_id) WHERE usado_en IS NULL` hace IMPOSIBLE que exista más de 1 fila pendiente
   para el mismo `usuario_id`. Backend queda estructuralmente obligado a invalidar
   (`UPDATE ... SET usado_en = now() WHERE usuario_id = ? AND usado_en IS NULL`) cualquier token
   pendiente existente ANTES de insertar uno nuevo, en la misma transacción — si lo hace en el
   orden equivocado, el INSERT nuevo falla por violación de unicidad (23505), mismo patrón de
   "conflicto detectado por el motor, no solo por la aplicación" que `uq_turno_slot_activo`. Este
   mismo índice cubre, como efecto secundario, la propia consulta de invalidación.

### Recomendación para Backend (no implementada acá, fuera de alcance de DBA)

- **`POST /auth/recuperar-password`** (o el nombre que se defina): 1) `SELECT id FROM usuario
  WHERE email = $1` (sin RLS, igual que `/registro-cliente`); 2) si existe, EN LA MISMA
  transacción, invalidar cualquier token pendiente (`UPDATE ... SET usado_en = now() WHERE
  usuario_id = $1 AND usado_en IS NULL`) seguido del `INSERT` del token nuevo — en ese orden, por
  el índice único parcial; 3) responder SIEMPRE el mismo mensaje genérico exista o no la cuenta
  ("si el email existe, vas a recibir instrucciones..."), para no filtrar por timing/contenido de
  la respuesta qué emails están registrados (user enumeration). El envío del email en sí es tarea
  de Integraciones, no de este modelado.
- **`POST /auth/reset-password`** (o el nombre que se defina): recibe el token en TEXTO PLANO
  (nunca `usuario_id` — el token ES la prueba de identidad), lo hashea, y busca
  `WHERE token_hash = $1 AND usado_en IS NULL AND expira_en > now()`. Sin fila → 400 genérico
  ("token inválido o vencido", sin distinguir cuál de las 2 razones). Con fila: EN LA MISMA
  transacción, `UPDATE usuario SET password_hash = ...` + `UPDATE token_recuperacion_password SET
  usado_en = now() WHERE id = ? AND usado_en IS NULL` — el `AND usado_en IS NULL` extra en este 2do
  UPDATE cierra la carrera de un doble submit concurrente con el mismo token (mismo espíritu que el
  manejo de 23505 ya existente para `uq_turno_slot_activo`): si `rowCount === 0`, alguien más ya
  canjeó este token en el medio, abortar sin aplicar el cambio de contraseña.
- **Rate limiting** — mismo patrón que `registroLimiter`/`loginLimiter` (`src/middleware/
  rateLimit.ts`), recomendado para ambos endpoints nuevos, en especial el de canje.
- **Job de limpieza** (no implementado, no bloqueante): un job periódico que borre filas viejas ya
  usadas/invalidadas o vencidas (mismo espíritu que `expirarPagosPendientes.ts`) es una mejora de
  housekeeping razonable para un ciclo futuro, no urgente — el volumen de esta tabla es bajo por
  diseño (a lo sumo 1 fila pendiente por usuario a la vez, por el índice único parcial).

Detalle línea por línea en `05-codigo/database/migrations/001_init.sql` (bloque "Recuperación de
contraseña — token de un solo uso") y en `008_recuperacion_password.sql` (mismo contenido, delta
para aplicar a mano contra Render — ver §4). RLS (o, en este caso, la decisión de no habilitarla)
en **§5octies**.

## 2undecies. Datos operativos del negocio — horario, dirección, teléfono, logo (HU-31) — 2026-08-17

**Origen.** HU-31 (`02-backlog/backlog.md`, épica E13) pide "completar datos operativos de mi
negocio más allá del alta inicial (horario general de atención, dirección detallada, teléfono/
contacto, logo o imagen), para que el cliente vea información completa y actualizada al elegir mi
negocio". La ronda "Modo Administrador v1" (épica E15, 2026-08-15) ya conectó
`PATCH /negocios/:id` a una pantalla real de edición (`configuracion_consultorio_screen.dart`, modo
`Rol.administrador`), pero la dejó **acotada a los 3 campos que ya tenían columna**
(`nombre`/`rubro`/`ubicacion`) — el propio `backlog.md` de esa ronda lo deja registrado como gap
explícito de DBA/Backend, no de Mobile/UX: *"Resto del alcance original de HU-31 (horario general
de atención, dirección detallada más allá de 'ubicación', teléfono/contacto, logo o imagen). Sin
columnas de datos ni endpoint — requiere DBA + Backend antes de poder construirse."* Este ciclo
cierra la mitad de DBA de ese gap: 4 columnas nuevas en `negocio`, **todas nullable** — un negocio
ya existente no tiene ninguna cargada hasta que su administrador las complete. El endpoint
(`PATCH /negocios/:id`) y la UI (`configuracion_consultorio_screen.dart`) quedan para una ronda
posterior de Backend/Mobile (recomendación con archivo y línea aproximada al final de esta
sección).

### Las 4 columnas

- **`horario_atencion` (TEXT, nullable)** — texto libre (ej. "Lunes a Viernes 9 a 18hs, Sábados 9
  a 13hs"), **deliberadamente NO estructurado por día**. Es puramente informativo para el perfil
  del negocio — **no participa en el cálculo de disponibilidad real de ningún profesional**, que
  sigue resuelto enteramente por `Disponibilidad`/`ExcepcionDisponibilidad` (bloques recurrentes +
  excepciones puntuales, **por profesional**, ya mucho más granular que un horario a nivel de
  negocio). Modelar esto de forma estructurada (columnas por día/franja) hubiera duplicado esa
  lógica sin necesidad, y peor, habría abierto la puerta a que ambas fuentes queden inconsistentes
  entre sí (ej. el texto dice "Sábados cerrado" pero un profesional puntual sí tiene disponibilidad
  cargada ese día) sin que nada en el esquema lo detecte — mismo criterio de "no duplicar una única
  fuente de verdad" ya aplicado a `Paciente.genero`/`contacto_emergencia_relacion` (§2quinquies):
  contenido informativo/de UI se modela como TEXT libre, no como estructura que controle lógica.
- **`direccion` (TEXT, nullable)** — dirección postal completa (calle, altura, piso). Campo
  **nuevo y distinto de `ubicacion`** (columna ya existente, sin cambios). Ver la investigación
  completa en la subsección siguiente.
- **`telefono` (TEXT, nullable)** — texto simple, sin `CHECK` de formato — mismo criterio que
  `Usuario.telefono` (§2sexies) y `Paciente.contacto_emergencia_telefono` (§2quinquies): ninguna
  columna de teléfono de este esquema valida formato a nivel de base de datos.
- **`logo_url` (TEXT, nullable)** — URL de una imagen ya alojada en otro lado. Ver el porqué de
  "URL pegada, no upload real" en la subsección dedicada más abajo.

Las 4 son **nullable, sin `DEFAULT`** — mismo motivo que el resto de columnas agregadas a una tabla
ya en uso en este esquema (`Usuario.telefono`/`google_id` en §2sexies, `Profesional.
duracion_cita_min` en §2quater): agregar una columna nullable sin `DEFAULT` no rompe ninguna fila
ni ningún `INSERT` existente que no la mencione. **Sin backfill** — a diferencia de
`SuscripcionNegocio` (§2novies, que sí backfillea un plan `'gratis'` por defecto para negocios ya
existentes), acá no hay ningún valor por defecto razonable: son datos que solo el dueño de cada
negocio conoce, nadie más puede completarlos en su nombre. Comparten el `modificado_en` genérico
que `Negocio` ya tenía desde la Fase 3 original — sin auditoría por columna individual.

### ¿Por qué `direccion` es una columna nueva y no una ampliación de `ubicacion`?

Investigado contra el código real antes de decidir (no asumido). `ubicacion` ya es una columna en
uso, con un propósito concreto y distinto del que pide HU-31 para este campo nuevo:

- Viaja en las 2 lecturas **públicas** de descubrimiento de negocios (`GET /negocios` y
  `GET /negocios/:id`, `src/routes/negocios.ts`, HU-00b/HU-31) y en `POST /auth/registro-negocio`
  (`src/routes/auth.ts`, alta inicial).
- Mobile la consume como **referencia corta de zona/ciudad**: `buscar_negocios_screen.dart`
  (pantalla de descubrimiento, HU-00b) la muestra concatenada con `rubro` en el subtítulo de cada
  card (`[rubro, ubicacion].whereType<String>().join(' · ')`) — un texto pensado para convivir con
  N negocios a la vez en una lista, no para una dirección postal completa.

HU-31 pide algo con un propósito distinto y posterior en el embudo: alguien que **ya decidió ir** a
ESTE negocio puntual y necesita la dirección exacta (calle, altura, piso) — un dato que no tiene
sentido amontonado en la lista de descubrimiento junto a otros negocios, y que además el propio
texto de HU-31 llama "dirección detallada" explícitamente para distinguirlo de la "ubicación" ya
existente (`backlog.md`, exclusiones de la épica E15: *"dirección detallada más allá de
'ubicación'"*). Sobrecargar `ubicacion` con este segundo propósito, en vez de agregar una columna,
tendría además un costo retroactivo: redefiniría en silencio el significado de datos que negocios
existentes ya cargaron bajo la semántica actual ("zona/ciudad corta", vía
`registro_negocio_screen.dart` o `configuracion_consultorio_screen.dart`), sin ninguna forma de
distinguir, fila por fila, si ese valor previo sigue sirviendo como dirección completa o no. Se
opta por la alternativa más simple y sin ambigüedad: `ubicacion` sigue exactamente igual, con su
mismo propósito de descubrimiento; `direccion` es un campo nuevo que coexiste con ella y se muestra
en un contexto distinto (perfil completo de un negocio ya elegido, no el listado de búsqueda).
Reutiliza el nombre genérico `direccion`, ya usado en `Paciente.direccion` (§2quinquies) con el
mismo significado literal — mismo criterio de reúso de nombre que `nombre`/`creado_en`, columnas
que también se repiten en más de una tabla de este esquema; no existe ninguna relación entre
`Negocio.direccion` y `Paciente.direccion` más allá de compartir nombre y significado genérico,
cada una vive scopeada a su propia tabla.

### ¿Por qué `logo_url` es una URL pegada y no un upload de imagen real?

Este esquema no tiene, ni este ciclo agrega, ningún servicio de almacenamiento de objetos (S3,
Cloudinary o similar) — y no es una omisión sino una restricción real de cómo opera esta Factory:
un agente de IA no puede aprovisionar por su cuenta credenciales nuevas para un servicio de storage
externo. El patrón elegido, consistente con el resto de esta ronda de Configuración, es que el
administrador pegue la URL de una imagen que ya subió a algún otro lado (un hosting de imágenes
existente, una red social, etc.) — `logo_url TEXT`, sin ninguna columna binaria/BYTEA ni un path de
archivo local.

**Sin `CHECK` de formato de URL a nivel de base de datos** — mismo criterio que `Usuario.email`
(tampoco tiene un `CHECK` de formato en este esquema; la validación de forma vive en `zod`, del
lado de Backend, no en el DDL). Se recomienda a Backend agregar `z.string().url()` (o equivalente)
al extender `actualizarNegocioSchema`, y a Mobile replicar la misma validación client-side antes de
habilitar "Guardar" (mismo patrón ya usado en esta app para la longitud mínima de contraseña). No
se valida — ni acá, ni se recomienda hacerlo de forma estricta a nivel de aplicación — que la URL
sea efectivamente una imagen: eso solo puede confirmarse intentando cargarla, no por el formato del
string. La recomendación para Mobile es un `Image.network(..., errorBuilder: ...)` con un ícono o
placeholder de fallback si la URL no carga, no un chequeo previo de contenido.

### Row Level Security e índices

**Sin cambios de RLS.** `Negocio` sigue sin tener Row Level Security habilitada en ningún punto de
este esquema (confirmado contra el código real: no hay ningún `ALTER TABLE negocio ENABLE ROW
LEVEL SECURITY` en `001_init.sql`, y el propio comentario de `PATCH /negocios/:id` en
`src/routes/negocios.ts` ya lo señala explícitamente) — nada que agregar en esta ronda.

**Sin índice nuevo.** Ninguna consulta existente ni recomendada filtra por `horario_atencion`,
`direccion`, `telefono` o `logo_url` — son campos de despliegue, de lectura directa junto al resto
de la fila por `id` (`GET /negocios/:id`) o por listado completo (`GET /negocios`), igual que
`rubro`/`ubicacion` hoy, que tampoco tienen índice propio. El índice implícito de la `PRIMARY KEY`
ya cubre el único patrón de acceso puntual real.

### Recomendación para Backend (no implementada acá, fuera de alcance de DBA)

Extender `PATCH /negocios/:id`, `src/routes/negocios.ts`. Línea aproximada verificada contra el
archivo tal como está al cierre de este ciclo — **ese mismo archivo ya tiene, en paralelo, cambios
de Backend ajenos a HU-31** (un fast-follow de E15: soft-delete de servicio y pausa/reactivación de
membresía de un profesional, sin relación con esta ronda), así que los números pueden correrse más
si Backend sigue tocándolo antes de retomar esto:

1. **`actualizarNegocioSchema` (línea ~67-71)** — sumar `horario_atencion`/`direccion`/`telefono`
   con `z.string().nullable()` (mismo patrón que `rubro`/`ubicacion` hoy — **no** `.optional()`,
   hace falta poder mandar `null` explícito para vaciar un campo ya cargado) y `logo_url` con una
   validación de formato URL (ver subsección de arriba).
2. **Body destructuring + `UPDATE`/`RETURNING` (línea ~643 y ~645-656)** — sumar las 4 columnas
   nuevas, mismo patrón que `nombre`/`rubro`/`ubicacion` ya tienen hoy.
3. **`GET /negocios` y `GET /negocios/:id` (línea ~116 y ~134)** — considerar sumar las 4 columnas
   al `SELECT`, al menos en `GET /:id` (perfil completo de un negocio puntual, exactamente donde
   HU-31 pide que "el cliente vea información completa... al elegir mi negocio"); si conviene
   exponerlas también en el listado `GET /` es una decisión de UX/producto, no cerrada acá.
4. **NO extender `POST /auth/registro-negocio` (`src/routes/auth.ts`) ni `POST /dev/seed`
   (`src/routes/dev.ts`)** con estos 4 campos — HU-31 los define explícitamente como datos que se
   completan "más allá del alta inicial", no en el registro.
5. **Mobile** (`configuracion_consultorio_screen.dart`, fuera de alcance de DBA/Backend) — sumar 4
   `TextEditingController` nuevos siguiendo el mismo patrón que `_ubicacionCtrl`, y considerar
   previsualizar `logo_url` con `Image.network` en vez de solo el campo de texto crudo.

Detalle línea por línea en `05-codigo/database/migrations/001_init.sql` (bloque "Datos operativos
del negocio — horario/dirección/teléfono/logo") y en `009_negocio_datos_operativos.sql` (mismo
contenido, delta para aplicar a mano contra Render — ver §4).

## 3. Diagrama conceptual

Actualizado (2026-08-06) para reflejar la generalización N:M de §2ter: `Profesional` ya no
cuelga directamente de `Negocio` como hijo fijo — la pertenencia pasa por las tablas de
asociación `NegocioAdministrador`/`NegocioProfesional`, ambas N:M entre `Usuario`/`Profesional`
y `Negocio`.

Actualizado de nuevo (2026-08-12, §2octies) — `Notificacion` ahora también apunta a `Usuario`
(el destinatario, no solo el `Turno` que la origina), y se agrega `UsuarioPreferenciasNotificacion`
1:1 con `Usuario` (misma forma que `UsuarioPreferencias` de HU-32, ciclo paralelo — no graficada
acá por no existir todavía en esta rama, ver §2octies).

Actualizado de nuevo (2026-08-14, §2novies) — se agrega `SuscripcionNegocio` 1:1 con `Negocio`
(HU-29/E11).

Actualizado de nuevo (2026-08-16, §2decies) — se agrega `TokenRecuperacionPassword` N:1 con
`Usuario` (un usuario puede tener 0..N tokens a lo largo del tiempo, a diferencia de las relaciones
1:1 de `UsuarioPreferencias`/`SuscripcionNegocio`).

```
Usuario ──< NegocioAdministrador >── Negocio
Usuario ── Profesional ──< NegocioProfesional >── Negocio
                 │
                 ├── Disponibilidad
                 ├── ExcepcionDisponibilidad
                 └── ProfesionalServicio ── Servicio ── Negocio (N:1)
Usuario ── UsuarioPreferencias (1:1, HU-32 — ver §2septies)

Negocio ── Turno ── Usuario (cliente)
                 ├── Pago
                 └── Notificacion ── Usuario (destinatario)

Negocio ── SuscripcionNegocio (1:1, HU-29 — ver §2novies)

Usuario ── UsuarioPreferenciasNotificacion (1:1)

Usuario ──< TokenRecuperacionPassword (N:1, ver §2decies — sin RLS, ver §5octies)
```

(`──< X >──` denota una relación N:M resuelta por la tabla de asociación `X`, con PK compuesta
por las dos claves foráneas que conecta.)

**Nota de mantenimiento (2026-08-11, todavía sin resolver al 2026-08-14):** este diagrama tampoco
se había actualizado con `Paciente`/`Tratamiento`/`NotaMedica` (§2quinquies, 2026-08-10) — gap
preexistente, detectado al tocar este diagrama para agregar `UsuarioPreferencias`, no corregido
ahí por quedar fuera del alcance de HU-32, y tampoco corregido en este ciclo (HU-29) por el mismo
motivo — no es parte de esta HU. Queda señalado para no perpetuarlo en silencio; la tabla de
entidades de §2 y el bloque de RLS (§5ter) sí están al día para esas 3 entidades.

## 4. Script de creación (DDL inicial)

Guardado en
[`05-codigo/database/migrations/001_init.sql`](../05-codigo/database/migrations/001_init.sql)
para que Backend/DevOps lo apliquen al levantar el entorno de desarrollo.

> **Nota operativa (2026-08-10, DBA) — por qué desde este ciclo también hay un
> `002_pacientes_historial_auth_google.sql`.** Hasta el ciclo anterior (§5bis), cada cambio de
> esquema se aplicaba editando `001_init.sql` en el lugar porque ningún Postgres había corrido
> todavía esa migración (`runMigrations()`, `05-codigo/backend/src/db.ts`, la gatea con un
> chequeo simple: "¿ya existe `public.usuario`?" → si existe, omite el script COMPLETO). Ese
> supuesto ya no vale: Render producción corrió su primera migración en el ciclo de §5bis
> (2026-08-09) y sigue activo — así que, por primera vez, editar `001_init.sql` **no alcanza**
> para que las tablas/columnas de HU-20/HU-21/HU-35 lleguen a esa base en el próximo deploy (el
> gate de `runMigrations()` salta el archivo entero sin error ni aviso). `001_init.sql` se
> actualizó igual en este ciclo (sigue siendo correcto para cualquier ambiente que migre desde
> cero) y, además, el delta para aplicar a mano contra un ambiente ya migrado vive en
> [`05-codigo/database/migrations/002_pacientes_historial_auth_google.sql`](../05-codigo/database/migrations/002_pacientes_historial_auth_google.sql)
> (no se corre solo — ver su propio header para el comando `psql` exacto). Recomendación de
> seguimiento para Backend/DevOps, no implementada acá: que `runMigrations()` pase a soportar una
> secuencia de migraciones numeradas con tabla de control, en vez de un único script gateado por
> la existencia de `usuario`.

> **Nota operativa (2026-08-11, DBA) — mismo patrón, ahora con
> `003_privacidad_usuario.sql`.** El mismo gap sigue vigente (Render producción ya corrió su
> migración, `runMigrations()` sigue gateada por "¿ya existe `usuario`?"), así que la tabla
> `usuario_preferencias` de HU-32 (§2septies) tiene el mismo problema que HU-20/HU-21/HU-35 en el
> ciclo anterior: editar `001_init.sql` (ya hecho, ambas copias) no alcanza para que Render la
> reciba en el próximo deploy. El delta para aplicar a mano vive en
> [`05-codigo/database/migrations/003_privacidad_usuario.sql`](../05-codigo/database/migrations/003_privacidad_usuario.sql)
> — mismo comando `psql "$DATABASE_URL" -f 003_privacidad_usuario.sql`, mismas garantías de
> idempotencia/reversibilidad que 002 (ver el propio header del archivo). Aplicado y verificado
> contra Render real por el Director General IA (2026-08-12, ver §5quater y el propio README del
> backend). Sigue en pie la misma recomendación de seguimiento para Backend/DevOps del párrafo
> anterior — cada ciclo que agrega esquema nuevo después del primer deploy de Render va a
> necesitar su propio archivo `00N_...sql` mientras `runMigrations()` no soporte una secuencia
> numerada con tabla de control.
>
> **Nota operativa (2026-08-12, DBA) — por qué el siguiente archivo incremental es
> `004_notificaciones.sql` y no `003_*`.** Mismo mecanismo que la nota de arriba (`001_init.sql`
> se actualizó igual, pero no alcanza para Render). El número "003" ya está tomado, en paralelo,
> por `003_privacidad_usuario.sql` (HU-32, `feature/configuracion-profesional`, todavía no
> mergeada a `main` al momento de escribir esta nota) — se reserva "004" acá para que ambas ramas
> no registren un "003" distinto que colisione al mergear. A diferencia de `002`/`003`, este
> archivo NO depende de que el anterior haya corrido: la tabla nueva que agrega
> (`usuario_preferencias_notificacion`, ver §2octies) es autocontenida a propósito, sin ninguna
> referencia a `usuario_preferencias` (la tabla de `003`) — se puede aplicar contra Render sin
> importar el orden en que se mergeen ambos ciclos. Aplicado y verificado contra Render real por
> el Director General IA (2026-08-12). Ver
> [`05-codigo/database/migrations/004_notificaciones.sql`](../05-codigo/database/migrations/004_notificaciones.sql).
>
> **Nota operativa (2026-08-14, DBA) — `005_suscripcion_negocio.sql` (HU-29/E11, §2novies).**
> Mismo mecanismo que las notas de arriba: `001_init.sql` (`05-codigo/database/migrations/`) se
> actualizó con la tabla `suscripcion_negocio` (correcto para cualquier ambiente que migre desde
> cero), pero no alcanza para Render — el delta vive en
> [`05-codigo/database/migrations/005_suscripcion_negocio.sql`](../05-codigo/database/migrations/005_suscripcion_negocio.sql),
> con el mismo backfill que ya usa `004` (ver su propio header) para las filas que hacen falta en
> un ambiente ya migrado: acá, una fila `suscripcion_negocio` en plan 'gratis' para cada `negocio`
> que ya existía antes de este ciclo (`INSERT ... SELECT id FROM negocio ON CONFLICT DO NOTHING`).
> **Diferencia respecto de los 3 ciclos anteriores, por instrucción explícita de este ciclo:** NO
> se tocó la copia operativa `05-codigo/backend/migrations/001_init.sql` (la que sí lee
> `runMigrations()`, ver `db.ts`) — solo la fuente de verdad de diseño en `database/migrations/`.
> Las 2 copias quedan divergentes hasta que un próximo ciclo de Backend las sincronice; no bloquea
> a Render (que de todos modos ignora `001_init.sql` una vez migrada, ver arriba) pero sí a
> cualquier ambiente nuevo que arranque desde la copia operativa (un docker-compose/CI/clon local
> recién creado no va a tener `suscripcion_negocio` hasta esa sincronización). **No aplicado
> todavía contra Render real** (a diferencia de `003`/`004`) — pendiente de que el Director
> General IA lo revise y lo corra, mismo flujo que los ciclos anteriores.
>
> **Nota operativa (2026-08-15, DBA) — `007_paciente_historial_acceso_administrador.sql`
> (fast-follow de la épica E15, ver §5septies).** Mismo mecanismo que las notas de arriba:
> `001_init.sql` se actualizó con las 3 policies `FOR SELECT` nuevas (correcto para cualquier
> ambiente que migre desde cero), pero no alcanza para Render — el delta vive en
> [`05-codigo/database/migrations/007_paciente_historial_acceso_administrador.sql`](../05-codigo/database/migrations/007_paciente_historial_acceso_administrador.sql).
> A diferencia del ciclo de `005`, **acá SÍ se sincronizaron ambas copias de `001_init.sql`**
> (`05-codigo/database/migrations/` y `05-codigo/backend/migrations/`, verificadas byte-idénticas
> en este mismo commit) — no queda la divergencia que sigue pendiente de `suscripcion_negocio`.
> Puramente aditivo, sin DDL de esquema y sin backfill: 3 `CREATE POLICY ... FOR SELECT`
> envueltos en un único bloque `DO` con guard contra `pg_policy` (mismo patrón que `005`). No toca
> ninguna de las 3 policies `FOR ALL` ya aplicadas contra Render por
> `002_pacientes_historial_auth_google.sql` — la escritura sobre
> `paciente`/`tratamiento`/`nota_medica` sigue exclusivamente en manos del profesional dueño de
> cada fila. **No aplicado todavía contra Render** (mismo patrón que `005`/`006`) — pendiente de
> que el Director General IA lo revise y lo corra, con aprobación del CEO, igual que los ciclos
> anteriores.
>
> **Nota operativa (2026-08-16, DBA) — `008_recuperacion_password.sql` (recuperación de
> contraseña, pedido del CEO, prioridad alta — ver §2decies/§5octies).** Mismo mecanismo que las
> notas de arriba: `001_init.sql` se actualizó con la tabla `token_recuperacion_password` nueva
> (correcto para cualquier ambiente que migre desde cero; **ambas copias sincronizadas y
> verificadas byte-idénticas**, mismo estándar que `007`), pero no alcanza para Render — el delta
> vive en
> [`05-codigo/database/migrations/008_recuperacion_password.sql`](../05-codigo/database/migrations/008_recuperacion_password.sql).
> Puramente aditivo, sin backfill (tabla nueva que nace vacía). **Diferencia respecto de los 7
> archivos anteriores: este NO se duplica en `05-codigo/backend/migrations/`** — verificado contra
> `backend/src/db.ts` que `runMigrations()` lee únicamente el nombre de archivo hardcodeado
> "001_init.sql" (nunca hace glob del directorio) y confirmado que ninguno de los incrementales
> 002–007 tiene copia ahí tampoco (ese directorio solo contiene `001_init.sql`) — es el patrón ya
> establecido en los 5 ciclos anteriores, no una omisión de este ciclo. **No aplicado todavía
> contra Render** (mismo patrón que `005`/`006`/`007`) — pendiente de que el Director General IA lo
> revise y lo corra, con aprobación del CEO.
>
> **Nota operativa (2026-08-17, DBA) — `009_negocio_datos_operativos.sql` (HU-31 — horario general
> de atención, dirección detallada, teléfono, logo, ver §2undecies).** Mismo mecanismo que las
> notas de arriba: `001_init.sql` se actualizó con las 4 columnas nuevas en `negocio`, todas
> nullable (correcto para cualquier ambiente que migre desde cero; **ambas copias sincronizadas y
> verificadas byte-idénticas con `diff`**, mismo estándar que `007`/`008`), pero no alcanza para
> Render — el delta vive en
> [`05-codigo/database/migrations/009_negocio_datos_operativos.sql`](../05-codigo/database/migrations/009_negocio_datos_operativos.sql).
> Puramente aditivo, sin backfill (nullable sin `DEFAULT`; a diferencia de `005`, acá no hay ningún
> valor por defecto razonable que backfillear — son datos que solo cada administrador conoce de su
> propio negocio) y sin cambios de RLS/índices (`negocio` sigue sin RLS habilitada). **Mismo
> patrón que `008`: este archivo NO se duplica en `05-codigo/backend/migrations/`** — mismo motivo
> ya verificado ahí contra `runMigrations()`/`backend/src/db.ts` (lee únicamente el nombre de
> archivo hardcodeado `"001_init.sql"`, nunca hace glob del directorio). **No aplicado todavía
> contra Render** (mismo patrón que los ciclos anteriores) — pendiente de que el Director General
> IA lo revise y lo corra, con aprobación del CEO. Sin cambios de Backend/Mobile en este ciclo
> (fuera de alcance de DBA) — recomendación de dónde extender `PATCH /negocios/:id` en §2undecies.

## 5. Row Level Security (Postgres, producción)

Implementado en el DDL (`05-codigo/database/migrations/001_init.sql`), **no verificado contra
un Postgres real** — este entorno de desarrollo no tiene `psql`/Docker instalados (ver
`memory/proyectos/turnos-profesionales/decisiones.md`). Antes de aplicarlo en un entorno real,
correrlo contra una instancia de prueba.

> **Nota (2026-08-09):** esta sección describe el diseño de las *políticas* de RLS, que sigue
> vigente sin cambios. Pero se descubrió (Backend, al conectar este esquema a un Postgres real por
> primera vez) que un supuesto estructural de esta sección — "el backend debe ejecutar `SET LOCAL
> app.usuario_id`... sin eso, las políticas de escritura deniegan" — **no alcanzaba por sí solo**:
> el rol de conexión de la app resultaba ser owner de las tablas (y, en docker-compose/CI,
> superusuario), y Postgres ignora RLS por completo para el owner/superusuario salvo un mecanismo
> adicional (`FORCE ROW LEVEL SECURITY`) que esta sección nunca mencionaba. Ver **§5bis** para el
> diagnóstico completo, el cierre aplicado en este ciclo, y las 3 policies nuevas que agregó
> Backend (ratificadas por DBA) para conectar este diseño a los endpoints reales.

Diseño (no es un simple "todo por `negocio_id`" — hay una tensión real que había que resolver).
**Actualizado (2026-08-06) por la generalización N:M de §2ter** — ver esa sección para el
motivo del cambio; acá solo se documenta el diseño de RLS resultante.

- **Por qué `current_setting('app.negocio_id')` (un único valor) ya no alcanza:** antes, un
  actor tenía a lo sumo un `negocio_id` válido, así que comparar por igualdad contra un único
  valor de sesión bastaba. Ahora un mismo usuario puede administrar o trabajar en 2+ negocios
  simultáneamente, y una variable de sesión solo guarda un valor — comparar contra un único
  "negocio activo" reintroduciría el mismo patrón de riesgo que causó CRITICAL-1 (confiar en un
  valor sin re-derivarlo contra la relación persistida real). Por eso las políticas de escritura
  pasan de `negocio_id = current_setting('app.negocio_id')` a `EXISTS (...)` contra
  `negocio_administrador`/`negocio_profesional`, ancladas en `app.usuario_id` — cada fila se
  re-verifica contra la tabla de membresía real en cada chequeo, no contra un claim cacheado.
  Esto vuelve innecesaria la variable de sesión `app.negocio_id` para RLS específicamente (el
  backend puede seguir usando un claim `negocio_id` en el JWT para su propia lógica de
  aplicación — ver §2ter, "vista activa" — pero es una capa distinta de esta).
- **`profesional`**: ya no tiene `negocio_id` propio, así que pasa a comportarse como una
  identidad (similar a `usuario`) en vez de un recurso propiedad de un negocio. `SELECT` sigue
  público (CU3/HU-07/HU-08); `INSERT` acotado a que el actor sea administrador de algún negocio
  (la fila en sí no lleva negocio_id — el negocio concreto se fija recién en el `INSERT` sobre
  `negocio_profesional`); `UPDATE` acotado a un administrador de alguno de los negocios donde
  ese profesional está efectivamente vinculado hoy.
- **Hallazgo nuevo sobre esta misma política de `profesional` (D10, 2026-08-06, ver §2quater):**
  el `UPDATE` de arriba solo habilita a un ADMINISTRADOR del negocio a escribir sobre
  `profesional` — no hay ninguna política que permita al propio profesional actualizar su propia
  fila. Es un problema concreto ahora que `duracion_cita_min` (§2quater) es, según RN11, un valor
  que configura el profesional mismo, no el administrador: bajo RLS activa tal como está hoy, ese
  `UPDATE` quedaría denegado por defecto (fail-closed). No bloquea nada en este momento porque RLS
  todavía no está conectada al backend (ver el párrafo introductorio de esta sección), pero hay
  que resolverlo antes de conectarla. No se agrega la policy en este slice porque no es una
  decisión trivial: una policy de auto-servicio de fila completa también dejaría al profesional
  tocar columnas que no debería (ej. `eliminado_en`, su propio soft-delete) — una policy de fila
  no distingue columnas por sí sola. Alternativas a evaluar por DBA/Backend en el próximo ciclo:
  una policy acotada al propio `usuario_id` combinada con un chequeo a nivel de aplicación de qué
  columnas puede enviar el profesional (mismo patrón que ya usa Backend con validación `zod` en
  otros endpoints), o una función `SECURITY DEFINER` acotada a las columnas de auto-servicio.
- **`negocio_administrador`** (nueva): `SELECT` acotado a las propias membresías
  (`usuario_id = app.usuario_id`) — no público, a diferencia de `profesional`/`servicio`, porque
  no hace falta que un cliente anónimo sepa quién administra qué negocio. `INSERT` solo permite
  que un usuario se dé de alta a **sí mismo** como administrador, nunca a un `usuario_id` de
  terceros. Sin `UPDATE` (no tiene atributos mutables) ni `DELETE` (no hay HU de "revocar
  administrador" todavía — documentado como extensión futura, no implementada).
- **`negocio_profesional`** (nueva): `SELECT` público — igual que `profesional`/`servicio`,
  hace falta para que HU-08 pueda resolver qué profesionales pertenecen a un negocio sin login.
  `INSERT`/`UPDATE` (alta y activar/desactivar la membresía, HU-02) acotados a administradores
  del `negocio_id` involucrado, verificado con `EXISTS` contra `negocio_administrador`.
- **`servicio`**: `SELECT` público sin cambios; `INSERT`/`UPDATE` pasan de comparar
  `negocio_id = current_setting('app.negocio_id')` a `EXISTS` contra `negocio_administrador`
  para ese `servicio.negocio_id` — mismo cambio que el resto, misma razón.
- **`turno`**: nunca es de lectura pública. Lo consultan/tocan el **cliente dueño de la reserva**
  (scope por `cliente_id`, sin cambios — un cliente reserva en varios negocios y su JWT nunca
  llevó `negocio_id`, ver `backend/src/auth.ts`) o el **staff del negocio** — administrador o
  profesional, ahora vía `EXISTS` contra `negocio_administrador`/`negocio_profesional` en vez de
  igualdad contra `app.negocio_id`. Sigue sin acotar a un profesional a ver solo sus propios
  turnos dentro del negocio (cualquier staff del negocio pasa el chequeo de RLS; ese filtro más
  fino lo aplican los endpoints) — no se restringe más para no exceder el alcance de este cambio.
- El backend debe ejecutar `SET LOCAL app.usuario_id = '...'` al inicio de cada transacción
  autenticada — sin eso, `current_setting(..., true)` devuelve `NULL` y las políticas de
  escritura deniegan por defecto (fail-closed). **Esto todavía no está conectado en el backend
  actual** (que usa `node:sqlite` para desarrollo, sin RLS) — es trabajo pendiente para cuando
  el backend apunte a Postgres.
  > **Actualización (2026-08-09):** esto ya se conectó (Backend migró a `pg`/Postgres real,
  > `withTransaction` en `db.ts` ejecuta exactamente este `SET LOCAL` vía `set_config`) — pero
  > conectarlo no alcanzó para que RLS tuviera efecto real, por el gap de ownership que describe
  > **§5bis**. Este párrafo se conserva sin editar porque el diagnóstico original ("sin `SET
  > LOCAL`, fail-closed") sigue siendo correcto como descripción de las políticas en sí — §5bis
  > documenta la capa adicional que hacía falta por debajo de esto.
- Pendiente para una próxima iteración (sin cambios por esta generalización): `disponibilidad`,
  `excepcion_disponibilidad`, `profesional_servicio`, `pago` y `notificacion` no tienen
  `negocio_id` propio (se llega por join a través de `profesional_id`/`turno_id`); necesitarían
  una política basada en subquery, no incluida en este slice. Si en una próxima iteración se
  agregan, deberían seguir el mismo patrón `EXISTS`/`app.usuario_id` de esta sección, no el
  patrón anterior de igualdad contra `app.negocio_id`.

## 5bis. Cierre del gap de ownership + ratificación de las 3 policies de Backend (DBA, 2026-08-09)

**Origen.** Backend conectó el esquema de §5 a un Postgres real por primera vez
(TURNOS-2026-001, migración `node:sqlite` → `pg`, ver `05-codigo/backend/README.md` y
`memory/proyectos/turnos-profesionales/decisiones.md`). Encontró y documentó un hallazgo de
arquitectura, y agregó 3 policies nuevas (marcadas `-- [BACKEND] ... pendiente de ratificación`)
que necesitaba para que 2 endpoints ya probados siguieran funcionando bajo RLS real. Ambas cosas
llegaron a DBA para decisión — este apartado documenta esa decisión, verificada de forma
independiente contra el código real (no solo aceptada del reporte de Backend), y la revisión en
paralelo de Security sobre el mismo cambio (mismo patrón de doble revisión que ya se usó en
Fase 5).

### Gap 1 — el rol de conexión es owner de las tablas (y, en 2 de 3 ambientes, superusuario)

`runMigrations()` (`05-codigo/backend/src/db.ts`) corre el DDL completo con el mismo `pool`/rol de
conexión que sirve **todo** el tráfico de la app — una sola `DATABASE_URL` por ambiente (ver
`05-codigo/backend/docker-compose.yml`, `.github/workflows/turnos-backend-ci.yml`,
`05-codigo/backend/render.yaml`). En Postgres, quien ejecuta `CREATE TABLE` se vuelve
automáticamente **owner** de esa tabla, y Postgres ignora RLS por completo para el owner (y para
cualquier rol con `BYPASSRLS`/superusuario) salvo que la tabla tenga `FORCE ROW LEVEL SECURITY` —
mecanismo que §5 nunca mencionaba y que ninguna tabla tenía hasta este ciclo. El propio párrafo de
§5 ("el rol de conexión... NO debe ser el owner...") ya advertía el riesgo desde la Fase 3
original, pero nunca se había cerrado con algo ejecutable. Conclusión verificada: **hasta este
ciclo, todo el trabajo de RLS de este proyecto podía no tener ningún efecto real en ningún
ambiente** — la autorización real la seguían haciendo únicamente los `WHERE` de cada query + los
checks de cada handler (ninguno de los dos deja de existir ni se debilita con este cambio: RLS es
defensa **en profundidad**, adicional a esos checks, nunca el único mecanismo de autorización de
este proyecto).

**Arreglo en dos capas, aplicado en `05-codigo/database/migrations/001_init.sql`
(+ copia idéntica en `05-codigo/backend/migrations/001_init.sql`):**

1. **`FORCE ROW LEVEL SECURITY`** en las 5 tablas con RLS habilitada — un comando por tabla,
   aplicado ya en este ciclo. Corrige que el owner deje de bypassear RLS, **solo si** el rol de
   conexión no es superusuario ni tiene `BYPASSRLS` explícito.
2. **Separar un rol de MIGRACIÓN (owner) de un rol de RUNTIME** (sirve `DATABASE_URL` de la app,
   sin ser owner y sin `BYPASSRLS`) — la separación que el diseño original de §5 ya asumía. Es la
   **única** capa que garantiza RLS real en los 3 ambientes, por un motivo verificado, no solo
   teórico: el rol que crean `docker-compose.yml` (`turnos`) y el service container de CI
   (`turnos_ci`) vía la variable `POSTGRES_USER` de la imagen oficial `postgres:16-alpine` se crea
   como **superusuario del cluster** (comportamiento documentado de esa imagen oficial: "This
   variable will create the specified user with superuser power") — y un superusuario bypassea
   RLS siempre, `FORCE` incluido. Es decir: **en docker-compose y en CI, la capa 1 sola no tiene
   ningún efecto real hoy**, sin que nada lo indique (`scripts/*.mjs` no puede distinguir "pasó
   porque RLS filtró correctamente" de "pasó porque RLS nunca se evaluó"). En Render, el rol que
   provisiona el Blueprint (`turnos_profesionales`) no debería ser superusuario (los proveedores
   de Postgres gestionado no suelen otorgarlo) — **no verificado contra una cuenta real de
   Render**, mismo tipo de limitación que ya documenta `08-despliegue/README.md`; diagnóstico
   exacto para confirmarlo (sugerido por Security):
   `SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;`.

**Tarea de seguimiento para DevOps (no ejecutada en este ciclo — fuera del alcance de DBA, que no
implementa cambios en `docker-compose.yml`/CI/`render.yaml`):** provisionar los 2 roles por
ambiente y repuntar `DATABASE_URL` de la app al rol de RUNTIME. Instrucciones exactas, GRANTs
completos y la secuencia de adopción (incluido cómo sigue funcionando `runMigrations()` **sin
ningún cambio de código**, gracias a que ya está gateada por "¿existe `public.usuario`?") en
[`05-codigo/database/scripts/provisionar_roles_postgres.sql`](../05-codigo/database/scripts/provisionar_roles_postgres.sql).
Recomendación adicional para QA/DevOps: la primera vez que RLS tenga efecto real en cualquier
ambiente (hoy nunca lo tuvo, ni siquiera en CI), re-correr la batería completa de
`05-codigo/backend/scripts/*.mjs` en ese ambiente antes de confiar en el resultado — pueden
aparecer fallos que estuvieron enmascarados por el bypass total de RLS, no necesariamente
introducidos por este cambio.

**Verificación de RLS a nivel de base de datos (pedido explícito de Security — ningún test HTTP
existente puede detectar este tipo de gap, porque la autorización de aplicación cubre el mismo
terreno y lo esconde):**
[`05-codigo/database/scripts/verificar_rls_postgres.sql`](../05-codigo/database/scripts/verificar_rls_postgres.sql) —
se conecta directo con los roles reales (sin pasar por la app), siembra datos de 2 tenants, y
verifica con `SET ROLE`/aserciones que el aislamiento cross-tenant y el cierre del gap de
ownership funcionan de verdad. No ejecutado en este ciclo (este entorno no tiene `psql`/Docker,
mismo caveat de siempre) — pendiente de correr contra un Postgres real la primera vez que exista
un ambiente con los roles ya separados.

### Gap 2 (ratificación) — las 3 policies nuevas de Backend

Las 3 quedaban en `05-codigo/backend/migrations/001_init.sql`, marcadas como pendientes de
ratificación. Verificadas por DBA contra el código real de cada endpoint involucrado (no solo
aceptadas del razonamiento de Backend) y ya incorporadas a la fuente de verdad
(`05-codigo/database/migrations/001_init.sql`, con el mismo razonamiento en el comentario junto a
cada `CREATE POLICY`):

1. **`profesional_update_propio_duracion_cita`** — **ratificada tal cual, sin cambios.** Resuelve
   un gap que el propio §5 dejaba documentado (2 alternativas evaluadas, sin decidir): el
   profesional necesita poder actualizar su propia `duracion_cita_min` (D10/RN11,
   `PATCH /profesionales/:id/configuracion`), y la única policy de `UPDATE` existente sobre
   `profesional` solo habilitaba a un administrador. Se eligió la alternativa (a) — policy
   acotada a `usuario_id` propio — sobre la (b) (función `SECURITY DEFINER`) porque, verificado
   contra `05-codigo/backend/src/routes/profesionales.ts`, ese endpoint es HOY el único call site
   de todo el código que ejecuta `UPDATE profesional ...` con el `usuario_id` del propio
   profesional en su contexto RLS, con un statement hardcodeado (sin nombres de columna dinámicos)
   que solo toca `duracion_cita_min` — no hay hoy ningún camino para que un profesional autenticado
   toque otra columna de su propia fila (ej. `eliminado_en`) a través de esta policy. Si se agrega
   un segundo endpoint de auto-servicio sobre `profesional`, hay que re-verificar esto explícitamente.

2. **`turno_select_publico`** — **ratificada CON RESERVA, explícitamente TRANSITORIA.** La más
   sensible de las 3: hace público (`USING (true)`, sin ningún chequeo) el `SELECT` completo de
   `turno`. Necesaria para 2 cosas verificadas contra el código real:
   - `GET /profesionales/:id/slots` (público, HU-09/CU1) — y, hallazgo **adicional** de esta
     revisión que Backend no había señalado: la validación interna RN1/RN2 de `POST /turnos`
     (`calcularSlotsDisponibles(pool, ...)`, invocada dos veces desde
     `05-codigo/backend/src/routes/turnos.ts`) lee `turno` por `pool` DIRECTO — igual que el
     endpoint público, sin contexto RLS, incluso cuando quien reserva SÍ está autenticado. Sin
     esta policy, `POST /turnos` podría aceptar una reserva solapada con otra existente si no
     coincide exactamente con el `(profesional_id, inicio)` que protege `uq_turno_slot_activo` —
     una regresión de RN2, no solo de privacidad.
   - La distinción 403/404 que exige `scripts/test-autorizacion-cruzada.mjs` al
     cancelar/reprogramar el turno de otro cliente (`SELECT * FROM turno WHERE id = $1` sin
     filtrar por `cliente_id`, ver `turnos.ts`).

   **Por qué queda como transitoria, no permanente (coincidencia con Security):** es una policy
   PERMISIVA de `SELECT` — se combina por OR con `turno_acceso_negocio_o_cliente`, así que mientras
   exista, esa otra policy queda irrelevante para lectura sin importar qué tan bien diseñada esté.
   Security, en su revisión independiente, coincidió en que hace falta hoy pero recomendó no
   dejarla como diseño permanente, y sugirió reemplazarla por funciones `SECURITY DEFINER`
   acotadas por caso de uso. **Se agregaron en este mismo ciclo** (`turno_ocupacion_publica` y
   `turno_propio_para_gestion`, al final de `001_init.sql`) pero **no se adoptaron todavía**:
   adoptarlas requiere que Backend deje de leer `turno` por `pool`/`SELECT *` suelto en
   `disponibilidad.ts`/`turnos.ts` y llame a las funciones en su lugar — cambio de código de
   Backend, fuera del alcance de este ciclo (instrucción explícita de no tocar rutas/`db.ts`).
   Retirar `turno_select_publico` sin que Backend adoptara las funciones en el mismo cambio
   habría reproducido exactamente el riesgo que señaló Security (dos cambios que se pisan) — así
   que se prioriza no romper nada por sobre cerrar el hallazgo del todo en este ciclo.

   **Secuencia de adopción recomendada para el próximo ciclo (conjunto Backend+DBA):**
   1. Backend reemplaza las 3 lecturas sueltas de `turno` (`disponibilidad.ts:94-97` y los 2 call
      sites de `calcularSlotsDisponibles(pool, ...)` en `turnos.ts`, más
      `turnos.ts:225`/`turnos.ts:294`, los `SELECT * FROM turno WHERE id = $1` de
      `cancelar`/`reprogramar`) por llamadas a `turno_ocupacion_publica`/`turno_propio_para_gestion`.
   2. DBA (o quien ejecute el cambio) resuelve la advertencia ya documentada en el comentario de
      esas funciones en `001_init.sql`: con `FORCE ROW LEVEL SECURITY` activo, una función
      `SECURITY DEFINER` propiedad del rol de MIGRACIÓN **no** bypassea RLS por sí sola (FORCE
      aplica las políticas al owner incluso dentro de una función que ese owner posee) — hace
      falta, en el mismo cambio, un tercer rol `NOLOGIN` con `BYPASSRLS` explícito, dueño
      ÚNICAMENTE de esas 2 funciones (recomendado), o aceptar conscientemente el trade-off de
      otorgarle `BYPASSRLS` al rol de migración (no recomendado). Detalle completo en el
      comentario de las funciones, `001_init.sql`.
   3. Recién ahí, `DROP POLICY turno_select_publico ON turno;` (reversible por diseño: una única
      sentencia) + re-correr `scripts/*.mjs` y `verificar_rls_postgres.sql`.

   **Si la conclusión de Security sobre esta policy en particular no hubiera coincidido con la de
   DBA, decide el Director General IA — no se resuelve unilateralmente entre DBA y Security.**

3. **`turno_acceso_job_expiracion`** — **ratificada tal cual, sin cambios.** La menos
   controvertida: acotada exclusivamente a `app.job_sistema = 'true'` (solo lo setea
   `expirarPagosPendientesVencidos()`, `05-codigo/backend/src/jobs/expirarPagosPendientes.ts`), y
   solo agrega `UPDATE` — el `SELECT` del propio job ya queda cubierto por `turno_select_publico`.
   Ya estaba anticipada por el comentario de `ContextoRls.jobSistema` en `db.ts` (código ya
   aprobado, sin cambios).

### Qué no se tocó en este ciclo

Código de Backend (`src/routes/`, `src/dominio/`, `db.ts`) — instrucción explícita. `pago` y
`notificacion` siguen sin RLS habilitada (gap preexistente, ya documentado en §5 como "pendiente
para una próxima iteración", no ampliado acá). `docker-compose.yml`, `.github/workflows/
turnos-backend-ci.yml`, `05-codigo/backend/render.yaml` — son tarea de seguimiento de DevOps, no
implementados por DBA (ver script de aprovisionamiento).

## 5ter. RLS de `paciente`/`tratamiento`/`nota_medica` (HU-20/HU-21, DBA, 2026-08-10)

Aplicando desde el primer commit la lección de §5bis: **las 3 tablas nuevas llevan `FORCE ROW
LEVEL SECURITY` además de `ENABLE`**, no solo `ENABLE` — el gap de ownership que dejó toda la RLS
de este proyecto sin efecto real hasta 2026-08-09 aplicaría igual, desde el día 1, a cualquier
tabla nueva que se olvide del `FORCE`.

**Criterio, más estricto que `turno`/`servicio`:** a diferencia de esas tablas (visibles para
cualquier staff del negocio — administrador o cualquier profesional activo), acá la policy exige
que el actor sea **específicamente el profesional dueño de la fila** (`paciente.profesional_id`,
o el `profesional_id` del `paciente` al que cuelga el `tratamiento`/`nota_medica`) — RN7/RN13/D3.
Ni el administrador del negocio ni otro profesional del mismo negocio pasan esta policy; coincide
con el default ya documentado en `documento-funcional.md` §6 ("A7/D3 dejan al administrador sin
acceso al historial por defecto"), que ese documento deja como pregunta menor todavía abierta —
**no se cierra acá**: si el CEO confirma en un próximo ciclo que el administrador sí debe tener
acceso, sumar una policy adicional (`OR EXISTS` contra `negocio_administrador`, mismo patrón que
`turno`) es aditivo, no rompe la actual. Tampoco hay policy para que el propio cliente/paciente
vea su ficha — ninguna HU de este ciclo pide esa vista desde el modo Cliente de Mobile.

- **`paciente`**: policy única (sin `FOR`, aplica a todos los comandos) — `EXISTS` contra
  `negocio_profesional` + `profesional`, verificando a la vez (a) que el actor autenticado ES el
  profesional referenciado (`p.usuario_id = app.usuario_id`) y (b) que ese `(negocio_id,
  profesional_id)` corresponde a una membresía real — reforzando aislamiento de tenant además de
  privacidad por profesional, no solo lo segundo.
- **`tratamiento`/`nota_medica`**: NO repiten `negocio_id`/`profesional_id` propios (ver
  §2quinquies) — la policy se ancla en `paciente` vía `JOIN`, reusando exactamente el mismo
  criterio de dueño único, para que nunca puedan quedar desincronizadas entre sí.

Detalle línea por línea de cada policy en `05-codigo/database/migrations/001_init.sql` (bloque
"RLS de paciente/tratamiento/nota_medica") y en
`002_pacientes_historial_auth_google.sql` (mismas policies, envueltas en bloques `DO` con guard
contra `pg_policy` para que ese script sí sea reintentable — ver nota de idempotencia en su
header). **No verificado contra un Postgres real** en este ciclo (mismo caveat que el resto de
este documento) — prioridad para quien retome Backend: correr `002_pacientes_historial_auth_google.sql`
contra un ambiente de prueba antes que contra Render producción.

### Cierre del loop con la revisión de Security en paralelo (adenda 2026-08-10, parte B)

Security revisó HU-20 en paralelo a este mismo modelado (`07-seguridad/informe-seguridad.md`,
Adenda 2026-08-10) y señaló, dos veces, a DBA por nombre ("punto de modelado urgente para DBA, que
está extendiendo este mismo esquema en paralelo ahora mismo"). Contraste explícito contra su
checklist:

- **"Acceso restringido por profesional (no solo por negocio)"** — YA satisfecho por el diseño de
  arriba: `paciente`/`tratamiento`/`nota_medica` no siguen el patrón de `turno`/`servicio`
  (cualquier staff del negocio); la policy exige específicamente que el actor sea el profesional
  dueño de la fila. Coincide, de forma independiente, con el mismo razonamiento (scope por
  `profesional_id`+`cliente_id`) que Security documentó por su cuenta antes de ver este DDL.
- **"Prueba de regresión automática dedicada (mismo espíritu que
  `test-autorizacion-cruzada.mjs`)"** — NO implementada en este ciclo (es un script de QA/Backend
  contra un Postgres real corriendo, no DDL) — queda como recomendación pendiente para el próximo
  ciclo de Backend/QA, con el caso concreto que debería cubrir: profesional A no debe poder leer
  ni escribir la ficha/tratamientos/notas de un paciente que nunca atendió, aunque comparta
  negocio con el profesional que sí lo atendió.
- **"Log de auditoría de accesos (lectura y escritura) a estos campos"** — **NO implementado en
  este ciclo, gap reconocido explícitamente.** `creado_por`/`modificado_por` en `paciente`
  cubren quién creó/modificó la fila por última vez (una sola vez, no un historial), pero no un
  log de cada acceso, y no cubren LECTURAS en absoluto — Postgres no tiene un mecanismo de
  trigger sobre `SELECT` equivalente al de `INSERT`/`UPDATE`/`DELETE`, así que un log de lecturas
  requiere necesariamente registrar el acceso desde la capa de aplicación (en el handler del
  endpoint, no en el DDL) o habilitar una extensión de auditoría a nivel de sesión (ej.
  `pgaudit`, decisión de infraestructura, fuera del alcance de DBA). Boceto de la tabla para
  cuando se implemente (no creada en este ciclo): `paciente_acceso_log(id, paciente_id,
  usuario_id, accion, campos TEXT[] o TEXT, creado_en)` — se deja documentado acá en vez de
  perderse, en línea con la advertencia de Security de que es "razonablemente barato agregar
  ahora... más caro de hacer retrofit después", pero no se prioriza sobre entregar HU-20/HU-21/
  HU-35 en este ciclo. Explícitamente NO bloqueante de Fases 3–5 (mismo criterio que el resto de
  esta adenda) — sí queda como parte del checklist antes de producción con datos reales.

## 5quater. RLS de `usuario_preferencias` (HU-32, DBA, 2026-08-11)

Aplicando la misma lección de §5bis/§5ter: **tabla nueva, `FORCE ROW LEVEL SECURITY` desde el
primer commit**, no solo `ENABLE`.

**Criterio — más simple que `paciente`/`tratamiento`/`nota_medica` (§5ter): una única policy,
sin `FOR`, aplica a los 4 comandos (SELECT/INSERT/UPDATE/DELETE) por columna directa
(`usuario_id = app.usuario_id`), sin `JOIN`.** No hace falta el patrón `EXISTS` contra
`negocio_profesional`/`profesional` que usa `paciente`: acá no hay negocio ni profesional de por
medio, la propiedad es directa entre la fila y el usuario dueño de la cuenta — mismo criterio de
columna simple ya usado en `negocio_administrador_select_propio` y
`profesional_update_propio_duracion_cita` (§5bis), no el criterio con `JOIN` de §5ter. Cada
usuario lee/edita únicamente su propia fila; no hay ninguna vía de acceso para administradores,
otros profesionales, ni el propio Backend fuera del contexto `SET LOCAL app.usuario_id` de la
transacción autenticada del dueño.

Ver la conclusión completa sobre por qué `usuario` en sí (a diferencia de esta tabla nueva) sigue
sin RLS habilitada, y por qué eso no se resuelve en este ciclo, en **§2septies**. Detalle línea
por línea de la policy en `05-codigo/database/migrations/001_init.sql` (bloque "Preferencias de
privacidad de usuario") y en `003_privacidad_usuario.sql` (misma policy, envuelta en un bloque
`DO` con guard contra `pg_policy` para que ese script sea reintentable — ver su propio header).
**Verificado contra un Postgres real** por el Director General IA (2026-08-12): aplicado contra
Render producción y confirmado con contexto RLS real (`set_config('app.usuario_id', ...)`) que
cada cuenta solo ve/edita su propia fila. `verificar_rls_postgres.sql` todavía no cubre esta
tabla (mismo gap que ya tiene para `paciente`/`tratamiento`/`nota_medica`) — pendiente para un
ciclo futuro de QA/Security.

## 5quinquies. RLS de la bandeja de notificaciones + preferencias de notificación (HU-14b/HU-25/HU-26, DBA, 2026-08-12)

Cierra un gap que la propia sección 5 de este documento ya dejaba anotado como pendiente ("`pago`
y `notificacion` no tienen `negocio_id` propio... necesitarían una política basada en subquery, no
incluida en este slice" — ver más arriba en esta misma sección): `notificacion` existe desde la
Fase 3 original SIN ninguna policy de RLS. No se había cerrado antes porque, hasta este ciclo, la
tabla no tenía ninguna noción de "de quién es cada fila" — sin `destinatario_usuario_id` no había
nada que proteger. FORCE desde el primer commit para la tabla nueva
(`usuario_preferencias_notificacion`) y, por primera vez, también para `notificacion` — misma
lección de §5bis.

**`notificacion` — 3 policies, ninguna cubre todos los comandos:**

- **SELECT/UPDATE ("ver mi bandeja"/"marcar como leída")**: estrictamente acotado al propio
  destinatario (`destinatario_usuario_id = app.usuario_id`) — la bandeja es personal, sin
  excepción para staff del negocio ni para quien originó el evento. El `WITH CHECK` del UPDATE es
  simétrico al `USING` a propósito, mismo patrón que `usuario_preferencias_acceso_propio`/
  `turno_acceso_negocio_o_cliente`: impide que la fila cambie de dueño vía el mismo UPDATE.
- **INSERT ("generar un aviso")**: necesariamente más ancha, y a propósito — verificado contra
  el código real que el actor casi nunca es el propio destinatario (ej. un cliente reserva:
  `app.usuario_id` es el cliente durante toda la transacción de `POST /turnos`, pero el
  destinatario de la notificación es el profesional). Replicar acá el truco que sí usa
  `POST /turnos` para `paciente` (un `set_config` a mitad de transacción) habría requerido tocar
  turnos.ts, fuera de alcance — en cambio, la policy verifica que TANTO el actor COMO el
  destinatario sean participantes del MISMO `turno_id`: el actor con el mismo criterio ancho que
  `turno_acceso_negocio_o_cliente` (cliente dueño, o cualquier staff del negocio), el destinatario
  con un criterio más angosto (cliente dueño, o específicamente el profesional ASIGNADO — no
  cualquier staff). Acepta explícitamente `destinatario_usuario_id IS NULL` — sin esto, los 2 call
  sites que hoy insertan sin esa columna (POST /turnos, PATCH /:id/reprogramar) habrían quedado
  bloqueados por RLS apenas esta migración tuviera efecto real, una regresión que este ciclo no
  puede introducir (no se toca código de Backend).
- **INSERT adicional para el futuro job de recordatorio** (`app.job_sistema = 'true'`): mismo
  criterio que `turno_acceso_job_expiracion` — un job que recorre turnos de cualquier
  cliente/negocio en un solo barrido no actúa "como" ningún usuario puntual. Ese job todavía no
  existe (ver §2octies) — policy dejada lista para cuando Backend lo implemente, mismo criterio
  que las funciones `SECURITY DEFINER` de `001_init.sql` (preparadas antes de que el código las
  use).

Sin policy de DELETE — mismo motivo que `negocio_administrador`: ningún endpoint/HU de este ciclo
borra notificaciones.

**`usuario_preferencias_notificacion`**: policy única simétrica
(`usuario_id = app.usuario_id`, sin JOIN), idéntica en forma a
`usuario_preferencias_acceso_propio` (HU-32).

Detalle línea por línea de cada policy en `05-codigo/database/migrations/001_init.sql` (bloque
"RLS de la bandeja de notificaciones + preferencias de notificación") y en
`004_notificaciones.sql` (mismas policies, envueltas en bloques `DO` con guard contra `pg_policy`
para que ese script sea reintentable). **No verificado contra un Postgres real** en este ciclo
(mismo caveat que el resto de este documento — no hay `psql`/Docker en este entorno de
desarrollo) — prioridad para quien retome Backend: correr `004_notificaciones.sql` contra un
ambiente de prueba antes que contra Render producción, con foco particular en el INSERT de
`POST /turnos`/`PATCH /:id/reprogramar` tal como están hoy (sin `destinatario_usuario_id`), para
confirmar empíricamente que la policy de compatibilidad (`IS NULL`) realmente los deja pasar.

**Verificado contra un Postgres real** por el Director General IA (2026-08-12): reserva de turno
→ INSERT de `confirmacion` pasa la policy; cancelación → INSERT de `cancelacion` pasa la policy;
lectura de la bandeja con contexto real (`set_config('app.usuario_id', ...)`) muestra solo las
notificaciones propias. La policy de compatibilidad `IS NULL` y el criterio de INSERT amplio
(actor ≠ destinatario) quedaron confirmados end-to-end, no solo en el diseño.

## 5sexies. RLS de `suscripcion_negocio` (HU-29/E11, DBA, 2026-08-14)

FORCE desde el primer commit (misma lección de §5bis/§5ter/§5quater/§5quinquies: cualquier tabla
nueva la necesita desde el día 1). A diferencia de `usuario_preferencias_acceso_propio`/
`usuario_preferencias_notificacion_acceso_propio` (una única policy simétrica, mismo criterio de
lectura y escritura), acá hacen falta **3 policies separadas** porque el pedido de esta ronda es
asimétrico: "administrador del negocio, y lectura para profesionales de ese negocio" — quién lee
es más amplio que quién escribe.

- **SELECT** — cualquier STAFF del negocio, administrador **o** profesional activo en ese
  `negocio_id`: mismo criterio `EXISTS`/`OR` que `turno_acceso_negocio_o_cliente` (§5), sin la
  rama de `cliente_id` (ningún caso de uso de este ciclo necesita que un cliente vea el plan del
  negocio). Sin filtrar por `negocio_profesional.activo` — mismo criterio ya aplicado en
  `paciente_acceso_propio_profesional` (§5ter) y en la rama de staff de
  `turno_acceso_negocio_o_cliente`, ninguna de las dos lo exige. Es lo que le permite a Mobile
  mostrar "gratis: 42/60 turnos este mes" tanto al administrador como a cualquier profesional del
  negocio.
- **INSERT/UPDATE** — solo ADMINISTRADOR del negocio: mismo criterio que
  `servicio_insert_admin_del_negocio`/`servicio_update_admin_del_negocio` (§5) — un profesional
  puede ver el estado del plan, pero gestionar la suscripción (dato de facturación del negocio) es
  una decisión de administrador, igual que dar de alta un servicio o un profesional. El UPDATE no
  lleva `WITH CHECK` explícito (a diferencia de `turno_acceso_negocio_o_cliente`/
  `usuario_preferencias_acceso_propio`) — mismo criterio que `servicio_update_admin_del_negocio`:
  Postgres reutiliza el `USING` como chequeo de la fila nueva cuando no se da un `WITH CHECK`
  separado, y `negocio_id` no es un valor que ningún flujo de este ciclo necesite reasignar.
- **Sin policy de DELETE** — mismo motivo que `negocio_administrador`/`usuario_preferencias`:
  ningún endpoint/HU de este ciclo borra una suscripción (cancelar es un `UPDATE` de `estado`, no
  un `DELETE` de la fila) — fail-closed por default, documentado como intencional.

Detalle línea por línea de cada policy en `05-codigo/database/migrations/001_init.sql` (bloque
"Suscripción 'Turnario Pro'") y en `005_suscripcion_negocio.sql` (mismas policies, envueltas en
bloques `DO` con guard contra `pg_policy` para que ese script sea reintentable). **No verificado
contra un Postgres real** en este ciclo (mismo caveat que el resto de este documento) —
prioridad para quien aplique `005_suscripcion_negocio.sql` contra Render: confirmar que el
backfill deja exactamente 1 fila `suscripcion_negocio` por `negocio` existente, todas en plan
'gratis', antes de que Backend conecte el chequeo de límites sobre esta tabla.

## 5septies. RLS de administrador — acceso de solo lectura al historial de pacientes (fast-follow de E15, DBA, 2026-08-15)

**Origen.** El CEO confirmó, en la ronda de trabajo de la épica E15 ("Modo Administrador v1"), la
pregunta que `documento-funcional.md` §6, ítem 2, dejaba abierta desde la Fase 2 ("Alcance de
permisos del administrador del negocio sobre el historial de clientes... A7/D3 dejan al
administrador sin acceso por defecto — confirmar si es correcto") y que `02-backlog/backlog.md`
(épica E15) había registrado con una propuesta de Product Manager de **mantener** ese default sin
acceso: el CEO pidió expresamente **"acceso completo"** al historial de pacientes de su negocio —
rechazando la propuesta conservadora — y, al no existir todavía backend para eso en esa misma
ronda, aceptó la recomendación de tratarlo como un **fast-follow separado** (DBA primero, sobre
este mismo diseño; Backend/Mobile en una ronda posterior). Detalle completo de esa decisión en
`memory/proyectos/turnos-profesionales/decisiones.md`, entrada "E15 'Modo Administrador v1'". Este
apartado es esa ronda de DBA.

**Alcance decidido: SOLO LECTURA, no escritura — evaluado explícitamente, no asumido.** "Acceso
completo al historial" se interpreta acá como "el historial ENTERO visible" (ficha + tratamientos
+ notas, sin recortes), no como "con permiso de edición incluido": nada en el pedido del CEO, ni
en HU-20/HU-21/RN7/RN13/D3, ni en ningún otro punto de `documento-funcional.md`/`backlog.md`, pide
que el administrador pueda editar o borrar una ficha, un tratamiento o una nota médica ajena — y
RN7/RN13/D3 siguen íntegramente vigentes para la escritura: ese registro es de autoría clínica del
profesional que atendió, con implicancia médico-legal, no solo de producto. Se aplica acá el mismo
criterio de mínimo privilegio que ya usa este documento ante instrucciones ambiguas entre 2
lecturas posibles (§1, "Estado por defecto seguro..."; `es_rubro_salud` DEFAULT false, §2quinquies):
implementar la lectura más angosta que satisface lo pedido explícitamente, dejando la más amplia
(escritura para administrador) como extensión futura documentada y aditiva si algún día se pide —
nunca al revés, por el costo asimétrico de tener que retirar un permiso de escritura ya otorgado
sobre datos clínicos sensibles (D11/RN15) que nadie pidió.

**Diseño — 3 policies `FOR SELECT` nuevas; ninguna de las 3 policies `FOR ALL` existentes
(`paciente_acceso_propio_profesional`/`tratamiento_acceso_via_paciente`/
`nota_medica_acceso_via_paciente`, §5ter) se toca ni se separa.** Se evaluó explícitamente separar
cada `FOR ALL` en `FOR SELECT` + policies de escritura — la vía que ya sugería el comentario
original de §5ter ("agregar una policy adicional... mismo patrón que turno") — y se descarta por
innecesario: Postgres combina con OR, por comando, todas las policies `PERMISSIVE` (el default;
ninguna policy de este esquema usa `RESTRICTIVE`) que aplican a ese comando — una `FOR ALL` aplica
a los 4 comandos, una `FOR SELECT` nueva solo a `SELECT`. Agregar la `FOR SELECT` nueva ya amplía
la lectura (se evalúa en OR junto al `USING` de la `FOR ALL` existente) sin tocar
INSERT/UPDATE/DELETE, que siguen dependiendo exclusivamente de la `FOR ALL` original — mismo
resultado final que "separar" la policy vieja, con menor superficie de cambio (0 líneas tocadas de
policies ya aprobadas y en producción) y por lo tanto menor riesgo de regresión.

Verificado contra el código real de Backend antes de dar por segura esta decisión (no asumido):
`05-codigo/backend/src/routes/profesionales.ts` (`GET`/`PATCH /:id/pacientes/:pacienteId`,
`GET /:id/pacientes/:pacienteId/historial`) es hoy el único lugar que lee o escribe estas 3
tablas; las 3 rutas exigen `requireAuth('profesional')` + `esPropioProfesional(req)` antes de
tocar la base y fijan `app.usuario_id` al propio profesional en `withTransaction(...)` — ningún
código hoy depende de que estas tablas tengan una única policy `FOR ALL`, así que sumar policies
de `SELECT` en paralelo no cambia el comportamiento de ninguna ruta existente. Backend todavía no
tiene ningún endpoint que lea estas tablas en contexto de administrador — esta migración deja
lista la autorización a nivel de base de datos para la ronda de Backend/Mobile de este mismo
fast-follow.

`negocio_id` para el chequeo de cada policy: `paciente.negocio_id` ya existe en la fila — a
diferencia de `suscripcion_negocio`/HU-29 (§5sexies), que necesitó `app.negocio_id` de sesión por
no tener FK directa a una identidad, acá no hace falta ninguna variable de sesión nueva.
`tratamiento`/`nota_medica` lo resuelven vía `JOIN` a `paciente`, mismo patrón que sus propias
policies `FOR ALL` (§5ter) ya usan para resolver "quién es el profesional dueño".

Detalle línea por línea de cada policy en `05-codigo/database/migrations/001_init.sql` (bloque
"Acceso de administrador al historial de pacientes — SOLO LECTURA") y en
`007_paciente_historial_acceso_administrador.sql` (mismas policies, envueltas en un bloque `DO`
con guard contra `pg_policy` para que ese script sea reintentable). **No verificado contra un
Postgres real** en este ciclo (mismo caveat que el resto de este documento) — prioridad para quien
aplique `007_paciente_historial_acceso_administrador.sql` contra Render: confirmar con
`set_config('app.usuario_id', ...)` que (a) un administrador del negocio SÍ puede `SELECT` la
ficha/tratamientos/notas de un paciente atendido por CUALQUIER profesional de su negocio, (b) un
administrador de OTRO negocio sigue sin poder verlas (aislamiento de tenant intacto), y (c) un
`UPDATE`/`INSERT`/`DELETE` intentado con contexto de administrador sigue denegado (fail-closed —
la escritura no tiene ninguna policy que la habilite para ese rol).

**Pendiente, fuera del alcance de DBA:** Business Analyst/Product Manager deben actualizar
formalmente `documento-funcional.md` (D3/RN7/§6) y `02-backlog/backlog.md` (E15) con esta
resolución — este documento y `001_init.sql` son la fuente de verdad del MODELO DE DATOS, no
reemplazan esa actualización textual. Backend necesita un endpoint nuevo (ej. `GET
/negocios/:id/pacientes/:pacienteId/historial` o equivalente, criterio de ruta a definir por
Arquitecto/Backend) que corra con `requireAuth('administrador')` y lea estas 3 tablas bajo el
contexto RLS del administrador para que esta policy tenga un consumidor real; Mobile necesita la
pantalla correspondiente en `AdministradorShell`. Ninguno de los dos implementado en este ciclo
(instrucción explícita: solo DBA en esta ronda, sin tocar Backend ni Mobile).

## 5octies. `TokenRecuperacionPassword` — decisión de NO habilitar Row Level Security (DBA, 2026-08-16)

**A diferencia de TODAS las tablas nuevas de los últimos 5 ciclos** (`paciente`/`tratamiento`/
`nota_medica` §5ter, `usuario_preferencias` §5quater, `usuario_preferencias_notificacion`
§5quinquies, `suscripcion_negocio` §5sexies — todas con `FORCE ROW LEVEL SECURITY` desde el primer
commit, lección de §5bis), `TokenRecuperacionPassword` **deliberadamente no la lleva**. No es un
olvido — es la misma conclusión, y por el mismo tipo de motivo, que ya dejó este documento para
`Usuario` en sí (§2septies, "Conclusión sobre RLS de `usuario`"), llevada un paso más allá: acá el
motivo no es solo "no se ha priorizado todavía" (como en `Usuario`, donde en principio SÍ podría
tener sentido a futuro) sino que el patrón mismo de RLS de este esquema es **estructuralmente
incompatible** con el 100% de los accesos de esta tabla.

### Por qué el patrón `app.usuario_id` no aplica acá

Verificado contra el código real antes de decidir (no asumido) — `current_setting('app.usuario_id',
true)`, el mecanismo detrás de toda policy de este esquema, lo setea `withTransaction(fn, {
usuarioId })` (`05-codigo/backend/src/db.ts`) a partir de un **actor ya autenticado**: el claim
`sub` de un JWT, o -en un puñado de endpoints de registro que todavía no tienen JWT emitido- el
UUID recién generado para la fila que se está por crear (`POST /auth/registro-negocio`,
`POST /auth/registro-cliente`; ver el comentario de `ContextoRls` en `db.ts` y el de
`POST /registro-cliente` en `src/routes/auth.ts`: "`usuario` no tiene RLS... no hace falta pasar
por una transacción con contexto"). En TODAS las tablas con RLS de este esquema, `app.usuario_id`
queda fijado ANTES de la primera query relevante de la transacción autenticada.

`TokenRecuperacionPassword` no tiene ningún punto de su ciclo de vida donde eso sea posible:

1. **Crear el token** (`POST /auth/recuperar-password`) es un pedido ANÓNIMO por email — no hay
   sesión, no hay JWT, y el `usuario_id` involucrado ni siquiera pertenece al actor (cualquiera
   puede escribir el email de cualquier otra persona en este formulario; la prueba de identidad
   real la aporta después el propio email, no este paso). Mismo tipo de operación, sin contexto
   RLS, que ya corre hoy sobre `usuario` en `POST /auth/registro-cliente`.
2. **Canjear el token** (`POST /auth/reset-password`) tiene un problema más profundo que "no hay
   sesión todavía": es **estructuralmente imposible** setear `app.usuario_id` antes de la lectura
   que lo necesitaría. La consulta que resuelve a qué usuario pertenece el token es justamente
   `SELECT ... WHERE token_hash = ?` — recién ESA consulta devuelve el `usuario_id`. Una policy
   `usuario_id = app.usuario_id` exigiría conocer, de antemano, exactamente el valor que la propia
   consulta todavía tiene que descubrir — una dependencia circular, no un simple "todavía no
   conectado" como el caso de `Usuario`.

### Dónde vive la protección real, si no es RLS

La autorización de esta tabla no es "¿de quién es esta fila?" (el terreno que cubre RLS en el
resto de este esquema) sino "¿quién conoce el token en texto plano?" — un hecho que la base de
datos no puede verificar por sí sola: la comparación ocurre en la capa de aplicación (hash del
valor recibido contra `token_hash`), estructuralmente análoga a cómo `usuario.password_hash`
tampoco depende de RLS para protegerse en el login (`bcrypt.compareSync`, sin ninguna policy de
por medio, ver `POST /auth/login`). La protección real de esta tabla es la combinación de: alta
entropía del token (aleatorio, generado por el servidor) + hash irreversible + expiración corta +
invalidación tras un solo uso + el índice único parcial
`uq_token_recuperacion_password_usuario_pendiente` (a lo sumo 1 token vivo por usuario, ver
§2decies) — ninguna de estas 5 capas depende de RLS.

### Alternativa considerada y descartada: policy permisiva transitoria

Se evaluó explícitamente replicar el patrón de `turno_select_publico` (§5bis: una policy
`USING (true)` explícitamente transitoria, para destrabar un caso de uso que hoy no tiene otra
vía) — y se descarta, a diferencia de aquel caso: ahí la policy permisiva convive con OTRAS
policies más estrictas sobre la misma tabla (`turno_acceso_negocio_o_cliente`) que sí importan y
que en algún momento la van a reemplazar. Acá NO hay ninguna policy más estricta posible que
`TokenRecuperacionPassword` pueda aspirar a tener — el problema no es de alcance/permisos (ej.
"quién más allá del dueño puede ver esto"), es que el mecanismo entero de RLS de este esquema
presupone conocer al actor de antemano, y esta tabla, por diseño, existe precisamente para los
momentos en que **todavía no se sabe quién es el actor**. Agregar `ENABLE ROW LEVEL SECURITY` con
una policy `USING (true)` no sumaría ninguna protección real (equivalente, para el SELECT que más
importa, a no tener RLS) y sí el riesgo de transmitir una falsa sensación de "esta tabla ya está
defendida por RLS" a quien lea el esquema — se prefiere la honestidad de dejarlo explícitamente
afuera y documentado, mismo criterio ya aplicado a `Usuario`.

### Cuándo reabrir esta decisión

Si en un ciclo futuro se agrega un endpoint AUTENTICADO que lea esta tabla (ej. "ver mis
solicitudes de recuperación recientes" en Configuración/Seguridad — ninguna HU lo pide hoy), ese
caso SÍ tendría `app.usuario_id` disponible en ese punto puntual y podría sumar una policy de solo
lectura (`usuario_id = app.usuario_id`), aditiva, sin afectar el resto de este diseño ni las 2
rutas pre-autenticación de arriba (que seguirían sin contexto RLS, igual que hoy). No es una
decisión que quede "mal encaminada" por diseñarse así ahora — es exactamente el mismo tipo de
extensión aditiva que ya usó este documento varias veces (ej. §5septies sobre `paciente`).

Detalle línea por línea en `05-codigo/database/migrations/001_init.sql` (bloque "Recuperación de
contraseña — token de un solo uso", sección "Row Level Security — DELIBERADAMENTE NO SE HABILITA
en esta tabla") y en `008_recuperacion_password.sql`.

## 6. Índices críticos

- `uq_turno_slot_activo` sobre `(profesional_id, inicio)` filtrado por estado activo —
  garantiza RN2 (no doble reserva), definido y justificado en
  `documento-arquitectura.md` §4.
- Índice sobre `(negocio_id)` en toda tabla de alcance de negocio, para que los filtros de
  aislamiento multi-tenant (RN9) sean eficientes.
- Índice sobre `(cliente_id, profesional_id)` en Turno, para las consultas de historial (CU2).
- **Actualizado 2026-08-06 (ver §2ter):** el índice único implícito sobre
  `negocio.admin_usuario_id` ya no existe (la columna fue reemplazada por
  `negocio_administrador`). En su lugar:
  - PK compuesta `(negocio_id, usuario_id)` en `negocio_administrador` — cubre eficientemente
    "administradores de este negocio" (ej. las políticas RLS de §5) por ser la columna líder.
  - Índice `idx_negocio_administrador_usuario` sobre `usuario_id` — cubre el sentido inverso,
    "negocios que administra este usuario", que es exactamente la query de resolución de
    negocio_id en el login (ver recomendación de Backend en §2ter).
  - PK compuesta `(negocio_id, profesional_id)` en `negocio_profesional` — cubre "profesionales
    de este negocio" (ej. HU-08, listar profesionales de un negocio+servicio).
  - Índice `idx_negocio_profesional_profesional` sobre `profesional_id` — cubre el sentido
    inverso, "negocios donde trabaja este profesional" (login, resolución de `turno.negocio_id`).
- **Nuevo 2026-08-10 (HU-20/HU-21, ver §2quinquies):**
  - `UNIQUE (negocio_id, profesional_id, cliente_id)` en `paciente` — además de garantizar que un
    profesional lleve una sola ficha por cliente por negocio, es en sí mismo el índice que cubre
    "mis pacientes en el negocio activo" (`WHERE negocio_id = ? AND profesional_id = ?`, la
    consulta dominante bajo el patrón "vista activa" de §2ter) por su prefijo izquierdo — no hace
    falta un índice aparte solo para `negocio_id` o `(negocio_id, profesional_id)`.
  - Índice `idx_paciente_cliente` sobre `cliente_id` en `paciente` — cubre el sentido inverso
    (`cliente_id` no es prefijo de la `UNIQUE` de arriba).
  - Índices `idx_tratamiento_paciente`/`idx_nota_medica_paciente` sobre `paciente_id` — cubren
    tanto el listado del historial enriquecido (HU-21) como los conteos de los stat cards
    "Tratamientos"/"Notas médicas".
- **Nuevo 2026-08-11 (HU-32, ver §2septies):** `UNIQUE (usuario_id)` en `usuario_preferencias` —
  además de expresar el 1:1 con `usuario`, es en sí misma el índice que cubre la única consulta
  de lectura de esta tabla (`WHERE usuario_id = ?`, resolver "mis preferencias" al abrir la
  pantalla de Privacidad y Seguridad) por igualdad exacta — no hace falta ningún índice
  adicional. Mismo criterio ya aplicado a `profesional.usuario_id UNIQUE` (Fase 3 original).
- **Nuevo 2026-08-12 (HU-14b/HU-25/HU-26, ver §2octies):**
  - `idx_notificacion_destinatario` sobre `(destinatario_usuario_id, creado_en DESC)` en
    `notificacion` — cubre la query dominante de la bandeja ("mis notificaciones, más nuevas
    primero") con un único índice, sin sort aparte, por llevar `creado_en DESC` como segunda
    columna.
  - `idx_notificacion_destinatario_no_leida` — parcial (`WHERE leido = false`) sobre
    `destinatario_usuario_id` en `notificacion`, para el badge/contador de no leídas sin escanear
    el historial completo — mismo patrón que `uq_turno_slot_activo` (índice parcial filtrado por
    estado activo).
  - `idx_notificacion_turno` (preexistente, sin cambios) sigue cubriendo el sentido original de
    la tabla (log por turno).
  - `usuario_preferencias_notificacion` no necesita índice propio además de su PK/UNIQUE
    (`usuario_id`): es 1:1 con `Usuario`, se lee siempre por ese único valor.
- **Nuevo 2026-08-14 (HU-29/E11, ver §2novies):**
  - `UNIQUE (negocio_id)` en `suscripcion_negocio` — igual que `usuario_preferencias.usuario_id`,
    expresa el 1:1 con `Negocio` y es en sí misma el índice que cubre la única consulta de lectura
    de esta tabla (`WHERE negocio_id = ?`, resolver el estado del plan al abrir cualquier pantalla
    que lo muestre) — no hace falta ningún índice adicional.
  - `idx_turno_negocio_confirmado_inicio` — parcial (`WHERE estado = 'confirmado'`) sobre
    `(negocio_id, inicio)` en `turno` (tabla existente, sin cambios de columnas) — soporta el hot
    path del límite de 60 turnos confirmados/mes del plan gratis (`SELECT count(*) FROM turno
    WHERE negocio_id = ? AND estado = 'confirmado' AND inicio >= ? AND inicio < ?`), mismo patrón
    de índice parcial que `uq_turno_slot_activo`/`idx_notificacion_destinatario_no_leida`. Indexa
    por `turno.inicio` (fecha/hora del turno), no por `creado_en` — supuesto señalado para
    Backend/Product Manager en el propio `001_init.sql`, a confirmar al implementar el chequeo.
  - Sin índice nuevo para el otro límite de HU-29 ("1 profesional por negocio"): ya cubierto por
    la PK compuesta `(negocio_id, profesional_id)` de `negocio_profesional` (`negocio_id` es la
    columna líder), documentada más arriba en esta misma sección (actualización 2026-08-06).
- **Nuevo 2026-08-16 (recuperación de contraseña, ver §2decies):**
  - `UNIQUE` inline sobre `token_hash` en `token_recuperacion_password` — cubre, por igualdad
    exacta, la consulta dominante de validación (`WHERE token_hash = ?`, resolver a qué token
    corresponde el valor que llega en el link de reset) — el índice que pedía explícitamente esta
    ronda ("para que Backend pueda buscar eficientemente por el hash del token al validar"), sin
    objeto nombrado aparte (mismo patrón que `usuario.email`/`usuario.google_id`).
  - `uq_token_recuperacion_password_usuario_pendiente` — parcial (`WHERE usado_en IS NULL`) y
    UNIQUE sobre `usuario_id`, mismo patrón de índice parcial filtrado por estado activo que
    `uq_turno_slot_activo`/`idx_notificacion_destinatario_no_leida`. Cubre "¿tiene este usuario un
    token pendiente?" (la consulta de invalidación al pedir uno nuevo) Y, por ser UNIQUE, es en sí
    mismo la garantía a nivel de base de datos de "a lo sumo 1 token pendiente por usuario" — ver
    §2decies.
- **Nuevo 2026-08-17 (HU-31, ver §2undecies):** **sin índice nuevo.** Las 4 columnas agregadas a
  `negocio` (`horario_atencion`, `direccion`, `telefono`, `logo_url`) son campos de despliegue —
  se leen siempre junto al resto de la fila, por `id` (`GET /negocios/:id`) o en el listado
  completo (`GET /negocios`), igual que `rubro`/`ubicacion` hoy, que tampoco tienen índice propio.
  Ninguna consulta existente ni recomendada filtra por ellas; el índice implícito de la
  `PRIMARY KEY` ya cubre el único patrón de acceso puntual real.
