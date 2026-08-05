import express from 'express';
import path from 'path';
import { runMigrations } from './db';
import { authRouter } from './routes/auth';
import { negociosRouter } from './routes/negocios';
import { profesionalesRouter } from './routes/profesionales';
import { turnosRouter } from './routes/turnos';
import { clientesRouter } from './routes/clientes';
import { devRouter } from './routes/dev';

export function createApp() {
  runMigrations();

  const app = express();
  app.use(express.json());

  app.get('/health', (_req, res) => res.json({ ok: true }));

  app.use('/auth', authRouter);
  app.use('/negocios', negociosRouter);
  app.use('/profesionales', profesionalesRouter);
  app.use('/turnos', turnosRouter);
  app.use('/clientes', clientesRouter);

  // Solo para desarrollo/demo: seed de datos + preview web del flujo, para poder ver y
  // probar el golden path en el navegador sin instalar Flutter. NUNCA en producción.
  if (process.env.NODE_ENV !== 'production') {
    app.use('/dev', devRouter);
    app.use(express.static(path.join(__dirname, '..', 'web-preview')));
  }

  return app;
}
