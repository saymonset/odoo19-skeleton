# Fix: Error #131009 al enviar menú interactivo de WhatsApp

## Síntoma

Un usuario pregunta algo que dispara una respuesta larga de la IA (típicamente **"¿cuánto cuesta?"**). El nodo **`Enviar menú interactivo a WhatsApp1`** del workflow `chatbot_create_lead_0_con_menu_whatsapp` se pone **en rojo** en n8n, la respuesta nunca llega a WhatsApp y hay que responder manual.

## Error exacto (de la BD de n8n)

```
(#131009) Parameter value is not valid
Bad request - please check your parameters
```

## Causa raíz

WhatsApp Cloud API limita el campo `interactive.body.text` a **1024 caracteres**.

En el Code node **`Construir_botones_WhatsApp`** el payload del menú interactivo se arma así:

```js
interactive: { type: "button", body: { text: outputText }, action: { buttons: botones } }
```

`outputText` es la respuesta completa de la IA. Cuando pasa de 1024 caracteres (la plantilla de precios generó **1200**), Meta rechaza el mensaje con `#131009` y el nodo queda en rojo.

## Fix aplicado (09-ago-2026)

El nodo `Construir_botones_WhatsApp` ahora trunca el texto a 1024 con elipsis:

```js
body: { text: outputText.length > 1024 ? outputText.slice(0, 1021) + "…" : outputText },
```

Workflow: `chatbot_create_lead_0_con_menu_whatsapp` (ID `rawHArcQkOt5uVmz`) — versión `50704a05-f3ea-4487-9e8d-693ef4085d02`.

Se aplicó vía actualización directa de BD (`workflow_entity` + `workflow_history`) con n8n detenido. El truncado queda verificable en el `jsCode` guardado y el nodo carga activo al reiniciar.

> **La ruta del repo:** este entorno vive en `/home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/` (hay rutas viejas documentadas como `/home/odoo/modulos_odoo/`; no existen).

## Qué hacer en futuras instalaciones / restauraciones

1. **Al restaurar** un backup de n8n (`9_4_restore_solo_n8n.sh`) o recrear la instalación, verifica que el nodo `Construir_botones_WhatsApp` contenga el truncado. El backup puede traer la versión vieja sin fix.

2. **Verificación rápida** — en BD de n8n:

   ```bash
   docker exec odoo-db19-n8n psql -U odoo -d db_n8n -t -A -c "SELECT \"versionId\" FROM workflow_entity WHERE id='rawHArcQkOt5uVmz';"
   ```

   Si no muestra `50704a05-...` o el código del nodo no tiene `outputText.slice`, reaplica el truncado.

3. **Reaplicar manual vía UI de n8n** (más simple que BD): editar el Code node `Construir_botones_WhatsApp`, reemplazar la línea `body: { text: outputText },` por la versión truncada, guardar y reactivar el workflow.

4. **Texto exacto que debe estar en el `jsCode` del nodo**:

   ```js
   body: { text: outputText.length > 1024 ? outputText.slice(0, 1021) + "…" : outputText },
   ```

5. **Prevención**: WhatsApp permite hasta **4096 caracteres** en mensajes de texto comunes. Si en el futuro el menú interactivo no es imprescindible, considera enviar textos largos como mensaje plano y usar botones solo en respuestas cortas (evita el truncado y conserva la info completa).

## Verificación post-fix

Enviar "¿cuánto cuesta?" desde un número de WhatsApp de prueba. El menú interactivo debe llegar truncado a 1024 y el nodo `Enviar menú interactivo a WhatsApp1` debe quedar en verde. Confirmar también en BD:

```bash
docker exec odoo-db19-n8n psql -U odoo -d db_n8n -c \
  "SELECT id, status, \"startedAt\" FROM execution_entity WHERE status='error' ORDER BY \"startedAt\" DESC LIMIT 5;"
```