#!/bin/bash
# fix_whatsapp_simple.sh

echo "=== FIX SIMPLE PARA WHATSAPP ==="

# 1. Asegurar que Odoo está corriendo
docker start odoo-19-web 2>/dev/null
sleep 5

# 2. Limpiar desde PostgreSQL (versión corregida)
echo "Limpiando base de datos..."
docker exec -i odoo-db19-n8n psql -U odoo -d dbodoo19 << 'EOF'
-- Eliminar todo lo relacionado con whatsapp
DELETE FROM ir_ui_view WHERE arch_db::text LIKE '%whatsapp%';
DELETE FROM ir_module_module WHERE name LIKE '%whatsapp%';
DELETE FROM ir_model_data WHERE module LIKE '%whatsapp%';
DELETE FROM ir_attachment WHERE name LIKE '%whatsapp%';
DELETE FROM ir_model_fields WHERE name LIKE '%whatsapp%';
DELETE FROM ir_ui_view_custom WHERE arch LIKE '%whatsapp%';

-- Agregar el campo si no existe
ALTER TABLE website ADD COLUMN IF NOT EXISTS whatsapp_text varchar DEFAULT '';

-- Limpiar caché de vistas
UPDATE ir_module_module SET state='to upgrade' WHERE name='website';
EOF

# 3. Parchear el archivo XML
echo "Parcheando archivo XML..."
docker exec odoo-19-web bash -c "
if [ -f /opt/odoo/odoo-core/addons/website/views/website_layout.xml ]; then
    # Comentar la línea problemática
    sed -i 's/t-if=\"website\.whatsapp_text\"/t-if=\"False\"/g' /opt/odoo/odoo-core/addons/website/views/website_layout.xml
    # También eliminar la línea si es necesario
    sed -i '/whatsapp_text/d' /opt/odoo/odoo-core/addons/website/views/website_layout.xml
fi
"

# 4. Limpiar caché de Python
docker exec odoo-19-web bash -c "find /opt/odoo/odoo-core -name '*.pyc' -delete 2>/dev/null"

# 5. Reiniciar Odoo
echo "Reiniciando Odoo..."
docker restart odoo-19-web

echo "Esperando 15 segundos..."
sleep 15

# 6. Verificar
echo ""
echo "=== Últimos logs ==="
docker logs --tail 20 odoo-19-web

echo ""
echo "=== Probar acceso ==="
curl -I http://localhost:18069