# Crear versión dinámica
cat > v19/config/odoo.conf.dynamic << 'EOF'
[options]
addons_path = /opt/odoo/odoo-core/addons,/opt/odoo/custom-addons/extra,/opt/odoo/custom-addons/oca,/opt/odoo/custom-addons/enterprise

admin_passwd = admin

db_host = db
db_port = 5432
db_user = odoo
db_password = __POSTGRES_PASSWORD__
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
limit_time_real_cron = -1

logfile = /var/log/odoo/odoo.log
log_level = info
log_db = False
log_db_level = warning
log_handler = :WARNING,odoo.addons.base.models.ir_qweb:WARNING

data_dir = /var/lib/odoo/.local/share/Odoo

server_wide_modules = base,web
geoip_database = False
without_demo = all
EOF

# Script para generar el archivo con la contraseña real
cat > generate_odoo_conf.sh << 'SCRIPT'
#!/bin/bash
POSTGRES_PASS=$(cat secrets/postgres_password.txt)
sed "s/__POSTGRES_PASSWORD__/$POSTGRES_PASS/g" v19/config/odoo.conf.dynamic > v19/config/odoo.conf
echo "✅ Configuración generada con la contraseña: $POSTGRES_PASS"
chmod 644 v19/config/odoo.conf
sudo chown -R 1001:1001 v19/config
SCRIPT
