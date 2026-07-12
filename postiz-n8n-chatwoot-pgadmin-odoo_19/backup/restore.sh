#!/bin/bash
set -e

# ============================================
# CONFIGURACIÓN (modificar por máquina)
# ============================================
BACKUP_BASE_DIR="./backup/out"
DB_CONTAINER="odoo-db19-leads"
WEB_CONTAINER="odoo-19-web-leads"
COMPOSE_FILE="docker-compose.leads.yml"
ODOO_CONF="./v19-leads/config/odoo.conf"
DATA_DIR="./v19-leads/odoo-web-data/.local/share/Odoo"
WEB_DATA_DIR="./v19-leads/odoo-web-data"
FILESTORE_DIR="$DATA_DIR/filestore"
LOGS_DIR="./v19-leads/logs"
DB_USER_DEFAULT="odoo"
NETWORK_NAME="odoo_network_19"
# ============================================

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

exec_in_web() { docker exec $WEB_CONTAINER "$@"; }
exec_in_db() { docker exec $DB_CONTAINER "$@"; }

# ============================================
# FUNCIONES
# ============================================

ensure_web_container() {
    if ! docker ps -a | grep -q "$WEB_CONTAINER"; then
        info "Contenedor $WEB_CONTAINER no existe, creándolo..."
        docker compose -f $COMPOSE_FILE up -d 2>/dev/null || true
        sleep 10
    fi
    if ! docker ps | grep -q "$WEB_CONTAINER"; then
        info "Contenedor $WEB_CONTAINER no está corriendo, iniciándolo..."
        docker start "$WEB_CONTAINER"
        sleep 10
    fi
    if docker ps | grep -q "$WEB_CONTAINER"; then
        log "Contenedor $WEB_CONTAINER está corriendo"
    else
        error "No se pudo iniciar el contenedor $WEB_CONTAINER"
    fi
}

docker_chown() {
    local path=$1
    if [ -d "$path" ]; then
        docker run --rm -v "$(readlink -f "$path"):/target" alpine chown -R 1001:1001 /target 2>/dev/null || true
    fi
}

confirm_target() {
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  DESTINOS DE LA RESTAURACIÓN"
    echo "═══════════════════════════════════════════════"
    echo "  DB Container:     $DB_CONTAINER"
    echo "  Web Container:    $WEB_CONTAINER"
    echo "  DB Name:          $DB_NAME"
    echo "  DB User:          $DB_USER"
    echo "  Compose File:     $COMPOSE_FILE"
    echo "  Data Dir:         $DATA_DIR"
    echo "  Filestore Dir:    $FILESTORE_DIR"
    echo "═══════════════════════════════════════════════"
    echo ""
    if [ "$SKIP_CONFIRM" != true ]; then
        read -p "¿Continuar con la restauración? (s/N): " CONFIRM
        if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
            error "Restauración cancelada por el usuario"
        fi
    fi
}

restore_filestore() {
    local archive=$1
    local tmp="/tmp/fs_restore_$$"
    mkdir -p "$tmp"
    local basename=$(basename "$archive")

    info "Extrayendo filestore desde: $basename"
    docker run --rm -v "$archive:/archive:ro" -v "$tmp:/out" alpine tar -xzf /archive -C /out

    # Find the DB directory inside any filestore/ tree
    local db_dir=""
    local fs_root=""

    # 1. Try root-level ./filestore/<DB_NAME> (archive from DATA_DIR)
    if [ -d "$tmp/filestore/$DB_NAME" ]; then
        db_dir="$DB_NAME"
        fs_root="$tmp/filestore"
    # 2. Try nested .local/share/Odoo/filestore/<DB_NAME> (archive from WEB_DATA_DIR)
    elif [ -d "$tmp/.local/share/Odoo/filestore/$DB_NAME" ]; then
        db_dir="$DB_NAME"
        fs_root="$tmp/.local/share/Odoo/filestore"
    # 3. Search for any filestore directory with a DB subdirectory
    else
        local found=$(find "$tmp" -type d -name filestore 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            fs_root="$found"
            db_dir=$(ls "$found/" 2>/dev/null | grep -v -E '^(addons|filestore|sessions)$' | head -1)
        fi
    fi

    if [ -n "$db_dir" ] && [ -d "$fs_root/$db_dir" ]; then
        info "Filestore original: $db_dir → renombrando a: $DB_NAME"
        local abs_fs=$(readlink -f "$FILESTORE_DIR")
        docker run --rm -v "$abs_fs:/dest" alpine sh -c "rm -rf /dest/$DB_NAME && mkdir -p /dest" 2>/dev/null || true
        docker run --rm \
            -v "$fs_root/$db_dir:/src" \
            -v "$abs_fs:/dest" \
            alpine sh -c "cp -r /src /dest/$DB_NAME && chown -R 1001:1001 /dest/$DB_NAME"
        log "Filestore restaurado"
    else
        warn "No se encontró subdirectorio de BD en el filestore"
    fi
    docker run --rm -v "$tmp:/tmp/cleanup" alpine rm -rf /tmp/cleanup 2>/dev/null || rm -rf "$tmp" 2>/dev/null || true
}

install_oca_modules() {
    info "Instalando módulos OCA encontrados en $ADDONS_DIR/oca..."
    if [ ! -d "$ADDONS_DIR/oca" ]; then
        warn "No existe el directorio $ADDONS_DIR/oca"
        return
    fi
    exec_in_web bash -c "
        if ! grep -q '/opt/odoo/custom-addons/oca' /etc/odoo/odoo.conf; then
            sed -i 's|addons_path = .*|&,/opt/odoo/custom-addons/oca|' /etc/odoo/odoo.conf
            echo 'Ruta OCA agregada a addons_path'
        fi
    "
    for module in $(ls -d $ADDONS_DIR/oca/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo OCA: $module"
        exec_in_web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --http-port=8099 \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    log "Módulos OCA instalados"
}

install_extra_modules() {
    info "Instalando módulos EXTRA encontrados en $ADDONS_DIR/extra..."
    if [ ! -d "$ADDONS_DIR/extra" ]; then
        warn "No existe el directorio $ADDONS_DIR/extra"
        return
    fi
    for module in $(ls -d $ADDONS_DIR/extra/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo EXTRA: $module"
        exec_in_web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --http-port=8099 \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    log "Módulos EXTRA instalados"
}

install_enterprise_modules() {
    info "Instalando módulos ENTERPRISE encontrados en $ADDONS_DIR/enterprise..."
    if [ ! -d "$ADDONS_DIR/enterprise" ]; then
        warn "No existe el directorio $ADDONS_DIR/enterprise"
        return
    fi
    for module in $(ls -d $ADDONS_DIR/enterprise/*/ 2>/dev/null | xargs -n 1 basename); do
        info "Instalando módulo ENTERPRISE: $module"
        exec_in_web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=$module \
            --stop-after-init \
            --http-port=8099 \
            --log-level=error 2>&1 | grep -E "ERROR|$module" || true
    done
    log "Módulos ENTERPRISE instalados"
}

fix_whatsapp_module() {
    info "Verificando/Arreglando módulo website_whatsapp..."
    if [ -d "$ADDONS_DIR/oca/website_whatsapp" ]; then
        exec_in_web python3 /opt/odoo/odoo-core/odoo-bin \
            -c /etc/odoo/odoo.conf \
            --update=website_whatsapp \
            --stop-after-init \
            --http-port=8099 \
            --log-level=info 2>&1 | head -20
    fi
    exec_in_db psql -U $DB_USER -d $DB_NAME << EOF
    ALTER TABLE website ADD COLUMN IF NOT EXISTS whatsapp_text varchar DEFAULT '';
    INSERT INTO ir_model_fields (model, name, field_description, ttype, store, selectable)
    SELECT 'website', 'whatsapp_text', 'WhatsApp Text', 'char', True, True
    WHERE NOT EXISTS (SELECT 1 FROM ir_model_fields WHERE model='website' AND name='whatsapp_text');
    DELETE FROM ir_ui_view WHERE arch_db::text LIKE '%whatsapp%';
EOF
    log "Campo whatsapp_text verificado/creado"
}

determine_addon_type() {
    local addon_path=$1
    local addon_name=$(basename "$addon_path")
    if [ -f "$addon_path/__manifest__.py" ]; then
        if grep -q "OCA" "$addon_path/__manifest__.py" 2>/dev/null || \
           [ -f "$addon_path/README.rst" ] && grep -q "OCA" "$addon_path/README.rst" 2>/dev/null || \
           [ -d "$addon_path/i18n" ] && ls "$addon_path/i18n/"*.po 2>/dev/null | grep -q "es_" || \
           [[ "$addon_name" =~ ^(web_|base_|account_|sale_|purchase_|stock_|hr_|project_|mrp_) ]]; then
            echo "oca"
            return
        fi
        if [[ "$addon_name" =~ (enterprise|_enterprise$) ]] || \
           grep -q "enterprise" "$addon_path/__manifest__.py" 2>/dev/null; then
            echo "enterprise"
            return
        fi
    fi
    echo "extra"
}

# ============================================
# RESTORE PRINCIPAL
# ============================================
restore() {
    local dump_file=$1
    local INSTALL_MODULES=${2:-false}
    local ORIGINAL_DB_NAME=""

    if [ ! -f "$dump_file" ]; then
        error "Archivo no encontrado: $dump_file"
    fi

    local BASE_NAME=$(basename "$dump_file" | sed 's/^odoo_db_//; s/^dbodoo19_//; s/\.dump$//')
    local FILESTORE_FILE="$(dirname "$dump_file")/odoo_filestore_${BASE_NAME}.tar.gz"
    local DATA_FILE="$(dirname "$dump_file")/odoo_data_${BASE_NAME}.tar.gz"
    local ADDONS_FILE="$(dirname "$dump_file")/odoo_addons_${BASE_NAME}.tar.gz"

    info "Restaurando desde backup: $BASE_NAME"
    info "Base de datos destino: $DB_NAME"
    info "Directorio: $(dirname "$dump_file")"

    # 1. Detener Odoo web (usar docker stop directo, no compose)
    info "Deteniendo Odoo web..."
    docker stop "$WEB_CONTAINER" 2>/dev/null || true
    sleep 2

    # 2. Restaurar base de datos
    info "Restaurando base de datos..."
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD=$(exec_in_db cat /run/secrets/postgres_password 2>/dev/null || echo "")
    fi
    # Forzar drop: negar conexiones, terminar backends, dropear
    exec_in_db psql -U $DB_USER -d postgres -c "UPDATE pg_database SET datallowconn = 'false' WHERE datname = '$DB_NAME';" 2>/dev/null || true
    exec_in_db psql -U $DB_USER -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME';" 2>/dev/null || true
    sleep 2
    exec_in_db dropdb -U $DB_USER --if-exists $DB_NAME 2>/dev/null || {
        # Si aún falla, reintentar con más fuerza
        exec_in_db psql -U $DB_USER -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME';" 2>/dev/null || true
        sleep 2
        exec_in_db dropdb -U $DB_USER --if-exists $DB_NAME
    }
    exec_in_db createdb -U $DB_USER $DB_NAME
    exec_in_db psql -U $DB_USER -d postgres -c "UPDATE pg_database SET datallowconn = 'true' WHERE datname = '$DB_NAME';" 2>/dev/null || true
    info "Copiando dump al contenedor..."
    docker cp "$dump_file" $DB_CONTAINER:/tmp/restore.dump
    info "Restaurando dump..."
    set +e
    exec_in_db pg_restore -U $DB_USER -d $DB_NAME \
        --no-owner --no-privileges --disable-triggers \
        -v /tmp/restore.dump 2>&1
    PG_EXIT=$?
    set -e
    exec_in_db rm -f /tmp/restore.dump
    if [ $PG_EXIT -gt 1 ]; then
        error "Falló la restauración de la base de datos (código: $PG_EXIT)"
    elif [ $PG_EXIT -eq 1 ]; then
        warn "pg_restore reportó 1 error no fatal (FK constraint, ignorado)"
    fi
    log "Base de datos restaurada"

    # 3. Restaurar filestore (intentar ambos formatos)
    if [ -f "$FILESTORE_FILE" ]; then
        restore_filestore "$FILESTORE_FILE"
    elif [ -f "$DATA_FILE" ]; then
        restore_filestore "$DATA_FILE"
    else
        warn "No se encontró backup de filestore (ni odoo_filestore_* ni odoo_data_*)"
    fi

    # 4. Restaurar addons (si existe)
    if [ -f "$ADDONS_FILE" ]; then
        info "Restaurando addons desde: $(basename $ADDONS_FILE)"
        local TEMP_ADDONS_DIR="/tmp/addons_restore_$$"
        mkdir -p "$TEMP_ADDONS_DIR"
        tar --no-same-owner --no-same-permissions -xzf "$ADDONS_FILE" -C "$TEMP_ADDONS_DIR"
        local MODULES=$(find "$TEMP_ADDONS_DIR" -type f \( -name "__manifest__.py" -o -name "__openerp__.py" \) -exec dirname {} \; 2>/dev/null)
        if [ -n "$MODULES" ]; then
            sudo rm -rf $ADDONS_DIR/oca/* $ADDONS_DIR/extra/* $ADDONS_DIR/enterprise/* 2>/dev/null || true
            sudo mkdir -p $ADDONS_DIR/{oca,extra,enterprise}
            for module_path in $MODULES; do
                local module_name=$(basename "$module_path")
                local addon_type=$(determine_addon_type "$module_path")
                local dest_dir="$ADDONS_DIR/$addon_type/$module_name"
                [ -d "$dest_dir" ] && sudo rm -rf "$dest_dir"
                sudo cp -r "$module_path" "$dest_dir"
            done
            sudo chown -R 1001:1001 $ADDONS_DIR/ 2>/dev/null || true
        fi
        sudo rm -rf "$TEMP_ADDONS_DIR"
        log "Addons restaurados"
    else
        info "No hay backup de addons, omitiendo"
    fi

    # 5. Ajustar permisos (via Docker, sin sudo)
    info "Ajustando permisos..."
    docker_chown "$WEB_DATA_DIR"
    docker_chown "$LOGS_DIR"

    # 6. Iniciar Odoo web
    info "Iniciando Odoo web..."
    ensure_web_container

    # 7. Actualizar módulo BCV (eliminar lock para evitar conflicto)
    info "Actualizando módulo bcv_rate_update_venezuela..."
    exec_in_web rm -f /var/lib/odoo/.local/share/Odoo/sessions/*.lock 2>/dev/null || true
    exec_in_web python3 /opt/odoo/odoo-core/odoo-bin \
        -c /etc/odoo/odoo.conf \
        --update=bcv_rate_update_venezuela \
        --stop-after-init \
        --http-port=8099 2>&1 | tail -10 || true
    # Si falló la actualización BCV, agregar columnas faltantes manualmente
    exec_in_db psql -U $DB_USER -d $DB_NAME -c "
        ALTER TABLE res_company ADD COLUMN IF NOT EXISTS schedule_info VARCHAR;
        ALTER TABLE product_template ADD COLUMN IF NOT EXISTS list_price_usd NUMERIC;
        ALTER TABLE product_template ADD COLUMN IF NOT EXISTS currency_usd_id INTEGER;
        ALTER TABLE product_template ADD COLUMN IF NOT EXISTS lst_price_usd NUMERIC;
        ALTER TABLE product_template ADD COLUMN IF NOT EXISTS price_extra_usd NUMERIC;
        ALTER TABLE product_product ADD COLUMN IF NOT EXISTS lst_price_usd NUMERIC;
        ALTER TABLE sale_order ADD COLUMN IF NOT EXISTS payment_proof BYTEA;
        ALTER TABLE sale_order ADD COLUMN IF NOT EXISTS payment_proof_filename VARCHAR;
        ALTER TABLE sale_order_line ADD COLUMN IF NOT EXISTS price_usd_bcv NUMERIC;
        ALTER TABLE sale_order_line ADD COLUMN IF NOT EXISTS price_subtotal_usd_bcv NUMERIC;
        ALTER TABLE sale_order_line ADD COLUMN IF NOT EXISTS rate_value NUMERIC;
        ALTER TABLE account_move_line ADD COLUMN IF NOT EXISTS price_usd_bcv NUMERIC;
        ALTER TABLE account_move_line ADD COLUMN IF NOT EXISTS bcv_rate_value NUMERIC;
        ALTER TABLE res_currency_rate ADD COLUMN IF NOT EXISTS is_bcv_rate BOOLEAN DEFAULT FALSE;
        ALTER TABLE res_currency_rate ADD COLUMN IF NOT EXISTS source VARCHAR;
        ALTER TABLE res_currency_rate ADD COLUMN IF NOT EXISTS bcv_rate_value NUMERIC;
        ALTER TABLE res_currency_rate ADD COLUMN IF NOT EXISTS is_bcv_editable BOOLEAN DEFAULT FALSE;
        ALTER TABLE payment_provider ADD COLUMN IF NOT EXISTS is_wire_transfer BOOLEAN DEFAULT FALSE;
        ALTER TABLE sale_order ADD COLUMN IF NOT EXISTS whatsapp_sent BOOLEAN DEFAULT FALSE;
    " 2>/dev/null || true
    docker restart "$WEB_CONTAINER" 2>/dev/null || true
    sleep 5

    # Force immediate currency rate update
    info "Forzando actualización inmediata de tasa de cambio..."
    exec_in_web /opt/venv/bin/python3 -c "
import sys
sys.path.append('/opt/odoo/odoo-core')
import odoo
from odoo.modules.registry import Registry
odoo.tools.config.parse_config(['-c', '/etc/odoo/odoo.conf', '-d', '$DB_NAME'])
registry = Registry('$DB_NAME')
with registry.cursor() as cr:
    env = odoo.api.Environment(cr, odoo.SUPERUSER_ID, {})
    providers = env['currency.rate.provider'].search([('active', '=', True)])
    providers.action_update_rate()
    cr.commit()
" || true

    # 8. Instalar módulos si se solicitó
    if [ "$INSTALL_MODULES" = true ]; then
        fix_whatsapp_module
        install_oca_modules
        install_extra_modules
        install_enterprise_modules
        docker restart $WEB_CONTAINER
        sleep 10
    fi

    echo ""
    log "RESTAURACIÓN COMPLETADA"
    info "BD: $DB_NAME | Filestore: $FILESTORE_DIR/$DB_NAME"
}

# ============================================
# LIST BACKUPS
# ============================================
list_backups() {
    echo "Backups disponibles en: $BACKUP_BASE_DIR"
    for backup in $(ls -td $BACKUP_BASE_DIR/backup_* 2>/dev/null); do
        echo ""
        echo "$(basename $backup)"
        ls -lh $backup/dbodoo19_*.dump $backup/odoo_db_*.dump 2>/dev/null | awk '{print "  BD: " $9 " (" $5 ")"}' || echo "  Sin BD"
        ls -lh $backup/odoo_data_*.tar.gz $backup/odoo_filestore_*.tar.gz 2>/dev/null | awk '{print "  FS: " $9 " (" $5 ")"}' || echo "  Sin filestore"
    done
    exit 0
}

usage() {
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  -l, --list              Listar backups"
    echo "  -f, --file FILE         Restaurar archivo específico"
    echo "  -y, --yes               Omitir confirmación de destino"
    echo "  --install-modules       Instalar módulos OCA/extra/enterprise"
    echo ""
    echo "Flags de entorno:"
    echo "  --db-container NAME      (default: $DB_CONTAINER)"
    echo "  --web-container NAME     (default: $WEB_CONTAINER)"
    echo "  --db-name NAME           (default: del odoo.conf)"
    echo "  --db-user USER           (default: $DB_USER_DEFAULT)"
    echo "  --db-password PASS       (default: de secrets)"
    echo "  --odoo-conf PATH         (default: $ODOO_CONF)"
    echo "  --data-dir PATH          (default: $DATA_DIR)"
    echo "  --compose-file PATH      (default: $COMPOSE_FILE)"
    echo "  --network NAME           (default: $NETWORK_NAME)"
    echo ""
    echo "Ejemplos:"
    echo "  $0 -l"
    echo "  $0 -f backup/out/backup_2026-06-10/dbodoo19_2026-06-10.dump"
    echo "  $0 --install-modules"
    echo ""
    exit 0
}

# ============================================
# MAIN
# ============================================

# Buscar backup más reciente
if [ -d "$BACKUP_BASE_DIR" ]; then
    LATEST_BACKUP=$(ls -td "$BACKUP_BASE_DIR"/backup_* 2>/dev/null | head -1)
    BACKUP_DIR="${LATEST_BACKUP:-$BACKUP_BASE_DIR}"
fi

# Procesar argumentos
INSTALL_MODULES=false
DUMP_FILE=""
SKIP_CONFIRM=false

while [ $# -gt 0 ]; do
    case $1 in
        -l|--list) list_backups ;;
        -f|--file) shift; DUMP_FILE="$1" ;;
        -y|--yes) SKIP_CONFIRM=true ;;
        --install-modules) INSTALL_MODULES=true ;;
        --db-container) shift; DB_CONTAINER="$1" ;;
        --web-container) shift; WEB_CONTAINER="$1" ;;
        --db-name) shift; DB_NAME="$1" ;;
        --db-user) shift; DB_USER="$1" ;;
        --db-password) shift; DB_PASSWORD="$1" ;;
        --odoo-conf) shift; ODOO_CONF="$1" ;;
        --data-dir) shift; DATA_DIR="$1" ;;
        --compose-file) shift; COMPOSE_FILE="$1" ;;
        --network) shift; NETWORK_NAME="$1" ;;
        -h|--help) usage ;;
        *) error "Opción desconocida: $1. Usa -h para ayuda." ;;
    esac
    shift
done

# Leer odoo.conf
if [ -f "$ODOO_CONF" ]; then
    DB_NAME_CFG=$(grep -E '^db_name\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_USER_CFG=$(grep -E '^db_user\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
    DB_PASSWORD_CFG=$(grep -E '^db_password\s*=' "$ODOO_CONF" | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '\r')
fi

DB_NAME=${DB_NAME:-${DB_NAME_CFG:-dbodoo19}}
DB_USER=${DB_USER:-${DB_USER_CFG:-$DB_USER_DEFAULT}}
DB_PASSWORD=${DB_PASSWORD:-$DB_PASSWORD_CFG}

# Recalcular paths
ADDONS_DIR="$DATA_DIR/addons"
FILESTORE_DIR="${FILESTORE_DIR:-$DATA_DIR/filestore}"

# Auto-detectar dump
if [ -z "$DUMP_FILE" ]; then
    LATEST=$(ls -t "$BACKUP_DIR"/dbodoo19_*.dump 2>/dev/null | head -1)
    [ -z "$LATEST" ] && LATEST=$(ls -t "$BACKUP_DIR"/odoo_db_*.dump 2>/dev/null | head -1)
    if [ -z "$LATEST" ]; then
        error "No hay backups en $BACKUP_DIR. Usa -f para especificar uno."
    fi
    DUMP_FILE="$LATEST"
fi

confirm_target
restore "$DUMP_FILE" "$INSTALL_MODULES"
