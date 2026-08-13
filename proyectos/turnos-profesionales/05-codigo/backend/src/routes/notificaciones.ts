import { Router, Response } from 'express';
import { z } from 'zod';
import { nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { uuidSchema, respuestaValidacionFallida } from '../dominio/validacion';
import { armarMensajeNotificacion } from '../dominio/notificaciones';

// Configuración de Notificaciones (HU-26, mapa-pantallas.md §5.14) + Bandeja de Notificaciones
// (HU-14b/HU-25, mapa-pantallas.md §5.15) — router nuevo, mismo criterio de "prefijo = concepto
// de dominio" que ya usa este backend (ej. turnos.ts monta /turnos aunque también toque
// `pago`/`paciente` de paso). Acá el concepto es "notificaciones de este usuario", que abarca 2
// tablas hermanas (`notificacion` y `usuario_preferencias_notificacion` — ver
// database/migrations/001_init.sql, bloque "Preferencias de notificación": "dos tablas hermanas
// de la misma familia conceptual") y 2 pantallas que el propio wireframe presenta como una sola
// unidad de navegación (§5.15: "El ícono ⚙ del header [de la bandeja] abre la Configuración de
// Notificaciones granular (§5.14)").
//
// Decisión de ubicación: NO se creó `src/routes/usuario.ts` para `/configuracion` (a diferencia
// de `/usuario/privacidad`, mismo patrón lazy-upsert que se reusa acá) — ese archivo no existe
// en esta rama (`feature/notificaciones`, parada sobre `main`). Lo crea, con OTRO contenido
// (`/usuario/perfil`, `/usuario/privacidad`, HU-32), el ciclo en paralelo
// `feature/configuracion-profesional`, todavía no mergeado. Crearlo acá también, con contenido
// distinto, hubiera producido el mismo archivo nuevo en 2 ramas con historia divergente —
// conflicto de merge garantizado. Todas las rutas de este ciclo quedan bajo `/notificaciones` en
// su lugar; si más adelante conviene mover `/notificaciones/configuracion` a
// `/usuario/notificaciones` para uniformar con `/usuario/privacidad` una vez mergeadas ambas
// ramas, es una decisión de un ciclo futuro (Director General IA/Backend) — mismo contrato de
// campos, sin impacto de datos.
export const notificacionesRouter = Router();

const notificacionIdParamsSchema = z.object({ id: uuidSchema });

// Los 7 booleanos de usuario_preferencias_notificacion (ver 001_init.sql, bloque "Preferencias
// de notificación"). Todos requeridos, no `.optional()` — mismo criterio que
// `privacidadSchema`/`fichaPacienteSchema` en este backend: el PATCH hace upsert de la fila
// completa, y el wireframe (§5.14bis) confirma un único botón "Guardar" para la pantalla entera,
// no autoguardado toggle por toggle.
const configuracionNotificacionesSchema = z.object({
  notif_canal_push: z.boolean(),
  notif_canal_email: z.boolean(),
  notif_canal_whatsapp: z.boolean(),
  notif_citas_recordatorios: z.boolean(),
  notif_promociones: z.boolean(),
  notif_sonido: z.boolean(),
  notif_vibracion: z.boolean(),
});

// Defaults de "fábrica" — MISMOS valores que el DEFAULT de cada columna (001_init.sql /
// 004_notificaciones.sql). Mientras no exista fila para un usuario_id dado, la API devuelve
// estos defaults en vez de crear la fila en el GET o responder 404 — HU-26 es transversal a
// cualquier cuenta existente, no algo opt-in que requiera un alta previa.
const DEFAULTS_CONFIGURACION_NOTIFICACIONES = {
  notif_canal_push: true,
  notif_canal_email: true,
  notif_canal_whatsapp: true,
  notif_citas_recordatorios: true,
  notif_promociones: false,
  notif_sonido: true,
  notif_vibracion: true,
};

// ============================================================================
// GET /notificaciones + PATCH /:id/leer + PATCH /leer-todas — Bandeja de Notificaciones
// (HU-14b/HU-25, mapa-pantallas.md §5.15). Cualquier rol autenticado, siempre las propias
// (destinatario_usuario_id = quien pide).
// ============================================================================

// Contrato: GET /notificaciones -> 200 [{ id, tipo, leido, creado_en, turno_id, mensaje }, ...]
// (array, más nuevas primero) | 401 sin token válido.
//
// Agrupado "Hoy"/"Ayer" (wireframe §5.15): NO lo arma este endpoint — devuelve una lista plana
// ordenada por `creado_en DESC`, mismo criterio ya establecido en este backend para listas
// similares (GET /turnos/mios en turnos.ts, GET /clientes/:id/historial en clientes.ts: ninguna
// de las dos agrupa ni envuelve el array en un objeto). Motivo puntual, además de esa
// consistencia: "Hoy"/"Ayer" es relativo al DÍA CALENDARIO LOCAL de quien mira la bandeja, y
// este backend no tiene ninguna noción confiable de la zona horaria del dispositivo (no viaja en
// el JWT, no hay header de por medio) — agrupar acá obligaría a asumir una zona horaria fija (la
// del proceso Node, ver dominio/notificaciones.ts) que puede no coincidir con la del usuario
// real, mostrando "Ayer" en vez de "Hoy" (o viceversa) cerca de la medianoche para alguien en
// otro huso horario. Mobile ya recibe `creado_en` en ISO-8601 completo y puede agrupar por el
// día calendario de SU propio reloj local sin ambigüedad — Backend solo garantiza el orden.
notificacionesRouter.get(
  '/',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const filas = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             n.id, n.tipo, n.leido, n.creado_en, n.turno_id,
             t.inicio AS turno_inicio, t.cliente_id AS turno_cliente_id,
             uc.nombre AS cliente_nombre, up.nombre AS profesional_nombre
           FROM notificacion n
           JOIN turno t ON t.id = n.turno_id
           JOIN usuario uc ON uc.id = t.cliente_id
           JOIN profesional pr ON pr.id = t.profesional_id
           JOIN usuario up ON up.id = pr.usuario_id
           WHERE n.destinatario_usuario_id = $1
           ORDER BY n.creado_en DESC`,
          [req.auth!.sub]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    const notificaciones = filas.map((fila: any) => ({
      id: fila.id,
      tipo: fila.tipo,
      leido: fila.leido,
      creado_en: fila.creado_en,
      turno_id: fila.turno_id,
      mensaje: armarMensajeNotificacion({
        tipo: fila.tipo,
        clienteNombre: fila.cliente_nombre,
        profesionalNombre: fila.profesional_nombre,
        turnoInicio: fila.turno_inicio,
        destinatarioEsCliente: fila.turno_cliente_id === req.auth!.sub,
      }),
    }));

    res.json(notificaciones);
  })
);

// Contrato: PATCH /notificaciones/:id/leer -> 200 { id, tipo, leido, creado_en, turno_id } | 400
// :id mal formado | 401 sin token válido | 404 (no existe, o existe pero no es tuya — mismo
// código para ambos casos a propósito: distinguirlos revelaría la existencia de una notificación
// ajena, algo que ningún caso de uso de esta pantalla necesita; a diferencia de
// PATCH /turnos/:id/cancelar en turnos.ts, que sí distingue 403/404 por un motivo puntual
// documentado ahí — acá no aplica el mismo motivo).
notificacionesRouter.patch(
  '/:id/leer',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const paramsParsed = notificacionIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    const actualizada = await withTransaction(
      async (client) => {
        // `destinatario_usuario_id = $3` en el WHERE (redundante con la policy RLS
        // `notificacion_update_propia_marcar_leida`) — mismo criterio de defensa en profundidad
        // que el resto de este backend (ej. `turno.cliente_id` chequeado en código en turnos.ts
        // ADEMÁS de la policy `turno_acceso_negocio_o_cliente`). Si no matchea (ajena o
        // inexistente), 0 filas afectadas, sin distinguir el motivo (ver comentario de arriba).
        const result = await client.query(
          `UPDATE notificacion SET leido = true, modificado_en = $1
           WHERE id = $2 AND destinatario_usuario_id = $3
           RETURNING id, tipo, leido, creado_en, turno_id`,
          [nowIso(), req.params.id, req.auth!.sub]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    if (!actualizada) return res.status(404).json({ error: 'Notificación no encontrada' });
    res.json(actualizada);
  })
);

// Contrato: PATCH /notificaciones/leer-todas -> 200 { actualizadas: number } | 401 sin token
// válido. Marca TODAS las no leídas del usuario autenticado, sin body ni parámetros — a
// diferencia de /:id/leer, acá no hace falta distinguir "ya estaban todas leídas" de "no tenías
// ninguna notificación": ambos son, correctamente, el mismo resultado `{ actualizadas: 0 }`, no
// un error.
notificacionesRouter.patch(
  '/leer-todas',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const cantidad = await withTransaction(
      async (client) => {
        const result = await client.query(
          `UPDATE notificacion SET leido = true, modificado_en = $1
           WHERE destinatario_usuario_id = $2 AND leido = false`,
          [nowIso(), req.auth!.sub]
        );
        return result.rowCount ?? 0;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json({ actualizadas: cantidad });
  })
);

// ============================================================================
// GET/PATCH /notificaciones/configuracion — Configuración de Notificaciones granular (HU-26,
// mapa-pantallas.md §5.14). Cualquier rol autenticado, siempre sobre uno mismo. Mismo patrón
// lazy-upsert que GET/PATCH /usuario/privacidad (HU-32, feature/configuracion-profesional,
// src/routes/usuario.ts — no presente en esta rama, ver nota de diseño arriba).
// ============================================================================

// Contrato: GET /notificaciones/configuracion -> 200 { notif_canal_push, notif_canal_email,
// notif_canal_whatsapp, notif_citas_recordatorios, notif_promociones, notif_sonido,
// notif_vibracion } (defaults de fábrica si la cuenta nunca guardó nada — NUNCA 404) | 401 sin
// token válido.
notificacionesRouter.get(
  '/configuracion',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const fila = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT notif_canal_push, notif_canal_email, notif_canal_whatsapp,
                  notif_citas_recordatorios, notif_promociones, notif_sonido, notif_vibracion
           FROM usuario_preferencias_notificacion WHERE usuario_id = $1`,
          [req.auth!.sub]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(fila ?? DEFAULTS_CONFIGURACION_NOTIFICACIONES);
  })
);

// Contrato: PATCH /notificaciones/configuracion, body = los 7 booleanos de arriba -> 200 (mismo
// shape) | 400 datos inválidos | 401 sin token válido.
notificacionesRouter.patch(
  '/configuracion',
  requireAuth(),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const bodyParsed = configuracionNotificacionesSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const datos = bodyParsed.data;

    const preferencias = await withTransaction(
      async (client) => {
        const ts = nowIso();
        const result = await client.query(
          `INSERT INTO usuario_preferencias_notificacion
             (usuario_id, notif_canal_push, notif_canal_email, notif_canal_whatsapp,
              notif_citas_recordatorios, notif_promociones, notif_sonido, notif_vibracion, creado_en)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (usuario_id) DO UPDATE SET
             notif_canal_push = excluded.notif_canal_push,
             notif_canal_email = excluded.notif_canal_email,
             notif_canal_whatsapp = excluded.notif_canal_whatsapp,
             notif_citas_recordatorios = excluded.notif_citas_recordatorios,
             notif_promociones = excluded.notif_promociones,
             notif_sonido = excluded.notif_sonido,
             notif_vibracion = excluded.notif_vibracion,
             modificado_en = $10
           RETURNING notif_canal_push, notif_canal_email, notif_canal_whatsapp,
                     notif_citas_recordatorios, notif_promociones, notif_sonido, notif_vibracion`,
          [
            req.auth!.sub,
            datos.notif_canal_push,
            datos.notif_canal_email,
            datos.notif_canal_whatsapp,
            datos.notif_citas_recordatorios,
            datos.notif_promociones,
            datos.notif_sonido,
            datos.notif_vibracion,
            ts,
            ts,
          ]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(preferencias);
  })
);
