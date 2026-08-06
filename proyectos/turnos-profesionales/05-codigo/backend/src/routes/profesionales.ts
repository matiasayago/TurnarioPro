import { Router } from 'express';
import { z } from 'zod';
import { v4 as uuid } from 'uuid';
import { db, nowIso } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
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
profesionalesRouter.post('/:id/servicios', requireAuth('profesional'), (req: AuthedRequest, res) => {
  const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
  if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés configurar tus propios servicios' });
  }
  const bodyParsed = asociarServicioSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { servicio_id, requiere_sena, monto_sena } = bodyParsed.data;

  const servicio = db.prepare('SELECT negocio_id FROM servicio WHERE id = ?').get(servicio_id) as
    | { negocio_id: string }
    | undefined;
  if (!servicio) {
    return res.status(404).json({ error: 'Servicio no encontrado' });
  }

  // Integridad N:M (ver modelo-datos.md §2ter, "recomendación adicional"): antes de esta
  // generalización era estructuralmente imposible asociar un servicio de un negocio donde el
  // profesional no trabaja (tenía un único negocio_id posible). Ahora `profesional` no tiene
  // negocio fijo, así que hay que validarlo a nivel de aplicación antes de insertar.
  const esMiembroActivo = db
    .prepare('SELECT 1 FROM negocio_profesional WHERE negocio_id = ? AND profesional_id = ? AND activo = 1')
    .get(servicio.negocio_id, req.params.id);
  if (!esMiembroActivo) {
    return res.status(403).json({
      error: 'No podés asociarte a un servicio de un negocio del que no sos miembro activo',
    });
  }

  db.prepare(
    `INSERT INTO profesional_servicio (profesional_id, servicio_id, requiere_sena, monto_sena)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(profesional_id, servicio_id) DO UPDATE SET requiere_sena = excluded.requiere_sena, monto_sena = excluded.monto_sena`
  ).run(req.params.id, servicio_id, requiere_sena ? 1 : 0, monto_sena ?? null);

  res.status(201).json({ ok: true });
});

// HU-05: el profesional define un bloque de disponibilidad recurrente.
profesionalesRouter.post('/:id/disponibilidad', requireAuth('profesional'), (req: AuthedRequest, res) => {
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
  db.prepare(
    `INSERT INTO disponibilidad (id, profesional_id, servicio_id, dia_semana, hora_inicio, hora_fin, creado_en)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(id, req.params.id, servicio_id, dia_semana, hora_inicio, hora_fin, nowIso());
  res.status(201).json({ id });
});

// HU-15: excepción puntual (feriado/licencia) — RN5/RN6.
profesionalesRouter.post('/:id/excepciones', requireAuth('profesional'), (req: AuthedRequest, res) => {
  const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
  if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés bloquear tu propia agenda' });
  }
  const bodyParsed = excepcionSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { inicio, fin, motivo } = bodyParsed.data;

  const turnosAfectados = db
    .prepare(
      `SELECT id FROM turno WHERE profesional_id = ? AND estado IN ('pendiente_de_pago','confirmado')
       AND inicio < ? AND fin > ?`
    )
    .all(req.params.id, fin, inicio);

  const id = uuid();
  db.prepare(
    'INSERT INTO excepcion_disponibilidad (id, profesional_id, inicio, fin, motivo, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
  ).run(id, req.params.id, inicio, fin, motivo ?? null, nowIso());

  res.status(201).json({
    id,
    turnos_afectados: turnosAfectados.length,
    aviso: turnosAfectados.length > 0
      ? 'RN6: hay turnos ya reservados en este rango — gestioná su reprogramación antes de confirmar el bloqueo definitivo.'
      : undefined,
  });
});

// D10 (amenda RN3, ver modelo-datos.md §2quater): el profesional configura (o revierte) su
// propia duración general de cita. Cuando está seteada (no NULL), reemplaza SIEMPRE
// `servicio.duracion_min` para calcular los turnos de este profesional, en todos sus servicios,
// sin excepción (aplicado en `src/dominio/disponibilidad.ts` y `src/routes/turnos.ts`, POST /
// y PATCH /:id/reprogramar). `duracion_cita_min: null` explícito revierte al comportamiento de
// siempre: usar la duración del servicio.
profesionalesRouter.patch('/:id/configuracion', requireAuth('profesional'), (req: AuthedRequest, res) => {
  const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
  if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés configurar tu propia agenda' });
  }
  const bodyParsed = configuracionProfesionalSchema.safeParse(req.body);
  if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
  const { duracion_cita_min } = bodyParsed.data;

  db.prepare('UPDATE profesional SET duracion_cita_min = ? WHERE id = ?').run(
    duracion_cita_min,
    req.params.id
  );

  res.json({ id: req.params.id, duracion_cita_min });
});

// HU-09: slots disponibles de un profesional para un servicio (motor de disponibilidad — CU1/CU4).
// El cálculo en sí vive en `src/dominio/disponibilidad.ts` (compartido con `POST /turnos`, que
// lo usa para validar RN1 — ver comentario ahí y en turnos.ts). Acá solo se resuelven los query
// params y se arma la respuesta pública, incluyendo el "próximo disponible" (D5, sin lista de
// espera) cuando no hay nada en el rango pedido.
profesionalesRouter.get('/:id/slots', (req, res) => {
  const { servicio_id, desde, dias } = req.query as { servicio_id?: string; desde?: string; dias?: string };
  if (!servicio_id) return res.status(400).json({ error: 'servicio_id es requerido' });

  let desdeDate: Date | undefined;
  if (desde !== undefined) {
    desdeDate = new Date(desde);
    if (isNaN(desdeDate.getTime())) {
      return res.status(400).json({ error: "El parámetro 'desde' no es una fecha válida" });
    }
  }

  const resultado = calcularSlotsDisponibles(req.params.id, servicio_id, {
    desde: desdeDate,
    dias: dias !== undefined ? Number(dias) : undefined,
  });
  if (!resultado) return res.status(404).json({ error: 'Servicio no encontrado' });

  res.json({
    slots: resultado.slots,
    proximo_disponible: resultado.slots[0] ?? null, // D5
  });
});

// HU-06: agenda del profesional autenticado (turnos propios, para la pantalla de Agenda).
profesionalesRouter.get('/:id/turnos', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés ver tu propia agenda' });
  }
  const turnos = db
    .prepare(
      `SELECT t.id, t.inicio, t.fin, t.estado, s.nombre AS servicio, u.nombre AS cliente
       FROM turno t
       JOIN servicio s ON s.id = t.servicio_id
       JOIN usuario u ON u.id = t.cliente_id
       WHERE t.profesional_id = ? AND t.estado IN ('pendiente_de_pago','confirmado')
       ORDER BY t.inicio ASC`
    )
    .all(req.params.id);
  res.json(turnos);
});

// HU-10: listado de clientes atendidos por el profesional autenticado.
profesionalesRouter.get('/:id/clientes', requireAuth('profesional'), (req: AuthedRequest, res) => {
  if (!esPropioProfesional(req)) {
    return res.status(403).json({ error: 'Solo podés ver tus propios clientes' });
  }
  const clientes = db
    .prepare(
      `SELECT DISTINCT u.id, u.nombre, u.email FROM turno t
       JOIN usuario u ON u.id = t.cliente_id
       WHERE t.profesional_id = ?`
    )
    .all(req.params.id);
  res.json(clientes);
});
