// Motor de disponibilidad — CU1/CU4/RN1/RN2. Extraído de `GET /profesionales/:id/slots`
// (antes vivía inline y duplicado ahí) para que `POST /turnos` pueda reutilizar EXACTAMENTE la
// misma grilla de slots al validar una reserva (ver reporte-qa.md DEF-01/DEF-02).
//
// Por qué esto también resuelve DEF-02 (solapamiento con `inicio` distinto) sin un chequeo de
// rango aparte: la grilla que calculamos acá está alineada a bloques de duración fija (bloque
// de disponibilidad + duración del servicio), así que un horario que no coincide con ningún
// paso de esa grilla (ej. 09:30 cuando la grilla es 09:00/10:00/11:00 para un servicio de 60
// min) nunca aparece en la lista, sin importar si ya hay algo reservado o no.
//
// `ignorarOcupacion` existe porque `POST /turnos` necesita distinguir DOS motivos de rechazo
// distintos (ver turnos.ts): (a) el horario ni siquiera está alineado a la grilla publicada →
// RN1, 400; (b) el horario SÍ está alineado a la grilla pero ya lo ocupa un turno/excepción
// activo → RN2, 409 (el mismo código que ya devolvía el índice único de la base ante una
// reserva duplicada exacta). Si reusáramos siempre el filtro de ocupación para la validación de
// RN1, una reserva duplicada exacta pasaría de 409 a 400 (regresión detectada al re-correr
// smoke-test.mjs) porque el slot ocupado directamente no aparecería en la lista.
//
// Migración a PostgreSQL (ver src/db.ts): recibe un `Queryable` en vez de asumir un objeto `db`
// síncrono — tanto `pool` (lecturas públicas, ej. GET /profesionales/:id/slots, sin necesidad
// de contexto RLS) como un `client` ya dentro de una transacción autenticada (POST /turnos reusa
// el mismo client de su propia transacción para RN1/RN2) cumplen esa interfaz sin duplicar esta
// función para cada caso.
//
// Adopción DBA (2026-08-09, ver migrations/001_init.sql, "Funciones SECURITY DEFINER" al final
// del archivo, caso de uso (a)): la lectura de `turno` de más abajo pasa por la función
// `turno_ocupacion_publica(profesional_id)` en vez de un SELECT directo sobre la tabla — expone
// solo inicio/fin de turnos activos de ESE profesional, ni cliente_id ni ninguna otra columna.
// SECURITY DEFINER no depende de `app.usuario_id`, así que sigue funcionando igual sin importar
// si `db` es `pool` (GET /profesionales/:id/slots, sin contexto RLS) o un `client` dentro de la
// transacción de POST /turnos (que sí tiene `app.usuario_id` seteado, pero esta lectura no lo
// necesita) — ninguno de los dos callers cambia de comportamiento por este reemplazo, ambos
// seguían leyendo sin contexto RLS antes también (ver reserva documentada junto a
// `turno_select_publico`, que se mantiene activa como red de seguridad transitoria).
import { Queryable } from '../db';

export interface OpcionesCalculoSlots {
  /** Desde qué instante buscar (por defecto: ahora). Para validar RN1 en POST /turnos se pasa
   *  el inicio del día calendario del `inicio` pedido, para que la ventana incluya ese día
   *  completo sin importar la hora actual. */
  desde?: Date;
  /** Cuántos días de ventana recorrer (por defecto: 14). */
  dias?: number;
  /** Tope de slots a devolver (por defecto: 20 — ver `GET /slots`, pensado para no listar de
   *  más en la UI; al validar un único día en POST /turnos se pasa un valor alto para no
   *  truncar la grilla del día antes de encontrar el slot pedido). */
  maxSlots?: number;
  /** Si es `true`, NO descuenta turnos/excepciones activos — devuelve la grilla "teórica" según
   *  los bloques de disponibilidad publicados, para chequear alineación (RN1) independientemente
   *  de si el slot está libre en este momento (ver comentario de archivo). Por defecto `false`
   *  (comportamiento de siempre: solo devuelve slots realmente libres, usado por `GET /slots`). */
  ignorarOcupacion?: boolean;
}

export interface ResultadoCalculoSlots {
  duracionMin: number;
  /** Slots válidos, como ISO strings, ordenados cronológicamente. */
  slots: string[];
}

/**
 * Calcula los slots de agenda disponibles para un profesional+servicio dentro de una ventana de
 * tiempo, a partir de los bloques de `disponibilidad` publicados, descontando turnos activos
 * (`pendiente_de_pago`/`confirmado`) y excepciones (`excepcion_disponibilidad`).
 *
 * Devuelve `null` si el servicio no existe (el caller decide qué responder — 404 en ambos
 * lugares que lo usan hoy).
 */
export async function calcularSlotsDisponibles(
  db: Queryable,
  profesionalId: string,
  servicioId: string,
  opciones: OpcionesCalculoSlots = {}
): Promise<ResultadoCalculoSlots | null> {
  const servicioResult = await db.query('SELECT duracion_min FROM servicio WHERE id = $1', [servicioId]);
  const servicio = servicioResult.rows[0] as { duracion_min: number } | undefined;
  if (!servicio) return null;

  // D10 (amenda RN3, ver modelo-datos.md §2quater): si el profesional configuró su propia
  // duración de cita general (`profesional.duracion_cita_min`), reemplaza SIEMPRE la duración
  // del servicio para calcular la grilla, en TODOS sus servicios, sin excepción. `NULL` (el
  // profesional no configuró ningún override) preserva el comportamiento de siempre: se sigue
  // usando `servicio.duracion_min`. Único lugar que decide el tamaño del paso de la grilla, así
  // que este fix alcanza para GET /profesionales/:id/slots y POST /turnos, que solo llaman a
  // esta función — no hace falta duplicar la regla en ninguno de los dos.
  const profesionalResult = await db.query(
    'SELECT duracion_cita_min FROM profesional WHERE id = $1',
    [profesionalId]
  );
  const profesional = profesionalResult.rows[0] as { duracion_cita_min: number | null } | undefined;
  const duracionEfectivaMin = profesional?.duracion_cita_min ?? servicio.duracion_min;

  const bloquesResult = await db.query(
    'SELECT * FROM disponibilidad WHERE profesional_id = $1 AND servicio_id = $2',
    [profesionalId, servicioId]
  );
  const bloques = bloquesResult.rows as any[];

  const inicioBusqueda = opciones.desde ?? new Date();
  const ventanaDias = opciones.dias ?? 14;
  const maxSlots = opciones.maxSlots ?? 20;
  const duracionMs = duracionEfectivaMin * 60_000;

  // Antes: `SELECT inicio, fin FROM turno WHERE profesional_id = $1 AND estado IN
  // ('pendiente_de_pago','confirmado')` directo sobre la tabla. Ahora vía la función
  // `turno_ocupacion_publica` (ver comentario de archivo, arriba) — mismo filtro
  // (profesional_id + estado activo), aplicado del lado de la base dentro de la función en vez
  // de repetido acá.
  const turnosActivosResult = await db.query('SELECT inicio, fin FROM turno_ocupacion_publica($1)', [
    profesionalId,
  ]);
  const turnosActivos = turnosActivosResult.rows as { inicio: string; fin: string }[];

  const excepcionesResult = await db.query(
    'SELECT inicio, fin FROM excepcion_disponibilidad WHERE profesional_id = $1',
    [profesionalId]
  );
  const excepciones = excepcionesResult.rows as { inicio: string; fin: string }[];

  const ocupado = (ini: Date, fin: Date) =>
    [...turnosActivos, ...excepciones].some((o) => ini < new Date(o.fin) && fin > new Date(o.inicio));

  const slots: string[] = [];
  for (let d = 0; d < ventanaDias && slots.length < maxSlots; d++) {
    const dia = new Date(inicioBusqueda);
    dia.setDate(dia.getDate() + d);
    const bloqueDelDia = bloques.find((b) => b.dia_semana === dia.getDay());
    if (!bloqueDelDia) continue;

    // `hora_inicio`/`hora_fin` son columnas TIME de Postgres — `pg` las devuelve como string
    // "HH:MM:SS" (a diferencia del TEXT "HH:MM" de node:sqlite). El destructuring de abajo sigue
    // funcionando sin cambios: toma los primeros dos elementos (horas, minutos) e ignora el
    // resto (segundos, siempre "00" acá — `horaSchema` en dominio/validacion.ts solo acepta
    // HH:MM al cargar disponibilidad).
    const [hIni, mIni] = bloqueDelDia.hora_inicio.split(':').map(Number);
    const [hFin, mFin] = bloqueDelDia.hora_fin.split(':').map(Number);
    let cursor = new Date(dia);
    cursor.setHours(hIni, mIni, 0, 0);
    const finBloque = new Date(dia);
    finBloque.setHours(hFin, mFin, 0, 0);

    while (cursor.getTime() + duracionMs <= finBloque.getTime() && slots.length < maxSlots) {
      const finSlot = new Date(cursor.getTime() + duracionMs);
      if (cursor > inicioBusqueda && (opciones.ignorarOcupacion || !ocupado(cursor, finSlot))) {
        slots.push(cursor.toISOString());
      }
      cursor = finSlot;
    }
  }

  return { duracionMin: duracionEfectivaMin, slots };
}

/** Medianoche LOCAL del día que contiene `fecha` — usado para construir una ventana de
 *  `calcularSlotsDisponibles` que cubra el día completo del `inicio` pedido en POST /turnos,
 *  sin que la hora actual del servidor recorte slots de ese mismo día. */
export function inicioDelDiaLocal(fecha: Date): Date {
  const copia = new Date(fecha);
  copia.setHours(0, 0, 0, 0);
  return copia;
}
