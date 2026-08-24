import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { readFileSync } from 'fs';
import { join } from 'path';
import { nowIso, withTransaction, pool } from '../db';
import { expirarPagosPendientesVencidos } from '../jobs/expirarPagosPendientes';
import { recordarTurnosProximos } from '../jobs/recordarTurnosProximos';
import { asyncHandler } from '../middleware/asyncHandler';

/**
 * Rutas SOLO de desarrollo: siembran datos de ejemplo para poder probar el flujo completo
 * desde web-preview/ (o Postman) sin tener que dar de alta todo a mano. NUNCA montar en
 * producción (ver app.ts — se monta condicionalmente según ENABLE_DEV_ROUTES).
 */
export const devRouter = Router();

devRouter.post(
  '/seed',
  asyncHandler(async (_req, res) => {
    const ts = nowIso();
    const sello = Date.now();
    const password = 'demo1234';
    // Mismo hash reutilizado en las 3 altas de `usuario`: es la MISMA contraseña en texto plano
    // para las 3 cuentas demo, así que no hace falta pagar el costo de bcrypt (10 rounds) tres
    // veces — cualquiera de los 3 hashes verificaría igual contra "demo1234".
    const passwordHash = bcrypt.hashSync(password, 10);

    const negocioId = uuid();
    const servicioId = uuid();
    const profesionalId = uuid();
    const profesionalUsuarioId = uuid();
    const adminUsuarioId = uuid();
    const clienteId = uuid();

    const emailProfesional = `profesional-demo-${sello}@test.com`;
    const emailAdmin = `admin-demo-${sello}@test.com`;
    const emailCliente = `cliente-demo-${sello}@test.com`;

    // Contexto RLS: `usuarioId: adminUsuarioId` (el propio admin recién creado, todavía sin JWT
    // emitido — mismo patrón que POST /auth/registro-negocio, ver db.ts). Alcanza para las 3
    // tablas con RLS que este seed toca (negocio_administrador, servicio, profesional,
    // negocio_profesional) SIEMPRE que el INSERT de negocio_administrador corra ANTES que
    // servicio/profesional/negocio_profesional dentro de la misma transacción — el orden de
    // abajo ya lo respeta, no reordenar.
    await withTransaction(
      async (client) => {
        // Generalización N:M (ver modelo-datos.md §2ter): mismo patrón transaccional que
        // /auth/registro-negocio y /negocios/:id/profesionales — negocio.admin_usuario_id y
        // profesional.negocio_id (columnas 1:1) ya no existen, reemplazadas por las tablas de
        // asociación negocio_administrador/negocio_profesional.
        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [adminUsuarioId, emailAdmin, passwordHash, 'Admin Demo', 'administrador', ts]
        );

        await client.query(
          'INSERT INTO negocio (id, nombre, rubro, ubicacion, creado_en) VALUES ($1, $2, $3, $4, $5)',
          [negocioId, 'Consultorio Dr. García (demo)', 'Salud', 'CABA', ts]
        );

        await client.query(
          'INSERT INTO negocio_administrador (negocio_id, usuario_id, creado_en) VALUES ($1, $2, $3)',
          [negocioId, adminUsuarioId, ts]
        );

        await client.query(
          'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [servicioId, negocioId, 'Consulta general', 30, 5000, ts]
        );

        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [profesionalUsuarioId, emailProfesional, passwordHash, 'Dr. García', 'profesional', ts]
        );

        await client.query('INSERT INTO profesional (id, usuario_id, creado_en) VALUES ($1, $2, $3)', [
          profesionalId,
          profesionalUsuarioId,
          ts,
        ]);

        await client.query(
          'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES ($1, $2, true, $3)',
          [negocioId, profesionalId, ts]
        );

        await client.query(
          'INSERT INTO profesional_servicio (profesional_id, servicio_id, requiere_sena, monto_sena) VALUES ($1, $2, $3, $4)',
          [profesionalId, servicioId, true, 1000]
        );

        for (let dia = 0; dia <= 6; dia++) {
          await client.query(
            `INSERT INTO disponibilidad (id, profesional_id, servicio_id, dia_semana, hora_inicio, hora_fin, creado_en)
             VALUES ($1, $2, $3, $4, $5, $6, $7)`,
            [uuid(), profesionalId, servicioId, dia, '09:00', '18:00', ts]
          );
        }

        await client.query(
          'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES ($1, $2, $3, $4, $5, $6)',
          [clienteId, emailCliente, passwordHash, 'Cliente Demo', 'cliente', ts]
        );
      },
      { usuarioId: adminUsuarioId }
    );

    res.status(201).json({
      negocio: { id: negocioId, nombre: 'Consultorio Dr. García (demo)' },
      servicio: { id: servicioId, nombre: 'Consulta general', requiere_sena: true, monto_sena: 1000 },
      administrador: { email: emailAdmin, password },
      profesional: { id: profesionalId, email: emailProfesional, password },
      cliente: { id: clienteId, email: emailCliente, password },
    });
  })
);

// Fuerza una corrida del job de expiración ya mismo (en vez de esperar EXPIRACION_PAGO_MIN
// minutos reales) — solo para poder probar la Fase 4 sin depender del reloj real.
devRouter.post(
  '/forzar-expiracion',
  asyncHandler(async (_req, res) => {
    const cantidad = await expirarPagosPendientesVencidos();
    res.json({ turnos_expirados: cantidad });
  })
);

// Mismo motivo que /forzar-expiracion, arriba: fuerza una corrida del job de recordatorios
// (HU-14b/HU-25) ya mismo, para poder probarlo sin depender del reloj real ni de
// VENTANA_RECORDATORIO_MIN/el intervalo de setInterval.
devRouter.post(
  '/forzar-recordatorios',
  asyncHandler(async (_req, res) => {
    const cantidad = await recordarTurnosProximos();
    res.json({ recordatorios_insertados: cantidad });
  })
);

// Ejecuta manualmente la migración 002 (Google OAuth + Pacientes) contra la base de datos actual.
// SOLO para desarrollo — útil cuando la conexión local a Render DB falla y necesita ejecutarse remotamente.
devRouter.post(
  '/ejecutar-migracion-002',
  asyncHandler(async (_req, res) => {
    const sqlPath = join(__dirname, '../../database/migrations/002_pacientes_historial_auth_google.sql');
    const sql = readFileSync(sqlPath, 'utf-8');

    const client = await pool.connect();
    try {
      await client.query(sql);
      res.json({ mensaje: 'Migración 002 ejecutada exitosamente' });
    } finally {
      client.release();
    }
  })
);
