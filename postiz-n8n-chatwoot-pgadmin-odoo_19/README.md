# Entorno Odoo 19 con n8n, Chatwoot, pgAdmin y Postiz

Esta es la guía rápida y principal para manejar y limpiar carpetas, así como gestionar copias de seguridad de este entorno. Si necesitas entender el flujo en general de cómo prender/apagar los contenedores, revisa el archivo `README_REFERENCIA.md`.

---

## 1. Limpieza Local (Borrar archivos auto-generados)

El script `0_install_docker_and_setup.sh` inicializa múltiples carpetas de volúmenes, asigna configuraciones y genera secretos y un archivo `.env` o `docker-compose.override.yml`.
Si necesitas empezar **completamente de cero** o eliminar todo rastro del despliegue actual manualmente, primero debes apagar tus contenedores y ejecutar los siguientes comandos para borrar todo el rastro:

```bash
# 1. Apagar y limpiar contenedores huérfanos de la pila:
docker compose -f docker-compose.odoo.yml down
docker compose -f docker-compose.n8n.yml down
docker compose -f docker-compose.chatwoot.yml down
docker compose -f docker-compose.pgadmin.yml down
docker compose -f docker-compose.postiz.yml down

# 2. Borrar carpetas generadas automáticamente (Requiere sudo)
sudo rm -rf v19/
sudo rm -rf secrets/
sudo rm -rf backups/

# 3. Borrar archivos de entorno generados en tiempo real
sudo rm -f .env docker-compose.override.yml
```

Una vez que corras esto, el entorno queda "reseteado". Tendrías que arrancar con `0_install_docker_and_setup.sh` de nuevo para generar todas las carpetas.

Te generara un .env, si no existe, debes crearlo y copiar el contenido de .env.example a .env y modificar las variables que necesites.

La password /secrets/chatwoot_secret_key_base.txt es para chatwoot.  y debe ser cambiada si la vas a cambiar en .env y en docker-compose.chatwoot.yml

El de postgres /secrets/postgres_password.txt solo la cambias en el .env  en la variable  POSTGRES_PASSWORD si necesitas cambiarla.

---

## 2. Gestión de Copias de Seguridad (Backups)

El sistema cuenta con un ejecutable configurado para guardar no sólo un "Dump" de la base de datos en SQL crudo o empaquetado, sino la configuración del contendor, tu filestore y los addons:

- Los respaldos generados se guardan automáticamente en la carpeta `./backup/out/`.
- El script extrae las credenciales del Docker enviándolas internamente por el `docker exec`.

**Comando para generar un respaldo:**
```bash
./9_1_backup_bd.sh
```

---

## 3. Restauración de Datos (Restores)

Hemos configurado los scripts de restauración para que operen sin destruir tu configuración ni el filestore anterior (haciendo en su defecto respaldos previos renombrando carpetas a `_backup`). El sistema es inteligente y auto-detecta la ruta del filestore que entra del zip para tratar de acoplarla a `dbodoo19`.

### 3.1. Listar Backups 
Para verificar cuáles archivos `*.dump` y `*.tar.gz` tienes disponibles en `./backup/out/`:
```bash
./9_2_restore_listar.sh
```

### 3.2. Ejecutar la Restauración
Puedes restaurar utilizando el script principal. Por defecto va a coger el backup **más reciente** de la carpeta asignada en el interior de `backup/restore.sh`:
```bash
./9_3__restore_odoo_filestore.sh
```

**Nota:** Si vas a restaurar un backup específico, asegúrate de actualizar la variable `BACKUP_DIR` dentro del archivo `./backup/restore.sh` apuntando a la subruta o ID exacto del backup que extrajiste.
