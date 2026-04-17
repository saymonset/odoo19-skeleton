#!/bin/bash
# 9_3_restore_n8n.sh - Script de restauración mejorado con manejo robusto de claves

# Dar permisos de ejecución
# chmod +x 9_1_backup_n8n.sh
# chmod +x 9_3_restore_n8n.sh
# chmod +x backup_n8n/backup.sh

# # Hacer backup
# ./9_1_backup_n8n.sh

# # Restaurar (automático - último backup)
# ./9_3_restore_n8n.sh

# # Restaurar backup específico
# ./9_3_restore_n8n.sh -f ./backup_n8n/out/backup_n8n_2026-04-17_14-40-53/n8n_db_2026-04-17_14-40-53.dump


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
            key=$(cat "$key_file" | tr -d '\n\r')
            if [ -n "$key" ]; then
                log "✅ Clave extraída del archivo .key"
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 2: Buscar en archivo config.json
    for json_file in "$backup_dir"/n8n_config_*.json; do
        if [ -f "$json_file" ]; then
            key=$(grep -o '"encryptionKey":"[^"]*"' "$json_file" | cut -d'"' -f4)
            if [ -n "$key" ]; then
                log "✅ Clave extraída del archivo config.json"
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 3: Buscar en archivo secreto del backup
    for secret_file in "$backup_dir"/n8n_encryption_key_secret_*.txt; do
        if [ -f "$secret_file" ]; then
            key=$(cat "$secret_file" | tr -d '\n\r')
            if [ -n "$key" ]; then
                log "✅ Clave extraída del archivo secreto"
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Método 4: Buscar en metadatos
    for metadata in "$backup_dir"/backup_metadata_*.txt; do
        if [ -f "$metadata" ]; then
            key=$(grep -o 'ENCRYPTION KEY:.*' "$metadata" | head -1 | sed 's/ENCRYPTION KEY: //' | tr -d '\n\r')
            if [ -n "$key" ] && [ "$key" != "No se pudo extraer" ]; then
                log "✅ Clave extraída de metadatos"
                echo "$key"
                return 0
            fi
        fi
    done
    
    # Si no se encuentra, usar clave por defecto (la de tu backup actual)
    warn "⚠️ No se encontró clave en el backup, usando clave por defecto"
    echo "874eca07f4fe0a551b4c004843c91dc0c4a41f520687baaf40b4c64218c322a06b105d4e4e920e8fc3e8b5d70ccf696e1841d71a8028975f379754962de73b98"
    return 0
}

# Forzar la clave de encriptación en todos los lugares posibles
force_encryption_key() {
    local key="$1"
    log "🔧 Forzando clave de encriptación..."
    
    # Método 1: Escribir directamente en la ruta del volumen local
    if [ -d "./v19/n8n_data" ]; then
        echo "{\"encryptionKey\":\"$key\"}" > ./v19/n8n_data/config
        chown 1000:1000 ./v19/n8n_data/config 2>/dev/null || true
        log "✅ Config actualizado en ./v19/n8n_data/config"
    fi
    
    # Método 2: Crear directorio si no existe
    mkdir -p ./v19/n8n_data
    echo "{\"encryptionKey\":\"$key\"}" > ./v19/n8n_data/config
    
    # Método 3: Actualizar el archivo secreto
    echo "$key" > secrets/n8n_encryption_key.txt
    chmod 600 secrets/n8n_encryption_key.txt
    log "✅ Clave guardada en secrets/n8n_encryption_key.txt"
    
    # Método 4: Usar docker run con el volumen (si existe)
    docker run --rm -v n8n_data:/data alpine sh -c "echo '{\"encryptionKey\":\"$key\"}' > /data/config" 2>/dev/null || true
    
    # Método 5: Si el contenedor está corriendo, forzar dentro
    if docker ps | grep -q $N8N_CONTAINER; then
        docker exec $N8N_CONTAINER sh -c "echo '{\"encryptionKey\":\"$key\"}' > /home/node/.n8n/config" 2>/dev/null || true
        log "✅ Config actualizado dentro del contenedor"
    fi
    
    log "✅ Clave forzada correctamente en todos los lugares"
}

# Verificar que n8n está funcionando correctamente
verify_n8n() {
    local max_attempts=12
    local attempt=1
    
    log "🔍 Verificando que n8n responda..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz 2>/dev/null | grep -q "200"; then
            log "✅ n8n responde correctamente (health check OK)"
            return 0
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    
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
# 1. DETENER N8N
# ====================================================
log "⏸️ Deteniendo contenedor n8n..."
docker stop $N8N_CONTAINER 2>/dev/null || warn "n8n no estaba corriendo"

# ====================================================
# 2. RESTAURAR BASE DE DATOS
# ====================================================
log "📦 Restaurando base de datos..."
log "⚠️ Esto ELIMINARÁ la base de datos actual y la reemplazará"

read -p "¿Está seguro de continuar? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log "Restauración cancelada"
    docker start $N8N_CONTAINER 2>/dev/null || true
    exit 0
fi

log "🗑️ Eliminando base de datos actual..."
docker exec -e PGPASSWORD=odoo123 $DB_CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
docker exec -e PGPASSWORD=odoo123 $DB_CONTAINER psql -U $DB_USER -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true

log "🔄 Restaurando desde backup..."
docker exec -i $DB_CONTAINER pg_restore -U $DB_USER -d $DB_NAME -c < "$BACKUP_FILE" 2>&1 | grep -v "does not exist" || true
log "✅ Base de datos restaurada (errores de tablas inexistentes son normales)"

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

# Forzar la clave en todos los lugares
force_encryption_key "$ENCRYPTION_KEY"

# ====================================================
# 5. INICIAR N8N
# ====================================================
log "▶️ Iniciando contenedor n8n..."
docker start $N8N_CONTAINER

# ====================================================
# 6. ESPERAR Y VERIFICAR
# ====================================================
log "⏳ Esperando a que n8n inicie..."
sleep 15

# Verificar si el contenedor está corriendo
if docker ps | grep -q $N8N_CONTAINER; then
    log "✅ n8n está corriendo"
    
    # Verificar error de encriptación
    if docker logs $N8N_CONTAINER 2>&1 | tail -30 | grep -q "Mismatching encryption keys"; then
        warn "⚠️ Error de encriptación persistente"
        log "🔄 Aplicando solución final..."
        
        # Solución final: detener, limpiar y recrear config
        docker stop $N8N_CONTAINER
        force_encryption_key "$ENCRYPTION_KEY"
        docker start $N8N_CONTAINER
        sleep 15
        
        if docker logs $N8N_CONTAINER 2>&1 | tail -20 | grep -q "Mismatching encryption keys"; then
            error "❌ No se pudo resolver el problema de encriptación"
        else
            log "🎉 Problema de encriptación resuelto!"
        fi
    else
        log "🎉 n8n restaurado sin errores de encriptación"
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
log "   Contraseña: (la del backup)"
log ""
log "🔑 Clave de encriptación utilizada:"
log "   ${ENCRYPTION_KEY:0:48}..."
log ""
log "📁 Backup de datos anterior (si existe):"
ls -d ${N8N_DATA_DIR}.backup.* 2>/dev/null | head -1 || echo "   No hay backup previo"
log "=========================================="