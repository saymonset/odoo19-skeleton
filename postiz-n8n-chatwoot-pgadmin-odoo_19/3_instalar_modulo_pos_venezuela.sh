#!/bin/bash

# Script para instalar los modulos POS Venezuela Dual Currency + IGTF,
# Odoo Chatwoot Connector y Web Responsive (y sus dependencias) sin que se cuelgue.
#
# ¿Por que un script y no el boton "Instalar" la UI?
#  El modulo arrastra ~44 dependencias (POS + eCommerce + Contabilidad +
#  Stock + Compras + BCV + WhatsApp). Al instalarlo de golpe desde la UI,
#  el cron del propio Odoo choca con la transaccion de instalacion
#  ("could not serialize access") y el worker (limite 600s) puede ser
#  asesinado a mitad. El resultado: los modulos quedan "para instalar"
#  para siempre y la app queda colgada.
#
#  Este script instala por linea de comandos en un contenedor dedicado,
#  SIN cron, SIN workers HTTP y SIN limite de tiempo => no se cuelga.
#
# Autor: Configuracion personalizada
set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_header()  { echo -e "${BLUE}============================================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}============================================================${NC}"; }

# --- Configuracion ---
DB_CONTAINER="odoo-db19-n8n"
WEB_CONTAINER="odoo-19-web"
ODOO_IMAGE="odoo-pers:19"
ODOO_NETWORK="odoo_network_19"
DB_NAME="dbodoo19"
DB_USER="odoo"
MODULES="pos_venezuela_dual_currency,odoo_chatwoot_connector,web_responsive"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/v19/config"
LOGS_DIR="$SCRIPT_DIR/v19/logs"
FILESTORE_DIR="$SCRIPT_DIR/v19/data/filestore"
ENTERPRISE_DIR="$SCRIPT_DIR/v19/data/addons/enterprise"
SECRET_FILE="$SCRIPT_DIR/secrets/postgres_password.txt"
EXTRA_ADDONS="/home/odoo/prod/modulos_odoo/shared/extra/19.0"
OCA_ADDONS="/home/odoo/prod/modulos_odoo/shared/oca/19.0"

# Asegura que el web vuelva a levantarse aunque algo falle
restart_web() {
    docker start "$WEB_CONTAINER" >/dev/null 2>&1 || true
}
trap restart_web EXIT

# ============================================
# 1. VERIFICAR PRE-REQUISITOS
# ============================================
print_header "Paso 1: Verificando pre-requisitos"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
    print_error "El contenedor $DB_CONTAINER no esta corriendo. Ejecuta primero 1_ y 2_ despliegue."
    exit 1
fi
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$ODOO_IMAGE"; then
    print_error "La imagen $ODOO_IMAGE no existe. Ejecuta primero 1_despliegue_reconstruye_imagen_servicios_adicionales.sh"
    exit 1
fi
print_message "OK: $DB_CONTAINER corriendo e imagen $ODOO_IMAGE presente."

# ============================================
# 2. AUTOCURA: limpiar estado pegado y sesiones colgadas
# ============================================
print_header "Paso 2: Limpiando estado pegado (autocura)"

STUCK=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM pg_stat_activity WHERE datname='$DB_NAME' AND state='idle in transaction' AND pid<>pg_backend_pid();")
if [ "${STUCK:-0}" -gt 0 ]; then
    print_warning "Hay $STUCK sesion(es) 'idle in transaction' reteniendo locks. Terminandolas..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME' AND state='idle in transaction' AND pid<>pg_backend_pid();" >/dev/null
    print_message "OK: sesiones colgadas terminadas."
else
    print_message "No hay sesiones colgadas."
fi

TO_INSTALL=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM ir_module_module WHERE state='to install';")
if [ "${TO_INSTALL:-0}" -gt 0 ]; then
    print_warning "Hay $TO_INSTALL modulo(s) marcados 'to install' de un intento fallido. Reseteando..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
        "UPDATE ir_module_module SET state='uninstalled' WHERE state='to install';" >/dev/null
    print_message "OK: marcas reseteadas."
else
    print_message "No hay marcas 'to install' pendientes."
fi

# ============================================
# 3. DETENER ODOO WEB (evita colision de cron/workers)
# ============================================
print_header "Paso 3: Deteniendo $WEB_CONTAINER (para instalar sin interferencias)"
if docker ps --format '{{.Names}}' | grep -qx "$WEB_CONTAINER"; then
    docker stop "$WEB_CONTAINER" >/dev/null
    print_message "OK: $WEB_CONTAINER detenido."
else
    print_message "$WEB_CONTAINER ya estaba detenido."
fi

# ============================================
# 4. INSTALAR POR LINEA DE COMANDOS (contenedor dedicado)
# ============================================
print_header "Paso 4: Instalando $MODULES (y sus dependencias)"
print_message "Esto puede tardar varios minutos POS+eCommerce+Contabilidad+Stock..."
print_message "Veras el progreso en vivo. NO interrumpas."

INSTALL_RC=0
docker run --rm --name "odoo-instalar-temp-$$" \
    --network "$ODOO_NETWORK" \
    --user 1001:1001 \
    -v "$CONFIG_DIR:/etc/odoo" \
    -v "$EXTRA_ADDONS:/opt/odoo/custom-addons/extra" \
    -v "$OCA_ADDONS:/opt/odoo/custom-addons/oca" \
    -v "$ENTERPRISE_DIR:/opt/odoo/custom-addons/enterprise" \
    -v "$LOGS_DIR:/var/log/odoo" \
    -v "$FILESTORE_DIR:/var/lib/odoo/.local/share/Odoo/filestore" \
    -v "$SECRET_FILE:/run/secrets/postgres_password:ro" \
    "$ODOO_IMAGE" \
    -i "$MODULES" --stop-after-init --without-demo=True --log-level=info || INSTALL_RC=$?

# Si la instalacion fallo, el trap levantara el web de todas formas
if [ "$INSTALL_RC" -ne 0 ]; then
    print_error "La instalacion ha fallado (codigo $INSTALL_RC)."
    print_error "Revisa el log de arriba y /var/log/odoo/odoo.log."
    print_error "Si la BD queda en mal estado, ejecuta ./borrar-bd-odoo19.sh para resetearla."
    exit "$INSTALL_RC"
fi

# ============================================
# 5. LEVANTAR ODOO WEB
# ============================================
print_header "Paso 5: Levantando $WEB_CONTAINER"
docker start "$WEB_CONTAINER" >/dev/null
print_message "OK: $WEB_CONTAINER iniciado."

# ============================================
# 6. VERIFICAR INSTALACION
# ============================================
print_header "Paso 6: Verificando instalacion"
NOT_INSTALLED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM ir_module_module WHERE name IN ('pos_venezuela_dual_currency','odoo_chatwoot_connector','web_responsive') AND state<>'installed';")
INSTALLED_COUNT=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT count(*) FROM ir_module_module WHERE state='installed';")

if [ "${NOT_INSTALLED:-1}" -eq 0 ]; then
    print_message "OK: todos los modulos estan INSTALADOS."
    print_message "Total de modulos instalados ahora: $INSTALLED_COUNT"
    print_header "Instalacion completada con exito"
    echo -e "${GREEN}=== Acceso a Odoo 19 ===${NC}"
    echo -e "${GREEN}OK:${NC} http://localhost:18069 (admin/admin)"
    echo ""
    echo "Verifica en Apps que 'POS Venezuela Dual Currency + IGTF',"
    echo "'Odoo Chatwoot Connector' y 'Web Responsive' aparezcan instalados,"
    echo "y que sus dependencias (eCommerce, Point of Sale, BCV, etc.) esten activas."
else
    print_error "Hay $NOT_INSTALLED modulo(s) que no quedaron en estado 'installed'."
    print_error "Revisa el log de arriba. Si hace falta, resetea con ./borrar-bd-odoo19.sh."
    exit 1
fi