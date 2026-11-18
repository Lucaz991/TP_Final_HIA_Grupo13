#!/bin/sh
set -eu
# El backend posee su base pero no es superusuario ni puede crear otras bases.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=app_password="$SECURITY_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE h24_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_password') \gexec
ALTER DATABASE h24_security_test OWNER TO h24_app;
SQL
