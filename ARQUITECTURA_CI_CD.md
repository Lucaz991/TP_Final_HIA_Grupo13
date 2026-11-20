# Arquitectura del Repositorio y Pipeline CI/CD

Este documento detalla la estrategia de gestión de código fuente y automatización implementada para el Proyecto Final HIA, garantizando la calidad y seguridad del desarrollo continuo del Grupo 13.

## 1. Estrategia de Ramas (Git Flow Simplificado)

Para organizar el trabajo de los 5 integrantes del equipo sin generar conflictos en la infraestructura unificada, se adoptó la siguiente topología de ramas:

- **main:** Rama de producción. Contiene únicamente código estable, testeado y listo para ser desplegado mediante Docker Compose.
- **develop:** Rama de integración principal. Todos los desarrollos convergen aquí para probar la interoperabilidad de los 21 contenedores.
- **feature/* y PT-*:** Ramas de trabajo individuales (ejemplo: `PT-30-rollback`, `feature/PT-26-glpi`). 
- **sync/*:** Ramas de sincronización o mantenimiento (ejemplo: `sync/main-a-develop`) utilizadas para alinear entornos, actualizar historiales desfasados o gestionar fusiones complejas entre ramas principales.

**Política de Integración:** Todo código nuevo debe ingresar a `develop` exclusivamente mediante Pull Requests (PR). Están restringidos los commits directos a las ramas principales para forzar la revisión de código.

## 2. Pipeline de Integración Continua (GitHub Actions)

Se configuró un flujo de trabajo automatizado (Workflow) en GitHub Actions para validar la integridad del proyecto ante cada cambio propuesto.

**Eventos desencadenantes (Triggers):**
- Apertura de un Pull Request hacia `develop` o `main`.
- Nuevos commits (Pushes) dentro de un Pull Request activo.

**Etapas del Pipeline (Jobs):**
- **Checkout:** Clonación del repositorio en el entorno virtual de GitHub (`ubuntu-latest`).
- **Validación de Orquestación:** El pipeline ejecuta un `docker compose config` (sin necesidad de variables del `.env`) para validar que la sintaxis del archivo YAML sea correcta y que la interconexión de los 21 servicios no esté rota.
- **Build de Imágenes:** Se compilan de forma aislada las imágenes para asegurar que los Dockerfiles están correctamente configurados antes de autorizar el merge.

## 3. Seguridad Continua (DevSecOps)

Para evitar la filtración de credenciales sensibles (claves de bases de datos, tokens de Cloudflare, secretos de JWT, etc.) en el repositorio público, se implementaron medidas de seguridad automatizadas:

- **GitGuardian:** Se integró para el escaneo automático de secretos en cada commit empujado al repositorio.
- **Bloqueo y Alertas:** Si se detecta un hardcodeo de una API Key o contraseña real en el código, se genera una alerta para revocar la credencial, cumpliendo con los estándares de seguridad perimetral del proyecto.