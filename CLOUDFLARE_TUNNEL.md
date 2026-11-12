# Publicación segura — Cloudflare Tunnel (Named Tunnel)

Guía para que **cualquier integrante del grupo** pueda levantar el túnel y exponer
los servicios del stack. El túnel admite **réplicas**: varios `cloudflared`
conectados simultáneamente con el mismo token. Si la máquina principal se apaga,
Cloudflare enruta el tráfico a otra réplica activa automáticamente.

> **Importante:** quien responde es la máquina que tiene el túnel activo. El
> público ve **la copia local de quien lo sirve**. La máquina "oficial" es la
> del responsable de despliegue (con el dataset 6M cargado); las demás quedan
> como respaldo de alta disponibilidad.

## Arquitectura

```
Internet → Cloudflare (TLS gratis) → Tunnel grupo13-server
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            │                             │                             │
      réplica: PC-MC               réplica: PC-Lucas              réplica: PC-Abi
            │                             │                             │
      stack local Docker           stack local Docker            stack local Docker
      (redtpfinal)                 (redtpfinal)                  (redtpfinal)
```

Los subdominios apuntan a los **nombres de servicio internos** de Docker —
funcionan igual en cualquier máquina que corra el mismo `compose.yaml`.

## Rutas configuradas (dominio hia-26.com)

| Subdominio | Destino interno | Acceso |
|---|---|---|
| `tutorias.hia-26.com` | `http://app-frontend:80` | Público |
| `glpi.hia-26.com` | `http://glpi:80` | Cloudflare Access (solo equipo) |
| `docs.hia-26.com` | `http://nextcloud:80` | Cloudflare Access (solo equipo) |
| `n8n.hia-26.com` | `http://n8n:5678` | Cloudflare Access (solo equipo) |
| `monitor.hia-26.com` | `http://prometheus:9090` | Cloudflare Access (solo equipo) |

## Prerequisitos

1. Tener el stack levantado: `docker compose up -d`
2. Tener el **TUNNEL_TOKEN** — se comparte por canal seguro del equipo
   (Nextcloud/WhatsApp). **NUNCA se commitea** (`.env` está en `.gitignore`).

## Opción A — Servicio del compose (recomendada, sin instalar nada)

1. Agregar al `.env` local:

   ```env
   TUNNEL_TOKEN=eyJhIjoi...<token compartido>
   ```

2. Levantar solo el conector:

   ```powershell
   docker compose up -d cloudflared
   ```

3. Verificar que conectó:

   ```powershell
   docker logs tp_final_hia_grupo13-cloudflared-1 --tail 20
   # Debe mostrar: "Registered tunnel connection" (x4)
   ```

## Opción B — cloudflared local (Windows)

1. Instalar (una de las dos):

   ```powershell
   winget install --id Cloudflare.cloudflared
   ```

   o descargar el MSI desde https://github.com/cloudflare/cloudflared/releases
   (`cloudflared-windows-amd64.msi`).

2. Correr con el token:

   ```powershell
   cloudflared tunnel --no-autoupdate run --token eyJhIjoi...<token>
   ```

   Dejar la terminal abierta; cerrarla apaga la réplica.

## Verificar

- Dashboard Cloudflare → **Networks → Tunnels → grupo13-server**:
  columna **Replicas** muestra cuántas máquinas están conectadas.
- `https://tutorias.hia-26.com` debe responder desde cualquier dispositivo.

## Notas

- El token **no expira** pero se puede rotar desde el dashboard
  (tunnel → Rotate token) — invalida todas las réplicas hasta que se
  actualice el `.env`.
- Si el túnel responde `502`: el servicio destino de esa ruta está caído
  en la máquina que está sirviendo (revisar `docker compose ps`).
- Si `app.` responde distinto según el momento, hay varias réplicas con
  datos diferentes — bajar la réplica que no corresponde
  (`docker compose stop cloudflared`).
- Configuración completa del dominio y Cloudflare Access:
  `SERVIDOR_CONFIG.md`, sección "Publicación segura".
