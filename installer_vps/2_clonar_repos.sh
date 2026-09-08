#!/bin/bash
# ============================================================================
# 2_clonar_repos.sh
#
# Crea el layout de /home/odoo (bin/, dynamicconfig/, opencode/) y clona desde
# GitHub los repos modulos_odoo y odoo19-skeleton en ~/prod/ (o ~/lead/ según
# config AMBIENTES). No empaqueta repos: siempre se bajan de GitHub.
#
# Uso:  sudo -u odoo ./2_clonar_repos.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_err "Ejecuta con sudo:  sudo -u odoo ./2_clonar_repos.sh"
    exit 1
fi

ODOO_HOME="$(getent passwd odoo | cut -d: -f6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config_instalacion.env"
[ -f "$CONFIG" ] && { # shellcheck source=/dev/null
    source "$CONFIG"
}

GITHUB_SKELETON_URL="${GITHUB_SKELETON_URL:-git@github.com:saymonset/odoo19-skeleton.git}"
GITHUB_MODULOS_URL="${GITHUB_MODULOS_URL:-git@github.com:saymonset/modulos_odoo.git}"
SKELETON_BRANCH="${SKELETON_BRANCH:-main}"
MODULOS_BRANCH="${MODULOS_BRANCH:-main}"
AMBIENTES="${AMBIENTES:-prod}"

echo "=== [1/3] Estructura base /home/odoo ==="
for d in bin dynamicconfig opencode; do
    install -d -o odoo -g odoo "$ODOO_HOME/$d"
    print_ok "$ODOO_HOME/$d"
done

# ------------------------------------------------------------
# Clonado por ambiente (prod, lead)
# ------------------------------------------------------------
clone_repo() {
    local env_dir="$1" repo="$2" url="$3" branch="$4"
    if [ -d "$env_dir" ]; then
        print_ok "$repo ya existe en $env_dir (se omite el clonado)"
    else
        install -d -o odoo -g odoo "$(dirname "$env_dir")"
        print_ok "Clonando $repo (rama $branch) -> $env_dir"
        sudo -u odoo git clone --branch "$branch" "$url" "$env_dir"
    fi
}

echo "[2/3] Clonando repos..."
for env in $AMBIENTES; do
    base="$ODOO_HOME/$env"
    clone_repo "$base/modulos_odoo"    "modulos_odoo"    "$GITHUB_MODULOS_URL"    "$MODULOS_BRANCH"
    clone_repo "$base/odoo19-skeleton" "odoo19-skeleton" "$GITHUB_SKELETON_URL" "$SKELETON_BRANCH"
done

# ------------------------------------------------------------
# Verificación
# ------------------------------------------------------------
echo "[3/3] Verificación..."
for env in $AMBIENTES; do
    echo "----------------------------------------"
    ls -ld "$ODOO_HOME/$env"/* 2>/dev/null || print_warn "$ODOO_HOME/$env vacío"
done

print_ok "Repos clonados. Siguiente: ./3_instalar_docker.sh (como odoo)"