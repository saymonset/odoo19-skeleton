#!/bin/bash
# ============================================================================
# 1_preparar_ssh_git.sh
#
# Genera/instala la llave SSH ed25519 de GitHub para el usuario odoo,
# configura ~/.ssh/config y ~/.gitconfig, y valida con `ssh -T git@github.com`.
# Incluye pausa para que el usuario agregue la llave pública a GitHub.
#
# Uso:  sudo -u odoo ./1_preparar_ssh_git.sh     (o `su - odoo` y ejecutar)
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_err "Ejecuta con sudo:  sudo -u odoo ./1_preparar_ssh_git.sh"
    exit 1
fi

ODOO_HOME="$(getent passwd odoo | cut -d: -f6)"
SSH_DIR="$ODOO_HOME/.ssh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config_instalacion.env"
[ -f "$CONFIG" ] && { # shellcheck source=/dev/null
    source "$CONFIG"
}
GIT_NAME="${GIT_NAME:-saymonset}"
GIT_EMAIL="${GIT_EMAIL:-saymon_set@hotmail.com}"

echo "=== [1/6] Preparación SSH + Git (usuario odoo) ==="

# ------------------------------------------------------------
# 1) Llave ed25519
# ------------------------------------------------------------
echo "[1/6] Llave SSH..."
if [ -f "$SSH_DIR/id_ed25519" ]; then
    print_ok "Llave ya existe: $SSH_DIR/id_ed25519"
else
    install -d -m 700 -o odoo -g odoo "$SSH_DIR"
    ssh-keygen -t ed25519 -C "odoo@$HOSTNAME" -f "$SSH_DIR/id_ed25519" -N "" > /dev/null
    chown odoo:odoo "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ed25519.pub"
    print_ok "Llave ed25519 generada"
fi

# ------------------------------------------------------------
# 2) known_hosts de GitHub (verificado contra fingerprint oficial)
# ------------------------------------------------------------
echo "[2/6] known_hosts de GitHub..."
GITHUB_FP="SHA256:uNiVztksCsDhcc0u9e8BujQXVUpKZIDTMczCvj3tD2s"
touch "$SSH_DIR/known_hosts" && chown odoo:odoo "$SSH_DIR/known_hosts"
if ssh-keygen -F github.com -f "$SSH_DIR/known_hosts" > /dev/null 2>&1; then
    print_ok "github.com ya en known_hosts"
else
    if ssh-keyscan github.com 2>/dev/null | grep -F "$GITHUB_FP" > "$SSH_DIR/known_hosts"; then
        chown odoo:odoo "$SSH_DIR/known_hosts"
        print_ok "github.com agregado a known_hosts (fingerprint verificado)"
    else
        print_err "No se pudo verificar el fingerprint de github.com. Revisa la red."
        exit 1
    fi
fi

# ------------------------------------------------------------
# 3) ~/.ssh/config
# ------------------------------------------------------------
echo "[3/6] Config SSH..."
cat > "$SSH_DIR/config" << EOF
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
EOF
chown odoo:odoo "$SSH_DIR/config" && chmod 600 "$SSH_DIR/config"
print_ok "$SSH_DIR/config escrito"

# ------------------------------------------------------------
# 4) .gitconfig
# ------------------------------------------------------------
echo "[4/6] Git config..."
cat > "$ODOO_HOME/.gitconfig" << EOF
[user]
    name = $GIT_NAME
    email = $GIT_EMAIL
EOF
chown odoo:odoo "$ODOO_HOME/.gitconfig"
print_ok ".gitconfig con $GIT_NAME <$GIT_EMAIL>"

# ------------------------------------------------------------
# 5) Pausa para agregar la llave pública a GitHub
# ------------------------------------------------------------
echo "[5/6] Agregar la llave a GitHub..."
PUB="$(cat "$SSH_DIR/id_ed25519.pub")"
echo ""
echo "  Copia esta llave pública y agrégala a GitHub"
echo "  (Settings -> SSH and GPG keys -> New SSH key):"
echo ""
echo "  $PUB"
echo ""
while true; do
    read -r -p "¿Ya la agregaste? Responde si cuando esté lista (si): " CONFIRM
    case "${CONFIRM,,}" in
        s|si|sí|y|yes) break ;;
        *) echo "  Aún no. Agrega la llave y escribe 'si'." ;;
    esac
done

# ------------------------------------------------------------
# 6) Validación de conexión
# ------------------------------------------------------------
echo "[6/6] Validando conexión con GitHub..."
if sudo -u odoo ssh -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    print_ok "Conexión SSH a GitHub verificada"
else
    print_err "ssh -T git@github.com falló. Revisa que la llave esté agregada."
    exit 1
fi

print_ok "SSH + Git listos. Siguiente: ./2_clonar_repos.sh (como odoo)"