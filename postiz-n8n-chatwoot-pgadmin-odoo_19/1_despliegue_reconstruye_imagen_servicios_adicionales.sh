#!/bin/bash

# Script para despliegue de Odoo 19 - LEADS
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

# 1. Construcción de la Imagen Personalizada
print_header "Paso 1: Construcción de la imagen personalizada Odoo 19"

print_message "Eliminando imagen anterior..."
docker image rm odoo-pers:19 2>/dev/null || true

if [ ! -f Dockerfile ]; then
    print_error "No se encuentra el Dockerfile para construir la imagen odoo-pers:19"
    exit 1
fi
print_message "Construyendo nueva imagen odoo-pers:19..."
docker build --no-cache -t odoo-pers:19 .

# 2. Configuración del archivo .env
print_header "Paso 2: Configuración del archivo .env"

if [ ! -f .env ]; then
    print_warning "No se encontró .env. Creando archivo..."
    cat > .env << 'EOF'
VERSION=19
POSTGRES_DB=dbodoo19
POSTGRES_USER=odoo
POSTGRES_PASSWORD=0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491
EOF
fi

source .env
print_message "Variables cargadas. VERSION=$VERSION"

# 3. Creación de la red en Docker
print_header "Paso 3: Creación de la red Docker"

if docker network ls | grep -q "odoo_network_${VERSION}"; then
    print_message "✓ Red odoo_network_${VERSION} ya existe"
else
    docker network create odoo_network_${VERSION}
    print_message "✓ Red odoo_network_${VERSION} creada"
fi

# 4. Detener y eliminar todo (limpieza total)
print_header "Paso 4: Limpieza total de contenedores"
docker compose -f docker-compose.yaml down -v 2>/dev/null || true
docker stop odoo-db19-leads odoo-19-web-leads 2>/dev/null || true
docker rm odoo-db19-leads odoo-19-web-leads 2>/dev/null || true

# 5. Verificar archivos de secretos
print_header "Paso 5: Verificando archivos de secretos"

mkdir -p secrets

if [ ! -f secrets/postgres_password.txt ]; then
    echo "0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491" > secrets/postgres_password.txt
    chmod 600 secrets/postgres_password.txt
fi

print_message "✓ Secretos verificados"

# 6. Iniciar todos los servicios (DB y Odoo)
print_header "Paso 6: Iniciando todos los servicios"

docker compose -f docker-compose.yaml up -d
print_message "✓ Todos los servicios iniciados"

# Esperar a que el contenedor de Odoo esté realmente corriendo
print_message "Esperando estabilidad del contenedor Odoo..."
sleep 15

# Instalar openai dentro del contenedor
print_header "Paso 6.1: Instalando librería openai en el contenedor"
docker exec --user root odoo-19-web-leads bash -c "apt update -qq && apt install -y -qq python3-pip && pip3 install -q openai" || {
    print_warning "Falló la instalación automática de openai. Intentando nuevamente..."
    docker exec --user root odoo-19-web-leads bash -c "pip3 install openai"
}
print_message "✓ Librería openai instalada correctamente"

# Corregir permisos del directorio de sesiones de Odoo
print_header "Paso 6.5: Corrigiendo permisos del directorio de sesiones de Odoo"

docker exec --user root odoo-19-web-leads bash -c "mkdir -p /var/lib/odoo/.local/share/Odoo/sessions && chown -R odoo:odoo /var/lib/odoo/.local/share/Odoo && chmod -R 755 /var/lib/odoo/.local/share/Odoo && chmod 700 /var/lib/odoo/.local/share/Odoo/sessions"
if docker exec odoo-19-web-leads ls -la /var/lib/odoo/.local/share/Odoo/ 2>/dev/null; then
    print_message "✓ Directorio de sesiones de Odoo verificado"
else
    print_warning "⚠ No se pudo verificar el directorio de sesiones"
fi

print_message "✓ Permisos de Odoo corregidos"

# 7. Esperar a que PostgreSQL esté realmente listo
print_header "Paso 7: Esperando a PostgreSQL"

sleep 5
MAX_RETRIES=20
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec odoo-db19-leads pg_isready -U odoo 2>/dev/null; then
        print_message "✓ PostgreSQL está listo"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Esperando PostgreSQL... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 3
done

# 8. Crear base de datos dbodoo19 si no existe
print_header "Paso 8: Verificando base de datos dbodoo19"

print_message "Creando base de datos dbodoo19..."
docker exec odoo-db19-leads psql -U odoo -d postgres -c "CREATE DATABASE dbodoo19 OWNER odoo;" 2>/dev/null && echo "   ✅ Base dbodoo19 creada" || echo "   ⚠️ Base dbodoo19 ya existe"

# 9. Verificar e inicializar Odoo
print_header "Paso 9: Verificando Odoo"

sleep 30
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:28069 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    print_message "✓ Odoo responde correctamente (HTTP $HTTP_CODE)"
else
    print_warning "⚠ Odoo aún no responde (HTTP $HTTP_CODE). Revisando logs..."
    docker logs odoo-19-web-leads --tail 30
fi

# Configurar swap de 16G (solo si no existe)
if [ ! -f /swapfile ]; then
    print_message "Creando archivo swap de 16G..."
    if ! sudo fallocate -l 16G /swapfile 2>/dev/null; then
        sudo dd if=/dev/zero of=/swapfile bs=1M count=16384 status=progress
    fi
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    print_message "Swap activado correctamente"
else
    print_warning "El archivo /swapfile ya existe. No se modificó el swap."
fi

CURRENT_SWAPPINESS=$(sysctl -n vm.swappiness)
if [ "$CURRENT_SWAPPINESS" -gt 10 ]; then
    sudo sysctl vm.swappiness=10
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
    print_message "Swappiness reducido de $CURRENT_SWAPPINESS a 10"
fi

# 10. Resumen final
print_header "🎉 DESPLIEGUE COMPLETADO"

echo ""
echo "=== SERVICIOS DESPLEGADOS ==="
echo "🌐 Odoo 19 Leads: http://localhost:28069"
echo "📊 PostgreSQL:    localhost:5435 (user: odoo, db: dbodoo19)"
echo "🗄️  Base creada:   dbodoo19"
echo "🤖 Librería openai instalada en el contenedor de Odoo"
echo ""
echo "=== VER LOGS ==="
echo "docker logs -f odoo-19-web-leads"
echo ""
print_message "¡Odoo 19 Leads está listo! Accede a http://localhost:28069"
