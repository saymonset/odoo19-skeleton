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
print_message "[1/7] Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

# 2. Instalar dependencias
print_message "[2/7] Instalando dependencias..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common openssl

# 3. Agregar repositorio de Docker
print_message "[3/7] Agregando repositorio de Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Instalar Docker Engine
print_message "[4/7] Instalando Docker Engine..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Agregar usuario al grupo docker
print_message "[5/7] Agregando usuario al grupo docker..."
sudo usermod -aG docker $USER

# 6. Crear grupo odoogroup y agregar usuario
print_message "[6/7] Configurando grupo odoogroup..."
sudo groupadd -f odoogroup
sudo usermod -aG odoogroup $USER

# 7. Configurar directorios y permisos
print_message "[7/7] Configurando directorios y permisos..."

# Detener contenedores si existen
print_message "Deteniendo contenedores existentes..."
docker compose -f docker-compose.odoo.yml down 2>/dev/null || true
docker compose -f docker-compose.n8n.yml down 2>/dev/null || true
docker compose -f docker-compose.chatwoot.yml down 2>/dev/null || true
docker compose -f docker-compose.pgadmin.yml down 2>/dev/null || true
docker compose -f docker-compose.postiz.yml down 2>/dev/null || true

# Borrar directorios con permisos incorrectos
print_message "Limpiando directorios antiguos..."
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
mkdir -p v19/logs v19/odoo-web-data v19/data v19/odoo_n8n_pgdata
sudo chown -R 1001:1001 v19/logs v19/odoo-web-data v19/data v19/odoo_n8n_pgdata
chmod 755 v19/logs v19/odoo-web-data v19/data

# Redis (usuario 1001)
print_message "Configurando Redis (UID 1001)..."
mkdir -p v19/redis_data
sudo chown -R 1001:1001 v19/redis_data
chmod 755 v19/redis_data

# n8n (usuario 1000) - CORREGIDO
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
print_message "Configurando Temporal (UID 1000)..."
mkdir -p v19/temporal_elasticsearch_data
sudo chown -R 1000:1000 v19/temporal_elasticsearch_data
chmod 755 v19/temporal_elasticsearch_data

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

if [ ! -f "v19/config/odoo.conf" ]; then
    print_message "Creando v19/config/odoo.conf por defecto..."
    cat > v19/config/odoo.conf << 'EOF'
[options]
admin_passwd = admin
db_host = db
db_port = 5432
db_user = odoo
db_password = odoo_password_secure
addons_path = /opt/odoo/odoo-core/addons,/opt/odoo/custom-addons/extra,/opt/odoo/custom-addons/oca,/opt/odoo/custom-addons/enterprise
logfile = /var/log/odoo/odoo-server.log
EOF
    sudo chown $USER:$USER v19/config/odoo.conf
    chmod 644 v19/config/odoo.conf
fi

# Addons Odoo (usuario 1001)
print_message "Configurando addons de Odoo..."
mkdir -p v19/addons/extra v19/addons/oca v19/addons/enterprise
sudo chown -R 1001:1001 v19/addons
chmod 755 v19/addons

# Configurar secrets
print_message "Configurando secrets..."
mkdir -p secrets
chmod 755 secrets

if [ ! -f "secrets/postgres_password.txt" ]; then
    print_message "Generando nuevos secrets..."
    openssl rand -hex 32 > secrets/postgres_password.txt
    openssl rand -hex 32 > secrets/redis_password.txt
    openssl rand -hex 32 > secrets/n8n_password.txt
    openssl rand -hex 64 > secrets/n8n_encryption_key.txt
    echo "chatwoot_secret_key_base_$(openssl rand -hex 32)" > secrets/chatwoot_secret_key_base.txt
    echo "✓ Secrets generados"
else
    print_message "✓ Secrets ya existen"
fi

chmod 644 secrets/*.txt

# Crear archivo .env si no existe
if [ ! -f ".env" ]; then
    if [ -f "env-example" ]; then
        print_message "Copiando env-example a .env..."
        cp env-example .env
    else
        print_message "Creando archivo .env básico..."
        cat > .env << 'EOF'
VERSION=19
POSTGRES_DB=dbodoo19
POSTGRES_USER=odoo
POSTGRES_PASSWORD=odoo_password_secure
REDIS_PASSWORD=redis123
EOF
    fi
    chmod 644 .env
fi

# Crear docker-compose.override.yml si no existe
if [ ! -f "docker-compose.override.yml" ]; then
    print_message "Creando docker-compose.override.yml..."
    cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  web:
    user: "1001:1001"
    volumes:
      - ./v19/odoo-web-data:/var/lib/odoo
      - ./v19/config:/etc/odoo
      - ./v19/addons/extra:/opt/odoo/custom-addons/extra
      - ./v19/addons/oca:/opt/odoo/custom-addons/oca
      - ./v19/addons/enterprise:/opt/odoo/custom-addons/enterprise
      - ./v19/logs:/var/log/odoo
      - ./v19/data:/var/lib/odoo/.local/share/Odoo

  db:
    volumes:
      - "./v19/odoo_n8n_pgdata/data:/var/lib/postgresql/data/pgdata"
      - "./v19/odoo_n8n_pgdata/init:/docker-entrypoint-initdb.d"

  redis:
    volumes:
      - "./v19/redis_data:/data"
EOF
fi

# Verificar Docker
echo ""
echo "=== Verificación final ==="
docker --version
docker compose version
echo ""
echo "Grupos del usuario:"
groups $USER
echo ""
echo "Permisos de directorios:"
ls -la v19/ | head -15
echo ""
echo "Secrets generados:"
ls -la secrets/
echo ""
echo "✅ Instalación completada"
echo ""
print_warning "⚠️  IMPORTANTE: Cierra sesión y vuelve a entrar para aplicar cambios de grupo"
echo "   Luego ejecuta: ./1_despliegue_odoo_19_servicios_adicionales.sh"
echo "   Y después: ./2_despliegue_servicios_adicionales.sh"