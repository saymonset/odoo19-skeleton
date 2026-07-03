#!/bin/bash
# ==============================
# Protección de puerto 18069
# Solo accesible desde IP 147.93.179.254
# ==============================

# Verificación de permisos
if [ "$EUID" -ne 0 ]; then
  echo "⚠️  Por favor ejecuta este script como root (sudo)."
  exit 1
fi

echo "🔧 Actualizando sistema..."
apt update && apt upgrade -y

echo "🧱 Instalando y configurando UFW..."
apt install ufw -y

# Reglas básicas del firewall
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH (puerto 22)
ufw allow ssh

# Permitir solo desde tu IP el puerto 28069
ufw allow from 147.93.179.254 to any port 28069 proto tcp

# Activar el firewall
ufw --force enable

echo "✅ Firewall configurado. Reglas activas:"
ufw status verbose

echo "🛡️ Instalando Fail2ban para proteger SSH..."
apt install fail2ban -y
systemctl enable fail2ban
systemctl start fail2ban

echo "✅ Fail2ban está activo y protegiendo contra intentos de hackeo."

echo "🧩 Verificando servicio en puerto 28069..."
ss -tuln | grep 28069 || echo "⚠️ El puerto 28069 no está escuchando (verifica tu servicio)."

echo "🎯 Configuración completada con éxito."
