import { Router } from 'express';
import { z } from 'zod';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { calcularSlotsDisponibles, inicioDelDiaLocal } from '../dominio/disponibilidad';
import {
  uuidSchema,
  fechaIsoSchema,
  diaSemanaSchema,
  horaSchema,
  montoPositivoSchema,
  respuestaValidacionFallida,
} from '../dominio/validacion';
import { LimitePlanGratisError, cuerpoLimitePlanAlcanzado, exigirLimiteTurnosConfirmadosDelMes } from '../dominio/suscripciones';

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

// Configuración de Pagos (Precios y Señas, mapa-pantallas.md §5.11bis "Panel Profesional >
// Configuración de Pagos") — `:servicioId` para editar una asociación profesional↔servicio YA
// EXISTENTE (ver PATCH /:id/servicios/:servicioId más abajo). Mismo criterio de nombrar el 2do
// parámetro por lo que representa (no un genérico `:subId`) que `profesionalPacienteParamsSchema`
// de arriba.
const profesionalServicioParamsSchema = z.object({ id: uuidSchema, servicioId: uuidSchema });

// Body de PATCH /:id/servicios/:servicioId — mismos 2 campos que ya acepta `asociarServicioSchema`
// (requiere_sena/monto_sena), pero acá AMBOS requeridos (no `.optional()`): a diferencia de POST
// /:id/servicios (que da de alta la asociación y puede razonablemente arrancar solo con
// `requiere_sena` en su default `false`), este PATCH edita una fila que ya existe — Mobile ya
// tiene los 2 valores actuales desde GET /:id/servicios (más abajo) para reenviar el formulario
// completo, mismo criterio que `fichaPacienteSchema`/`configuracionProfesionalSchema`.
const actualizarSenaSchema = z.object({
  requiere_sena: z.boolean(),
  monto_sena: montoPositivoSchema.nullable(),
});

// Reportes y Estadísticas (HU-28/E10) — filtros opcionales de GET /:id/reportes más abajo:
// período (rango de fechas sobre `turno.inicio`) y servicio. Los 3 son independientes; sin
// ninguno, el reporte cubre toda la agenda histórica del profesional.
const reportesQuerySchema = z.object({
  desde: fechaIsoSchema.optional(),
  hasta: fechaIsoSchema.optional(),
  servicio_id: uuidSchema.optional(),
});

// HU-23 (v1, P1 — backlog.md, "Ampliación del backlog"): carga manual de un turno por el propio
// profesional (ej. el paciente llamó por teléfono o se presentó sin reserva previa) — body de
// `POST /:id/turnos` más abajo.
//
// `paciente_id`: MISMA convención que `profesionalPacienteParamsSchema` de arriba — el
// `usuario.id` del paciente, no `paciente.id` (Mobile ya lo tiene de `GET /:id/clientes`, que
// expone `u.id` como `id` de cada fila, sin depender de que la fila `paciente` exista todavía).
//
// `cobrar_sena` (RN10, "Seña resuelta (CEO, 2026-08-06)" en backlog.md): la ÚNICA regla que esta
// carga manual puede saltear, y solo si el profesional lo decide explícitamente en cada request
// — overridea `profesional_servicio.requiere_sena` SOLO para este turno puntual, sin tocar la
// configuración general del servicio (que sigue aplicando sin cambios en la autoreserva del
// cliente, CU4). Requerido, no `.optional()` — mismo criterio ya usado en este archivo para
// decisiones que el wireframe pide como control explícito (ver `actualizarSenaSchema`,
// `fichaPacienteSchema.activo`): el propio criterio de aceptación de la HU pide "una opción
// explícita... no un valor implícito", así que la API tampoco asume un default silencioso.
//
// Deliberadamente NO incluye "notas" (mencionado en la narrativa de la historia, "eligiendo
// servicio, fecha, hora y agregando notas"): `turno` no tiene ninguna columna de texto libre para
// esto y los criterios de aceptación cerrados de la HU no lo repiten como requisito — ver el
// resumen de este endpoint para el Director General IA/DBA antes de agregar una columna nueva.
const profesionalTurnoManualSchema = z.object({
  paciente_id: uuidSchema,
  servicio_id: uuidSchema,
  inicio: fechaIsoSchema,
  cobrar_sena: z.boolean(),
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

// HU-06/HU-27: agenda del profesional autenticado (turnos propios, para la pantalla de Agenda y
// las métricas del resumen del día del Dashboard). Acotada al negocio_id "vista activa" del JWT
// (ver el chequeo y el filtro más abajo) — un profesional en 2+ negocios (N:M,
// negocio_profesional) puede tener turnos de varios a la vez, y HU-27 pide explícitamente que
// estas métricas se calculen "sobre los turnos... dentro del negocio actualmente seleccionado",
// no mezclados de todos los negocios donde trabaja (bug encontrado por Mobile haciendo HU-27:
// esta query filtraba antes solo por profesional_id, sin negocio_id).
profesionalesRouter.get(
  '/:id/turnos',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver tu propia agenda' });
    }
    // Sin negocio_id en el JWT (0 o 2+ negocios y todavía no eligió ninguno vía "cambiar de
    // vista", ver auth.ts POST /entrar-a-negocio) no hay con qué acotar la agenda. Mobile ya evita
    // esta llamada en ese caso (dashboard_screen.dart, _SinNegocioView, que muestra su propio
    // estado "sin negocio" en vez de pedir la agenda), pero el endpoint responde 400 igual si lo
    // invocan así de todos modos — nunca 200 con una mezcla de negocios ni adivinando cuál mostrar.
    if (!req.auth!.negocio_id) {
      return res.status(400).json({ error: 'Elegí un negocio primero para ver tu agenda' });
    }
    const turnos = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT t.id, t.inicio, t.fin, t.estado, s.nombre AS servicio, u.nombre AS cliente
           FROM turno t
           JOIN servicio s ON s.id = t.servicio_id
           JOIN usuario u ON u.id = t.cliente_id
           WHERE t.profesional_id = $1 AND t.negocio_id = $2
             AND t.estado IN ('pendiente_de_pago','confirmado')
           ORDER BY t.inicio ASC`,
          [req.params.id, req.auth!.negocio_id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(turnos);
  })
);

// HU-23 (v1, P1 — backlog.md, "Ampliación del backlog"): el profesional carga un turno
// directamente para un paciente de su cartera (ej. llamó por teléfono, se presentó sin reserva
// previa) — sin pasar por el flujo de autoreserva del cliente (CU4/`POST /turnos` en turnos.ts).
//
// Reusa el MISMO motor de disponibilidad y la MISMA garantía anti-doble-reserva que
// `POST /turnos` (turnos.ts, HU-09/HU-09b): la grilla de 2 pasadas de `calcularSlotsDisponibles`
// para RN1 (alineado a un slot publicado) + RN2 (libre), y el índice único parcial
// `uq_turno_slot_activo` como última línea de defensa contra una carrera entre 2 requests. HU-23
// pide expresamente "se aplican las mismas reglas de no solapamiento y duración por servicio que
// en la reserva del cliente (RN1, RN2, RN3)... no es un camino que evite esas garantías" — la
// ÚNICA excepción autorizada es la seña (RN10, ver `profesionalTurnoManualSchema` más arriba). La
// lógica de validación (servicio/membresía/RN4/grilla) se duplica acá en vez de extraerse a un
// helper compartido con turnos.ts a propósito: son ~30 líneas de glue code sencillo alrededor de
// la MISMA función compartida (`calcularSlotsDisponibles`, que es donde vive la garantía real) —
// no se justifica tocar el endpoint `POST /turnos` ya aprobado/probado (con su propio historial
// de fixes de QA/Security) solo para deduplicar ese glue.
//
// A diferencia de `POST /turnos`, acá el actor autenticado YA ES el profesional del turno (no un
// cliente reservando con un tercero) — simplifica el manejo de identidad RLS:
//   - No hace falta resolver `profesional.usuario_id` por separado para notificacion/paciente: es
//     literalmente `req.auth!.sub` (el propio profesional autenticado).
//   - No hace falta ningún cambio de identidad a mitad de transacción (a diferencia de
//     `POST /turnos`, que sí lo necesita para el alta de `paciente` — ver ese comentario extenso
//     en turnos.ts): acá `withTransaction` ya corre con `usuarioId: req.auth!.sub` = el
//     profesional dueño de la fila `paciente` (`paciente_acceso_propio_profesional` exige
//     exactamente esa identidad), del turno (`turno_acceso_negocio_o_cliente` lo admite vía el
//     3er OR, "staff activo del negocio") y de la notificación
//     (`notificacion_insert_evento_turno` lo admite por el mismo motivo) — las 3 sentencias de la
//     transacción pasan sus policies con la MISMA identidad, sin excepción.
//
// Contrato: POST /profesionales/:id/turnos, body { paciente_id: uuid, servicio_id: uuid,
// inicio: ISO-8601, cobrar_sena: boolean } -> 201 { id, paciente_id, servicio_id, inicio, fin,
// estado, requiere_pago, monto_sena } | 400 datos inválidos, o `inicio` no alineado a la grilla
// de disponibilidad publicada (RN1) | 402 (HU-29) `cobrar_sena=false` y el negocio (plan gratis)
// ya alcanzó el límite de 60 turnos confirmados este mes — ver dominio/suscripciones.ts | 403 rol
// distinto de profesional o `:id` ajeno | 404 paciente/servicio inexistente, servicio de un
// negocio donde no trabajás, o todavía no asociaste ese servicio a tu agenda (RN4) | 409 el
// horario ya está ocupado por otro turno/excepción (RN2).
profesionalesRouter.post(
  '/:id/turnos',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés cargar turnos en tu propia agenda' });
    }
    const bodyParsed = profesionalTurnoManualSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { paciente_id, servicio_id, inicio, cobrar_sena } = bodyParsed.data;
    const profesionalId = req.params.id;
    const inicioDate = new Date(inicio);

    // El paciente tiene que ser una cuenta `usuario` real con rol 'cliente' (mismo tipo de dato
    // que `turno.cliente_id` siempre asumió) — se acepta cualquier cliente existente, no solo los
    // que ya tienen fila `paciente`/turno previo con este profesional (mismo criterio que
    // `POST /turnos`, que también permite reservar con un profesional nunca antes visitado): esta
    // ruta cubre igual el caso "primer turno de un paciente nuevo para mí" — la fila `paciente` se
    // da de alta automáticamente más abajo. 404 uniforme si no existe o si el id corresponde a
    // otro rol (profesional/administrador), para no filtrar esa distinción a quien llama.
    const pacienteResult = await pool.query('SELECT id FROM usuario WHERE id = $1 AND rol = $2', [
      paciente_id,
      'cliente',
    ]);
    if (!pacienteResult.rowCount) {
      return res.status(404).json({ error: 'Paciente no encontrado' });
    }

    // Mismos 3 chequeos de integridad que `POST /turnos` (turnos.ts) — ver esos comentarios: el
    // servicio existe, el profesional pertenece al negocio de ese servicio (N:M,
    // modelo-datos.md §2ter) y el profesional asoció explícitamente ese servicio (RN4) — de paso
    // trae `requiere_sena`/`monto_sena`, el default que `cobrar_sena` puede overridear (RN10).
    const servicioResult = await pool.query('SELECT negocio_id, duracion_min FROM servicio WHERE id = $1', [
      servicio_id,
    ]);
    const servicio = servicioResult.rows[0] as { negocio_id: string; duracion_min: number } | undefined;
    if (!servicio) {
      return res.status(404).json({ error: 'Servicio no encontrado' });
    }

    const esMiembroActivoResult = await pool.query(
      'SELECT 1 FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2 AND activo = true',
      [servicio.negocio_id, profesionalId]
    );
    if (!esMiembroActivoResult.rowCount) {
      return res.status(404).json({ error: 'Este servicio no pertenece a un negocio en el que trabajás' });
    }

    const relacionResult = await pool.query(
      'SELECT requiere_sena, monto_sena FROM profesional_servicio WHERE profesional_id = $1 AND servicio_id = $2',
      [profesionalId, servicio_id]
    );
    const relacion = relacionResult.rows[0] as
      | { requiere_sena: boolean; monto_sena: number | null }
      | undefined;
    if (!relacion) {
      return res.status(404).json({ error: 'Todavía no asociaste este servicio a tu agenda (RN4)' });
    }

    // RN1/RN2 — misma grilla de 2 pasadas que `POST /turnos` (turnos.ts, ver el comentario
    // extenso ahí): 1) `inicio` alineado a un slot publicado (`ignorarOcupacion: true`) -> si no,
    // 400; 2) ese slot efectivamente libre -> si no, 409. HU-23 pide expresamente las mismas
    // reglas RN1-RN3, así que esta carga manual no es un atajo para saltarse la grilla publicada.
    const inicioIso = inicioDate.toISOString();
    const ventanaDelDia = { desde: inicioDelDiaLocal(inicioDate), dias: 1, maxSlots: 500 };

    const grilla = await calcularSlotsDisponibles(pool, profesionalId, servicio_id, {
      ...ventanaDelDia,
      ignorarOcupacion: true,
    });
    const alineadoAGrilla = grilla?.slots.includes(inicioIso) ?? false;
    if (!alineadoAGrilla) {
      return res.status(400).json({
        error: 'El horario solicitado no corresponde a un slot de disponibilidad publicado por vos (RN1).',
      });
    }

    const slotsLibres = await calcularSlotsDisponibles(pool, profesionalId, servicio_id, ventanaDelDia);
    const estaLibre = slotsLibres?.slots.includes(inicioIso) ?? false;
    if (!estaLibre) {
      return res.status(409).json({
        error: 'Ese horario ya no está disponible — se solapa con otro turno o excepción tuyo (RN2).',
      });
    }

    // RN3/D10: misma duración ya validada por `estaLibre` arriba — ver el comentario largo en
    // turnos.ts (POST /) sobre por qué se reusa `slotsLibres.duracionMin` en vez de recalcular a
    // partir de `servicio.duracion_min` (evita una 2da fuente de verdad que se desincronice del
    // slot que realmente se validó).
    const finDate = new Date(inicioDate.getTime() + slotsLibres!.duracionMin * 60_000);

    // RN10 (HU-23, "Seña resuelta" en backlog.md) — la única regla que esta carga manual puede
    // saltear, y solo porque el profesional lo decidió explícitamente en este request:
    // `cobrar_sena` gana siempre sobre `relacion.requiere_sena`, tanto para prender la seña donde
    // el servicio no la pide como (el caso que motiva la historia) para apagarla donde sí la pide.
    const cobrarSena = cobrar_sena;
    const estadoInicial = cobrarSena ? 'pendiente_de_pago' : 'confirmado';
    const turnoId = uuid();
    const ts = nowIso();

    try {
      await withTransaction(
        async (client) => {
          // HU-29 (Turnario Pro) — el chequeo del límite "60 turnos confirmados/mes" tiene que
          // correr ACÁ, antes del INSERT: este camino (`cobrar_sena=false`) deja nacer el turno
          // DIRECTO en 'confirmado' — no hay ningún punto posterior en el que este turno puntual
          // cambie de estado, así que este es el ÚNICO momento en que se puede bloquear antes de
          // que "cuente". (El otro camino de este mismo endpoint, `cobrar_sena=true`, nace
          // 'pendiente_de_pago' y el chequeo se difiere — ver dominio/suscripciones.ts y
          // turnos.ts/POST / para el resto de los caminos documentados. Ese camino que faltaba
          // (2026-08-17) es `POST /webhooks/mercadopago` (src/routes/webhooks.ts) — usa la
          // variante que DEVUELVE resultado, no la que lanza; ver el comentario ahí para el
          // porqué.) Se salta completo si el negocio tiene Turnario Pro activo.
          if (estadoInicial === 'confirmado') {
            await exigirLimiteTurnosConfirmadosDelMes(client, servicio.negocio_id, inicioDate);
          }

          await client.query(
            `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              turnoId,
              servicio.negocio_id,
              profesionalId,
              servicio_id,
              paciente_id,
              inicioDate.toISOString(),
              finDate.toISOString(),
              estadoInicial,
              ts,
            ]
          );

          if (cobrarSena) {
            await client.query(
              'INSERT INTO pago (id, turno_id, monto, estado, creado_en) VALUES ($1, $2, $3, $4, $5)',
              [uuid(), turnoId, relacion.monto_sena ?? 0, 'pendiente', ts]
            );
          }

          // HU-25: mismo criterio de "bandeja" que los 3 INSERT ya existentes en turnos.ts, pero
          // acá el destinatario natural es el PACIENTE, no el profesional — es quien está
          // ejecutando la acción, notificarse a sí mismo no aporta nada y, peor, el mensaje para
          // destinatario≠cliente ("<nombre> confirmó su turno...") describiría mal lo que pasó:
          // fue el profesional quien lo cargó, no el cliente. Es el primer productor real del
          // lado `destinatarioEsCliente: true` de `armarMensajeNotificacion`
          // (dominio/notificaciones.ts) — esa rama ya estaba prevista en el helper ("Hoy ningún
          // productor real genera este caso") sin ningún INSERT que la alimentara todavía; el
          // mensaje en sí no se arma acá (se deriva en cada GET /notificaciones, ver ese archivo),
          // solo el evento con su destinatario correcto.
          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, destinatario_usuario_id, creado_en) VALUES ($1, $2, $3, $4, $5)',
            [uuid(), turnoId, 'confirmacion', paciente_id, ts]
          );

          // Alta automática de `paciente` — mismo mecanismo exacto que `POST /turnos` (turnos.ts,
          // ver ese comentario extenso), pero sin el cambio de identidad RLS que esa ruta
          // necesita: acá `app.usuario_id` YA es el profesional (ver comentario de arriba), la
          // misma identidad que exige `paciente_acceso_propio_profesional`.
          await client.query(
            `INSERT INTO paciente (negocio_id, profesional_id, cliente_id, creado_en)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (negocio_id, profesional_id, cliente_id) DO NOTHING`,
            [servicio.negocio_id, profesionalId, paciente_id, ts]
          );
        },
        { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
      );
    } catch (err: any) {
      // HU-29 — ver el comentario junto a `exigirLimiteTurnosConfirmadosDelMes` más arriba y
      // `cuerpoLimitePlanAlcanzado` (dominio/suscripciones.ts) para el razonamiento completo del
      // 402 (en vez de 403): la identidad/rol de quien llama es correcta, lo que falla es el plan.
      if (err instanceof LimitePlanGratisError) {
        return res.status(402).json(cuerpoLimitePlanAlcanzado(err.message));
      }
      // Mismo código 23505 (unique_violation de `uq_turno_slot_activo`) que `POST /turnos` — ver
      // ese comentario: última línea de defensa si 2 requests corren la misma ventana en paralelo
      // (ej. el profesional carga un turno a mano justo cuando el cliente reserva ese mismo slot).
      if (err?.code === '23505') {
        return res.status(409).json({
          error: 'Ese horario ya no está disponible — se solapa con otro turno tuyo (RN2).',
        });
      }
      throw err;
    }

    res.status(201).json({
      id: turnoId,
      paciente_id,
      servicio_id,
      inicio: inicioDate.toISOString(),
      fin: finDate.toISOString(),
      estado: estadoInicial,
      requiere_pago: cobrarSena,
      monto_sena: relacion.monto_sena ?? null,
    });
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

// ============================================================================
// Configuración de Pagos (Precios y Señas) — mapa-pantallas.md §5.11bis, "Panel Profesional >
// Configuración de Pagos" (ícono magenta, HU-30 en el wireframe stub, pero el contenido real es
// D2/RN10: la seña ya se configura por asociación profesional↔servicio, HU-04b — esto es la
// vista de EDICIÓN posterior, no una historia numerada propia). Dos rutas: GET (listar con la
// seña actual) + PATCH (editar una asociación puntual, sin recrearla). El alta de la primera
// asociación sigue siendo POST /:id/servicios, más arriba en este archivo — no se toca.
// ============================================================================

// Contrato: GET /profesionales/:id/servicios -> 200 [{ servicio_id, nombre, duracion_min,
// precio_referencia, negocio_id, negocio_nombre, requiere_sena, monto_sena }, ...] | 403 rol
// distinto de profesional o `:id` ajeno.
//
// Lista TODOS los servicios que este profesional ya asoció (fila en `profesional_servicio`, la
// crea HU-04b vía POST /:id/servicios) junto con su configuración de seña actual, para que
// Mobile tenga qué mostrar antes de editar con el PATCH de abajo. Privado
// (`requireAuth('profesional')` + `esPropioProfesional`) — a diferencia de
// GET /negocios/:id/servicios (catálogo público del servicio de un negocio), esto expone
// `requiere_sena`/`monto_sena`, información de cobro sin motivo para ser pública.
//
// Sin filtrar por negocio_id (mismo criterio ya documentado en GET /:id/clientes, más arriba en
// este archivo: un profesional puede pertenecer a 2+ negocios, y esta lista tampoco filtra por la
// "vista activa" del JWT) — a diferencia de GET /:id/turnos y GET /:id/reportes (ver esos
// comentarios, HU-27/HU-28), que sí filtran por negocio_id. Se agrega igual `negocio_id`/
// `negocio_nombre` por fila (vía JOIN) para que Mobile pueda agrupar/etiquetar si hace falta.
profesionalesRouter.get(
  '/:id/servicios',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver tus propios servicios' });
    }
    const servicios = await withTransaction(
      async (client) => {
        const result = await client.query(
          `SELECT
             s.id AS servicio_id, s.nombre, s.duracion_min, s.precio_referencia,
             s.negocio_id, n.nombre AS negocio_nombre,
             ps.requiere_sena, ps.monto_sena
           FROM profesional_servicio ps
           JOIN servicio s ON s.id = ps.servicio_id
           JOIN negocio n ON n.id = s.negocio_id
           WHERE ps.profesional_id = $1 AND s.eliminado_en IS NULL
           ORDER BY n.nombre ASC, s.nombre ASC`,
          [req.params.id]
        );
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(servicios);
  })
);

// Contrato: PATCH /profesionales/:id/servicios/:servicioId, body { requiere_sena: boolean,
// monto_sena: number | null } -> 200 { servicio_id, requiere_sena, monto_sena } | 400 datos
// inválidos | 403 rol distinto de profesional o `:id` ajeno | 404 no existe asociación previa
// para ese (profesional, servicio).
//
// Edita requiere_sena/monto_sena de una asociación YA EXISTENTE, sin recrearla — distinto de
// POST /:id/servicios de arriba: ese endpoint da de alta (y, de yapa, ya es upsert — `ON
// CONFLICT ... DO UPDATE` — así que técnicamente Mobile podría reusarlo también para editar),
// pero re-verifica en cada llamada que el profesional sea miembro activo del negocio del
// servicio (2 SELECT adicionales) — innecesario para "ya existe la fila, solo cambio la seña", y
// semánticamente un alta (201, verbo POST) no comunica bien una edición. Este PATCH es más
// angosto a propósito: si la fila (profesional_id, servicio_id) no existe todavía, responde 404
// y NO crea nada — usar POST /:id/servicios para la primera asociación.
profesionalesRouter.patch(
  '/:id/servicios/:servicioId',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalServicioParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés configurar tus propios servicios' });
    }
    const bodyParsed = actualizarSenaSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { requiere_sena, monto_sena } = bodyParsed.data;

    const servicio = await withTransaction(
      async (client) => {
        const result = await client.query(
          `UPDATE profesional_servicio SET requiere_sena = $1, monto_sena = $2
           WHERE profesional_id = $3 AND servicio_id = $4
           RETURNING servicio_id, requiere_sena, monto_sena`,
          [requiere_sena, monto_sena, req.params.id, req.params.servicioId]
        );
        return result.rows[0];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    if (!servicio) {
      return res.status(404).json({
        error: 'Todavía no asociaste este servicio — usá POST /profesionales/:id/servicios primero',
      });
    }
    res.json(servicio);
  })
);

// ============================================================================
// Reportes y Estadísticas (HU-28/E10) — v1 SIMPLIFICADA, lado Profesional ÚNICAMENTE en este
// ciclo. mapa-pantallas.md §7 marca esta pantalla como "Stub de navegación — contenido a diseñar
// cuando Product Manager cierre alcance", así que este endpoint se diseña directamente a partir
// del criterio de aceptación ya cerrado de HU-28 (02-backlog/backlog.md), no de un wireframe.
// ============================================================================

// Contrato: GET /profesionales/:id/reportes?desde=<ISO>&hasta=<ISO>&servicio_id=<uuid> (los 3
// query params son opcionales e independientes) -> 200 { desde, hasta, servicio_id,
// turnos_totales, turnos_completados, turnos_cancelados, monto_facturado } | 400 query inválida o
// todavía no elegiste un negocio ("vista activa", ver GET /:id/turnos más arriba) | 403 rol
// distinto de profesional o `:id` ajeno.
//
// Devuelve las 4 métricas básicas que pide HU-28 ("turnos totales, turnos completados, turnos
// cancelados, y monto facturado"), filtrables por período y servicio.
//
// Qué queda AFUERA de esta v1, a propósito (documentado, no un olvido):
//   - Vista de negocio/administrador (todos los profesionales a la vez): HU-28 la pide, pero la
//     consigna de este ciclo la difiere explícitamente. Cuando se construya, es un endpoint
//     nuevo (ej. GET /negocios/:id/reportes), no una extensión de este.
//   - Filtro "por profesional": no aplica ACÁ porque este endpoint ya está scopeado a un único
//     profesional por diseño (`:id` + `esPropioProfesional`, RN7/D3) — ese filtro cobra sentido
//     recién en la futura vista de negocio.
//   - Exportar (CSV/PDF/etc.): HU-28 lo marca explícitamente "fuera de este alcance básico —
//     candidato a una iteración posterior".
//   - Métricas avanzadas (ocupación, ausentismo, pacientes nuevos vs. recurrentes): HU-28 las
//     marca explícitamente fuera de este alcance básico también.
//
// Definiciones elegidas acá (no explícitas letra por letra en HU-28 — mismo criterio de "v1
// simplificada, documentada explícitamente" ya usado en Gestión de Horarios):
//   - `turnos_completados` / "monto facturado": reusa EXACTAMENTE la misma derivación que ya
//     recomienda DBA para "Completadas" en HU-21 (ver 001_init.sql, comentario junto a
//     `nota_medica`) y que ya implementa GET /:id/pacientes/:pacienteId/historial más arriba:
//     `estado = 'confirmado' AND fin < now()`. `estado_turno` no tiene un valor 'completado'
//     propio (mismo gap ya documentado por DBA) — esta es la mejor aproximación disponible sin
//     rediseñar la máquina de estados de turno, fuera de alcance de este ciclo.
//   - "monto facturado" = suma de `servicio.precio_referencia` (el precio del SERVICIO, tal cual
//     dice HU-28 — "suma del precio de servicio de los turnos completados/pagados") de esos
//     turnos completados — NO la seña (`pago.monto`/`profesional_servicio.monto_sena`), que en la
//     práctica es un valor más chico: HU-28 pide explícitamente el precio del servicio, no lo
//     efectivamente cobrado de seña.
//   - `turnos_totales` EXCLUYE `estado = 'reprogramado'` (decisión propia, no dicha explícitamente
//     en HU-28): reprogramar (HU-13) deja la fila vieja en ese estado y crea una fila NUEVA con
//     el horario nuevo — contar ambas duplicaría la misma cita real. Sumando
//     pendiente_de_pago + confirmado + cancelado ya se obtiene la cuenta real de citas distintas
//     del período.
//   - `turnos_cancelados`: `estado = 'cancelado'` sin más condición (incluye tanto cancelaciones
//     manuales, HU-12, como expiraciones automáticas por falta de pago,
//     src/jobs/expirarPagosPendientes.ts — ambas dejan el turno en el mismo estado; no hay forma
//     de distinguirlas hoy sin un campo nuevo, fuera de alcance).
//
// Período: filtra por `turno.inicio` (fecha del turno), no por `creado_en` (fecha de la
// reserva) — "reporte de mi agenda de tal período" se entiende naturalmente sobre cuándo
// ocurrió/ocurre la cita, no sobre cuándo se reservó. Ambos extremos se normalizan con
// `new Date(x).toISOString()` antes de llegar a la query (mismo criterio que `POST /turnos` en
// turnos.ts) en vez de pasar el string crudo ya validado por `fechaIsoSchema` — evita cualquier
// divergencia entre el parser (muy permisivo) de `Date` de JS y el de Postgres.
profesionalesRouter.get(
  '/:id/reportes',
  requireAuth('profesional'),
  asyncHandler(async (req: AuthedRequest, res) => {
    const paramsParsed = profesionalIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);
    if (!esPropioProfesional(req)) {
      return res.status(403).json({ error: 'Solo podés ver el reporte de tu propia agenda' });
    }
    // HU-27/HU-28: mismo criterio (y mismo bug corregido, ver GET /:id/turnos más arriba) — un
    // profesional en 2+ negocios ve el reporte acotado al negocio que tiene seleccionado como
    // "vista activa", no su agenda combinada de todos los negocios donde trabaja. Mismo 400 si
    // todavía no eligió ninguno.
    if (!req.auth!.negocio_id) {
      return res.status(400).json({ error: 'Elegí un negocio primero para ver el reporte' });
    }
    const queryParsed = reportesQuerySchema.safeParse(req.query);
    if (!queryParsed.success) return respuestaValidacionFallida(res, queryParsed.error);
    const { desde, hasta, servicio_id } = queryParsed.data;
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
           WHERE t.profesional_id = $1
             AND t.negocio_id = $5
             AND ($2::timestamptz IS NULL OR t.inicio >= $2)
             AND ($3::timestamptz IS NULL OR t.inicio <= $3)
             AND ($4::uuid IS NULL OR t.servicio_id = $4)`,
          [req.params.id, desdeIso, hastaIso, servicio_id ?? null, req.auth!.negocio_id]
        );
        return result.rows as { estado: string; completado: boolean; precio_referencia: number | null }[];
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    const completados = filas.filter((f) => f.completado);
    const turnos_totales = filas.filter((f) => f.estado !== 'reprogramado').length;
    const turnos_cancelados = filas.filter((f) => f.estado === 'cancelado').length;
    const monto_facturado = completados.reduce((acc, f) => acc + (f.precio_referencia ?? 0), 0);

    res.json({
      desde: desdeIso,
      hasta: hastaIso,
      servicio_id: servicio_id ?? null,
      turnos_totales,
      turnos_completados: completados.length,
      turnos_cancelados,
      monto_facturado,
    });
  })
);
