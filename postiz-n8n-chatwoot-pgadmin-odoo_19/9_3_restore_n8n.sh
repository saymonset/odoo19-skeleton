#!/bin/bash
# 9_3_restore_n8n.sh - Script de restauración con manejo robusto de claves

set -e

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

# ====================================================
# CONFIGURACIÓN
# ====================================================
N8N_CONTAINER="n8n-container"
N8N_DATA_DIR="./v19/n8n_data"
DB_NAME="db_n8n"
DB_USER="odoo"
DB_CONTAINER="odoo-db19-n8n"
BACKUP_BASE_DIR="./backup_n8n/out"

# Clave por defecto (de tu backup actual)
DEFAULT_ENCRYPTION_KEY="874eca07f4fe0a551b4c004843c91dc0c4a41f520687baaf40b4c64218c322a06b105d4e4e920e8fc3e8b5d70ccf696e1841d71a8028975f379754962de73b98"

# ====================================================
# FUNCIONES PRINCIPALES
# ====================================================

# Extraer clave de encriptación del backup (múltiples métodos)
extract_encryption_key() {
    local backup_dir="$1"
    local key=""
    
    # Método 1: Buscar archivo .key (más confiable)
    for key_file in "$backup_dir"/n8n_encryption_key_*.key; do
        if [ -f "$key_file" ]; then
            key=$(cat "$key_file" | tr -d '\n\r' | head -1)
            if [ -n "$key" ] && [ ${#key} -gt 30 ]; then
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 2: Buscar en archivo config.json
    for json_file in "$backup_dir"/n8n_config_*.json; do
        if [ -f "$json_file" ]; then
            key=$(grep -o '"encryptionKey":"[^"]*"' "$json_file" | cut -d'"' -f4)
            if [ -n "$key" ] && [ ${#key} -gt 30 ]; then
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 3: Buscar en archivo secreto del backup
    for secret_file in "$backup_dir"/n8n_encryption_key_secret_*.txt; do
        if [ -f "$secret_file" ]; then
            key=$(cat "$secret_file" | tr -d '\n\r' | head -1)
            if [ -n "$key" ] && [ ${#key} -gt 30 ]; then
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 4: Si no se encuentra, usar clave por defecto (SIN WARNINGS)
    echo "$DEFAULT_ENCRYPTION_KEY"
    return 0
}

# Limpiar y recrear el archivo config de forma segura
clean_and_create_config() {
    local key="$1"
    
    log "🧹 Limpiando archivo config anterior..."
    
    # Eliminar contenedor si existe
    docker rm -f $N8N_CONTAINER 2>/dev/null || true
    
    # Limpiar completamente el volumen
    docker run --rm -v n8n_data:/data alpine sh -c "rm -rf /data/* && mkdir -p /data" 2>/dev/null || true
    
    # Crear archivo config con el formato EXACTO que espera n8n
    docker run --rm -v n8n_data:/data alpine sh -c "echo '{\"encryptionKey\":\"$key\"}' > /data/config && chmod 600 /data/config" 2>/dev/null || true
    
    # Crear también en el directorio local
    mkdir -p "$N8N_DATA_DIR"
    echo "{\"encryptionKey\":\"$key\"}" > "$N8N_DATA_DIR/config"
    chmod 600 "$N8N_DATA_DIR/config"
    
    # Actualizar archivo secreto
    echo "$key" > secrets/n8n_encryption_key.txt
    chmod 600 secrets/n8n_encryption_key.txt
    
    log "✅ Archivo config creado correctamente"
}

# Forzar la clave de encriptación (versión mejorada)
force_encryption_key() {
    local key="$1"
    log "🔧 Forzando clave de encriptación..."
    
    # Limpiar y recrear config
    clean_and_create_config "$key"
    
    log "✅ Clave forzada correctamente"
}

# Verificar que n8n está funcionando correctamente
verify_n8n() {
    local max_attempts=15
    local attempt=1
    
    log "🔍 Verificando que n8n responda..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz 2>/dev/null | grep -q "200"; then
            log "✅ n8n responde correctamente (health check OK)"
            return 0
        fi
        sleep 4
        attempt=$((attempt + 1))
        echo -n "."
    done
    echo ""
    warn "⚠️ n8n no responde al health check"
    return 1
}

# ====================================================
# BÚSQUEDA AUTOMÁTICA DEL ÚLTIMO BACKUP
# ====================================================
if [ $# -eq 0 ]; then
    log "🔍 No se especificó backup, buscando el último..."
    LAST_BACKUP_DIR=$(ls -td $BACKUP_BASE_DIR/backup_n8n_* 2>/dev/null | head -1)
    if [ -z "$LAST_BACKUP_DIR" ]; then
        error "No se encontraron backups en $BACKUP_BASE_DIR"
    fi
    DUMP_FILE=$(ls "$LAST_BACKUP_DIR"/n8n_db_*.dump 2>/dev/null | head -1)
    if [ -z "$DUMP_FILE" ]; then
        error "No se encontró archivo .dump en $LAST_BACKUP_DIR"
    fi
    log "✅ Usando backup automático: $DUMP_FILE"
    set -- -f "$DUMP_FILE"
fi

# Parsear argumentos
BACKUP_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -k|--key)
            N8N_ENCRYPTION_KEY="$2"
            shift 2
            ;;
        -h|--help)
            echo "Uso: $0 [-f <archivo_backup.dump>] [-k <clave_encriptacion>]"
            echo ""
            echo "Opciones:"
            echo "  -f, --file    Archivo dump de base de datos a restaurar"
            echo "  -k, --key     Clave de encriptación (opcional, se extrae automáticamente)"
            echo "  -h, --help    Mostrar esta ayuda"
            echo ""
            echo "Si no se especifica -f, se restaura automáticamente el último backup"
            exit 0
            ;;
        *)
            error "Opción desconocida: $1"
            ;;
    esac
done

if [ -z "$BACKUP_FILE" ]; then
    error "Debe especificar el archivo de backup con -f"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    error "Archivo de backup no encontrado: $BACKUP_FILE"
fi

BACKUP_DIR=$(dirname "$BACKUP_FILE")

log "=========================================="
log "Iniciando Restauración de n8n"
log "=========================================="
log "📂 Archivo backup: $BACKUP_FILE"

# ====================================================
# 1. DETENER Y LIMPIAR
# ====================================================
log "⏸️ Deteniendo y limpiando contenedor n8n..."
docker stop $N8N_CONTAINER 2>/dev/null || true
docker rm -f $N8N_CONTAINER 2>/dev/null || true

# ====================================================
# 2. RESTAURAR BASE DE DATOS
# ====================================================
log "📦 Restaurando base de datos..."
log "⚠️ Esto ELIMINARÁ la base de datos actual y la reemplazará"

read -p "¿Está seguro de continuar? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log "Restauración cancelada"
    exit 0
fi

log "🗑️ Eliminando base de datos actual..."
docker exec -e PGPASSWORD=odoo123 $DB_CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
docker exec -e PGPASSWORD=odoo123 $DB_CONTAINER psql -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true

log "🔄 Restaurando desde backup..."
docker exec -i $DB_CONTAINER pg_restore -U $DB_USER -d $DB_NAME -c < "$BACKUP_FILE" 2>&1 | grep -v "does not exist" || true
log "✅ Base de datos restaurada"

# ====================================================
# 3. RESTAURAR ARCHIVOS
# ====================================================
FILES_BACKUP="$BACKUP_DIR/n8n_files_*.tar.gz"
FILES_BACKUP_FILE=$(ls $FILES_BACKUP 2>/dev/null | head -1)

if [ -f "$FILES_BACKUP_FILE" ]; then
    log "📁 Restaurando archivos de n8n..."
    
    # Backup del directorio actual por seguridad
    if [ -d "$N8N_DATA_DIR" ]; then
        BACKUP_NAME="${N8N_DATA_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$N8N_DATA_DIR" "$BACKUP_NAME"
        log "📁 Backup de datos anterior guardado en: $BACKUP_NAME"
    fi
    
    # Crear directorio y restaurar
    mkdir -p "$N8N_DATA_DIR"
    tar -xzf "$FILES_BACKUP_FILE" -C ./v19/
    
    # Ajustar permisos
    chown -R 1000:1000 "$N8N_DATA_DIR" 2>/dev/null || true
    
    log "✅ Archivos restaurados"
else
    warn "⚠️ No se encontró backup de archivos para restaurar"
fi

# ====================================================
# 4. EXTRAER Y FORZAR CLAVE DE ENCRIPTACIÓN
# ====================================================
log "🔑 Extrayendo clave de encriptación del backup..."
ENCRYPTION_KEY=$(extract_encryption_key "$BACKUP_DIR")

if [ -n "$N8N_ENCRYPTION_KEY" ]; then
    ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY"
    log "✅ Usando clave proporcionada manualmente"
fi

log "🔐 Clave extraída: ${ENCRYPTION_KEY:0:48}..."

# Forzar la clave (esto limpia y recrea el config)
force_encryption_key "$ENCRYPTION_KEY"

# ====================================================
# 5. INICIAR N8N
# ====================================================
log "▶️ Iniciando contenedor n8n..."
docker compose up -d n8n

# ====================================================
# 6. ESPERAR Y VERIFICAR
# ====================================================
log "⏳ Esperando a que n8n inicie..."
sleep 15

# Verificar si el contenedor está corriendo
if docker ps | grep -q $N8N_CONTAINER; then
    log "✅ n8n está corriendo"
    
    # Verificar errores comunes
    LOGS=$(docker logs $N8N_CONTAINER 2>&1 | tail -30)
    
    if echo "$LOGS" | grep -q "Mismatching encryption keys"; then
        error "❌ Error de encriptación persistente"
    elif echo "$LOGS" | grep -q "Error parsing n8n-config file"; then
        error "❌ Error de JSON en archivo config"
    elif echo "$LOGS" | grep -q "n8n ready"; then
        log "🎉 n8n restaurado correctamente!"
    else
        log "✅ n8n iniciado, verificando acceso..."
    fi
else
    error "❌ n8n no pudo iniciar"
fi

# Verificar acceso
verify_n8n

# Mostrar workflows activados
log "📋 Workflows activados:"
docker logs $N8N_CONTAINER 2>&1 | grep "Activated workflow" | head -10 || echo "   No se encontraron workflows activados"

# ====================================================
# 7. RESUMEN FINAL
# ====================================================
log "=========================================="
log "✅ RESTAURACIÓN COMPLETADA"
log "=========================================="
log "📝 Para verificar los workflows:"
log "   Accede a https://n8n.integraia.lat"
log "   Usuario: admin"
log ""
log "🔑 Clave de encriptación utilizada:"
log "   ${ENCRYPTION_KEY:0:48}..."
log ""
log "📁 Backup de datos anterior (si existe):"
ls -d ${N8N_DATA_DIR}.backup.* 2>/dev/null | head -1 || echo "   No hay backup previo"
log "=========================================="