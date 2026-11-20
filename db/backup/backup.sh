#!/bin/bash
set -euo pipefail
umask 077

source /run/tpfinal-backup.env
export PGCONNECT_TIMEOUT=10

exec 9>/backups/.backup.lock
if ! flock -n 9; then
    echo 'Ya hay un respaldo en ejecución.'
    exit 0
fi

nombre="tpFinal-$(date +%Y%m%d-%H%M%S)-$(cut -c1-8 /proc/sys/kernel/random/uuid)"
archivo="/backups/$nombre.dump"
inventario="/backups/$nombre-inventario.txt"
registro="/backups/$nombre-registro.json"
inicio=$(date -Iseconds)
segundos_inicio=$SECONDS
paso='comprobar la conexión al líder'
hash=''
bytes=0
segundos_backup=0

registrar_resultado() {
    local codigo=$? estado error
    if (( codigo == 0 )); then
        estado='backup_verificado_restauracion_pendiente'
        error=''
    else
        estado='fallido'
        error="No se pudo $paso."
        rm -f -- "$archivo.partial" "$inventario.partial"
    fi

    if jq -n --arg inicio "$inicio" --arg fin "$(date -Iseconds)" \
        --arg estado "$estado" --arg error "$error" --arg archivo "$archivo" \
        --arg sha256 "$hash" --argjson bytes "$bytes" \
        --argjson segundos "$((SECONDS - segundos_inicio))" \
        --argjson segundos_backup "$segundos_backup" \
        '{base: "tpFinal", conexion: "proxy:5465", inicio: $inicio, fin: $fin,
          estado: $estado, restauracion_verificada: false, segundos_totales: $segundos}
         + (if $error == "" then
              {archivo: $archivo, bytes: $bytes, sha256: $sha256,
               segundos_backup_e_inventario: $segundos_backup}
            else {error: $error} end)' > "$registro.partial" \
        && mv -- "$registro.partial" "$registro"; then
        echo "$estado — $registro"
        if ! curl --fail --silent --show-error --max-time 15 \
            -H 'Content-Type: application/json' --data-binary "@$registro" \
            "$BACKUP_WEBHOOK_URL" >/dev/null; then
            echo 'No se pudo notificar a n8n. El resultado está en el registro.' >&2
        fi
    else
        echo "No se pudo guardar el registro $registro" >&2
        exit 1
    fi
    exit "$codigo"
}
trap registrar_resultado EXIT

conexion=(-w -h proxy -p 5465 -U "$DB_ADMIN_USER" -d tpFinal)
origen=$(psql "${conexion[@]}" -X -At -v ON_ERROR_STOP=1 \
    -c "SELECT current_database() || '|' || pg_is_in_recovery()::text")
[[ $origen == 'tpFinal|false' ]]

paso='generar el respaldo'
pg_dump "${conexion[@]}" --format=custom --file="$archivo.partial"
paso='leer el inventario del respaldo'
pg_restore --list "$archivo.partial" > "$inventario.partial"
segundos_backup=$((SECONDS - segundos_inicio))
paso='verificar y guardar el respaldo'
hash=$(sha256sum "$archivo.partial")
hash=${hash%% *}
bytes=$(stat -c %s "$archivo.partial")
mv -- "$inventario.partial" "$inventario"
mv -- "$archivo.partial" "$archivo"
