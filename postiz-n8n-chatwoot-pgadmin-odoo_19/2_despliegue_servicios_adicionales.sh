#!/bin/bash

# Script para desplegar servicios adicionales (n8n, pgAdmin, Chatwoot)
# Autor: Configuración personalizada
# Fecha: $(date +%Y-%m-%d)

set -e  # Detener el script si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

# Verificar que la red existe
print_header "Verificando red Docker"
if docker network ls | grep -q "odoo_network_19"; then
    print_message "✓ Red odoo_network_19 existe"
else
    print_warning "Red odoo_network_19 no existe, creándola..."
    docker network create odoo_network_19
    print_message "✓ Red odoo_network_19 creada"
fi

# Verificar archivos de secretos necesarios
print_header "Verificando archivos de secretos"
mkdir -p secrets

# Secretos para n8n
if [ ! -f secrets/n8n_password.txt ]; then
    print_warning "Creando secrets/n8n_password.txt..."
    echo "n8n_password_$(openssl rand -hex 8)" > secrets/n8n_password.txt
    chmod 600 secrets/n8n_password.txt
fi

if [ ! -f secrets/n8n_encryption_key.txt ]; then
    print_warning "Creando secrets/n8n_encryption_key.txt..."
    openssl rand -base64 32 > secrets/n8n_encryption_key.txt
    chmod 600 secrets/n8n_encryption_key.txt
fi

print_message "✓ Archivos de secretos verificados"

# 1. Desplegar n8n (USANDO DOCKER-COMPOSE.YAML PRINCIPAL)
print_header "Desplegando n8n"
if [ -f docker-compose.yaml ]; then
    print_message "Iniciando n8n desde docker-compose.yaml..."
    docker compose -f docker-compose.yaml up -d n8n
    print_message "✓ n8n desplegado correctamente"
    print_message "  Acceso: http://localhost:5678"
else
    print_error "No se encontró docker-compose.yaml"
    exit 1
fi

# Esperar que n8n esté listo
sleep 10

# 2. Desplegar pgAdmin
print_header "Desplegando pgAdmin"
if [ -f docker-compose.pgadmin.yml ]; then
    print_message "Iniciando pgAdmin..."
    docker compose -f docker-compose.pgadmin.yml up -d
    print_message "✓ pgAdmin desplegado correctamente"
    print_message "  Acceso: http://localhost:5050"
    print_message "  Email: admin@pgadmin.com"
    print_message "  Password: admin123"
else
    print_warning "No se encontró docker-compose.pgadmin.yml"
fi

# 3. Desplegar Chatwoot
print_header "Desplegando Chatwoot"
if [ -f docker-compose.chatwoot.yml ]; then
    print_message "Iniciando Chatwoot..."
    print_warning "Chatwoot puede tomar varios minutos en iniciar completamente..."
    docker compose -f docker-compose.chatwoot.yml up -d
    
    print_message "✓ Chatwoot desplegado correctamente"
    print_message "  Acceso: http://localhost:3000"
    print_message "  Credenciales por defecto: admin@chatwoot.com / Chatwoot123!"
else
    print_warning "No se encontró docker-compose.chatwoot.yml"
fi

# Verificar estado de los servicios
print_header "Verificando estado de los servicios"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "n8n|pgadmin|chatwoot|odoo|db|redis" || true

# Mostrar información de acceso
print_header "Información de acceso a servicios"

echo -e "${GREEN}=== Servicios Desplegados ===${NC}"
echo ""

if docker ps | grep -q "n8n"; then
    echo -e "${GREEN}✓ n8n:${NC} http://localhost:5678"
    echo "   Dashboard: http://localhost:5678"
    echo ""
fi

if docker ps | grep -q "pgadmin"; then
    echo -e "${GREEN}✓ pgAdmin:${NC} http://localhost:5050"
    echo "   Email: admin@pgadmin.com"
    echo "   Password: admin123"
    echo ""
fi

if docker ps | grep -q "chatwoot"; then
    echo -e "${GREEN}✓ Chatwoot:${NC} http://localhost:3000"
    echo "   Email: admin@chatwoot.com"
    echo "   Password: Chatwoot123!"
    echo ""
fi

if docker ps | grep -q "odoo-19-web"; then
    echo -e "${GREEN}✓ Odoo 19:${NC} http://localhost:18069"
    echo "   Master Password: admin"
    echo ""
fi

if docker ps | grep -q "odoo_redis"; then
    echo -e "${GREEN}✓ Redis:${NC} localhost:6379"
    echo "   Password: redis123"
    echo ""
fi

if docker ps | grep -q "odoo-db19-n8n"; then
    echo -e "${GREEN}✓ PostgreSQL:${NC} localhost:5432"
    echo "   Database: dbodoo19"
    echo "   User: odoo"
    echo ""
fi

# Verificar backup (opcional)
print_header "Verificar backups (opcional)"
echo "Para verificar backups de Odoo, ejecuta:"
echo "  docker exec -it odoo_backup ls /backup/daily 2>/dev/null || echo 'No backups yet'"
echo ""
echo "Para ver logs de servicios:"
echo "  docker compose -f docker-compose.yaml logs -f n8n"
echo "  docker compose -f docker-compose.chatwoot.yml logs -f"
echo "  docker compose -f docker-compose.pgadmin.yml logs -f"
echo ""

print_message "¡Despliegue de servicios adicionales completado!"