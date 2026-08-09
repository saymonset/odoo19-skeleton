#!/bin/bash
#
# BORRAR BD DE ODOO 19
# ---------------------------------------------
# Borra y recrea la base de datos dbodoo19 en el
# contenedor odoo-db19-n8n, para el usuario odoo.
# Antes de borrar hace un backup de seguridad.
#
# Uso:
#   ./borrar-bd-odoo19.sh          # normal (con backup previo)
#   ./borrar-bd-odoo19.sh --no-backup   # sin backup previo
#
set -euo pipefail

# Si algo falla a mitad, reactiva el contenedor web
trap 'docker start $WEB_CONTAINER >/dev/null 2>&1 || true' EXIT

# --- Configuración ---
DB_CONTAINER="odoo-db19-n8n"
WEB_CONTAINER="odoo-19-web"
DB_NAME="dbodoo19"
DB_USER="odoo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backup/out"
DO_BACKUP=true

for arg in "$@"; do
    case "$arg" in
        --no-backup) DO_BACKUP=false ;;
        *) echo "Opción desconocida: $arg" >&2; exit 1 ;;
    esac
done

echo "=========================================="
echo " BORRAR BD DE ODOO 19"
echo " Contenedor : $DB_CONTAINER"
echo " Base de datos: $DB_NAME"
echo " Usuario    : $DB_USER"
echo "=========================================="

# --- 1. Verificar contenedor ---
if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
    echo "ERROR: El contenedor $DB_CONTAINER no está corriendo." >&2
    exit 1
fi
echo "[1/6] Contenedor $DB_CONTAINER verificado."

# --- 2. Detener Odoo web ---
echo "[2/6] Deteniendo $WEB_CONTAINER..."
docker stop "$WEB_CONTAINER" >/dev/null || echo "  (aviso: $WEB_CONTAINER no estaba corriendo)"

# --- 3. Backup de seguridad ---
if $DO_BACKUP; then
    if [ ! -w "$BACKUP_DIR" ]; then
        BACKUP_DIR="$SCRIPT_DIR/backup/pre_reset"
        echo "  (aviso: backup/out no es escribible, usando $BACKUP_DIR)"
    fi
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_pre_reset_${TIMESTAMP}.dump"
    echo "[3/6] Haciendo backup de $DB_NAME -> $BACKUP_FILE"
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -Fc -d "$DB_NAME" > "$BACKUP_FILE"
    echo "  Backup listo ($(du -h "$BACKUP_FILE" | cut -f1))."
else
    echo "[3/6] Backup omitido (--no-backup)."
fi

# --- 4. Borrar la base ---
echo "[4/6] Borrando $DB_NAME..."
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME WITH (FORCE);"

# --- 5. Recrear la base ---
echo "[5/6] Recreando $DB_NAME (owner: $DB_USER)..."
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

# --- 6. Verificación ---
EXISTS="$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';")"
if [ "$EXISTS" != "1" ]; then
    echo "ERROR: $DB_NAME no se pudo recrear." >&2
    exit 1
fi
SIZE="$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));")"
echo "  Base recreada correctamente (tamaño: $SIZE)."

# --- Levantar Odoo web ---
echo "Levantando $WEB_CONTAINER..."
docker start "$WEB_CONTAINER" >/dev/null
echo "  $WEB_CONTAINER iniciado."

echo "=========================================="
echo " LISTO: la base $DB_NAME fue borrada y recreada."
echo " Odoo 19 reconstruirá sus tablas al arrancar."
if [ "$DO_BACKUP" = true ]; then
    echo " Backup previo en: $BACKUP_FILE"
    echo " Para restaurarlo: docker exec $DB_CONTAINER pg_restore -U $DB_USER -d $DB_NAME --clean --if-exists < $BACKUP_FILE"
fi
echo "=========================================="