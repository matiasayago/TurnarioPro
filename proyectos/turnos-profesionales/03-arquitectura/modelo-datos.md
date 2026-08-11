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

## 2. Entidades principales

| Entidad | Descripción | Relaciones |
|---|---|---|
| **Negocio** | Comercio/consultorio, raíz de aislamiento multi-tenant (D1). `es_rubro_salud` (D11/RN15, ver §2quinquies) determina si sus profesionales ven los campos extendidos de `Paciente`. | N:M Usuario (administradores, vía `NegocioAdministrador`); 1:N Servicio, Cliente-en-negocio, `Paciente`; N:M Profesional (vía `NegocioProfesional`) — ver §2ter, generalización N:M 2026-08-06 |
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
| **Notificacion** | Registro de notificaciones enviadas (confirmación, recordatorio) — D4. | N:1 Turno |
| **Paciente** (HU-20, nueva 2026-08-10) | "Ficha" que un Profesional lleva de un Cliente, dentro de un Negocio — NO 1:1 con Usuario, ver §2quinquies (RN7/RN13/D3: privacidad por profesional). Campos básicos ya en Usuario (nombre/email/teléfono); acá viven fecha de nacimiento, género, dirección, alergias, contacto de emergencia, notas médicas generales (gateados a rubro salud, D11/RN15) y `activo` (D20/RN20, no gateado). | N:1 Negocio, N:1 Profesional, N:1 Usuario (cliente); 1:N Tratamiento, 1:N NotaMedica |
| **Tratamiento** (HU-21/D8, nueva 2026-08-10) | Proceso de seguimiento asociado a un Paciente, independiente de un turno puntual (descripción, fecha de inicio, fecha de fin opcional). Privado por profesional (RN13), heredado de `Paciente` — ver §2quinquies. | N:1 Paciente |
| **NotaMedica** (HU-21/D8, nueva 2026-08-10) | Anotación clínica/de seguimiento asociada a un Paciente, independiente de un turno puntual (fecha, texto). Privado por profesional (RN13), heredado de `Paciente` — ver §2quinquies. | N:1 Paciente |

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

## 3. Diagrama conceptual

Actualizado (2026-08-06) para reflejar la generalización N:M de §2ter: `Profesional` ya no
cuelga directamente de `Negocio` como hijo fijo — la pertenencia pasa por las tablas de
asociación `NegocioAdministrador`/`NegocioProfesional`, ambas N:M entre `Usuario`/`Profesional`
y `Negocio`.

```
Usuario ──< NegocioAdministrador >── Negocio
Usuario ── Profesional ──< NegocioProfesional >── Negocio
                 │
                 ├── Disponibilidad
                 ├── ExcepcionDisponibilidad
                 └── ProfesionalServicio ── Servicio ── Negocio (N:1)

Negocio ── Turno ── Usuario (cliente)
                 ├── Pago
                 └── Notificacion
```

(`──< X >──` denota una relación N:M resuelta por la tabla de asociación `X`, con PK compuesta
por las dos claves foráneas que conecta.)

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
