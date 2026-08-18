/**
 * Integración de email — recuperación de contraseña (HU-37, 02-backlog/backlog.md, extiende E4)
 * y, desde el 2026-08-18 (ampliación explícita del CEO), envío real de las notificaciones de la
 * bandeja (HU-25, ver dominio/notificaciones.ts) también por correo.
 *
 * (2026-08-18, Backend) Cierre PARCIAL del HALLAZGO que documentaba este archivo hasta este
 * ciclo: el CEO ya decidió el proveedor (Resend, ver `ResendEmailProvider` más abajo) — deja de
 * estar "a definir" — pero `emailProvider` (al final de este archivo) sigue resolviendo a
 * `MockEmailProvider` mientras `RESEND_API_KEY` no esté configurada, exactamente el mismo patrón
 * que tenía `pagoProvider` (`PagoProvider`/`MockPagoProvider`, ver integraciones/pagos.ts) contra
 * `MP_ACCESS_TOKEN` hasta el 2026-08-17. NO se creó ninguna cuenta de Resend ni se cargó ninguna
 * credencial real acá (fuera del alcance permitido de un agente de IA) — eso queda para que el
 * CEO lo resuelva en otra ronda, mismo proceso ya usado para `MP_ACCESS_TOKEN`/`GOOGLE_CLIENT_ID`
 * (ver src/routes/auth.ts).
 *
 * A diferencia de Mercado Pago (que tiene un modo "sin seña" 100% funcional para lanzar sin la
 * integración real, ver 02-backlog/backlog.md "Notas operativas de rollout"), acá NO hay
 * equivalente para HU-37: mientras no haya un proveedor real configurado, un usuario real que
 * olvide su contraseña en producción sigue sin poder recuperarla por ese flujo puntual — es, a
 * propósito, bloqueante de LANZAMIENTO (no de desarrollo ni de pruebas: el Mock alcanza para
 * ambas). Las notificaciones por email (HU-25), en cambio, SÍ tienen un equivalente 100%
 * funcional sin este proveedor configurado: la bandeja in-app (`notificacion`, ver
 * routes/notificaciones.ts) — el email es un canal ADICIONAL, no el único, así que la ausencia de
 * `RESEND_API_KEY` no bloquea ningún flujo de negocio, solo ese canal extra.
 */

export interface EmailProvider {
  /**
   * "Envía" el email de recuperación de contraseña (HU-37) a `destinatario`, con el token de un
   * solo uso EN TEXTO PLANO (`tokenPlano`) que el usuario va a copiar/pegar en la segunda
   * pantalla del flujo (sin deep-linking, ver backlog.md HU-37). Es el ÚNICO punto del backend
   * que vuelve a tener acceso a este valor una vez generado — `src/routes/auth.ts` solo persiste
   * su hash (`token_recuperacion_password.token_hash`, ver 03-arquitectura/modelo-datos.md
   * §2decies), nunca el token crudo.
   */
  enviarRecuperacionPassword(destinatario: string, tokenPlano: string): Promise<void>;

  /**
   * "Envía" por email el MISMO contenido que ya quedó insertado en la bandeja in-app de
   * notificaciones (HU-25 — tabla `notificacion`, ver dominio/notificaciones.ts) — ampliación
   * 2026-08-18, pedido explícito del CEO. Genérico a propósito (no acoplado a "turno" ni a ningún
   * `tipo_notificacion` puntual): a diferencia de `enviarRecuperacionPassword`, acá el asunto y
   * el cuerpo ya vienen armados por quien llama (`armarAsuntoNotificacion`/
   * `armarMensajeNotificacion`, dominio/notificaciones.ts) — este método solo transporta.
   */
  enviarNotificacion(destinatarioEmail: string, asunto: string, cuerpo: string): Promise<void>;
}

export class MockEmailProvider implements EmailProvider {
  async enviarRecuperacionPassword(destinatario: string, tokenPlano: string): Promise<void> {
    // No envía nada real. El token debe quedar visible de alguna forma para poder probar el
    // flujo de punta a punta en desarrollo (HU-37, backlog.md) — acá vía log de servidor; el
    // handler de `POST /auth/recuperar-password` (src/routes/auth.ts) además lo suma a la propia
    // respuesta HTTP bajo el mismo gateo, la otra alternativa que deja explícitamente habilitada
    // esa misma historia. Gateado detrás de `ENABLE_DEV_ROUTES` (mismo flag que ya usa
    // src/routes/dev.ts/src/app.ts): nunca debe imprimirse un secreto de este tipo a un log en
    // un entorno donde ese flag no esté activo explícitamente (en Render queda en "false", ver
    // render.yaml) — fuera de ese modo, el Mock igual "envía" (no hace nada real) pero no deja
    // ningún rastro del token.
    if (process.env.ENABLE_DEV_ROUTES === 'true') {
      // eslint-disable-next-line no-console
      console.log(`[email:recuperacion-password] -> ${destinatario}: token=${tokenPlano}`);
    }
  }

  /**
   * Mismo criterio exacto que `enviarRecuperacionPassword` de arriba (mismo gateo detrás de
   * `ENABLE_DEV_ROUTES`, "sin dejar ningún rastro fuera de ese modo") — no repetido en detalle acá.
   * A diferencia de un token de recuperación, el contenido de una notificación (HU-25) no es un
   * secreto de un solo uso, pero el criterio de no filtrar nada a un log fuera de desarrollo se
   * mantiene igual: en Render, `ENABLE_DEV_ROUTES` queda en "false" (ver render.yaml).
   */
  async enviarNotificacion(destinatarioEmail: string, asunto: string, cuerpo: string): Promise<void> {
    if (process.env.ENABLE_DEV_ROUTES === 'true') {
      // eslint-disable-next-line no-console
      console.log(`[email:notificacion] -> ${destinatarioEmail} (${asunto}): ${cuerpo}`);
    }
  }
}

// ============================================================================
// Implementación real — API REST de Resend directa (`fetch` nativo de Node 22, ver Dockerfile de
// este backend — sin agregar el paquete npm `resend`, que no es dependencia de este proyecto).
// Mismo criterio que `MercadoPagoProvider` (integraciones/pagos.ts): un cliente HTTP fino contra
// la API pública, sin SDK.
// ============================================================================

const RESEND_API_BASE = 'https://api.resend.com';

/**
 * Remitente por default — dominio de pruebas de Resend (`onboarding@resend.dev`), disponible sin
 * que el CEO tenga que verificar un dominio propio. Mismo criterio que el modo sandbox de
 * Mercado Pago (ver integraciones/pagos.ts, `esCredencialDePrueba`): funciona sin configuración
 * adicional pero con una limitación real de ese modo — según la documentación pública de Resend
 * (Dashboard > Domains), mientras no haya un dominio propio verificado, la cuenta solo puede
 * enviar a la dirección de email con la que se creó la cuenta de Resend, no a destinatarios
 * arbitrarios (clientes/profesionales reales de este proyecto). Para que las notificaciones le
 * lleguen de verdad a cualquier cliente/profesional en producción, el CEO va a necesitar verificar
 * un dominio propio en Resend y pisar este default vía `RESEND_FROM_EMAIL` — documentado acá, no
 * resuelto (mismo tipo de límite documentado ya para Mercado Pago sandbox).
 */
const REMITENTE_POR_DEFECTO = 'Turnario <onboarding@resend.dev>';

export class ResendEmailProvider implements EmailProvider {
  /**
   * A diferencia de `enviarNotificacion` (más abajo), este método NUNCA propaga un error de
   * Resend — lo atrapa y solo lo loguea. No es el mismo criterio "fail-closed/no-throw de quien
   * llama" que el resto de esta ampliación (ver el comentario grande en routes/turnos.ts junto a
   * cada call site de `enviarNotificacion`): acá la razón es puntual y distinta. Este método
   * alimenta a `POST /auth/recuperar-password` (src/routes/auth.ts), que:
   *   1) por instrucción explícita de este ciclo, no se toca — sigue sin envolver este `await` en
   *      try/catch — y
   *   2) responde SIEMPRE el mismo mensaje genérico, precisamente para no delatar si una cuenta
   *      existe (ver el comentario de ese endpoint, "No-enumeración").
   * Si esto propagara un error de Resend (rate limit, red, lo que sea), ese endpoint pasaría a
   * responder 500 SOLO en el branch que efectivamente intenta enviar el email (cuenta real, con
   * password) — un oráculo de existencia de cuenta nuevo, exactamente lo que el resto de ese
   * endpoint ya se cuida de no filtrar. Por eso el error se atrapa y se loguea server-side acá
   * mismo, para no dejarlo invisible sin cambiar el comportamiento externo de ese endpoint.
   */
  async enviarRecuperacionPassword(destinatario: string, tokenPlano: string): Promise<void> {
    try {
      await this.enviarPorResend(
        destinatario,
        'Recuperación de tu contraseña',
        `Tu código para restablecer tu contraseña es: ${tokenPlano}\n\n` +
          'Copialo y pegalo en la pantalla "Restablecer contraseña" de la app. ' +
          'Si vos no pediste este cambio, podés ignorar este mensaje: tu contraseña actual no fue modificada.'
      );
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('[email] Error enviando el email de recuperación de contraseña vía Resend:', err);
    }
  }

  /**
   * A diferencia de `enviarRecuperacionPassword`, este método SÍ propaga cualquier error de
   * Resend — cada call site (routes/turnos.ts, routes/profesionales.ts,
   * jobs/recordarTurnosProximos.ts) lo llama siempre FUERA de la transacción que insertó la
   * notificación en la bandeja, envuelto en su propio try/catch que solo loguea (mismo criterio
   * fail-closed/no-throw que ya usa integraciones/pagos.ts `validarWebhook` para no tirar abajo
   * el flujo principal por un problema de un sistema externo) — no hace falta duplicar ese
   * try/catch acá adentro.
   */
  async enviarNotificacion(destinatarioEmail: string, asunto: string, cuerpo: string): Promise<void> {
    await this.enviarPorResend(destinatarioEmail, asunto, cuerpo);
  }

  /**
   * `POST /emails` — cuerpo mínimo (`from`/`to`/`subject`/`text`), tal como lo especificó el CEO
   * para este ciclo. Mismo estilo de manejo de respuesta que `MercadoPagoProvider.crearIntencion`
   * (integraciones/pagos.ts): chequea `response.ok` y lanza con detalle (status + body) si Resend
   * rechaza el envío, en vez de asumir éxito.
   */
  private async enviarPorResend(to: string, subject: string, text: string): Promise<void> {
    const apiKey = process.env.RESEND_API_KEY;
    // No debería poder pasar en la práctica: `emailProvider` (al final de este archivo) solo
    // construye un `ResendEmailProvider` cuando `RESEND_API_KEY` ya está seteada. Chequeado
    // igual, nunca asumido — mismo criterio defensivo que el resto de este backend.
    if (!apiKey) {
      throw new Error('RESEND_API_KEY no está configurada en este entorno');
    }
    const from = process.env.RESEND_FROM_EMAIL || REMITENTE_POR_DEFECTO;

    const response = await fetch(`${RESEND_API_BASE}/emails`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from, to, subject, text }),
    });

    if (!response.ok) {
      const detalle = await response.text().catch(() => '');
      throw new Error(`Resend respondió ${response.status} al enviar un email a ${to}: ${detalle}`);
    }
  }
}

// Selección condicional — mismo patrón que tenía `pagoProvider` (integraciones/pagos.ts) contra
// `MP_ACCESS_TOKEN` hasta el 2026-08-17 (ver el header de este archivo): sin `RESEND_API_KEY`
// configurada, el comportamiento tiene que quedar IDÉNTICO al de hoy (`MockEmailProvider`, sin
// ningún intento de red real) — nunca se lee ninguna variable de entorno al importar este módulo
// más que en esta única condición (`ResendEmailProvider` en sí no lee nada en su constructor, ver
// `enviarPorResend` — se lee perezosamente recién al invocar cada método).
export const emailProvider: EmailProvider = process.env.RESEND_API_KEY
  ? new ResendEmailProvider()
  : new MockEmailProvider();
