import { Router } from 'express';
import { z } from 'zod';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { calcularSlotsDisponibles } from '../dominio/disponibilidad';
import {
  uuidSchema,
  fechaIsoSchema,
  diaSemanaSchema,
  horaSchema,
  montoPositivoSchema,
  respuestaValidacionFallida,
} from '../dominio/validacion';

export const profesionalesRouter = Router();

function esPropioProfesional(req: AuthedRequest): boolean {
  return req.auth!.rol === 'profesional' && req.auth!.profesional_id === req.params.id;
}

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación de entrada — se
// aplican al INICIO de cada handler, antes de tocar la base de datos.
const profesionalIdParamsSchema = z.object({ id: uuidSchema });

const asociarServicioSchema = z.object({
  servicio_id: uuidSchema,
  requiere_sena: z.boolean().optional(),
  monto_sena: montoPositivoSchema.nullable().optional(),
});

const disponibilidadSchema = z.object({
  servicio_id: uuidSchema,
  dia_semana: diaSemanaSchema,
  hora_inicio: horaSchema,
  hora_fin: horaSchema,
});

const excepcionSchema = z.object({
  inicio: fechaIsoSchema,
  fin: fechaIsoSchema,
  motivo: z.string().nullable().optional(),
});

// D10 (amenda RN3, ver modelo-datos.md §2quater): entero positivo o `null` EXPLÍCITO (para que
// el profesional pueda volver a usar la duración del servicio si se arrepiente) — no `.optional()`,
// el body siempre tiene que traer el campo, aunque sea `null`.
const configuracionProfesionalSchema = z.object({
  duracion_cita_min: z
    .number()
    .int('duracion_cita_min debe ser un entero')
    .positive('duracion_cita_min debe ser mayor a 0')
    .nullable(),
});

// HU-04 / HU-04b: el profesional asocia un servicio a su agenda y configura si requiere seña.
profesionalesRouter.post(
  '/:id/servicios',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés configurar tus propios servicios' });
    }
    const bodyParsed = asociarServicioSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { servicio_id, requiere_sena, monto_sena } = bodyParsed.data;

    // `servicio` tiene SELECT público (ver migrations/001_init.sql) — pool.query directo.
    const servicioResult = await pool.query('SELECT negocio_id FROM servicio WHERE id = $1', [servicio_id]);
    const servicio = servicioResult.rows[0] as { negocio_id: string } | undefined;
    if (!servicio) {
      return res.status(404).json({ error: 'Servicio no encontrado' });
    }

    // Integridad N:M (ver modelo-datos.md §2ter, "recomendación adicional"): antes de esta
    // generalización era estructuralmente imposible asociar un servicio de un negocio donde el
    // profesional no trabaja (tenía un único negocio_id posible). Ahora `profesional` no tiene
    // negocio fijo, así que hay que validarlo a nivel de aplicación antes de insertar.
    // `negocio_profesional` también tiene SELECT público.
    const esMiembroActivoResult = await pool.query(
      'SELECT 1 FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2 AND activo = true',
      [servicio.negocio_id, req.params.id]
    );
    if (!esMiembroActivoResult.rowCount) {
      return res.status(403).json({
        error: 'No podés asociarte a un servicio de un negocio del que no sos miembro activo',
      });
    }

    await withTransaction(
      async (client) => {
        await client.query(
          `INSERT INTO profesional_servicio (profesional_id, servicio_id, requiere_sena, monto_sena)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (profesional_id, servicio_id) DO UPDATE SET requiere_sena = excluded.requiere_sena, monto_sena = excluded.monto_sena`,
          [req.params.id, servicio_id, !!requiere_sena, monto_sena ?? null]
        );
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    res.status(201).json({ ok: true });
  })
);

// HU-05: el profesional define un bloque de disponibilidad recurrente.
profesionalesRouter.post(
  '/:id/disponibilidad',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés definir tu propia disponibilidad' });
    }
    // MEDIUM-3 / DEF-04 (ver informe-seguridad.md y reporte-qa.md): valida presencia, UUID y el
    // rango de dia_semana ACÁ, en vez de dejar que lo rechace el CHECK de la base de datos.
    const bodyParsed = disponibilidadSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { servicio_id, dia_semana, hora_inicio, hora_fin } = bodyParsed.data;
    const id = uuid();

    await withTransaction(
      async (client) => {
        await client.query(
          `INSERT INTO disponibilidad (id, profesional_id, servicio_id, dia_semana, hora_inicio, hora_fin, creado_en)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [id, req.params.id, servicio_id, dia_semana, hora_inicio, hora_fin, nowIso()]
        );
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    res.status(201).json({ id });
  })
);

// HU-15: excepción puntual (feriado/licencia) — RN5/RN6.
profesionalesRouter.post(
  '/:id/excepciones',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés bloquear tu propia agenda' });
    }
    const bodyParsed = excepcionSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { inicio, fin, motivo } = bodyParsed.data;
    const id = uuid();

    const turnosAfectadosCount = await withTransaction(
      async (client) => {
        const turnosAfectadosResult = await client.query(
          `SELECT id FROM turno WHERE profesional_id = $1 AND estado IN ('pendiente_de_pago','confirmado')
           AND inicio < $2 AND fin > $3`,
          [req.params.id, fin, inicio]
        );

        await client.query(
          'INSERT INTO excepcion_disponibilidad (id, profesional_id, inicio, fin, motivo, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [id, req.params.id, inicio, fin, motivo ?? null, nowIso()]
        );

        return turnosAfectadosResult.rowCount ?? 0;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    res.status(201).json({
      id,
      turnos_afectados: turnosAfectadosCount,
      aviso:
        turnosAfectadosCount > 0
          ? 'RN6: hay turnos ya reservados en este rango — gestioná su reprogramación antes de confirmar el bloqueo definitivo.'
          : undefined,
    });
  })
);

// D10 (amenda RN3, ver modelo-datos.md §2quater): el profesional configura (o revierte) su
// propia duración general de cita. Cuando está seteada (no NULL), reemplaza SIEMPRE
// `servicio.duracion_min` para calcular los turnos de este profesional, en todos sus servicios,
// sin excepción (aplicado en `src/dominio/disponibilidad.ts` y `src/routes/turnos.ts`, POST /
// y PATCH /:id/reprogramar). `duracion_cita_min: null` explícito revierte al comportamiento de
// siempre: usar la duración del servicio.
//
// RLS: el UPDATE de `profesional` de DBA (`profesional_update_admin_de_su_negocio`) solo
// habilita a un ADMINISTRADOR — no al propio profesional (gap documentado por DBA, ver
// modelo-datos.md §5 y memory/proyectos/turnos-profesionales/decisiones.md, entrada
// "profesional.duracion_cita_min"). migrations/001_init.sql (copia operativa de Backend) agrega
// una policy adicional de auto-servicio (`profesional_update_propio_duracion_cita`) para que
// este UPDATE no quede denegado por RLS — ver esa policy para el detalle y el flag para
// DBA/Security. Por eso se chequea `rowCount` acá: si esa policy no está aplicada en la base
// real, el UPDATE afecta 0 filas EN SILENCIO (RLS no tira error, solo no matchea ninguna fila) y
// preferimos un 500 explícito a un 200 mintiendo que se guardó.
profesionalesRouter.patch(
  '/:id/configuracion',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés configurar tu propia agenda' });
    }
    const bodyParsed = configuracionProfesionalSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { duracion_cita_min } = bodyParsed.data;

    const rowCount = await withTransaction(
      async (client) => {
        const result = await client.query('UPDATE profesional SET duracion_cita_min = $1 WHERE id = $2', [
          duracion_cita_min,
          req.params.id,
        ]);
        return result.rowCount;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    if (!rowCount) {
      return res.status(500).json({
        error: 'No se pudo guardar la configuración (revisar policy RLS de auto-servicio sobre profesional)',
      });
    }

    res.json({ id: req.params.id, duracion_cita_min });
  })
);

// HU-09: slots disponibles de un profesional para un servicio (motor de disponibilidad — CU1/CU4).
// El cálculo en sí vive en `src/dominio/disponibilidad.ts` (compartido con `POST /turnos`, que
// lo usa para validar RN1 — ver comentario ahí y en turnos.ts). Acá solo se resuelven los query
// params y se arma la respuesta pública, incluyendo el "próximo disponible" (D5, sin lista de
// espera) cuando no hay nada en el rango pedido. Público — se le pasa `pool` directo a
// `calcularSlotsDisponibles` (sin transacción ni contexto RLS; la ocupación de `turno` es
// visible igual gracias a la policy `turno_select_publico`, ver migrations/001_init.sql).
profesionalesRouter.get(
  '/:id/slots',
  asyncHandler(async (req, res) => {
    const { servicio_id, desde, dias } = req.query as { servicio_id?: string; desde?: string; dias?: string };
    if (!servicio_id) return res.status(400).json({ error: 'servicio_id es requerido' });

    let desdeDate: Date | undefined;
    if (desde !== undefined) {
      desdeDate = new Date(desde);
      if (isNaN(desdeDate.getTime())) {
        return res.status(400).json({ error: "El parámetro 'desde' no es una fecha válida" });
      }
    }

    const resultado = await calcularSlotsDisponibles(pool, req.params.id, servicio_id, {
      desde: desdeDate,
      dias: dias !== undefined ? Number(dias) : undefined,
    });
    if (!resultado) return res.status(404).json({ error: 'Servicio no encontrado' });

    res.json({
      slots: resultado.slots,
      proximo_disponible: resultado.slots[0] ?? null, // D5
    });
  })
);

// HU-06: agenda del profesional autenticado (turnos propios, para la pantalla de Agenda).
profesionalesRouter.get(
  '/:id/turnos',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver tu propia agenda' });
    }
    const turnos = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT t.id, t.inicio, t.fin, t.estado, s.nombre AS servicio, u.nombre AS cliente
           FROM turno t
           JOIN servicio s ON s.id = t.servicio_id
           JOIN usuario u ON u.id = t.cliente_id
           WHERE t.profesional_id = $1 AND t.estado IN ('pendiente_de_pago','confirmado')
           ORDER BY t.inicio ASC`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(turnos);
  })
);

// HU-10: listado de clientes atendidos por el profesional autenticado.
profesionalesRouter.get(
  '/:id/clientes',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver tus propios clientes' });
    }
    const clientes = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT DISTINCT u.id, u.nombre, u.email FROM turno t
           JOIN usuario u ON u.id = t.cliente_id
           WHERE t.profesional_id = $1`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(clientes);
  })
);
