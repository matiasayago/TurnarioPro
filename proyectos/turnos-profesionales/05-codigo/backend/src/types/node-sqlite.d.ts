// Tipado ambiental mínimo para node:sqlite (incorporado en Node >=22.5, aún no incluido en
// @types/node 20.x). Cubre únicamente la superficie que usa este proyecto.
declare module 'node:sqlite' {
  export type SqlValue = string | number | bigint | Buffer | null;

  export class StatementSync {
    run(...params: SqlValue[]): { changes: number | bigint; lastInsertRowid: number | bigint };
    get(...params: SqlValue[]): Record<string, unknown> | undefined;
    all(...params: SqlValue[]): Record<string, unknown>[];
  }

  export class DatabaseSync {
    constructor(location: string, options?: Record<string, unknown>);
    exec(sql: string): void;
    prepare(sql: string): StatementSync;
    close(): void;
  }
}
