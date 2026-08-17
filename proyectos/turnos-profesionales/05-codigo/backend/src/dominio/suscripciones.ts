// Suscripción "Turnario Pro" (HU-29/E11, 2026-08-14) — freemium POR NEGOCIO. Ver DBA:
// ../../database/migrations/001_init.sql (bloque "Suscripción 'Turnario Pro'") y
// ../../../03-arquitectura/modelo-datos.md §2novies para el modelado completo. Este módulo junta
// la lógica de negocio que usan los 3+ call sites que necesitan saber "¿este negocio puede hacer
// X, o ya llegó al límite del plan gratis?" — mismo criterio de extracción a `dominio/` que
// `disponibilidad.ts` (compartido por profesionales.ts/turnos.ts) — no se duplica esta lógica en
// cada router.
//
// Los 2 límites del plan gratis (backlog.md HU-29, tabla de E11) — Turnario Pro los levanta a
// "ilimitados":
//   - 1 profesional ACTIVO por negocio (negocio_profesional.activo = true).
//   - 60 turnos 'confirmado' por MES — el mes del `turno.inicio` (fecha de la cita), no de
//     `creado_en` (cuándo se cargó/confirmó la fila) — mismo criterio que dejó documentado DBA
//     junto al índice `idx_turno_negocio_confirmado_inicio` (001_init.sql): "60, ~2/día" describe
//     densidad de agenda de ESE mes, no volumen de altas. Un turno cargado hoy para el mes que
//     viene consume cupo del mes que viene, no el de hoy.
import { PoolClient } from 'pg';

export const LIMITE_TURNOS_CONFIRMADOS_MES_GRATIS = 60;
export const LIMITE_PROFESIONALES_ACTIVOS_GRATIS = 1;

export type PlanNegocio = 'gratis' | 'turnario_pro';
export type PeriodoSuscripcion = 'mensual' | 'anual';
export type EstadoSuscripcionNegocio = 'activa' | 'vencida' | 'cancelada';

export interface EstadoSuscripcion {
  plan: PlanNegocio;
  periodo: PeriodoSuscripcion | null;
  vencimiento: string | null; // ISO-8601 (ver db.ts — TIMESTAMPTZ normalizado a string)
  estado: EstadoSuscripcionNegocio;
}

/** Negocio sin fila propia en `suscripcion_negocio` todavía — tratado como 'gratis'/'activa'
 *  implícito, NUNCA como "sin límite" (criterio explícito de DBA, ver 001_init.sql: un negocio
 *  nuevo puede no tener fila todavía si nada la creó de forma perentoria — ningún flujo de este
 *  ciclo agrega esa fila a `POST /auth/registro-negocio`, queda como recomendación pendiente de
 *  DBA para un ciclo futuro — este fallback cubre ese hueco de forma segura mientras tanto). */
const ESTADO_SIN_FILA: EstadoSuscripcion = { plan: 'gratis', periodo: null, vencimiento: null, estado: 'activa' };

/**
 * Lee el estado de suscripción de un negocio DENTRO de una transacción ya abierta con
 * `withTransaction` — requiere `PoolClient` (no `pool`/`Queryable` genérico) porque fija
 * `app.negocio_id` con `SET LOCAL` (vía `set_config(..., true)`, scope de la transacción actual)
 * inmediatamente antes de leer.
 *
 * Por qué hace falta fijar `app.negocio_id` acá, explícitamente, en vez de confiar en el
 * contexto que ya haya pasado el caller a `withTransaction`: `suscripcion_negocio` tiene RLS
 * FORCE con SELECT acotado a STAFF del negocio (administrador o profesional activo — ver las 3
 * policies "de DBA" en migrations/001_init.sql). Eso alcanza para los call sites donde quien
 * llama YA es staff (`GET /negocios/:id/plan`, `POST /negocios/:id/profesionales` — ambos
 * corren con `app.usuario_id` = administrador/profesional). Pero el chequeo del límite de 60
 * turnos/mes tiene que poder correr TAMBIÉN dentro de `POST /turnos` (turnos.ts), que autentica
 * con `requireAuth('cliente')` — el cliente que reserva NUNCA es administrador ni profesional de
 * ESE negocio, así que ninguna de esas 3 policies lo habilita, sin importar el negocio. Backend
 * agregó una 4ta policy para este caso puntual,
 * `[BACKEND] suscripcion_negocio_select_negocio_en_contexto` (ver migrations/001_init.sql,
 * pendiente de ratificación por DBA — mismo mecanismo ya usado para
 * `profesional_update_propio_duracion_cita`/`turno_select_publico`/`notificacion_insert_job_sistema`),
 * acotada por `negocio_id = app.negocio_id` — de ahí que esta función fije esa variable de sesión
 * al negocio EXACTO que está chequeando (nunca un valor sin validar: siempre
 * `servicio.negocio_id` u otro valor ya resuelto server-side), sin depender de qué haya seteado
 * el resto del handler. Sobreescribir `app.negocio_id` acá es seguro para todos los call sites de
 * hoy: ninguna otra policy de la migración lo usa (ver `ContextoRls.negocioId` en db.ts), así que
 * pisarlo no puede romper ninguna sentencia posterior de la misma transacción.
 */
export async function obtenerEstadoSuscripcion(client: PoolClient, negocioId: string): Promise<EstadoSuscripcion> {
  await client.query('SELECT set_config($1, $2, true)', ['app.negocio_id', negocioId]);
  const result = await client.query(
    'SELECT plan, periodo, vencimiento, estado FROM suscripcion_negocio WHERE negocio_id = $1',
    [negocioId]
  );
  return (result.rows[0] as EstadoSuscripcion | undefined) ?? ESTADO_SIN_FILA;
}

/**
 * Acceso EFECTIVO a las funciones de Turnario Pro — mismo criterio documentado por DBA
 * (001_init.sql, bloque "Suscripción 'Turnario Pro'"): NO alcanza con `plan = 'turnario_pro'`
 * solo (ese valor puede quedar así de forma permanente, como registro de "alguna vez pagó",
 * incluso mucho después de vencer/cancelar) — hace falta además no haber pasado `vencimiento`.
 * No es una regla forzada por la base de datos (ningún CHECK ni job la recalcula) — vive acá, en
 * la capa de aplicación, a propósito.
 *
 * Corrección (2026-08-15, encontrada al construir la pantalla de Turnario Pro del lado
 * Administrador — épica E15): `estado` acepta 'activa' **o** 'cancelada', nunca 'vencida'. Antes
 * exigía `estado === 'activa'` a secas, lo que cortaba el acceso apenas se cancelaba —
 * contradice tanto el comentario de `PATCH /:id/suscripcion/cancelar` (negocios.ts: "conserva el
 * acceso hasta que venza lo ya pagado, patrón común de SaaS") como la propia nota de DBA sobre
 * 'cancelada' ("puede seguir con acceso hasta que venza lo ya pagado"). Con ningún job de este
 * ciclo escribiendo 'vencida' todavía (ver nota de DBA), el chequeo de `vencimiento` de abajo ya
 * cubre la expiración real en ambos casos — excluir 'vencida' explícitamente es defensa a futuro,
 * para el día que sí exista ese job.
 */
export function tieneAccesoTurnarioPro(estadoSuscripcion: EstadoSuscripcion, ahora: Date = new Date()): boolean {
  return (
    estadoSuscripcion.plan === 'turnario_pro' &&
    estadoSuscripcion.estado !== 'vencida' &&
    estadoSuscripcion.vencimiento !== null &&
    new Date(estadoSuscripcion.vencimiento).getTime() >= ahora.getTime()
  );
}

/** Medianoche LOCAL del 1ro del mes que contiene `fecha` — mismo criterio de "hora local del
 *  servidor, sin librería de zonas horarias" que `inicioDelDiaLocal` (dominio/disponibilidad.ts;
 *  este proyecto no modela zona horaria por negocio/usuario en ningún otro lado tampoco). */
export function inicioDelMesLocal(fecha: Date): Date {
  const copia = new Date(fecha);
  copia.setDate(1);
  copia.setHours(0, 0, 0, 0);
  return copia;
}

/** Medianoche LOCAL del 1ro del mes SIGUIENTE al que contiene `fecha` — límite superior
 *  (exclusivo) de la ventana "turnos confirmados de ese mes". */
export function inicioDelMesSiguienteLocal(fecha: Date): Date {
  const inicio = inicioDelMesLocal(fecha);
  inicio.setMonth(inicio.getMonth() + 1);
  return inicio;
}

/**
 * Cuenta turnos `estado = 'confirmado'` de un negocio cuyo `inicio` cae dentro del mes que
 * contiene `fechaReferencia`. Usa exactamente la forma de query para la que DBA diseñó
 * `idx_turno_negocio_confirmado_inicio` (negocio_id, inicio) WHERE estado='confirmado' —
 * ver 001_init.sql. `client` (no `pool`): corre dentro de la misma transacción que el resto del
 * chequeo para que el plan y el uso se lean como un snapshot consistente. A diferencia de
 * `suscripcion_negocio`, `turno` sí tiene hoy una policy de SELECT pública activa
 * (`turno_select_publico`, transitoria — ver migrations/001_init.sql), así que esta lectura en
 * particular no depende de la policy nueva de este ciclo — no hace falta (ni se hace) fijar
 * `app.negocio_id` acá.
 */
export async function contarTurnosConfirmadosDelMes(
  client: PoolClient,
  negocioId: string,
  fechaReferencia: Date
): Promise<number> {
  const desde = inicioDelMesLocal(fechaReferencia);
  const hasta = inicioDelMesSiguienteLocal(fechaReferencia);
  const result = await client.query(
    `SELECT count(*)::int AS total FROM turno
     WHERE negocio_id = $1 AND estado = 'confirmado' AND inicio >= $2 AND inicio < $3`,
    [negocioId, desde.toISOString(), hasta.toISOString()]
  );
  return (result.rows[0]?.total as number) ?? 0;
}

/** Profesionales ACTIVOS (`negocio_profesional.activo = true`) de un negocio — sin índice nuevo
 *  (DBA: ya cubierto por la PK compuesta `(negocio_id, profesional_id)`, ver 001_init.sql). */
export async function contarProfesionalesActivos(client: PoolClient, negocioId: string): Promise<number> {
  const result = await client.query(
    'SELECT count(*)::int AS total FROM negocio_profesional WHERE negocio_id = $1 AND activo = true',
    [negocioId]
  );
  return (result.rows[0]?.total as number) ?? 0;
}

export interface ResultadoChequeoLimite {
  permitido: boolean;
  /** Presente solo cuando `permitido = false` — mensaje ya redactado para devolver tal cual en
   *  la respuesta HTTP (ver `cuerpoLimitePlanAlcanzado` más abajo). */
  motivo?: string;
}

/**
 * Chequeo del límite "60 turnos confirmados/mes" (HU-29). Se salta COMPLETO (ni siquiera cuenta)
 * si el negocio tiene acceso efectivo a Turnario Pro — ver `tieneAccesoTurnarioPro`.
 *
 * Pensado para llamarse INMEDIATAMENTE ANTES de cualquier sentencia que deje un turno en estado
 * 'confirmado' — no en el momento en que se decide/planea crear el turno. Ver
 * `exigirLimiteTurnosConfirmadosDelMes` (más abajo, la variante que LANZA) para los call sites de
 * `POST /turnos` y `POST /profesionales/:id/turnos` (turnos.ts/profesionales.ts — el turno nace
 * DIRECTO en 'confirmado', sin seña de por medio). Esta misma función (la que DEVUELVE un
 * resultado, no la que lanza) es la que usa, en cambio, `POST /webhooks/mercadopago`
 * (src/routes/webhooks.ts, 2026-08-17) al confirmar un pago con seña — ver el comentario ahí para
 * el porqué de esa variante en ese call site puntual (en resumen: ahí el pago ya está cobrado por
 * Mercado Pago antes de correr este chequeo, y no hay ningún ROLLBACK que pueda deshacer eso).
 */
export async function verificarLimiteTurnosConfirmadosDelMes(
  client: PoolClient,
  negocioId: string,
  inicioTurno: Date
): Promise<ResultadoChequeoLimite> {
  const estadoSuscripcion = await obtenerEstadoSuscripcion(client, negocioId);
  if (tieneAccesoTurnarioPro(estadoSuscripcion)) return { permitido: true };

  const usados = await contarTurnosConfirmadosDelMes(client, negocioId, inicioTurno);
  if (usados >= LIMITE_TURNOS_CONFIRMADOS_MES_GRATIS) {
    return {
      permitido: false,
      motivo: `Plan gratis: este negocio ya alcanzó el límite de ${LIMITE_TURNOS_CONFIRMADOS_MES_GRATIS} turnos confirmados para este mes. Suscribite a Turnario Pro para turnos confirmados ilimitados.`,
    };
  }
  return { permitido: true };
}

/** Ver `verificarLimiteTurnosConfirmadosDelMes` — versión que lanza en vez de devolver un
 *  resultado, para los call sites que ya usan el patrón try/catch de `withTransaction` +
 *  `err.code === '23505'` (POST /turnos y POST /profesionales/:id/turnos, ver esos archivos):
 *  agregar UN branch más al mismo catch existente, sin reestructurar esos handlers al patrón de
 *  "resultado discriminado por tipo" que sí usan otros endpoints de este backend (ej.
 *  POST /negocios/:id/profesionales). `withTransaction` hace ROLLBACK normalmente ante cualquier
 *  excepción — lanzar acá antes del INSERT dejar la transacción sin ningún efecto, igual que
 *  cualquier otro error de esa misma transacción. */
export class LimitePlanGratisError extends Error {
  constructor(motivo: string) {
    super(motivo);
    this.name = 'LimitePlanGratisError';
  }
}

export async function exigirLimiteTurnosConfirmadosDelMes(
  client: PoolClient,
  negocioId: string,
  inicioTurno: Date
): Promise<void> {
  const resultado = await verificarLimiteTurnosConfirmadosDelMes(client, negocioId, inicioTurno);
  if (!resultado.permitido) throw new LimitePlanGratisError(resultado.motivo!);
}

/**
 * Chequeo del límite "1 profesional activo por negocio" (HU-29) — `POST /negocios/:id/profesionales`
 * (negocios.ts, HU-02). Mismo criterio de saltarse completo con Turnario Pro que el chequeo de
 * turnos.
 */
export async function verificarLimiteProfesionalesActivos(
  client: PoolClient,
  negocioId: string
): Promise<ResultadoChequeoLimite> {
  const estadoSuscripcion = await obtenerEstadoSuscripcion(client, negocioId);
  if (tieneAccesoTurnarioPro(estadoSuscripcion)) return { permitido: true };

  const activos = await contarProfesionalesActivos(client, negocioId);
  if (activos >= LIMITE_PROFESIONALES_ACTIVOS_GRATIS) {
    return {
      permitido: false,
      motivo: `Plan gratis: este negocio ya tiene ${LIMITE_PROFESIONALES_ACTIVOS_GRATIS} profesional activo. Suscribite a Turnario Pro para agregar profesionales ilimitados.`,
    };
  }
  return { permitido: true };
}

/**
 * Cuerpo de respuesta uniforme para los 3 call sites que bloquean por límite del plan gratis
 * (GET/POST en negocios.ts, POST en profesionales.ts, POST en turnos.ts). `requiere_turnario_pro`
 * (no solo el mensaje en `error`): mismo criterio que `requiere_confirmacion_password` en
 * auth.ts — un flag booleano explícito para que Mobile pueda reaccionar (ej. mostrar el paywall
 * de Turnario Pro) sin tener que parsear el texto de `error`.
 *
 * Código de estado elegido para los 3 call sites: `402 Payment Required`. Se evaluó reusar `403`
 * (ya el código dominante de esta API para "no autorizado") pero se prefirió `402` porque el
 * motivo de rechazo acá es categóricamente distinto: `403` en el resto de este backend siempre
 * significa "tu identidad/rol no te habilita a esto, sin importar nada más" (ej. "no podés
 * administrar recursos de otro negocio"); acá la identidad/rol SÍ están habilitados — la acción
 * falla únicamente porque el PLAN del negocio no la permite en este volumen, y pagar la habilita
 * de inmediato sin cambiar de identidad. `402` es semánticamente exacto para ese caso ("hace
 * falta pagar para continuar") y le da a Mobile/QA una señal inequívoca para distinguir ambos
 * escenarios sin depender de parsear `error` — se documenta acá porque es una desviación
 * deliberada del código dominante de esta API, no un descuido de consistencia.
 */
export function cuerpoLimitePlanAlcanzado(motivo: string) {
  return { error: motivo, requiere_turnario_pro: true };
}
