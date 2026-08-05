import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-not-for-production';

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
