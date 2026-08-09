import { Router, Response } from 'express';
import { z } from 'zod';
import { v4 as uuid } from 'uuid';
import { pool, nowIso, withTransaction } from '../db';
import { requireAuth, AuthedRequest } from '../auth';
import { asyncHandler } from '../middleware/asyncHandler';
import { calcularSlotsDisponibles, inicioDelDiaLocal } from '../dominio/disponibilidad';
import { uuidSchema, fechaIsoSchema, respuestaValidacionFallida } from '../dominio/validacion';

export const turnosRouter = Router();

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación de entrada — se
// aplican al INICIO de cada handler, antes de tocar la base de datos. Reemplazan (sin dejar
// huecos) los chequeos puntuales de presencia y de fecha (DEF-04) que ya existían.
const crearTurnoSchema = z.object({
  profesional_id: uuidSchema,
  servicio_id: uuidSchema,
  inicio: fechaIsoSchema,
});

const turnoIdParamsSchema = z.object({ id: uuidSchema });

const reprogramarSchema = z.object({ nuevo_inicio: fechaIsoSchema });

// RN8: ventana mínima de cancelación/reprogramación (parametrizable, propuesta 2 horas — A3).
const VENTANA_MIN_MINUTOS = Number(process.env.VENTANA_CANCELACION_MIN ?? 120);

function dentroDeVentanaMinima(inicioTurno: string): boolean {
  const minutosParaElTurno = (new Date(inicioTurno).getTime() - Date.now()) / 60_000;
  return minutosParaElTurno < VENTANA_MIN_MINUTOS;
}

// HU-09 / HU-09b: reservar un turno. Ver documento-arquitectura.md §4 — la garantía
// anti-doble-reserva (RN2) vive en el índice único parcial `uq_turno_slot_activo`, no en un
// SELECT previo. Si dos clientes piden el mismo (profesional_id, inicio) al mismo tiempo,
// Postgres solo deja pasar un INSERT; el segundo lanza el error de unicidad 23505.
//
// Las lecturas de validación (profesional/servicio/membresía/RN4/grilla RN1-RN2) corren vía
// `pool` directo, sin transacción: `profesional`, `servicio`, `negocio_profesional` y
// `profesional_servicio` son legibles sin contexto RLS (policies públicas de SELECT); la
// ocupación de `turno` que usa la grilla RN1-RN2 (calcularSlotsDisponibles, ver
// dominio/disponibilidad.ts) pasa por la función SECURITY DEFINER `turno_ocupacion_publica` en
// vez de un SELECT directo (adopción DBA 2026-08-09, ver migrations/001_init.sql) — mismo
// criterio que ya usaba esta función antes de la migración (chequeos previos sueltos, la
// garantía real es el índice único). El INSERT final (turno + pago + notificación) SÍ corre en
// una única transacción con contexto RLS (`usuarioId`), sobre el MISMO client para las 3
// sentencias — necesario porque `turno` tiene RLS de escritura (WITH CHECK exige
// `cliente_id = app.usuario_id`).
turnosRouter.post(
  '/',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // MEDIUM-3 / DEF-04 (ver informe-seguridad.md y reporte-qa.md): valida presencia, UUID bien
    // formado y fecha ISO-8601 válida ANTES de usar `inicio` en cualquier cálculo — antes un
    // valor no parseable llegaba a `new Date(inicio).toISOString()` y tiraba un RangeError no
    // capturado (500 con stack trace, ver HIGH-2, ya resuelto por el error handler, pero mejor
    // rechazarlo acá).
    const parsed = crearTurnoSchema.safeParse(req.body);
    if (!parsed.success) return respuestaValidacionFallida(res, parsed.error);
    const { profesional_id, servicio_id, inicio } = parsed.data;

    const inicioDate = new Date(inicio);

    // `profesional.negocio_id` (1:1) ya no existe (ver modelo-datos.md §2ter) — el negocio del
    // turno sale de `servicio.negocio_id`, inequívoco porque un servicio sigue siendo 1:1 con su
    // negocio (esa relación no cambia en esta generalización). Acá solo hace falta confirmar que
    // el profesional_id pedido exista (la FK de `turno.profesional_id` fallaría más abajo si no).
    const profesionalResult = await pool.query('SELECT id FROM profesional WHERE id = $1', [profesional_id]);
    const profesional = profesionalResult.rows[0] as { id: string } | undefined;
    const servicioResult = await pool.query('SELECT negocio_id, duracion_min FROM servicio WHERE id = $1', [
      servicio_id,
    ]);
    const servicio = servicioResult.rows[0] as { negocio_id: string; duracion_min: number } | undefined;
    if (!profesional || !servicio) {
      return res.status(404).json({ error: 'Profesional o servicio no encontrado' });
    }

    // Integridad N:M (ver modelo-datos.md §2ter, "recomendación adicional"): antes de esta
    // generalización era estructuralmente imposible reservar con un profesional que no trabaja en
    // el negocio del servicio elegido (el profesional tenía un único negocio_id posible). Ahora
    // hay que confirmarlo a nivel de aplicación antes de crear la reserva.
    const esMiembroActivoResult = await pool.query(
      'SELECT 1 FROM negocio_profesional WHERE negocio_id = $1 AND profesional_id = $2 AND activo = true',
      [servicio.negocio_id, profesional_id]
    );
    if (!esMiembroActivoResult.rowCount) {
      return res.status(404).json({
        error: 'Este profesional no pertenece al negocio del servicio solicitado',
      });
    }

    // RN4 (DEF-03, ver reporte-qa.md): el profesional tiene que haber asociado explícitamente
    // este servicio (fila en `profesional_servicio`). Se valida ANTES de leer requiere_sena /
    // insertar el turno — si no hay fila, el default de la columna (`requiere_sena = false`)
    // eludía el control de seña además de permitir reservar un servicio que el profesional
    // nunca ofreció.
    const relacionResult = await pool.query(
      'SELECT requiere_sena, monto_sena FROM profesional_servicio WHERE profesional_id = $1 AND servicio_id = $2',
      [profesional_id, servicio_id]
    );
    const relacion = relacionResult.rows[0] as
      | { requiere_sena: boolean; monto_sena: number | null }
      | undefined;
    if (!relacion) {
      return res.status(404).json({ error: 'Este profesional no ofrece este servicio (RN4)' });
    }

    // RN1 (DEF-01) — y, de yapa, DEF-02 (solapamiento con `inicio` distinto), ver el comentario
    // largo en src/dominio/disponibilidad.ts: recalculamos la grilla de slots para el día del
    // `inicio` pedido (misma función que usa GET /profesionales/:id/slots) y exigimos que
    // `inicio` sea EXACTAMENTE uno de sus pasos. Se hace en DOS pasadas para no confundir dos
    // motivos de rechazo distintos:
    //  1) `inicio` ni siquiera está alineado a la grilla publicada (dia/horario fuera de bloque,
    //     o un horario "intermedio" no alcanzable con la duración del servicio, ej. 09:30 con
    //     bloques de 60 min) → RN1, 400.
    //  2) `inicio` SÍ está alineado a la grilla pero ya lo ocupa un turno/excepción activo → RN2,
    //     409 (mismo código que ya devuelve el índice único de la base ante una reserva duplicada
    //     exacta — si solo usáramos la lista de slots LIBRES para el chequeo de RN1, una reserva
    //     duplicada exacta pasaría a responder 400 en vez de 409, rompiendo esa garantía existente).
    const inicioIso = inicioDate.toISOString();
    const ventanaDelDia = { desde: inicioDelDiaLocal(inicioDate), dias: 1, maxSlots: 500 };

    const grilla = await calcularSlotsDisponibles(pool, profesional_id, servicio_id, {
      ...ventanaDelDia,
      ignorarOcupacion: true,
    });
    const alineadoAGrilla = grilla?.slots.includes(inicioIso) ?? false;
    if (!alineadoAGrilla) {
      return res.status(400).json({
        error:
          'El horario solicitado no corresponde a un slot de disponibilidad publicado por el profesional (RN1).',
      });
    }

    const slotsLibres = await calcularSlotsDisponibles(pool, profesional_id, servicio_id, ventanaDelDia);
    const estaLibre = slotsLibres?.slots.includes(inicioIso) ?? false;
    if (!estaLibre) {
      return res.status(409).json({
        error: 'Ese horario ya no está disponible — se solapa con otro turno o excepción de este profesional (RN2).',
      });
    }

    // D10 (amenda RN3, ver modelo-datos.md §2quater): reusamos `slotsLibres.duracionMin` en vez de
    // recalcular a partir de `servicio.duracion_min` — ese valor ya salió de
    // `calcularSlotsDisponibles` (con el fallback a `profesional.duracion_cita_min` ya aplicado) y
    // es EXACTAMENTE la duración con la que se validó el slot `estaLibre` arriba. Evita una
    // segunda fuente de verdad que se pueda desincronizar del slot que realmente se validó. El `!`
    // es seguro acá: si `slotsLibres` fuera `null`, `estaLibre` habría sido `false` y ya se
    // devolvió antes de llegar a esta línea.
    const finDate = new Date(inicioDate.getTime() + slotsLibres!.duracionMin * 60_000);
    const requiereSena = !!relacion?.requiere_sena; // D2/RN10 — configurable por profesional+servicio
    const estadoInicial = requiereSena ? 'pendiente_de_pago' : 'confirmado';
    const turnoId = uuid();
    const ts = nowIso();

    try {
      await withTransaction(
        async (client) => {
          await client.query(
            `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              turnoId,
              servicio.negocio_id,
              profesional_id,
              servicio_id,
              req.auth!.sub,
              inicioDate.toISOString(),
              finDate.toISOString(),
              estadoInicial,
              ts,
            ]
          );

          if (requiereSena) {
            await client.query(
              'INSERT INTO pago (id, turno_id, monto, estado, creado_en) VALUES ($1, $2, $3, $4, $5)',
              [uuid(), turnoId, relacion?.monto_sena ?? 0, 'pendiente', ts]
            );
          }

          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, creado_en) VALUES ($1, $2, $3, $4)',
            [uuid(), turnoId, 'confirmacion', ts] // D4 — el envío real lo hace el proveedor de notificaciones (stub, ver notificaciones.ts)
          );
        },
        { usuarioId: req.auth!.sub }
      );
    } catch (err: any) {
      // Postgres (ver database/migrations/001_init.sql): code 23505 = unique_violation, lanzado
      // por el índice único parcial `uq_turno_slot_activo` si dos requests corren la misma
      // ventana de tiempo en paralelo (ver scripts/test-concurrent-booking.mjs). Ya no hay
      // fallback al shape de error de node:sqlite (SQLITE_CONSTRAINT_UNIQUE / mensaje "UNIQUE") —
      // ese driver quedó reemplazado por completo, un solo código de error posible acá.
      if (err?.code === '23505') {
        return res.status(409).json({
          error: 'Ese horario ya no está disponible — alguien más lo reservó primero (RN2).',
        });
      }
      throw err;
    }

    res.status(201).json({
      id: turnoId,
      estado: estadoInicial,
      requiere_pago: requiereSena,
      monto_sena: relacion?.monto_sena ?? null,
    });
  })
);

// HU-12: cancelar un turno propio. Todo (SELECT + chequeos + UPDATE) corre en una sola
// transacción con contexto RLS — el resultado es un objeto discriminado por `tipo` porque ya no
// se puede hacer `return res.status(...)` desde adentro del closure de `withTransaction`.
turnosRouter.patch(
  '/:id/cancelar',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // Validación de `:id` agregada acá (no existía en la versión anterior): con `turno.id`
    // tipado `uuid` en Postgres (a diferencia del TEXT de node:sqlite), un `:id` mal formado ya
    // no devuelve "no encontrado" solo — Postgres tira "invalid input syntax for type uuid",
    // que sin este chequeo previo terminaría como 500 genérico en vez del 400 esperable.
    const paramsParsed = turnoIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    const resultado = await withTransaction(
      async (client) => {
        // Adopción DBA (2026-08-09, ver migrations/001_init.sql, caso de uso (b)): antes un SELECT
        // directo sobre `turno` (cubierto por la policy pública `turno_select_publico`, que se
        // mantiene activa como red de seguridad transitoria). La función `turno_propio_para_gestion`
        // lee SIN filtrar por cliente_id (a propósito — hace falta distinguir 403 de 404 más abajo)
        // y expone solo las columnas que este handler usa (no creado_en/modificado_en).
        const turnoResult = await client.query('SELECT * FROM turno_propio_para_gestion($1)', [
          req.params.id,
        ]);
        const turno = turnoResult.rows[0];
        if (!turno) return { tipo: 'no_encontrado' as const };
        if (turno.cliente_id !== req.auth!.sub) return { tipo: 'prohibido' as const };
        if (dentroDeVentanaMinima(turno.inicio)) return { tipo: 'fuera_de_ventana' as const };

        await client.query("UPDATE turno SET estado = 'cancelado', modificado_en = $1 WHERE id = $2", [
          nowIso(),
          req.params.id,
        ]);
        return { tipo: 'ok' as const };
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'prohibido':
        return res.status(403).json({ error: 'No podés cancelar un turno que no es tuyo' });
      case 'fuera_de_ventana':
        return res.status(409).json({
          error: `Fuera de la ventana mínima de cancelación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
        });
      case 'ok':
        return res.json({ ok: true });
    }
  })
);

// HU-13: reprogramar un turno propio a otro horario del MISMO profesional/servicio (CU5).
// Reutiliza la misma garantía anti-doble-reserva del alta (índice único parcial, ver §4 de
// documento-arquitectura.md): el turno viejo se marca 'reprogramado' (sale del índice, que
// solo cubre pendiente_de_pago/confirmado) y el nuevo se inserta con el nuevo horario; si ese
// horario ya lo tomó otro cliente, el INSERT falla con 409 igual que en POST /turnos.
//
// Mismo patrón que /:id/cancelar (resultado discriminado por `tipo`) más un try/catch exterior
// para el 23505 (que sale de `withTransaction` como excepción, no como valor de retorno, porque
// el motor de Postgres lo lanza en medio de la transacción — `withTransaction` hace ROLLBACK y
// relanza).
turnosRouter.patch(
  '/:id/reprogramar',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    // MEDIUM-3 (ver informe-seguridad.md): valida el :id de la URL como UUID bien formado.
    const paramsParsed = turnoIdParamsSchema.safeParse(req.params);
    if (!paramsParsed.success) return respuestaValidacionFallida(res, paramsParsed.error);

    // MEDIUM-3 / DEF-04 (ver informe-seguridad.md y reporte-qa.md): mismo problema que en
    // POST /turnos — validar el formato ANTES de usar la fecha en cualquier cálculo, para no
    // dejar pasar un RangeError sin capturar.
    const bodyParsed = reprogramarSchema.safeParse(req.body);
    if (!bodyParsed.success) return respuestaValidacionFallida(res, bodyParsed.error);
    const { nuevo_inicio } = bodyParsed.data;
    const nuevoInicioDate = new Date(nuevo_inicio);
    const nuevoTurnoId = uuid();
    const ts = nowIso();

    type Resultado =
      | { tipo: 'no_encontrado' }
      | { tipo: 'prohibido' }
      | { tipo: 'estado_invalido'; estado: string }
      | { tipo: 'fuera_de_ventana' }
      | { tipo: 'ok'; estadoFinal: string };

    let resultado: Resultado;
    try {
      resultado = await withTransaction(
        async (client) => {
          // Misma función SECURITY DEFINER que /:id/cancelar (ver comentario ahí). Este handler
          // además usa profesional_id/servicio_id/negocio_id/estado del turno leído acá, todos
          // presentes en turno_propio_para_gestion (no así creado_en/modificado_en, sin uso acá).
          const turnoResult = await client.query('SELECT * FROM turno_propio_para_gestion($1)', [
            req.params.id,
          ]);
          const turno = turnoResult.rows[0];
          if (!turno) return { tipo: 'no_encontrado' as const };
          if (turno.cliente_id !== req.auth!.sub) return { tipo: 'prohibido' as const };
          if (!['pendiente_de_pago', 'confirmado'].includes(turno.estado)) {
            return { tipo: 'estado_invalido' as const, estado: turno.estado };
          }
          if (dentroDeVentanaMinima(turno.inicio)) return { tipo: 'fuera_de_ventana' as const };

          const servicioResult = await client.query('SELECT duracion_min FROM servicio WHERE id = $1', [
            turno.servicio_id,
          ]);
          const servicio = servicioResult.rows[0] as { duracion_min: number } | undefined;
          // D10 (amenda RN3, ver modelo-datos.md §2quater — "Hallazgo adicional"): mismo
          // fallback que `calcularSlotsDisponibles` — si el profesional de este turno tiene
          // `duracion_cita_min` configurada, reemplaza la duración del servicio también al
          // reprogramar. Sin esto, reprogramar el turno de un profesional con override
          // configurado le devolvería silenciosamente la duración del servicio en vez de
          // mantener la duración con la que se reservó originalmente.
          const profesionalResult = await client.query(
            'SELECT duracion_cita_min FROM profesional WHERE id = $1',
            [turno.profesional_id]
          );
          const profesionalConfig = profesionalResult.rows[0] as
            | { duracion_cita_min: number | null }
            | undefined;
          const duracionEfectivaMin = profesionalConfig?.duracion_cita_min ?? servicio!.duracion_min;
          const nuevoFinDate = new Date(nuevoInicioDate.getTime() + duracionEfectivaMin * 60_000);
          const estadoFinal = turno.estado === 'confirmado' ? 'confirmado' : 'pendiente_de_pago'; // conserva el estado de pago (D2)

          await client.query("UPDATE turno SET estado = 'reprogramado', modificado_en = $1 WHERE id = $2", [
            ts,
            turno.id,
          ]);

          await client.query(
            `INSERT INTO turno (id, negocio_id, profesional_id, servicio_id, cliente_id, inicio, fin, estado, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              nuevoTurnoId,
              turno.negocio_id,
              turno.profesional_id,
              turno.servicio_id,
              turno.cliente_id,
              nuevoInicioDate.toISOString(),
              nuevoFinDate.toISOString(),
              estadoFinal,
              ts,
            ]
          );

          // El pago (si existe) sigue al turno reprogramado — no se le vuelve a cobrar la seña.
          await client.query('UPDATE pago SET turno_id = $1 WHERE turno_id = $2', [nuevoTurnoId, turno.id]);

          await client.query(
            'INSERT INTO notificacion (id, turno_id, tipo, creado_en) VALUES ($1, $2, $3, $4)',
            [uuid(), nuevoTurnoId, 'confirmacion', ts]
          );

          return { tipo: 'ok' as const, estadoFinal };
        },
        { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
      );
    } catch (err: any) {
      if (err?.code === '23505') {
        return res.status(409).json({
          error: 'Ese nuevo horario ya no está disponible — alguien más lo reservó primero (RN2).',
        });
      }
      throw err;
    }

    switch (resultado.tipo) {
      case 'no_encontrado':
        return res.status(404).json({ error: 'Turno no encontrado' });
      case 'prohibido':
        return res.status(403).json({ error: 'No podés reprogramar un turno que no es tuyo' });
      case 'estado_invalido':
        return res.status(409).json({ error: `No se puede reprogramar un turno en estado '${resultado.estado}'` });
      case 'fuera_de_ventana':
        return res.status(409).json({
          error: `Fuera de la ventana mínima de reprogramación (${VENTANA_MIN_MINUTOS} min) — contactá al negocio directamente.`,
        });
      case 'ok':
        return res.json({ id: nuevoTurnoId, estado: resultado.estadoFinal });
    }
  })
);

// Mis turnos (cliente autenticado).
turnosRouter.get(
  '/mios',
  requireAuth('cliente'),
  asyncHandler(async (req: AuthedRequest, res: Response) => {
    const turnos = await withTransaction(
      async (client) => {
        const result = await client.query('SELECT * FROM turno WHERE cliente_id = $1 ORDER BY inicio DESC', [
          req.auth!.sub,
        ]);
        return result.rows;
      },
      { usuarioId: req.auth!.sub, negocioId: req.auth!.negocio_id }
    );
    res.json(turnos);
  })
);
