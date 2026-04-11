#!/bin/bash
set -e

# Configuración
BACKUP_DIR="/home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out/backup_2026-04-10_16-27-26"
DB_CONTAINER="odoo-db19-n8n"
ODOO_CONF="./v19/config/odoo.conf"

# Extraer variables del archivo de configuración de forma dinámica
if [ -f "$ODOO_CONF" ]; then
    DB_NAME=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_PASSWORD=$(grep -E '^db_password\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

# Valores por defecto en caso de no encontrarlos o no existir el conf
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

install_oca_modules() {
    info "Instalando módulos OCA encontrados en ./v19/addons/oca..."
    
    # Lista de módulos OCA a instalar
    OCA_MODULES=$(ls -d ./v19/addons/oca/*/ 2>/dev/null | xargs -n 1 basename | tr '\n' ',')
    
    if [ -z "$OCA_MODULES" ]; then
        warn "No se encontraron módulos OCA en ./v19/addons/oca/"
        return
    fi
    
    info "Módulos OCA encontrados: $OCA_MODULES"
    
    # Agregar la ruta OCA al addons_path en el contenedor
    docker exec odoo-19-web bash -c "
        if ! grep -q '/opt/odoo/custom-addons/oca' /etc/odoo/odoo.conf; then
            sed -i 's|addons_path = .*|&,/opt/odoo/custom-addons/oca|' /etc/odoo/odoo.conf
            echo '✅ Ruta OCA agregada a addons_path'
        fi
    "
    
    # Instalar módulos OCA
    for module in $(ls -d ./v19/addons/oca/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo: $module"
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
    
    for module in $(ls -d ./v19/addons/extra/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo: $module"
        docker exec odoo-19-web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    
    log "✅ Módulos EXTRA instalados"
}

fix_whatsapp_module() {
    info "Arreglando módulo website_whatsapp..."
    
    # Crear el campo manualmente si el módulo no funciona
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d $DB_NAME << EOF
    ALTER TABLE website ADD COLUMN IF NOT EXISTS whatsapp_text varchar DEFAULT '';
    INSERT INTO ir_model_fields (model, name, field_description, ttype, store, selectable)
    SELECT 'website', 'whatsapp_text', 'WhatsApp Text', 'char', True, True
    WHERE NOT EXISTS (SELECT 1 FROM ir_model_fields WHERE model='website' AND name='whatsapp_text');
    DELETE FROM ir_ui_view WHERE arch_db::text LIKE '%whatsapp%';
EOF
    
    log "✅ Campo whatsapp_text creado/verificado"
}

restore() {
    local dump_file=$1
    local INSTALL_MODULES=${2:-false}
    local ORIGINAL_DB_NAME=""
    
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
    info "Base de datos destino: $DB_NAME"
    
    # 1. Detener Odoo web
    info "Deteniendo Odoo web..."
    docker compose -f docker-compose.odoo.yml stop web
    
    # 2. Restaurar addons (código personalizado)
    if [ -f "$ADDONS_FILE" ]; then
        info "Restaurando addons personalizados..."
        
        # Eliminar addons existentes
        sudo rm -rf ./v19/addons
        
        mkdir -p ./v19/addons
        
        # Extraer sin preservar permisos para evitar errores
        tar --no-same-owner --no-same-permissions -xzf "$ADDONS_FILE" -C ./v19/addons/
        
        # Cambiar permisos al usuario 1001
        sudo chown -R 1001:odoogroup ./v19/addons/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/addons/
        sudo chmod -R 755 ./v19/addons/
        
        log "✅ Addons restaurados"
    else
        warn "No se encontró backup de addons"
    fi
    
    # 2b. También restaurar addons OCA y EXTRA si existen como directorios separados
    if [ -d "./v19/addons/extra" ]; then
        sudo chown -R 1001:odoogroup ./v19/addons/extra 2>/dev/null || true
        log "✅ Addons EXTRA preservados"
    fi
    
    if [ -d "./v19/addons/oca" ]; then
        sudo chown -R 1001:odoogroup ./v19/addons/oca 2>/dev/null || true
        log "✅ Addons OCA preservados"
    fi
    
    # 3. Restaurar filestore y renombrar al nombre de la BD actual
    if [ -f "$FILESTORE_FILE" ]; then
        info "Restaurando filestore (documentos adjuntos)..."
        
        # Crear directorio temporal para extraer
        local TEMP_FILESTORE_DIR="/tmp/filestore_restore_$$"
        mkdir -p "$TEMP_FILESTORE_DIR"
        
        # Extraer el filestore backup sin preservar permisos
        tar --no-same-owner --no-same-permissions -xzf "$FILESTORE_FILE" -C "$TEMP_FILESTORE_DIR"
        
        # Buscar el directorio del filestore original
        local FILESTORE_BASE=$(find "$TEMP_FILESTORE_DIR" -type d -name "filestore" | head -1)
        
        if [ -n "$FILESTORE_BASE" ]; then
            # Obtener el nombre original de la BD del backup
            ORIGINAL_DB_NAME=$(find "$FILESTORE_BASE" -maxdepth 1 -type d ! -path "$FILESTORE_BASE" | head -1 | xargs basename 2>/dev/null)
            
            if [ -n "$ORIGINAL_DB_NAME" ]; then
                info "Filestore original detectado: $ORIGINAL_DB_NAME"
                info "Renombrando a: $DB_NAME"
                
                # Eliminar filestore existente
                sudo rm -rf ./v19/data/filestore/$DB_NAME
                
                # Crear estructura de directorios
                mkdir -p ./v19/data/filestore
                
                # Mover y renombrar el filestore
                sudo mv "$FILESTORE_BASE/$ORIGINAL_DB_NAME" "./v19/data/filestore/$DB_NAME"
                
                # Cambiar permisos al usuario 1001
                sudo chown -R 1001:odoogroup ./v19/data/filestore/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/data/filestore/
                sudo chmod -R 755 ./v19/data/filestore/
                
                log "✅ Filestore restaurado y renombrado a: $DB_NAME"
            else
                error "No se pudo determinar el nombre original del filestore"
                sudo rm -rf ./v19/data/filestore/$DB_NAME
                mkdir -p "./v19/data/filestore/$DB_NAME"
                sudo cp -r "$FILESTORE_BASE"/* "./v19/data/filestore/$DB_NAME/"
                sudo chown -R 1001:odoogroup ./v19/data/filestore/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/data/filestore/
                warn "Filestore copiado con estructura alternativa"
            fi
        else
            warn "Carpeta padre 'filestore' no explícita, buscando heurísticamente..."
            local ANY_FILESTORE=$(find "$TEMP_FILESTORE_DIR" -type d -name "db*" -o -type d -name "*odoo*" | head -1)
            if [ -n "$ANY_FILESTORE" ]; then
                ORIGINAL_DB_NAME=$(basename "$ANY_FILESTORE")
                
                sudo rm -rf ./v19/data/filestore/$DB_NAME
                mkdir -p "./v19/data/filestore"
                sudo mv "$ANY_FILESTORE" "./v19/data/filestore/$DB_NAME"
                sudo chown -R 1001:odoogroup ./v19/data/filestore/ 2>/dev/null || sudo chown -R 1001:1001 ./v19/data/filestore/
                log "✅ Filestore recuperado y renombrado a: $DB_NAME"
            else
                warn "No se pudo recuperar el filestore - Los documentos adjuntos se perderán"
            fi
        fi
        
        sudo rm -rf "$TEMP_FILESTORE_DIR"
        
    else
        warn "No se encontró backup de filestore - Los documentos adjuntos se perderán"
    fi
    
    # 4. Restaurar configuración
    if [ -f "$CONFIG_FILE" ]; then
        info "Backup contiene configuración, pero se mantendrá odoo.conf original."
    fi
    
    # 5. Restaurar base de datos
    info "Restaurando base de datos..."
    
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(docker exec $DB_CONTAINER cat /run/secrets/postgres_password 2>/dev/null || echo "")
    fi
    
    info "Eliminando base de datos existente..."
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME';" 2>/dev/null || true
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER dropdb -U $DB_USER --if-exists $DB_NAME
    
    docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER createdb -U $DB_USER $DB_NAME
    
    info "Restaurando dump de base de datos (esto puede tomar varios minutos)..."
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
            info "Actualizando referencias al filestore en la base de datos..."
            docker exec -e PGPASSWORD=$DB_PASSWORD $DB_CONTAINER psql -U $DB_USER -d $DB_NAME -c \
                "UPDATE ir_attachment SET store_fname = REPLACE(store_fname, '$ORIGINAL_DB_NAME', '$DB_NAME') WHERE store_fname LIKE '%$ORIGINAL_DB_NAME%';" \
                2>/dev/null || warn "No se pudieron actualizar algunas referencias"
            
            log "✅ Referencias actualizadas en la base de datos"
        fi
    else
        error "❌ Falló la restauración de la base de datos (código: $PG_EXIT)"
        exit 1
    fi
    
    # 6. Iniciar Odoo web
    info "Iniciando Odoo web..."
    docker compose -f docker-compose.odoo.yml start web
    
    # Esperar a que Odoo esté listo
    info "Esperando a que Odoo esté listo..."
    sleep 15
    
    # 7. Instalar módulos OCA si se solicitó
    if [ "$INSTALL_MODULES" = true ]; then
        info "Instalando módulos adicionales..."
        fix_whatsapp_module
        install_oca_modules
        install_extra_modules
        
        # Reiniciar Odoo después de instalar módulos
        info "Reiniciando Odoo para aplicar cambios..."
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
        restore "$BACKUP_DIR/$2" "$INSTALL_MODULES"
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
            error "No hay backups disponibles"
            exit 1
        fi
        restore "$LATEST" false
        ;;
esac