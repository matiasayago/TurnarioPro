// Helpers de dominio para la bandeja de notificaciones (HU-14b/HU-25) — extraídos a un módulo
// propio (mismo criterio que dominio/disponibilidad.ts, lógica compartida sin dependencia de
// Express/HTTP): lo usa GET /notificaciones (src/routes/notificaciones.ts) para armar el texto de
// la bandeja, y (ampliación 2026-08-18, pedido explícito del CEO — envío real por email vía
// Resend, ver integraciones/email.ts) también routes/turnos.ts, routes/profesionales.ts y
// jobs/recordarTurnosProximos.ts, para armar el mismo texto (más el asunto,
// `armarAsuntoNotificacion` más abajo) como cuerpo del email que replica cada notificación — el
// armado de texto es independiente del transporte, tal como preveía este comentario desde el
// origen.
//
// Decisión heredada de DBA (ver database/migrations/001_init.sql, bloque "Bandeja de
// notificaciones", y 004_notificaciones.sql): la fila `notificacion` NO guarda texto/nombre/hora
// "congelados" — se arman acá, en el momento de leer, a partir de los datos de `turno` (que
// nunca se borra físicamente, solo cambia de `estado` — la referencia por turno_id sigue siendo
// válida para siempre).
import { Queryable } from '../db';

/** Espejo de tipo_notificacion (database/migrations/001_init.sql). */
export type TipoNotificacion = 'confirmacion' | 'recordatorio' | 'cancelacion' | 'reprogramacion';

export interface DatosMensajeNotificacion {
  tipo: TipoNotificacion;
  /** usuario.nombre del cliente del turno. */
  clienteNombre: string;
  /** usuario.nombre del profesional del turno (vía profesional.usuario_id). */
  profesionalNombre: string;
  /** negocio.nombre del turno (vía turno.negocio_id) — agregado 2026-08-19, pedido explícito del
   *  CEO tras revisar un email real de confirmación en producción: el mensaje no decía DÓNDE era
   *  el turno (solo con qué profesional). */
  negocioNombre: string;
  /** turno.inicio, ISO-8601. */
  turnoInicio: string;
  /** true si el DESTINATARIO de esta notificación puntual es el cliente del turno, false si es
   *  el profesional — el mensaje habla siempre desde la perspectiva de QUIEN LO RECIBE, nunca
   *  asume un valor fijo. Hasta el 2026-08-17 ningún productor real generaba el caso `true` (ver
   *  el razonamiento original de DBA en 001_init.sql, "es la bandeja del PROFESIONAL"); desde
   *  `POST /profesionales/:id/turnos` (HU-23, routes/profesionales.ts) ya no es así, y desde la
   *  ampliación del 2026-08-18 (pedido explícito del CEO: notificar a AMBAS partes en los 5
   *  productores existentes, más el envío real por email vía Resend, ver integraciones/email.ts)
   *  los 5 productores generan SIEMPRE los 2 casos para cada evento. */
  destinatarioEsCliente: boolean;
}

/**
 * Hora local "HH:MM" de un ISO-8601 — mismo criterio que ya usa el resto de este backend para
 * "local" (ver dominio/disponibilidad.ts: `dia.getDay()` / `cursor.setHours(...)`, ambos sobre
 * el huso horario del proceso Node, sin `Intl`/zona horaria explícita en ningún lugar del código
 * existente): se reutiliza esa misma convención acá en vez de introducir una nueva.
 */
export function formatearHoraLocal(fechaIso: string): string {
  const fecha = new Date(fechaIso);
  const horas = String(fecha.getHours()).padStart(2, '0');
  const minutos = String(fecha.getMinutes()).padStart(2, '0');
  return `${horas}:${minutos}`;
}

/**
 * Fecha + hora local, en español, en un fraseo natural (ej. "martes 25 de agosto a las 11:00") —
 * agregada 2026-08-19 (pedido explícito del CEO, ver el comentario grande de
 * `armarMensajeNotificacion` más abajo). Mismo criterio de "local" que `formatearHoraLocal` de
 * arriba (huso horario del proceso Node, sin zona horaria explícita en ningún lugar del código
 * existente) — de hecho reutiliza esa misma función para la porción de hora, así ambas piezas del
 * texto quedan calculadas sobre exactamente el mismo huso horario, sin una segunda fuente de
 * verdad para "ahora".
 *
 * `Intl.DateTimeFormat` es nativo del runtime de Node (con ICU completo desde Node 13+, sin flags
 * ni compilación adicional) — no hace falta agregar date-fns/luxon/moment como dependencia nueva
 * solo para esto (este backend no tiene ninguna de las tres instaladas). Se usa acá únicamente
 * para el nombre del día de la semana y del mes, ya localizados en español por ese runtime
 * (`'es-AR'`, mismo país de referencia que ya usa Mobile — ver
 * `mobile/lib/screens/cliente/confirmar_turno_screen.dart`, `DateFormat('EEEE d MMMM · HH:mm',
 * 'es')` — sin copiar ese formato literal, que es más compacto por ser para UI; acá el texto es
 * prosa de una notificación).
 */
export function formatearFechaHoraLocal(fechaIso: string): string {
  const fecha = new Date(fechaIso);
  const diaSemana = new Intl.DateTimeFormat('es-AR', { weekday: 'long' }).format(fecha);
  const diaYMes = new Intl.DateTimeFormat('es-AR', { day: 'numeric', month: 'long' }).format(fecha);
  return `${diaSemana} ${diaYMes} a las ${formatearHoraLocal(fechaIso)}`;
}

/**
 * Arma, en español, el texto de una notificación. Copy original (hasta 2026-08-18) igual, exacto,
 * a mapa-pantallas.md §5.15 para los 3 tipos que entonces tenían productor real: "María Pérez
 * confirmó su turno de las 10:00" / "Recordatorio: turno con Juan Ramírez en 1 hora" / "Sofía Cano
 * canceló su turno de las 16:00".
 *
 * AMPLIACIÓN 2026-08-19 (pedido explícito del CEO, tras revisar un email real de confirmación en
 * producción): ese copy original solo traía la HORA del turno (nunca el día/mes — un turno de
 * mañana y uno de dentro de 3 semanas a la misma hora generaban idéntico texto) y nunca el negocio
 * donde era (solo el nombre del profesional). Los 8 casos de abajo ahora arman la fecha completa
 * con `formatearFechaHoraLocal` (en vez de solo `formatearHoraLocal`) y agregan
 * `datos.negocioNombre` — ya no son el copy literal del wireframe de arriba (que no contemplaba
 * ninguno de los dos datos), pero preservan su mismo tono y estructura por caso.
 *
 * `recordatorio` usa el texto fijo "en 1 hora" — NO una cuenta regresiva calculada contra
 * `now()` en cada lectura: como el mensaje se deriva en cada GET (no se congela, ver header de
 * archivo), una cuenta regresiva real mostraría valores decrecientes (o negativos, pasado el
 * turno) cada vez que el usuario reabre la bandeja. "en 1 hora" se interpreta acá como la
 * ETIQUETA del tipo de aviso (el recordatorio de 1 hora antes, ver VENTANA_RECORDATORIO_MIN en
 * jobs/recordarTurnosProximos.ts), no un cronómetro en vivo.
 *
 * `reprogramacion` no tiene productor real todavía (routes/turnos.ts, PATCH /:id/reprogramar
 * sigue insertando tipo='confirmacion' — decisión documentada ahí) — el caso queda resuelto acá
 * de todos modos para que el ENUM completo (tipo_notificacion, 001_init.sql) tenga siempre un
 * texto razonable si algún productor futuro lo usa, en vez de caer al `default` genérico.
 */
export function armarMensajeNotificacion(datos: DatosMensajeNotificacion): string {
  const fechaHora = formatearFechaHoraLocal(datos.turnoInicio);

  if (datos.destinatarioEsCliente) {
    switch (datos.tipo) {
      case 'cancelacion':
        return `Tu turno con ${datos.profesionalNombre} en ${datos.negocioNombre} el ${fechaHora} fue cancelado`;
      case 'reprogramacion':
        return `Tu turno con ${datos.profesionalNombre} en ${datos.negocioNombre} fue reprogramado para el ${fechaHora}`;
      case 'recordatorio':
        return `Recordatorio: tenés un turno con ${datos.profesionalNombre} en ${datos.negocioNombre} el ${fechaHora}, en 1 hora`;
      case 'confirmacion':
      default:
        return `Tu turno con ${datos.profesionalNombre} en ${datos.negocioNombre} el ${fechaHora} fue confirmado`;
    }
  }

  switch (datos.tipo) {
    case 'cancelacion':
      return `${datos.clienteNombre} canceló su turno en ${datos.negocioNombre} el ${fechaHora}`;
    case 'reprogramacion':
      return `${datos.clienteNombre} reprogramó su turno en ${datos.negocioNombre} para el ${fechaHora}`;
    case 'recordatorio':
      return `Recordatorio: turno con ${datos.clienteNombre} en ${datos.negocioNombre} el ${fechaHora}, en 1 hora`;
    case 'confirmacion':
    default:
      return `${datos.clienteNombre} confirmó su turno en ${datos.negocioNombre} el ${fechaHora}`;
  }
}

/**
 * Asunto del email que replica una notificación de la bandeja (ampliación 2026-08-18 — envío
 * real por email vía Resend, pedido explícito del CEO; ver integraciones/email.ts). Mapeo fijo
 * por `tipo`, tal como lo definió el CEO — a diferencia de `armarMensajeNotificacion`, el asunto
 * NO depende de `destinatarioEsCliente` (mismo asunto para ambas partes de un mismo evento; el
 * cuerpo sí sigue siendo el texto de `armarMensajeNotificacion`, que cambia según quién lo recibe).
 */
export function armarAsuntoNotificacion(tipo: TipoNotificacion): string {
  switch (tipo) {
    case 'cancelacion':
      return 'Turno cancelado';
    case 'reprogramacion':
      return 'Turno reprogramado';
    case 'recordatorio':
      return 'Recordatorio de tu turno';
    case 'confirmacion':
    default:
      return 'Confirmación de tu turno';
  }
}

/** Lo que hace falta para notificar POR EMAIL a las 2 partes de un turno — ver
 *  `obtenerDatosNotificacionTurno` más abajo (ampliación 2026-08-18). */
export interface DatosNotificacionTurno {
  clienteNombre: string;
  clienteEmail: string;
  profesionalNombre: string;
  profesionalEmail: string;
  /** negocio.nombre del turno (vía turno.negocio_id) — agregado 2026-08-19, mismo motivo que
   *  `DatosMensajeNotificacion.negocioNombre` (ver ese campo más arriba). */
  negocioNombre: string;
  /** turno.inicio, ISO-8601 — mismo campo que `DatosMensajeNotificacion.turnoInicio`. */
  turnoInicio: string;
}

/**
 * Junta, en una sola lectura, todo lo que hace falta para notificar POR EMAIL a las 2 partes de
 * un turno (ampliación 2026-08-18, pedido explícito del CEO — envío real vía Resend, ver
 * integraciones/email.ts): nombre y email de cliente y profesional, el nombre del negocio (vía
 * `turno.negocio_id`, agregado 2026-08-19 — ver `DatosNotificacionTurno.negocioNombre`) y
 * `turno.inicio` (insumo de `armarMensajeNotificacion`). `turno` nunca se borra físicamente (solo
 * cambia de `estado`, ver el header de este archivo) — sigue siendo válido leerlo por `turnoId`
 * después de que la transacción que lo creó/modificó ya hizo COMMIT, que es justamente cuándo se
 * usa esto (ver cada
 * call site en routes/turnos.ts, routes/profesionales.ts y jobs/recordarTurnosProximos.ts: el
 * envío de email es un efecto secundario best-effort que corre SIEMPRE fuera de la transacción
 * principal — nunca debe poder demorarla ni arriesgar su rollback).
 *
 * Recibe un `Queryable` (mismo criterio que dominio/disponibilidad.ts) — el uso real de hoy
 * siempre pasa `pool` (nunca un `client` de una transacción ya resuelta: a esa altura ya está
 * liberado de vuelta al pool por `withTransaction`, ver db.ts), pero queda igual de genérico por
 * si algún caller futuro necesitara llamarlo dentro de una transacción todavía abierta.
 *
 * Sin contexto RLS a propósito: `turno` tiene la policy pública transitoria `turno_select_publico`,
 * `profesional` es de lectura pública, `usuario` no tiene RLS habilitada en absoluto, y `negocio`
 * tampoco (agregado 2026-08-19 — no hay ningún `ALTER TABLE negocio ENABLE ROW LEVEL SECURITY` en
 * database/migrations/001_init.sql, mismo caso que `usuario`) — mismo criterio que ya usa, por
 * ejemplo, el primer SELECT de `POST /turnos` (routes/turnos.ts) para leer `profesional` antes de
 * abrir cualquier transacción. No se filtra por ningún estado de `turno` (a diferencia de otras
 * lecturas de este backend): para este uso puntual (arma el texto de un evento que YA pasó —
 * confirmación/cancelación/etc.) el estado actual de la fila es irrelevante, solo importan sus
 * datos descriptivos.
 *
 * `JOIN negocio` directo por `t.negocio_id` (agregado 2026-08-19) — no hace falta pasar por
 * `profesional`/`negocio_profesional` (N:M): `turno.negocio_id` ya es una columna propia de
 * `turno` (ver database/migrations/001_init.sql, "turno.negocio_id ahora sale de
 * servicio.negocio_id" en el comentario de la generalización 1:1→N:M) y es `NOT NULL REFERENCES
 * negocio(id)` — un `INNER JOIN` es seguro acá, nunca puede dejar afuera un turno existente por
 * `negocio_nombre` nulo.
 */
export async function obtenerDatosNotificacionTurno(
  db: Queryable,
  turnoId: string
): Promise<DatosNotificacionTurno | undefined> {
  const result = await db.query(
    `SELECT t.inicio AS turno_inicio,
            uc.nombre AS cliente_nombre, uc.email AS cliente_email,
            up.nombre AS profesional_nombre, up.email AS profesional_email,
            ng.nombre AS negocio_nombre
     FROM turno t
     JOIN usuario uc ON uc.id = t.cliente_id
     JOIN profesional p ON p.id = t.profesional_id
     JOIN usuario up ON up.id = p.usuario_id
     JOIN negocio ng ON ng.id = t.negocio_id
     WHERE t.id = $1`,
    [turnoId]
  );
  const fila = result.rows[0] as
    | {
        turno_inicio: string;
        cliente_nombre: string;
        cliente_email: string;
        profesional_nombre: string;
        profesional_email: string;
        negocio_nombre: string;
      }
    | undefined;
  if (!fila) return undefined;
  return {
    turnoInicio: fila.turno_inicio,
    clienteNombre: fila.cliente_nombre,
    clienteEmail: fila.cliente_email,
    profesionalNombre: fila.profesional_nombre,
    profesionalEmail: fila.profesional_email,
    negocioNombre: fila.negocio_nombre,
  };
}
