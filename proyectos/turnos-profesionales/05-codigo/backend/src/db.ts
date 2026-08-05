// Usamos el módulo `node:sqlite` incorporado en Node.js (>=22.5) en vez de better-sqlite3:
// better-sqlite3 requiere compilar un addon nativo (node-gyp + Visual Studio Build Tools),
// no disponibles en este entorno. node:sqlite evita esa dependencia para desarrollo/pruebas.
// Producción sigue apuntando a PostgreSQL (ver ../database/migrations/001_init.sql, DBA).
import { DatabaseSync } from 'node:sqlite';
import fs from 'fs';
import path from 'path';

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'dev.sqlite3');

export const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA foreign_keys = ON');

export function runMigrations(): void {
  const sql = fs.readFileSync(
    path.join(__dirname, '..', 'migrations', '001_init.sqlite.sql'),
    'utf-8'
  );
  db.exec(sql);
}

/** node:sqlite no trae un helper `.transaction()` como better-sqlite3; lo emulamos. */
export function withTransaction<T>(fn: () => T): T {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

export function nowIso(): string {
  return new Date().toISOString();
}
