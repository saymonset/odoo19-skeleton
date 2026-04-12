#!/bin/bash


 #Restauración normal (sin instalar módulos adicionales)
#./backup/restore.sh

# Restauración e instalación de módulos OCA
./backup/restore.sh --install-modules

# Restaurar un archivo específico e instalar módulos
#./backup/restore.sh -f odoo_db_2026-04-10_16-27-26.dump --install-modules

# Guardar el script
#chmod +x 9_3__restore_odoo_filestore.sh

# Restauración normal
#./9_3__restore_odoo_filestore.sh

# Restauración con instalación de módulos
#./9_3__restore_odoo_filestore.sh --install-modules

# Restaurar un backup específico
#./9_3__restore_odoo_filestore.sh -f backup/out/backup_2026-04-12_09-20-34/odoo_db_2026-04-12_09-20-34.dump --install-modules