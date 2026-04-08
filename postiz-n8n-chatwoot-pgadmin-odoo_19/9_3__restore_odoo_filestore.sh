#!/bin/bash

# 1. Detener todos los servicios que dependen de la DB
docker stop odoo-19-web
docker stop odoo_backup

# 2. Detener y eliminar el contenedor de base de datos
docker stop odoo-db19-n8n
docker rm odoo-db19-n8n

# 3. Limpiar los datos viejos (IMPORTANTE: esto borra la DB actual)
sudo rm -rf ./v19/odoo_n8n_pgdata/data/

# 4. Recrear el contenedor de base de datos
docker compose -f docker-compose.odoo.yml up -d db

# 5. Esperar que esté saludable
sleep 20

# 6. Verificar que está corriendo
docker ps | grep odoo-db

# 7. Ahora restaurar el backup
./backup/restore.sh

# 1. Intentar levantar Odoo web
docker compose -f docker-compose.odoo.yml up -d web

# 2. Ver el estado
docker ps -a | grep odoo-19-web

# 3. Ver logs para identificar el problema
docker logs odoo-19-web --tail 50