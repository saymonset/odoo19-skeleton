#!/bin/bash
# 9_2_restore_sistema_ultimo.sh
set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# rclone para restaurar desde Cloudflare R2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RCLONE="$(command -v rclone 2>/dev/null || echo "$HOME/bin/rclone")"

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

cat << "EOF"

============================================================
RESTAURACIÓN DESDE CLOUDFLARE R2 (backup remoto cifrado)
============================================================
Use este procedimiento si el servidor se perdió y los backups
locales NO existen. rclone descifra automáticamente con las
contraseñas de ~/.config/rclone/rclone.conf.

1) Listar backups remotos disponibles (diarios):
   $RCLONE lsd r2-crypt:daily

2) Descargar y descifrar un backup a la carpeta ./restored:
   $RCLONE copy r2-crypt:daily/backup_<FECHA_HORA> ./restored/

   Ejemplo:
   $RCLONE copy r2-crypt:daily/backup_2026-08-09_22-33-02 ./restored/

   Backups semanales (>4 semanas de ventana):
   $RCLONE copy r2-crypt:weekly/weekly_<FECHA_HORA> ./restored/

3) Con ./restored/ ya poblado, use ./backup/restore_full.sh
   (o los scripts 9_4_restore_solo_odoo.sh / 9_4_restore_solo_n8n.sh
   para restaurar solo un servicio).

REQUISITOS: rclone instalado (~/bin/rclone) y el archivo
~/.config/rclone/rclone.conf con los remotes r2 y r2-crypt.
============================================================
EOF
