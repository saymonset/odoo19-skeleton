#!/bin/bash

# Script para pausar/levantar servicios secundarios bajo demanda.
#
# ¿Por que un script y no `docker stop` a mano?
#  Con `restart: unless-stopped`, un reboot del host hace RESUCITAR todo lo
#  pausado (el 22-sep recreo el stack completo asi). Este script pone
#  `--restart=no` antes de parar (pausa duradera) y lo restaura al prender,
#  arrancando en orden de dependencias y midiendo la RAM liberada.
#
# Uso:
#   ./10_pausar_levantar_secundarios.sh parar   postiz
#   ./10_pausar_levantar_secundarios.sh parar   pgadmin
#   ./10_pausar_levantar_secundarios.sh parar   todos [--inclui-leads]
#   ./10_pausar_levantar_secundarios.sh prender postiz|pgadmin|todos [--inclui-leads]
#   ./10_pausar_levantar_secundarios.sh estado
#
# Autor: Configuracion personalizada (SPEC 69)
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

# --- Grupos de contenedores ---
POSTIZ_CONTAINERS="postiz temporal temporal-elasticsearch temporal-ui"
PGADMIN_CONTAINERS="pgadmin-container"
LEADS_CONTAINERS="odoo-19-web-leads odoo-db19-leads"

# Orden al prender (dependencias primero) y al parar (dependientes primero)
POSTIZ_ORDER_UP="temporal-elasticsearch temporal postiz temporal-ui"
POSTIZ_ORDER_DOWN="postiz temporal-ui temporal temporal-elasticsearch"
LEADS_ORDER_UP="odoo-db19-leads odoo-19-web-leads"
LEADS_ORDER_DOWN="odoo-19-web-leads odoo-db19-leads"

# Camino del chatbot: NUNCA se toca, aborta si aparece en el objetivo
FORBIDDEN="chatwoot-app chatwoot-sidekiq chatwoot-db n8n-container odoo-19-web odoo-db19-n8n odoo_redis"

usage() { print_error "Uso: $0 {parar|prender|estado} [postiz|pgadmin|todos] [--inclui-leads]"; exit 1; }

is_running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

container_exists() { docker inspect "$1" >/dev/null 2>&1; }

memory_mb_used() { free -m | awk '/^Mem:/{print $3}'; }

guard_forbidden() {
    for c in "$@"; do
        case " $FORBIDDEN " in
            *" $c "*) print_error "El contenedor '$c' es del camino del chatbot. Aborto sin tocar nada."; exit 1;;
        esac
    done
}

group_containers() {
    case "$1" in
        postiz)  echo "$POSTIZ_CONTAINERS";;
        pgadmin) echo "$PGADMIN_CONTAINERS";;
        todos)   echo "$POSTIZ_CONTAINERS $PGADMIN_CONTAINERS";;
        *)       usage;;
    esac
}

# Orden correcto de parada para los grupos pedidos
stop_order() {
    case "$1" in
        postiz) echo "$POSTIZ_ORDER_DOWN";;
        pgadmin) echo "$PGADMIN_CONTAINERS";;
        todos)  echo "$POSTIZ_ORDER_DOWN $PGADMIN_CONTAINERS";;
    esac
}

# Orden correcto de arranque para los grupos pedidos
start_order() {
    case "$1" in
        postiz) echo "$POSTIZ_ORDER_UP";;
        pgadmin) echo "$PGADMIN_CONTAINERS";;
        todos)  echo "$POSTIZ_ORDER_UP $PGADMIN_CONTAINERS";;
    esac
}

parar() {
    local targets; targets=$(stop_order "$1")
    [ "${INCLUDE_LEADS:-0}" = "1" ] && targets="$targets $LEADS_ORDER_DOWN"
    guard_forbidden $targets

    local before; before=$(memory_mb_used)
    for c in $targets; do
        if ! container_exists "$c"; then
            print_warning "No existe el contenedor: $c (lo salto)"
            continue
        fi
        if is_running "$c"; then
            docker update --restart=no "$c" >/dev/null
            docker stop "$c" >/dev/null
            print_message "Pausado: $c (restart=no, no resucitara tras reboot)"
        else
            print_message "Ya estaba pausado: $c"
        fi
    done
    print_message "RAM usada antes: ${before} MB -> ahora: $(memory_mb_used) MB"
}

prender() {
    local targets; targets=$(start_order "$1")
    [ "${INCLUDE_LEADS:-0}" = "1" ] && targets="$targets $LEADS_ORDER_UP"
    guard_forbidden $targets

    for c in $targets; do
        if ! container_exists "$c"; then
            print_warning "No existe el contenedor: $c (lo salto)"
            continue
        fi
        docker update --restart=unless-stopped "$c" >/dev/null
        if is_running "$c"; then
            print_message "Ya estaba corriendo: $c"
        else
            docker start "$c" >/dev/null
            print_message "Levantado: $c"
        fi
    done
    print_warning "Si alguien ejecuta 'docker compose up -d' del stack principal, estos servicios se recrean igual."
}

estado() {
    printf "%-30s %-12s %-16s\n" "CONTENEDOR" "ESTADO" "RESTART"
    for c in $POSTIZ_CONTAINERS $PGADMIN_CONTAINERS $LEADS_CONTAINERS; do
        if ! container_exists "$c"; then
            printf "%-30s %-12s\n" "$c" "no-existe"
            continue
        fi
        local line; line=$(docker inspect "$c" --format '{{.State.Status}} {{.HostConfig.RestartPolicy.Name}}')
        printf "%-30s %-12s %-16s\n" "$c" $line
    done
    echo
    uptime
    free -h | head -2
}

ACTION="${1:-}"; GROUP="${2:-}"; [ "${3:-}" = "--inclui-leads" ] && INCLUDE_LEADS=1
case "$ACTION" in
    parar)   [ -n "$GROUP" ] || usage; print_header "Pausando servicios ($GROUP)"; parar "$GROUP";;
    prender) [ -n "$GROUP" ] || usage; print_header "Levantando servicios ($GROUP)"; prender "$GROUP";;
    estado)  print_header "Estado de servicios secundarios"; estado;;
    *)       usage;;
esac
