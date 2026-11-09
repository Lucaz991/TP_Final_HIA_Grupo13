#!/bin/bash
set -e

# Ajustar permisos de las carpetas clave para el usuario postgres
chown -R postgres:postgres /var/lib/postgresql /etc/patroni
chmod 700 /var/lib/postgresql/data

# Expandir variables de entorno en patroni.yml
envsubst < /etc/patroni/patroni.yml > /tmp/patroni.yml.expanded
cp /tmp/patroni.yml.expanded /etc/patroni/patroni.yml

# Ejecutar patroni con el usuario postgres
exec gosu postgres patroni /etc/patroni/patroni.yml
