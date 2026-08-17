import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import {
  uuidSchema,
  fechaIsoSchema,
  montoPositivoSchema,
  passwordSchema,
  respuestaValidacionFallida,
} from '../dominio/validacion';
import {
  LIMITE_PROFESIONALES_ACTIVOS_GRATIS,
  LIMITE_TURNOS_CONFIRMADOS_MES_GRATIS,
  contarProfesionalesActivos,
  contarTurnosConfirmadosDelMes,
  cuerpoLimitePlanAlcanzado,
  obtenerEstadoSuscripcion,
  tieneAccesoTurnarioPro,
  verificarLimiteProfesionalesActivos,
} from '../dominio/suscripciones';

export const negociosRouter = Router();

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación de entrada — se
// aplican al INICIO de cada handler, antes de tocar la base de datos.
const negocioIdParamsSchema = z.object({ id: uuidSchema });

// Acceso de administrador al historial de pacientes — SOLO LECTURA (fast-follow de la épica E15
// "Modo Administrador v1", 2026-08-15 — ver ../../database/migrations/
// 007_paciente_historial_acceso_administrador.sql y 03-arquitectura/modelo-datos.md §5septies
// para el razonamiento completo de DBA). Usado por los 3 endpoints GET /:id/pacientes... al
// final de este archivo. `fichaId` es `paciente.id` (la PK real de la ficha) — A PROPÓSITO
// distinto de `:pacienteId` en profesionales.ts (que es `cliente_id`/`usuario.id`): del lado
// profesional alcanza con `cliente_id` porque la ruta ya está acotada a un único profesional_id
// fijo (`:id` de esa ruta); acá un administrador ve TODO el negocio, y la misma persona puede
// tener 2+ fichas (una por cada profesional que la atendió — `paciente` tiene
// UNIQUE (negocio_id, profesional_id, cliente_id), ver modelo-datos.md §6) — hace falta la PK
// real de la fila puntual para desambiguar cuál de esas fichas se está pidiendo.
const negocioFichaParamsSchema = z.object({ id: uuidSchema, fichaId: uuidSchema });

const altaServicioSchema = z.object({
  nombre: z.string().min(1, 'nombre es requerido'),
  duracion_min: montoPositivoSchema,
  precio_referencia: montoPositivoSchema.nullable().optional(),
});

// Configuración de Consultorio (mapa-pantallas.md §5.11bis, "Panel Profesional > Configuración
// de Consultorio", HU-31) — PATCH /:id de más abajo. `nombre`/`rubro`/`ubicacion` viajan TODOS
// en el body (no parcial), mismo criterio de "reenviar el formulario completo" que
// `fichaPacienteSchema`/`configuracionProfesionalSchema` en profesionales.ts: Mobile ya tiene el
// valor actual de cada campo desde GET /:id (ver más abajo) y reenvía el formulario entero al
// guardar. `nombre` requerido (columna NOT NULL en `negocio`); `rubro`/`ubicacion` nullable pero
// NO `.optional()` — hay que poder mandar `null` explícito para vaciar un campo que antes tenía
// valor, mismo motivo que en `fichaPacienteSchema`.
const actualizarNegocioSchema = z.object({
  nombre: z.string().min(1, 'nombre es requerido'),
  rubro: z.string().nullable(),
  ubicacion: z.string().nullable(),
});

// HU-29 (Turnario Pro) — body de POST /:id/suscripcion (activación simulada), más abajo. Mismo
// estilo que `visibilidadPerfilSchema` (dominio/validacion.ts): enum sin mensaje custom, zod ya
// devuelve un error legible por campo vía `respuestaValidacionFallida`.
const activarSuscripcionSchema = z.object({
  periodo: z.enum(['mensual', 'anual']),
});

// MEDIUM-1 (ver 07-seguridad/informe-seguridad.md): misma política mínima de contraseña que
// registro-negocio/registro-cliente, aplicada acá también (alta de profesional por el admin).
const altaProfesionalSchema = z.object({
  email: z.string().email('email debe ser una dirección de correo válida'),
  password: passwordSchema,
  nombre: z.string().min(1, 'nombre es requerido'),
});

// Reportes y Estadísticas (HU-28/E10) — filtros opcionales de GET /:id/reportes, al final de
// este archivo (vista de negocio/administrador — ver el bloque de comentarios ahí para el
// contrato completo). Mismo shape que `reportesQuerySchema` (profesionales.ts, lado Profesional,
// ~línea 112) más `profesional_id`, que ahí no aplica (esa ruta ya está scopeada a un único
// profesional por diseño) y acá sí, como filtro más. Duplicado local en vez de importado desde
// profesionales.ts: ningún schema de este backend se comparte hoy entre routers — cada archivo de
// rutas define los propios, incluso cuando coinciden campo a campo con otro (mismo criterio ya
// aplicado en todo este archivo, ej. `negocioIdParamsSchema` vs. `profesionalIdParamsSchema` de
// profesionales.ts, ambos `{ id: uuidSchema }`).
const reportesNegocioQuerySchema = z.object({
  desde: fechaIsoSchema.optional(),
  hasta: fechaIsoSchema.optional(),
  servicio_id: uuidSchema.optional(),
  profesional_id: uuidSchema.optional(),
});

// HU-00b: cliente descubre negocios (RN9 — no se filtra por negocio_id porque es cross-tenant
// por diseño). Público — pool.query directo, sin transacción ni contexto RLS.
negociosRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const result = await pool.query(
      'SELECT id, nombre, rubro, ubicacion, es_rubro_salud FROM negocio WHERE eliminado_en IS NULL'
    );
    res.json(result.rows);
  })
);

// HU-31: detalle de un negocio puntual. Configuración de Consultorio (Mobile) lo usa para
// prefillear el formulario de edición antes del PATCH de más abajo, pero es público — mismos
// datos que YA expone GET / para TODOS los negocios sin login (HU-00b); esto solo acota a una
// fila en vez de forzar a Mobile a traer la lista completa y filtrar del lado cliente. Mismo
// criterio de "público por diseño" que el resto de las lecturas de este archivo. `404` si no
// existe o está soft-deleted (`eliminado_en`), mismo filtro que ya aplica GET /.
negociosRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    const result = await pool.query(
      'SELECT id, nombre, rubro, ubicacion, es_rubro_salud FROM negocio WHERE id = $1 AND eliminado_en IS NULL',
      [req.params.id]
    );
    const negocio = result.rows[0];
    if (!negocio) return res.status(404).json({ error: 'Negocio no encontrado' });
    res.json(negocio);
  })
);

// HU-07: servicios de un negocio puntual (público, para que el cliente elija).
negociosRouter.get(
  '/:id/servicios',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      'SELECT id, nombre, duracion_min, precio_referencia FROM servicio WHERE negocio_id = $1 AND eliminado_en IS NULL',
      [req.params.id]
    );
    res.json(result.rows);
  })
);

// HU-08: profesionales del negocio que ofrecen un servicio puntual (público, para que el
// cliente elija profesional una vez que ya eligió el servicio — CU4 paso 2).
// `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — el JOIN pasa por
// `negocio_profesional`, que resuelve la membresía activa del profesional en ESTE negocio en
// particular (un mismo profesional puede pertenecer a otros negocios además de este).
negociosRouter.get(
  '/:id/servicios/:servicioId/profesionales',
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT p.id, u.nombre
       FROM profesional p
       JOIN usuario u ON u.id = p.usuario_id
       JOIN profesional_servicio ps ON ps.profesional_id = p.id
       JOIN negocio_profesional np ON np.profesional_id = p.id AND np.negocio_id = $1 AND np.activo = true
       WHERE ps.servicio_id = $2 AND p.eliminado_en IS NULL`,
      [req.params.id, req.params.servicioId]
    );
    res.json(result.rows);
  })
);

// HU-03: administrador carga un servicio de SU negocio (RN9 aplicado vía claim del JWT, no del parámetro).
negociosRouter.post(
  '/:id/servicios',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
    }
    const bodyParsed = altaServicioSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nombre, duracion_min, precio_referencia } = bodyParsed.data;
    const id = uuid();

    await withTransaction(
      async (client) => {
        await client.query(
          'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [id, req.params.id, nombre, duracion_min, precio_referencia ?? null, nowIso()]
        );
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    res.status(201).json({ id });
  })
);

// HU-02: administrador da de alta un profesional de SU negocio.
// Generalización N:M (ver modelo-datos.md §2ter): un mismo profesional puede trabajar en más
// de un negocio, así que un email que YA pertenece a una identidad profesional existente (dada
// de alta antes por OTRO negocio) no es un conflicto — hay que reusar esa fila de `profesional`
// (por `usuario_id`, que sigue siendo UNIQUE) e insertar solo el vínculo nuevo en
// `negocio_profesional`, nunca duplicar la identidad. `password`/`nombre` del body se IGNORAN a
// propósito en el caso de reuso: son necesarios en el schema porque el mismo endpoint también
// crea la cuenta cuando es la primera vez, pero pisar la contraseña de una identidad ya
// existente dejaría que un segundo negocio le "robe" el acceso a un profesional que ya trabaja
// en otro lado — solo el email correlaciona la identidad, nunca sus credenciales.
//
// Toda la lógica (lecturas + escrituras condicionales) corre en UNA sola transacción con
// contexto RLS fijo (usuarioId=admin, negocioId=req.params.id) — antes (versión a medio migrar)
// esto llamaba a `withTransaction(fn)` con un `fn` síncrono que ni siquiera recibía el `client`
// (no compilaba y, aunque hubiera compilado, nunca habría fijado el contexto RLS para los
// UPDATE/INSERT de `negocio_profesional`, que si tiene RLS). El resultado de la transacción es
// un objeto discriminado por `tipo` que el código de después usa para elegir status/body HTTP —
// necesario porque ya no se puede hacer `return res.status(...)` desde adentro del closure.
negociosRouter.post(
  '/:id/profesionales',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
    }
    const bodyParsed = altaProfesionalSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { email, password, nombre } = bodyParsed.data;

    const ts = nowIso();
    const usuarioIdNuevo = uuid();
    const profesionalIdNuevo = uuid();

    const resultado = await withTransaction(
      async (client) => {
        const existenteResult = await client.query('SELECT id, rol FROM usuario WHERE email = $1', [email]);
        const existente = existenteResult.rows[0] as { id: string; rol: string } | undefined;

        if (existente && existente.rol !== 'profesional') {
          // El email ya está tomado por una identidad de otro rol (cliente/administrador) — un
          // email es una única identidad con un único rol, no se puede reusar como profesional.
          return { tipo: 'email_tomado' as const };
        }

        // HU-29 (Turnario Pro) — límite "1 profesional activo por negocio" del plan gratis. Se
        // calcula UNA sola vez acá (no depende de nada resuelto más abajo, es información
        // estática del negocio al momento del request) y se reusa en los 2 puntos de abajo donde
        // este handler efectivamente SUMA un profesional activo (reactivar una membresía
        // pausada, o crear una membresía — para un profesional ya existente o para uno nuevo).
        // A propósito NO se aplica al branch `email_tomado` de arriba (ya cortado) ni a
        // `inconsistencia`/`ya_activo` de abajo (ninguno de los dos hace crecer el conteo de
        // profesionales activos de este negocio — bloquearlos igual sería más restrictivo de lo
        // necesario).
        const limiteProfesionales = await verificarLimiteProfesionalesActivos(client, req.params.id);

        if (existente) {
          const profesionalResult = await client.query('SELECT id FROM profesional WHERE usuario_id = $1', [
            existente.id,
          ]);
          const profesional = profesionalResult.rows[0] as { id: string } | undefined;
          if (!profesional) {
            // No debería poder pasar: todo usuario con rol='profesional' se crea junto con su
            // fila `profesional` en la misma transacción, en este mismo endpoint (ver rama de
            // alta nueva más abajo).
            return { tipo: 'inconsistencia' as const };
          }

          const membresiaResult = await client.query(
            'SELECT activo FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2',
            [req.params.id, profesional.id]
          );
          const membresia = membresiaResult.rows[0] as { activo: boolean } | undefined;

          if (membresia?.activo) {
            return { tipo: 'ya_activo' as const };
          }
          if (!limiteProfesionales.permitido) {
            return { tipo: 'limite_alcanzado' as const, motivo: limiteProfesionales.motivo! };
          }
          if (membresia) {
            // Ya había estado vinculado a este negocio pero la membresía estaba pausada
            // (activo=false) — se reanuda sin perder el vínculo/historial (ver diseño de
            // `activo` en modelo-datos.md).
            await client.query(
              'UPDATE negocio_profesional SET activo = true, modificado_en = $1 WHERE negocio_id = $2 AND profesional_id = $3',
              [ts, req.params.id, profesional.id]
            );
          } else {
            await client.query(
              'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES ($1, $2, true, $3)',
              [req.params.id, profesional.id, ts]
            );
          }
          return { tipo: 'ok' as const, id: profesional.id };
        }

        if (!limiteProfesionales.permitido) {
          return { tipo: 'limite_alcanzado' as const, motivo: limiteProfesionales.motivo! };
        }

        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [usuarioIdNuevo, email, bcrypt.hashSync(password, 10), nombre, 'profesional', ts]
        );
        await client.query('INSERT INTO profesional (id, usuario_id, creado_en) VALUES ($1, $2, $3)', [
          profesionalIdNuevo,
          usuarioIdNuevo,
          ts,
        ]);
        await client.query(
          'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES ($1, $2, true, $3)',
          [req.params.id, profesionalIdNuevo, ts]
        );
        return { tipo: 'ok' as const, id: profesionalIdNuevo };
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    switch (resultado.tipo) {
      case 'email_tomado':
        return res.status(409).json({ error: 'Email ya registrado' });
      case 'inconsistencia':
        return res.status(500).json({ error: 'No se pudo resolver la identidad profesional existente' });
      case 'limite_alcanzado':
        // HU-29 — 402 (no 403): ver el razonamiento completo en dominio/suscripciones.ts,
        // `cuerpoLimitePlanAlcanzado`. El administrador SÍ está autorizado a dar de alta
        // profesionales (pasó `requireAuth('administrador')` y el chequeo de RN9 de arriba) — lo
        // que falla es el PLAN, no el rol/identidad.
        return res.status(402).json(cuerpoLimitePlanAlcanzado(resultado.motivo));
      case 'ya_activo':
        return res.status(409).json({ error: 'Este profesional ya pertenece a este negocio' });
      case 'ok':
        return res.status(201).json({ id: resultado.id });
    }
  })
);

// HU-02 / E15 (02-backlog/backlog.md, "Modo Administrador v1 (Mobile)" — nota de alcance HU-02):
// roster completo de profesionales de SU negocio. Único endpoint nuevo que necesitó esa épica — el
// resto de sus pantallas se apoyan en endpoints que ya existían (ver esa sección del backlog).
// Contrato: GET /negocios/:id/profesionales -> 200 [{ id, nombre, email, activo }] | 400 :id
// inválido | 403 rol distinto de administrador, o negocio ajeno.
//
// `id` es `profesional.id` (NO `usuario.id`) a propósito: es el identificador que ya usa el resto
// de los endpoints `/profesionales/:id/...` (profesionales.ts) para referenciar a un profesional
// puntual, así que Mobile puede enlazar cada fila de este listado directo a esos endpoints sin
// resolver ningún id intermedio. `activo` es `negocio_profesional.activo` (la membresía de ESTE
// profesional en ESTE negocio, no un estado global de la identidad) — el mismo flag que ya usa
// `verificarLimiteProfesionalesActivos`/`contarProfesionalesActivos` (dominio/suscripciones.ts,
// HU-29) para el límite de "1 profesional activo" del plan gratis, así que Mobile puede mostrar en
// la misma pantalla quién cuenta contra ese límite y quién no (membresía pausada). `p.eliminado_en
// IS NULL` filtra identidades profesionales soft-deleted, mismo criterio que el resto de las
// lecturas de `profesional` en este archivo (ej. HU-08 más arriba) — defensa en profundidad, no
// debería poder existir una fila `negocio_profesional` apuntando a un `profesional` eliminado.
// Orden alfabético por `u.nombre`, sin paginar: mismo criterio que el resto de los listados de este
// archivo (GET /:id/servicios, GET /:id/servicios/:servicioId/profesionales), ninguno pagina hoy.
//
// Auth: RN9 vía claim del JWT (mismo patrón que el resto de este archivo, comparación directa
// contra `:id`, no una query aparte) — un administrador no puede listar el roster de otro negocio.
//
// Sin migración nueva: las 3 tablas del JOIN ya son legibles con el contexto RLS de un
// administrador autenticado — `negocio_profesional`/`profesional` tienen SELECT público
// (`negocio_profesional_select_publico`/`profesional_select_publico`, migrations/001_init.sql,
// USING (true)) y `usuario` no tiene RLS habilitada en ningún punto de ese archivo (ver el
// comentario junto a su CREATE TABLE). `withTransaction` con contexto de todos modos, por el mismo
// criterio de consistencia que ya dejó documentado `emitirLoginParaUsuario` (routes/auth.ts) para
// una lectura equivalente sobre una tabla con SELECT público: no hace falta para autorizar (ya lo
// resolvió el chequeo de `req.auth!.negocio_id` de arriba), pero mantiene el mismo patrón que el
// resto de los handlers autenticados de este archivo.
negociosRouter.get(
  '/:id/profesionales',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés listar profesionales de otro negocio' });
    }

    const profesionales = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT p.id AS id, u.nombre AS nombre, u.email AS email, np.activo AS activo
           FROM negocio_profesional np
           JOIN profesional p ON p.id = np.profesional_id
           JOIN usuario u ON u.id = p.usuario_id
           WHERE np.negocio_id = $1 AND p.eliminado_en IS NULL
           ORDER BY u.nombre`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    res.json(profesionales);
  })
);

// HU-31: Configuración de Consultorio — el administrador edita los datos descriptivos de SU
// PROPIO negocio (RN9 aplicado vía claim del JWT, no del parámetro — mismo patrón que
// POST /:id/servicios y POST /:id/profesionales de arriba). Contrato: PATCH /negocios/:id, body
// { nombre: string, rubro: string | null, ubicacion: string | null } -> 200
// { id, nombre, rubro, ubicacion, es_rubro_salud } | 400 datos inválidos | 403 rol distinto de
// administrador o negocio ajeno | 404 negocio inexistente/eliminado.
//
// `es_rubro_salud` queda A PROPÓSITO fuera de este PATCH — no está en el alcance que definió
// este ciclo ("nombre, rubro, ubicacion"). Ese flag gatea si se muestran los campos extendidos de
// `paciente` (D11/RN15, ver ../database/migrations/001_init.sql) y cambiarlo tiene implicancias
// de producto que exceden un campo más de un formulario descriptivo — se deja para que Product
// Manager/CTO IA decidan explícitamente si corresponde exponerlo, y en tal caso probablemente
// con su propio flujo de confirmación, no como parte de este PATCH.
//
// `withTransaction` con contexto pese a que `negocio` HOY NO TIENE Row Level Security habilitada
// (verificado en database/migrations/001_init.sql — no hay ningún `ALTER TABLE negocio ENABLE
// ROW LEVEL SECURITY`, a diferencia de negocio_administrador/negocio_profesional/servicio/etc.
// más abajo en ese mismo archivo): se mantiene igual por consistencia con el resto de ESTE
// archivo, que envuelve toda escritura en `withTransaction` sin excepción (ver POST
// /:id/servicios y POST /:id/profesionales arriba, donde tampoco todas las tablas tocadas tienen
// RLS) — y como defensa en profundidad/forward-compat si `negocio` gana RLS en un ciclo futuro
// (mismo espíritu que `ContextoRls.negocioId` en src/db.ts: "se deja disponible... aunque hoy
// ninguna policy lo use directamente").
negociosRouter.patch(
  '/:id',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar recursos de otro negocio' });
    }
    const bodyParsed = actualizarNegocioSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nombre, rubro, ubicacion } = bodyParsed.data;

    const negocio = await withTransaction(
      async (client) => {
        const result = await client.query(
          `UPDATE negocio SET nombre = $1, rubro = $2, ubicacion = $3, modificado_en = $4, modificado_por = $5
           WHERE id = $6 AND eliminado_en IS NULL
           RETURNING id, nombre, rubro, ubicacion, es_rubro_salud`,
          [nombre, rubro, ubicacion, nowIso(), req.auth!.sub, req.params.id]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    if (!negocio) return res.status(404).json({ error: 'Negocio no encontrado' });
    res.json(negocio);
  })
);

// ============================================================================
// Suscripción "Turnario Pro" (HU-29/E11, 2026-08-14) — ver dominio/suscripciones.ts para toda la
// lógica de negocio compartida (acceso efectivo, conteo de uso, chequeo de límites) y
// database/migrations/001_init.sql (bloque "Suscripción 'Turnario Pro'") / modelo-datos.md
// §2novies para el modelado de datos (DBA).
// ============================================================================

// Contrato: GET /negocios/:id/plan -> 200 { negocio_id, plan, periodo, vencimiento, estado,
// acceso_turnario_pro, turnos_confirmados_mes: { usados, limite, al_limite },
// profesionales_activos: { usados, limite, al_limite } } | 400 :id inválido | 403 rol distinto de
// administrador/profesional, o negocio ajeno | 404 negocio inexistente/eliminado.
//
// Auth: cualquier STAFF del negocio (administrador o profesional) — mismo criterio que la policy
// `suscripcion_negocio_select_staff_del_negocio` (DBA, migrations/001_init.sql): un profesional
// necesita poder ver el estado del plan de su negocio tanto como el administrador (Mobile: tarjeta
// "Turnario Pro — 42/60 turnos este mes" en la pantalla de Configuración/Suscripción, visible para
// ambos roles). `req.auth.negocio_id` es la "vista activa" del JWT (ver auth.ts) — mismo patrón
// RN9 que el resto de este archivo (comparación directa contra `:id`, no una query aparte).
//
// `plan`/`periodo`/`vencimiento`/`estado` viajan SIEMPRE los 4 (no solo cuando
// `plan = 'turnario_pro'`): mismo shape de respuesta sin importar el plan, más simple de consumir
// para Mobile que 2 shapes distintas — `periodo`/`vencimiento` ya son `null` para 'gratis' por el
// propio CHECK de la tabla, así que no se pierde ninguna información con este criterio.
// `profesionales_activos` no lo pidió la consigna explícitamente para ESTE endpoint, pero se
// agrega igual (mismo cálculo que ya usa el chequeo de límite de POST /:id/profesionales, sin
// costo extra relevante) — es el otro límite del mismo plan, coherente con mostrar el estado
// completo en una pantalla de "mi plan". `limite: null` = ilimitado (Turnario Pro activo).
negociosRouter.get(
  '/:id/plan',
  requireAuth('administrador', 'profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés consultar el plan de otro negocio' });
    }

    const datos = await withTransaction(
      async (client) => {
        const estadoSuscripcion = await obtenerEstadoSuscripcion(client, req.params.id);
        const proActivo = tieneAccesoTurnarioPro(estadoSuscripcion);
        const turnosUsados = await contarTurnosConfirmadosDelMes(client, req.params.id, new Date());
        const profesionalesActivos = await contarProfesionalesActivos(client, req.params.id);
        return { estadoSuscripcion, proActivo, turnosUsados, profesionalesActivos };
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    const limiteTurnos = datos.proActivo ? null : LIMITE_TURNOS_CONFIRMADOS_MES_GRATIS;
    const limiteProfesionales = datos.proActivo ? null : LIMITE_PROFESIONALES_ACTIVOS_GRATIS;

    res.json({
      negocio_id: req.params.id,
      plan: datos.estadoSuscripcion.plan,
      periodo: datos.estadoSuscripcion.periodo,
      vencimiento: datos.estadoSuscripcion.vencimiento,
      estado: datos.estadoSuscripcion.estado,
      acceso_turnario_pro: datos.proActivo,
      turnos_confirmados_mes: {
        usados: datos.turnosUsados,
        limite: limiteTurnos,
        al_limite: limiteTurnos !== null && datos.turnosUsados >= limiteTurnos,
      },
      profesionales_activos: {
        usados: datos.profesionalesActivos,
        limite: limiteProfesionales,
        al_limite: limiteProfesionales !== null && datos.profesionalesActivos >= limiteProfesionales,
      },
    });
  })
);

// Contrato: POST /negocios/:id/suscripcion, body { periodo: 'mensual' | 'anual' } -> 200
// { plan, periodo, vencimiento, estado } | 400 datos inválidos | 403 rol distinto de
// administrador, o negocio ajeno.
//
// ACTIVACIÓN SIMULADA (MOCK) — mismo criterio que usaba `MockPagoProvider`
// (src/integraciones/pagos.ts) hasta que Integraciones lo reemplazó por un cliente real de
// Mercado Pago (2026-08-17, ver ese archivo): la plataforma real de cobro (Google Play Billing,
// solo Android en v1 — ver 08-despliegue/google-play-billing.md) todavía no está integrada — la
// cuenta de Google Play Developer ya existe, pero la verificación real de compra (validar un
// `purchaseToken` contra la Android Publisher API, ver ese documento §6-7) es un ciclo futuro.
// Este endpoint activa el plan DIRECTO, sin ningún cobro ni verificación real — cualquier
// administrador autenticado de su propio negocio puede "comprar" Turnario Pro gratis mientras
// esto siga siendo el único camino.
// Aceptable para este ciclo (mismo trade-off que se aceptó para Mercado Pago entre Fase 4 y
// 2026-08-17, mientras `pagoProvider` todavía era `MockPagoProvider`) porque no hay dinero real
// involucrado en ningún punto de ESTE endpoint puntual (a diferencia de la seña de turnos, que
// desde ese cierre ya cobra de verdad vía Mercado Pago).
//
// EL DÍA QUE EXISTA LA VERIFICACIÓN REAL: este endpoint se REEMPLAZA (no se extiende) por uno que
// reciba y valide un `purchaseToken` real contra la Android Publisher API — DBA decidió
// explícitamente NO modelar todavía columnas para eso (`purchase_token`, ver 001_init.sql,
// "Deliberadamente NO se modela en este ciclo"), así que a propósito este handler NO agrega
// ninguna columna/campo nuevo para guardarlo — se agregarán recién en esa migración futura.
//
// Upsert (`ON CONFLICT (negocio_id) DO UPDATE`), no INSERT liso: cubre tanto la primera activación
// de un negocio (probablemente ya tiene fila 'gratis' por el backfill/DEFAULT, ver
// migrations/001_init.sql) como una renovación/reactivación después de vencer o cancelar — mismo
// criterio de "no asumir que la fila no existe" que el resto de upserts de este backend (ej.
// `paciente`, `profesional_servicio`). `periodo`/`vencimiento`/`estado` se pisan siempre con el
// valor nuevo; `plan` pasa a 'turnario_pro' incondicionalmente (si ya lo era, no cambia nada).
negociosRouter.post(
  '/:id/suscripcion',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar la suscripción de otro negocio' });
    }
    const bodyParsed = activarSuscripcionSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { periodo } = bodyParsed.data;

    // USD 9/mes, USD 86.40/año (20% off) — backlog.md HU-29/E11 y google-play-billing.md §5. El
    // precio en sí NO se persiste (ver 001_init.sql, "Deliberadamente NO se modela..." — es
    // configuración de producto, no un hecho transaccional mientras la activación sea simulada);
    // se documenta acá solo como referencia de qué representa cada `periodo`.
    const vencimiento = new Date();
    if (periodo === 'mensual') {
      vencimiento.setMonth(vencimiento.getMonth() + 1);
    } else {
      vencimiento.setFullYear(vencimiento.getFullYear() + 1);
    }
    const ts = nowIso();

    const suscripcion = await withTransaction(
      async (client) => {
        const result = await client.query(
          `INSERT INTO suscripcion_negocio (negocio_id, plan, periodo, vencimiento, estado, creado_en, creado_por)
           VALUES ($1, 'turnario_pro', $2, $3, 'activa', $4, $5)
           ON CONFLICT (negocio_id) DO UPDATE SET
             plan = 'turnario_pro', periodo = excluded.periodo, vencimiento = excluded.vencimiento,
             estado = 'activa', modificado_en = $4, modificado_por = $5
           RETURNING plan, periodo, vencimiento, estado`,
          [req.params.id, periodo, vencimiento.toISOString(), ts, req.auth!.sub]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    res.json(suscripcion);
  })
);

// Contrato: PATCH /negocios/:id/suscripcion/cancelar -> 200 { plan, periodo, vencimiento, estado }
// | 403 rol distinto de administrador, o negocio ajeno | 404 este negocio nunca se suscribió a
// Turnario Pro (plan sigue en 'gratis', nada que cancelar).
//
// Opcional (punto 5 de esta ronda) — mismo criterio de "acceso efectivo" que documentó DBA
// (001_init.sql / modelo-datos.md §2novies): cancelar SOLO cambia `estado` a 'cancelada' — NO
// resetea `plan`/`periodo`/`vencimiento`. El negocio conserva el acceso a Turnario Pro hasta que
// venza lo ya pagado (patrón común de SaaS: "cancelar" ≠ "perder acceso ya pagado de inmediato"),
// y `plan = 'turnario_pro'` queda como registro histórico de "alguna vez se suscribió" incluso
// después de vencer/cancelar (ver `tieneAccesoTurnarioPro`, dominio/suscripciones.ts, que ya evalúa
// `estado`/`vencimiento` además de `plan` para decidir el acceso real). No reactiva nada si ya
// estaba 'vencida' — el UPDATE es idempotente (cancelar 2 veces no falla, solo confirma el estado).
negociosRouter.patch(
  '/:id/suscripcion/cancelar',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés administrar la suscripción de otro negocio' });
    }

    const suscripcion = await withTransaction(
      async (client) => {
        const result = await client.query(
          `UPDATE suscripcion_negocio SET estado = 'cancelada', modificado_en = $1, modificado_por = $2
           WHERE negocio_id = $3 AND plan = 'turnario_pro'
           RETURNING plan, periodo, vencimiento, estado`,
          [nowIso(), req.auth!.sub, req.params.id]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    if (!suscripcion) {
      return res.status(404).json({ error: 'Este negocio nunca se suscribió a Turnario Pro' });
    }
    res.json(suscripcion);
  })
);

// ============================================================================
// Acceso de administrador al historial de pacientes — SOLO LECTURA (fast-follow de la épica E15
// "Modo Administrador v1", 2026-08-15). Origen completo de esta decisión — por qué SOLO LECTURA y
// no también escritura, por qué 3 policies `FOR SELECT` nuevas en vez de tocar las `FOR ALL` ya
// aprobadas — en ../../database/migrations/007_paciente_historial_acceso_administrador.sql y
// 03-arquitectura/modelo-datos.md §5septies (DBA); leer ese razonamiento antes de tocar este
// bloque. Resumen operativo para quien mantenga esto después:
//
// - RN7/RN13/D3 (autoría clínica del profesional dueño de la ficha, con implicancia médico-legal,
//   ver documento-funcional.md §3) siguen íntegramente vigentes para la ESCRITURA — este bloque
//   agrega SOLO 3 endpoints GET, ninguno POST/PATCH/DELETE. NO agregar acá (ni en ningún otro
//   lugar) un endpoint que deje crear/editar/borrar paciente/tratamiento/nota_medica en contexto
//   de administrador: no es un detalle pendiente de este ciclo, es una decisión de producto ya
//   evaluada y tomada (CEO + DBA, ver §5septies) — esa escritura sigue siendo EXCLUSIVA del
//   profesional dueño de la fila (`profesionales.ts`, sin cambios).
// - Autorización de base de datos ya resuelta por DBA: 3 policies `FOR SELECT` nuevas
//   (`paciente_select_admin_del_negocio` / `tratamiento_select_admin_del_negocio` /
//   `nota_medica_select_admin_del_negocio`) — alcanza con `withTransaction(fn, { usuarioId:
//   req.auth!.sub, negocioId: req.params.id })`, mismo patrón que el resto de este archivo. NO
//   hace falta ningún `set_config`/lógica de autorización propia acá: ninguna de las 3 policies
//   nuevas depende de `app.negocio_id` (se resuelven solas contra `paciente.negocio_id`, directo o
//   vía JOIN a `paciente` — ver el detalle en modelo-datos.md §5septies), con `app.usuario_id` YA
//   seteado por `withTransaction` alcanza.
// - Aun así, cada query de este bloque filtra EXPLÍCITAMENTE por `negocio_id = :id` en el WHERE
//   (no delega esa parte en la RLS) — mismo criterio que ya usa el resto de este archivo (ej.
//   GET /:id/profesionales, más arriba, filtra `np.negocio_id = $1` pese a que
//   `negocio_profesional_select_publico`/`profesional_select_publico` ya son públicas). Motivo acá
//   además del criterio general: `negocio_administrador` es N:M (modelo-datos.md §2ter) — un mismo
//   usuario puede administrar 2+ negocios — y las policies nuevas de DBA autorizan por
//   `app.usuario_id` SOLO, sin `app.negocio_id` (a propósito, ver §5septies). Sin este filtro
//   explícito, un administrador de los negocios A y B pidiendo `GET /negocios/A/pacientes/:fichaId`
//   con una ficha que en realidad pertenece a B (que ese mismo usuario también administra)
//   recibiría esa ficha "bajo la URL de A" — la RLS por sí sola lo autorizaría (es admin de B), pero
//   sería una confusión de alcance que rompe el aislamiento por negocio (RN9) que el resto de la
//   API sí respeta. El chequeo de rol de arriba (`req.auth!.negocio_id !== req.params.id`) NO cubre
//   este caso (compara contra la "vista activa" del JWT, no contra el negocio real de la fila) —
//   por eso hace falta además el filtro explícito en cada query.
// - `turno` tiene SELECT público (`turno_select_publico ON turno FOR SELECT USING (true)`, ver
//   migrations/001_init.sql) — es decir, la RLS de `turno` NO restringe nada por sí sola. El
//   filtro `t.negocio_id = :id` de GET .../historial (más abajo) no es una precaución extra, es LA
//   única barrera de aislamiento por negocio para esa lectura puntual.
// - `paciente.eliminado_en` (soft delete — ver 001_init.sql, "retirar una ficha creada por
//   error/duplicada") se filtra acá con `IS NULL` en las 3 queries — a diferencia de los endpoints
//   equivalentes del profesional (`profesionales.ts`, GET/PATCH .../pacientes/:pacienteId y GET
//   .../historial), que hoy NO lo filtran (gap preexistente, verificado pero fuera de alcance de
//   este ciclo — no se toca profesionales.ts acá). Para una vista de SOLO LECTURA del
//   administrador no hay motivo para mostrar una ficha que el propio profesional ya retiró como
//   error/duplicada.
// - Shape de respuesta: espejado lo más posible del lado profesional (profesionales.ts, GET
//   /:id/clientes ~673-714, GET/PATCH /:id/pacientes/:pacienteId ~716-919, GET
//   /:id/pacientes/:pacienteId/historial ~921-1047) para que Mobile reuse los mismos patrones de
//   parseo — más `ficha_id`/`profesional_id`/`profesional_nombre` en las 3 respuestas (acá, a
//   diferencia del lado profesional, un negocio entero puede tener N profesionales distintos
//   atendiendo, así que hace falta decir cuál).
// ============================================================================

// Contrato: GET /negocios/:id/pacientes -> 200 [{ ficha_id, id, nombre, email, telefono,
// profesional_id, profesional_nombre, activo, es_nuevo, es_reciente, ultima_visita }, ...] | 400
// :id inválido | 403 rol distinto de administrador, o negocio ajeno.
//
// TODAS las fichas del negocio — una fila por cada `paciente` (no por cliente): la MISMA persona
// atendida por 2 profesionales de este negocio aparece 2 VECES, cada una con sus propios datos
// clínicos (`UNIQUE (negocio_id, profesional_id, cliente_id)`, ver modelo-datos.md §6) — a
// propósito NO se fusionan esas filas. Por eso esta lista sale directo de `paciente` (WHERE
// negocio_id = :id), a diferencia de GET /profesionales/:id/clientes (que sale de `turno`, con
// LEFT JOIN a `paciente`, para poder listar también clientes sin ficha todavía) — acá esa
// diferencia no aplica: sin fila `paciente` no hay `ficha_id` con el que Mobile pueda navegar a
// GET /:id/pacientes/:fichaId de abajo, así que no tendría sentido listar un cliente sin ficha.
//
// `activo`/`es_nuevo`/`es_reciente`/`ultima_visita`: misma definición exacta que ya usa GET
// /profesionales/:id/clientes (HU-19, backlog.md) — ver ese comentario para el detalle completo.
// Única diferencia: acá `activo`/`es_nuevo` salen directo de la fila `paciente` (siempre existe,
// es la tabla que maneja este SELECT — no hace falta el `COALESCE`/`LEFT JOIN LATERAL` que sí
// necesita la versión del profesional para su caso "cliente sin ficha todavía"), y
// `es_reciente`/`ultima_visita` agregan `tr.negocio_id = :id` a la correlación con `turno` (ver
// nota de aislamiento más arriba: sin este filtro, un profesional que trabaja en 2+ negocios
// podría filtrar actividad de OTRO negocio hacia esta vista).
negociosRouter.get(
  '/:id/pacientes',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés ver pacientes de otro negocio' });
    }

    const pacientes = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             pa.id AS ficha_id,
             u.id, u.nombre, u.email, u.telefono,
             pa.profesional_id, up.nombre AS profesional_nombre,
             pa.activo,
             (pa.creado_en >= now() - interval '30 days') AS es_nuevo,
             EXISTS (
               SELECT 1 FROM turno tr
               WHERE tr.negocio_id = $1 AND tr.profesional_id = pa.profesional_id AND tr.cliente_id = pa.cliente_id
                 AND tr.estado = 'confirmado' AND tr.fin < now() AND tr.fin >= now() - interval '30 days'
             ) AS es_reciente,
             (
               SELECT MAX(tr2.fin) FROM turno tr2
               WHERE tr2.negocio_id = $1 AND tr2.profesional_id = pa.profesional_id AND tr2.cliente_id = pa.cliente_id
                 AND tr2.estado = 'confirmado' AND tr2.fin < now()
             ) AS ultima_visita
           FROM paciente pa
           JOIN usuario u ON u.id = pa.cliente_id
           JOIN profesional pr ON pr.id = pa.profesional_id
           JOIN usuario up ON up.id = pr.usuario_id
           WHERE pa.negocio_id = $1 AND pa.eliminado_en IS NULL
           ORDER BY u.nombre ASC, up.nombre ASC`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    res.json(pacientes);
  })
);

// Contrato: GET /negocios/:id/pacientes/:fichaId -> 200 { id, nombre, email, telefono, ficha_id,
// profesional_id, profesional_nombre, fecha_nacimiento, genero, direccion,
// contacto_emergencia_nombre, contacto_emergencia_telefono, contacto_emergencia_relacion,
// alergias, notas_medicas_generales, activo } | 400 :id/:fichaId inválidos | 403 rol distinto de
// administrador, o negocio ajeno | 404 ficha inexistente, eliminada, o de otro negocio.
//
// Detalle completo de UNA ficha puntual (`:fichaId` = `paciente.id`, ver nota de
// `negocioFichaParamsSchema` más arriba). A diferencia de GET /profesionales/:id/pacientes/
// :pacienteId (que arma un default en blanco si el cliente ya está en la cartera pero la fila
// `paciente` no existe todavía — "alta perezosa"), acá no hay ningún default posible: `:fichaId`
// ES la PK de la fila `paciente`, así que sin fila no hay nada que mostrar — 404 directo.
//
// `pa.negocio_id = $2` en el WHERE es lo que garantiza el criterio pedido ("una ficha de otro
// negocio debe quedar inaccesible") — ver la nota de aislamiento al principio de este bloque:
// imprescindible, no una redundancia con la RLS (que autoriza por `app.usuario_id` sin mirar cuál
// negocio pidió la URL).
negociosRouter.get(
  '/:id/pacientes/:fichaId',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioFichaParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés ver pacientes de otro negocio' });
    }

    const resultado = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             u.id, u.nombre, u.email, u.telefono,
             pa.id AS ficha_id, pa.profesional_id, up.nombre AS profesional_nombre,
             pa.fecha_nacimiento, pa.genero, pa.direccion,
             pa.contacto_emergencia_nombre, pa.contacto_emergencia_telefono,
             pa.contacto_emergencia_relacion, pa.alergias, pa.notas_medicas_generales,
             pa.activo
           FROM paciente pa
           JOIN usuario u ON u.id = pa.cliente_id
           JOIN profesional pr ON pr.id = pa.profesional_id
           JOIN usuario up ON up.id = pr.usuario_id
           WHERE pa.id = $1 AND pa.negocio_id = $2 AND pa.eliminado_en IS NULL`,
          [req.params.fichaId, req.params.id]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    if (!resultado) {
      return res.status(404).json({ error: 'Ficha de paciente no encontrada en este negocio' });
    }
    res.json(resultado);
  })
);

// Contrato: GET /negocios/:id/pacientes/:fichaId/historial -> 200 { paciente: { id, nombre,
// email, telefono, ficha_id, profesional_id, profesional_nombre }, resumen: { citas_totales,
// citas_completadas, tratamientos, notas_medicas }, turnos: [...], tratamientos: [...],
// notas_medicas: [...] } | 400 :id/:fichaId inválidos | 403 rol distinto de administrador, o
// negocio ajeno | 404 ficha inexistente, eliminada, o de otro negocio.
//
// Mismas 3 queries (turno/tratamiento/nota_medica) que GET /profesionales/:id/pacientes/
// :pacienteId/historial, pero resueltas a partir de la ficha puntual (`:fichaId` = `paciente.id`)
// en vez de `(profesional_id, cliente_id)` sueltos de la URL:
//   - `tratamiento`/`nota_medica` SÍ tienen `paciente_id` propio (FK directa) — filtrar
//     `WHERE paciente_id = :fichaId` alcanza solo, sin joinear de vuelta contra `paciente` (más
//     simple que el equivalente del profesional, que necesita el JOIN porque parte de
//     `(profesional_id, cliente_id)`, no de una PK de ficha).
//   - `turno` NO tiene `paciente_id` (ver CREATE TABLE turno, modelo-datos.md/001_init.sql) — se
//     sigue resolviendo por `(profesional_id, cliente_id)`, tomados de la fila `paciente` ya
//     resuelta en el primer SELECT de abajo (en vez de venir sueltos por URL, como en el lado
//     profesional), más `negocio_id = :id` (ver nota de aislamiento arriba: `turno` tiene SELECT
//     público, ese filtro es la única barrera acá).
//
// El primer SELECT (resolución de la ficha) cumple 2 roles a la vez: (a) confirma que la ficha
// pertenece a este negocio y no está eliminada (404 si no — mismo criterio que GET
// /:id/pacientes/:fichaId de arriba), y (b) trae `profesional_id`/`cliente_id` para las 2 queries
// de abajo que los necesitan. Igual que el lado profesional, el campo `paciente` de la respuesta
// es el CLIENTE (id/nombre/email/telefono), no la ficha clínica completa — mismo criterio de
// shape ya usado ahí (el resto de la ficha ya se puede pedir aparte con GET
// /:id/pacientes/:fichaId).
negociosRouter.get(
  '/:id/pacientes/:fichaId/historial',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioFichaParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés ver el historial de pacientes de otro negocio' });
    }

    const resultado = await withTransaction(
      async (client) => {
        const fichaResult = await client.query(
          `SELECT
             pa.id AS ficha_id, pa.profesional_id, pa.cliente_id,
             u.nombre, u.email, u.telefono,
             up.nombre AS profesional_nombre
           FROM paciente pa
           JOIN usuario u ON u.id = pa.cliente_id
           JOIN profesional pr ON pr.id = pa.profesional_id
           JOIN usuario up ON up.id = pr.usuario_id
           WHERE pa.id = $1 AND pa.negocio_id = $2 AND pa.eliminado_en IS NULL`,
          [req.params.fichaId, req.params.id]
        );
        const ficha = fichaResult.rows[0];
        if (!ficha) return { tipo: 'no_encontrado' as const };

        // Mismos campos por turno que GET /profesionales/:id/pacientes/:pacienteId/historial —
        // ver ese comentario (profesionales.ts) para el detalle de cada uno
        // (estado_pago/completado/duracion_min derivados).
        const turnosResult = await client.query(
          `SELECT
             t.id, t.inicio, t.fin, t.estado,
             t.estado AS estado_pago,
             (t.estado = 'confirmado' AND t.fin < now()) AS completado,
             s.nombre AS servicio,
             s.precio_referencia AS costo,
             up.nombre AS profesional,
             (EXTRACT(EPOCH FROM (t.fin - t.inicio)) / 60)::int AS duracion_min
           FROM turno t
           JOIN servicio s ON s.id = t.servicio_id
           JOIN profesional pr ON pr.id = t.profesional_id
           JOIN usuario up ON up.id = pr.usuario_id
           WHERE t.negocio_id = $1 AND t.profesional_id = $2 AND t.cliente_id = $3
           ORDER BY t.inicio DESC`,
          [req.params.id, ficha.profesional_id, ficha.cliente_id]
        );

        const tratamientosResult = await client.query(
          `SELECT id, descripcion, fecha_inicio, fecha_fin
           FROM tratamiento
           WHERE paciente_id = $1
           ORDER BY fecha_inicio DESC`,
          [req.params.fichaId]
        );

        const notasResult = await client.query(
          `SELECT id, fecha, texto
           FROM nota_medica
           WHERE paciente_id = $1
           ORDER BY fecha DESC`,
          [req.params.fichaId]
        );

        const citasCompletadas = turnosResult.rows.filter((t: any) => t.completado).length;

        return {
          tipo: 'ok' as const,
          paciente: {
            id: ficha.cliente_id,
            nombre: ficha.nombre,
            email: ficha.email,
            telefono: ficha.telefono,
            ficha_id: ficha.ficha_id,
            profesional_id: ficha.profesional_id,
            profesional_nombre: ficha.profesional_nombre,
          },
          resumen: {
            citas_totales: turnosResult.rowCount ?? 0,
            citas_completadas: citasCompletadas,
            tratamientos: tratamientosResult.rowCount ?? 0,
            notas_medicas: notasResult.rowCount ?? 0,
          },
          turnos: turnosResult.rows,
          tratamientos: tratamientosResult.rows,
          notas_medicas: notasResult.rows,
        };
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Ficha de paciente no encontrada en este negocio' });
      case 'ok':
        return res.json({
          paciente: resultado.paciente,
          resumen: resultado.resumen,
          turnos: resultado.turnos,
          tratamientos: resultado.tratamientos,
          notas_medicas: resultado.notas_medicas,
        });
    }
  })
);

// ============================================================================
// Reportes y Estadísticas (HU-28/E10) — vista de NEGOCIO/administrador, TODOS los profesionales a
// la vez. Completa lo que GET /profesionales/:id/reportes (profesionales.ts, ver el bloque de
// comentarios "Reportes y Estadísticas" ahí, ~línea 1153) dejó documentado explícitamente afuera
// de esa v1: "Vista de negocio/administrador (todos los profesionales a la vez): HU-28 la pide,
// pero la consigna de ese ciclo la difería explícitamente [...] Cuando se construya, es un
// endpoint nuevo (ej. GET /negocios/:id/reportes), no una extensión de este." Este es ese
// endpoint nuevo.
// ============================================================================

// Contrato: GET /negocios/:id/reportes?desde=<ISO>&hasta=<ISO>&servicio_id=<uuid>&profesional_id=
// <uuid> (los 4 query params son opcionales e independientes) -> 200 { desde, hasta, servicio_id,
// profesional_id, turnos_totales, turnos_completados, turnos_cancelados, monto_facturado } | 400
// query inválida | 403 rol distinto de administrador o `:id` ajeno.
//
// MISMA lógica/definiciones exactas que GET /profesionales/:id/reportes — `turnos_completados` =
// `estado = 'confirmado' AND fin < now()`, "monto facturado" = suma de `servicio.precio_referencia`
// (no la seña) de esos turnos completados, `turnos_totales` excluye `estado = 'reprogramado'`
// (la fila vieja que deja HU-13 al reprogramar, para no duplicar la cita real),
// `turnos_cancelados` = `estado = 'cancelado'` sin más condición — ver ese comentario
// (profesionales.ts) para el razonamiento completo de cada una, no repetido acá. Mismo criterio de
// período también: filtra por `turno.inicio`, no por `creado_en`, con ambos extremos normalizados
// vía `new Date(x).toISOString()`.
//
// 2 diferencias con el lado profesional, ambas ya anticipadas por ese mismo comentario:
//   - `WHERE t.negocio_id = :id` en vez de `t.profesional_id = :id` — el "administrador ve el
//     reporte de todo su negocio (todos los profesionales)" que pide HU-28 explícitamente.
//   - `profesional_id` pasa de fijo (era el `:id` de la URL del lado profesional, vía
//     `esPropioProfesional`) a FILTRO OPCIONAL más, exactamente al mismo patrón que ya usan
//     `desde`/`hasta`/`servicio_id` (`AND ($X::uuid IS NULL OR t.profesional_id = $X)`) — acá sí
//     tiene sentido (a diferencia del lado profesional, donde ese comentario ya explica por qué
//     no aplica ahí): esta ruta cubre TODOS los profesionales del negocio por default, y este
//     filtro deja acotar el reporte a uno puntual sin perder la vista agregada como default.
//
// Sin gate de plan/Turnario Pro (`tieneAccesoTurnarioPro`, ver el bloque de Suscripción más
// arriba en este archivo): ninguno de los 2 endpoints de reportes lo tiene hoy — no fue pedido
// para esta funcionalidad, no se inventa acá.
//
// Auth: RN9 vía claim del JWT, mismo patrón que el resto de este archivo (comparación directa
// contra `:id`, no una query aparte) — SIN el 400 "elegí un negocio primero" que sí tiene el lado
// profesional: ese chequeo existe ahí porque un profesional puede no tener ninguna "vista activa"
// seteada todavía (puede pertenecer a 0+ negocios, ver GET /profesionales/:id/turnos). Un
// administrador en ESTE archivo siempre opera sobre su negocio fijo — mismo criterio que cada
// otro endpoint de negocios.ts, ninguno repite ese chequeo.
//
// Sin policy nueva de RLS: `turno`/`servicio` ya tienen SELECT público a nivel de base
// (`turno_select_publico`/`servicio_select_publico`, `USING (true)` — confirmado en
// ../../database/migrations/001_init.sql) — mismo motivo por el que GET /profesionales/:id/reportes
// tampoco necesitó ninguna nueva. `withTransaction` con contexto de todos modos, por consistencia
// con el resto de este archivo (mismo criterio ya documentado junto a GET /:id/profesionales).
negociosRouter.get(
  '/:id/reportes',
  requireAuth('administrador'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = negocioIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (req.auth!.negocio_id !== req.params.id) {
      return res.status(403).json({ error: 'No podés ver el reporte de otro negocio' });
    }
    const queryParsed = reportesNegocioQuerySchema.safeParse(req.query);
    if (!queryParsed.success) return respuestaValidacionFallida(res, queryParsed.error);
    const { desde, hasta, servicio_id, profesional_id } = queryParsed.data;
    const desdeIso = desde ? new Date(desde).toISOString() : null;
    const hastaIso = hasta ? new Date(hasta).toISOString() : null;

    const filas = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             t.estado,
             (t.estado = 'confirmado' AND t.fin < now()) AS completado,
             s.precio_referencia
           FROM turno t
           JOIN servicio s ON s.id = t.servicio_id
           WHERE t.negocio_id = $1
             AND ($2::timestamptz IS NULL OR t.inicio >= $2)
             AND ($3::timestamptz IS NULL OR t.inicio <= $3)
             AND ($4::uuid IS NULL OR t.servicio_id = $4)
             AND ($5::uuid IS NULL OR t.profesional_id = $5)`,
          [req.params.id, desdeIso, hastaIso, servicio_id ?? null, profesional_id ?? null]
        );
        return result.rows as { estado: string; completado: boolean; precio_referencia: number | null }[];
      },
      { usuarioId: req.auth!.sub, negocioId: req.params.id }
    );

    const completados = filas.filter((f) => f.completado);
    const turnos_totales = filas.filter((f) => f.estado !== 'reprogramado').length;
    const turnos_cancelados = filas.filter((f) => f.estado === 'cancelado').length;
    const monto_facturado = completados.reduce((acc, f) => acc + (f.precio_referencia ?? 0), 0);

    res.json({
      desde: desdeIso,
      hasta: hastaIso,
      servicio_id: servicio_id ?? null,
      profesional_id: profesional_id ?? null,
      turnos_totales,
      turnos_completados: completados.length,
      turnos_cancelados,
      monto_facturado,
    });
  })
);
