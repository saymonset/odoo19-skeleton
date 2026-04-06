#!/bin/bash
POSTGRES_PASS=$(cat secrets/postgres_password.txt)
sed "s/__POSTGRES_PASSWORD__/$POSTGRES_PASS/g" v19/config/odoo.conf.dynamic > v19/config/odoo.conf
echo "✅ Configuración generada con la contraseña: $POSTGRES_PASS"
chmod 644 v19/config/odoo.conf
sudo chown -R 1001:1001 v19/config
