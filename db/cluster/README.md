# Clúster PostgreSQL de Alta Disponibilidad y Replicación (Patroni + etcd + HAProxy)

Este módulo implementa la solución de alta disponibilidad y tolerancia a fallos para la base de datos PostgreSQL del proyecto (**PT-25 / Sprint 2**), basada en el estándar industrial con **Patroni**, **etcd** y **HAProxy**.

---

## 1. Arquitectura del Clúster

- **Nodos de Base de Datos:**
  - `db_node1` (servicio `node1`)
  - `db_node2` (servicio `node2`)
  - `db_node3` (servicio `node3`)
  - Construidos a partir de `postgres:16` con Python 3 y `patroni[etcd3]`.
  - Replicación por streaming física con slots de replicación y `use_pg_rewind: true`.
  - API REST de Patroni en el puerto `8000` (interno).

- **Coordinador Distribuido (DCS):**
  - `cluster_etcd` (servicio `etcd` en `quay.io/coreos/etcd:v3.5.0`): almacena el estado del clúster, gestiona el quórum y la adquisición del candado de liderazgo (*leader lock* con TTL de 30s).

- **Balanceador y Proxy de Acceso:**
  - `cluster_proxy` (servicio `proxy` con `haproxy:2.9-alpine`):
    - Monitorea la salud de cada nodo mediante llamadas HTTP `GET /master` al puerto 8000 de Patroni.
    - Dirige dinámicamente todo el tráfico transaccional al nodo que tenga el rol de **Leader**.
    - Expone el panel de estadísticas en `http://localhost:7000/stats`.
    - Actúa con el alias de red `postgres` en la red `redtpfinal` para que el `backend`, `pgAdmin` y `postgres-exporter` se conecten de forma transparente sin exponer credenciales ni puertos directos.

- **Seguridad (Zero Exposure):**
  - **Ningún puerto de PostgreSQL (5432) se expone directamente al host de Windows**.
  - Toda la comunicación de base de datos se mantiene aislada dentro de la red Docker privada `redtpfinal`.
  - El único punto de entrada externo es el proxy seguro de HAProxy en el puerto `5465` (configurable vía `DB_PROXY_PORT`) y estadísticas en `7000`.

---

## 2. Variables de Entorno requeridas (`.env`)

Las credenciales del clúster deben definirse en el archivo local `.env` (el cual está excluido del repositorio por seguridad):

- `DB_PROXY_PORT`: Puerto de conexión externa de HAProxy (ej. `5465`).
- `DB_ADMIN_USER`: Nombre del usuario administrador para Patroni.
- `DB_ADMIN_PASSWORD`: Contraseña del usuario administrador.
- `DB_REPL_USER`: Usuario exclusivo para el canal de replicación.
- `DB_REPL_PASSWORD`: Contraseña del usuario de replicación.
- `DB_APP_USER`: Usuario para conexiones de aplicación.
- `DB_APP_PASSWORD`: Contraseña de aplicación.
- `DB_MONITOR_USER`: Usuario para el exportador de Prometheus.
- `DB_MONITOR_PASSWORD`: Contraseña de monitorización.

---

## 3. Comandos de Gestión y Pruebas

### 3.1 Iniciar el Clúster
```bash
docker compose up -d etcd node1 node2 node3 proxy
```

### 3.2 Verificar el Estado de los Nodos (Patronictl)
```bash
docker exec -it db_node1 patronictl -c /etc/patroni/patroni.yml list
```

### 3.3 Probar Conmutación Automática por Falla (Failover)
1. Detener el nodo primario actual:
   ```bash
   docker stop db_node3
   ```
2. Consultar el estado del clúster desde una réplica:
   ```bash
   docker exec -it db_node1 patronictl -c /etc/patroni/patroni.yml list
   ```
   *Patroni detectará la pérdida del lock en etcd y promoverá automáticamente a `node1` o `node2` como nuevo Leader.*

3. Recuperar el nodo caído:
   ```bash
   docker start db_node3
   ```
4. Verificar que se reincorpora automáticamente como réplica mediante `pg_rewind`:
   ```bash
   docker exec -it db_node1 patronictl -c /etc/patroni/patroni.yml list
   ```

### 3.4 Panel de Monitoreo HAProxy
Acceder desde el navegador web a:
- URL: `http://localhost:7000/stats`
