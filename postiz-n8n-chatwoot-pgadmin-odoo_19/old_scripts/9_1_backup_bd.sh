#!/bin/bash
# 9_1_backup_bd.sh

set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Verificar que el script de backup existe
if [ ! -f "./backup/backup.sh" ]; then
    error "No se encuentra ./backup/backup.sh"
fi

# Dar permisos de ejecución
chmod +x ./backup/backup.sh

# Ejecutar backup
log "=========================================="
log "Ejecutando backup de Odoo"
log "=========================================="

./backup/backup.sh

if [ $? -eq 0 ]; then
    log "✅ Backup completado exitosamente"
    info "Los backups se guardaron en: ./backup/out/"
    echo ""
    echo "📂 Últimos backups:"
    ls -ltd ./backup/out/backup_* | head -5
else
    error "❌ Falló el backup"
fi