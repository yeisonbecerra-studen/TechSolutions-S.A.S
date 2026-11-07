#!/usr/bin/env bash
# =====================================================================
# TechSolutions S.A.S. - Herramienta de administración DBA
# Uso: ./ts.sh <comando>      (./ts.sh ayuda para ver la lista)
# =====================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

DB=techsolutions
DBA=dba_admin
BACKUP_DIR=backups
RETENCION_DIAS=${RETENCION_DIAS:-7}

# psql dentro del contenedor. Uso: psql_db [usuario] [args...]
psql_db() { local u=${1:-$DBA}; shift || true; docker compose exec -T db psql -U "$u" -d "$DB" "$@"; }
sql_file() { psql_db "${2:-$DBA}" -f - < "sql/$1"; }
log() { printf '\n\033[1;36m>> %s\033[0m\n' "$*"; }

cmd_up() {
    docker compose up -d --build
    log "Esperando a que la base de datos esté lista..."
    until docker compose exec -T db pg_isready -U "$DBA" -d "$DB" -q; do sleep 1; done
    log "Listo:  App http://localhost:8081   pgAdmin http://localhost:5050   PostgreSQL localhost:5433"
}

cmd_down()  { docker compose down; }

cmd_reset() {
    read -rp "Esto BORRA la base y la recrea desde cero. ¿Continuar? (si/no) " r
    [[ $r == si ]] || exit 1
    docker compose down -v
    cmd_up
}

cmd_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts file inicio sha size
    ts=$(date +%Y%m%d_%H%M%S)
    file="$BACKUP_DIR/${DB}_$ts.dump"
    inicio=$(date -Iseconds)
    log "Respaldo completo (pg_dump formato custom, comprimido) -> $file"
    docker compose exec -T db pg_dump -U "$DBA" -d "$DB" -Fc -Z 6 > "$file"

    log "Verificando que el archivo sea restaurable (pg_restore --list)"
    docker compose exec -T db pg_restore --list < "$file" > /dev/null

    sha=$(sha256sum "$file" | cut -d' ' -f1)
    size=$(stat -c%s "$file")
    echo "$sha  $(basename "$file")" > "$file.sha256"
    psql_db "$DBA" -q -v ON_ERROR_STOP=1 -c \
        "INSERT INTO auditoria.log_respaldos (archivo, tamano_bytes, sha256, inicio, estado)
         VALUES ('$(basename "$file")', $size, '$sha', '$inicio', 'OK');"
    echo "Tamaño: $(numfmt --to=iec "$size")  SHA-256: $sha"

    log "Retención: se eliminan respaldos con más de $RETENCION_DIAS días"
    find "$BACKUP_DIR" -name "${DB}_*.dump*" -mtime +"$RETENCION_DIAS" -print -delete
    ls -lh "$BACKUP_DIR"/*.dump | tail -5
}

ultimo_backup() { ls -1t "$BACKUP_DIR"/${DB}_*.dump 2>/dev/null | head -1; }

verificar_checksum() {
    log "Verificando integridad (SHA-256) de $1"
    (cd "$(dirname "$1")" && sha256sum -c "$(basename "$1").sha256")
}

# Prueba de restauración en una base aparte, sin tocar producción
cmd_verificar() {
    local file=${1:-$(ultimo_backup)}
    [[ -n $file ]] || { echo "No hay respaldos. Ejecute ./ts.sh backup"; exit 1; }
    verificar_checksum "$file"
    log "Restaurando $file en la base de prueba techsolutions_verif"
    psql_db "$DBA" -q -c "DROP DATABASE IF EXISTS techsolutions_verif;" -c "CREATE DATABASE techsolutions_verif;"
    docker compose exec -T db pg_restore -U "$DBA" -d techsolutions_verif --exit-on-error < "$file"
    log "Conteos en la copia restaurada"
    docker compose exec -T db psql -U "$DBA" -d techsolutions_verif -f - < sql/conteos.sql
    psql_db "$DBA" -q -c "DROP DATABASE techsolutions_verif;"
    log "Respaldo verificado: es restaurable"
}

# Falla controlada: el practicante con privilegios excesivos borra los tickets
cmd_falla() {
    log "Estado ANTES de la falla"
    sql_file conteos.sql
    log "SIMULACIÓN: practicante_tmp ejecuta DELETE FROM app.tickets (error humano)"
    psql_db practicante_tmp -c "DELETE FROM app.tickets;" || true
    log "Estado DESPUÉS de la falla"
    sql_file conteos.sql
}

# Recuperación: restaura SOLO el esquema app y conserva la evidencia de auditoría
cmd_restaurar() {
    local file=${1:-$(ultimo_backup)}
    [[ -n $file ]] || { echo "No hay respaldos. Ejecute ./ts.sh backup"; exit 1; }
    verificar_checksum "$file"
    log "Deteniendo la app para evitar escrituras durante la recuperación"
    docker compose stop app
    log "Restaurando esquema app desde $file (una sola transacción)"
    docker compose exec -T db pg_restore -U "$DBA" -d "$DB" -n app --clean --if-exists \
        --single-transaction --exit-on-error < "$file"
    docker compose start app
    log "Estado DESPUÉS de la recuperación"
    sql_file conteos.sql
}

cmd_mantenimiento() {
    mkdir -p logs
    local out="logs/mantenimiento_$(date +%Y%m%d_%H%M%S).log"
    sql_file mantenimiento.sql | tee "$out"
    log "Reporte guardado en $out"
}

# Programa respaldo diario (02:00) y mantenimiento semanal con systemd (usuario)
cmd_programar() {
    local dir=~/.config/systemd/user here
    here=$(pwd)
    mkdir -p "$dir"
    for t in backup mantenimiento; do
        cat > "$dir/techsolutions-$t.service" <<EOF
[Unit]
Description=TechSolutions $t

[Service]
Type=oneshot
ExecStart=$here/ts.sh $t
EOF
    done
    cat > "$dir/techsolutions-backup.timer" <<'EOF'
[Unit]
Description=Respaldo diario TechSolutions

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    cat > "$dir/techsolutions-mantenimiento.timer" <<'EOF'
[Unit]
Description=Mantenimiento semanal TechSolutions

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now techsolutions-backup.timer techsolutions-mantenimiento.timer
    systemctl --user list-timers 'techsolutions-*'
}

cmd_logs() { docker compose logs --tail "${1:-30}" db; }

cmd_ayuda() {
    cat <<'EOF'
TechSolutions S.A.S. - comandos

  Entorno        up | down | reset | psql [usuario] | logs [n]
  Diagnóstico    diagnostico
  Seguridad      seguridad        (GRANT/REVOKE y pruebas de permisos)
  Auditoría      auditoria        (quién cambió qué)
  Respaldo       backup | verificar [archivo]
  Recuperación   falla | restaurar [archivo]
  Mantenimiento  mantenimiento | programar   (timers systemd)
  Rendimiento    optimizar | monitoreo
EOF
}

case "${1:-ayuda}" in
    up) cmd_up ;;
    down) cmd_down ;;
    reset) cmd_reset ;;
    psql) docker compose exec db psql -U "${2:-$DBA}" -d "$DB" ;;
    logs) cmd_logs "${2:-30}" ;;
    diagnostico) sql_file diagnostico.sql ;;
    seguridad) sql_file seguridad.sql ;;
    auditoria) sql_file auditoria.sql ;;
    backup) cmd_backup ;;
    verificar) cmd_verificar "${2:-}" ;;
    falla) cmd_falla ;;
    restaurar) cmd_restaurar "${2:-}" ;;
    mantenimiento) cmd_mantenimiento ;;
    programar) cmd_programar ;;
    optimizar) sql_file optimizacion.sql ;;
    monitoreo) sql_file monitoreo.sql ;;
    *) cmd_ayuda ;;
esac
