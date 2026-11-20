#!/bin/bash
set -euo pipefail
umask 077

: "${DB_ADMIN_USER:?Falta DB_ADMIN_USER}"
: "${DB_ADMIN_PASSWORD:?Falta DB_ADMIN_PASSWORD}"

schedule_pattern='^([0-9*/,-]+ ){4}[0-9*/,-]+$'
if [[ ! $BACKUP_SCHEDULE =~ $schedule_pattern ]]; then
    echo 'BACKUP_SCHEDULE debe tener cinco campos de cron separados por espacios.' >&2
    exit 1
fi

ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf 'export TZ=%q\nexport PATH=%q\nexport DB_ADMIN_USER=%q\nexport PGPASSWORD=%q\nexport BACKUP_WEBHOOK_URL=%q\n' \
    "$TZ" "$PATH" "$DB_ADMIN_USER" "$DB_ADMIN_PASSWORD" "$BACKUP_WEBHOOK_URL" > /run/tpfinal-backup.env

printf '%s /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1\n' "$BACKUP_SCHEDULE" | crontab -
exec cron -f
