#!/bin/bash
# 6_6_monitor_cliente_testusuario.sh
# Vigila la entrega de correos de la orden S00001 / partner testUsuario (saymon_set@hotmail.com)
# en Odoo (dbodoo19) y avisa por email si hay envíos en estado exception/canceled.
# Sin estados persistentes de incidente, alerta máx. 1 vez cada 6h.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
ENV_FILE="$PROJECT_DIR/.env"
STATE_FILE="$PROJECT_DIR/v19/monitor_cliente_testusuario.state"
LOG_FILE="$PROJECT_DIR/v19/monitor_cliente_testusuario.log"
DB_CONTAINER="odoo-db19-n8n"
ALERT_EVERY_S=21600

PARTNER_ID=6
PARTNER_NAME="testUsuario"
PARTNER_EMAIL="saymon_set@hotmail.com"
ORDER_NAME="S00001"
LOOKBACK_HOURS=24

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
    if { { printf "From: Monitor Cliente <$from>\n"
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

if ! docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null | grep -q running; then
    warn "Contenedor $DB_CONTAINER no está corriendo; monitor inactivo"
    exit 0
fi

SQL="SELECT n.notification_status, COUNT(*)
FROM mail_notification n
JOIN mail_message_res_partner_rel r ON r.mail_message_id = n.mail_message_id
JOIN mail_message m ON m.id = n.mail_message_id
WHERE r.res_partner_id = $PARTNER_ID
  AND n.notification_type = 'email'
  AND m.date >= NOW() - INTERVAL '$LOOKBACK_HOURS hours'
GROUP BY n.notification_status;"

STATUSES=$(docker exec "$DB_CONTAINER" psql -U odoo -d dbodoo19 -t -A -c "$SQL" 2>/dev/null)
SENT=$(echo "$STATUSES" | awk -F'|' '$1=="sent"{print $2}')
FAILED=$(echo "$STATUSES" | awk -F'|' '$1=="exception" || $1=="canceled"{print $2}')

log "Cliente: $PARTNER_NAME ($PARTNER_EMAIL) | Orden: $ORDER_NAME | últimos ${LOOKBACK_HOURS}h | sent=${SENT:-0} fallidos=${FAILED:-0}"
[ -n "$STATUSES" ] && echo "$STATUSES" | while IFS='|' read -r st cnt; do log "   - $st: $cnt"; done

if [ -z "${FAILED:-}" ] || [ "$FAILED" -eq 0 ]; then
    log "OK: sin envíos fallidos"
    exit 0
fi

NOW=$(date +%s)
LAST_ALERT=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
if [ $((NOW - LAST_ALERT)) -lt $ALERT_EVERY_S ]; then
    warn "Incidente en curso (última alerta hace $(( (NOW - LAST_ALERT) / 60 ))min), email suprimido: $FAILED envío(s) fallido(s)"
    exit 0
fi

DETAIL=$(docker exec "$DB_CONTAINER" psql -U odoo -d dbodoo19 -t -A -c "
SELECT m.subject || ' | ' || n.notification_status || ' | ' || COALESCE(n.failure_type,'') || ' | ' || COALESCE(n.failure_reason,'') || ' | ' || m.date
FROM mail_notification n
JOIN mail_message_res_partner_rel r ON r.mail_message_id = n.mail_message_id
JOIN mail_message m ON m.id = n.mail_message_id
WHERE r.res_partner_id = $PARTNER_ID
  AND n.notification_type = 'email'
  AND n.notification_status IN ('exception','canceled')
  AND m.date >= NOW() - INTERVAL '$LOOKBACK_HOURS hours'
ORDER BY m.date DESC;" 2>/dev/null)

alert "Se detectaron $FAILED envío(s) fallido(s) de correo para $PARTNER_NAME:"
printf '%s\n' "$DETAIL"
echo "$NOW" > "$STATE_FILE"

BODY="=== Monitor Cliente - $(date '+%Y-%m-%d %H:%M:%S') ===
Cliente: $PARTNER_NAME ($PARTNER_EMAIL)
Orden: $ORDER_NAME (partner_id=$PARTNER_ID)
Ventana: últimas $LOOKBACK_HOURS horas

Envíos fallidos: $FAILED

Detalle:
$DETAIL

Posibles causas:
- Timeout SMTP (mail.privateemail.com:465): revisar conectividad
- Remitente no configurado (mail.default.from / mail.catchall.domain)
- Dominio en lista negra / SPF-DKIM-DMARC: verificar DNS de integraia.lat

Para revisar: docker exec odoo-db19-n8n psql -U odoo -d dbodoo19"
send_email "⚠️ ALERTA correo cliente $PARTNER_NAME - envíos fallidos" "$BODY" || true
