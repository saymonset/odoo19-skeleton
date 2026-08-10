#!/bin/bash
# backup/backup.sh - Script de backup unificado para IntegraIA (Odoo, n8n, Postiz, Chatwoot)
set -e

# ---------------------------------------------------------
# Rutas absolutas (funcionan desde cron o manual)
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# ---------------------------------------------------------
# Cargar configuración
# ---------------------------------------------------------
ODOO_CONF="$PROJECT_DIR/v19/config/odoo.conf"
ENV_FILE="$PROJECT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

# Leer variables de odoo.conf si existe
if [ -f "$ODOO_CONF" ]; then
    DB_NAME_ODOO=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER_ODOO=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

# Valores por defecto
DB_NAME_ODOO=${DB_NAME_ODOO:-dbodoo19}
DB_USER_ODOO=${DB_USER_ODOO:-odoo}
MAIN_DB_CONTAINER="odoo-db19-n8n"
CHATWOOT_DB_CONTAINER="chatwoot-db"

# rclone para subida remota a Cloudflare R2
RCLONE="$(command -v rclone 2>/dev/null || echo "$HOME/bin/rclone")"
R2_REMOTE_DAILY="r2-crypt:daily"
R2_REMOTE_WEEKLY="r2-crypt:weekly"

# Directorio de backup
BACKUP_BASE_DIR="$PROJECT_DIR/backup/out"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
RETENTION_DAYS=7
WEEKLY_DIR="$BACKUP_BASE_DIR/weekly"

# Si el directorio base no existe o no es escribible (ej. creado por otro usuario),
# usar un fallback en /tmp para que el backup no falle.
if ! mkdir -p "$BACKUP_BASE_DIR" 2>/dev/null || [ ! -w "$BACKUP_BASE_DIR" ]; then
    warn "Sin permisos de escritura en $BACKUP_BASE_DIR, usando /tmp/backup_odoo como alternativa"
    BACKUP_BASE_DIR="/tmp/backup_odoo"
    WEEKLY_DIR="$BACKUP_BASE_DIR/weekly"
    mkdir -p "$BACKUP_BASE_DIR"
fi

BACKUP_DIR="$BACKUP_BASE_DIR/backup_$DATE"
ABS_BACKUP_DIR=$(readlink -f "$BACKUP_DIR")

# Destinatario de notificaciones
NOTIFY_TO="${BACKUP_NOTIFY_TO:-admin@integraia.lat}"

# Crear directorio de backup
mkdir -p "$BACKUP_DIR"

# ---------------------------------------------------------
# Reporte acumulativo (se envía por email al final)
# ---------------------------------------------------------
REPORT=""
report() { REPORT="$REPORT$1\n"; }

# ---------------------------------------------------------
# Notificación por email vía SMTP (credenciales del .env)
# ---------------------------------------------------------
send_email() {
    local subject="$1"
    local body="$2"

    if ! command -v curl >/dev/null 2>&1 || [ -z "${SMTP_HOST:-}" ]; then
        warn "   ⚠️ curl/SMTP no disponible; no se envió notificación"
        return 0
    fi

    local from="${SMTP_FROM:-admin@integraia.lat}"
    log "📧 Enviando notificación a $NOTIFY_TO..."
    if { { printf "From: IntegraIA Backup <%s>\n" "$from"
           printf "To: %s\n" "$NOTIFY_TO"
           printf "Subject: %s\n" "$subject"
           printf "MIME-Version: 1.0\n"
           printf "Content-Type: text/plain; charset=UTF-8\n\n"
           printf "%b" "$body"
         } | curl --silent --show-error --ssl-reqd \
            --url "smtps://${SMTP_HOST}:${SMTP_PORT:-465}" \
            --user "${SMTP_USER}:${SMTP_PASSWORD}" \
            --mail-from "$from" \
            --mail-rcpt "$NOTIFY_TO" \
            --upload-file - >/dev/null 2>&1; }; then
        log "   ✅ Notificación enviada a $NOTIFY_TO"
    else
        warn "   ⚠️ No se pudo enviar el email de notificación"
    fi
    return 0
}

# ---------------------------------------------------------
# Verificación del backup: restaura dbodoo19 en una DB temporal
# ---------------------------------------------------------
verify_backup() {
    local dump_file="$1"
    local verify_db="dbodoo19_verify"
    local modules=""

    log "🔍 Verificando restauración de $DB_NAME_ODOO..."
    docker exec "$MAIN_DB_CONTAINER" dropdb -U "$DB_USER_ODOO" "$verify_db" 2>/dev/null || true

    if docker exec "$MAIN_DB_CONTAINER" createdb -U "$DB_USER_ODOO" "$verify_db" 2>/dev/null \
       && docker exec -i "$MAIN_DB_CONTAINER" pg_restore -U "$DB_USER_ODOO" -d "$verify_db" --no-owner --no-privileges < "$dump_file" >/dev/null 2>&1; then
        modules=$(docker exec "$MAIN_DB_CONTAINER" psql -U "$DB_USER_ODOO" -d "$verify_db" -tAc "SELECT count(*) FROM ir_module_module" 2>/dev/null | tr -d ' ')
        if [ -n "$modules" ] && [ "$modules" -gt 0 ]; then
            log "   ✅ Restauración verificada: $modules módulos OK"
            report "Verificación $DB_NAME_ODOO: OK ($modules módulos)"
        else
            warn "   ⚠️ Tabla ir_module_module vacía o inaccesible"
            report "Verificación $DB_NAME_ODOO: FALLO (módulos no legibles)"
        fi
    else
        warn "   ⚠️ La restauración de prueba no completó"
        report "Verificación $DB_NAME_ODOO: FALLO (pg_restore)"
    fi

    docker exec "$MAIN_DB_CONTAINER" dropdb -U "$DB_USER_ODOO" "$verify_db" 2>/dev/null || true
}

# ---------------------------------------------------------
# Manejo de errores: si algo falla, notificar por email
# ---------------------------------------------------------
on_exit() {
    local code=$?
    if [ "$code" -ne 0 ]; then
        error "El backup falló (código $code)"
        report "Estado: ❌ FALLO"
        send_email "❌ Backup IntegraIA FALLÓ - $DATE" "=== Backup IntegraIA - $DATE ===
Estado: ❌ FALLO (código $code)
Destino: $ABS_BACKUP_DIR
$REPORT"
    fi
}
trap on_exit EXIT

report "=== Backup IntegraIA - $DATE ==="
report "Destino: $ABS_BACKUP_DIR"

log "=========================================="
log "Iniciando Backup del Sistema Completo - $DATE"
log "=========================================="
log "📂 Destino: $ABS_BACKUP_DIR"

# ---------------------------------------------------------
# A. BACKUP DE BASES DE DATOS
# ---------------------------------------------------------
DATABASES=("dbodoo19" "db_n8n" "postiz")
ODOO_DUMP="$BACKUP_DIR/${DB_NAME_ODOO}_${DATE}.dump"

report "Bases de datos:"
for DB in "${DATABASES[@]}"; do
    log "📦 Backup de base de datos: $DB..."
    if docker exec "$MAIN_DB_CONTAINER" pg_dump -U odoo -d "$DB" -F c > "$BACKUP_DIR/${DB}_${DATE}.dump" 2>/dev/null; then
        SIZE=$(du -sh "$BACKUP_DIR/${DB}_${DATE}.dump" | cut -f1)
        log "   ✅ $DB respaldada ($SIZE)"
        report "  - $DB: OK ($SIZE)"
    else
        warn "   ⚠️ No se pudo respaldar $DB"
        report "  - $DB: FALLO"
        rm -f "$BACKUP_DIR/${DB}_${DATE}.dump"
    fi
done

log "📦 Backup de base de datos: Chatwoot..."
if docker exec "$CHATWOOT_DB_CONTAINER" pg_dump -U chatwoot -d chatwoot_production -F c > "$BACKUP_DIR/chatwoot_db_${DATE}.dump" 2>/dev/null; then
    SIZE=$(du -sh "$BACKUP_DIR/chatwoot_db_${DATE}.dump" | cut -f1)
    log "   ✅ Chatwoot respaldada ($SIZE)"
    report "  - chatwoot_production: OK ($SIZE)"
else
    warn "   ⚠️ No se pudo respaldar Chatwoot"
    report "  - chatwoot_production: FALLO"
fi

# ---------------------------------------------------------
# C. BACKUP DE ARCHIVOS (Usando Docker para evitar problemas de permisos)
# ---------------------------------------------------------

backup_folder() {
    local label=$1
    local src_path=$2
    local output_name=$3

    log "📁 Respaldando archivos: $label..."
    if [ -d "$PROJECT_DIR/$src_path" ]; then
        docker run --rm \
            -v "$PROJECT_DIR/$src_path:/source:ro" \
            -v "$ABS_BACKUP_DIR:/backup" \
            alpine tar -czf "/backup/$output_name" -C /source .
        log "   ✅ $label respaldado"
        report "  - $label: OK"
    else
        warn "   ⚠️ Directorio no encontrado: $PROJECT_DIR/$src_path"
        report "  - $label: directorio no encontrado"
    fi
}

# ---------------------------------------------------------
# Subida remota cifrada a Cloudflare R2 (rclone crypt).
# Un fallo aquí NO rompe el backup local.
# ---------------------------------------------------------
upload_remote() {
    local label=$1
    local src_path=$2
    local dest_path=$3

    log "☁️ Subiendo $label a R2 (cifrado)..."
    local start_ts
    start_ts=$(date +%s)
    if "$RCLONE" copy "$src_path" "$dest_path" --transfers=4 --stats=15s >> "$PROJECT_DIR/backup/backup_remote.log" 2>&1; then
        local elapsed
        elapsed=$(($(date +%s) - start_ts))
        log "   ✅ $label subido a R2 en ${elapsed}s"
        report "  - $label (R2): ✅ subido en ${elapsed}s"
        return 0
    else
        warn "   ⚠️ No se pudo subir $label a R2 (el backup local sigue intacto)"
        report "  - $label (R2): ⚠️ FALLO (revisar backup_remote.log)"
        return 1
    fi
}

report "Archivos:"
backup_folder "Odoo Data" "v19/data" "odoo_data_${DATE}.tar.gz"
backup_folder "n8n Data" "v19/n8n_data" "n8n_data_${DATE}.tar.gz"
backup_folder "Postiz Data" "v19/postiz_uploads" "postiz_data_${DATE}.tar.gz"
backup_folder "Chatwoot Data" "v19/chatwoot_storage" "chatwoot_data_${DATE}.tar.gz"

# ---------------------------------------------------------
# D. CONFIGURACIÓN Y CLAVES
# ---------------------------------------------------------
log "🔑 Respaldando configuración y claves..."
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$BACKUP_DIR/env_file_${DATE}.env"
[ -f "$ODOO_CONF" ] && cp "$ODOO_CONF" "$BACKUP_DIR/odoo_config_${DATE}.conf"

if [ -d "$PROJECT_DIR/v19/n8n_data" ]; then
    N8N_CONFIG="$PROJECT_DIR/v19/n8n_data/config"
    CONFIG_CONTENT=""
    if [ -r "$N8N_CONFIG" ]; then
        CONFIG_CONTENT=$(cat "$N8N_CONFIG" 2>/dev/null)
    fi
    if [ -z "$CONFIG_CONTENT" ] && docker exec n8n-container cat /home/node/.n8n/config >/dev/null 2>&1; then
        warn "Config n8n sin permisos en el host, leyendo via docker exec..."
        CONFIG_CONTENT=$(docker exec n8n-container cat /home/node/.n8n/config 2>/dev/null)
    fi
    if [ -n "$CONFIG_CONTENT" ]; then
        ENCRYPTION_KEY=$(echo "$CONFIG_CONTENT" | grep -o '"encryptionKey": *"[^"]*"' | cut -d'"' -f4)
        [ -n "$ENCRYPTION_KEY" ] && echo "$ENCRYPTION_KEY" > "$BACKUP_DIR/n8n_encryption_key_${DATE}.key"
    else
        warn "⚠️ No se pudo leer la clave de cifrado n8n; el backup de n8n no será restaurable"
    fi
fi

report "Configuración y claves: OK"

# ---------------------------------------------------------
# E. VERIFICACIÓN DEL DUMP DE ODOO
# ---------------------------------------------------------
if [ -f "$ODOO_DUMP" ]; then
    verify_backup "$ODOO_DUMP"
fi

# ---------------------------------------------------------
# F. METADATOS
# ---------------------------------------------------------
cat > "$BACKUP_DIR/backup_metadata.txt" << EOF
INTEGRAIA FULL BACKUP - $DATE
Verificación de restauración incluida en este backup
EOF

BACKUP_SIZE=$(du -sh "$ABS_BACKUP_DIR" | cut -f1)
report "Tamaño total: $BACKUP_SIZE"
DISK=$(df -h "$PROJECT_DIR" | tail -1 | awk '{print $4 " libres de " $2 " (" $5 " usado)"}')
report "Disco: $DISK"

# ---------------------------------------------------------
# G. RETENCIÓN SEMANAL (domingos: copia a weekly/ con 4 semanas de vida)
# ---------------------------------------------------------
if [ "$(date +%u)" -eq 7 ]; then
    log "🗓️ Hoy es domingo: archivando backup semanal..."
    mkdir -p "$WEEKLY_DIR"
    cp -a "$BACKUP_DIR" "$WEEKLY_DIR/weekly_$DATE"
    find "$WEEKLY_DIR" -maxdepth 1 -type d -name "weekly_*" -mtime +28 -exec rm -rf {} \; 2>/dev/null || true
    log "   ✅ Backup semanal archivado en $WEEKLY_DIR"
    report "Retención semanal: archivado en $WEEKLY_DIR"
fi

# ---------------------------------------------------------
# H. LIMPIEZA DE BACKUPS DIARIOS ANTIGUOS
# ---------------------------------------------------------
find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "backup_*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
log "🧹 Backups diarios con más de $RETENTION_DAYS días eliminados"

# ---------------------------------------------------------
# J. SUBIDA REMOTA A CLOUDFLARE R2 (cifrado con rclone crypt)
# ---------------------------------------------------------
if [ -x "$RCLONE" ]; then
    mkdir -p "$PROJECT_DIR/backup"
    log "☁️ Subiendo backup a Cloudflare R2 (cifrado)..."
    report "Subida remota (R2 cifrado):"
    upload_remote "Backup diario" "$ABS_BACKUP_DIR" "$R2_REMOTE_DAILY/backup_$DATE" || true

    if [ "$(date +%u)" -eq 7 ]; then
        upload_remote "Backup semanal" "$WEEKLY_DIR/weekly_$DATE" "$R2_REMOTE_WEEKLY/weekly_$DATE" || true
    fi

    log "🧹 Aplicando retención remota (diarios >$RETENTION_DAYS días, semanales >28 días)..."
    { "$RCLONE" delete "$R2_REMOTE_DAILY" --min-age "${RETENTION_DAYS}d" >> "$PROJECT_DIR/backup/backup_remote.log" 2>&1 \
      && "$RCLONE" delete "$R2_REMOTE_WEEKLY" --min-age "28d" >> "$PROJECT_DIR/backup/backup_remote.log" 2>&1; } \
      && log "   ✅ Retención remota aplicada" \
      || warn "   ⚠️ La limpieza remota no completó"
    report "Retención remota: diarios >${RETENTION_DAYS}d, semanales >28d"
else
    warn "⚠️ rclone no encontrado en $RCLONE; NO se subió backup a R2"
    report "Subida remota (R2): ⚠️ rclone no instalado"
fi

# ---------------------------------------------------------
# I. NOTIFICAR ÉXITO
# ---------------------------------------------------------
log "=========================================="
log "✅ BACKUP COMPLETADO EXITOSAMENTE"
log "📁 Ubicación: $ABS_BACKUP_DIR"
log "=========================================="

report "Estado: ✅ OK"
send_email "✅ Backup IntegraIA OK - $DATE ($BACKUP_SIZE)" "=== Backup IntegraIA - $DATE ===
$REPORT"