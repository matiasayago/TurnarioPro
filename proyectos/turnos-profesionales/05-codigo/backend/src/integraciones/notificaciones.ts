/**
 * Integración de notificaciones (D4) — Firebase Cloud Messaging (decisión de CTO IA, ver
 * ../../03-arquitectura/lineamientos-tecnicos.md §1).
 *
 * Igual que en pagos.ts: acá solo va la interfaz + un Mock que loguea en vez de enviar. No se
 * crea proyecto de Firebase ni se cargan credenciales reales sin autorización explícita del CEO.
 */

export interface NotificacionProvider {
  enviar(destinatarioUsuarioId: string, tipo: 'confirmacion' | 'recordatorio', mensaje: string): Promise<void>;
}

export class MockNotificacionProvider implements NotificacionProvider {
  async enviar(destinatarioUsuarioId: string, tipo: string, mensaje: string): Promise<void> {
    // eslint-disable-next-line no-console
    console.log(`[notificacion:${tipo}] -> usuario ${destinatarioUsuarioId}: ${mensaje}`);
  }
}

export const notificacionProvider: NotificacionProvider = new MockNotificacionProvider();
