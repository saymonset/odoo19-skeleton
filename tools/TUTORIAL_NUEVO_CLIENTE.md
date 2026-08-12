# Tutorial: Onboarding de un Cliente Nuevo

App demo multi-cliente: **un prompt a la vez** en Odoo Settings. Cada cliente se configura cambiando solo el prompt de negocio.

---

## Arquitectura (resumen)

```
Usuario WhatsApp
    │
    ▼
Chatwoot (CRM omnicanal)
    │  webhook
    ▼
n8n (workflow inmutable, NO tocar)
    │  POST /ai_chatbot_1_portal/procesar_paso
    ▼
Odoo (ai_chatbot_1_portal)
    │  devuelve modo: MENU_PRINCIPAL / FLUJO / COMPLETADO
    │
    ├── Si MENU_PRINCIPAL:
    │     n8n → POST /configuracion_agente → obtiene system_prompt
    │     n8n → envía mensaje + system_prompt a OpenAI (GPT-4o)
    │     OpenAI → devuelve JSON con output, tipoPregunta, equipo_asignado, flow_name
    │     n8n → parsea JSON, construye botones según tipoPregunta
    │     Si equipo_asignado no vacío → POST /inicioagendar → inicia flujo de captura
    │     Si equipo_asignado vacío → solo responde (sin flujo)
    │
    └── Si FLUJO/COMPLETADO:
          n8n → envía nombre_mostrar del paso actual a Chatwoot
```

**Regla de oro**: n8n NO se toca. Todo se configura desde Odoo (prompt + flujos + pasos).

---

## Paso 1: Copiar la plantilla base

```bash
cp /home/odoo/prod/odoo19-skeleton/tools/prompt_integraia_v2_modelo.txt \
   /home/odoo/prod/odoo19-skeleton/tools/prompt_[cliente].txt
```

Abrir `prompt_[cliente].txt` en un editor.

---

## Paso 2: Reemplazar datos del negocio

Reemplazar estas secciones con los datos del nuevo cliente:

### `TÚ ERES:`
- Nombre del negocio
- Qué vende/hace
- Descripción breve

### `OBJETIVO:`
- Qué vuole lograr el bot (atender, cotizar, agendar, etc.)

### `REGLA CLAVE DE VENTA:`
- Tono (formal/casual, "usted"/"tú")
- CTA obligatorio en cada respuesta

### `REGLA CLAVE DEL NEGOCIO:`
- Reglas específicas (ej: "no ofrecer UV si no lo piden")
- Fórmulas de cálculo de precios
- Montos mínimos
- Productos sin precio definido → derivar a asesor

### `QUÉ ES REALMENTE EL PRODUCTO`
- Lista de productos/servicios reales

### `BASE DE CONOCIMIENTO DE PRECIOS Y SERVICIOS`
- Todos los productos con precios y especificaciones
- Formulas de cálculo si aplica

### `MENÚ MAESTRO OFICIAL`
- Las 4 opciones del menú adaptadas al negocio
- Ej: Precios, Servicios, Agendar, Otra consulta

### `ORDEN DE PRIORIDAD PARA CLASIFICAR`
- Palabras clave para cada prioridad (4.1 PRECIOS, 4.2 SERVICIOS, etc.)
- Adaptar a los productos del negocio

### `RESPUESTAS POR REGLA`
- Un bloque `REGLA [nombre]` por cada tipo de respuesta
- Cada regla tiene: tipoPregunta, isMenu, equipo_asignado y el texto de output
- Incluir `VERSIÓN CORTA OBLIGATORIA` para PRECIOS y SERVICIOS (máx. 900 chars para Instagram/Meta)

### `EJEMPLOS DE SALIDA`
- 3-4 ejemplos con JSON completo
- Usar session_id, conversation_id, account_id, platform reales o de prueba

---

## Paso 3: NO modificar estas secciones (son técnicas)

Estas secciones se mantienen **idénticas** en todos los clientes:

- `REGLAS CRÍTICAS` (1-10) — formato JSON, límites de caracteres, claves obligatorias
- `LÓGICA ESPECIAL PARA "SÍ"` — comportamiento de confirmación
- `CONSTRUCCIÓN FINAL DEL JSON` — instrucción de output final
- La estructura de las `REGLAS CRÍTICAS` (los 10 campos del JSON)

**No incluir**:
- `=== FLUJOS DISPONIBLES ===` — Odoo lo inyecta automáticamente
- `=== FORMATO DE SALIDA OBLIGATORIO ===` — Odoo lo inyecta automáticamente
- El esquema JSON con las 10 claves al final — Odoo lo appendiza

---

## Paso 4: Verificar/crear flujos en Odoo

Los flujos existentes son **genéricos** y probablemente sirven:

| Flujo | routing_key | Uso típico |
|---|---|---|
| `flujo_agendamiento_directo` | `flujo_agendamiento_directo` | Cita/agenda directa |
| `flujo_agendamiento_precios` | `flujo_agendamiento_precios` | Consulta de precios con flujo |
| `flujo_agendamiento_servicios` | `flujo_agendamiento_servicios` | Solicitud de servicios |
| `flujo_agendamiento_otra_consulta` | `flujo_agendamiento_otra_consulta` | Derivación a asesor |
| `flujo_ventas` | `flujo_ventas` | Ventas generales |
| `flujo_agendamiento_default` | `flujo_agendamiento_default` | Fallback |

### Si el cliente necesita flujos específicos:

1. Ir a Odoo → Chatbot → Flujos → Crear
2. Campos obligatorios:
   - `name`: debe empezar con `flujo_` (ej: `flujo_cotizacion_madera`)
   - `routing_key`: defaults al `name` (no cambiar)
   - `palabras_clave`: palabras separadas por comas (ej: `madera, mdf, melamina, pino`)
   - `descripcion_intencion`: cuándo activar este flujo
3. Crear los pasos (`chatbot.paso`):
   - `nombre_interno`: ej: `solicitar_medidas`
   - `nombre_mostrar`: texto que ve el usuario
   - `tipo_dato`: text / integer / float / date / boolean / image / selection
   - `campo_destino`: key en `datos_paciente` (ej: `medidas`)
   - `es_requerido`: True/False
   - `mensaje_prompt`: texto que el bot envía para pedir el dato
   - `secuencia`: orden del paso (10, 20, 30...)
4. Pasos obligatorios recomendados: `solicitar_phone`, `solicitar_name`, `consentimiento`
5. Marcar `active=True` para que aparezca en el system_prompt

### Si los flujos existentes bastan:
- No hacer nada. Al guardar el prompt (Paso 5), `aplicar_deteccion_automatica` activará los flujos cuyas `palabras_clave` coincidan con el prompt.

---

## Paso 5: Pegar el prompt en Settings

1. Abrir Odoo → **Settings** → **Chatbot** → campo `system_prompt`
2. **Borrar** todo el contenido anterior
3. **Copiar** todo el contenido de `prompt_[cliente].txt`
4. **Pegar** en el campo `system_prompt`
5. **Guardar**

Al guardar, Odoo ejecuta automáticamente:
- `normalizar_business_prompt` → valida que el JSON schema tenga las 10 claves
- `aplicar_deteccion_automatica` → activa/desactiva flujos según las `palabras_clave` que coincidan con el prompt

> **Importante**: al cambiar el prompt, el cliente anterior deja de funcionar (es un prompt a la vez).

---

## Paso 6: Verificar con curl

```bash
# Confirmar que el system_prompt incluye el nuevo prompt + flujos activos + JSON schema
curl -s -X POST http://127.0.0.1:18069/ai_chatbot_1_portal/configuracion_agente \
  -H 'Content-Type: application/json' \
  -d '{"text":"hola","token":"OOm8oXtJ3Df03_El39HoYcor2myq7eKcg22_uxXabrg"}' \
  | python3 -m json.tool | head -30
```

Verificar:
- `system_prompt` contiene el nuevo nombre del negocio
- `=== FLUJOS DISPONIBLES ===` lista los flujos activos
- `=== FORMATO DE SALIDA OBLIGATORIO ===` tiene las 10 claves

### Test de flujos

```bash
# Iniciar un flujo (simular lo que n8n envía)
curl -s -X POST http://127.0.0.1:18069/ai_chatbot_1_portal/inicioagendar \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test_cliente","conversation_id":"1","account_id":"1","name_flow":"flujo_agendamiento_directo","equipo_asignado":"flujo_agendamiento_directo"}' \
  | python3 -m json.tool

# Procesar un paso
curl -s -X POST http://127.0.0.1:18069/ai_chatbot_1_portal/procesar_paso \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test_cliente","conversation_id":"1","account_id":"1","platform":"whatsapp","valor":"+584121234567"}' \
  | python3 -m json.tool

# Limpiar la sesión de prueba
curl -s -X POST http://127.0.0.1:18069/ai_chatbot_1_portal/session/eliminar \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"test_cliente"}' \
  | python3 -m json.tool
```

---

## Paso 7: Probar por WhatsApp

Enviar estos mensajes al número del bot y verificar:

| Mensaje | Respuesta esperada | tipoPregunta | equipo_asignado | flow_name |
|---|---|---|---|---|
| `"hola"` | Menú de bienvenida | `""` (isMenu: true) | `""` | `""` |
| `"1"` | Lista de precios del negocio | `"PRECIOS"` | `""` | `""` |
| `"2"` | Catálogo de servicios | `"SERVICIOS"` | `""` | `""` |
| `"3"` | Mensaje para agendar | `"CITA_DIRECTA"` | `""` | `""` |
| `"4"` | Solicitud de cotización a medida | `"OTRA_CONSULTA"` | `"Agendamiento_Otra_Consulta"` | `""` |
| `"sí"` (tras opción 3) | Confirmación + crea lead | `"CONFIRMACION"` | `"Agendamiento_Directo"` | `""` |

Si algo falla, revisar logs:
```bash
docker logs -f odoo-19-web 2>&1 | grep -i 'chatbot\|flujo\|procesar_paso\|inicioagendar'
```

---

## Valores permitidos

### tipoPregunta (reconocidos por n8n para construir botones)

| Valor | Botones que genera |
|---|---|
| `"CITA_DIRECTA"` | "💰 Demo Chatbot" / "🩺 Asesoría Odoo" |
| `"ESTATICO"` | "🔙 Menú" / "🚪 Salir" |
| `"RESULTADOS"` | "🔬 Laboratorio" / "📷 Imágenes" |
| `"PRECIOS"` | "✅ Quiero cotización" / "❌ No, gracias" |
| `"SERVICIOS"` | "✅ Sí, quiero demo" / "❌ No, gracias" |
| `"TARJETA"` | "✅ Sí, contratar" / "❌ No, gracias" |
| `""` o no reconocido | Sin botones (solo texto) |

### equipo_asignado (dispara flujo si no está vacío)

| Valor | Cuándo usarlo |
|---|---|
| `"Agendamiento_Directo"` | Cita/agenda directa |
| `"Agendamiento_Otra_Consulta"` | Derivación a asesor |
| `""` | Sin flujo (pregunta general) |

> Los `routing_key` de los flujos en Odoo pueden no coincidir con estos valores. El `flow_name` con prefijo `flujo_` pasa directo por n8n (passthrough). Verificar que el `flow_name` exista como `chatbot.flujo.name` en Odoo (sino `/inicioagendar` devuelve 404).

---

## Restricciones

- **No tocar n8n** — el workflow está en producción
- **Un prompt a la vez** — al pegar un prompt nuevo, el cliente anterior deja de funcionar
- **Prefijo `flujo_` obligatorio** — sin esto el flow_name no pasa por n8n como flujo directo
- **El flujo debe existir en Odoo** — sino `/inicioagendar` devuelve 404
- **No incluir catálogo de flujos ni JSON schema en el prompt** — Odoo los inyecta automáticamente
- **tipoPregunta debe ser uno de los 6 valores reconocidos** — valor no reconocido = sin botones interactivos
- **equipo_asignado vacío = sin flujo** — la IA responde directo, no se capturan datos

---

## Checklist final

- [ ] Prompt incluye nombre y descripción del negocio
- [ ] Prompt incluye todos los productos con precios
- [ ] Prompt incluye reglas del negocio (qué ofrecer, qué no, fórmulas)
- [ ] Prompt incluye MENÚ MAESTRO adaptado al negocio
- [ ] Prompt incluye ORDEN DE PRIORIDAD con palabras clave del negocio
- [ ] Prompt incluye RESPUESTAS POR REGLA (14 reglas mínimo)
- [ ] Prompt incluye VERSIONES CORTAS para PRECIOS y SERVICIOS (máx. 900 chars)
- [ ] Prompt incluye 3-4 EJEMPLOS DE SALIDA con JSON completo
- [ ] Prompt NO incluye `=== FLUJOS DISPONIBLES ===` (Odoo lo inyecta)
- [ ] Prompt NO incluye `=== FORMATO DE SALIDA OBLIGATORIO ===` (Odoo lo inyecta)
- [ ] Flujos necesarios creados en Odoo (si el negocio los requiere)
- [ ] Prompt pegado en Settings y guardado
- [ ] `/configuracion_agente` devuelve el prompt correcto
- [ ] Test de WhatsApp: hola, 1, 2, 3, 4, sí
- [ ] Logs de Odoo sin errores

---

## Archivos de referencia en `/tools/`

| Archivo | Qué es |
|---|---|
| `prompt_integraia_v2_modelo.txt` | Plantilla base con la estructura completa (copiar de aquí) |
| `prompt_aristosoluciones.txt` | Ejemplo real de AristoSoluciones (impresión gran formato) |
| `crear_multiflujos_prompt_diferentes.md` | Guía técnica detallada (arquitectura, valores de n8n, modelos Odoo) |
| `TUTORIAL_NUEVO_CLIENTE.md` | Este tutorial |