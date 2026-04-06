#!/bin/bash
set -e

echo "=== Iniciando Entrypoint de Odoo ==="

CONFIG_FILE="/etc/odoo/odoo.conf"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${POSTGRES_USER:-odoo}"
DB_NAME="${POSTGRES_DB:-dbodoo19}"

if [ -f "/run/secrets/postgres_password" ]; then
    DB_PASSWORD=$(cat /run/secrets/postgres_password)
else
    echo "ERROR: No se encontró el archivo de contraseña"
    exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

wait_for_postgres() {
    echo "Esperando a PostgreSQL en $DB_HOST:$DB_PORT..."
    until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
        sleep 5
    done
    echo "PostgreSQL está listo!"
}

database_exists() {
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"
}

wait_for_postgres

if ! database_exists; then
    echo "ERROR: La base de datos '$DB_NAME' no existe."
    exit 1
fi

# Buscar el binario de Odoo
if [ -f "/opt/odoo/odoo-core/odoo-bin" ]; then
    ODOO_BIN="/opt/odoo/odoo-core/odoo-bin"
else
    echo "ERROR: No se encontró odoo-bin"
    exit 1
fi

echo "Iniciando Odoo con: $ODOO_BIN"
exec $ODOO_BIN -c "$CONFIG_FILE" "$@"