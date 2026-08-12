import { z } from 'zod';
import { Response } from 'express';

// MEDIUM-3 (ver 07-seguridad/informe-seguridad.md): esquemas de validación reutilizables para
// los handlers de turnos/profesionales/negocios que reciben body/params de usuario. Antes solo
// se validaba presencia (`!campo`) y, puntualmente, formato de fecha/dia_semana (ver DEF-04 en
// turnos.ts/profesionales.ts) — acá se centraliza esa validación con zod para cubrir también
// UUIDs bien formados y rangos numéricos, devolviendo 400 con el detalle del error ANTES de
// tocar la base de datos, en vez de dejar que una excepción no controlada llegue al error
// handler genérico (HIGH-2, ya resuelto, pero mejor no volver a depender de esa red de
// contención para casos que se pueden rechazar antes).

/** negocio_id / servicio_id / profesional_id / turno :id recibidos por parámetro o body. */
export const uuidSchema = z.string().uuid({ message: 'Debe ser un identificador UUID válido' });

/**
 * Equivalente al chequeo `isNaN(new Date(x).getTime())` que ya usaban `POST /turnos` y
 * `PATCH /turnos/:id/reprogramar` (ver DEF-04, reporte-qa.md) — se mantiene la misma semántica
 * de aceptación (cualquier string que `Date` pueda parsear) para no dejar huecos ni volverse
 * más permisivo ni más estricto que el comportamiento ya verificado, solo que ahora vive acá
 * como schema reutilizable y corre ANTES de construir el `Date` "de verdad" en el handler.
 */
export const fechaIsoSchema = z.string().refine((valor) => !isNaN(new Date(valor).getTime()), {
  message: 'Debe ser una fecha ISO-8601 válida',
});

/** dia_semana: entero 0 (domingo) a 6 (sábado) — ya validado a mano en profesionales.ts (DEF-04). */
export const diaSemanaSchema = z
  .number()
  .int('dia_semana debe ser un entero')
  .min(0, 'dia_semana debe estar entre 0 (domingo) y 6 (sábado)')
  .max(6, 'dia_semana debe estar entre 0 (domingo) y 6 (sábado)');

/** hora_inicio / hora_fin de un bloque de disponibilidad, formato HH:MM (24hs). */
export const horaSchema = z
  .string()
  .regex(/^([01]\d|2[0-3]):([0-5]\d)$/, 'Debe tener formato HH:MM (24hs)');

/**
 * `visibilidad_perfil` (HU-32, Privacidad — ver src/routes/usuario.ts): mismos 3 valores que el
 * ENUM `visibilidad_perfil_usuario` de la base (database/migrations/001_init.sql /
 * 003_privacidad_usuario.sql). Vive acá, no local a usuario.ts, por el mismo criterio que
 * `diaSemanaSchema`/`horaSchema` de arriba: un primitivo de dominio validado contra un ENUM real
 * de la base — no un objeto compuesto específico de un único endpoint (esos quedan locales a
 * cada router, ver `configuracionProfesionalSchema` en profesionales.ts como ejemplo).
 */
export const visibilidadPerfilSchema = z.enum(['publico', 'solo_contactos', 'privado']);

/** duracion_min, monto_sena, precio_referencia y similares: números positivos. */
export const montoPositivoSchema = z.number().positive('Debe ser un número mayor a 0');

// MEDIUM-1 (ver 07-seguridad/informe-seguridad.md): política mínima de fortaleza de contraseña,
// aplicada de forma consistente en los 3 puntos donde se crea una contraseña nueva
// (POST /auth/registro-negocio, POST /auth/registro-cliente, POST /negocios/:id/profesionales).
// No se agrega chequeo contra contraseñas filtradas (ej. HaveIBeenPwned) en este ciclo — alcanza
// con longitud mínima según lo priorizado por el Director General IA.
export const PASSWORD_MIN_LENGTH = 8;
export const passwordSchema = z
  .string()
  .min(PASSWORD_MIN_LENGTH, `La contraseña debe tener al menos ${PASSWORD_MIN_LENGTH} caracteres`);

/** Responde 400 con el detalle campo-por-campo del error de zod (nunca un mensaje genérico). */
export function respuestaValidacionFallida(res: Response, error: z.ZodError) {
  return res.status(400).json({ error: 'Datos inválidos', detalles: error.flatten().fieldErrors });
}
