#!/bin/bash
# 6_5_monitor_bd_salud.sh
# Vigila la salud de PostgreSQL (odoo-db19-n8n) y avisa por email ante fallos.
# Detecta el síntoma del incidente de shm: FATAL "could not open shared memory segment".
# Sin estados persistentes de incidente, evita email-spam: alerta máx. 1 vez cada 6h.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
ENV_FILE="$PROJECT_DIR/.env"
STATE_FILE="$PROJECT_DIR/v19/monitor_bd.state"
LOG_FILE="$PROJECT_DIR/v19/monitor_bd.log"
CONTAINER="odoo-db19-n8n"
ALERT_EVERY_S=21600

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
alert() { echo -e "${RED}[ALERTA]${NC} $1" | tee -a "$LOG_FILE"; }

if [ -f "$ENV_FILE" ]; then
    set -a
    . "$ENV_FILE"
    set +a
fi

NOTIFY_TO="${MONITOR_NOTIFY_TO:-${BACKUP_NOTIFY_TO:-admin@integraia.lat}}"

mkdir -p "$PROJECT_DIR/v19"

send_email() {
    local subject="$1"
    local body="$2"
    if ! command -v curl >/dev/null 2>&1 || [ -z "${SMTP_HOST:-}" ]; then
        warn "   curl/SMTP no disponible; no se envió notificación"
        return 1
    fi
    local from="${SMTP_FROM:-admin@integraia.lat}"
    if { { printf "From: Monitor BD <$from>\n"
           printf "To: %s\n" "$NOTIFY_TO"
           printf "Subject: %s\n" "$subject"
           printf "MIME-Version: 1.0\n"
           printf "Content-Type: text/plain; charset=UTF-8\n\n"
           printf "%b" "$body"
         } | curl --silent --show-error --ssl-reqd \
            --url "smtps://${SMTP_HOST}:${SMTP_PORT:-465}" \
            --user "${SMTP_USER}:${SMTP_PASSWORD}" \
            --mail-from "$from" \
            --mail-rcpt "$NOTIFY_TO" \
            --upload-file - >/dev/null 2>&1; }; then
        log "   Email enviado a $NOTIFY_TO"
        return 0
    fi
    warn "   No se pudo enviar el email de notificación"
    return 1
}

STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null)
FATALS=$(docker logs --since 1h "$CONTAINER" 2>/dev/null | grep -c "FATAL")
PGRES=$(docker exec "$CONTAINER" pg_isready -U odoo -d dbodoo19 >/dev/null 2>&1 && echo "OK" || echo "FALLO")

PROBLEMS=""
[ "$STATUS" != "running" ] && PROBLEMS="$PROBLEMS\n- Contenedor $CONTAINER NO está running (estado: $STATUS)"
[ "$HEALTH" != "healthy" ] && [ "$HEALTH" != "none" ] && PROBLEMS="$PROBLEMS\n- Healthcheck de $CONTAINER: $HEALTH"
[ "${FATALS:-0}" -gt 0 ] && PROBLEMS="$PROBLEMS\n- $FATALS error(es) FATAL en logs de postgres en la última hora (posible incidente de shared memory)"
[ "$PGRES" != "OK" ] && PROBLEMS="$PROBLEMS\n- pg_isready falla: postgres no acepta conexiones"

if [ -z "$PROBLEMS" ]; then
    log "OK: estado=$STATUS health=$HEALTH fatals_1h=$FATALS pg_isready=$PGRES"
    exit 0
fi

NOW=$(date +%s)
LAST_ALERT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if [ $((NOW - LAST_ALERT)) -lt $ALERT_EVERY_S ]; then
    warn "Incidente en curso (última alerta hace $(( (NOW - LAST_ALERT) / 60 ))min), email suprimido:"
    printf '%b\n' "$PROBLEMS"
    exit 0
fi

alert "Problemas detectados en $CONTAINER:"
printf '%b\n' "$PROBLEMS"
echo "$NOW" > "$STATE_FILE"

BODY="=== Monitor BD - $(date '+%Y-%m-%d %H:%M:%S') ===
Servicio: $CONTAINER
Problemas:
$(printf '%b' "$PROBLEMS")

Detalle:
- Estado contenedor: $STATUS
- Healthcheck: $HEALTH
- FATAL en logs (última hora): $FATALS
- pg_isready: $PGRES

Logs recientes:
$(docker logs --tail 20 "$CONTAINER" 2>/dev/null | grep -vE "checkpoint|backup starting")

Para revisar: docker logs -f $CONTAINER"
send_email "⚠️ ALERTA BD $CONTAINER - problemas detectados" "$BODY" || true