#!/bin/bash
set -e

# Configuración - Leer desde odoo.conf
ODOO_CONF="./v19/config/odoo.conf"

# Leer variables del archivo de configuración
if [ -f "$ODOO_CONF" ]; then
    DB_NAME=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_PASSWORD=$(grep -E '^db_password\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DATA_DIR=$(grep -E '^data_dir\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    ADDONS_PATH=$(grep -E '^addons_path\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

# Valores por defecto
DB_NAME=${DB_NAME:-dbodoo19}
DB_USER=${DB_USER:-odoo}
DB_CONTAINER="odoo-db19-n8n"

# Directorio de backup (ahora en backup/out)
BACKUP_BASE_DIR="./backup/out"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$BACKUP_BASE_DIR/backup_$DATE"
RETENTION_DAYS=7

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Crear directorio de backup
mkdir -p $BACKUP_DIR

log "=========================================="
log "Iniciando Backup - $DATE"
log "=========================================="
log "📂 Backup destino: $BACKUP_DIR"
log "🗄️ Base de datos: $DB_NAME"
log "📁 Data dir: $DATA_DIR"

# 1. Backup de base de datos
log "📦 Backup de base de datos Odoo..."
docker exec $DB_CONTAINER pg_dump -U $DB_USER -d $DB_NAME -F c > "$BACKUP_DIR/odoo_db_${DATE}.dump"

if [ $? -eq 0 ]; then
    SIZE=$(du -sh "$BACKUP_DIR/odoo_db_${DATE}.dump" | cut -f1)
    log "✅ Base de datos respaldada: odoo_db_${DATE}.dump ($SIZE)"
else
    error "❌ Falló el backup de la base de datos"
    exit 1
fi

# 2. Backup de addons (ahora desde ./v19/data/addons)
log "📚 Backup de addons completos..."
if [ -d "./v19/data/addons" ] && [ "$(ls -A ./v19/data/addons 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_addons_${DATE}.tar.gz" -C ./v19/data/addons . 2>/dev/null
    SIZE=$(du -sh "$BACKUP_DIR/odoo_addons_${DATE}.tar.gz" | cut -f1)
    log "✅ Addons respaldados: odoo_addons_${DATE}.tar.gz ($SIZE)"
else
    warn "⚠️ No hay addons para respaldar en ./v19/data/addons"
fi

# 3. Backup de filestore (./v19/data/filestore específicamente)
log "📎 Backup de documentos adjuntos (filestore)..."
if [ -d "./v19/data/filestore" ] && [ "$(ls -A ./v19/data/filestore 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_filestore_${DATE}.tar.gz" -C ./v19/data/filestore . 2>/dev/null
    SIZE=$(du -sh "$BACKUP_DIR/odoo_filestore_${DATE}.tar.gz" | cut -f1)
    log "✅ Filestore respaldado: odoo_filestore_${DATE}.tar.gz ($SIZE)"
else
    warn "⚠️ No hay filestore para respaldar en ./v19/data/filestore"
fi

# 4. Backup de configuración
log "⚙️ Backup de configuración..."
if [ -f "./v19/config/odoo.conf" ]; then
    cp ./v19/config/odoo.conf "$BACKUP_DIR/odoo_config_${DATE}.conf"
    log "✅ Configuración respaldada: odoo_config_${DATE}.conf"
else
    warn "⚠️ No se encontró archivo de configuración"
fi

# 5. Backup de addons OCA y EXTRA (desde la nueva ruta)
log "📚 Backup de addons OCA específicos..."
if [ -d "./v19/data/addons/oca" ] && [ "$(ls -A ./v19/data/addons/oca 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_oca_addons_${DATE}.tar.gz" -C ./v19/data/addons/oca . 2>/dev/null
    log "✅ Addons OCA respaldados"
fi

if [ -d "./v19/data/addons/extra" ] && [ "$(ls -A ./v19/data/addons/extra 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_extra_addons_${DATE}.tar.gz" -C ./v19/data/addons/extra . 2>/dev/null
    log "✅ Addons EXTRA respaldados"
fi

# 6. Backup completo de ./v19/data (opcional, para tener todo junto)
log "📦 Backup completo del directorio data (addons + filestore)..."
if [ -d "./v19/data" ] && [ "$(ls -A ./v19/data 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_data_complete_${DATE}.tar.gz" -C ./v19/data . 2>/dev/null
    SIZE=$(du -sh "$BACKUP_DIR/odoo_data_complete_${DATE}.tar.gz" | cut -f1)
    log "✅ Data completo respaldado: odoo_data_complete_${DATE}.tar.gz ($SIZE)"
fi

# 7. Limpiar backups antiguos
log "🧹 Eliminando backups con más de $RETENTION_DAYS días..."
find $BACKUP_BASE_DIR -type d -name "backup_*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true

# 8. Resumen final
log "=========================================="
log "✅ BACKUP COMPLETADO"
log "=========================================="
log "📁 Ubicación: $BACKUP_DIR"
log "📦 Archivos generados:"
ls -lh $BACKUP_DIR/ | tail -n +2 | awk '{print "   - " $9 " (" $5 ")"}'
log "=========================================="