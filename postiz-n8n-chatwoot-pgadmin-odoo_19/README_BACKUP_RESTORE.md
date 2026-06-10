# Backup & Restore — Postiz-n8n-Chatwoot-Odoo 19

Guía de respaldo y restauración para el stack completo.

---

## Scripts disponibles

| Script | Llama a | Formato backup | Propósito |
|---|---|---|---|
| `9_1_backup_sistema_completo.sh` | `backup/backup.sh` | `dbodoo19_*.dump`, `n8n_*.dump`, etc. | Backup unificado (Odoo + n8n + Postiz + Chatwoot) |
| `9_2_restore_sistema_ultimo.sh` | `backup/restore_full.sh` | `dbodoo19_*.dump` | Restaura el backup más reciente (formato `backup.sh`) |
| `9_3_restore_solo_odoo.sh` | `backup/restore.sh` | `odoo_db_*.dump` | Restaura solo Odoo (formatos antiguo y nuevo) |
| `9_4_restore_solo_n8n.sh` | `backup/restore_solo_n8n.sh` | — | Restaura solo n8n |
| `9_5_restore_solo_postiz.sh` | `backup/restore_solo_postiz.sh` | — | Restaura solo Postiz |

---

## Formatos de backup

Existen dos formatos según el script que generó el backup.

### Formato nuevo (`backup/backup.sh`)

```
backup/out/backup_2026-06-10_16-49-36/
  ├── dbodoo19_2026-06-10_16-49-36.dump
  ├── db_n8n_2026-06-10_16-49-36.dump
  ├── postiz_2026-06-10_16-49-36.dump
  ├── chatwoot_db_2026-06-10_16-49-36.dump
  ├── odoo_data_2026-06-10_16-49-36.tar.gz      (opcional)
  ├── n8n_data_2026-06-10_16-49-36.tar.gz        (opcional)
  ├── env_file_2026-06-10_16-49-36.env
  └── odoo_config_2026-06-10_16-49-36.conf
```

**Usar con**: `9_2_restore_sistema_ultimo.sh`

### Formato antiguo (`backup` anterior)

```
backup/out/backup_2026-06-10_14-52-54/
  ├── odoo_db_2026-06-10_14-52-54.dump
  ├── odoo_filestore_2026-06-10_14-52-54.tar.gz
  ├── odoo_addons_2026-06-10_14-52-54.tar.gz
  └── odoo_config_2026-06-10_14-52-54.conf
```

**Usar con**: `9_3_restore_solo_odoo.sh` / `backup/restore.sh`

---

## Cómo hacer backup

### Backup completo (todo el stack)

```bash
cd ~/lead/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19
./9_1_backup_sistema_completo.sh
```

El backup se guarda en `backup/out/backup_AAAA-MM-DD_HH-MM-SS/`.

### Solo Odoo (formato antiguo)

```bash
# Usando el script de backup antiguo (si existe)
./old_scripts/9_1_backup_bd.sh
```

---

## Cómo restaurar

### Restaurar en la misma máquina (PROD por defecto)

```bash
cd ~/lead/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19

# Restaurar el último backup completo
./9_2_restore_sistema_ultimo.sh

# Restaurar un backup específico de Odoo
./9_3_restore_solo_odoo.sh \
  -f backup/out/backup_2026-06-10_14-52-54/odoo_db_2026-06-10_14-52-54.dump
```

### Restaurar en una máquina diferente (LEAD, staging, etc.)

`backup/restore.sh` acepta flags para apuntar a cualquier instancia.

#### Flags disponibles

| Flag | Variable que sobreescribe | Default (PROD) |
|---|---|---|
| `--db-container` | `DB_CONTAINER` | `odoo-db19-n8n` |
| `--web-container` | `WEB_CONTAINER` | `odoo-19-web` |
| `--db-name` | `DB_NAME` | (del odoo.conf) |
| `--db-user` | `DB_USER` | `odoo` |
| `--db-password` | `DB_PASSWORD` | (del odoo.conf o secrets) |
| `--odoo-conf` | `ODOO_CONF` | `./v19/config/odoo.conf` |
| `--filestore-dir` | `FILESTORE_DIR` | `./v19/data/filestore` |
| `--data-dir` | `DATA_DIR` | `./v19/data` |
| `--compose-file` | `COMPOSE_ODOO_FILE` | `docker-compose.odoo.yml` |
| `--network` | `NETWORK_NAME` | `odoo_network_19` |

#### Ejemplo: restaurar en LEAD

```bash
cd ~/lead/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19

./backup/restore.sh \
  -f backup/out/backup_2026-06-10_14-52-54/odoo_db_2026-06-10_14-52-54.dump \
  --db-container odoo-db19-leads \
  --web-container odoo-19-web-leads \
  --db-name dbodoo19 \
  --odoo-conf ./v19-leads/config/odoo.conf \
  --filestore-dir ./v19-leads/odoo-web-data/.local/share/Odoo/filestore
```

#### Sin flags = comportamiento original (PROD)

```bash
# Restaura el último backup en PROD exactamente como antes
./backup/restore.sh
```

---

## Post-restauración

### 1. Módulos faltantes

Si el backup contiene módulos que no existen en los addons de la máquina destino,
Odoo fallará al arrancar. Para evitarlo, márcalos como no instalados **antes de iniciar Odoo**:

```bash
docker exec <DB_CONTAINER> psql -U odoo -d <DB_NAME> -c "
  UPDATE ir_module_module SET state='uninstalled'
  WHERE name IN ('chat_bot_integra','chat_bot_n8n_ia','website_whatsapp')
  AND state='installed';
"
```

### 2. Nombre de base de datos diferente

Si el backup se hizo con una BD llamada `dbintegraiadev_19` y la restauras como `dbodoo19`:

```bash
# Renombrar directorio del filestore
mv <filestore-dir>/dbintegraiadev_19 <filestore-dir>/dbodoo19

# Actualizar referencias en ir_attachment
docker exec <DB_CONTAINER> psql -U odoo -d <DB_NAME> -c "
  UPDATE ir_attachment
  SET store_fname = REPLACE(store_fname, 'dbintegraiadev_19', 'dbodoo19')
  WHERE store_fname LIKE '%dbintegraiadev_19%';
"
```

### 3. Permisos del filestore

```bash
chown -R 1001:1001 <filestore-dir>
```

---

## Troubleshooting

### `export: '#': not a valid identifier`

El archivo `.env` tiene comentarios inline (`VAR=valor # comentario`).
El script `backup.sh` ya maneja esto correctamente. Si ves el error en otro script,
aplica el mismo fix: reemplazar `export $(grep -v '^#' .env | xargs)` por un `while read` loop.

### `Permission denied: /var/lib/odoo/.local/share/Odoo/filestore`

El contenedor corre como uid 1001 pero el directorio en el host pertenece a otro usuario.
Solución:

```bash
docker run --rm -v <ruta_host>/filestore:/data alpine chown -R 1001:1001 /data
```

### `module X not found`

El backup tiene módulos instalados que no existen en el filesystem de la máquina destino.

```bash
docker exec <DB_CONTAINER> psql -U odoo -d <DB_NAME> -c "
  UPDATE ir_module_module SET state='uninstalled' WHERE name='X';
"
```

### `database already exists`

```bash
docker exec <DB_CONTAINER> dropdb -U odoo --if-exists <DB_NAME>
```

### `relation "ir_attachment" does not exist`

El dump no se restauró correctamente o la BD está vacía.
Verifica que `pg_restore` completó sin errores.

---

## Arquitectura

```
proyecto/
├── backup/
│   ├── backup.sh              # Script de backup unificado
│   ├── restore.sh             # Restaura Odoo (parametrizable con flags)
│   ├── restore_full.sh        # Restaura completo (formato nuevo)
│   ├── restore_solo_n8n.sh    # Restaura solo n8n
│   ├── restore_solo_postiz.sh # Restaura solo Postiz
│   └── out/                   # Backups generados aquí
│
├── 9_1_backup_sistema_completo.sh  → backup/backup.sh
├── 9_2_restore_sistema_ultimo.sh   → backup/restore_full.sh
├── 9_3_restore_solo_odoo.sh        → backup/restore.sh
├── 9_4_restore_solo_n8n.sh         → backup/restore_solo_n8n.sh
├── 9_5_restore_solo_postiz.sh      → backup/restore_solo_postiz.sh
│
├── v19/         # Datos de PROD (odoo-db19-n8n, odoo-19-web)
├── v19-leads/   # Datos de LEAD (odoo-db19-leads, odoo-19-web-leads)
└── README_BACKUP_RESTORE.md
```

---

## Notas

- Los scripts usan `set -e` — fallan ante cualquier error.
- Los backups se almacenan en `backup/out/` con retención de 7 días (configurable en `backup.sh`).
- Todos los comandos se ejecutan desde la raíz del proyecto.
- Para agregar soporte a una nueva instancia, solo pasa los flags correspondientes a `backup/restore.sh`.
