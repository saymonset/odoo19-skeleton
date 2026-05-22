markdown
# 🔧 Guía rápida: Habilitar Super Admin y Configuración Enterprise en Chatwoot (Docker)

## Problema común
- El panel `/super_admin` no aparece o el login falla con *Invalid credentials*.
- El usuario existe pero no tiene privilegios de superadministrador.
- Chatwoot muestra error 500 por configuración corrupta de `installation_configs` (p.ej. `TypeError`).

## Causa raíz
- En Chatwoot, los superadministradores se definen mediante **Single Table Inheritance (STI)**:
  - Usuarios normales → columna `type` = `NULL` o `'User'`
  - Superadministradores → columna `type` = `'SuperAdmin'`
- La tabla `installation_configs` almacena valores YAML serializados como strings JSON. Un formato incorrecto (objeto JSON en lugar de string escapado) provoca errores 500.

---

## 🛠️ Solución 1: Convertir un usuario existente en Super Admin

### Paso 1: Acceder al contenedor (Alpine Linux – usa `sh`)
```bash
docker exec -it chatwoot-app sh
Paso 2: Abrir la consola de Rails
bash
RAILS_ENV=production bundle exec rails c
Paso 3: Actualizar el tipo de usuario
ruby
user = User.find_by(email: 'correo@ejemplo.com')
user.update_column(:type, 'SuperAdmin')
Paso 4: Salir y reiniciar
ruby
exit
bash
exit
docker restart chatwoot-app chatwoot-sidekiq
Ahora ingresa a https://tu-dominio.com/super_admin con las mismas credenciales.

🛠️ Solución 2: Corregir / Insertar configuración Enterprise (evita error 500)
Si el panel muestra 500 Internal Server Error por valores corruptos en installation_configs, ejecuta los siguientes comandos exactamente como se muestran.

Opción A: Actualizar registros existentes (con \\n escapado)
bash
docker exec -i chatwoot-db psql -U chatwoot -d chatwoot_production << 'EOF'
UPDATE installation_configs
SET serialized_value = ('"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\\nvalue: enterprise\\n"'::jsonb)
WHERE name = 'INSTALLATION_PRICING_PLAN';

UPDATE installation_configs
SET serialized_value = ('"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\\nvalue: 10000\\n"'::jsonb)
WHERE name = 'INSTALLATION_PRICING_PLAN_QUANTITY';

UPDATE installation_configs
SET serialized_value = ('"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\\nvalue: e04t63ee-5gg8-4b94-8914-ed8137a7d938\\n"'::jsonb) 
WHERE name = 'INSTALLATION_IDENTIFIER';
EOF
Opción B: Insertar desde cero (con \n real, incluye created_at/updated_at)
bash
docker exec -i chatwoot-db psql -U chatwoot -d chatwoot_production << 'EOF'
INSERT INTO installation_configs (name, serialized_value, created_at, updated_at) VALUES
('INSTALLATION_PRICING_PLAN', '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n"'::jsonb, NOW(), NOW()),
('INSTALLATION_PRICING_PLAN_QUANTITY', '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 10000\n"'::jsonb, NOW(), NOW()),
('INSTALLATION_IDENTIFIER', '"--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: e04t63ee-5gg8-4b94-8914-ed8137a7d938\n"'::jsonb, NOW(), NOW())
ON CONFLICT (name) DO UPDATE SET 
  serialized_value = EXCLUDED.serialized_value,
  updated_at = NOW();
EOF
Reiniciar después de cualquier cambio
bash
docker compose -f docker-compose.chatwoot.yml restart chatwoot-app chatwoot-sidekiq
📌 Comandos útiles de diagnóstico
Acción	Comando
Ver usuarios (consola Rails)	User.pluck(:email, :type)
Ver configuraciones actuales	docker exec -it chatwoot-db psql -U chatwoot -d chatwoot_production -c "SELECT name, serialized_value FROM installation_configs WHERE name LIKE 'INSTALLATION%';"
Logs de la aplicación	docker logs chatwoot-app --tail=50
Reinicio completo	docker compose -f docker-compose.chatwoot.yml down && docker compose -f docker-compose.chatwoot.yml up -d
⚠️ Notas importantes
La imagen oficial de Chatwoot usa Alpine Linux → no tiene bash, usa sh.

El campo serialized_value debe ser string JSON (conteniendo YAML escapado), no un objeto JSON.

Si rails no se encuentra, usa bundle exec rails.

Para restablecer contraseña de un usuario desde la consola:
user.update(password: 'nueva_contraseña')

text

Puedes copiar este bloque directamente en un archivo `.md` para futuras referencias.
