// HIGH-1 (ver 07-seguridad/informe-seguridad.md): protección básica de fuerza bruta /
// creación masiva de cuentas en los endpoints de autenticación. Los valores por defecto (10
// intentos / 15 min por IP) son el "límite razonable" que pidió Security; son configurables
// vía env vars para poder subirlos en corridas de pruebas automatizadas masivas (que, al
// compartir la misma IP de loopback, generan mucho más tráfico legítimo que un usuario real)
// sin tener que tocar el valor por defecto recomendado para producción.
import rateLimit from 'express-rate-limit';

const minutosAMs = (minutos: number) => minutos * 60_000;

/**
 * Límite para `POST /auth/login`. Solo cuenta intentos FALLIDOS
 * (`skipSuccessfulRequests`) — un login legítimo (200) nunca debe verse penalizado, sin
 * importar cuánto tráfico normal genere; lo que se limita es la cantidad de credenciales
 * incorrectas probadas contra la misma IP en la ventana de tiempo (fuerza bruta /
 * credential stuffing, OWASP A07:2021).
 */
export const loginLimiter = rateLimit({
  windowMs: minutosAMs(Number(process.env.RATE_LIMIT_LOGIN_WINDOW_MIN ?? 15)),
  limit: Number(process.env.RATE_LIMIT_LOGIN_MAX ?? 10),
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { error: 'Demasiados intentos de login fallidos desde esta IP — probá de nuevo más tarde.' },
});

/**
 * Límite para los endpoints de alta de cuenta (`/auth/registro-negocio`,
 * `/auth/registro-cliente`). Acá SÍ cuentan también los intentos exitosos: no hay una
 * "credencial" que forzar, el riesgo es volumen de altas automatizadas (spam de
 * negocios/cuentas), a diferencia del login.
 */
export const registroLimiter = rateLimit({
  windowMs: minutosAMs(Number(process.env.RATE_LIMIT_REGISTRO_WINDOW_MIN ?? 15)),
  limit: Number(process.env.RATE_LIMIT_REGISTRO_MAX ?? 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Demasiadas solicitudes de registro desde esta IP — probá de nuevo más tarde.' },
});

/**
 * Límite para los 2 endpoints nuevos de recuperación de contraseña (HU-37, backlog.md, extiende
 * E4): `POST /auth/recuperar-password` y `POST /auth/reset-password` — mismo patrón que
 * `loginLimiter`/`registroLimiter` de arriba (recomendación de DBA, ver
 * database/migrations/001_init.sql, bloque "Recuperación de contraseña"), pero ninguno de los
 * dos limiters existentes encaja tal cual, así que este es uno nuevo, reusado (misma instancia)
 * en ambos endpoints:
 * - `loginLimiter` no serviría para `/recuperar-password`: cuenta solo intentos FALLIDOS
 *   (`skipSuccessfulRequests`), pero ese endpoint SIEMPRE responde 200 con el mismo mensaje
 *   genérico (criterio de no-enumeración de HU-37) — con `skipSuccessfulRequests` ningún
 *   request contaría nunca, dejando el endpoint sin protección real contra spam de emails.
 * - Por eso cuenta TODOS los intentos (como `registroLimiter`), incluidos los canjes exitosos
 *   de `/reset-password` — un usuario legítimo normalmente solo necesita canjear un token una
 *   vez, así que el costo de UX es mínimo frente a limitar de forma pareja la fuerza bruta del
 *   token en el endpoint que DBA marcó como el más sensible de los dos ("en especial el de
 *   canje").
 */
export const recuperacionPasswordLimiter = rateLimit({
  windowMs: minutosAMs(Number(process.env.RATE_LIMIT_RECUPERACION_WINDOW_MIN ?? 15)),
  limit: Number(process.env.RATE_LIMIT_RECUPERACION_MAX ?? 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: 'Demasiadas solicitudes de recuperación de contraseña desde esta IP — probá de nuevo más tarde.',
  },
});
