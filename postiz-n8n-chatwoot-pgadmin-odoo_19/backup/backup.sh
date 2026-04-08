#!/bin/bash
set -e

# Configuración
BACKUP_DIR="./v19/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DB_CONTAINER="odoo-db19-n8n"
DB_NAME="dbodoo19"
RETENTION_DAYS=7

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Crear directorio
mkdir -p $BACKUP_DIR

log "=========================================="
log "Iniciando Backup - $DATE"
log "=========================================="

# 1. Backup de base de datos
log "📦 Backup de base de datos Odoo..."
docker exec $DB_CONTAINER pg_dump -U odoo -d $DB_NAME -F c > "$BACKUP_DIR/odoo_db_${DATE}.dump"

if [ $? -eq 0 ]; then
    log "✅ Base de datos respaldada: odoo_db_${DATE}.dump"
else
    error "❌ Falló el backup de la base de datos"
    exit 1
fi

# 2. Backup de addons
log "📚 Backup de addons..."
tar -czf "$BACKUP_DIR/odoo_addons_${DATE}.tar.gz" -C ./v19/addons . 2>/dev/null && log "✅ Addons respaldados" || warn "⚠️ No hay addons"

# 3. Backup de filestore
log "📎 Backup de documentos adjuntos..."
tar -czf "$BACKUP_DIR/odoo_filestore_${DATE}.tar.gz" -C ./v19/data . 2>/dev/null && log "✅ Filestore respaldado" || warn "⚠️ No hay filestore"

# 4. Backup de configuración
log "⚙️ Backup de configuración..."
cp ./v19/config/odoo.conf "$BACKUP_DIR/odoo_config_${DATE}.conf" 2>/dev/null && log "✅ Configuración respaldada" || warn "⚠️ No hay configuración"

# 5. Limpiar backups antiguos
log "🧹 Eliminando backups con más de $RETENTION_DAYS días..."
find $BACKUP_DIR -type f -mtime +$RETENTION_DAYS -delete

log "✅ BACKUP COMPLETADO - $BACKUP_DIR"
ls -lh $BACKUP_DIR/ | grep $DATE