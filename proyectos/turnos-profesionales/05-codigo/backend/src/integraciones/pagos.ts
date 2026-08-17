import crypto from 'crypto';

/**
 * Integración de pagos (D2/RN10) — Mercado Pago Checkout Pro (decisión de CTO IA, ver
 * ../../03-arquitectura/lineamientos-tecnicos.md §1).
 *
 * (2026-08-17, Integraciones) Cierre del HALLAZGO que documentaba este archivo hasta este ciclo
 * (Backend, 2026-08-14): `pagoProvider` deja de ser `MockPagoProvider` y pasa a un cliente real
 * contra la API REST de Mercado Pago (preferencias de Checkout Pro + redirect a
 * init_point/sandbox_init_point — sin SDK, sin Checkout API/Bricks). Los dos callers que
 * faltaban para que un turno `'pendiente_de_pago'` (RN10) pueda llegar a `'confirmado'` los
 * agrega Backend en este mismo ciclo, en paralelo, en sus propios archivos: `POST
 * /turnos/:id/pago` (turnos.ts, llama a `crearIntencion`) y `POST /webhooks/mercadopago`
 * (webhooks.ts, llama a `validarWebhook` + `obtenerPagoMercadoPago` de más abajo) — la lógica de
 * negocio de esos endpoints (incluido el chequeo de límite de Turnario Pro/HU-29) vive ahí, no
 * acá.
 */

// ============================================================================
// Contrato — no cambiar la FORMA de `IntencionDePago`/`PagoProvider` sin coordinar con Backend
// (routes/turnos.ts y routes/webhooks.ts ya integran contra esta forma exacta, en paralelo).
// ============================================================================

export interface IntencionDePago {
  id: string;
  monto: number;
  urlCheckout: string;
}

export interface PagoProvider {
  crearIntencion(turnoId: string, monto: number): Promise<IntencionDePago>;
  validarWebhook(payload: unknown, firma: string | undefined): boolean;
}

/**
 * El webhook de Mercado Pago (`POST /webhooks/mercadopago`, ver webhooks.ts) solo trae el ID del
 * pago (`data.id`), no el objeto completo — `obtenerPagoMercadoPago` (más abajo) lo resuelve. NO
 * forma parte de `PagoProvider` a propósito (esa interfaz no se toca).
 */
export interface PagoConfirmado {
  turnoId: string; // = external_reference, tal cual lo mandó crearIntencion.
  estadoPago: string; // status crudo de MP: 'approved' | 'pending' | 'rejected' | 'in_process' | 'cancelled' | 'refunded' | ...
  montoAcreditado: number;
  paymentId: string;
}

// ============================================================================
// Configuración — MP_ACCESS_TOKEN (llamadas a la API) y MP_WEBHOOK_SECRET (firma) se leen
// perezosamente, DENTRO de cada método, nunca acá arriba ni en el constructor de
// `MercadoPagoProvider`. `pagoProvider` (al final de este archivo) es un singleton de MÓDULO
// construido al importar este archivo — si el constructor o el scope de módulo leyeran/
// exigieran estas variables, su ausencia (todavía el caso hoy: el CEO no dio de alta
// credenciales de Mercado Pago) tiraría abajo el arranque de TODO el backend, no solo los
// endpoints de pago. Mismo criterio que `GOOGLE_CLIENT_ID` en src/routes/auth.ts (ver
// `verificarIdTokenGoogle`): opt-in explícito, nunca un crash silencioso al importar.
// ============================================================================

/**
 * Lanzado por `crearIntencion`/`obtenerPagoMercadoPago` cuando falta configuración (hoy, solo
 * `MP_ACCESS_TOKEN`) — mismo espíritu que `LimitePlanGratisError` (dominio/suscripciones.ts): una
 * clase de error propia y exportada para que quien llama pueda `instanceof`-chequearla si lo
 * necesita, en vez de parsear un mensaje de texto. Backend (turnos.ts/webhooks.ts) hoy la atrapa
 * con un `catch` genérico y responde 503 — igual que ya hace con Google sin configurar.
 *
 * `validarWebhook` NUNCA lanza esto (ni ningún otro error) — ver el comentario de ese método más
 * abajo: su contrato es devolver `false` ante secreto no configurado, no lanzar.
 */
export class MercadoPagoNoConfiguradoError extends Error {
  constructor(variable: string) {
    super(`Mercado Pago no está configurado en este entorno (falta ${variable})`);
    this.name = 'MercadoPagoNoConfiguradoError';
  }
}

function obtenerAccessToken(): string {
  const token = process.env.MP_ACCESS_TOKEN;
  if (!token) throw new MercadoPagoNoConfiguradoError('MP_ACCESS_TOKEN');
  return token;
}

// ============================================================================
// Implementación real — API REST de Mercado Pago directa (`fetch` nativo de Node 22, ver
// Dockerfile de este backend — sin agregar el SDK npm `mercadopago`, ver resumen de este cambio
// para la justificación) + `crypto` built-in para el HMAC del webhook.
// ============================================================================

const MP_API_BASE = 'https://api.mercadopago.com';

interface MercadoPagoPreferenceResponse {
  id?: string;
  init_point?: string;
  sandbox_init_point?: string;
}

interface MercadoPagoPaymentResponse {
  id?: number;
  status?: string;
  external_reference?: string;
  transaction_amount?: number;
}

/** Constructor trivial a propósito (no lee ninguna variable de entorno) — ver el bloque de
 *  "Configuración" más arriba: cada método valida la suya recién cuando se invoca. */
export class MercadoPagoProvider implements PagoProvider {
  /**
   * Crea una preferencia de Checkout Pro (`POST /checkout/preferences/`) y devuelve la URL de
   * checkout para redirigir al cliente. Endpoint, body mínimo (`items[].id/title/quantity/
   * unit_price` + `external_reference`) y campos de respuesta (`id`/`init_point`/
   * `sandbox_init_point`) verificados 2026-08-17 contra el código fuente actual del SDK oficial
   * de Mercado Pago para Node.js (github.com/mercadopago/sdk-nodejs, rama `master` —
   * src/clients/preference/create/index.ts, src/clients/preference/commonTypes.ts,
   * src/clients/commonTypes.ts `Items`, src/utils/config/index.ts `AppConfig.BASE_URL`): las
   * páginas de Referencia de API (developers.mercadopago.com/reference/...) no estuvieron
   * accesibles durante esta verificación (404 en ambas rutas probadas) — se usó el propio código
   * fuente del SDK oficial que la documentación pública recomienda, la fuente más autorizada
   * disponible en su lugar.
   *
   * `currency_id` del item se deja SIN especificar a propósito: es opcional (ver `Items` en el
   * SDK) y, si se omite, Mercado Pago usa la moneda de la cuenta/sitio del vendedor — este
   * proyecto no modela columna `moneda` en `pago` (migrations/001_init.sql) ni tiene ninguna
   * convención previa de moneda fija, así que no corresponde inventar/hardcodear un ISO 4217 acá.
   *
   * `notification_url` NO se manda en el body, a propósito: la documentación oficial de webhooks
   * (mercadopago.com.ar/developers/es/docs/your-integrations/notifications/webhooks, sección "1.
   * Indicar URLs de notificación y configurar eventos", verificada 2026-08-17) confirma que se
   * puede configurar la URL de notificaciones a NIVEL DE APLICACIÓN desde "Tus integraciones" >
   * Webhooks > Configurar notificaciones (con URLs separadas para prueba/producción) — y que una
   * URL puesta en la preferencia individual tendría prioridad por sobre esa configuración de
   * aplicación. Por eso, precisamente, no se manda ninguna acá: el CEO carga esa URL UNA sola vez
   * en el dashboard de Mercado Pago al dar de alta las credenciales, junto con el secreto de
   * firma (`MP_WEBHOOK_SECRET`). No existe (ni se inventa acá) ninguna variable de entorno
   * `BASE_URL`/`PUBLIC_URL` en este proyecto para armar esa URL en runtime — confirmado contra
   * package.json/.env.example/render.yaml, no asumido.
   */
  async crearIntencion(turnoId: string, monto: number): Promise<IntencionDePago> {
    const accessToken = obtenerAccessToken();

    const response = await fetch(`${MP_API_BASE}/checkout/preferences/`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        items: [
          { id: turnoId, title: 'Seña de turno — Turnos Profesionales', quantity: 1, unit_price: monto },
        ],
        external_reference: turnoId,
      }),
    });

    if (!response.ok) {
      const detalle = await response.text().catch(() => '');
      throw new Error(
        `Mercado Pago respondió ${response.status} al crear la preferencia de pago del turno ${turnoId}: ${detalle}`
      );
    }

    const preferencia = (await response.json()) as MercadoPagoPreferenceResponse;
    if (!preferencia.id) {
      throw new Error(`Mercado Pago no devolvió un id de preferencia válido para el turno ${turnoId}`);
    }

    // Credenciales de prueba (prefijo "TEST-", ver documentación oficial de credenciales de
    // Mercado Pago) -> `sandbox_init_point`; credenciales de producción -> `init_point`. Si el
    // campo "correcto" según esta regla faltara en la respuesta, se cae al otro antes de fallar
    // — la propia respuesta de Mercado Pago manda por sobre la heurística del prefijo.
    const esCredencialDePrueba = accessToken.startsWith('TEST-');
    const urlCheckout =
      (esCredencialDePrueba ? preferencia.sandbox_init_point : preferencia.init_point) ??
      preferencia.init_point ??
      preferencia.sandbox_init_point;
    if (!urlCheckout) {
      throw new Error(
        `Mercado Pago no devolvió ninguna URL de checkout (init_point/sandbox_init_point) para el turno ${turnoId}`
      );
    }

    return { id: preferencia.id, monto, urlCheckout };
  }

  /**
   * Valida la firma HMAC-SHA256 del webhook de Mercado Pago — header `x-signature`, formato
   * `ts=<epoch_segundos>,v1=<hex>` (solo `v1` existe hoy; si Mercado Pago migrara a una versión
   * nueva del esquema de firma haría falta revisar esto).
   *
   * El "manifest" que se firma NO está expuesto en la página pública de webhooks tal como quedó
   * verificada 2026-08-17 (mercadopago.com.ar/developers/es/docs/your-integrations/notifications/
   * webhooks, sección "2. Validar origen de una notificación") — esa página hoy documenta
   * ÚNICAMENTE el uso de los SDKs oficiales (`WebhookSignatureValidator.validate(...)`, con
   * ejemplo de código para Node.js/PHP/Python/Go/C#/Java/Ruby) sin exponer el algoritmo interno.
   * Se reconstruyó acá, punto por punto, contra el código fuente real y actual de ESE MISMO
   * validador oficial (github.com/mercadopago/sdk-nodejs, rama `master`, verificado 2026-08-17,
   * src/utils/webhook/index.ts — paquete npm `mercadopago`, la fuente que la propia
   * documentación pública recomienda usar): manifest = `id:{dataId};request-id:{requestId};ts:{ts};`
   * (cada segmento `id:.../request-id:...` se omite del todo si ese valor no vino; `ts` siempre
   * va), HMAC-SHA256 con `MP_WEBHOOK_SECRET`, hex, comparado en tiempo constante.
   *
   * NO usa el body crudo del request en ningún punto — el manifest se arma solo con `dataId`
   * (acá, el id del pago que ya extrajo Backend de query/body de la notificación — ver `POST
   * /webhooks/mercadopago`), el header `x-request-id` y `ts` (parseado del propio
   * `x-signature`). El `express.json()` global de app.ts NO es un problema para esta validación
   * (confirmado contra el algoritmo real, no asumido).
   *
   * `false` ante CUALQUIER problema (firma ausente, header malformado, versión de firma no
   * reconocida, HMAC que no matchea, o `MP_WEBHOOK_SECRET` no configurado) — a propósito NUNCA
   * lanza (a diferencia de `crearIntencion`/`obtenerPagoMercadoPago`): el contrato de este método
   * es un booleano simple para que quien llama pueda hacer `if (!pagoProvider.validarWebhook(...))
   * return 401` sin un try/catch adicional, y para que "no puedo verificar la firma" y "la firma
   * es inválida" se traten exactamente igual del lado de afuera (fail-closed).
   */
  validarWebhook(payload: unknown, firma: string | undefined): boolean {
    const secret = process.env.MP_WEBHOOK_SECRET;
    if (!secret) return false;
    if (!firma || !firma.trim()) return false;

    const { ts, v1 } = parsearEncabezadoFirma(firma);
    if (!ts || !/^\d+$/.test(ts) || !v1) return false;

    // [BAJO-1, revisión de Security 2026-08-17] Ventana anti-replay: sin esto, una request HTTP
    // capturada una vez (headers + body) con firma válida se podía reproducir tal cual en
    // cualquier momento futuro y seguía pasando esta validación (el manifest firma `ts`, pero
    // nada acá comparaba ese valor contra la hora actual). Impacto ya estaba acotado por diseño
    // (el estado del pago NUNCA sale del payload de la notificación — `obtenerPagoMercadoPago`
    // siempre lo re-consulta en vivo contra la API de Mercado Pago, ver ese método) pero agregar
    // la ventana es defensa en profundidad barata. 5 minutos de tolerancia en cada sentido
    // (relojes no perfectamente sincronizados) — no viene de ninguna doc oficial de Mercado Pago
    // consultada en esta verificación (no se encontró una ventana recomendada publicada), es un
    // valor conservador propio.
    const TOLERANCIA_REPLAY_SEGUNDOS = 5 * 60;
    const tsNumero = Number(ts);
    const ahoraSegundos = Date.now() / 1000;
    if (Math.abs(ahoraSegundos - tsNumero) > TOLERANCIA_REPLAY_SEGUNDOS) return false;

    const { dataId, requestId } = extraerCamposPayload(payload);
    const manifest = construirManifestFirma(dataId, requestId, ts);
    const hashCalculado = crypto.createHmac('sha256', secret).update(manifest).digest('hex');

    return compararEnTiempoConstante(hashCalculado, v1);
  }
}

/** `ts=<segundos>,v1=<hex>` -> `{ ts, v1 }`. Claves comparadas en minúscula (igual que el
 *  validador oficial); pares sin `=` o con valor vacío se ignoran. */
function parsearEncabezadoFirma(header: string): { ts?: string; v1?: string } {
  let ts: string | undefined;
  let v1: string | undefined;
  for (const parte of header.split(',')) {
    const igual = parte.indexOf('=');
    if (igual === -1) continue;
    const clave = parte.slice(0, igual).trim().toLowerCase();
    const valor = parte.slice(igual + 1).trim();
    if (!valor) continue;
    if (clave === 'ts') ts = valor;
    else if (clave === 'v1') v1 = valor;
  }
  return { ts, v1 };
}

/** `id:{dataId};request-id:{requestId};ts:{ts};` — cada par se omite del todo si su valor es
 *  `undefined` (`ts` siempre está presente en este punto, ya validado por el caller). */
function construirManifestFirma(dataId: string | undefined, requestId: string | undefined, ts: string): string {
  const partes: string[] = [];
  if (dataId) partes.push(`id:${dataId}`);
  if (requestId) partes.push(`request-id:${requestId}`);
  partes.push(`ts:${ts}`);
  return partes.join(';') + ';';
}

/** `payload` es `unknown` a propósito (ver contrato) — Backend arma `{ dataId, requestId }`
 *  (`POST /webhooks/mercadopago`, ver webhooks.ts). Cualquier forma inesperada (no objeto, campos
 *  ausentes o de otro tipo) se trata como "ese campo no vino", nunca como error de parseo — el
 *  manifest resultante simplemente no va a matchear la firma real de Mercado Pago (fail-closed,
 *  no hace falta un chequeo de forma más estricto). */
function extraerCamposPayload(payload: unknown): { dataId?: string; requestId?: string } {
  if (typeof payload !== 'object' || payload === null) return {};
  const objeto = payload as Record<string, unknown>;
  return { dataId: normalizarCampo(objeto.dataId), requestId: normalizarCampo(objeto.requestId) };
}

function normalizarCampo(valor: unknown): string | undefined {
  if (typeof valor !== 'string') return undefined;
  const recortado = valor.trim();
  return recortado.length > 0 ? recortado : undefined;
}

/** Comparación de hashes hex en tiempo constante (mitiga timing attacks) — mismo mecanismo que
 *  usa el validador oficial (`crypto.timingSafeEqual`). Longitudes de buffer distintas ya
 *  implican strings distintos: se devuelve `false` sin comparar bytes (`timingSafeEqual` de Node
 *  lanza si los buffers no miden lo mismo, en vez de devolver `false`). */
function compararEnTiempoConstante(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

export const pagoProvider: PagoProvider = new MercadoPagoProvider();

/**
 * GET `/v1/payments/:id` — devuelve el pago completo para un `paymentId` ya autenticado por
 * `validarWebhook` (único caller hoy, ver `POST /webhooks/mercadopago` en webhooks.ts). Endpoint
 * y campos de respuesta (`id`, `status`, `external_reference`, `transaction_amount`) verificados
 * 2026-08-17 contra el mismo código fuente del SDK oficial citado en `crearIntencion`
 * (src/clients/payment/get/index.ts, src/clients/payment/commonTypes.ts `PaymentResponse`).
 *
 * Mismo criterio de configuración perezosa que `crearIntencion`: lanza `MercadoPagoNoConfiguradoError`
 * recién al invocarse si falta `MP_ACCESS_TOKEN`, nunca al importar este módulo.
 */
export async function obtenerPagoMercadoPago(paymentId: string): Promise<PagoConfirmado> {
  const accessToken = obtenerAccessToken();

  const response = await fetch(`${MP_API_BASE}/v1/payments/${encodeURIComponent(paymentId)}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!response.ok) {
    const detalle = await response.text().catch(() => '');
    throw new Error(`Mercado Pago respondió ${response.status} al consultar el pago ${paymentId}: ${detalle}`);
  }

  const pago = (await response.json()) as MercadoPagoPaymentResponse;
  if (!pago.external_reference || !pago.status || typeof pago.transaction_amount !== 'number') {
    throw new Error(
      `Mercado Pago devolvió un pago incompleto para ${paymentId} (falta external_reference/status/transaction_amount)`
    );
  }

  return {
    turnoId: pago.external_reference,
    estadoPago: pago.status,
    montoAcreditado: pago.transaction_amount,
    paymentId: pago.id !== undefined ? String(pago.id) : paymentId,
  };
}
