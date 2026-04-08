#!/bin/bash
set -e

# Configuración
BACKUP_DIR="./v19/backups"
DB_CONTAINER="odoo-db19-n8n"
DB_NAME="dbodoo19"

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

usage() {
    echo "Uso: $0 [opciones]"
    echo "Opciones:"
    echo "  -l, --list        Listar backups disponibles"
    echo "  -f, --file FILE   Restaurar desde archivo específico"
    echo "  -h, --help        Mostrar ayuda"
    exit 0
}

list_backups() {
    echo "=========================================="
    echo "📚 Backups disponibles:"
    echo "=========================================="
    echo "🗄️ Bases de datos:"
    ls -lh $BACKUP_DIR/odoo_db_*.dump 2>/dev/null || echo "   No hay backups"
    echo ""
    echo "📎 Filestore:"
    ls -lh $BACKUP_DIR/odoo_filestore_*.tar.gz 2>/dev/null || echo "   No hay backups"
    echo ""
    echo "📚 Addons:"
    ls -lh $BACKUP_DIR/odoo_addons_*.tar.gz 2>/dev/null || echo "   No hay backups"
}

restore() {
    local dump_file=$1
    
    if [ ! -f "$dump_file" ]; then
        error "Archivo no encontrado: $dump_file"
        exit 1
    fi
    
    # Obtener la fecha del backup para buscar archivos relacionados
    local BASE_NAME=$(basename "$dump_file" | sed 's/odoo_db_//' | sed 's/\.dump//')
    local ADDONS_FILE="$BACKUP_DIR/odoo_addons_${BASE_NAME}.tar.gz"
    local FILESTORE_FILE="$BACKUP_DIR/odoo_filestore_${BASE_NAME}.tar.gz"
    local CONFIG_FILE="$BACKUP_DIR/odoo_config_${BASE_NAME}.conf"
    
    info "Restaurando desde backup: $BASE_NAME"
    
    # 1. Detener Odoo web
    info "Deteniendo Odoo web..."
    docker compose -f docker-compose.odoo.yml stop web
    
    # 2. Restaurar addons (código personalizado)
    if [ -f "$ADDONS_FILE" ]; then
        info "Restaurando addons personalizados..."
        # Backup de addons existentes
        if [ -d "./v19/addons" ] && [ "$(ls -A ./v19/addons 2>/dev/null)" ]; then
            mv ./v19/addons "./v19/addons.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        mkdir -p ./v19/addons
        tar -xzf "$ADDONS_FILE" -C ./v19/addons/
        log "✅ Addons restaurados"
    else
        warn "No se encontró backup de addons"
    fi
    
    # 3. Restaurar filestore (documentos adjuntos)
    if [ -f "$FILESTORE_FILE" ]; then
        info "Restaurando filestore (documentos adjuntos)..."
        # Backup del filestore existente
        if [ -d "./v19/data" ] && [ "$(ls -A ./v19/data 2>/dev/null)" ]; then
            mv ./v19/data "./v19/data.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        mkdir -p ./v19/data
        tar -xzf "$FILESTORE_FILE" -C ./v19/data/
        # Corregir permisos (el usuario de Odoo es 1001)
        sudo chown -R 1001:1001 ./v19/data/ 2>/dev/null || true
        log "✅ Filestore restaurado"
    else
        warn "No se encontró backup de filestore - Los documentos adjuntos se perderán"
    fi
    
    # 4. Restaurar configuración
    if [ -f "$CONFIG_FILE" ]; then
        info "Restaurando configuración..."
        cp "$CONFIG_FILE" ./v19/config/odoo.conf
        log "✅ Configuración restaurada"
    fi
    
    # 5. Restaurar base de datos
    info "Restaurando base de datos..."
    
    # Obtener contraseña
    PGPASS=$(docker exec $DB_CONTAINER cat /run/secrets/postgres_password 2>/dev/null)
    
    docker exec -e PGPASSWORD=$PGPASS $DB_CONTAINER dropdb -U odoo --if-exists $DB_NAME
    docker exec -e PGPASSWORD=$PGPASS $DB_CONTAINER createdb -U odoo $DB_NAME
    docker exec -i -e PGPASSWORD=$PGPASS $DB_CONTAINER pg_restore -U odoo -d $DB_NAME -c --no-owner < "$dump_file"
    
    if [ $? -eq 0 ]; then
        log "✅ Base de datos restaurada"
    else
        error "❌ Falló la restauración de la base de datos"
        exit 1
    fi
    
    # 6. Iniciar Odoo web
    info "Iniciando Odoo web..."
    docker compose -f docker-compose.odoo.yml start web
    
    echo ""
    log "✅ RESTAURACIÓN COMPLETADA"
    info "Accede a Odoo en: http://localhost:18069"
}

# Procesar argumentos
case $1 in
    -l|--list)
        list_backups
        ;;
    -f|--file)
        restore "$BACKUP_DIR/$2"
        ;;
    -h|--help)
        usage
        ;;
    *)
        LATEST=$(ls -t $BACKUP_DIR/odoo_db_*.dump 2>/dev/null | head -1)
        if [ -z "$LATEST" ]; then
            error "No hay backups disponibles"
            exit 1
        fi
        restore "$LATEST"
        ;;
esac