#!/bin/bash
# ============================================================================
# odoo_user_create.sh  (wrapper legacy)
#
# Deprecado: la creación del usuario odoo y de todo el VPS ahora vive en el
# kit portable installer_vps/. Este wrapper mantiene compatibilidad con el
# script histórico y delega en el paso 0 del kit.
#
# Uso:  sudo ./odoo_user_create.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_SCRIPT="$SCRIPT_DIR/installer_vps/0_crear_usuario_odoo.sh"

if [ ! -f "$KIT_SCRIPT" ]; then
    echo "[ERROR] No se encuentra $KIT_SCRIPT (¿falta installer_vps/?)."
    echo "        Recupéralo del repo o del tarball portable."
    exit 1
fi

echo "[INFO] Este script es un wrapper. Delegando en installer_vps/0_crear_usuario_odoo.sh ..."
echo ""
exec "$KIT_SCRIPT"