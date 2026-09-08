#!/bin/bash
# ============================================================================
# 0_crear_usuario_odoo.sh
#
# Crea el usuario 'odoo' con los grupos y permisos que exige el stack
# (mismo perfil que el VPS de referencia: uid 1001, adm,sudo,docker,odoogroup).
# Idempotente y no destructivo: si el usuario ya existe, solo verifica y completa.
#
# Uso:  sudo ./0_crear_usuario_odoo.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_err "Ejecuta con sudo o como root."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config_instalacion.env"
if [ -f "$CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG"
fi
ODOO_UID="${ODOO_UID:-1001}"

echo "=== [0/6] Creación de usuario odoo ==="

# ------------------------------------------------------------
# 1) Grupos necesarios
# ------------------------------------------------------------
echo "[1/6] Verificando grupos..."
for group in docker odoo odoogroup; do
    if getent group "$group" > /dev/null 2>&1; then
        print_ok "Grupo $group ya existe"
    else
        groupadd "$group"
        print_ok "Grupo $group creado"
    fi
done

# ------------------------------------------------------------
# 2) Usuario odoo
# ------------------------------------------------------------
echo "[2/6] Verificando usuario odoo..."
if id odoo > /dev/null 2>&1; then
    print_ok "El usuario odoo ya existe: $(id odoo)"
else
    print_ok "Creando usuario odoo (uid $ODOO_UID)..."
    # -M no home temporal; -m crea home; -G grupos secundarios
    useradd -m -s /bin/bash -g odoo -G adm,sudo,docker,odoogroup -u "$ODOO_UID" odoo
    print_ok "Usuario odoo creado"
fi

# ------------------------------------------------------------
# 3) Grupos garantizados (idempotente)
# ------------------------------------------------------------
echo "[3/6] Garantizando grupos secundarios..."
usermod -aG adm,sudo,docker,odoogroup odoo
print_ok "Grupos: $(groups odoo)"

# ------------------------------------------------------------
# 4) Password temporal (solo si no tiene)
# ------------------------------------------------------------
echo "[4/6] Password..."
if passwd --status odoo | grep -q 'L\|NP'; then
    TEMP_PASS="$(openssl rand -base64 12)"
    echo "odoo:$TEMP_PASS" | chpasswd
    print_warn "Password temporal generada (anótala y cámbiala luego):"
    echo "    $TEMP_PASS"
else
    print_ok "El usuario odoo ya tiene password configurada (no se toca)"
fi

# ------------------------------------------------------------
# 5) Permisos del home
# ------------------------------------------------------------
echo "[5/6] Permisos del home..."
chown -R odoo:odoo /home/odoo
chmod 750 /home/odoo
print_ok "Home /home/odoo con dueño odoo:odoo y 750"

# ------------------------------------------------------------
# 6) Verificación final
# ------------------------------------------------------------
echo "[6/6] Verificación..."
echo "----------------------------------------"
id odoo
groups odoo
ls -ld /home/odoo
echo "----------------------------------------"
print_ok "Usuario odoo configurado. Siguiente: ./1_preparar_ssh_git.sh (como odoo)"