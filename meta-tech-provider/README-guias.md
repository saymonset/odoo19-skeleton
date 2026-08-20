# Guía: editar el sitio integraia.lat en el Website editor de Odoo 19

Acceso: entra en `https://integraia.lat/web`, inicia sesión con tu usuario admin y abre el menú **Sitio web** (Website).

---

## 1. Corregir el footer (mailto, tel, copyright, link duplicado)

1. Abre cualquier página (p. ej., la home) y haz clic en **Editar** (arriba a la derecha).
2. En la barra superior del editor, abre el desplegable **Personalizar** → **Editar Footer** (o desplázate al pie de página y haz clic sobre él).
3. Corrige:
   - **Email**: clic en el enlace del correo → en el panel de la derecha cambia `mailto:info@yourcompany.example.com` por `mailto:admin@integraia.lat`.
   - **Teléfono**: cambia `tel:+1 555-555-5556` por `tel:+584129141074`.
   - **Copyright**: reemplaza "All rights reserved © integraiaconodoo" por `© 2026 IntegraIA · Developer Software con IA · RIF V-127601875`.
   - En la columna "Useful Links", **elimina** el enlace "Terms of Service" que apunta a `/en/terms` (es el duplicado de TikTok). Deja solo los enlaces del menú.
4. Clic en **Guardar**.

## 2. Eliminar la página `/en/terms` (la de TikTok)

1. En el menú **Sitio web** ve a **Sitio web → Páginas** (Website → Pages) y busca "Terms & Conditions" (slug `terms`).
2. Selecciona la página y haz clic en **Eliminar** (o actívala en modo borrador/despublicar).
3. Confirma. El footer ya no apunta a ella tras el paso 1.

## 3. Reemplazar el contenido de Términos de Servicio (`/en/terms-of-service`)

1. Abre la página `/en/terms-of-service` y haz clic en **Editar**.
2. Borra el contenido actual y pega el texto del archivo `meta-tech-provider/terms-of-service.md`.
3. Aplica formato sencillo (encabezados H2 para cada sección, texto plano para el resto).
4. **Guardar**.

## 4. Reemplazar el contenido de Política de Privacidad (`/en/privacy-policy`)

1. Abre `/en/privacy-policy` → **Editar**.
2. Borra el contenido actual y pega `meta-tech-provider/privacy-policy.md`.
3. **Guardar**.

## 5. Crear la página `/data-deletion` (Eliminación de datos)

1. En el menú **Sitio web** → **Nueva página** (New Page).
2. Nombre: `Eliminación de datos` → URL: `data-deletion`.
3. Pega el contenido de `meta-tech-provider/data-deletion.md`.
4. **Publicar** y añade el enlace "Eliminación de datos" en el footer (junto a Privacy).

## 6. SEO de la home (meta description + OG)

1. Abre la home → **Editar**.
2. En el panel derecho usa el botón **SEO** (icono de engranaje/búsqueda).
3. En "Descripción SEO" y "Descripción para redes sociales" pega:

   > IntegraIA: agente de IA que atiende y deriva consultas por WhatsApp a cada área de tu empresa. Automatiza ventas, inventario y facturación 24/7.

4. **Guardar**.

## 7. Canonical/OG en https (dominio del sitio)

1. Ve a **Ajustes → Sitio web** (Settings → Website) y en la sección del sitio revisa el campo **Dominio** / Website URL.
2. Asegúrate de que sea `https://integraia.lat` (con `https://`). Guarda.
3. Si el tráfico ya entra por https (Cloudflare/nginx), esto corrige los `og:url` y `canonical` que hoy usan `http://`.

## 8. Menú "Clients"

1. En **Sitio web → Menús** (Website → Menus), localiza el elemento "Clients".
2. Cambia su URL a `/en/about-us` (o elimínalo del menú).

---

## App Dashboard de Meta (integraiaconodooapp — ID 1425520542363410)

1. **Ícono**: sube `meta-tech-provider/icon-app-1024x1024.png` (1024×1024, 28 KB).
2. **URL de Condiciones del servicio**: `https://integraia.lat/en/terms-of-service`
3. **URL de la política de privacidad**: `https://integraia.lat/privacy-policy`
4. **URL de Eliminación de datos**: `https://integraia.lat/data-deletion`
5. **Categoría**: cambia "Redes sociales y citas" por **Negocios** (o **Comunicación**).
6. Añade el producto/caso de uso **WhatsApp** → conecta el portfolio **Integraia** (ID `2096167304123947`) → crea la WABA con tu número → configura **Webhooks**.
7. Cuando Meta apruebe la **verificación del negocio**, inicia la **Access Verification (Tech Provider)** en la app, y después el **App Review** (acceso avanzado a `whatsapp_business_messaging` y `whatsapp_business_management`, con los 2 videos).