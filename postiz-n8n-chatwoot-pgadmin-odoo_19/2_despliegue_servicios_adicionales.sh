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
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_header() { echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"; }

# ============================================
# 0. LIMPIEZA Y RECREACIÓN DE RED (SOLUCIÓN)
# ============================================
print_header "Paso 0: Verificando y recreando red Docker"

if docker network ls | grep -q "odoo_network_19"; then
    print_message "✓ Red odoo_network_19 existe"
else
    print_warning "Red odoo_network_19 no existe, creándola..."
    docker network create odoo_network_19
    print_message "✓ Red odoo_network_19 creada"
fi

# ============================================
# 1. VERIFICAR Y CREAR ALIAS DE RED PARA REDIS
# ============================================
print_header "Paso 1: Configurando alias de red para Redis"

if docker ps | grep -q odoo_redis; then
    print_message "✓ Redis está corriendo"
    if docker network inspect odoo_network_19 | grep -q '"redis"'; then
        print_message "✓ Alias 'redis' ya existe en la red"
    else
        print_message "Agregando alias 'redis' a la red..."
        docker network connect --alias redis odoo_network_19 odoo_redis 2>/dev/null && \
            print_message "✓ Alias 'redis' agregado correctamente" || \
            print_warning "⚠ No se pudo agregar alias (puede que ya exista)"
    fi
else
    print_warning "Redis no está corriendo. Asegúrate de ejecutar 1_despliegue primero."
fi

# ============================================
# 2. VERIFICAR BASE DE DATOS DE N8N
# ============================================
print_header "Paso 2: Verificando base de datos de n8n"

if docker ps | grep -q odoo-db19-n8n; then
    print_message "✓ PostgreSQL está corriendo"
    if docker exec odoo-db19-n8n psql -U odoo -d postgres -c "\l" 2>/dev/null | grep -q db_n8n; then
        print_message "✓ Base de datos db_n8n ya existe"
    else
        print_message "Creando base de datos db_n8n..."
        docker exec odoo-db19-n8n psql -U odoo -d postgres -c "CREATE DATABASE db_n8n OWNER odoo;"
        print_message "✓ Base de datos db_n8n creada"
    fi
else
    print_error "PostgreSQL no está corriendo. Ejecuta primero 1_despliegue_reconstruye_imagen_servicios_adicionales.sh"
    exit 1
fi

# ============================================
# 3. VERIFICAR ARCHIVOS DE SECRETOS
# ============================================
print_header "Paso 3: Verificando archivos de secretos"
mkdir -p secrets

if [ ! -f secrets/n8n_password.txt ]; then
    print_warning "Creando secrets/n8n_password.txt..."
    echo "n8n_password_$(openssl rand -hex 8)" > secrets/n8n_password.txt
    chmod 600 secrets/n8n_password.txt
fi

if [ ! -f secrets/n8n_encryption_key.txt ]; then
    print_warning "Creando secrets/n8n_encryption_key.txt..."
    echo "874eca07f4fe0a551b4c004843c91dc0c4a41f520687baaf40b4c64218c322a06b105d4e4e920e8fc3e8b5d70ccf696e1841d71a8028975f379754962de73b98" > secrets/n8n_encryption_key.txt
    chmod 600 secrets/n8n_encryption_key.txt
fi
print_message "✓ Archivos de secretos verificados"

# ============================================
# 4. DETENER SERVICIOS ANTIGUOS (OPCIONAL)
# ============================================
print_header "Paso 4: Deteniendo servicios antiguos"
read -p "¿Deseas detener y recrear los servicios? (yes/no): " RECREATE

if [ "$RECREATE" = "yes" ]; then
    print_message "Deteniendo servicios existentes..."
    docker compose -f docker-compose.yaml down 2>/dev/null || true
    docker compose -f docker-compose.pgadmin.yml down 2>/dev/null || true
    docker compose -f docker-compose.chatwoot.yml down 2>/dev/null || true
    print_message "✓ Servicios detenidos"
fi

# ============================================
# 5. DESPLEGAR N8N
# ============================================
print_header "Paso 5: Desplegando n8n"
if [ -f docker-compose.yaml ]; then
    print_message "Iniciando n8n desde docker-compose.yaml..."
    docker compose -f docker-compose.yaml up -d n8n
    sleep 15
    if docker ps | grep -q n8n-container; then
        print_message "✓ n8n desplegado correctamente (http://localhost:5678)"
    else
        print_warning "⚠ n8n no está corriendo. Revisa logs."
    fi
else
    print_error "No se encontró docker-compose.yaml"
    exit 1
fi

# ============================================
# 6. DESPLEGAR PGADMIN
# ============================================
print_header "Paso 6: Desplegando pgAdmin"
if [ -f docker-compose.pgadmin.yml ]; then
    docker compose -f docker-compose.pgadmin.yml up -d
    print_message "✓ pgAdmin desplegado (http://localhost:8080 - oraclefedora@gmail.com / admin123)"
else
    print_warning "No se encontró docker-compose.pgadmin.yml"
fi

# ============================================
# 7. DESPLEGAR CHATWOOT + MIGRACIONES AUTOMÁTICAS
# ============================================
print_header "Paso 7: Desplegando Chatwoot y aplicando migraciones"

if [ -f docker-compose.chatwoot.yml ]; then
    print_message "Iniciando Chatwoot..."
    docker compose -f docker-compose.chatwoot.yml up -d
    
    print_message "Esperando a que Chatwoot esté listo..."
    MAX_RETRIES=30
    RETRY=0
    while [ $RETRY -lt $MAX_RETRIES ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|301\|302"; then
            print_message "✓ Chatwoot responde correctamente"
            break
        fi
        RETRY=$((RETRY+1))
        echo "Esperando... ($RETRY/$MAX_RETRIES)"
        sleep 5
    done
    
    # Verificar y ejecutar migraciones si falta la tabla
    print_message "Verificando estado de la base de datos de Chatwoot..."
    TABLE_EXISTS=$(docker exec chatwoot-db psql -U chatwoot -d chatwoot_production -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'installation_configs');" 2>/dev/null | tr -d ' ')
    
    if [ "$TABLE_EXISTS" = "f" ]; then
        print_message "Tabla 'installation_configs' no encontrada. Ejecutando migraciones..."
        docker exec chatwoot-app bundle exec rails db:migrate
        print_message "✓ Migraciones aplicadas correctamente"
    else
        print_message "✓ La base de datos ya está migrada"
    fi
    
    # Comprobación final
    if docker exec chatwoot-db psql -U chatwoot -d chatwoot_production -c "\dt" 2>/dev/null | grep -q installation_configs; then
        print_message "✅ Chatwoot completamente listo (migraciones OK)"
    else
        print_warning "⚠️ Chatwoot está corriendo pero podría faltar alguna migración. Revisa logs."
    fi
    
    print_message "✓ Chatwoot accesible en http://localhost:3000"
else
    print_warning "No se encontró docker-compose.chatwoot.yml"
fi

# ============================================
# 8. VERIFICAR CONEXIONES
# ============================================
print_header "Paso 8: Verificando conexiones"
if docker ps | grep -q n8n-container; then
    print_message "Verificando conexión de n8n a Redis..."
    sleep 5
    if docker logs n8n-container --tail=10 2>&1 | grep -q "Redis connection"; then
        print_message "✓ n8n conectado a Redis"
    else
        print_warning "⚠ Verifica logs de n8n para conexión a Redis"
    fi
fi

sudo sysctl vm.overcommit_memory=1
echo 'vm.overcommit_memory=1' | sudo tee -a /etc/sysctl.conf

# ============================================
# 9. VERIFICAR ESTADO FINAL
# ============================================
print_header "Paso 9: Verificando estado de los servicios"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "n8n|pgadmin|chatwoot|odoo|db|redis" || true

# ============================================
# 10. INFORMACIÓN DE ACCESO
# ============================================
print_header "Información de acceso a servicios"
echo -e "${GREEN}=== Servicios Desplegados ===${NC}"
docker ps | grep -q n8n-container && echo -e "${GREEN}✓ n8n:${NC} http://localhost:5678 (usuario: admin, pass: ver secrets/n8n_password.txt)"
docker ps | grep -q pgadmin-container && echo -e "${GREEN}✓ pgAdmin:${NC} http://localhost:8080 (oraclefedora@gmail.com / admin123)"
docker ps | grep -q chatwoot-app && echo -e "${GREEN}✓ Chatwoot:${NC} http://localhost:3000"
docker ps | grep -q odoo-19-web && echo -e "${GREEN}✓ Odoo 19:${NC} http://localhost:18069 (admin/admin)"
docker ps | grep -q odoo_redis && echo -e "${GREEN}✓ Redis:${NC} localhost:6379 (redis123)"
docker ps | grep -q odoo-db19-n8n && echo -e "${GREEN}✓ PostgreSQL:${NC} localhost:5432 (dbodoo19, user odoo)"

print_header "Comandos útiles"
echo "docker logs -f n8n-container"
echo "docker compose -f docker-compose.chatwoot.yml logs -f"
echo "docker compose -f docker-compose.yaml restart n8n"
echo "docker compose -f docker-compose.chatwoot.yml restart"

print_message "¡Despliegue de servicios adicionales completado!"