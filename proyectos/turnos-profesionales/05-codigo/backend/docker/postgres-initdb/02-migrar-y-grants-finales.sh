#!/bin/sh
# Turnos Profesionales (TURNOS-2026-001) — DevOps, 2026-08-09/10.
# Paso 2/2 de la separación de roles de Postgres para docker-compose (ver 01-provisionar-roles.sh
# para el paso 1 y el porqué completo). Corre automáticamente a continuación de ese script,
# dentro de la misma ejecución de docker-entrypoint-initdb.d (mismo mecanismo de "solo la primera
# vez que el volumen está vacío" — ver el comentario largo en 01-provisionar-roles.sh).
set -e

echo "[02-migrar] Corriendo 001_init.sql como el rol de MIGRACION ($TURNOS_MIGRADOR_ROL)..."

# Conectado COMO el rol de MIGRACIÓN (no como POSTGRES_USER/turnos, el superusuario de
# bootstrap) — así ese rol, no el superusuario, queda como OWNER de las tablas/tipos/funciones
# que crea este DDL. Es la pieza central de toda la separación de roles: ver el bloque
# "Separación owner/runtime y FORCE ROW LEVEL SECURITY" en
# ../../../database/migrations/001_init.sql. Con ON_ERROR_STOP=1: sobre una base recién
# provisionada (Parte 1 del paso anterior ya corrió) este DDL no tiene ningún motivo esperable
# para fallar — si falla, mejor que el arranque del contenedor lo muestre fuerte en vez de
# seguir como si el esquema estuviera migrado cuando no lo está.
PGPASSWORD="$TURNOS_MIGRADOR_PASSWORD" psql -v ON_ERROR_STOP=1 \
  --username "$TURNOS_MIGRADOR_ROL" --dbname "$POSTGRES_DB" \
  -f /opt/turnos/001_init.sql

echo "[02-migrar] Esquema migrado (rol de MIGRACION = owner). Completando GRANTs (funciones SECURITY DEFINER)..."

# Re-correr provisionar_roles_postgres.sql completo (Parte 1 + Parte 2, sin modificarlo) — hace
# falta repetirlo para que corran de verdad los 2 GRANT EXECUTE ON FUNCTION de la Parte 2, que en
# 01-provisionar-roles.sh fallaron a propósito porque las funciones todavía no existían (ver el
# comentario ahí). El resto de las sentencias del script son idempotentes al repetirse
# (GRANT/REVOKE/ALTER DEFAULT PRIVILEGES no fallan, y el GRANT sobre "ALL TABLES" ahora sí
# alcanza a las tablas reales recién creadas) salvo los 2 CREATE ROLE de la Parte 1, que acá SÍ
# van a fallar con "already exists" — tolerado a propósito, otra vez sin "-v ON_ERROR_STOP=1",
# mismo criterio que 01-provisionar-roles.sh y que el propio comentario de
# provisionar_roles_postgres.sql sobre por qué es seguro ignorar ese error puntual.
# Mismo criterio de "contraseñas crudas, sin comillas extra" que 01-provisionar-roles.sh (ver
# el comentario largo ahí) — :'migrador_password'/:'app_password' en el SQL ya se encargan de
# la cita SQL.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v migrador_rol="$TURNOS_MIGRADOR_ROL" -v migrador_password="$TURNOS_MIGRADOR_PASSWORD" \
  -v app_rol="$TURNOS_APP_ROL" -v app_password="$TURNOS_APP_PASSWORD" \
  -v nombre_db="$POSTGRES_DB" \
  -f /opt/turnos/provisionar_roles_postgres.sql

echo "[02-migrar] Grants completos. Rol de RUNTIME ($TURNOS_APP_ROL) listo para DATABASE_URL de backend."
