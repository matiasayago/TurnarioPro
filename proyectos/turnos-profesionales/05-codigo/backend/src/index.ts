import { createApp } from './app';
import { iniciarJobExpiracionPagos } from './jobs/expirarPagosPendientes';

const PORT = Number(process.env.PORT || 3000);
createApp().listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Turnos Profesionales backend escuchando en http://localhost:${PORT}`);
});

iniciarJobExpiracionPagos();
