# GUÍA DE CONFIGURACIÓN PARA UN CLIENTE NUEVO (para tontos 😄)

Esta guía explica **dónde viven los tokens y URLs** de este stack (Odoo 19 + n8n +
Chatwoot + Postiz) y cómo cambiarlos para un cliente nuevo, sea con el script
automático o a mano.

---

## 1) LO PRIMERO: ¿DÓNDE ESTÁ CADA COSA?

| Dato | ¿Dónde se guarda? | ¿Quién lo usa? |
|---|---|---|
| **Token de Chatwoot** (`api_access_token`) | `docker-compose.chatwoot.yml` → `API_AUTH_TOKEN` + `.env` → `CHATWOOT_API_TOKEN` + **workflows n8n (JSON)** | Chatwoot valida quién puede enviar mensajes por API. Los workflows de n8n lo mandan en el header para responder mensajes. |
| **URL de Chatwoot** | `docker-compose.chatwoot.yml` (RAILS_HOST, FRONTEND_URL, ASSET_HOST...) + `.env` `CHATWOOT_FRONTEND_URL` + **workflows n8n**: `https://chatwoot.integraia.lat/api/v1/...` | n8n envía mensajes a `chatwoot.<dominio>/api/v1/...` |
| **URL de n8n** | `docker-compose.n8n.yml` (`N8N_HOST`, `N8N_EDITOR_BASE_URL`) + `.env` `N8N_EDITOR_BASE_URL` | El webhook/editor de n8n. |
| **URL de Odoo (el backend del bot)** | **workflows n8n**: `https://integraia.lat/ai_chatbot_1_portal/...` (3 nodos HTTP Request) | El bot consulta Odoo para saber el estado de la conversación (paso, flujo, etc.). |
| **Token entre n8n ↔ Odoo** (`CHATBOT_API_TOKEN`) | `docker-compose.n8n.yml` → `CHATBOT_API_TOKEN` (hardcodeado) | Odoo valida las llamadas que le hace n8n. Debe coincidir con el token que Odoo espera (módulo `ai_chatbot_1_portal`). |
| **SMTP (correos)** | `.env` (`SMTP_*`, `ACTION_MAILER_*`) | Chatwoot (envíos de correo) y Postiz (notificaciones). |
| **Passwords "de sistema"** | Carpeta `secrets/*.txt` | PostgreSQL, login de n8n, llave de cifrado de n8n, master key de Chatwoot. |
| **API keys de Postiz** (OpenAI, Instagram, FB, TikTok, YouTube...) | `.env` | Postiz publica/automatiza en redes sociales. |

> Regla de oro: **si un valor cambia, cambialo en TODOS los lugares a la vez.**
> El más fácil de olvidar es el de los workflows de n8n (JSON), porque está
> hardcodeado dentro del archivo.

---

## 2) EL MÉTODO FÁCIL: SCRIPT AUTOMÁTICO (recomendado)

```bash
./configure_new_client.sh
```

Te pregunta: dominio, token de Chatwoot, SMTP → y reemplaza todo solo en
`.env`, `docker-compose.chatwoot.yml`, `docker-compose.n8n.yml` y (si le dices
que sí) en los workflows JSON de n8n.

Antes de tocar nada hace un **backup** en `backup_config_<fecha>/`.

**Lo único que el script NO hace** (porque no se puede automatizar) lo imprime
al final: cambiar los archivos de `secrets/`, apuntar los DNS/nginx, y reiniciar.

---

## 3) EL MÉTODO MANUAL: 5 PASOS

### Paso 1 — Editar `.env`
Abrir y cambiar:
- `CHATWOOT_API_TOKEN` → token nuevo (en la UI de Chatwoot: *Settings →
  Account → API tokens* → `Create API token`).
- `CHATWOOT_FRONTEND_URL`, `ASSET_HOST`, `ACTIVE_STORAGE_HOST`,
  `RAILS_STORAGE_HOST` → `https://chatwoot.<dominio-del-cliente>`
- `N8N_EDITOR_BASE_URL` → `https://n8n.<dominio-del-cliente>`
- `MAIN_URL`, `FRONTEND_URL` → `https://postiz.<dominio-del-cliente>`
- Todo el bloque `SMTP_*` / `ACTION_MAILER_*` → correo del cliente.
- `BACKUP_NOTIFY_TO` → correo donde llegan alertas de backup.

### Paso 2 — Editar `docker-compose.chatwoot.yml`
Buscar y reemplazar el dominio viejo por el del cliente:
- `chatwoot.integraia.lat` → `chatwoot.<dominio>` (aparece en RAILS_HOST,
  FRONTEND_URL, ASSET_HOST, ACTIVE_STORAGE_HOST, RAILS_STORAGE_HOST,
  APP_HOST, RAILS_ASSET_HOST, ACTIVE_STORAGE_URL_HOST).
- `API_AUTH_TOKEN: yvJxkWhi...` → token nuevo (debe ser **el mismo** del `.env`).

### Paso 3 — Editar `docker-compose.n8n.yml`
- `N8N_HOST` / `WEBHOOK_URL` / `N8N_EDITOR_BASE_URL` → `n8n.<dominio>`.
- (Opcional) `CHATBOT_API_TOKEN` si cambias el token de Odoo.

### Paso 4 — Editar los workflows de n8n (¡el más olvidado!)
Abrir `n8n/chatbot_create_lead_0_con_menu_whatsapp.json` y `n8n/chatbot-simple_1_subflow.json`.

Hay **2 formas**:

**a) Directo en el archivo JSON** (igual que el script):
```bash
# Reemplazar dominio de Chatwoot
sed -i 's|chatwoot.integraia.lat|chatwoot.MIDOMINIO|g' n8n/chatbot_create_lead_0_con_menu_whatsapp.json

# Reemplazar token de Chatwoot
sed -i 's|yvJxkWhiTMioFgKTZTq3ZE3h|MITOKEN_NUEVO|g' n8n/chatbot_create_lead_0_con_menu_whatsapp.json

# Reemplazar lo que apunta al dominio de Odoo (backend del bot)
sed -i 's|https://integraia.lat/ai_chatbot|https://MIDOMINIO/ai_chatbot|g' n8n/chatbot_create_lead_0_con_menu_whatsapp.json
```

**b) Desde la UI de n8n** (si ya desplegaste):
1. Ir a la carpeta de workflows de n8n.
2. Abrir el workflow `chatbot_create_lead_0_con_menu_whatsapp`.
3. Buscar los nodos que dicen `Enviar_mensaje_de_IA*` → campo `URL`:
   `https://chatwoot.integraia.lat/api/v1/accounts/...` y el header
   `api_access_token`.
4. Idem en el subflow `chatbot-simple_1_subflow` → nodo `Consultar_estado_Odoo`
   (URL `https://integraia.lat/ai_chatbot_1_portal/procesar_paso`).
5. Guardar y **activar** el workflow.

> ⚠️ Si después de guardar el JSON los nodos se ven "reseteados", a veces hay
> que ajustar desde la UI porque n8n regenera IDs al importar.

### Paso 5 — Secrets, DNS, y reinicio
- `secrets/postgres_password.txt` → password de la BD (debe coincidir con
  `POSTGRES_PASSWORD` del `.env`).
- Crear entradas DNS/nginx para `n8n.<dominio>` (5678), `chatwoot.<dominio>`
  (3000) y `postiz.<dominio>` (4007) con certificados SSL.
- Reiniciar:
  ```bash
  ./5_res_start-all.sh
  ```

---

## 4) RESUMEN: DÓNDE "SACA" EL CHATBOT CADA TOKEN

| Qué pregunta el bot | De dónde sale | Archivo |
|---|---|---|
| ¿A dónde envío la respuesta del bot? | URL de Chatwoot | workflow n8n (nodo `Enviar_mensaje_de_IA*`) |
| ¿Quién soy para Chatwoot? | `api_access_token` | workflow n8n (header) = `CHATWOOT_API_TOKEN` en `.env` |
| ¿Cuál es el estado de la conversación? | URL de Odoo | workflow n8n (nodo `Consultar_estado_Odoo` / `paso_0_inicio_agendar`) |
| ¿Me autentico contra Odoo? | `CHATBOT_API_TOKEN` | `docker-compose.n8n.yml` (variable de entorno del contenedor n8n) |

**Si el bot "no responde", revisa en este orden:**
1. Token de Chatwoot (workflow JSON + `.env` + compose) → error 401.
2. URL de Chatwoot → error 404/connection.
3. URL de Odoo (`ai_chatbot_1_portal`) → si n8n no alcanza Odoo.
4. Webhook `Entrar_ChattWoot` (path `chatwoot_integraia`) activado → si no llegan mensajes al bot.
5. Redis (`redis123`) → si el buffer/cache no funciona.

---

## 5) PREGUNTAS FRECUENTES

**¿Puedo cambiar solo el token de Chatwoot sin tocar el resto?**
Sí: edita `CHATWOOT_API_TOKEN` en `.env`, `API_AUTH_TOKEN` en el compose y
`api_access_token` en el workflow JSON. Los 3 deben llevar el mismo valor.

**¿Por qué mi bot responde pero no guarda el estado?**
Revisa la URL de Odoo en el workflow (nodo `Consultar_estado_Odoo`). Si el
dominio de Odoo cambió, n8n sigue apuntando al viejo.

**¿Cómo consigo el token de Chatwoot?**
En la UI de Chatwoot: *Settings → Account → API tokens → Create API token*.
Es el token que usan n8n y el módulo de Odoo para hablar con Chatwoot.