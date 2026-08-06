#!/bin/bash

echo "=== Creación de usuario odoo CORREGIDO ==="
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Verificar y crear grupos necesarios
print_message "Verificando grupos necesarios..."

# Lista de grupos a crear
GROUPS=("docker" "odoo" "odoogroup")

for group in "${GROUPS[@]}"; do
    if getent group "$group" > /dev/null 2>&1; then
        print_warning "Grupo $group ya existe"
    else
        sudo groupadd "$group" 2>/dev/null
        if [ $? -eq 0 ]; then
            print_message "✓ Grupo $group creado"
        else
            print_error "✗ Error al crear grupo $group"
        fi
    fi
done

echo ""

# 2. Verificar si el usuario odoo existe
if id "odoo" > /dev/null 2>&1; then
    print_warning "El usuario odoo YA EXISTE"
    print_message "Información actual:"
    id odoo
    groups odoo
    echo ""
    
    # Preguntar si quiere recrear el usuario
    read -p "¿Deseas eliminar y recrear el usuario odoo? (s/N): " RECREAR
    if [[ "$RECREAR" == "s" || "$RECREAR" == "S" || "$RECREAR" == "si" || "$RECREAR" == "SI" ]]; then
        print_warning "Eliminando usuario odoo..."
        sudo userdel -r odoo 2>/dev/null
        print_message "✓ Usuario odoo eliminado"
        USER_EXISTS=false
    else
        USER_EXISTS=true
    fi
else
    USER_EXISTS=false
fi

# 3. Crear el usuario si no existe
if [ "$USER_EXISTS" = false ]; then
    print_message "Creando usuario odoo..."
    
    # Crear usuario con -g para grupo primario y -G para grupos secundarios
    sudo useradd -m -s /bin/bash -g odoo -G sudo,adm,docker odoo 2>/dev/null
    
    if [ $? -eq 0 ]; then
        print_message "✓ Usuario odoo creado exitosamente"
        
        # 4. Establecer contraseña temporal
        print_message "Estableciendo contraseña temporal..."
        echo "odoo:odoo" | sudo chpasswd 2>/dev/null
        if [ $? -eq 0 ]; then
            print_message "✓ Contraseña temporal: odoo"
            print_warning "⚠️  CAMBIA LA CONTRASEÑA DESPUÉS: sudo passwd odoo"
        else
            print_error "✗ Error al establecer contraseña"
        fi
        
        # 5. Agregar a todos los grupos necesarios
        print_message "Agregando a grupos adicionales..."
        sudo usermod -aG odoogroup odoo 2>/dev/null
        sudo usermod -aG docker odoo 2>/dev/null
        sudo usermod -aG adm odoo 2>/dev/null
        sudo usermod -aG sudo odoo 2>/dev/null
        print_message "✓ Usuario agregado a todos los grupos"
        
        # 6. Crear estructura de directorios
        print_message "Creando estructura de directorios..."
        sudo mkdir -p /home/odoo/v18/{logs,odoo-web-data,data/addons,data/filestore,odoo_n8n_pgdata,redis_data,n8n_data,chatwoot_storage,chatwoot_logs,chatwoot_tmp,chatwoot_pgdata,postiz_config,postiz_uploads,temporal_elasticsearch_data,pgadmin-data,config}
        sudo mkdir -p /home/odoo/dynamicconfig
        sudo mkdir -p /home/odoo/secrets
        sudo mkdir -p /home/odoo/.local/share/Odoo
        sudo mkdir -p /home/odoo/scripts
        
        # 7. Configurar permisos
        print_message "Configurando permisos..."
        sudo chown -R odoo:odoo /home/odoo/
        sudo chmod 755 /home/odoo/
        sudo chmod 755 /home/odoo/v18
        sudo chmod 755 /home/odoo/dynamicconfig
        sudo chmod 755 /home/odoo/secrets
        sudo chmod 755 /home/odoo/scripts
        
        # 8. Crear .bashrc personalizado
        print_message "Configurando .bashrc personalizado..."
        sudo bash -c 'cat > /home/odoo/.bashrc << "EOF"
# ~/.bashrc: executed by bash(1) for non-login shells.

# If running interactively, then:
if [[ $- != *i* ]] ; then
    # Non-interactive.  Don\'t do anything complicated.
    return
fi

# Source the system-wide bashrc if it exists
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# Enable color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls="ls --color=auto"
    alias grep="grep --color=auto"
    alias fgrep="fgrep --color=auto"
    alias egrep="egrep --color=auto"
fi

# Useful aliases
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Docker aliases
alias dps="docker ps"
alias dpsa="docker ps -a"
alias di="docker images"
alias docker-clean="docker system prune -f"
alias docker-clean-all="docker system prune -a -f"

# Odoo aliases
alias odoo-log="tail -f ~/v18/logs/odoo.log 2>/dev/null || echo \"Log no disponible\""
alias odoo-shell="docker exec -it odoo-web /bin/bash 2>/dev/null || echo \"Contenedor no disponible\""
alias odoo-restart="docker compose -f ~/docker-compose.odoo.yml restart"
alias odoo-stop="docker compose -f ~/docker-compose.odoo.yml stop"
alias odoo-start="docker compose -f ~/docker-compose.odoo.yml start"

# Path
export PATH="$HOME/.local/bin:$PATH"
export ODOO_HOME="$HOME"

# Custom prompt
if [ "$color_prompt" = yes ]; then
    PS1="\${debian_chroot:+(\$debian_chroot)}\\[\033[01;32m\\]\\u@\\h\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "
else
    PS1="\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\$ "
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title
case "$TERM" in
xterm*|rxvt*)
    PS1="\\[\\e]0;\\u@\\h: \\w\\a\\]$PS1"
    ;;
*)
    ;;
esac

# Enable programmable completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi
EOF'

        sudo chown odoo:odoo /home/odoo/.bashrc
        sudo chmod 644 /home/odoo/.bashrc
        
        # 9. Crear .profile
        sudo bash -c 'cat > /home/odoo/.profile << "EOF"
# ~/.profile: executed by the command interpreter for login shells.
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# Set PATH so it includes user private bin
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
EOF'

        sudo chown odoo:odoo /home/odoo/.profile
        sudo chmod 644 /home/odoo/.profile
        
        print_message "✓ Usuario odoo configurado completamente"
    else
        print_error "✗ Error al crear el usuario odoo"
        exit 1
    fi
fi

# 10. Verificación final
echo ""
echo "=== VERIFICACIÓN FINAL ==="
echo ""
echo "Usuario odoo:"
id odoo
echo ""
echo "Grupos de odoo:"
groups odoo
echo ""
echo "Directorio home:"
ls -la /home/odoo/ 2>/dev/null || echo "Home no encontrado"
echo ""
echo "Estructura v18:"
ls -la /home/odoo/v18/ 2>/dev/null || echo "v18 no encontrado"
echo ""

print_message "✅ CONFIGURACIÓN COMPLETADA EXITOSAMENTE"
echo ""
print_warning "⚠️  INSTRUCCIONES IMPORTANTES:"
echo "   1. Cambia la contraseña: sudo passwd odoo"
echo "   2. Cambia al usuario: su - odoo"
echo "   3. Verifica grupos: groups odoo"
echo "   4. Si falta algún grupo, ejecuta:"
echo "      sudo usermod -aG docker,odoo,odoo odoo"
echo ""
print_message "Comandos útiles una vez dentro de odoo:"
echo "   ll              # Ver directorios"
echo "   odoo-log        # Ver logs de Odoo"
echo "   dps             # Ver contenedores Docker"
echo "   docker-clean    # Limpiar Docker"
echo ""
print_message "Para cambiar al usuario odoo:"
echo "   su - odoo"
echo "   cd ~/v18"
echo ""
