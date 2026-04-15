#!/bin/bash
# 1. Cambia el propietario de toda la estructura a tu usuario (simon)
sudo chown -R simon:staff /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/v19

# 2. Da permisos amplios a la carpeta que necesita Docker
sudo chmod -R 777 /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/v19/odoo_n8n_pgdata

# 3. Crea las subcarpetas necesarias (data e init)
mkdir -p /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/v19/odoo_n8n_pgdata/data
mkdir -p /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/v19/odoo_n8n_pgdata/init

# 4. (Opcional) si quieres permisos aún más abiertos para evitar futuros problemas:
chmod -R 777 /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/v19/

# 1. Detén Odoo para evitar conflictos
docker stop odoo-19-web

# 2. Asegura que existe la estructura de directorios dentro de odio-web-data
mkdir -p v19/odoo-web-data/.local/share/Odoo/sessions

# 3. Da permisos totales (777) a toda la carpeta de datos de Odoo para que el usuario 1001 pueda escribir
chmod -R 777 v19/odoo-web-data

# 4. Opcional: si quieres ser más específico, solo para sessions:
# chmod -R 777 v19/odoo-web-data/.local/share/Odoo/sessions

# 5. Reinicia Odoo
docker start odoo-19-web