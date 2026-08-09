#!/bin/bash
# 9_1_backup_sistema_completo.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

BACKUP_SCRIPT="$SCRIPT_DIR/backup/backup.sh"

# Verificar scripts
if [ ! -f "$BACKUP_SCRIPT" ]; then
    error "No se encuentra $BACKUP_SCRIPT"
fi

chmod +x "$BACKUP_SCRIPT"

# Ejecutar backup
log "🚀 Iniciando proceso de backup unificado..."
"$BACKUP_SCRIPT"

if [ $? -eq 0 ]; then
    log "✅ Proceso finalizado correctamente."
else
    error "❌ El backup falló. Revisa los logs arriba."
fi
