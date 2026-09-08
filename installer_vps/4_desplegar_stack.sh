#!/bin/bash
# ============================================================================
# 4_desplegar_stack.sh
#
# Prepara el stack odoo19-skeleton (ya clonado por 2_clonar_repos.sh) para el
# cliente: carpetas v19/ con ownerships correctos, secrets auto-generados,
# .env desde env-example, odoo.conf, override con modulos_odoo y tokens nuevos
# en los compose. Idempotente y NO destructivo (no borra v19/ ni secrets/).
#
# Uso:  sudo -u odoo ./4_desplegar_stack.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
print_ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
print_warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err(){ echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_err "Ejecuta con sudo:  sudo -u odoo ./4_desplegar_stack.sh"
    exit 1
fi

ODOO_HOME="$(getent passwd odoo | cut -d: -f6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config_instalacion.env"
[ -f "$CONFIG" ] && { # shellcheck source=/dev/null
    source "$CONFIG"
}

CLIENTE_SLUG="${CLIENTE_SLUG:?Falta CLIENTE_SLUG}"
DOMINIO_BASE="${DOMINIO_BASE:?Falta DOMINIO_BASE}"
DB_NAME="${DB_NAME:-dbodoo19}"
TZ="${TZ:-America/Santiago}"
SMTP_HOST="${SMTP_HOST:-mail.integraia.lat}"
SMTP_PORT="${SMTP_PORT:-465}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_FROM="${SMTP_FROM:-$SMTP_USER}"

CLIENTE_FQDN="$CLIENTE_SLUG.$DOMINIO_BASE"
STACK_DIR="$ODOO_HOME/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19"

if [ ! -d "$STACK_DIR" ]; then
    print_err "No existe el stack: $STACK_DIR. Ejecuta primero 2_clonar_repos.sh."
    exit 1
fi
cd "$STACK_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
echo "=== Stack: $STACK_DIR ==="

# ------------------------------------------------------------
# 1) Carpetas v19/ con ownerships exactos
# ------------------------------------------------------------
echo "[1/8] Carpetas v19/..."
mkdir -p v19/{logs,odoo-web-data,config,redis_data,n8n_data,pgadmin-data}
mkdir -p v19/data/{addons/{extra,oca,enterprise},filestore}
mkdir -p v19/odoo_n8n_pgdata/{data,init}
mkdir -p v19/{chatwoot_storage,chatwoot_logs,chatwoot_tmp,chatwoot_pgdata}
mkdir -p v19/{postiz_config,postiz_uploads,temporal_elasticsearch_data}

chown -R 1001:1001 v19/logs v19/odoo-web-data v19/config v19/redis_data v19/data v19/odoo_n8n_pgdata
chown -R 1000:1000 v19/n8n_data v19/chatwoot_storage v19/chatwoot_logs v19/chatwoot_tmp v19/chatwoot_pgdata v19/postiz_config v19/postiz_uploads v19/temporal_elasticsearch_data
chown -R 5050:5050 v19/pgadmin-data
print_ok "v19/ con ownerships (1001:1001, 1000:1000, 5050:5050)"

# ------------------------------------------------------------
# 2) Secrets auto-generados
# ------------------------------------------------------------
echo "[2/8] Secrets..."
mkdir -p secrets
gen_secret() {
    local name="$1" len="${2:-32}"
    if [ ! -f "secrets/$name.txt" ]; then
        openssl rand -hex "$len" > "secrets/$name.txt"
        print_ok "  $name.txt generado"
    else
        print_ok "  $name.txt ya existe"
    fi
    chmod 600 "secrets/$name.txt"
    chown odoo:odoo "secrets/$name.txt"
}
gen_secret postgres_password
gen_secret redis_password
gen_secret n8n_password
gen_secret n8n_encryption_key
gen_secret chatwoot_secret_key_base 32

POSTGRES_PASS="$(cat secrets/postgres_password.txt)"
REDIS_PASS="$(cat secrets/redis_password.txt)"
CHATWOOT_SECRET="$(cat secrets/chatwoot_secret_key_base.txt)"
CHATWOOT_API_TOKEN="$(openssl rand -hex 24)"
CHATBOT_API_TOKEN="$(openssl rand -hex 24)"
JWT_SECRET="$(openssl rand -hex 32)"

# ------------------------------------------------------------
# 3) .env desde env-example
# ------------------------------------------------------------
echo "[3/8] .env..."
if [ -f .env ]; then
    print_ok ".env ya existe (no se sobrescribe)"
else
    if [ ! -f env-example ]; then
        print_err "Falta env-example en el stack."
        exit 1
    fi
    cp env-example .env
    # URLs
    sed -i "s|tudominio\.com|$CLIENTE_FQDN|g" .env
    sed -i "s|admin@integraia\.lat|$SMTP_FROM|g" .env
    # Redis
    sed -i "s|CAMBIAR_REDIS_PASSWORD|$REDIS_PASS|g" .env
    # Chatwoot / Postiz secrets
    sed -i "s|CAMBIAR_API_TOKEN|$CHATWOOT_API_TOKEN|g" .env
    sed -i "s|CAMBIAR_SECRETO_LARGO|$CHATWOOT_SECRET|g" .env
    sed -i "s|cambia_esto_chatwoot_db_pass|$POSTGRES_PASS|g" .env
    sed -i "s|CAMBIAR_POSTGRES_PASSWORD|$POSTGRES_PASS|g" .env
    sed -i "s|CAMBIAR_JWT_SECRETO|$JWT_SECRET|g" .env
    sed -i "s|CAMBIAR_EMAIL_NOTIFICACION|$SMTP_FROM|g" .env
    # SMTP
    sed -i "s|^SMTP_HOST=.*|SMTP_HOST=$SMTP_HOST|" .env
    sed -i "s|^SMTP_ADDRESS=.*|SMTP_ADDRESS=$SMTP_HOST|" .env
    sed -i "s|^SMTP_PORT=.*|SMTP_PORT=$SMTP_PORT|" .env
    sed -i "s|^SMTP_USER=.*|SMTP_USER=$SMTP_USER|" .env
    sed -i "s|^SMTP_USERNAME=.*|SMTP_USERNAME=$SMTP_USER|" .env
    sed -i "s|^SMTP_PASSWORD=.*|SMTP_PASSWORD='$SMTP_PASSWORD'|" .env
    sed -i "s|^SMTP_FROM=.*|SMTP_FROM=$SMTP_FROM|" .env
    sed -i "s|^SMTP_DOMAIN=.*|SMTP_DOMAIN=$DOMINIO_BASE|" .env
    sed -i "s|^ACTION_MAILER_SMTP_ADDRESS=.*|ACTION_MAILER_SMTP_ADDRESS=$SMTP_HOST|" .env
    sed -i "s|^ACTION_MAILER_SMTP_PORT=.*|ACTION_MAILER_SMTP_PORT=$SMTP_PORT|" .env
    sed -i "s|^ACTION_MAILER_SMTP_USER_NAME=.*|ACTION_MAILER_SMTP_USER_NAME=$SMTP_USER|" .env
    sed -i "s|^ACTION_MAILER_SMTP_PASSWORD=.*|ACTION_MAILER_SMTP_PASSWORD='$SMTP_PASSWORD'|" .env
    sed -i "s|^MAILER_SENDER_EMAIL=.*|MAILER_SENDER_EMAIL=$SMTP_FROM|" .env
    chmod 644 .env
    print_ok ".env creado y configurado para $CLIENTE_FQDN"
fi

# ------------------------------------------------------------
# 4) Patch de compose (URLs + tokens + secrets por cliente)
# ------------------------------------------------------------
echo "[4/8] Parcheando docker-compose.*.yml..."
BACKUP_DIR="backup_instalacion_$TS"
mkdir -p "$BACKUP_DIR"

patch_compose() {
    local file="$1"
    [ -f "$file" ] || return 0
    cp "$file" "$BACKUP_DIR/$(basename "$file")"
    # URLs n8n/chatwoot/postiz
    sed -i "s|n8n\.integraia\.lat|n8n.$CLIENTE_FQDN|g"        "$file"
    sed -i "s|n8n\.aristosoluciones\.integraia\.lat|n8n.$CLIENTE_FQDN|g" "$file"
    sed -i "s|chatwoot\.integraia\.lat|chatwoot.$CLIENTE_FQDN|g" "$file"
    sed -i "s|chatwoot\.aristosoluciones\.integraia\.lat|chatwoot.$CLIENTE_FQDN|g" "$file"
    sed -i "s|postiz\.integraia\.lat|postiz.$CLIENTE_FQDN|g"  "$file"
    sed -i "s|postiz\.aristosoluciones\.integraia\.lat|postiz.$CLIENTE_FQDN|g" "$file"
    # Secrets hardcodeados
    sed -i "s|redis123|$REDIS_PASS|g" "$file"
    sed -i "s|chatwoot123|$POSTGRES_PASS|g" "$file"
    # Chatwoot secret base (main usa el mismo valor en SECRET_KEY_BASE y RAILS_MASTER_KEY)
    sed -i "s|99f4fa1f8fadd2125a12148ccf962c5d1ae16592a7da11ef9fc795f6a5c68e97737746c53ce0ecbc45d64235e349b879312d0a28431c81c2a59165d2d7077c54|$CHATWOOT_SECRET|g" "$file"
    # Tokens API
    sed -i "s|CHATBOT_API_TOKEN=[^ ]*|CHATBOT_API_TOKEN=$CHATBOT_API_TOKEN|g" "$file"
    sed -i "s|API_AUTH_TOKEN: [^ ]*|API_AUTH_TOKEN: $CHATWOOT_API_TOKEN|g" "$file"
    sed -i "s|API_AUTH_TOKEN=[^ ]*|API_AUTH_TOKEN=$CHATWOOT_API_TOKEN|g" "$file"
}

patch_compose docker-compose.n8n.yml
patch_compose docker-compose.chatwoot.yml
patch_compose docker-compose.postiz.yml
patch_compose docker-compose.odoo.yml
print_ok "compose parcheados (backup en $BACKUP_DIR)"

# ------------------------------------------------------------
# 5) odoo.conf
# ------------------------------------------------------------
echo "[5/8] v19/config/odoo.conf..."
cat > v19/config/odoo.conf << EOF
[options]
addons_path = /opt/odoo/odoo-core/addons,/opt/odoo/custom-addons/extra,/opt/odoo/custom-addons/oca,/opt/odoo/custom-addons/enterprise
admin_passwd = $(openssl rand -hex 12)
db_host = db
db_port = 5432
db_user = odoo
db_password = $POSTGRES_PASS
db_name = $DB_NAME
db_sslmode = prefer
db_template = template0
db_maxconn = 64
http_enable = True
http_interface = 0.0.0.0
http_port = 8069
gevent_port = 8072
proxy_mode = True
workers = 2
max_cron_threads = 1
limit_memory_hard = 1610612736
limit_memory_soft = 1073741824
limit_request = 8192
limit_time_cpu = 300
limit_time_real = 600
logfile = /var/log/odoo/odoo.log
log_level = info
data_dir = /var/lib/odoo/.local/share/Odoo
server_wide_modules = base,web
without_demo = all
EOF
chown -R 1001:1001 v19/config
chmod 644 v19/config/odoo.conf
print_ok "odoo.conf generado"

# ------------------------------------------------------------
# 6) Override (monta modulos_odoo) — lo trae main; verificamos
# ------------------------------------------------------------
echo "[6/8] docker-compose.override.yml..."
if [ -f docker-compose.override.yml ]; then
    print_ok "override ya existe (monta /home/odoo/prod/modulos_odoo/shared/{extra,oca}/19.0)"
else
    print_warn "No hay override. Verifica que main lo incluya o agrégalo manualmente."
fi

# ------------------------------------------------------------
# 7) Validación del compose
# ------------------------------------------------------------
echo "[7/8] Validando compose..."
if docker compose -f docker-compose.yaml config > /dev/null 2>&1; then
    print_ok "docker compose config OK"
else
    print_warn "docker compose config falló (puede requerir Docker arrancado o ajustes)."
fi

# ------------------------------------------------------------
# 8) Resumen
# ------------------------------------------------------------
echo "[8/8] Resumen..."
echo "  Cliente   : $CLIENTE_FQDN"
echo "  DB        : $DB_NAME (user odoo)"
echo "  Secrets   : $STACK_DIR/secrets/"
echo "  CHATBOT_API_TOKEN generado (debe coincidir con Odoo ir.config_parameter)"
echo ""
print_ok "Stack listo. Siguiente: ./5_post_instalacion.sh (como odoo)"
print_warn "Luego despliega:  cd $STACK_DIR && ./1_despliegue_reconstruye_imagen_servicios_adicionales.sh && ./2_despliegue_servicios_adicionales.sh && ./4_start-all.sh"