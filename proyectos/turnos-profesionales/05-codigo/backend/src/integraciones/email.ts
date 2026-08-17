/**
 * Integración de email — recuperación de contraseña (HU-37, 02-backlog/backlog.md, extiende E4).
 *
 * Mismo patrón que tenía ../integraciones/pagos.ts (`PagoProvider`/`MockPagoProvider`) hasta el
 * 2026-08-17, cuando Integraciones lo reemplazó por un cliente real de Mercado Pago
 * (`MercadoPagoProvider`, ver ese archivo): una interfaz propia y una implementación "Mock" para
 * desarrollo, en vez de acoplar el router directo a un proveedor real. NO se crea ninguna cuenta
 * ni se cargan credenciales reales acá (fuera del
 * alcance permitido de un agente de IA) — el rol Integraciones debe reemplazar
 * `MockEmailProvider` por un cliente real (SendGrid/Resend/AWS SES, a definir) una vez que el
 * CEO provea las credenciales de una cuenta de un proveedor de email real como variable(s) de
 * entorno (mismo criterio ya aplicado a `MP_ACCESS_TOKEN` en pagos.ts y a `GOOGLE_CLIENT_ID` en
 * src/routes/auth.ts).
 *
 * A diferencia de Mercado Pago (que tiene un modo "sin seña" 100% funcional para lanzar sin la
 * integración real, ver 02-backlog/backlog.md "Notas operativas de rollout"), acá NO hay
 * equivalente: mientras no haya un proveedor real configurado, un usuario real que olvide su
 * contraseña en producción sigue sin poder recuperarla por este flujo — es, a propósito,
 * bloqueante de LANZAMIENTO (no de desarrollo ni de pruebas: el Mock alcanza para ambas).
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
}

export const emailProvider: EmailProvider = new MockEmailProvider();
