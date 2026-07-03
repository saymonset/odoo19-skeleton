#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_header() { echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; }

print_header "⚠️  RECREAR BASE DE DATOS DESDE CERO"

echo ""
echo -e "${YELLOW}¡ATENCIÓN! Esto va a:${NC}"
echo "  1. Detener los servicios (db-leads, web-leads)"
echo "  2. BORRAR toda la base de datos PostgreSQL (dbodoo19)"
echo "  3. Recrear la base de datos desde cero"
echo "  4. Iniciar los servicios de nuevo"
echo ""
read -p "¿Estás seguro? Escribí 'yes' para continuar: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_warning "Operación cancelada."
    exit 0
fi

# Paso 1: Detener servicios
print_header "Paso 1: Deteniendo servicios"
docker compose -f docker-compose.yaml down
print_message "✓ Servicios detenidos"

# Paso 2: Borrar datos de PostgreSQL
print_header "Paso 2: Borrando datos de la base de datos"
DB_PATH="./v19-leads/pgdata/data"
if [ -d "$DB_PATH" ]; then
    print_warning "Borrando $DB_PATH ..."
    sudo rm -rf "$DB_PATH"
    print_message "✓ Datos eliminados"
else
    print_warning "El directorio $DB_PATH no existe, no hay nada que borrar."
fi

# Paso 3: Iniciar servicios
print_header "Paso 3: Iniciando servicios"
docker compose -f docker-compose.yaml up -d
print_message "✓ Servicios iniciados. PostgreSQL creará la BD desde cero."

# Paso 4: Esperar a que PostgreSQL esté listo
print_header "Paso 4: Esperando a que PostgreSQL esté saludable..."
sleep 5
if docker compose -f docker-compose.yaml exec db-leads pg_isready -U odoo -d dbodoo19 2>/dev/null; then
    print_message "✅ PostgreSQL está listo con la base de datos dbodoo19 recién creada"
else
    print_warning "Esperando más tiempo..."
    sleep 10
    docker compose -f docker-compose.yaml exec db-leads pg_isready -U odoo -d dbodoo19 && \
        print_message "✅ PostgreSQL listo" || \
        print_error "PostgreSQL no responde. Revisá los logs con: docker compose logs db-leads"
fi

print_header "✅ BASE DE DATOS RECREADA"
echo ""
echo "Comandos útiles:"
echo "  docker compose logs db-leads  - Ver logs de PostgreSQL"
echo "  docker compose ps             - Ver estado de servicios"
echo "  ./4_start-all.sh              - Iniciar servicios si es necesario"
echo ""
