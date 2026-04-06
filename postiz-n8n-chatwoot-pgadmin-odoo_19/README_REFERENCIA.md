# Propósito de cada script:
# Script	Propósito	¿Cuándo usarlo?
# 0_install_docker_and_setup.sh	Instalación inicial - Instala Docker y crea directorios/permisos	SOLO UNA VEZ (la primera vez que configuras el sistema)
# 1_despliegue_odoo_19_servicios_adicionales.sh	Despliega Odoo - Construye la imagen e inicia PostgreSQL, Redis y Odoo	Cada vez que quieras iniciar Odoo
# 2_despliegue_servicios_adicionales.sh	Despliega servicios extra - Inicia n8n, pgAdmin y Chatwoot	Después de Odoo, para iniciar los servicios adicionales


./1_despliegue_odoo_19_servicios_adicionales.sh
Este script va a:

Construir la imagen Odoo con el Dockerfile corregido

Crear la red si no existe

Iniciar PostgreSQL, Redis y Odoo

Crear las bases de datos (postiz, temporal, db_n8n)

Verificar que todo funciona

Después de que termine (unos minutos), ejecuta:

bash
./2_despliegue_servicios_adicionales.sh
Eso es todo. No tienes que hacer nada más.

La secuencia correcta para SIEMPRE es:

./1_despliegue_odoo_19_servicios_adicionales.sh → Inicia Odoo

./2_despliegue_servicios_adicionales.sh → Inicia n8n, pgAdmin, Chatwoot

Para apagar todo:

bash
docker compose -f docker-compose.yaml down
Para prender todo otra vez:

bash
./1_despliegue_odoo_19_servicios_adicionales.sh
./2_despliegue_servicios_adicionales.sh





# Flujo normal de uso:
bash
# PRIMERA VEZ SOLO (ya lo hiciste)
./0_install_docker_and_setup.sh

# CADA VEZ QUE QUIERAS INICIAR TODO:
./1_despliegue_odoo_19_servicios_adicionales.sh   # Inicia Odoo
./2_despliegue_servicios_adicionales.sh           # Inicia n8n, pgAdmin, Chatwoot

# PARA APAGAR TODO:
docker compose -f docker-compose.yaml down

# PARA VER ESTADO:
docker ps



### Empieza instalando 0_install_docker_and_setup.sh, 1...sh, 2..sh
###
```bash
Asegurate que la variable de ambiente file este : .env


```

# Ver logs de un servicio específico
docker compose -f docker-compose.yaml logs -f web
docker compose -f docker-compose.yaml logs -f n8n
docker compose -f docker-compose.yaml logs -f chatwoot-app

# Ejecutar comandos en servicios específicos
docker compose -f docker-compose.yaml exec web bash
docker compose -f docker-compose.yaml exec db psql -U odoo -d dbodoo19

# Escalar servicios (si aplica)
docker compose -f docker-compose.yaml up -d --scale web=2

# Ver configuración completa
docker compose -f docker-compose.yaml config


# 4. Inicia en orden:
# Primero Odoo stack
docker compose -f docker-compose.odoo.yml up -d

# Espera a que PostgreSQL esté listo
sleep 10

# Luego n8n
docker compose -f docker-compose.n8n.yml up -d

# pgadmin 
docker compose -f  docker-compose.pgadmin.yml  up -d

# Finalmente Chatwoot (después de arreglar los problemas)
docker compose -f docker-compose.chatwoot.yml up


# Backup y Restore
# Reiniciar Odoo stack con el nuevo servicio
# docker compose -f docker-compose.odoo.yml down
# docker compose -f docker-compose.odoo.yml up -d

# Ejecutar backup manual
docker exec odoo_backup /usr/local/bin/backup.sh

# Ver backups
ls -la v19/backups/daily/

# Ver logs del backup
docker logs odoo_backup

# Restaurar backup
docker exec -it odoo_backup /backup/scripts/restore.sh


