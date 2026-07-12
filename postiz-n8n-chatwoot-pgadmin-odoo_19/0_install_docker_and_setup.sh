#!/bin/bash

echo "=== Instalación de Docker y configuración de permisos (LEADS) ==="
echo ""

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
docker compose -f docker-compose.yaml down 2>/dev/null || true

# ============================================
# LIMPIEZA COMPLETA DE VOLÚMENES (OPCIONAL)
# ============================================
print_message "⚠️ ADVERTENCIA: Esto eliminará TODOS los datos existentes"
read -p "¿Deseas eliminar también los volúmenes? (yes/no): " CLEAN_VOLUMES

if [ "$CLEAN_VOLUMES" = "yes" ]; then
    print_message "Eliminando volúmenes..."
    docker compose -f docker-compose.yaml down -v 2>/dev/null || true
    print_message "✓ Volúmenes eliminados"
fi

# LIMPIEZA TOTAL DE DIRECTORIOS ANTIGUOS
print_message "Limpiando directorios antiguos por completo..."
sudo rm -rf v19-leads/

# Crear directorios principales
print_message "Creando directorios con permisos correctos..."
mkdir -p v19-leads

# PostgreSQL (UID 1001 para pgdata)
print_message "Configurando PostgreSQL..."
mkdir -p v19-leads/pgdata/data v19-leads/pgdata/init
sudo chown -R 1001:1001 v19-leads/pgdata
chmod 755 v19-leads/pgdata

# Odoo (UID 1001)
print_message "Configurando Odoo (UID 1001)..."
mkdir -p v19-leads/logs v19-leads/odoo-web-data
sudo chown -R 1001:1001 v19-leads/logs v19-leads/odoo-web-data
chmod 755 v19-leads/logs v19-leads/odoo-web-data

# Configuración Odoo (usuario actual)
print_message "Configurando archivos de configuración..."
mkdir -p v19-leads/config
sudo chown -R $USER:$USER v19-leads/config
chmod 755 v19-leads/config

# CREAR ODOO.CONF ACTUALIZADO
print_message "Creando v19-leads/config/odoo.conf (configuración optimizada)..."
cat > v19-leads/config/odoo.conf << 'EOF'
[options]
addons_path = /opt/odoo/odoo-core/addons,/opt/odoo/custom-addons/extra,/opt/odoo/custom-addons/oca,/opt/odoo/custom-addons/enterprise
admin_passwd = admin
db_host = db-leads
db_port = 5432
db_user = odoo
db_name = dbodoo19
db_password = leads_password_123
db_sslmode = prefer
db_template = template0
db_maxconn = 64
http_enable = True
http_interface = 0.0.0.0
http_port = 8069
gevent_port = 8072
proxy_mode = True
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

sudo chown $USER:$USER v19-leads/config/odoo.conf
chmod 644 v19-leads/config/odoo.conf

# Configurar secrets (solo postgres)
print_message "Configurando secrets..."
mkdir -p secrets
chmod 755 secrets

cat > secrets/postgres_password.txt << 'EOF'
0c7ea99eb597bce5495e2d93cb0cdaa0ab3294f4d48933c892ac6133d6c20491
EOF

chmod 644 secrets/*.txt
print_message "✓ Secrets configurados"

# Crear archivo .env desde env-example
print_message "Creando archivo .env desde env-example..."
if [ -f "env-example" ]; then
    cp env-example .env
    print_message "✓ .env creado desde env-example"

    sed -i "s/POSTGRES_DB=.*/POSTGRES_DB=dbodoo19/" .env
    sed -i "s/POSTGRES_USER=.*/POSTGRES_USER=odoo/" .env
    sed -i "s/VERSION=.*/VERSION=19/" .env
else
    print_error "❌ No se encuentra el archivo env-example"
    exit 1
fi

chmod 644 .env

print_message "✓ .env configurado correctamente"
print_message "Contenido de .env:"
cat .env

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
ls -la v19-leads/
echo ""
echo "Secrets generados:"
ls -la secrets/
echo ""
echo "✅ Instalación y configuración completada"
echo ""
print_warning "⚠️  IMPORTANTE: Cierra sesión y vuelve a entrar para aplicar cambios de grupo"
echo "   Luego ejecuta: ./1_despliegue_reconstruye_imagen_servicios_adicionales.sh"
