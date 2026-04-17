#!/bin/bash

echo "=== Instalación de Docker y configuración de permisos ==="
echo ""

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Actualizar sistema
print_message "[1/8] Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

# 2. Instalar dependencias
print_message "[2/8] Instalando dependencias..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common openssl

# 3. Agregar repositorio de Docker
print_message "[3/8] Agregando repositorio de Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Instalar Docker Engine
print_message "[4/8] Instalando Docker Engine..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Agregar usuario al grupo docker
print_message "[5/8] Agregando usuario al grupo docker..."
sudo usermod -aG docker $USER

# 6. Crear grupo odoogroup y agregar usuario
print_message "[6/8] Configurando grupo odoogroup..."
sudo groupadd -f odoogroup
sudo usermod -aG odoogroup $USER

# 7. Configurar directorios y permisos (LIMPIO DESDE CERO)
print_message "[7/8] Configurando directorios y permisos..."

# Detener contenedores si existen
print_message "Deteniendo contenedores existentes..."
docker compose -f docker-compose.odoo.yml down 2>/dev/null || true
docker compose -f docker-compose.n8n.yml down 2>/dev/null || true
docker compose -f docker-compose.chatwoot.yml down 2>/dev/null || true
docker compose -f docker-compose.pgadmin.yml down 2>/dev/null || true
docker compose -f docker-compose.postiz.yml down 2>/dev/null || true

# ============================================
# LIMPIEZA COMPLETA DE VOLÚMENES (OPCIONAL)
# ============================================
print_message "⚠️ ADVERTENCIA: Esto eliminará TODOS los datos existentes"
read -p "¿Deseas eliminar también los volúmenes? (yes/no): " CLEAN_VOLUMES

if [ "$CLEAN_VOLUMES" = "yes" ]; then
    print_message "Eliminando volúmenes..."
    docker compose down -v 2>/dev/null || true
    print_message "✓ Volúmenes eliminados"
fi

# LIMPIEZA TOTAL DE DIRECTORIOS ANTIGUOS
print_message "Limpiando directorios antiguos por completo..."
sudo rm -rf v19/ secrets/ backups/ dynamicconfig/
sudo rm -rf v19/chatwoot_logs v19/chatwoot_pgdata v19/chatwoot_tmp v19/chatwoot_storage
sudo rm -rf v19/logs v19/n8n_data v19/odoo_n8n_pgdata
sudo rm -rf v19/redis_data v19/temporal_elasticsearch_data
sudo rm -rf v19/pgdata v19/postiz_config v19/postiz_uploads
sudo rm -rf v19/odoo-web-data v19/data v19/addons
sudo rm -rf v19/pgadmin-data

# Crear directorios principales
print_message "Creando directorios con permisos correctos..."
mkdir -p v19

# Odoo (usuario 1001)
print_message "Configurando Odoo (UID 1001)..."
mkdir -p v19/logs v19/odoo-web-data v19/data/addons v19/data/filestore v19/odoo_n8n_pgdata
sudo chown -R 1001:1001 v19/logs v19/odoo-web-data v19/data v19/odoo_n8n_pgdata
chmod 755 v19/logs v19/odoo-web-data v19/data

# Redis (usuario 1001)
print_message "Configurando Redis (UID 1001)..."
mkdir -p v19/redis_data
sudo chown -R 1001:1001 v19/redis_data
chmod 755 v19/redis_data

# n8n (usuario 1000)
print_message "Configurando n8n (UID 1000)..."
mkdir -p v19/n8n_data
sudo chown -R 1000:1000 v19/n8n_data
chmod 755 v19/n8n_data

# Chatwoot (usuario 1000)
print_message "Configurando Chatwoot (UID 1000)..."
mkdir -p v19/chatwoot_storage v19/chatwoot_logs v19/chatwoot_tmp v19/chatwoot_pgdata
sudo chown -R 1000:1000 v19/chatwoot_storage v19/chatwoot_logs v19/chatwoot_tmp v19/chatwoot_pgdata
chmod 755 v19/chatwoot_storage v19/chatwoot_logs v19/chatwoot_tmp

# Postiz (usuario 1000)
print_message "Configurando Postiz (UID 1000)..."
mkdir -p v19/postiz_config v19/postiz_uploads
sudo chown -R 1000:1000 v19/postiz_config v19/postiz_uploads
chmod 755 v19/postiz_config v19/postiz_uploads

# Temporal/Elasticsearch (usuario 1000)
print_message "Configurando Temporal/Elasticsearch (UID 1000)..."
mkdir -p v19/temporal_elasticsearch_data
sudo chown -R 1000:1000 v19/temporal_elasticsearch_data
chmod 755 v19/temporal_elasticsearch_data

# ============================================
# LIMPIEZA ADICIONAL DE DATOS CORRUPTOS DE ELASTICSEARCH
# ============================================
print_message "Limpiando datos previos de Elasticsearch para evitar errores de lock..."
sudo rm -rf v19/temporal_elasticsearch_data/*
mkdir -p v19/temporal_elasticsearch_data
sudo chown -R 1000:1000 v19/temporal_elasticsearch_data
chmod 755 v19/temporal_elasticsearch_data
print_message "✓ Datos de Elasticsearch limpiados correctamente"

# ============================================
# Temporal dynamic config
# ============================================
print_message "Configurando dynamicconfig para Temporal..."
mkdir -p dynamicconfig

# Crear el archivo de configuración
cat > dynamicconfig/development-sql.yaml << 'EOF'
limit.maxIDLength:
  - value: 255
    constraints: {}
system.forceSearchAttributesCacheRefreshOnRead:
  - value: false
    constraints: {}
worker.buildIdScavengerEnabled:
  - value: true
    constraints: {}
EOF

# Verificar que el archivo no está vacío
if [ -s dynamicconfig/development-sql.yaml ]; then
    chmod 644 dynamicconfig/development-sql.yaml
    print_message "✓ Dynamic config de Temporal creado correctamente"
else
    print_error "❌ Error: El archivo dynamicconfig/development-sql.yaml está vacío"
    # Crear de nuevo con método alternativo
    echo "limit.maxIDLength:" > dynamicconfig/development-sql.yaml
    echo "  - value: 255" >> dynamicconfig/development-sql.yaml
    echo "    constraints: {}" >> dynamicconfig/development-sql.yaml
    echo "system.forceSearchAttributesCacheRefreshOnRead:" >> dynamicconfig/development-sql.yaml
    echo "  - value: false" >> dynamicconfig/development-sql.yaml
    echo "    constraints: {}" >> dynamicconfig/development-sql.yaml
    echo "worker.buildIdScavengerEnabled:" >> dynamicconfig/development-sql.yaml
    echo "  - value: true" >> dynamicconfig/development-sql.yaml
    echo "    constraints: {}" >> dynamicconfig/development-sql.yaml
    chmod 644 dynamicconfig/development-sql.yaml
    print_message "✓ Dynamic config creado con método alternativo"
fi

print_message "Contenido de dynamicconfig/development-sql.yaml:"
cat dynamicconfig/development-sql.yaml

# pgAdmin (usuario 5050)
print_message "Configurando pgAdmin (UID 5050)..."
mkdir -p v19/pgadmin-data
sudo chown -R 5050:5050 v19/pgadmin-data
chmod 755 v19/pgadmin-data

# Configuración Odoo (usuario actual)
print_message "Configurando archivos de configuración..."
mkdir -p v19/config
sudo chown -R $USER:$USER v19/config
chmod 755 v19/config

# CREAR ODOO.CONF ACTUALIZADO
print_message "Creando v19/config/odoo.conf (configuración optimizada)..."
cat > v19/config/odoo.conf << 'EOF'
[options]
addons_path = /opt/odoo/odoo-core/addons,/opt/odoo/custom-addons/extra,/opt/odoo/custom-addons/oca,/opt/odoo/custom-addons/enterprise
admin_passwd = admin
db_host = db
db_port = 5432
db_user = odoo
db_name = dbodoo19
db_password = 0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491
db_sslmode = prefer
db_template = template0
db_maxconn = 64
http_enable = True
http_interface = 0.0.0.0
http_port = 8069
gevent_port = 8072
proxy_mode = False
workers = 2
max_cron_threads = 1
limit_memory_hard = 1610612736
limit_memory_soft = 1073741824
limit_request = 8192
limit_time_cpu = 300
limit_time_real = 600
logfile = /var/log/odoo/odoo.log
log_level = info
data_dir = /var/lib/odoo/.local/share/Odoo
server_wide_modules = base,web
without_demo = all
EOF

sudo chown $USER:$USER v19/config/odoo.conf
chmod 644 v19/config/odoo.conf

# Addons Odoo
print_message "Configurando addons de Odoo dentro de v19/data/addons..."
mkdir -p v19/data/addons/extra v19/data/addons/oca v19/data/addons/enterprise
sudo chown -R 1001:1001 v19/data/addons
chmod 755 v19/data/addons

# Configurar secrets
print_message "Configurando secrets..."
mkdir -p secrets
chmod 755 secrets

cat > secrets/postgres_password.txt << 'EOF'
0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491
EOF

cat > secrets/redis_password.txt << 'EOF'
redis123
EOF

if [ ! -f "secrets/n8n_password.txt" ]; then
    openssl rand -hex 32 > secrets/n8n_password.txt
fi

if [ ! -f "secrets/n8n_encryption_key.txt" ]; then
    openssl rand -hex 64 > secrets/n8n_encryption_key.txt
fi

if [ ! -f "secrets/chatwoot_secret_key_base.txt" ]; then
    echo "chatwoot_secret_key_base_$(openssl rand -hex 32)" > secrets/chatwoot_secret_key_base.txt
fi

chmod 644 secrets/*.txt
print_message "✓ Secrets configurados"

# Crear archivo .env desde env-example (CORREGIDO)
print_message "Creando archivo .env desde env-example..."
if [ -f "env-example" ]; then
    # Copiar env-example a .env
    cp env-example .env
    print_message "✓ .env creado desde env-example"
    
    # Actualizar valores específicos si es necesario
    sed -i "s/POSTGRES_DB=.*/POSTGRES_DB=dbodoo19/" .env
    sed -i "s/POSTGRES_USER=.*/POSTGRES_USER=odoo/" .env
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491/" .env
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=redis123/" .env
    sed -i "s/VERSION=.*/VERSION=19/" .env
else
    print_error "❌ No se encuentra el archivo env-example"
    exit 1
fi



chmod 644 .env

# Añadir al final del .env (después de la creación)
# echo "" >> .env
# echo "# Redes Sociales (opcional - valores por defecto)" >> .env
# echo "OPENAI_API_KEY=" >> .env
# echo "INSTAGRAM_APP_ID=" >> .env
# echo "INSTAGRAM_APP_SECRET=" >> .env
# echo "FACEBOOK_APP_ID=" >> .env
# echo "FACEBOOK_APP_SECRET=" >> .env

print_message "✓ .env configurado correctamente"
print_message "Contenido de .env:"
cat .env


# 2. Crear base de datos 'odoo' faltante
echo "2. Creando base de datos 'odoo'..."
docker exec odoo-db19-n8n psql -U odoo -d postgres -c "CREATE DATABASE odoo OWNER odoo;" 2>/dev/null && echo "   ✅ Base de datos 'odoo' creada" || echo "   ⚠️ La base de datos 'odoo' ya existe"

# 3. Crear base de datos 'dbodoo19' si no existe
echo "3. Verificando base de datos 'dbodoo19'..."
docker exec odoo-db19-n8n psql -U odoo -d postgres -c "CREATE DATABASE dbodoo19 OWNER odoo;" 2>/dev/null && echo "   ✅ Base de datos 'dbodoo19' creada" || echo "   ⚠️ La base de datos 'dbodoo19' ya existe"

# Crear docker-compose.override.yml
print_message "Creando docker-compose.override.yml..."
cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  web:
    user: "1001:1001"
    volumes:
      - ./v19/odoo-web-data:/var/lib/odoo
      - ./v19/config:/etc/odoo
      - ./v19/data/addons/extra:/opt/odoo/custom-addons/extra
      - ./v19/data/addons/oca:/opt/odoo/custom-addons/oca
      - ./v19/data/addons/enterprise:/opt/odoo/custom-addons/enterprise
      - ./v19/logs:/var/log/odoo
      - ./v19/data/filestore:/var/lib/odoo/.local/share/Odoo

  db:
    volumes:
      - "./v19/odoo_n8n_pgdata/data:/var/lib/postgresql/data/pgdata"
      - "./v19/odoo_n8n_pgdata/init:/docker-entrypoint-initdb.d"

  redis:
    volumes:
      - "./v19/redis_data:/data"
EOF

# 8. Verificar Docker
print_message "[8/8] Verificación final..."
echo ""
echo "=== Verificación final ==="
docker --version
docker compose version
echo ""
echo "Grupos del usuario:"
groups $USER
echo ""
echo "Estructura de directorios creada:"
ls -la v19/
echo ""
echo "Dynamic config de Temporal:"
ls -la dynamicconfig/
cat dynamicconfig/development-sql.yaml
echo ""
echo "Secrets generados:"
ls -la secrets/
echo ""
echo "✅ Instalación y configuración completada"
echo ""
print_warning "⚠️  IMPORTANTE: Cierra sesión y vuelve a entrar para aplicar cambios de grupo"
echo "   Luego ejecuta: ./1_despliegue_reconstruye_imagen_servicios_adicionales.sh"
echo "   Y después: ./2_despliegue_servicios_adicionales.sh"