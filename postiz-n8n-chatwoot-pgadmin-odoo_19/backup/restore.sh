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

# Mostrar uso
usage() {
    echo "Uso: $0 [opciones]"
    echo "Opciones:"
    echo "  -l, --list        Listar backups disponibles"
    echo "  -f, --file FILE   Restaurar desde archivo específico"
    echo "  -h, --help        Mostrar ayuda"
    exit 0
}

# Listar backups
list_backups() {
    echo "=========================================="
    echo "📚 Backups disponibles:"
    echo "=========================================="
    ls -lh $BACKUP_DIR/odoo_db_*.dump 2>/dev/null || echo "No hay backups"
}

# Restaurar
restore() {
    local dump_file=$1
    
    if [ ! -f "$dump_file" ]; then
        error "Archivo no encontrado: $dump_file"
        exit 1
    fi
    
    info "Restaurando desde: $(basename $dump_file)"
    
    # Detener Odoo web
    info "Deteniendo Odoo web..."
    docker compose -f docker-compose.odoo.yml stop web
    
    # Restaurar base de datos
    info "Restaurando base de datos..."
    docker exec -i $DB_CONTAINER dropdb -U odoo --if-exists $DB_NAME
    docker exec -i $DB_CONTAINER createdb -U odoo $DB_NAME
    docker exec -i $DB_CONTAINER pg_restore -U odoo -d $DB_NAME -c --no-owner < "$dump_file"
    
    if [ $? -eq 0 ]; then
        log "✅ Base de datos restaurada"
    else
        error "❌ Falló la restauración"
        exit 1
    fi
    
    # Iniciar Odoo
    info "Iniciando Odoo web..."
    docker compose -f docker-compose.odoo.yml start web
    
    log "✅ RESTAURACIÓN COMPLETADA"
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
        # Restaurar el backup más reciente
        LATEST=$(ls -t $BACKUP_DIR/odoo_db_*.dump 2>/dev/null | head -1)
        if [ -z "$LATEST" ]; then
            error "No hay backups disponibles"
            exit 1
        fi
        restore "$LATEST"
        ;;
esac