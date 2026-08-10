import { NextFunction, Request, RequestHandler, Response } from 'express';

/**
 * Envuelve un handler async de Express para reenviar cualquier excepción (síncrona o de una
 * promesa rechazada) a `next(err)`, que termina en el error handler centralizado (ver
 * src/app.ts). Necesario porque Express 4 (ver package.json — este proyecto todavía no está en
 * Express 5, que sí hace esto solo) NO atrapa automáticamente los rechazos de promesas de un
 * handler `async`: un `await pool.query(...)`/`await withTransaction(...)` que tira adentro de
 * un handler async sin este wrapper deja el request colgado (nunca se llama a `res.send`) o
 * termina como unhandled rejection del proceso, sin pasar por el error handler.
 *
 * Se aplica de forma pareja a TODOS los handlers async de este backend (ver src/routes/*.ts y
 * src/routes/dev.ts) — un único punto de conversión en vez de un try/catch manual repetido en
 * cada handler.
 */
export function asyncHandler<Req extends Request = Request>(
  fn: (req: Req, res: Response, next: NextFunction) => Promise<unknown>
): RequestHandler {
  return (req, res, next) => {
    fn(req as Req, res, next).catch(next);
  };
}
