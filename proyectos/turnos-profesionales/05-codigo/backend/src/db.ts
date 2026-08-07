// Persistencia sobre PostgreSQL real vía `pg` (node-postgres) — driver JS puro, sin
// compilación nativa (a diferencia de `better-sqlite3`, la elección original que este
// entorno no podía compilar por falta de Visual Studio Build Tools). Reemplaza a
// `node:sqlite` (usado como solución de desarrollo hasta que el CEO aprobó Render/Railway
// como hosting de producción — ver README.md y
// memory/proyectos/turnos-profesionales/decisiones.md). No queda ningún fallback a
// node:sqlite: un solo driver, una sola forma de acceder a los datos.
//
// La conexión SIEMPRE sale de `DATABASE_URL` (convención Render/Heroku): Render la inyecta
// sola al conectar su addon de Postgres gestionado (ver render.yaml); en desarrollo/CI,
// DevOps la provee vía docker-compose / service container con este mismo nombre de
// variable (ver docker-compose.yml y .github/workflows/turnos-backend-ci.yml).
import { Pool, PoolClient, types as pgTypes } from 'pg';
import fs from 'fs';
import path from 'path';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error(
    'DATABASE_URL no está seteada — la app no puede arrancar sin apuntar a un Postgres real (ver .env.example).'
  );
}

// `pg` devuelve NUMERIC/DECIMAL (OID 1700 — precio_referencia, monto_sena, monto) como
// string por defecto, para no perder precisión al mapear a un `number` de JS — pero acá
// preferimos number (mismo comportamiento que tenía node:sqlite, que los guardaba como REAL):
// nada en este dominio hace aritmética de precisión financiera crítica, y devolver
// "5000.00" en vez de 5000 en el JSON de la API sería un cambio de contrato para
// mobile/web-preview que nadie pidió. TIMESTAMPTZ (OID 1184) y TIMESTAMP (OID 1114) — el
// parser por defecto de `pg` los convierte a `Date`; se normalizan acá a string ISO-8601
// para preservar exactamente el mismo contrato que tenía `node:sqlite` (columnas TEXT) en
// las respuestas JSON y en la lógica interna (dentroDeVentanaMinima, comparaciones de
// disponibilidad.ts), sin tener que reauditar cada `.inicio`/`.fin`/`.creado_en` del código.
pgTypes.setTypeParser(1700, (valor) => parseFloat(valor));
pgTypes.setTypeParser(1114, (valor) => new Date(valor).toISOString());
pgTypes.setTypeParser(1184, (valor) => new Date(valor).toISOString());

function resolveSsl(): boolean | { rejectUnauthorized: boolean } | undefined {
  if (process.env.DATABASE_SSL === 'true') return { rejectUnauthorized: false };
  if (process.env.DATABASE_SSL === 'false') return false;
  // Sin override explícito: dejamos que `pg`/`pg-connection-string` decida a partir de la
  // propia `DATABASE_URL` (ej. si trae `?sslmode=require`, lo respeta solo). No se fuerza
  // nada acá basado en NODE_ENV porque el Dockerfile fija NODE_ENV=production en TODA
  // imagen (docker-compose local, CI, Render por igual) — no sirve para distinguir "es
  // Render" de "es el Postgres sin TLS de docker-compose/CI". Si el Postgres gestionado
  // real (Render/Railway) llegara a exigir TLS con un certificado no confiable por Node,
  // setear DATABASE_SSL=true en ese entorno puntual (ver .env.example) en vez de tocar
  // este default.
  return undefined;
}

const sslOverride = resolveSsl();

export const pool = new Pool({
  connectionString,
  ...(sslOverride !== undefined ? { ssl: sslOverride } : {}),
});

// Un cliente inactivo del pool puede tirar un error async (ej. el servidor cierra la
// conexión) — sin este listener, `pg.Pool` emite 'error' sin handler y tira abajo todo el
// proceso Node (comportamiento default de EventEmitter). Solo lo logueamos: el pool
// descarta ese cliente y sirve el próximo request con uno nuevo.
pool.on('error', (err) => {
  // eslint-disable-next-line no-console
  console.error('[db] Error inesperado en un cliente inactivo del pool de Postgres:', err);
});

/** Mínima interfaz común entre `Pool` y `PoolClient` — permite que funciones de lectura
 *  compartidas (ver src/dominio/disponibilidad.ts) acepten indistintamente el pool (fuera
 *  de transacción, para endpoints públicos) o un client ya dentro de una transacción
 *  autenticada, sin duplicar la función para cada caso. */
export interface Queryable {
  query(text: string, params?: unknown[]): Promise<{ rows: any[]; rowCount: number | null }>;
}

export function nowIso(): string {
  return new Date().toISOString();
}

/** Contexto de Row Level Security a fijar antes de correr el resto de las queries de una
 *  transacción — ver `withTransaction`. */
export interface ContextoRls {
  /** usuario.id del actor autenticado (claim `sub` del JWT) — o, en los pocos endpoints de
   *  registro que todavía no tienen JWT emitido, el id recién generado para la fila que se
   *  está por crear (ver src/routes/auth.ts POST /registro-negocio y src/routes/dev.ts). */
  usuarioId?: string;
  /** negocio_id del JWT (claim "vista activa", ver modelo-datos.md §2ter) — hoy ninguna
   *  policy de database/migrations/001_init.sql lo usa directamente (todas re-derivan la
   *  pertenencia contra negocio_administrador/negocio_profesional a partir de
   *  app.usuario_id), pero se deja disponible para setearlo igual — defensa en profundidad
   *  y forward-compat si una policy futura lo necesita. */
  negocioId?: string;
  /** Ver src/jobs/expirarPagosPendientes.ts y la policy turno_acceso_job_expiracion en
   *  migrations/001_init.sql: el job periódico de expiración actualiza turnos de
   *  CUALQUIER cliente/negocio en un mismo barrido — no actúa "como" ningún usuario
   *  puntual, así que ninguna combinación de usuarioId/negocioId lo habilitaría bajo las
   *  policies pensadas para requests HTTP autenticados. Solo ese job setea este flag. */
  jobSistema?: boolean;
}

/**
 * Corre `fn` dentro de una transacción real (`BEGIN`/`COMMIT`/`ROLLBACK`) sobre un único
 * `PoolClient` dedicado y, si se pasa `contexto`, deja seteadas ANTES de invocar `fn` las
 * variables de sesión que leen las políticas de Row Level Security (`app.usuario_id` /
 * `app.negocio_id` / `app.job_sistema` — ver migrations/001_init.sql). Sin esto,
 * `current_setting(..., true)` devuelve NULL dentro de las políticas y tanto las
 * escrituras (fail-closed, deniegan por defecto) como algunas lecturas (`turno`, que no
 * tiene SELECT público) devuelven menos de lo esperado, en silencio, sin ningún error.
 *
 * Se usa `SELECT set_config(name, value, true)` en vez del literal `SET LOCAL app.x = '...'`
 * porque Postgres NO acepta parámetros bindeados (`$1`) dentro de una sentencia `SET` —
 * `set_config` es una función normal que sí los acepta, y con `is_local = true` es
 * exactamente equivalente a `SET LOCAL` (se revierte solo al terminar la transacción, sea
 * por COMMIT o ROLLBACK). Evita además interpolar el valor a mano en el texto del SQL.
 */
export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>,
  contexto?: ContextoRls
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    if (contexto?.usuarioId) {
      await client.query('SELECT set_config($1, $2, true)', ['app.usuario_id', contexto.usuarioId]);
    }
    if (contexto?.negocioId) {
      await client.query('SELECT set_config($1, $2, true)', ['app.negocio_id', contexto.negocioId]);
    }
    if (contexto?.jobSistema) {
      await client.query('SELECT set_config($1, $2, true)', ['app.job_sistema', 'true']);
    }
    const resultado = await fn(client);
    await client.query('COMMIT');
    return resultado;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Corre el schema completo (migrations/001_init.sql — copia operativa de
 * ../database/migrations/001_init.sql, DBA/fuente de verdad del diseño; ver el header de
 * ese archivo para el detalle de las 3 diferencias que agrega Backend y por qué) contra
 * `pool`, de forma async, al arrancar.
 *
 * El DDL de Postgres NO es idempotente (`CREATE TYPE`/`CREATE POLICY` no soportan
 * `IF NOT EXISTS`) — a diferencia del viejo esquema de node:sqlite (`CREATE TABLE IF NOT
 * EXISTS`, se podía re-ejecutar sin problema en cada arranque). Por eso la migración se
 * gatea con un chequeo simple ("¿ya existe la tabla `usuario`?"): si ya corrió antes, se
 * omite por completo. Esto es necesario para poder arrancar el proceso más de una vez
 * contra la MISMA base ya migrada — un redeploy/restart en Render contra la base gestionada
 * persistente, o (confirmado con DevOps, ver .github/workflows/turnos-backend-ci.yml) un
 * mismo service container de Postgres que en CI se reutiliza sin resetear entre las dos
 * fases de arranque del servidor de ese job — sin este gate, el segundo arranque fallaría
 * con "type/relation ya existe" y el proceso no levantaría.
 */
export async function runMigrations(): Promise<void> {
  const yaMigrado = await pool.query("SELECT to_regclass('public.usuario') AS existe");
  if (yaMigrado.rows[0]?.existe) return;

  const sql = fs.readFileSync(path.join(__dirname, '..', 'migrations', '001_init.sql'), 'utf-8');
  await pool.query(sql);
}
