import os
import sys

# Script para ser ejecutado con 'odoo shell'
# Uso: odoo shell -d <dbname> -- < script.py [--fix]

def check_filestore(env, fix=False):
    print("Iniciando escaneo de filestore...")
    # Solo buscamos archivos de tipo binario (los almacenados en disco)
    attachments = env['ir.attachment'].search([('type', '=', 'binary')])
    
    missing_count = 0
    found_count = 0
    records_to_unlink = []

    for attach in attachments:
        if not attach.store_fname:
            continue
            
        # Odoo 19 / 17+ usa _full_path para obtener la ruta absoluta
        try:
            full_path = attach._full_path(attach.store_fname)
            if not os.path.exists(full_path):
                missing_count += 1
                print(f"[FALTA] ID: {attach.id} | Nombre: {attach.name} | Hash: {attach.checksum}")
                records_to_unlink.append(attach)
            else:
                found_count += 1
        except Exception as e:
            print(f"[ERROR] No se pudo verificar ID {attach.id}: {e}")

    print("\n" + "="*40)
    print(f"RESULTADO DEL DIAGNÓSTICO:")
    print(f"Archivos encontrados: {found_count}")
    print(f"Archivos faltantes:    {missing_count}")
    print("="*40 + "\n")

    if fix:
        if missing_count > 0:
            print(f"REPARANDO: Eliminando {missing_count} registros de ir.attachment sin archivo físico...")
            for attach in records_to_unlink:
                try:
                    # Usamos unlink para borrar la referencia en la BD
                    attach.unlink()
                except Exception as e:
                    print(f"Error borrando ID {attach.id}: {e}")
            
            # Commit manual ya que estamos en odoo shell
            env.cr.commit()
            print("Reparación completada y cambios guardados en la base de datos.")
        else:
            print("No hay nada que reparar.")
    else:
        if missing_count > 0:
            print("AVISO: Para reparar estos errores, ejecuta el script con el flag --fix")
        else:
            print("Todo parece estar en orden.")

if 'env' in locals() or 'env' in globals():
    # Detectar si se pasó FIX_MODE en el entorno
    fix_mode = os.environ.get('FIX_MODE') == 'true'
    check_filestore(env, fix=fix_mode)
    sys.exit(0)
else:
    print("Error: Este script debe ejecutarse dentro de un entorno Odoo (odoo shell).")
