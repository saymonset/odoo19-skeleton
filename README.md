# Traer backup de maquina remota a local
scp -r odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out  /home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup

scp -r odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup

# Subir backup de maquina local a remota
scp -r /home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup

