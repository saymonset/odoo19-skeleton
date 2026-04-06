#!/bin/bash

# Script completo para despliegue de Odoo 19 con servicios adicionales
# Autor: Configuración personalizada
# Fecha: $(date +%Y-%m-%d)

set -e  # Detener el script si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 1. Construcción de la Imagen Personalizada
print_message "Paso 1: Construcción de la imagen personalizada Odoo 19"

# Eliminar recursos anteriores (opcional)
print_message "Eliminando recursos anteriores..."
docker rm -f odoo-pers-19 2>/dev/null || true
docker image rm odoo-pers:19 2>/dev/null || true

# Construir nueva imagen
print_message "Construyendo nueva imagen odoo-pers:19..."
docker build -t odoo-pers:19 .

# 2. Configuración del archivo .env
print_message "Paso 2: Configuración del archivo .env"

# Copiar el archivo env-example a .env si no existe
if [ ! -f .env ]; then
    if [ -f env-example ]; then
        cp env-example .env
        print_message "Archivo .env creado desde env-example"
    else
        print_warning "No se encontró archivo env-example. Creando .env básico..."
        cat > .env << EOF
VERSION=19
POSTGRES_DB=dbodoo19
POSTGRES_USER=odoo
POSTGRES_PASSWORD=odoo_password_secure
REDIS_PASSWORD=redis123
EOF
        print_message "Archivo .env básico creado"
    fi
else
    print_message "Archivo .env ya existe"
fi

# Cargar variables de entorno
source .env 2>/dev/null || VERSION="19"
print_message "Variables de entorno cargadas. VERSION=$VERSION"

# 3. Creación de la red en Docker
print_message "Paso 3: Creación de la red Docker"

# Crear red con nombre específico por versión (USANDO GUIÓN BAJO)
docker network create odoo_network_${VERSION} 2>/dev/null && print_message "Red odoo_network_${VERSION} creada" || print_message "Red odoo_network_${VERSION} ya existe"

# Verificar red creada
print_message "Redes Docker disponibles:"
docker network ls | grep odoo_network

# 4. Detener servicios existentes
print_message "Paso 4: Deteniendo servicios existentes"
docker-compose down 2>/dev/null || print_message "No hay servicios corriendo con docker-compose"

# 5. Verificar archivos de secretos
print_message "Paso 5: Verificando archivos de secretos"

# Crear directorio de secretos si no existe
mkdir -p secrets

# Verificar/crear archivo de contraseña de PostgreSQL
if [ ! -f secrets/postgres_password.txt ]; then
    print_warning "No se encontró secrets/postgres_password.txt. Creando archivo..."
    echo "${POSTGRES_PASSWORD:-odoo_password_secure}" > secrets/postgres_password.txt
    chmod 600 secrets/postgres_password.txt
    print_message "Archivo secrets/postgres_password.txt creado"
fi

# Verificar/crear archivo de contraseña de Redis
if [ ! -f secrets/redis_password.txt ]; then
    print_warning "No se encontró secrets/redis_password.txt. Creando archivo..."
    echo "${REDIS_PASSWORD:-redis123}" > secrets/redis_password.txt
    chmod 600 secrets/redis_password.txt
    print_message "Archivo secrets/redis_password.txt creado"
fi

# 6. Iniciar servicios en orden
print_message "Paso 6: Iniciando servicios Docker Compose"

# Iniciar Odoo stack
if [ -f docker-compose.odoo.yml ]; then
    print_message "Iniciando Odoo stack con docker-compose.odoo.yml..."
    docker compose -f docker-compose.odoo.yml up -d
else
    print_error "No se encontró el archivo docker-compose.odoo.yml"
    exit 1
fi

# Esperar a que PostgreSQL esté listo
print_message "Esperando a que PostgreSQL esté listo (máximo 60 segundos)..."
MAX_RETRIES=12
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec odoo-db19-n8n pg_isready -U odoo -d dbodoo19 2>/dev/null; then
        print_message "PostgreSQL está listo!"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Esperando... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    print_error "Timeout esperando a PostgreSQL"
    exit 1
fi

# 7. Crear bases de datos adicionales
print_message "Paso 7: Creando bases de datos adicionales (postiz, temporal)"

# Función para crear base de datos si no existe
create_database_if_not_exists() {
    local db_name=$1
    local exists=$(docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'")
    
    if [ -z "$exists" ]; then
        print_message "Creando base de datos: $db_name"
        docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -c "CREATE DATABASE $db_name;"
        print_message "Base de datos $db_name creada exitosamente"
    else
        print_message "La base de datos $db_name ya existe"
    fi
}

# Crear bases de datos necesarias
create_database_if_not_exists "postiz"
create_database_if_not_exists "temporal"
create_database_if_not_exists "db_n8n"

# Verificar bases de datos creadas
print_message "Bases de datos existentes:"
docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -c "\l"

# 8. Verificar estado de los servicios
print_message "Paso 8: Verificando estado de los servicios"

echo ""
print_message "=== Estado de los contenedores ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "odoo|db|redis"

echo ""
print_message "=== Verificación específica de servicios ==="

# Verificar Redis
if docker exec odoo_redis redis-cli -a redis123 ping 2>/dev/null | grep -q "PONG"; then
    print_message "✓ Redis está funcionando correctamente"
else
    print_error "✗ Redis no responde"
fi

# Verificar Odoo
if curl -s http://localhost:19069/web/database/selector > /dev/null 2>&1; then
    print_message "✓ Odoo está accesible en el puerto 19069"
else
    print_warning "✗ Odoo puede que aún esté iniciando (espera unos segundos)"
fi

# Verificar PostgreSQL
if docker exec odoo-db19-n8n pg_isready -U odoo -d dbodoo19 > /dev/null 2>&1; then
    print_message "✓ PostgreSQL está funcionando correctamente"
else
    print_error "✗ PostgreSQL no está funcionando correctamente"
fi

echo ""
print_message "=== Resumen del despliegue ==="
print_message "✓ Imagen Odoo personalizada construida"
print_message "✓ Red Docker creada: odoo_network_${VERSION}"
print_message "✓ Servicios iniciados: PostgreSQL, Redis, Odoo"
print_message "✓ Bases de datos adicionales creadas: postiz, temporal"
echo ""
print_message "=== Acceso a los servicios ==="
echo "Odoo Web: http://localhost:19069"
echo "Redis: localhost:6379 (password: redis123)"
echo "PostgreSQL: localhost:5432 (database: dbodoo19, user: odoo)"
echo ""
print_message "=== Comandos útiles ==="
echo "Ver logs: docker compose -f docker-compose.odoo.yml logs -f"
echo "Detener servicios: docker compose -f docker-compose.odoo.yml down"
echo "Acceder a PostgreSQL: docker exec -it odoo-db19-n8n psql -U odoo -d dbodoo19"
echo "Acceder a Odoo shell: docker exec -it odoo-19-web bash"
echo ""
print_message "¡Despliegue completado exitosamente!"