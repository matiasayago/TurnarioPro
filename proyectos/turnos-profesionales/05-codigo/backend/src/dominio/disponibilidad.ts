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
import { db } from '../db';

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
export function calcularSlotsDisponibles(
  profesionalId: string,
  servicioId: string,
  opciones: OpcionesCalculoSlots = {}
): ResultadoCalculoSlots | null {
  const servicio = db.prepare('SELECT duracion_min FROM servicio WHERE id = ?').get(servicioId) as
    | { duracion_min: number }
    | undefined;
  if (!servicio) return null;

  // D10 (amenda RN3, ver modelo-datos.md §2quater): si el profesional configuró su propia
  // duración de cita general (`profesional.duracion_cita_min`), reemplaza SIEMPRE la duración
  // del servicio para calcular la grilla, en TODOS sus servicios, sin excepción. `NULL` (el
  // profesional no configuró ningún override) preserva el comportamiento de siempre: se sigue
  // usando `servicio.duracion_min`. Único lugar que decide el tamaño del paso de la grilla, así
  // que este fix alcanza para GET /profesionales/:id/slots y POST /turnos, que solo llaman a
  // esta función — no hace falta duplicar la regla en ninguno de los dos.
  const profesional = db
    .prepare('SELECT duracion_cita_min FROM profesional WHERE id = ?')
    .get(profesionalId) as { duracion_cita_min: number | null } | undefined;
  const duracionEfectivaMin = profesional?.duracion_cita_min ?? servicio.duracion_min;

  const bloques = db
    .prepare('SELECT * FROM disponibilidad WHERE profesional_id = ? AND servicio_id = ?')
    .all(profesionalId, servicioId) as any[];

  const inicioBusqueda = opciones.desde ?? new Date();
  const ventanaDias = opciones.dias ?? 14;
  const maxSlots = opciones.maxSlots ?? 20;
  const duracionMs = duracionEfectivaMin * 60_000;

  const turnosActivos = db
    .prepare(
      `SELECT inicio, fin FROM turno WHERE profesional_id = ? AND estado IN ('pendiente_de_pago','confirmado')`
    )
    .all(profesionalId) as { inicio: string; fin: string }[];

  const excepciones = db
    .prepare('SELECT inicio, fin FROM excepcion_disponibilidad WHERE profesional_id = ?')
    .all(profesionalId) as { inicio: string; fin: string }[];

  const ocupado = (ini: Date, fin: Date) =>
    [...turnosActivos, ...excepciones].some((o) => ini < new Date(o.fin) && fin > new Date(o.inicio));

  const slots: string[] = [];
  for (let d = 0; d < ventanaDias && slots.length < maxSlots; d++) {
    const dia = new Date(inicioBusqueda);
    dia.setDate(dia.getDate() + d);
    const bloqueDelDia = bloques.find((b) => b.dia_semana === dia.getDay());
    if (!bloqueDelDia) continue;

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
