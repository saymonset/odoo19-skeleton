#!/bin/bash
# backup/backup.sh - Script de backup unificado para Odoo (Leads)
set -e

# 1. Cargar configuración
ODOO_CONF="./v19-leads/config/odoo.conf"
ENV_FILE="./.env"

if [ -f "$ENV_FILE" ]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key="$(echo "$key" | xargs)"
        value="${value%%[[:space:]]#*}"
        value="$(echo "$value" | xargs)"
        [[ -n "$key" ]] && export "$key=$value"
    done < "$ENV_FILE"
fi

# Leer variables de odoo.conf si existe
if [ -f "$ODOO_CONF" ]; then
    DB_NAME_ODOO=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER_ODOO=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

# Valores por defecto
DB_NAME_ODOO=${DB_NAME_ODOO:-dbodoo19}
DB_USER_ODOO=${DB_USER_ODOO:-odoo}
MAIN_DB_CONTAINER="odoo-db19-leads"

# Directorio de backup
BACKUP_BASE_DIR="./backup/out"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$BACKUP_BASE_DIR/backup_$DATE"
ABS_BACKUP_DIR=$(readlink -m "$BACKUP_DIR")
RETENTION_DAYS=7

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

# Crear directorio de backup
mkdir -p "$BACKUP_DIR"

log "=========================================="
log "Iniciando Backup del Sistema - $DATE"
log "=========================================="
log "Destino: $BACKUP_DIR"

# ---------------------------------------------------------
# A. BACKUP DE BASE DE DATOS
# ---------------------------------------------------------
DATABASES=("dbodoo19")

for DB in "${DATABASES[@]}"; do
    log "Backup de base de datos: $DB..."
    if docker exec $MAIN_DB_CONTAINER pg_dump -U odoo -d "$DB" -F c > "$BACKUP_DIR/${DB}_${DATE}.dump" 2>/dev/null; then
        SIZE=$(du -sh "$BACKUP_DIR/${DB}_${DATE}.dump" | cut -f1)
        log "   $DB respaldada ($SIZE)"
    else
        warn "   No se pudo respaldar $DB"
        rm -f "$BACKUP_DIR/${DB}_${DATE}.dump"
    fi
done

# ---------------------------------------------------------
# B. BACKUP DE ARCHIVOS
# ---------------------------------------------------------

backup_folder() {
    local label=$1
    local src_path=$2
    local output_name=$3
    
    log "Respaldando archivos: $label..."
    if [ -d "$src_path" ]; then
        docker run --rm \
            -v "$(pwd)/$src_path:/source:ro" \
            -v "$ABS_BACKUP_DIR:/backup" \
            alpine tar -czf "/backup/$output_name" -C /source .
        log "   $label respaldado"
    else
        warn "   Directorio no encontrado: $src_path"
    fi
}

backup_folder "Odoo Data" "v19-leads/odoo-web-data" "odoo_data_${DATE}.tar.gz"

# ---------------------------------------------------------
# C. CONFIGURACIÓN
# ---------------------------------------------------------
log "Respaldando configuracion..."
[ -f "./.env" ] && cp ./.env "$BACKUP_DIR/env_file_${DATE}.env"
[ -f "./v19-leads/config/odoo.conf" ] && cp ./v19-leads/config/odoo.conf "$BACKUP_DIR/odoo_config_${DATE}.conf"

# ---------------------------------------------------------
# D. METADATOS Y LIMPIEZA
# ---------------------------------------------------------
cat > "$BACKUP_DIR/backup_metadata.txt" << EOF
ODOO LEADS BACKUP - $DATE
EOF

find "$BACKUP_BASE_DIR" -type d -name "backup_*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true

log "=========================================="
log "BACKUP COMPLETADO"
log "Ubicacion: $BACKUP_DIR"
log "=========================================="
