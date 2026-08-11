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

// HU-20/HU-21 (Ficha de Paciente + historial enriquecido, 2026-08-11, ver
// mapa-pantallas.md §5.9/§5.9bis/§5.10 y modelo-datos.md §2quinquies): `:pacienteId` es el
// `cliente_id` (usuario.id) del paciente dentro de la cartera de este profesional — A PROPÓSITO
// no el `id` propio de la fila `paciente`. Motivo: GET /:id/clientes (más abajo) ya puede listar
// un cliente con turnos pero SIN fila `paciente` todavía (alta perezosa/automática, ver POST
// /turnos en turnos.ts) — si esta ruta pidiera `paciente.id`, Mobile no tendría con qué navegar
// a la ficha de ESE cliente hasta que la fila existiera. `cliente_id` en cambio siempre está
// disponible desde el listado (es el mismo `id` que ya devuelve GET /:id/clientes).
const profesionalPacienteParamsSchema = z.object({ id: uuidSchema, pacienteId: uuidSchema });

// Campos editables de la Ficha de Paciente (HU-20, Variante B aprobada por el CEO — ver
// mapa-pantallas.md §5.9bis, 2026-08-09). Todos requeridos (no `.optional()`, mismo criterio que
// `configuracionProfesionalSchema` de arriba) porque el PATCH hace de upsert de la fila
// `paciente` completa (ver comentario en el handler más abajo): al ser upsert, cada columna
// necesita siempre un valor a insertar si la fila es nueva, no alcanza con "actualizar solo lo
// que vino en el body". Mobile ya tiene el valor actual de cada campo desde el GET previo (o los
// defaults `null`/`true` si la ficha todavía no existe) y reenvía el formulario entero al
// guardar — un solo botón "Actualizar Paciente" (§5.9bis), no autoguardado campo por campo.
// Nullable salvo `activo` (D20/RN20: no tiene un valor "sin definir", default `true`). Sin
// CHECK/enum en `genero`/`contacto_emergencia_relacion` a propósito, mismo motivo que la columna
// (ver 001_init.sql): son contenido de UI (dropdowns), no reglas de negocio.
const fichaPacienteSchema = z.object({
  fecha_nacimiento: fechaIsoSchema.nullable(),
  genero: z.string().nullable(),
  direccion: z.string().nullable(),
  contacto_emergencia_nombre: z.string().nullable(),
  contacto_emergencia_telefono: z.string().nullable(),
  contacto_emergencia_relacion: z.string().nullable(),
  alergias: z.string().nullable(),
  notas_medicas_generales: z.string().nullable(),
  activo: z.boolean(),
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

// HU-10 + HU-19 (extendido 2026-08-11 — fuente de "Gestión de Pacientes", ver backlog.md HU-19
// y mapa-pantallas.md §5.8/§5.8bis): listado de clientes atendidos por el profesional
// autenticado. Sigue siendo la misma base ("todo cliente con al menos un turno con este
// profesional") — se agregan `activo`/`es_nuevo`/`es_reciente`/`ultima_visita` por fila más
// `telefono` a los datos básicos (columna nueva, ya confirmada en la fila de paciente contra
// capturas reales, §5.8bis).
//
// `activo`: LEFT JOIN a `paciente` (D20/RN20, manual, default `true` si la fila todavía no
// existe — la crea automáticamente POST /turnos desde el primer turno, ver turnos.ts, o el
// PATCH de /pacientes/:pacienteId más abajo si el profesional edita la ficha antes).
//
// `es_nuevo`/`es_reciente` (criterio exacto de Product Manager, backlog.md HU-19, 2026-08-10):
// dos métricas calculadas al consultar, independientes entre sí y del estado manual
// Activo/Inactivo, sin columna propia ni job periódico:
//   - es_nuevo: `paciente.creado_en` (fecha de alta en la cartera de ESTE profesional — al ser
//     automática desde POST /turnos, en la práctica es la fecha del primer turno) cae dentro de
//     los últimos 30 días. Un cliente sin fila `paciente` todavía (turno anterior a que este
//     mecanismo existiera, ficha nunca abierta) se considera `es_nuevo: false` — no hay forma de
//     conocer su fecha de alta real sin esa fila.
//   - es_reciente: al menos un turno "completado" en los últimos 30 días. `estado_turno` no
//     tiene un valor 'completado' propio (ver 001_init.sql / modelo-datos.md §2quinquies) — se
//     deriva, igual que recomienda DBA para el stat card "Completadas" de HU-21, como
//     `estado = 'confirmado' AND fin < now()`.
// 30 días hardcodeado (no config) — mismo criterio que dejó Product Manager: "sujeto a ajuste...
// si el uso real pide otro umbral, es un cambio de configuración, no de diseño".
//
// `ultima_visita`: MAX(fin) del último turno "completado" (misma derivación que es_reciente,
// sin la ventana de 30 días) — `null` si el cliente nunca tuvo un turno completado todavía.
//
// `LEFT JOIN LATERAL` (no un `LEFT JOIN` liso) a `paciente`: el UNIQUE real de esa tabla es
// (negocio_id, profesional_id, cliente_id), no (profesional_id, cliente_id) — un profesional que
// trabaja en 2+ negocios (N:M, modelo-datos.md §2ter) podría, en un caso límite, tener 2 fichas
// del mismo cliente (una por negocio). Esta lista no filtra por negocio (mismo criterio que ya
// tenía este endpoint antes de HU-19), así que el LATERAL con `ORDER BY creado_en DESC LIMIT 1`
// evita que ese caso límite duplique la fila del cliente en la respuesta — se muestra la ficha
// más reciente.
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
          `SELECT
             u.id, u.nombre, u.email, u.telefono,
             COALESCE(p.activo, true) AS activo,
             (p.creado_en IS NOT NULL AND p.creado_en >= now() - interval '30 days') AS es_nuevo,
             EXISTS (
               SELECT 1 FROM turno tr
               WHERE tr.profesional_id = $1 AND tr.cliente_id = u.id
                 AND tr.estado = 'confirmado' AND tr.fin < now() AND tr.fin >= now() - interval '30 days'
             ) AS es_reciente,
             (
               SELECT MAX(tr2.fin) FROM turno tr2
               WHERE tr2.profesional_id = $1 AND tr2.cliente_id = u.id
                 AND tr2.estado = 'confirmado' AND tr2.fin < now()
             ) AS ultima_visita
           FROM (SELECT DISTINCT cliente_id FROM turno WHERE profesional_id = $1) tc
           JOIN usuario u ON u.id = tc.cliente_id
           LEFT JOIN LATERAL (
             SELECT activo, creado_en FROM paciente
             WHERE profesional_id = $1 AND cliente_id = u.id
             ORDER BY creado_en DESC
             LIMIT 1
           ) p ON true
           ORDER BY u.nombre ASC`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(clientes);
  })
);

// HU-20 (Ficha de Paciente, Variante B aprobada por el CEO — mapa-pantallas.md §5.9bis):
// devuelve la ficha si ya existe, o valores por defecto (todo `null`, `activo: true`) si el
// cliente ya está en la cartera de este profesional (al menos un turno) pero todavía no tiene
// fila `paciente` — misma "alta perezosa" que POST /turnos resuelve de forma automática, sin
// bloquear la lectura mientras tanto.
//
// La verificación "es realmente mi cliente" (turno o paciente existente, ver el WHERE de abajo)
// no la puede hacer RLS sola: `usuario` NO tiene RLS habilitada (ver 001_init.sql — ninguna
// política ENABLE ROW LEVEL SECURITY la menciona), mismo motivo por el que GET
// /clientes/:id/historial (clientes.ts, HU-11) ya filtra "a mano" en el WHERE en vez de confiar
// en RLS de `usuario`. Sin este chequeo, este endpoint devolvería una ficha en blanco (con
// nombre/email/teléfono reales) para CUALQUIER UUID de usuario válido, sea o no cliente de este
// profesional.
profesionalesRouter.get(
  '/:id/pacientes/:pacienteId',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalPacienteParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver tus propios pacientes' });
    }

    const resultado = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             u.id, u.nombre, u.email, u.telefono,
             p.id AS paciente_id, p.fecha_nacimiento, p.genero, p.direccion,
             p.contacto_emergencia_nombre, p.contacto_emergencia_telefono,
             p.contacto_emergencia_relacion, p.alergias, p.notas_medicas_generales,
             COALESCE(p.activo, true) AS activo
           FROM usuario u
           LEFT JOIN LATERAL (
             SELECT id, fecha_nacimiento, genero, direccion, contacto_emergencia_nombre,
                    contacto_emergencia_telefono, contacto_emergencia_relacion, alergias,
                    notas_medicas_generales, activo, creado_en
             FROM paciente
             WHERE profesional_id = $2 AND cliente_id = u.id
             ORDER BY creado_en DESC
             LIMIT 1
           ) p ON true
           WHERE u.id = $1
             AND (
               p.id IS NOT NULL
               OR EXISTS (SELECT 1 FROM turno t WHERE t.profesional_id = $2 AND t.cliente_id = u.id)
             )`,
          [req.params.pacienteId, req.params.id]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    if (!resultado) {
      return res.status(404).json({ error: 'Paciente no encontrado en tu cartera' });
    }
    res.json(resultado);
  })
);

// PATCH — mismos campos editables que exige HU-20 (fecha_nacimiento, genero, direccion,
// contacto_emergencia_*, alergias, notas_medicas_generales, activo). NO se filtra por
// `negocio.es_rubro_salud` server-side (decisión explícita de Product Manager, 2026-08-10 —
// backlog.md HU-20: el condicional de mostrar/ocultar la sección "Salud" es de UI/Mobile; la API
// siempre acepta y devuelve estos campos, sin importar el rubro del negocio).
//
// Upsert (`INSERT ... ON CONFLICT ... DO UPDATE`) en vez de UPDATE liso: cubre tanto la primera
// edición (la fila `paciente` puede no existir todavía) como ediciones siguientes, con una sola
// sentencia.
//
// `negocio_id`: no viaja en la URL ni en el body de esta ficha (a diferencia de POST /turnos, en
// turnos.ts, donde sale de servicio.negocio_id). Se resuelve así: si ya existe una fila
// `paciente` para este (profesional, cliente) —en cualquier negocio, ver nota de LATERAL en GET
// /:id/clientes más arriba— se reusa SU negocio_id (para actualizar esa misma fila, nunca crear
// una segunda bajo un negocio distinto sin querer); si es la primera vez, se usa el negocio
// "vista activa" del JWT del profesional (`req.auth.negocio_id`, mismo dato que ya usa
// `withTransaction` en todo este archivo).
profesionalesRouter.patch(
  '/:id/pacientes/:pacienteId',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalPacienteParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés editar tus propios pacientes' });
    }
    const bodyParsed = fichaPacienteSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const {
      fecha_nacimiento,
      genero,
      direccion,
      contacto_emergencia_nombre,
      contacto_emergencia_telefono,
      contacto_emergencia_relacion,
      alergias,
      notas_medicas_generales,
      activo,
    } = bodyParsed.data;

    const resultado = await withTransaction(
      async (client) => {
        // Ficha existente (en cualquier negocio) para este profesional+cliente — reusa su
        // negocio_id si la hay (ver nota de diseño arriba). Su sola existencia ya prueba que
        // este cliente_id es legítimo (RLS de `paciente` no deja crear una fila ajena).
        const existenteResult = await client.query(
          `SELECT id, negocio_id FROM paciente WHERE profesional_id = $1 AND cliente_id = $2
           ORDER BY creado_en DESC LIMIT 1`,
          [req.params.id, req.params.pacienteId]
        );
        const existente = existenteResult.rows[0] as { id: string; negocio_id: string } | undefined;

        let negocioId = existente?.negocio_id;
        if (!negocioId) {
          // Ficha nueva — confirma que este cliente_id efectivamente tuvo trato con este
          // profesional (mismo criterio que el GET de arriba) antes de crear una fila de la nada
          // para cualquier UUID de usuario.
          const esClienteResult = await client.query(
            'SELECT 1 FROM turno WHERE profesional_id = $1 AND cliente_id = $2 LIMIT 1',
            [req.params.id, req.params.pacienteId]
          );
          if (!esClienteResult.rowCount) return { tipo: 'no_encontrado' as const };
          negocioId = req.auth!.negocio_id;
          if (!negocioId) return { tipo: 'sin_negocio' as const };
        }

        const ts = nowIso();
        const upsertResult = await client.query(
          `INSERT INTO paciente (
             negocio_id, profesional_id, cliente_id, fecha_nacimiento, genero, direccion,
             contacto_emergencia_nombre, contacto_emergencia_telefono, contacto_emergencia_relacion,
             alergias, notas_medicas_generales, activo, creado_en
           ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
           ON CONFLICT (negocio_id, profesional_id, cliente_id) DO UPDATE SET
             fecha_nacimiento = excluded.fecha_nacimiento,
             genero = excluded.genero,
             direccion = excluded.direccion,
             contacto_emergencia_nombre = excluded.contacto_emergencia_nombre,
             contacto_emergencia_telefono = excluded.contacto_emergencia_telefono,
             contacto_emergencia_relacion = excluded.contacto_emergencia_relacion,
             alergias = excluded.alergias,
             notas_medicas_generales = excluded.notas_medicas_generales,
             activo = excluded.activo,
             modificado_en = $14
           RETURNING id AS paciente_id, fecha_nacimiento, genero, direccion,
                     contacto_emergencia_nombre, contacto_emergencia_telefono,
                     contacto_emergencia_relacion, alergias, notas_medicas_generales, activo`,
          [
            negocioId,
            req.params.id,
            req.params.pacienteId,
            fecha_nacimiento,
            genero,
            direccion,
            contacto_emergencia_nombre,
            contacto_emergencia_telefono,
            contacto_emergencia_relacion,
            alergias,
            notas_medicas_generales,
            activo,
            ts,
            ts,
          ]
        );

        const clienteResult = await client.query(
          'SELECT id, nombre, email, telefono FROM usuario WHERE id = $1',
          [req.params.pacienteId]
        );

        return { tipo: 'ok' as const, paciente: upsertResult.rows[0], cliente: clienteResult.rows[0] };
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Paciente no encontrado en tu cartera' });
      case 'sin_negocio':
        return res.status(409).json({
          error:
            'No se pudo determinar el negocio para esta ficha nueva — volvé a iniciar sesión e intentá de nuevo.',
        });
      case 'ok':
        return res.json({
          id: resultado.cliente.id,
          nombre: resultado.cliente.nombre,
          email: resultado.cliente.email,
          telefono: resultado.cliente.telefono,
          paciente_id: resultado.paciente.paciente_id,
          fecha_nacimiento: resultado.paciente.fecha_nacimiento,
          genero: resultado.paciente.genero,
          direccion: resultado.paciente.direccion,
          contacto_emergencia_nombre: resultado.paciente.contacto_emergencia_nombre,
          contacto_emergencia_telefono: resultado.paciente.contacto_emergencia_telefono,
          contacto_emergencia_relacion: resultado.paciente.contacto_emergencia_relacion,
          alergias: resultado.paciente.alergias,
          notas_medicas_generales: resultado.paciente.notas_medicas_generales,
          activo: resultado.paciente.activo,
        });
    }
  })
);

// HU-11 + HU-21 (Historial enriquecido, ver mapa-pantallas.md §5.10): mismo criterio de
// privacidad que GET /clientes/:id/historial (HU-11 original, clientes.ts, que queda sin tocar)
// — SOLO turnos de ESTE profesional con este cliente (RN7/D3), nunca los de otro profesional del
// mismo negocio aunque haya atendido al mismo cliente. Vive acá (no en clientes.ts) para
// mantener las 3 rutas nuevas de esta tanda juntas bajo el mismo prefijo /profesionales/:id.
profesionalesRouter.get(
  '/:id/pacientes/:pacienteId/historial',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalPacienteParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver el historial de tus propios pacientes' });
    }

    const resultado = await withTransaction(
      async (client) => {
        // Mismo chequeo de legitimidad que GET /:id/pacientes/:pacienteId (ver ese comentario):
        // `usuario` no tiene RLS, así que sin esto cualquier UUID de usuario devolvería un
        // historial "vacío pero válido" (200 con nombre/email reales) en vez de 404.
        const clienteResult = await client.query(
          `SELECT u.id, u.nombre, u.email, u.telefono
           FROM usuario u
           WHERE u.id = $1
             AND (
               EXISTS (SELECT 1 FROM turno t WHERE t.profesional_id = $2 AND t.cliente_id = u.id)
               OR EXISTS (SELECT 1 FROM paciente p WHERE p.profesional_id = $2 AND p.cliente_id = u.id)
             )`,
          [req.params.pacienteId, req.params.id]
        );
        const cliente = clienteResult.rows[0];
        if (!cliente) return { tipo: 'no_encontrado' as const };

        // Campos por turno = exactamente los que pide HU-21. `fecha`/`hora` viajan como
        // `inicio`/`fin` ISO — mismo criterio que el resto de esta API (nunca se parte
        // fecha/hora server-side, ver GET /:id/turnos más arriba). `estado_pago` es el MISMO
        // valor que `estado` (criterio de aceptación de HU-21: "reutiliza el estado ya definido
        // en HU-09b [pendiente_de_pago/confirmado]... no introduce un estado de pago nuevo") —
        // se expone además con este nombre explícito para que Mobile no tenga que reinterpretar
        // `estado` con dos significados distintos sin una pista en el propio payload.
        // `completado` es un booleano derivado de conveniencia (misma fórmula que "Completadas"
        // del resumen, ver abajo) para que Mobile no reimplemente la derivación (`estado_turno`
        // no tiene un valor 'completado' propio, ver 001_init.sql / modelo-datos.md §2quinquies).
        // Cast directo a ::int (sin round()) para duracion_min: el cast de double precision a
        // integer en Postgres redondea al entero más cercano (no trunca) — alcanza, y evita
        // depender de la firma exacta de round(double precision). En la práctica fin-inicio de
        // este dominio siempre cae en un múltiplo exacto de minutos (inicio/fin se calculan
        // siempre en pasos de minutos enteros, ver dominio/disponibilidad.ts), así que no hay
        // parte fraccionaria de la que preocuparse de todos modos.
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
           WHERE t.cliente_id = $1 AND t.profesional_id = $2
           ORDER BY t.inicio DESC`,
          [req.params.pacienteId, req.params.id]
        );

        // Tratamientos/notas médicas (HU-21/D8/RN13): JOIN a `paciente` filtrado por
        // (profesional_id, cliente_id) en vez de un `paciente_id` fijo — mismo motivo que el
        // LATERAL de GET /:id/clientes más arriba (caso límite: profesional en 2+ negocios podría
        // tener 2 fichas del mismo cliente). A diferencia de la ficha única de arriba, acá SUMAR
        // sobre ambas es lo correcto (no perder tratamientos/notas cargados bajo cualquiera de
        // las 2 fichas) — no hace falta desambiguar a una sola.
        const tratamientosResult = await client.query(
          `SELECT tr.id, tr.descripcion, tr.fecha_inicio, tr.fecha_fin
           FROM tratamiento tr
           JOIN paciente pa ON pa.id = tr.paciente_id
           WHERE pa.profesional_id = $2 AND pa.cliente_id = $1
           ORDER BY tr.fecha_inicio DESC`,
          [req.params.pacienteId, req.params.id]
        );

        const notasResult = await client.query(
          `SELECT nm.id, nm.fecha, nm.texto
           FROM nota_medica nm
           JOIN paciente pa ON pa.id = nm.paciente_id
           WHERE pa.profesional_id = $2 AND pa.cliente_id = $1
           ORDER BY nm.fecha DESC`,
          [req.params.pacienteId, req.params.id]
        );

        // "Completadas" reusa el `completado` ya calculado por fila en vez de una 2da query de
        // COUNT (recomendación de DBA en 001_init.sql / modelo-datos.md §2quinquies) — mismo
        // resultado, un round-trip menos.
        const citasCompletadas = turnosResult.rows.filter((t: any) => t.completado).length;

        return {
          tipo: 'ok' as const,
          paciente: cliente,
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
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Paciente no encontrado en tu cartera' });
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
