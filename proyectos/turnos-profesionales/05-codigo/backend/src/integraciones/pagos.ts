/**
 * Integración de pagos (D2/RN10) — Mercado Pago (decisión de CTO IA, ver
 * ../../03-arquitectura/lineamientos-tecnicos.md §1).
 *
 * Este archivo define la interfaz que usa el módulo de Turnos y una implementación
 * "Mock" para desarrollo. NO se crea ninguna cuenta ni se ingresan credenciales reales acá
 * (fuera del alcance permitido de un agente de IA) — el rol Integraciones debe reemplazar
 * MockPagoProvider por un cliente real de Mercado Pago una vez que el CEO provea
 * MP_ACCESS_TOKEN como variable de entorno.
 *
 * HALLAZGO (2026-08-14, Backend, HU-29/E11 "Turnario Pro") — verificado contra el código real
 * (grep de todo `backend/src/`, no asumido): NINGÚN endpoint/ruta llama hoy a
 * `crearIntencion`/`validarWebhook` ni actualiza `pago.estado` a `'acreditado'` — de hecho,
 * `pagoProvider` (más abajo) no tiene NINGÚN caller en todo el backend. En la práctica, un turno
 * que nace `'pendiente_de_pago'` (RN10: el servicio requiere seña — `POST /turnos` en turnos.ts,
 * o `POST /profesionales/:id/turnos` con `cobrar_sena=true`) hoy NUNCA transiciona a
 * `'confirmado'` en ningún camino de este código — solo puede expirar a `'cancelado'`
 * (`src/jobs/expirarPagosPendientes.ts`, turno_id.pago.estado -> `'expirado'`) o quedar
 * `'pendiente_de_pago'` indefinidamente. La confirmación real de pago (webhook de Mercado Pago
 * validado con `validarWebhook`, seguido de `UPDATE pago SET estado = 'acreditado' ...` +
 * `UPDATE turno SET estado = 'confirmado' ...`) es un gap preexistente de HU-04b/HU-09b, anterior
 * a este ciclo y fuera de su alcance — no se implementa acá.
 *
 * PENDIENTE PARA QUIEN IMPLEMENTE ESE WEBHOOK (Backend/Integraciones, ciclo futuro): el momento
 * exacto en que ese código futuro haga `UPDATE turno SET estado = 'confirmado'` es, también, uno
 * de los puntos donde HU-29 (límite de 60 turnos confirmados/mes del plan gratis) necesita
 * aplicar el chequeo — ver `dominio/suscripciones.ts`
 * (`exigirLimiteTurnosConfirmadosDelMes(client, negocioId, turno.inicio)`, mismo helper que ya
 * usan `POST /turnos` y `POST /profesionales/:id/turnos` para sus propios caminos "directo a
 * confirmado"). Consciente: si el chequeo del límite solo se aplicara en la CREACIÓN del turno
 * (cuando nace `pendiente_de_pago`) y no en esta confirmación futura, un negocio en plan gratis
 * podría acumular pendientes de pago sin límite y el bloqueo real llegaría tarde (recién al mes
 * siguiente) o nunca por esta vía — llamar al chequeo ACÁ, no en la creación, para ese camino.
 */

export interface IntencionDePago {
  id: string;
  monto: number;
  urlCheckout: string;
}

export interface PagoProvider {
  crearIntencion(turnoId: string, monto: number): Promise<IntencionDePago>;
  validarWebhook(payload: unknown, firma: string | undefined): boolean;
}

export class MockPagoProvider implements PagoProvider {
  async crearIntencion(turnoId: string, monto: number): Promise<IntencionDePago> {
    return {
      id: `mock-${turnoId}`,
      monto,
      urlCheckout: `https://mock-checkout.local/pagar/${turnoId}`,
    };
  }

  validarWebhook(): boolean {
    return true; // Mock: siempre válido. La implementación real valida la firma de Mercado Pago.
  }
}

export const pagoProvider: PagoProvider = new MockPagoProvider();
