import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { v4 as uuid } from 'uuid';
import { db, nowIso, withTransaction } from '../db';
import { expirarPagosPendientesVencidos } from '../jobs/expirarPagosPendientes';

/**
 * Rutas SOLO de desarrollo: siembran datos de ejemplo para poder probar el flujo completo
 * desde web-preview/ (o Postman) sin tener que dar de alta todo a mano. NUNCA montar en
 * producción (ver app.ts — se monta condicionalmente según NODE_ENV).
 */
export const devRouter = Router();

devRouter.post('/seed', (_req, res) => {
  const ts = nowIso();
  const sello = Date.now();
  const password = 'demo1234';

  const negocioId = uuid();
  const servicioId = uuid();
  const profesionalId = uuid();
  const profesionalUsuarioId = uuid();
  const adminUsuarioId = uuid();
  const clienteId = uuid();

  const emailProfesional = `profesional-demo-${sello}@test.com`;
  const emailAdmin = `admin-demo-${sello}@test.com`;
  const emailCliente = `cliente-demo-${sello}@test.com`;

  withTransaction(() => {
    // Generalización N:M (ver modelo-datos.md §2ter): mismo patrón transaccional que
    // /auth/registro-negocio y /negocios/:id/profesionales — negocio.admin_usuario_id y
    // profesional.negocio_id (columnas 1:1) ya no existen, reemplazadas por las tablas de
    // asociación negocio_administrador/negocio_profesional.
    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(adminUsuarioId, emailAdmin, bcrypt.hashSync(password, 10), 'Admin Demo', 'administrador', ts);

    db.prepare(
      'INSERT INTO negocio (id, nombre, rubro, ubicacion, creado_en) VALUES (?, ?, ?, ?, ?)'
    ).run(negocioId, 'Consultorio Dr. García (demo)', 'Salud', 'CABA', ts);

    db.prepare(
      'INSERT INTO negocio_administrador (negocio_id, usuario_id, creado_en) VALUES (?, ?, ?)'
    ).run(negocioId, adminUsuarioId, ts);

    db.prepare(
      'INSERT INTO servicio (id, negocio_id, nombre, duracion_min, precio_referencia, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(servicioId, negocioId, 'Consulta general', 30, 5000, ts);

    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(profesionalUsuarioId, emailProfesional, bcrypt.hashSync(password, 10), 'Dr. García', 'profesional', ts);

    db.prepare(
      'INSERT INTO profesional (id, usuario_id, creado_en) VALUES (?, ?, ?)'
    ).run(profesionalId, profesionalUsuarioId, ts);

    db.prepare(
      'INSERT INTO negocio_profesional (negocio_id, profesional_id, activo, creado_en) VALUES (?, ?, 1, ?)'
    ).run(negocioId, profesionalId, ts);

    db.prepare(
      'INSERT INTO profesional_servicio (profesional_id, servicio_id, requiere_sena, monto_sena) VALUES (?, ?, ?, ?)'
    ).run(profesionalId, servicioId, 1, 1000);

    for (let dia = 0; dia <= 6; dia++) {
      db.prepare(
        `INSERT INTO disponibilidad (id, profesional_id, servicio_id, dia_semana, hora_inicio, hora_fin, creado_en)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).run(uuid(), profesionalId, servicioId, dia, '09:00', '18:00', ts);
    }

    db.prepare(
      'INSERT INTO usuario (id, email, password_hash, nombre, rol, creado_en) VALUES (?, ?, ?, ?, ?, ?)'
    ).run(clienteId, emailCliente, bcrypt.hashSync(password, 10), 'Cliente Demo', 'cliente', ts);
  });

  res.status(201).json({
    negocio: { id: negocioId, nombre: 'Consultorio Dr. García (demo)' },
    servicio: { id: servicioId, nombre: 'Consulta general', requiere_sena: true, monto_sena: 1000 },
    administrador: { email: emailAdmin, password },
    profesional: { id: profesionalId, email: emailProfesional, password },
    cliente: { id: clienteId, email: emailCliente, password },
  });
});

// Fuerza una corrida del job de expiración ya mismo (en vez de esperar EXPIRACION_PAGO_MIN
// minutos reales) — solo para poder probar la Fase 4 sin depender del reloj real.
devRouter.post('/forzar-expiracion', (_req, res) => {
  const cantidad = expirarPagosPendientesVencidos();
  res.json({ turnos_expirados: cantidad });
});
