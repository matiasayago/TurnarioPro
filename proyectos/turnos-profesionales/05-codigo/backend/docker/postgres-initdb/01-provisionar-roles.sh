#!/bin/sh
# Turnos Profesionales (TURNOS-2026-001) — DevOps, 2026-08-09/10.
# Paso 1/2 de la separación de roles de Postgres (rol de MIGRACIÓN vs. rol de RUNTIME) para
# docker-compose. Corre AUTOMÁTICAMENTE solo la primera vez que el volumen
# "turnos_postgres_data" está vacío — mecanismo estándar de docker-entrypoint-initdb.d de la
# imagen oficial postgres:16-alpine (se ejecuta, en orden alfabético junto al resto de los
# scripts de ese directorio, ANTES de que el contenedor acepte conexiones normales, y por lo
# tanto antes de que su healthcheck pase y de que "backend" — depends_on: condition:
# service_healthy — pueda arrancar).
#
# POR QUÉ EXISTE ESTA SEPARACIÓN: ver el bloque grande "Separación owner/runtime y FORCE ROW
# LEVEL SECURITY" en ../../../database/migrations/001_init.sql y
# ../../../database/scripts/provisionar_roles_postgres.sql (DBA). Resumen: el rol único de hoy
# (POSTGRES_USER=turnos) es SUPERUSUARIO del cluster (así lo crea esta imagen oficial vía esa
# variable) — un superusuario bypassea Row Level Security siempre, incluso con FORCE ROW LEVEL
# SECURITY. Hace falta un rol de MIGRACIÓN (no superusuario, corre el DDL una vez, queda owner
# de las tablas) separado de un rol de RUNTIME (no superusuario, sin BYPASSRLS, es el que usa
# la app) para que RLS tenga efecto real acá.
#
# Nota Windows/bind mount: este archivo no necesita permiso de ejecución (chmod +x) — un bind
# mount desde un host Windows normalmente no preserva el bit +x de Unix. No hace falta: el
# entrypoint de la imagen oficial hace `. "$f"` (source) para cualquier *.sh que no sea
# ejecutable, en vez de invocarlo directo — funciona igual sin +x.
#
# Este script corre ANTES de que exista ninguna tabla (001_init.sql corre recién en el paso 2,
# ver 02-migrar-y-grants-finales.sh) porque el rol de MIGRACIÓN tiene que existir ANTES de
# poder conectarse como él para correr ese DDL.
set -e

echo "[01-provisionar-roles] Creando rol de MIGRACION ($TURNOS_MIGRADOR_ROL) y rol de RUNTIME ($TURNOS_APP_ROL)..."

# Corre TODO ../../../database/scripts/provisionar_roles_postgres.sql (Parte 1 + Parte 2, tal
# cual lo dejó DBA, sin modificarlo) — A PROPÓSITO SIN "-v ON_ERROR_STOP=1" acá. Ese script está
# diseñado en 2 partes pensadas para correr en 2 momentos distintos (Parte 1: crear roles; Parte
# 2: GRANTs sobre el esquema YA migrado) — acá, corriendo ANTES de 001_init.sql, ninguna tabla ni
# función existe todavía, así que las 2 sentencias finales de la Parte 2 (GRANT EXECUTE ON
# FUNCTION turno_ocupacion_publica/turno_propio_para_gestion) VAN A FALLAR ACÁ, A PROPÓSITO
# ("function ... does not exist" — es esperable, no un error real, ver el paso 2 donde se
# completan). Sin ON_ERROR_STOP, psql no aborta por eso: imprime el error y sigue con el resto
# del archivo — mismo comportamiento que el propio script anticipa en su comentario ("Postgres
# no soporta CREATE ROLE IF NOT EXISTS... es seguro ignorar ESE error puntual y seguir con el
# resto"). El resto de las sentencias de ese script SÍ corren completas acá: los 2 CREATE ROLE,
# los GRANT/REVOKE a nivel de esquema/base, y el ALTER DEFAULT PRIVILEGES (aplica a las tablas
# que cree el rol de MIGRACIÓN de acá en adelante, incluidas las que va a crear 001_init.sql en
# el paso 2 — ver ese script para el detalle).
#
# OJO con las contraseñas: se pasan CRUDAS (sin comillas extra alrededor del valor), a
# diferencia del ejemplo de invocación del propio header de provisionar_roles_postgres.sql
# (-v migrador_password="'CAMBIAR_1'"). Ese script usa :'migrador_password' en el SQL
# (sustitución YA entre comillas -- psql envuelve y escapa el valor solo); si acá además
# envolviéramos el valor en comillas literales, quedaría doblemente citado y la contraseña
# real guardada incluiría esas comillas de más -- rompe la reconexión posterior con el valor
# limpio (ver 02-migrar-y-grants-finales.sh, que se conecta con
# PGPASSWORD="$TURNOS_MIGRADOR_PASSWORD" tal cual, sin comillas extra).
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v migrador_rol="$TURNOS_MIGRADOR_ROL" -v migrador_password="$TURNOS_MIGRADOR_PASSWORD" \
  -v app_rol="$TURNOS_APP_ROL" -v app_password="$TURNOS_APP_PASSWORD" \
  -v nombre_db="$POSTGRES_DB" \
  -f /opt/turnos/provisionar_roles_postgres.sql

# GRANT adicional que NO está en provisionar_roles_postgres.sql a propósito (ese script deja
# expresamente afuera de su alcance el privilegio de CREATE sobre el esquema para el rol de
# RUNTIME — ver ahí mismo el REVOKE CREATE ON SCHEMA public FROM :"app_rol"). El rol de
# MIGRACIÓN sí necesita CREATE sobre "public" para poder correr 001_init.sql (CREATE
# EXTENSION/TYPE/TABLE) en el paso 2: desde Postgres 15, el esquema "public" ya no le otorga
# CREATE a PUBLIC por defecto, y ser owner de la base (POSTGRES_USER=turnos) no se hereda
# automáticamente a un rol nuevo sin este GRANT explícito. Con ON_ERROR_STOP=1 acá sí (a
# diferencia de la invocación de arriba): este GRANT puntual no tiene ningún motivo esperable
# para fallar, así que si falla, mejor que este script corte de forma ruidosa.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v migrador_rol="$TURNOS_MIGRADOR_ROL" \
  -c 'GRANT CREATE ON SCHEMA public TO :"migrador_rol";'

echo "[01-provisionar-roles] Roles provisionados (ver 02-migrar-y-grants-finales.sh para el resto de la secuencia)."
