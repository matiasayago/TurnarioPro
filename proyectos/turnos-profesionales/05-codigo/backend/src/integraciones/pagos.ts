/**
 * Integración de pagos (D2/RN10) — Mercado Pago (decisión de CTO IA, ver
 * ../../03-arquitectura/lineamientos-tecnicos.md §1).
 *
 * Este archivo define la interfaz que usa el módulo de Turnos y una implementación
 * "Mock" para desarrollo. NO se crea ninguna cuenta ni se ingresan credenciales reales acá
 * (fuera del alcance permitido de un agente de IA) — el rol Integraciones debe reemplazar
 * MockPagoProvider por un cliente real de Mercado Pago una vez que el CEO provea
 * MP_ACCESS_TOKEN como variable de entorno.
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
