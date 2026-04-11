#!/bin/bash


 #Restauración normal (sin instalar módulos adicionales)
#./backup/restore.sh

# Restauración e instalación de módulos OCA
./backup/restore.sh --install-modules

# Restaurar un archivo específico e instalar módulos
#./backup/restore.sh -f odoo_db_2026-04-10_16-27-26.dump --install-modules