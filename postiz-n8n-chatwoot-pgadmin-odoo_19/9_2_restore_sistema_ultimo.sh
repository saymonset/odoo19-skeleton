#!/bin/bash
# 9_2_restore_sistema_ultimo.sh
set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Verificar scripts
if [ ! -f "./backup/restore_full.sh" ]; then
    error "No se encuentra ./backup/restore_full.sh"
fi

chmod +x ./backup/restore_full.sh

# Ejecutar restauración
log "🚀 Iniciando proceso de restauración automática (último backup)..."
./backup/restore_full.sh

if [ $? -eq 0 ]; then
    log "✅ Proceso finalizado."
else
    error "❌ La restauración falló."
fi
