#!/bin/bash
set -e

# Configuración - DINÁMICA
BACKUP_BASE_DIR="./backup/out"
DB_CONTAINER="odoo-db19-n8n"
ODOO_CONF="./v19/config/odoo.conf"

# Buscar el backup más reciente automáticamente
if [ -d "$BACKUP_BASE_DIR" ]; then
    LATEST_BACKUP=$(ls -td "$BACKUP_BASE_DIR"/backup_* 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        BACKUP_DIR="$LATEST_BACKUP"
    else
        BACKUP_DIR="$BACKUP_BASE_DIR"
    fi
else
    BACKUP_DIR="$BACKUP_BASE_DIR"
fi

# Configuración
#BACKUP_DIR="/home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out/backup_2026-04-11_09-33-00"

# Extraer variables del archivo de configuración
if [ -f "$ODOO_CONF" ]; then
    DB_NAME=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_PASSWORD=$(grep -E '^db_password\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

DB_NAME=${DB_NAME:-dbodoo19}
DB_USER=${DB_USER:-odoo}

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

usage() {
    echo "Uso: $0 [opciones]"
    echo "Opciones:"
    echo "  -l, --list        Listar backups disponibles"
    echo "  -f, --file FILE   Restaurar desde archivo específico"
    echo "  --install-modules Instalar módulos OCA después de restaurar"
    echo "  -h, --help        Mostrar ayuda"
    exit 0
}

list_backups() {
    echo "=========================================="
    echo "📚 Backups disponibles en: $BACKUP_BASE_DIR"
    echo "=========================================="
    
    for backup in $(ls -td $BACKUP_BASE_DIR/backup_* 2>/dev/null); do
        echo ""
        echo "📁 $(basename $backup)"
        echo "   🗄️ Bases de datos:"
        ls -lh $backup/odoo_db_*.dump 2>/dev/null | awk '{print "      - " $9 " (" $5 ")"}' || echo "      No hay backups"
        echo "   📎 Filestore+Addons:"
        ls -lh $backup/odoo_filestore_*.tar.gz 2>/dev/null | awk '{print "      - " $9 " (" $5 ")"}' || echo "      No hay backups"
    done
}

install_oca_modules() {
    info "Instalando módulos OCA encontrados en ./v19/addons/oca..."
    
    # Verificar si hay módulos OCA
    if [ ! -d "./v19/addons/oca" ]; then
        warn "No existe el directorio ./v19/addons/oca"
        return
    fi
    
    # Agregar la ruta OCA al addons_path en el contenedor
    docker exec odoo-19-web bash -c "
        if ! grep -q '/opt/odoo/custom-addons/oca' /etc/odoo/odoo.conf; then
            sed -i 's|addons_path = .*|&,/opt/odoo/custom-addons/oca|' /etc/odoo/odoo.conf
            echo '✅ Ruta OCA agregada a addons_path'
        fi
    "
    
    # Instalar cada módulo OCA encontrado
    for module in $(ls -d ./v19/addons/oca/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo OCA: $module"
        docker exec odoo-19-web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    
    log "✅ Módulos OCA instalados"
}

install_extra_modules() {
    info "Instalando módulos EXTRA encontrados en ./v19/addons/extra..."
    
    if [ ! -d "./v19/addons/extra" ]; then
        warn "No existe el directorio ./v19/addons/extra"
        return
    fi
    
    for module in $(ls -d ./v19/addons/extra/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo EXTRA: $module"
        docker exec odoo-19-web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    
    log "✅ Módulos EXTRA instalados"
}

fix_whatsapp_module() {
    info "Verificando/Arreglando módulo website_whatsapp..."
    
    # Verificar si el módulo existe en el sistema de archivos
    if [ -d "./v19/addons/oca/website_whatsapp" ]; then
        info "Módulo website_whatsapp encontrado en ./v19/addons/oca/"
        
        # Instalar el módulo específicamente
        docker exec odoo-19-web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=website_whatsapp \
            --stop-after-init \
            --log-level=info 2>&1 | head -20
    fi
    
    # Crear el campo manualmente como respaldo
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d $DB_NAME << EOF
    ALTER TABLE website ADD COLUMN IF NOT EXISTS whatsapp_text varchar DEFAULT '';
    INSERT INTO ir_model_fields (model, name, field_description, ttype, store, selectable)
    SELECT 'website', 'whatsapp_text', 'WhatsApp Text', 'char', True, True
    WHERE NOT EXISTS (SELECT 1 FROM ir_model_fields WHERE model='website' AND name='whatsapp_text');
    DELETE FROM ir_ui_view WHERE arch_db::text LIKE '%whatsapp%';
EOF
    
    log "✅ Campo whatsapp_text verificado/creado"
}

restore() {
    local dump_file=$1
    local INSTALL_MODULES=${2:-false}
    local ORIGINAL_DB_NAME=""
    
    if [ ! -f "$dump_file" ]; then
        error "Archivo no encontrado: $dump_file"
        exit 1
    fi
    
    local BASE_NAME=$(basename "$dump_file" | sed 's/odoo_db_//' | sed 's/\.dump//')
    local FILESTORE_FILE="$(dirname "$dump_file")/odoo_filestore_${BASE_NAME}.tar.gz"
    local CONFIG_FILE="$(dirname "$dump_file")/odoo_config_${BASE_NAME}.conf"
    
    info "Restaurando desde backup: $BASE_NAME"
    info "Base de datos destino: $DB_NAME"
    info "Directorio de backup: $(dirname "$dump_file")"
    
    # 1. Detener Odoo web
    info "Deteniendo Odoo web..."
    docker compose -f docker-compose.odoo.yml stop web
    
    # 2. Restaurar filestore y addons (vienen juntos en el backup)
    if [ -f "$FILESTORE_FILE" ]; then
        info "Restaurando filestore y addons..."
        
        local TEMP_RESTORE_DIR="/tmp/restore_$$"
        mkdir -p "$TEMP_RESTORE_DIR"
        
        # Extraer todo el contenido
        tar --no-same-owner --no-same-permissions -xzf "$FILESTORE_FILE" -C "$TEMP_RESTORE_DIR"
        
        # Buscar y restaurar filestore
        local FILESTORE_BASE=$(find "$TEMP_RESTORE_DIR" -type d -name "filestore" | head -1)
        
        if [ -n "$FILESTORE_BASE" ]; then
            # Obtener el nombre original de la BD
            ORIGINAL_DB_NAME=$(find "$FILESTORE_BASE" -maxdepth 1 -type d ! -path "$FILESTORE_BASE" | head -1 | xargs basename 2>/dev/null)
            
            if [ -n "$ORIGINAL_DB_NAME" ]; then
                info "Filestore original detectado: $ORIGINAL_DB_NAME"
                info "Renombrando a: $DB_NAME"
                
                sudo rm -rf ./v19/data/filestore/$DB_NAME
                mkdir -p ./v19/data/filestore
                sudo mv "$FILESTORE_BASE/$ORIGINAL_DB_NAME" "./v19/data/filestore/$DB_NAME"
                
                log "✅ Filestore restaurado"
            fi
        fi
        
        # Buscar y restaurar addons (pueden estar en diferentes ubicaciones dentro del tar)
        local ADDONS_DIRS=("addons" "custom-addons" "oca" "extra")
        
        for dir in "${ADDONS_DIRS[@]}"; do
            local ADDONS_PATH=$(find "$TEMP_RESTORE_DIR" -type d -name "$dir" | head -1)
            if [ -n "$ADDONS_PATH" ] && [ "$(ls -A "$ADDONS_PATH" 2>/dev/null)" ]; then
                info "Restaurando addons desde: $(basename "$ADDONS_PATH")"
                sudo cp -r "$ADDONS_PATH"/* ./v19/addons/ 2>/dev/null || true
            fi
        done
        
        # También buscar directamente la estructura oca/website_whatsapp
        local OCA_MODULE=$(find "$TEMP_RESTORE_DIR" -type d -path "*/oca/website_whatsapp" | head -1)
        if [ -n "$OCA_MODULE" ]; then
            info "Encontrado módulo OCA: website_whatsapp"
            mkdir -p ./v19/addons/oca
            sudo cp -r "$OCA_MODULE" ./v19/addons/oca/
        fi
        
        # Limpiar permisos
        sudo chown -R 1001:odoogroup ./v19/addons/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/addons/
        sudo chown -R 1001:odoogroup ./v19/data/filestore/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/data/filestore/
        sudo chmod -R 755 ./v19/addons/ ./v19/data/filestore/
        
        sudo rm -rf "$TEMP_RESTORE_DIR"
        log "✅ Filestore y addons restaurados"
    else
        warn "No se encontró backup de filestore"
    fi
    
    # 3. Restaurar base de datos
    info "Restaurando base de datos..."
    
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(docker exec $DB_CONTAINER cat /run/secrets/postgres_password 2>/dev/null || echo "")
    fi
    
    info "Eliminando base de datos existente..."
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';" 2>/dev/null || true
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER dropdb -U $DB_USER --if-exists $DB_NAME
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER createdb -U $DB_USER $DB_NAME
    
    info "Restaurando dump de base de datos..."
    set +e
    docker exec -i -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER pg_restore \
        -U $DB_USER \
        -d $DB_NAME \
        --no-owner \
        --no-privileges \
        < "$dump_file" 2>&1
    PG_EXIT=$?
    set -e
    
    if [ $PG_EXIT -eq 0 ]; then
        log "✅ Base de datos restaurada"
        
        if [ -n "$ORIGINAL_DB_NAME" ] && [ "$ORIGINAL_DB_NAME" != "$DB_NAME" ]; then
            info "Actualizando referencias al filestore..."
            docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c \
                "UPDATE ir_attachment SET store_fname = REPLACE(store_fname, '$ORIGINAL_DB_NAME', '$DB_NAME') WHERE store_fname LIKE '%$ORIGINAL_DB_NAME%';" \
                2>/dev/null || true
        fi
    else
        error "❌ Falló la restauración de la base de datos (código: $PG_EXIT)"
        exit 1
    fi
    
    # 4. Iniciar Odoo
    info "Iniciando Odoo web..."
    docker compose -f docker-compose.odoo.yml start web
    sleep 15
    
    # 5. Instalar módulos si se solicitó
    if [ "$INSTALL_MODULES" = true ]; then
        info "Instalando módulos adicionales..."
        fix_whatsapp_module
        install_oca_modules
        install_extra_modules
        
        info "Reiniciando Odoo..."
        docker restart odoo-19-web
        sleep 10
    fi
    
    echo ""
    log "✅ RESTAURACIÓN COMPLETADA"
    info "Base de datos: $DB_NAME"
    info "Filestore: ./v19/data/filestore/$DB_NAME"
    info "Addons: ./v19/addons"
    info "Accede a Odoo en: http://localhost:18069"
}

# Procesar argumentos
INSTALL_MODULES=false

case $1 in
    -l|--list)
        list_backups
        ;;
    -f|--file)
        if [ "$3" = "--install-modules" ]; then
            INSTALL_MODULES=true
        fi
        restore "$2" "$INSTALL_MODULES"
        ;;
    --install-modules)
        INSTALL_MODULES=true
        LATEST=$(ls -t $BACKUP_DIR/odoo_db_*.dump 2>/dev/null | head -1)
        if [ -z "$LATEST" ]; then
            error "No hay backups disponibles"
            exit 1
        fi
        restore "$LATEST" "$INSTALL_MODULES"
        ;;
    -h|--help)
        usage
        ;;
    *)
        LATEST=$(ls -t $BACKUP_DIR/odoo_db_*.dump 2>/dev/null | head -1)
        if [ -z "$LATEST" ]; then
            error "No hay backups disponibles en $BACKUP_DIR"
            exit 1
        fi
        restore "$LATEST" false
        ;;
esac