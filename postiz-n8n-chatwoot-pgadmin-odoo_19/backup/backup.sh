#!/bin/bash
set -e

# Configuración
BACKUP_DIR="/backup/daily"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DB_HOST="db"
DB_USER="odoo"
DB_NAME="dbodoo19"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para loguear
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Crear directorio de backup
mkdir -p $BACKUP_DIR

log "=========================================="
log "Iniciando Backup - $DATE"
log "=========================================="

# 1. Backup de PostgreSQL (Odoo database)
log "📦 Backup de base de datos Odoo..."
PGPASSWORD=$(cat /run/secrets/postgres_password) pg_dump -h $DB_HOST -U $DB_USER -F c -b -v "$DB_NAME" > "$BACKUP_DIR/odoo_db_${DATE}.dump"

if [ $? -eq 0 ]; then
    log "✅ Base de datos respaldada: odoo_db_${DATE}.dump ($(du -h "$BACKUP_DIR/odoo_db_${DATE}.dump" | cut -f1))"
else
    error "❌ Falló el backup de la base de datos"
    exit 1
fi

# 2. Backup de n8n (si existe)
if [ -d "/n8n_data" ] && [ "$(ls -A /n8n_data)" ]; then
    log "🔄 Backup de datos de n8n..."
    tar -czf "$BACKUP_DIR/n8n_data_${DATE}.tar.gz" -C /n8n_data . 2>/dev/null
    if [ $? -eq 0 ]; then
        log "✅ n8n respaldado: n8n_data_${DATE}.tar.gz ($(du -h "$BACKUP_DIR/n8n_data_${DATE}.tar.gz" | cut -f1))"
    else
        warn "⚠️  Advertencia en backup de n8n"
    fi
else
    warn "⚠️  No se encontraron datos de n8n para respaldar"
fi

# 3. Backup de configuración de Odoo
log "⚙️  Backup de configuración de Odoo..."
if [ -f "/etc/odoo/odoo.conf" ]; then
    cp /etc/odoo/odoo.conf "$BACKUP_DIR/odoo_config_${DATE}.conf"
    log "✅ Configuración respaldada"
else
    warn "⚠️  No se encontró odoo.conf"
fi

# 4. Backup de addons personalizados
log "📚 Backup de addons de Odoo..."
if [ -d "/opt/odoo/custom-addons" ] && [ "$(ls -A /opt/odoo/custom-addons)" ]; then
    tar -czf "$BACKUP_DIR/odoo_addons_${DATE}.tar.gz" -C /opt/odoo custom-addons 2>/dev/null
    if [ $? -eq 0 ]; then
        log "✅ Addons respaldados: odoo_addons_${DATE}.tar.gz ($(du -h "$BACKUP_DIR/odoo_addons_${DATE}.tar.gz" | cut -f1))"
    else
        warn "⚠️  Advertencia en backup de addons"
    fi
else
    warn "⚠️  No se encontraron addons personalizados"
fi

# 5. Backup de filestore (documentos adjuntos)
log "📎 Backup de documentos adjuntos..."
if [ -d "/var/lib/odoo/.local/share/Odoo" ] && [ "$(ls -A /var/lib/odoo/.local/share/Odoo 2>/dev/null)" ]; then
    tar -czf "$BACKUP_DIR/odoo_filestore_${DATE}.tar.gz" -C /var/lib/odoo/.local/share/Odoo . 2>/dev/null
    if [ $? -eq 0 ]; then
        log "✅ Filestore respaldado: odoo_filestore_${DATE}.tar.gz ($(du -h "$BACKUP_DIR/odoo_filestore_${DATE}.tar.gz" | cut -f1))"
    else
        warn "⚠️  Advertencia en backup de filestore"
    fi
else
    warn "⚠️  No se encontró filestore"
fi

# 6. Backup de Chatwoot (si existe)
if [ -d "/chatwoot_storage" ] && [ "$(ls -A /chatwoot_storage)" ]; then
    log "💬 Backup de datos de Chatwoot..."
    tar -czf "$BACKUP_DIR/chatwoot_data_${DATE}.tar.gz" -C /chatwoot_storage . 2>/dev/null
    if [ $? -eq 0 ]; then
        log "✅ Chatwoot respaldado: chatwoot_data_${DATE}.tar.gz"
    else
        warn "⚠️  Advertencia en backup de Chatwoot"
    fi
fi

# 7. Crear archivo de metadatos
log "📝 Creando metadatos del backup..."
cat > "$BACKUP_DIR/backup_metadata_${DATE}.txt" << EOF
Fecha: $DATE
Servidor: $(hostname)
Base de datos: $DB_NAME
Retención: $RETENTION_DAYS días
Tamaño DB: $(du -h "$BACKUP_DIR/odoo_db_${DATE}.dump" | cut -f1)
EOF

# 8. Limpiar backups antiguos
log "🧹 Limpiando backups con más de $RETENTION_DAYS días..."
DELETED=$(find $BACKUP_DIR -type f -name "*.dump" -o -name "*.tar.gz" -o -name "*.conf" -o -name "*.txt" -mtime +$RETENTION_DAYS | wc -l)
find $BACKUP_DIR -type f -mtime +$RETENTION_DAYS -delete
log "✅ Eliminados $DELETED archivos antiguos"

# 9. Resumen final
log "=========================================="
log "✅ BACKUP COMPLETADO EXITOSAMENTE"
log "=========================================="
log "📁 Directorio: $BACKUP_DIR"
log "📊 Archivos generados:"
ls -lh $BACKUP_DIR/ | grep $DATE | awk '{print "   - " $9 " (" $5 ")"}'
log "💾 Espacio total usado: $(du -sh $BACKUP_DIR | cut -f1)"
log "=========================================="