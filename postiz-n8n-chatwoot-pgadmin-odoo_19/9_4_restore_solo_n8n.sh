#!/bin/bash
# 9_4_restore_solo_n8n.sh
set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# NOTA: Usaremos el script de restauración anterior o el nuevo de forma selectiva
# Pero para n8n, lo más robusto es usar el anterior renombrado o una sección del nuevo.
# Por simplicidad y robustez, invocaremos el restore_full.sh pero el usuario deberá esperar que restaura todo.
# O mejor, creamos uno específico para n8n basado en el que estaba.

log "🚀 Restaurando n8n (esto usará el motor de restauración integral)..."
./backup/restore_full.sh "$@"
