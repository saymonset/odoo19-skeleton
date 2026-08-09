# Manual de instalación: Nginx + SSL delante del stack Docker

> **Propósito:** Guía reutilizable para poner **nginx como reverse proxy** (puertos 80/443 con SSL) delante del stack Docker de un cliente (Odoo, Chatwoot, n8n, Postiz, pgAdmin, Temporal UI).
> **Audiencia:** Técnicos y agentes de IA. El texto está pensado para ser seguido paso a paso.
> **Ejemplo real de referencia:** `aristosoluciones.integraia.lat` en `169.58.138.60` (IBM Cloud, Ubuntu 24.04).

---

## 0. Índice

1. [Arquitectura](#1-arquitectura)
2. [Prerrequisitos](#2-prerrequisitos)
3. [Paso 0 — DNS en Namecheap](#paso-0--dns-en-namecheap)
4. [Paso 1 — URLs de las apps](#paso-1--urls-de-las-apps)
5. [Paso 2 — Rebind de puertos a 127.0.0.1](#paso-2--rebind-de-puertos-a-127001)
6. [Paso 3 — Odoo detrás de proxy](#paso-3--odoo-detrás-de-proxy)
7. [Paso 4 — Instalar nginx + certbot](#paso-4--instalar-nginx--certbot)
8. [Paso 5 — Configuración de nginx](#paso-5--configuración-de-nginx)
9. [Paso 6 — Certificado SSL (Let's Encrypt)](#paso-6--certificado-ssl-lets-encrypt)
10. [Paso 7 — Firewall (UFW)](#paso-7--firewall-ufw)
11. [Paso 8 — Verificación](#paso-8--verificación)
12. [Solución de problemas](#12--solución-de-problemas)
13. [Cheat sheet de comandos](#13--cheat-sheet-de-comandos)
14. [Ejemplo real: aristosoluciones.integraia.lat](#14--ejemplo-real-aristosolucionesintegraialat)
15. [Variables y placeholders](#15--variables-y-placeholders)

---

## 1. Arquitectura

```
 Internet
    │
    ▼  peticiones a https://<subdominio>.<dominio-cliente>
 DNS (Namecheap)  →  A record  →  <IP_PUBLICA>
    │
    ▼
 nginx (host, puertos 80/443, TLS)
    │  reverse proxy
    ├─► 127.0.0.1:18069  Odoo http
    ├─► 127.0.0.1:18072  Odoo longpolling/websocket
    ├─► 127.0.0.1:3000   Chatwoot
    ├─► 127.0.0.1:5678   n8n
    ├─► 127.0.0.1:4007   Postiz
    ├─► 127.0.0.1:8080   pgAdmin
    └─► 127.0.0.1:8180   Temporal UI
```

**Principio clave:** una vez que nginx está delante, **ningún contenedor debe exponer puertos al público**. Todos los `ports:` se publican en `127.0.0.1` y solo nginx los alcanza. Esto protege redis, bases de datos y apps de exposición directa.

---

## 2. Prerrequisitos

| Requisito | Detalle |
|---|---|
| SO | Ubuntu 22.04 / 24.04 |
| Docker + Docker Compose | Stack desplegado y funcionando (ej.: `postiz-n8n-chatwoot-pgadmin-odoo_19`) |
| Acceso sudo | `sudo -v` sin error |
| Puertos libres | `80` y `443` (nada más escuchando) |
| Dominio | Registrado en Namecheap (o donde sea) y con A records apuntando a la IP pública |
| Puertos abiertos en el proveedor | Security Group / Firewall del proveedor (IBM, Contabo, DigitalOcean) debe permitir entrada `80` y `443` |

---

## Paso 0 — DNS en Namecheap

Para cada servicio web del cliente se crea un **A record** en la zona DNS del dominio:

| Host (Namecheap) | Tipo | Valor (IP pública del servidor) | TTL |
|---|---|---|---|
| `@` | A | `<IP_PUBLICA>` | Automatic |
| `chatwoot` | A | `<IP_PUBLICA>` | Automatic |
| `n8n` | A | `<IP_PUBLICA>` | Automatic |
| `postiz` | A | `<IP_PUBLICA>` | Automatic |
| `pgadmin` | A | `<IP_PUBLICA>` | Automatic |
| `temporal` | A | `<IP_PUBLICA>` | Automatic |

> **Importante:** El "Host" en Namecheap es relativo al dominio. Para un dominio `integralat` y host `chatwoot.aristosoluciones`, el FQDN resultante es `chatwoot.aristosoluciones.integraia.lat`.

**Verificar que el DNS resuelve a la IP del servidor** (desde el servidor):
```bash
dig +short A chatwoot.aristosoluciones.integraia.lat
# Debe imprimir: 169.58.138.60
```

**Errores comunes:**
- `NXDOMAIN` → el dominio/host **no existe** en DNS. Comprobar la zona correcta en Namecheap.
- Resuelve a otra IP → el A record apunta a otro servidor; corregir antes de continuar.
- Antes de pedir el certificado, el FQDN **debe** resolver a esta máquina, porque Let's Encrypt validará contra esa IP.

---

## Paso 1 — URLs de las apps

Las apps se configuran con su URL pública para generar enlaces, redirects y assets correctos.

Ubicación del stack (ejemplo):
```bash
cd /home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19
```

**Sustituir en los archivos siguientes** el dominio viejo por el nuevo, SOLO en variables de URL web:

| Archivo | Variables a cambiar |
|---|---|
| `.env` | `N8N_EDITOR_BASE_URL`, `CHATWOOT_FRONTEND_URL`, `CHATWOOT_RAILS_HOST`, `ASSET_HOST`, `ACTIVE_STORAGE_HOST`, `RAILS_STORAGE_HOST`, `MAIN_URL`, `FRONTEND_URL` |
| `docker-compose.chatwoot.yml` | `RAILS_HOST`, `FRONTEND_URL`, `APP_HOST`, `ASSET_HOST`, `ACTIVE_STORAGE_HOST`, `RAILS_STORAGE_HOST`, `RAILS_ASSET_HOST`, `ACTIVE_STORAGE_URL_HOST` |
| `docker-compose.n8n.yml` | `N8N_HOST`, `WEBHOOK_URL`, `N8N_EDITOR_BASE_URL` |
| `docker-compose.postiz.yml` | `MAIN_URL`, `FRONTEND_URL`, `NEXT_PUBLIC_BACKEND_URL` |

**NO tocar** las variables SMTP (`SMTP_DOMAIN`, `SMTP_USERNAME`, `MAILER_SENDER_EMAIL`, `MAIL_DOMAIN`, `ACTION_MAILER_*`), pertenecen al correo del cliente.

Ejemplo de cambio:
```diff
- N8N_HOST=n8n.aristosoluciones.com
+ N8N_HOST=n8n.aristosoluciones.integraia.lat
```

**Verificar que no quede ninguna URL web vieja** (deben quedar solo las SMTP):
```bash
grep -rn "<dominio-viejo>" .env docker-compose.chatwoot.yml docker-compose.n8n.yml docker-compose.postiz.yml
```

---

## Paso 2 — Rebind de puertos a 127.0.0.1

Para que los servicios no queden expuestos al público, se publican en `127.0.0.1`.

| Archivo | Antes | Después |
|---|---|---|
| `docker-compose.odoo.yml` | `"18069:8069"` | `"127.0.0.1:18069:8069"` |
| `docker-compose.odoo.yml` | `"18072:8072"` | `"127.0.0.1:18072:8072"` |
| `docker-compose.odoo.yml` | `"6379:6379"` | `"127.0.0.1:6379:6379"` |
| `docker-compose.n8n.yml` | `"5678:5678"` | `"127.0.0.1:5678:5678"` |
| `docker-compose.chatwoot.yml` | `"3000:3000"` | `"127.0.0.1:3000:3000"` |
| `docker-compose.postiz.yml` | `"4007:5000"` | `"127.0.0.1:4007:5000"` |
| `docker-compose.postiz.yml` | `"7233:7233"` | `"127.0.0.1:7233:7233"` |
| `docker-compose.postiz.yml` | `"8180:8080"` | `"127.0.0.1:8180:8080"` |

**Temporal UI:** si el stack define `temporal-ui` pero está comentado en `docker-compose.yaml`, descomentar su bloque `extends` para que arranque (serve el puerto `8180`).

**Aplicar los cambios** (recrea solo los contenedores afectados):
```bash
docker compose -f docker-compose.yaml config -q    # valida el YAML
docker compose -f docker-compose.yaml up -d        # recrea contenedores
```

**Verificar bindings** (todos deben estar en `127.0.0.1`):
```bash
docker ps --format '{{.Names}}: {{.Ports}}'
```

**Verificar que cada backend responde:**
```bash
for p in 18069 3000 5678 4007 8180 8080; do curl -s -o /dev/null -w "$p -> %{http_code}\n" --max-time 8 http://127.0.0.1:$p/; done
```
> Los códigos pueden variar (200/301/302/303/404/502) según la app; lo importante es que **conecte** y no dé `000` (connection refused) una vez la app terminó de arrancar.

---

## Paso 3 — Odoo detrás de proxy

Odoo necesita saber que está detrás de un reverse proxy:

1. En `v19/config/odoo.conf`:
   ```ini
   proxy_mode = True
   ```

2. Fijar la URL pública en la base de datos:
   ```bash
   docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -c \
     "UPDATE ir_config_parameter SET value='https://<SUBDOMINIO_PRINCIPAL>/' WHERE key='web.base.url';"
   ```

3. Reiniciar el contenedor web para que tome `proxy_mode`:
   ```bash
   docker compose -f docker-compose.yaml up -d --force-recreate web
   ```

4. Verificar:
   ```bash
   docker exec odoo-db19-n8n psql -U odoo -d dbodoo19 -t -c \
     "SELECT value FROM ir_config_parameter WHERE key='web.base.url';"
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:18069/
   ```

---

## Paso 4 — Instalar nginx + certbot

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nginx certbot python3-certbot-nginx
```

Comprobar instalación:
```bash
nginx -v
certbot --version
```

Arrancar y habilitar al boot:
```bash
sudo systemctl enable --now nginx
sudo systemctl is-active nginx   # debe imprimir: active
```

> Tras instalar, nginx trae un sitio por defecto (`sites-enabled/default`) que escucha en `80` con root `/var/www/html`. Sirve para validar el desafío ACME y se desactiva al desplegar el config del cliente.

---

## Paso 5 — Configuración de nginx

La configuración vive en el repo (para versionarla) y se copia a `/etc/nginx/`.

**Archivos:**
- `nginx/aristosoluciones.conf` — vhosts (upstreams + server blocks HTTP→HTTPS y HTTPS).
- `nginx/snippets/ssl.conf` — parámetros TLS compartidos.
- `nginx/snippets/letsencrypt.conf` — location del desafío ACME (para la renovación automática).

**Estructura del config principal** (por cada subdominio):

```
upstream <servicio> { server 127.0.0.1:<puerto>; }

server {                     # HTTP  → redirige a HTTPS
    listen 80;
    server_name <sub>.<dominio>;
    include snippets/letsencrypt.conf;      # sirve el desafío ACME
    location / { return 301 https://$server_name$request_uri; }
}

server {                     # HTTPS → reverse proxy
    listen 443 ssl http2;
    server_name <sub>.<dominio>;
    ssl_certificate     /etc/letsencrypt/live/<dominio>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<dominio>/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/<dominio>/chain.pem;
    include snippets/ssl.conf;
    include snippets/letsencrypt.conf;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Ssl on;

    location / {
        proxy_pass http://<servicio>;
        proxy_redirect off;
    }
}
```

**Extras por servicio** (ya incluidos en el archivo de referencia):

| Servicio | Locations adicionales |
|---|---|
| Odoo | `/websocket` y `/longpolling/` → upstream longpolling (WebSocket upgrade) |
| Chatwoot | `/cable` (WebSocket), `/rails/active_storage/` (cache 1y) |
| n8n | WebSocket upgrade en `/`, estáticos con cache 10d, gzip |
| Postiz | `/cable` (WebSocket), `/rails/active_storage/`, imágenes con cache 1y |
| pgAdmin | proxy simple |
| Temporal UI | proxy simple con WebSocket upgrade |

**Desplegar** (ajustar `<SRC>` a la ruta real del repo):
```bash
SRC=/home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19/nginx
sudo cp $SRC/snippets/ssl.conf          /etc/nginx/snippets/ssl.conf
sudo cp $SRC/snippets/letsencrypt.conf  /etc/nginx/snippets/letsencrypt.conf
sudo cp $SRC/aristosoluciones.conf      /etc/nginx/sites-available/aristosoluciones.conf
sudo ln -sf /etc/nginx/sites-available/aristosoluciones.conf /etc/nginx/sites-enabled/aristosoluciones.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t       # syntax ok + test successful
sudo systemctl reload nginx
```

> El config usa **un único certificado multi-SAN** compartido por todos los subdominios, por eso todas las directivas `ssl_certificate` apuntan al mismo directorio `/etc/letsencrypt/live/<dominio>/`.

---

## Paso 6 — Certificado SSL (Let's Encrypt)

Con nginx sirviendo el desafío desde `/var/www/html` (ver snippet `letsencrypt.conf`), se emite un único certificado con todos los subdominios:

```bash
sudo mkdir -p /var/www/html && sudo chmod 755 /var/www/html

sudo certbot certonly --webroot -w /var/www/html \
  -d <dominio> \
  -d <sub>.<dominio> \
  -d <otro-sub>.<dominio> \
  --non-interactive --agree-tos -m <EMAIL_ADMIN>
```

**Resultado esperado:**
```
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/<dominio>/fullchain.pem
```

**Requisitos:**
- Puerto `80` accesible desde Internet (el desafío ACME http-01 es por HTTP).
- El FQDN resuelve a la IP de este servidor (Paso 0).

**Renovación automática** (la instala certbot):
```bash
sudo systemctl list-timers certbot.timer   # timer activo
```
> La renovación usa el mismo método `--webroot`; por eso los server blocks HTTP incluyen `snippets/letsencrypt.conf` (no redirigen el desafío a HTTPS).

---

## Paso 7 — Firewall (UFW)

```bash
sudo ufw allow 22/tcp    # SSH — SIEMPRE PRIMERO, para no quedarse fuera
sudo ufw allow 80/tcp    # HTTP (ACME + redirect)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw --force enable
sudo ufw status
```

**Además del UFW**, el *security group / firewall* del proveedor (IBM Cloud, Contabo, DigitalOcean...) debe permitir entrada en `80` y `443`. UFW es el firewall del SO; el del proveedor es independiente.

---

## Paso 8 — Verificación

Desde el servidor (o cualquier máquina):

```bash
# 1) HTTP debe redirigir a HTTPS (301)
for d in <dominio> <sub>.<dominio> ...; do
  curl -s -o /dev/null -w "$d http -> %{http_code}\n" "http://$d/"
done

# 2) HTTPS debe responder con la app (200/301/302/303/307)
for d in <dominio> <sub>.<dominio> ...; do
  curl -sk -o /dev/null -w "$d https -> %{http_code}\n" "https://$d/"
done

# 3) El certificado contiene todos los SANs
echo | openssl s_client -connect <dominio>:443 2>/dev/null | openssl x509 -noout -text | grep -A1 "Subject Alternative Name"
```

**WebSocket (Odoo):** una petición manual incompleta suele devolver `400`; eso confirma que nginx conecta al backend longpolling. `404/400/502` indican fallo de proxy; `000` indica que el backend no escucha.

**Ejemplo de resultado correcto (caso real):**

| Subdominio | HTTP | HTTPS |
|---|---|---|
| `aristosoluciones.integraia.lat` (Odoo) | 301 | 303 |
| `chatwoot.aristosoluciones.integraia.lat` | 301 | 302 |
| `n8n.aristosoluciones.integraia.lat` | 301 | 200 |
| `postiz.aristosoluciones.integraia.lat` | 301 | 307 |
| `pgadmin.aristosoluciones.integraia.lat` | 301 | 302 |
| `temporal.aristosoluciones.integraia.lat` | 301 | 200 |

---

## 12. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| Firefox: "Server Not Found" | nginx no instalado/activo, o puerto 80/443 cerrado en el proveedor | `sudo systemctl is-active nginx`; abrir `80/443` en UFW y en el security group del proveedor |
| `dig +short` vacío / NXDOMAIN | Falta el A record o está en la zona equivocada | Revisar la zona DNS en Namecheap (Paso 0) |
| `nginx -t` falla: "cannot load certificate" | Aún no se emitió el certificado | Emitir primero con certbot (Paso 6) |
| certbot: "Failed to connect / connection refused" | Puerto 80 no accesible desde Internet | Abrir 80 en UFW y en el security group del proveedor |
| `502 Bad Gateway` | Backend caído o arrancando | `docker ps` y `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:<puerto>/` |
| `curl` devuelve `000` en un puerto interno | Contenedor no escucha aún | Esperar arranque y revisar `docker logs <contenedor>` |
| El certificado no cubre un subdominio | Falta el `-d` en certbot | Emitir de nuevo añadiendo el dominio |
| La renovación no funciona | El desafío ACME redirige a HTTPS | Confirmar que el server block HTTP incluye `snippets/letsencrypt.conf` y `root /var/www/html` |

---

## 13. Cheat sheet de comandos

```bash
# DNS
dig +short A <fqdn>

# Docker
docker compose -f docker-compose.yaml config -q
docker compose -f docker-compose.yaml up -d
docker compose -f docker-compose.yaml up -d --force-recreate web
docker ps --format '{{.Names}}: {{.Ports}}'
docker logs --tail 50 <contenedor>

# nginx
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl enable --now nginx

# certbot
sudo certbot certonly --webroot -w /var/www/html -d <dominio> -d <sub>.<dominio> ...
sudo systemctl list-timers certbot.timer

# firewall
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw --force enable && sudo ufw status

# verificación
for d in <dominio> <sub>.<dominio>; do curl -sk -o /dev/null -w "$d -> %{http_code}\n" "https://$d/"; done
```

---

## 14. Ejemplo real: aristosoluciones.integraia.lat

Cliente **Aristo Soluciones**, servidor `169.58.138.60` (IBM Cloud, Ubuntu 24.04), stack en `/home/odoo/prod/odoo19-skeleton/postiz-n8n-chatwoot-pgadmin-odoo_19`.

**DNS (zona `integraia.lat` en Namecheap):** A records `aristosoluciones`, `chatwoot.aristosoluciones`, `n8n.aristosoluciones`, `postiz.aristosoluciones`, `pgadmin.aristosoluciones`, `temporal.aristosoluciones` → `169.58.138.60`. (`lead.*` y `*.aristosoluciones.com` quedaron pendientes, sin backend/dominio.)

**Cambios aplicados:**
- URLs de apps: `*.aristosoluciones.com` → `*.aristosoluciones.integraia.lat` (`.env`, chatwoot, n8n, postiz). SMTP sin cambios.
- Puertos rebindeados a `127.0.0.1` (odoo `18069/18072`, redis `6379`, n8n `5678`, chatwoot `3000`, postiz `4007`, temporal `7233`, temporal-ui `8180`).
- `proxy_mode = True` en `v19/config/odoo.conf` + `web.base.url = https://aristosoluciones.integraia.lat`.
- nginx + certbot instalados; config en `/etc/nginx/sites-available/aristosoluciones.conf` (fuente en `nginx/` del repo).
- Certificado multi-SAN con 6 dominios, renovación automática vía `certbot.timer`.
- UFW activo: `22/80/443`.

**Comando certbot usado:**
```bash
sudo certbot certonly --webroot -w /var/www/html \
  -d aristosoluciones.integraia.lat \
  -d chatwoot.aristosoluciones.integraia.lat \
  -d n8n.aristosoluciones.integraia.lat \
  -d postiz.aristosoluciones.integraia.lat \
  -d pgadmin.aristosoluciones.integraia.lat \
  -d temporal.aristosoluciones.integraia.lat \
  --non-interactive --agree-tos -m oraclefedora@gmail.com
```

**Resultado verificado:** todos los subdominios responden por HTTPS (ver tabla del Paso 8).

---

## 15. Variables y placeholders

| Variable | Descripción | Ejemplo |
|---|---|---|
| `<IP_PUBLICA>` | IP pública del servidor | `169.58.138.60` |
| `<dominio>` | Dominio base usado para nginx/cert | `aristosoluciones.integraia.lat` |
| `<sub>.<dominio>` | Subdominio de cada servicio | `n8n.aristosoluciones.integraia.lat` |
| `<SUBDOMINIO_PRINCIPAL>` | Subdominio que sirve Odoo (root) | `aristosoluciones.integraia.lat` |
| `<EMAIL_ADMIN>` | Correo para certbot / admin | `oraclefedora@gmail.com` |
| `<puerto>` | Puerto interno del servicio | `18069` |
| `<SRC>` | Ruta del config nginx en el repo | `/home/odoo/prod/.../nginx` |
| `<dominio-viejo>` | Dominio anterior de las apps | `*.aristosoluciones.com` |

> **Seguridad:** este manual no incluye secretos (contraseñas sudo, SMTP, tokens). Los agentes de IA y técnicos deben usar placeholders o variables de entorno, nunca hardcodear credenciales en configs versionadas.
