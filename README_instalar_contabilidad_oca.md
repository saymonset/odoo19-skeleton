#  Bajar responsive
git clone --depth 1 --branch 19.0 git@github.com:OCA/web.git temp_oca_modules

# Bajar los repositorios de contabilidad oca

git clone --depth 1 --branch 19.0 git@github.com:OCA/account-financial-tools.git temp_oca_modules

git clone --depth 1 --branch 19.0 git@github.com:OCA/reporting-engine.git temp_oca_modules
                                  
git clone --depth 1 --branch 19.0 git@github.com:OCA/reporting-engine.git temp_oca_modules
git clone --depth 1 --branch 19.0 git@github.com:OCA/server-ux.git temp_oca_modules
git clone --depth 1 --branch 19.0 git@github.com:OCA/account-financial-reporting.git temp_oca_modules
git clone --depth 1 --branch 19.0 git@github.com:OCA/account-financial-reporting.git temp_oca_modules

# Copiar modulos a una carpeta para instalarlos
 # Estás en: ~/lead/modulos_odoo/shared/oca/19.0.1/temp_oca_modules
# Los módulos se moverán a: ~/lead/modulos_odoo/shared/oca/19.0.1/

for dir in */; do [ -f "${dir}__manifest__.py" ] || [ -f "${dir}__openerp__.py" ] && mv "$dir" "../${dir%/}" && echo "✅ ${dir%/}" || echo "⏭️ ${dir%/}"; done