# Traer backup de maquina remota a local linux 
scp -r odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out  /home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup

# Traer backup de maquina remota a local linux 
scp -r odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup

# Subir backup de maquina linux a remota
scp -r /home/simon/opt/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/

# Subir backup de maquina mac a remota
scp -r /Users/simon/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out odoo@147.93.179.254:/home/odoo/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup


# backup de produccion a desarrollo
mv /home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out/backup_2026-04-28_21-05-30 /home/odoo/develop/odoo-from-13-to-18/arquitectura/odoo19/backup/out

# backup de desarrollo a produccion
mv /home/odoo/develop/odoo-from-13-to-18/arquitectura/odoo19/backup/out/backup_2026-04-28_21-46-06 /home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/backup/out