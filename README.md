# Proyecto Final HIA - Grupo 13

Repositorio unificado para el trabajo final de la materia Infraestructura (HIA). Este proyecto integra el frontend, backend, herramientas de gestión y un clúster de base de datos de alta disponibilidad en un único entorno orquestado con Docker Compose.

## Equipo de Trabajo y Roles

- **Lucas Zerpa:** Arquitectura y Despliegue (Git, Docker, CI/CD)
- **Matías Churquina:** Redes y Ciberseguridad
- **Rodrigo Guanactolay:** Base de Datos Core (PostgreSQL, Optimización)
- **Luján Cansino:** Alta Disponibilidad y Monitoreo
- **Abigail Terán:** Operaciones y Automatización (Ops)

---

## Arquitectura de Contenedores (Docker)

El proyecto se despliega a través de un único archivo compose.yaml que orquesta 21 servicios interconectados mediante dos redes internas (redtpfinal y red-patroni):

1. **Clúster PostgreSQL (Patroni):** 3 nodos de base de datos, etcd para el consenso, y HAProxy como balanceador de carga en el puerto 5465.
2. **Aplicación Core:** Frontend (Angular) y Backend (Node.js).
3. **Observabilidad:** Prometheus, Alertmanager, cAdvisor, Exporters individuales por nodo y Grafana.
4. **Gestión y Ops:** Nextcloud (documentos), GLPI (incidencias) y n8n (automatización con IA).
5. **Seguridad Perimetral:** Cloudflare Tunnel (cloudflared) para acceso externo seguro mediante subdominios.

---

## Ejecución del Proyecto (Entorno de Producción)

Para levantar la infraestructura completa, asegúrese de tener configurado el archivo .env en la raíz del proyecto.

1. Clonar el repositorio y posicionarse en la rama principal.
2. Ejecutar el despliegue orquestado mediante el comando `docker compose up -d`.
3. Para detener la infraestructura de forma segura, utilizar `docker compose stop`.

---

## Credenciales de Acceso

Por normativas de seguridad (DevSecOps) y para evitar la exposición de datos sensibles, **las credenciales de acceso no se incluyen en este repositorio público.**

### 1. Sistema de Incidencias (GLPI)
- **Arquitectura (Admin):** dev.ops (Lucas Zerpa)
- **Redes:** dev.sec (Matias Churquina)
- **Base de Datos:** dev.dba (Rodrigo Guanactolay)
- **Monitoreo:** dev.mon (Lujan Cansino)
- **Automatización:** dev.auto (Abigail Terán)
- **Usuario Prueba 1:** usuario1 (Martina Castillo)
- **Usuario Prueba 2:** usuario2 (Maria Gonzales)
- **Soporte:** soporte (Juan Perez)

---
*Consulte la carpeta raíz para acceder a la documentación técnica detallada de cada módulo (Redes, Rollbacks, Configuración de Servidor).*