#!/bin/bash
# ============================================================================
# configure_new_client.sh
#
# Configura TODO el stack (n8n + Chatwoot + Postiz + SMTP) para el despliegue
# de un cliente NUEVO. Te pregunta los datos (dominio, tokens, correo) y
# reemplaza automaticamente en:
#   - .env
#   - docker-compose.chatwoot.yml   (URLs + token API)
#   - docker-compose.n8n.yml        (URLs)
#   - Workflows de n8n (JSON)       (opcional: URLs Chatwoot/Odoo + token)
#
# ANTES de correrlo: haz una copia del despliegue base (este directorio),
# porque el script MODIFICA los archivos en el lugar.
#
# Uso:  ./configure_new_client.sh
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

SCRIPT_DIR="$(pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_CHATWOOT="$SCRIPT_DIR/docker-compose.chatwoot.yml"
COMPOSE_N8N="$SCRIPT_DIR/docker-compose.n8n.yml"
N8N_JSON_FILE="$SCRIPT_DIR/../n8n_json/chatbot_create_lead_0_con_menu_whatsapp.json"

echo "============================================================"
echo "  CONFIGURADOR DE CLIENTE NUEVO  (Odoo 19 + n8n + Chatwoot)"
echo "============================================================"
echo ""

# ---------------------------------------------------------------
# 1) DATOS DEL CLIENTE (se preguntan todos)
# ---------------------------------------------------------------
read -r -p "1) Dominio base del cliente (ej: integraia.lat, micliente.com): " DOMINIO
DOMINIO=${DOMINIO:-integraia.lat}

read -r -p "2) Token API de Chatwoot (Settings > Account > API tokens): " CHATWOOT_TOKEN
if [ -z "$CHATWOOT_TOKEN" ]; then
    echo "❌ El token de Chatwoot es OBLIGATORIO. Cancelo."
    exit 1
fi

read -r -p "3) SMTP host (ej: mail.privateemail.com): " SMTP_HOST
SMTP_HOST=${SMTP_HOST:-mail.privateemail.com}
read -r -p "4) SMTP puerto (ej: 465): " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-465}
read -r -p "5) SMTP usuario/correo (ej: admin@integraia.lat): " SMTP_USER
read -r -p "6) SMTP password: " SMTP_PASSWORD
read -r -p "7) SMTP from (ej: admin@integraia.lat): " SMTP_FROM

N8N_URL="https://n8n.$DOMINIO"
CHATWOOT_URL="https://chatwoot.$DOMINIO"
POSTIZ_URL="https://postiz.$DOMINIO"

echo ""
echo "------------------------------------------------------------"
echo " RESUMEN DE LO QUE SE APLICARA:"
echo "   Dominio            : $DOMINIO"
echo "   n8n URL            : $N8N_URL"
echo "   Chatwoot URL       : $CHATWOOT_URL"
echo "   Postiz URL         : $POSTIZ_URL"
echo "   Chatwoot token     : $CHATWOOT_TOKEN"
echo "   SMTP host/port     : $SMTP_HOST:$SMTP_PORT"
echo "   SMTP user/pass/from: $SMTP_USER / **** / $SMTP_FROM"
echo "------------------------------------------------------------"
read -r -p "¿Aplicar? (s/n): " CONFIRM
if [ "${CONFIRM,,}" != "s" ]; then
    echo "Cancelado. No se modifico nada."
    exit 0
fi

# ---------------------------------------------------------------
# 2) BACKUP automatico de los archivos que se van a tocar
# ---------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$SCRIPT_DIR/backup_config_$TIMESTAMP"
mkdir -p "$BACKUP_DIR"
cp "$ENV_FILE" "$BACKUP_DIR/.env" 2>/dev/null || true
cp "$COMPOSE_CHATWOOT" "$BACKUP_DIR/" 2>/dev/null || true
cp "$COMPOSE_N8N" "$BACKUP_DIR/" 2>/dev/null || true
cp "$N8N_JSON_FILE" "$BACKUP_DIR/" 2>/dev/null || true
echo "📦 Backup creado en: $BACKUP_DIR"
echo ""

# ---------------------------------------------------------------
# 3) FUNCIONES AUXILIARES (reemplazo seguro de variables)
# ---------------------------------------------------------------

# Reemplaza el VALOR de una variable en un archivo .env (o la agrega al final)
set_env_var() {
    local file="$1" var="$2" value="$3"
    if grep -q "^${var}=" "$file"; then
        # sed con '|' como delimitador para tolerar '/' en los valores
        sed -i "s|^${var}=.*|${var}=${value}|" "$file"
    else
        echo "${var}=${value}" >> "$file"
    fi
}

# Reemplaza un valor hardcodeado en archivos JSON/YAML (ej: URLs de dominio)
replace_value() {
    local file="$1" old="$2" new="$3"
    if grep -qF "$old" "$file"; then
        sed -i "s|$(printf '%s' "$old" | sed 's/[.[\*^$]/\\&/g')|$(printf '%s' "$new" | sed 's/[&|]/\\&/g')|g" "$file"
        echo "   ✓ $file : '$old' -> '$new'"
    fi
}

# ---------------------------------------------------------------
# 4) APLICAR CAMBIOS EN .env
# ---------------------------------------------------------------
echo "===== .env ====="
set_env_var "$ENV_FILE" "N8N_EDITOR_BASE_URL" "$N8N_URL"
set_env_var "$ENV_FILE" "CHATWOOT_API_TOKEN" "$CHATWOOT_TOKEN"
set_env_var "$ENV_FILE" "CHATWOOT_FRONTEND_URL" "$CHATWOOT_URL"
set_env_var "$ENV_FILE" "CHATWOOT_RAILS_HOST" "$CHATWOOT_URL"
set_env_var "$ENV_FILE" "ASSET_HOST" "$CHATWOOT_URL"
set_env_var "$ENV_FILE" "ACTIVE_STORAGE_HOST" "$CHATWOOT_URL"
set_env_var "$ENV_FILE" "RAILS_STORAGE_HOST" "$CHATWOOT_URL"
set_env_var "$ENV_FILE" "MAIN_URL" "$POSTIZ_URL"
set_env_var "$ENV_FILE" "FRONTEND_URL" "$POSTIZ_URL"
set_env_var "$ENV_FILE" "SMTP_HOST" "$SMTP_HOST"
set_env_var "$ENV_FILE" "SMTP_ADDRESS" "$SMTP_HOST"
set_env_var "$ENV_FILE" "SMTP_PORT" "$SMTP_PORT"
set_env_var "$ENV_FILE" "SMTP_USER" "$SMTP_USER"
set_env_var "$ENV_FILE" "SMTP_USERNAME" "$SMTP_USER"
set_env_var "$ENV_FILE" "SMTP_PASSWORD" "'$SMTP_PASSWORD'"
set_env_var "$ENV_FILE" "SMTP_FROM" "$SMTP_FROM"
set_env_var "$ENV_FILE" "MAILER_SENDER_EMAIL" "$SMTP_FROM"
set_env_var "$ENV_FILE" "ACTION_MAILER_SMTP_ADDRESS" "$SMTP_HOST"
set_env_var "$ENV_FILE" "ACTION_MAILER_SMTP_PORT" "$SMTP_PORT"
set_env_var "$ENV_FILE" "ACTION_MAILER_SMTP_USER_NAME" "$SMTP_USER"
set_env_var "$ENV_FILE" "ACTION_MAILER_SMTP_PASSWORD" "'$SMTP_PASSWORD'"
set_env_var "$ENV_FILE" "BACKUP_NOTIFY_TO" "$SMTP_FROM"
echo "   ✓ Variables de .env actualizadas"
echo ""

# ---------------------------------------------------------------
# 5) APLICAR CAMBIOS EN docker-compose.chatwoot.yml
# ---------------------------------------------------------------
echo "===== docker-compose.chatwoot.yml ====="
replace_value "$COMPOSE_CHATWOOT" "chatwoot.integraia.lat" "chatwoot.$DOMINIO"
replace_value "$COMPOSE_CHATWOOT" "$CHATWOOT_TOKEN" "$CHATWOOT_TOKEN"  # no-op; token se deja igual si ya estaba
echo ""

# ---------------------------------------------------------------
# 6) APLICAR CAMBIOS EN docker-compose.n8n.yml
# ---------------------------------------------------------------
echo "===== docker-compose.n8n.yml ====="
replace_value "$COMPOSE_N8N" "n8n.integraia.lat" "n8n.$DOMINIO"
echo ""

# ---------------------------------------------------------------
# 7) WORKFLOWS N8N (opcional, pero RECOMENDADO)
#    El workflow JSON tiene hardcodeadas:
#      - la URL de Chatwoot (https://chatwoot.integraia.lat/api/v1/...)
#      - el token api_access_token (yvJxkWhiTMioFgKTZTq3ZE3h)
#      - la URL de Odoo (https://integraia.lat/ai_chatbot_1_portal/...)
# ---------------------------------------------------------------
read -r -p "¿Actualizar tambien los workflows de n8n (JSON)? (s/n): " UPDATE_N8N
if [ "${UPDATE_N8N,,}" == "s" ]; then
    echo "===== Workflows n8n (JSON) ====="
    OLD_TOKEN="yvJxkWhiTMioFgKTZTq3ZE3h"
    if grep -qF "chatwoot.integraia.lat" "$N8N_JSON_FILE"; then
        replace_value "$N8N_JSON_FILE" "chatwoot.integraia.lat" "chatwoot.$DOMINIO"
    fi
    if grep -qF "$OLD_TOKEN" "$N8N_JSON_FILE"; then
        sed -i "s|$OLD_TOKEN|$CHATWOOT_TOKEN|g" "$N8N_JSON_FILE"
        echo "   ✓ token api_access_token actualizado en workflow"
    fi
    # URLs de Odoo (ai_chatbot_1_portal) apuntan al dominio base
    replace_value "$N8N_JSON_FILE" "https://integraia.lat/ai_chatbot" "https://$DOMINIO/ai_chatbot"
    echo ""
fi

# ---------------------------------------------------------------
# 8) RESUMEN FINAL (pasos manuales que quedan)
# ---------------------------------------------------------------
echo "============================================================"
echo " ✅ LISTO. Resumen de acciones manuales que quedan:"
echo "============================================================"
echo ""
echo " 1) SECRETOS (obligatorio si cambiaste el password de postgres):"
echo "      vim secrets/postgres_password.txt    # password de la BD"
echo "      vim secrets/n8n_password.txt         # login de n8n"
echo "      vim secrets/n8n_encryption_key.txt   # clave de cifrado n8n"
echo "      vim secrets/chatwoot_secret_key_base.txt"
echo ""
echo " 2) DOMINIOS en DNS/nginx (apuntar a este servidor):"
echo "      n8n.$DOMINIO  -> nginx (puerto 5678)"
echo "      chatwoot.$DOMINIO -> nginx (puerto 3000)"
echo "      postiz.$DOMINIO -> nginx (puerto 4007)"
echo ""
echo " 3) En n8n (UI) si NO actualizaste los JSON:"
echo "      Workflow 'chatbot_create_lead' -> reemplazar chatwoot URL y token"
echo ""
echo " 4) En Odoo: token CHATBOT_API_TOKEN debe coincidir con el de este"
echo "    stack (esta en docker-compose.n8n.yml y en la config de Odoo"
echo "    del modulo ai_chatbot_1_portal)."
echo ""
echo " 5) REINICIAR el stack:"
echo "      ./5_res_start-all.sh        (o docker compose up -d)"
echo ""
echo "Backup de los archivos modificados: $BACKUP_DIR"
echo "============================================================"