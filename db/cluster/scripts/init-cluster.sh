#!/bin/bash
set -eu

echo "=== [Patroni post_init] Inicializando base de datos y usuarios del clúster ==="

psql -v ON_ERROR_STOP=1 \
    --username="$DB_ADMIN_USER" \
    --dbname=postgres <<SQL

-- 1. Crear base de datos de la aplicacion (tpFinal)
SELECT 'CREATE DATABASE "tpFinal"'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'tpFinal'
)\gexec

-- 2. Asegurar usuario postgres para compatibilidad total del proyecto
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = '$POSTGRES_USER'
    ) THEN
        CREATE USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
    ELSE
        ALTER USER "$POSTGRES_USER" WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';
    END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE "tpFinal" TO "$POSTGRES_USER";

-- 3. Usuario de aplicacion
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = '$DB_APP_USER'
    ) THEN
        CREATE USER "$DB_APP_USER" WITH PASSWORD '$DB_APP_PASSWORD';
    END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE "tpFinal" TO "$DB_APP_USER";

-- 4. Usuario de monitorizacion
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_roles WHERE rolname = '$DB_MONITOR_USER'
    ) THEN
        CREATE USER "$DB_MONITOR_USER" WITH PASSWORD '$DB_MONITOR_PASSWORD';
    END IF;
END
\$\$;

GRANT pg_monitor TO "$DB_MONITOR_USER";

SQL

echo "=== [Patroni post_init] Inicialización completada exitosamente ==="
