# Configuración del Servidor Local

## Especificaciones

- **OS:** Microsoft Windows 11 Home (10.0.26200)
- **RAM:** 7.502 MB
- **CPU:** AMD64 Family 23 Model 104 Stepping 1 AuthenticAMD ~2100 MHz (1 procesador)
- **Disco:** KBG40ZNV256G KIOXIA 256 GB (256052966400 bytes)
- **Docker:** version 29.7.2, build a7dcaa6
- **Docker Compose:** version v5.4.0

## Análisis de Puertos

### 🔴 Puertos Ocupados (Requieren acción)

| Puerto | Estado | Servicio Actual | PID | Conflicto | Solución |
|--------|--------|-----------------|-----|----------|----------|
| 5432 | LISTENING | PostgreSQL local | 9732 | ✅ Sí | Cambiar a 5434 en docker-compose |
| 5050 | UDP | Desconocido | 6088 | ✅ Sí | Cambiar a 5051 en docker-compose |

### 🟢 Puertos Disponibles

| Puerto | Estado | Servicio | Observaciones |
|--------|--------|----------|---------------|
| 80 | Tráfico HTTPS | Cloudflare Tunnel | Hay conexiones HTTPS existentes |
| 443 | Tráfico HTTPS | Cloudflare Tunnel | MUCHAS conexiones (GitHub, Cloudflare, etc.) |
| 3000 | Disponible | Backend | Libre |
| 4200 | Disponible | Frontend dev | Libre |
| 9090 | Disponible | Prometheus | Libre |
| 3001 | Disponible | Grafana | Libre |
| 5678 | Disponible | n8n | Libre |
| 8080 | Disponible | GLPI | Libre |
| 8081 | Disponible | Nextcloud | Libre |

### 📋 Puertos Configurados (Con ajustes)

| Puerto Host | Puerto Contenedor | Servicio | Estado | Nota |
|-------------|------------------|----------|--------|------|
| 80 | 80 | Frontend (nginx) | ✅ Disponible | Usado por Cloudflare Tunnel |
| 443 | 443 | HTTPS (Cloudflare) | ✅ Disponible | Usado por Cloudflare Tunnel |
| 3000 | 3000 | Backend | ✅ Disponible | Libre |
| 4200 | 4200 | Frontend dev | ✅ Disponible | Libre |
| 5434 | 5432 | PostgreSQL Primary | ✅ Disponible | **Cambiado de 5432** |
| 5435 | 5432 | PostgreSQL Replica | ✅ Disponible | **Cambiado de 5433** |
| 5051 | 80 | pgAdmin | ✅ Disponible | **Cambiado de 5050** |
| 9090 | 9090 | Prometheus | ✅ Disponible | Libre |
| 3001 | 3001 | Grafana | ✅ Disponible | Libre |
| 5678 | 5678 | n8n | ✅ Disponible | Libre |
| 8080 | 8080 | GLPI | ✅ Disponible | Libre |
| 8081 | 8081 | Nextcloud | ✅ Disponible | Libre |

## Firewall

- [x] Reglas de entrada configuradas
- [x] Reglas de salida configuradas
- [x] Puertos permitidos: 80, 443, 3000, 4200, 5434, 5435, 5051, 9090, 3001, 5678, 8080, 8081
- [x] Puertos bloqueados: resto

### Reglas Creadas (12 reglas)

✅ Todas las reglas creadas exitosamente

1. ✅ Permitir HTTP (80) - Enabled: True, Status: OK
2. ✅ Permitir HTTPS (443) - Enabled: True, Status: OK
3. ✅ Permitir Backend (3000) - Enabled: True, Status: OK
4. ✅ Permitir Frontend Dev (4200) - Enabled: True, Status: OK
5. ✅ Permitir PostgreSQL Primary (5434) - Enabled: True, Status: OK
6. ✅ Permitir PostgreSQL Replica (5435) - Enabled: True, Status: OK
7. ✅ Permitir pgAdmin (5051) - Enabled: True, Status: OK
8. ✅ Permitir Prometheus (9090) - Enabled: True, Status: OK
9. ✅ Permitir Grafana (3001) - Enabled: True, Status: OK
10. ✅ Permitir n8n (5678) - Enabled: True, Status: OK
11. ✅ Permitir GLPI (8080) - Enabled: True, Status: OK
12. ✅ Permitir Nextcloud (8081) - Enabled: True, Status: OK

### Verificación

Comando ejecutado:
```powershell
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "Permitir*"} | Select-Object DisplayName, Direction, Action, Enabled
```

Resultado: Todas las reglas activas y funcionando correctamente.

## Docker

- [x] Docker Desktop corriendo
- [x] Docker Compose funcionando
- [ ] Red Docker creada (app-network) - Pendiente de creación en docker-compose
- [ ] Volúmenes configurados - Pendiente de configuración en docker-compose

### Verificación

```bash
docker --version
# Output: Docker version 29.7.2, build a7dcaa6

docker-compose --version
# Output: Docker Compose version v5.4.0

docker ps
# Output: Lista de contenedores corriendo (actualmente vacío)
```

## Pruebas

- [x] docker ps funciona
- [x] docker-compose --version funciona
- [x] Puertos no tienen conflictos (ajustados en docker-compose)
- [x] Firewall configurado correctamente

## Cambios Requeridos en docker-compose.yml

Para evitar conflictos de puertos, actualizar las siguientes líneas en `docker-compose.yml`:

```yaml
services:
  db-primary:
    ports:
      - "5434:5432"  # Cambiado de 5432 a 5434

  db-replica:
    ports:
      - "5435:5432"  # Cambiado de 5433 a 5435

  pgadmin:
    ports:
      - "5051:80"  # Cambiado de 5050 a 5051
```

## Variables de Entorno (.env)

Actualizar las variables de entorno para reflejar los nuevos puertos:

```env
# PostgreSQL Primary
DB_HOST=db-primary
DB_PORT=5434  # Puerto host

# PostgreSQL Replica
DB_REPLICA_HOST=db-replica
DB_REPLICA_PORT=5435  # Puerto host

# pgAdmin
PGADMIN_PORT=5051
```

## Pasos Siguientes (Mañana con equipo)

1. [ ] Actualizar docker-compose.yml con puertos corregidos (Lucas)
2. [ ] Actualizar .env con puertos corregidos (Rodrigo)
3. [ ] Probar docker-compose up -d
4. [ ] Verificar que todos los contenedores inicien
5. [ ] Verificar acceso a cada servicio
6. [ ] Documentar resultados

## Responsable

- **Matias (MC)** - Preparación del servidor local ✅ COMPLETADO HOY
- **Lucas** - Actualización de docker-compose.yml (pendiente)
- **Rodrigo** - Actualización de variables de entorno (pendiente)

## Fecha de Actualización

4 de noviembre de 2026

## Estado de PT-13

✅ **COMPLETADO HOY:**
- [x] Ejecutar comandos de verificación
- [x] Documentar especificaciones del servidor
- [x] Verificar puertos disponibles
- [x] Analizar conflictos de puertos
- [x] Configurar firewall
- [x] Actualizar SERVIDOR_CONFIG.md

⏳ **PENDIENTE (Mañana con equipo):**
- [ ] Actualizar docker-compose.yml con puertos corregidos
- [ ] Actualizar .env con puertos corregidos
- [ ] Probar docker-compose up -d
- [ ] Verificar que todos los contenedores inicien