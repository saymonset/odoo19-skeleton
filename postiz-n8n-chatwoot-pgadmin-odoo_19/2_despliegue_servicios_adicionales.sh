#!/bin/bash

# Script de verificación de servicios - Odoo 19 LEADS
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

# ============================================
# 1. VERIFICAR RED DOCKER
# ============================================
print_header "Paso 1: Verificando red Docker"

if docker network ls | grep -q "odoo_network_19"; then
    print_message "✓ Red odoo_network_19 existe"
else
    print_warning "Red odoo_network_19 no existe, créala con:"
    echo "  docker network create odoo_network_19"
fi

# ============================================
# 2. VERIFICAR CONTENEDORES
# ============================================
print_header "Paso 2: Verificando contenedores"

DB_RUNNING=false
WEB_RUNNING=false

if docker ps | grep -q odoo-db19-leads; then
    print_message "✓ PostgreSQL (odoo-db19-leads) está corriendo"
    DB_RUNNING=true
else
    print_warning "⚠ PostgreSQL (odoo-db19-leads) no está corriendo"
fi

if docker ps | grep -q odoo-19-web-leads; then
    print_message "✓ Odoo web (odoo-19-web-leads) está corriendo"
    WEB_RUNNING=true
else
    print_warning "⚠ Odoo web (odoo-19-web-leads) no está corriendo"
fi

# ============================================
# 3. VERIFICAR ESTADO DE SALUD
# ============================================
print_header "Paso 3: Verificando estado de salud"

if [ "$DB_RUNNING" = true ]; then
    if docker exec odoo-db19-leads pg_isready -U odoo 2>/dev/null; then
        print_message "✓ PostgreSQL responde correctamente"
    else
        print_error "✗ PostgreSQL no responde"
    fi
fi

if [ "$WEB_RUNNING" = true ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:28069 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
        print_message "✓ Odoo responde (HTTP $HTTP_CODE) en http://localhost:28069"
    else
        print_warning "⚠ Odoo no responde aún"
    fi
fi

# ============================================
# 4. RESUMEN DE SERVICIOS
# ============================================
print_header "Paso 4: Estado de los servicios"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "odoo-db19-leads|odoo-19-web-leads" || true

# ============================================
# 5. INFORMACIÓN DE ACCESO
# ============================================
print_header "Información de acceso"

echo -e "${GREEN}=== Servicios LEADS ===${NC}"
docker ps | grep -q odoo-19-web-leads && echo -e "${GREEN}✓ Odoo 19 Leads:${NC} http://localhost:28069 (admin/admin)"
docker ps | grep -q odoo-db19-leads && echo -e "${GREEN}✓ PostgreSQL:${NC}     localhost:5435 (user: odoo, db: dbodoo19)"

print_header "Comandos útiles"
echo "docker logs -f odoo-19-web-leads"
echo "docker compose -f docker-compose.yaml logs -f"
echo "docker compose -f docker-compose.yaml restart"

print_message "¡Verificación completada!"
