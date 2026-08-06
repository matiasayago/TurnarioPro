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
| **Negocio** | Comercio/consultorio, raíz de aislamiento multi-tenant (D1). | N:M Usuario (administradores, vía `NegocioAdministrador`); 1:N Servicio, Cliente-en-negocio; N:M Profesional (vía `NegocioProfesional`) — ver §2ter, generalización N:M 2026-08-06 |
| **Usuario** | Identidad base (email, hash de contraseña, rol: cliente/profesional/administrador). | 1:1 Profesional (si rol=profesional, identidad — no implica pertenencia a un negocio); N:M Negocio (si rol=administrador, vía `NegocioAdministrador`) — ver §2ter |
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

*(Historial de visitas no es una entidad propia: es una consulta de `Turno` filtrada por
`cliente_id` + `profesional_id` con estado "atendido", reforzando RN7/D3 — un profesional solo
puede filtrar por su propio `profesional_id`.)*

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

## 5. Row Level Security (Postgres, producción)

Implementado en el DDL (`05-codigo/database/migrations/001_init.sql`), **no verificado contra
un Postgres real** — este entorno de desarrollo no tiene `psql`/Docker instalados (ver
`memory/proyectos/turnos-profesionales/decisiones.md`). Antes de aplicarlo en un entorno real,
correrlo contra una instancia de prueba.

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
- Pendiente para una próxima iteración (sin cambios por esta generalización): `disponibilidad`,
  `excepcion_disponibilidad`, `profesional_servicio`, `pago` y `notificacion` no tienen
  `negocio_id` propio (se llega por join a través de `profesional_id`/`turno_id`); necesitarían
  una política basada en subquery, no incluida en este slice. Si en una próxima iteración se
  agregan, deberían seguir el mismo patrón `EXISTS`/`app.usuario_id` de esta sección, no el
  patrón anterior de igualdad contra `app.negocio_id`.

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
