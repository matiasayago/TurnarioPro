import express, { NextFunction, Request, Response } from 'express';
import helmet from 'helmet';
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

  // CORRECCIÓN (2026-08-10, confirmado contra el primer despliegue real en Render): sin esto,
  // cualquier ruta con rate-limit (express-rate-limit, ver middleware/rateLimit.ts) revienta con
  // "ValidationError: The 'X-Forwarded-For' header is set but the Express 'trust proxy' setting
  // is false" apenas el tráfico pasa por un proxy real que agrega ese header (Render, igual que
  // Heroku/Railway) — ni el entorno de desarrollo local ni el smoke test de CI (docker run
  // --network host, sin proxy delante) podían revelar esto. Sin `trust proxy`, Express ignora
  // `X-Forwarded-For` y `req.ip` devolvería la IP del proxy para TODOS los usuarios por igual
  // (rompería el rate-limit real, no solo tiraría este error) — express-rate-limit lo detecta y
  // aborta el request en vez de dejarlo pasar silenciosamente mal configurado. `1` (no `true`):
  // confía únicamente en el primer hop (el proxy de Render, que está directamente delante de
  // este servicio) — nunca en un X-Forwarded-For más lejano que un cliente pudiera falsificar.
  app.set('trust proxy', 1);

  // MEDIUM-2 (ver 07-seguridad/informe-seguridad.md): cabeceras de seguridad HTTP básicas
  // (quita `X-Powered-By`, agrega `X-Content-Type-Options`, `X-Frame-Options`/frame-ancestors,
  // `Referrer-Policy`, etc.). Va ANTES de las rutas para cubrir toda la superficie, incluida
  // `web-preview/` que sirve HTML. `Strict-Transport-Security` queda fuera de alcance acá —
  // corresponde a la capa de terminación TLS/reverse proxy (DevOps), no a la app Node.
  app.use(helmet());
  app.use(express.json());

  // Dev-only: un cliente web servido desde otro origen (p. ej. `flutter run -d web-server`, en
  // un puerto distinto al de esta API) necesita cabeceras CORS o el navegador bloquea la
  // respuesta aunque ambos corran en localhost. Mismo flag que ya gatea `/dev` y el preview
  // HTML (ENABLE_DEV_ROUTES) — en Render queda explícitamente en "false" (ver render.yaml), así
  // que esto nunca se activa en producción salvo opt-in explícito.
  if (process.env.ENABLE_DEV_ROUTES === 'true') {
    app.use((req, res, next) => {
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      res.header('Access-Control-Allow-Methods', 'GET,POST,PATCH,PUT,DELETE,OPTIONS');
      if (req.method === 'OPTIONS') {
        res.sendStatus(204);
        return;
      }
      next();
    });
  }

  app.get('/health', (_req, res) => res.json({ ok: true }));

  app.use('/auth', authRouter);
  app.use('/negocios', negociosRouter);
  app.use('/profesionales', profesionalesRouter);
  app.use('/turnos', turnosRouter);
  app.use('/clientes', clientesRouter);

  // HIGH-4 (ver 07-seguridad/informe-seguridad.md): estas rutas NO tienen autenticación propia
  // (seed de datos + preview web del flujo, para poder probar el golden path sin instalar
  // Flutter), así que antes dependían solo de `NODE_ENV !== 'production'` (opt-OUT implícito:
  // si un entorno compartido no seteaba NODE_ENV=production por error, quedaban expuestas sin
  // querer). Ahora es un opt-IN explícito — solo se montan si ENABLE_DEV_ROUTES=true, sin
  // importar NODE_ENV. `npm run dev` ya lo setea (ver package.json); en cualquier otro entorno
  // hay que setearlo a mano a sabiendas de que se está exponiendo un endpoint sin auth.
  if (process.env.ENABLE_DEV_ROUTES === 'true') {
    app.use('/dev', devRouter);
    app.use(express.static(path.join(__dirname, '..', 'web-preview')));
  }

  // HIGH-2 (ver 07-seguridad/informe-seguridad.md): middleware de manejo de errores
  // centralizado (4 argumentos — Express lo reconoce como error handler solo por esa firma).
  // Va AL FINAL, después de montar todas las rutas, para capturar cualquier excepción no
  // controlada que suba desde un handler síncrono (Express 4 reenvía automáticamente esos
  // throws acá). Loguea el detalle completo server-side (auditoría) pero nunca devuelve stack
  // trace ni mensaje interno al cliente, en NINGÚN entorno.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    // eslint-disable-next-line no-console
    console.error('Error no controlado:', err);
    res.status(500).json({ error: 'Error interno' });
  });

  return app;
}
