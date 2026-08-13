// Helpers de dominio para la bandeja de notificaciones (HU-14b/HU-25) — extraídos a un módulo
// propio (mismo criterio que dominio/disponibilidad.ts, lógica compartida sin dependencia de
// Express/HTTP): hoy solo lo usa GET /notificaciones (src/routes/notificaciones.ts), pero el
// armado de texto es independiente del transporte y puede reutilizarse a futuro (ej. el día que
// integraciones/notificaciones.ts tenga un proveedor real de push y necesite el mismo texto).
//
// Decisión heredada de DBA (ver database/migrations/001_init.sql, bloque "Bandeja de
// notificaciones", y 004_notificaciones.sql): la fila `notificacion` NO guarda texto/nombre/hora
// "congelados" — se arman acá, en el momento de leer, a partir de los datos de `turno` (que
// nunca se borra físicamente, solo cambia de `estado` — la referencia por turno_id sigue siendo
// válida para siempre).

/** Espejo de tipo_notificacion (database/migrations/001_init.sql). */
export type TipoNotificacion = 'confirmacion' | 'recordatorio' | 'cancelacion' | 'reprogramacion';

export interface DatosMensajeNotificacion {
  tipo: TipoNotificacion;
  /** usuario.nombre del cliente del turno. */
  clienteNombre: string;
  /** usuario.nombre del profesional del turno (vía profesional.usuario_id). */
  profesionalNombre: string;
  /** turno.inicio, ISO-8601. */
  turnoInicio: string;
  /** true si el DESTINATARIO de esta notificación puntual es el cliente del turno. Hoy ningún
   *  productor real genera este caso — los 4 INSERT existentes (POST /turnos, PATCH
   *  /:id/reprogramar, PATCH /:id/cancelar en routes/turnos.ts; el job en
   *  jobs/recordarTurnosProximos.ts) siempre apuntan al profesional, ver el razonamiento de DBA
   *  en 001_init.sql ("es la bandeja del PROFESIONAL") — pero el mensaje debe hablar desde la
   *  perspectiva de QUIEN LO RECIBE, no asumir siempre "destinatario = profesional", para no
   *  quedar mal armado el día que exista un productor que notifique al cliente. */
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
 * Arma, en español, el texto de una notificación — mismo copy exacto que mapa-pantallas.md
 * §5.15 para los 3 tipos que hoy tienen productor real: "María Pérez confirmó su turno de las
 * 10:00" / "Recordatorio: turno con Juan Ramírez en 1 hora" / "Sofía Cano canceló su turno de
 * las 16:00".
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
  const hora = formatearHoraLocal(datos.turnoInicio);

  if (datos.destinatarioEsCliente) {
    switch (datos.tipo) {
      case 'cancelacion':
        return `Tu turno con ${datos.profesionalNombre} de las ${hora} fue cancelado`;
      case 'reprogramacion':
        return `Tu turno con ${datos.profesionalNombre} fue reprogramado para las ${hora}`;
      case 'recordatorio':
        return `Recordatorio: tenés un turno con ${datos.profesionalNombre} en 1 hora`;
      case 'confirmacion':
      default:
        return `Tu turno con ${datos.profesionalNombre} de las ${hora} fue confirmado`;
    }
  }

  switch (datos.tipo) {
    case 'cancelacion':
      return `${datos.clienteNombre} canceló su turno de las ${hora}`;
    case 'reprogramacion':
      return `${datos.clienteNombre} reprogramó su turno para las ${hora}`;
    case 'recordatorio':
      return `Recordatorio: turno con ${datos.clienteNombre} en 1 hora`;
    case 'confirmacion':
    default:
      return `${datos.clienteNombre} confirmó su turno de las ${hora}`;
  }
}
