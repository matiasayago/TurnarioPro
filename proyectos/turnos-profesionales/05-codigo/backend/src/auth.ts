import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

// HIGH-3 (ver 07-seguridad/informe-seguridad.md): el fallback hardcodeado se mantiene SOLO para
// desarrollo/test (donde nunca hay datos reales en juego); en producción, arrancar sin
// JWT_SECRET seteado es un error de configuración que debe frenar el proceso, no degradar
// silenciosamente a un secreto público conocido (visible en este mismo archivo fuente), lo que
// permitiría forjar JWT arbitrarios de cualquier rol/negocio/profesional.
function resolveJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (secret) return secret;
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      'JWT_SECRET no está seteado y NODE_ENV=production — el proceso no puede arrancar sin un secreto real (ver informe-seguridad.md HIGH-3).'
    );
  }
  return 'dev-secret-not-for-production';
}

const JWT_SECRET = resolveJwtSecret();

export type Rol = 'cliente' | 'profesional' | 'administrador';

export interface JwtClaims {
  sub: string; // usuario_id
  rol: Rol;
  negocio_id?: string; // presente para profesional/administrador (RN9)
  profesional_id?: string; // presente solo para rol=profesional
}

export function signToken(claims: JwtClaims): string {
  return jwt.sign(claims, JWT_SECRET, { expiresIn: '2h' });
}

export interface AuthedRequest extends Request {
  auth?: JwtClaims;
}

export function requireAuth(...rolesPermitidos: Rol[]) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Falta token de autenticación' });
    }
    try {
      const claims = jwt.verify(header.slice(7), JWT_SECRET) as JwtClaims;
      if (rolesPermitidos.length > 0 && !rolesPermitidos.includes(claims.rol)) {
        return res.status(403).json({ error: 'Rol no autorizado para esta acción' });
      }
      req.auth = claims;
      next();
    } catch {
      return res.status(401).json({ error: 'Token inválido o expirado' });
    }
  };
}
