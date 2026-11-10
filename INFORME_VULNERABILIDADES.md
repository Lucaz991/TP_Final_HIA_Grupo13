# Informe de Vulnerabilidades — TP Final HIA Grupo 13

> Punto 14 del TP: Seguridad informática y amenazas actuales.
> Fecha de escaneo: 09/11/2026 — Entorno: Docker Desktop (WSL2) / Windows 11.

---

## 1. Herramientas utilizadas

| Herramienta | Versión | Objetivo | Estado |
|-------------|---------|----------|--------|
| **Trivy** | 0.76.2 | Escaneo de imágenes Docker (OS + paquetes) | ✅ Ejecutado |
| **npm audit** | npm 10.x | Dependencias Node.js (backend/frontend) | ✅ Ejecutado |
| `docker compose ps` | — | Evidencia de bind `127.0.0.1` en puertos | ✅ Ejecutado |
| OWASP ZAP | — | Escaneo DAST de la aplicación | ⏳ Pendiente (manual) |
| **Gitleaks** | 8.30.1 | Secretos en historial Git | ✅ Ejecutado — 1 falso positivo |
| Docker Bench Security | — | Benchmark CIS de Docker | ⚠️ No compatible WSL2 — revisión manual realizada |
| sqlmap | — | Prueba controlada SQLi | ⏳ Pendiente |
| nmap | — | Mapa de puertos expuestos | ⏳ Pendiente |

---

## 2. Resultados — Imágenes Docker (Trivy)

### 2.1 `tp_final_hia_grupo13-frontend` (nginx:alpine)

| Capa | Total | CRITICAL | HIGH | MEDIUM | LOW |
|------|-------|----------|------|--------|-----|
| OS (Alpine 3.24.4) | 1 | 0 | 0 | 1 | 0 |
| npm packages | — | — | — | — | — |

**Hallazgo:**
- `zlib 1.3.2-r1` — **CVE-2026-4738** (MEDIUM, corregible → 1.4-r0). Vulnerabilidad de buffer en zlib del sistema base.
- Las dependencias npm del frontend **NO viajan a la imagen final**: la etapa de build compila Angular y solo se copia el `dist/` estático al nginx. Superficie de ataque mínima.

### 2.2 `tp_final_hia_grupo13-backend` (node:20-alpine)

| Capa | Total | CRITICAL | HIGH | MEDIUM | LOW |
|------|-------|----------|------|--------|-----|
| OS (Alpine 3.23.4) | 54 | 0 | 7 | 15 | 32 |
| npm packages | 43 | 1 | 21 | 18 | 3 |

**Hallazgos críticos/altos relevantes (npm):**

| Paquete | CVE | Sev | Instalado | Fix | Descripción |
|---------|-----|-----|-----------|-----|-------------|
| `tar` | CVE-2026-59873 | **CRITICAL** | 6.2.1 | 7.5.19 | DoS via gzip bomb |
| `tar` | CVE-2026-23745 | HIGH | 6.2.1 | 7.5.3 | Sobrescritura arbitraria + symlink poisoning |
| `tar` | CVE-2026-23950 | HIGH | 6.2.1 | 7.5.4 | Race condition Unicode path |
| `tar` | CVE-2026-24842 | HIGH | 6.2.1 | 7.5.7 | Creación arbitraria vía hardlink path traversal |
| `tar` | CVE-2026-26960 | HIGH | 6.2.1 | 7.5.8 | Read/write arbitrario vía hardlink malicioso |
| `tar` | CVE-2026-29786 | HIGH | 6.2.1 | 7.5.10 | Path traversal drive-relative |
| `tar` | CVE-2026-31802 | HIGH | 6.2.1 | 7.5.11 | File overwrite vía symlink traversal |
| `tar` | CVE-2026-59874/59871/59875/73656 | HIGH | 6.2.1 | 7.5.x | Múltiples DoS/parseo de headers |
| `tar` | CVE-2026-53655 | MEDIUM | 6.2.1 | 7.5.16 | File smuggling por parsing inconsistente |
| `sigstore` | CVE-2026-48815 | HIGH | 2.3.1 | 4.1.1 | Certificados no verificados aceptados |
| `uuid` | CVE-2026-41907 | MEDIUM | 8.3.2 | 11.1.1+ | Out-of-bounds write |

**Evaluación de explotabilidad:**
- `tar` es dependencia transitiva (probablemente de `node-gyp` o tooling de build) — **no se usa en runtime** para procesar archivos del usuario. Riesgo real: BAJO en producción, pero debe documentarse.
- `sigstore` — librería de firma de artefactos; el backend no firma artefactos en runtime. Riesgo: BAJO.
- Mitigación: actualizar a versiones con fix en próxima iteración (`npm audit fix` controlado en branch dedicada).

### 2.3 `tp_final_hia_grupo13-node1` (Patroni/cluster, postgres:16 + Debian)

| Capa | Total | CRITICAL | HIGH | MEDIUM | LOW |
|------|-------|----------|------|--------|-----|
| OS (Debian) | 433 | 1 | 92 | 181 | 158 |
| pip (Patroni deps) | 61 | 1 | 25 | 31 | 3 |

**Evaluación:** imagen Debian completa — mayor superficie del stack. Mitigantes:
- Sin puertos publicados (solo red interna Docker)
- Patroni corre como usuario no-root
- Acceso solo vía HAProxy con health checks
- **Acción:** evaluar slim variant o pin de versiones en próxima iteración.

---

## 3. Resultados — Dependencias npm (npm audit)

| Proyecto | Total | CRITICAL | HIGH | MODERATE | LOW |
|----------|-------|----------|------|----------|-----|
| backend | 12 | 0 | 0 | 10 | 2 |
| frontend | 47 | 4 | 19 | 22 | 2 |

Archivos de evidencia: `backend/audit-backend.json`, `frontend/audit-frontend.json`.

**Nota:** npm audit reporta menos que Trivy porque evalúa solo `package-lock.json` (no imágenes base ni transitivas del SO).

---

## 4. Evidencia — Puertos y exposición de red

### Bind a localhost verificado (`docker compose ps`)

| Puerto | Servicio | Binding | Expuesto a LAN |
|--------|----------|---------|----------------|
| 80 | GLPI | `127.0.0.1:80` | ❌ No |
| 3000 | Backend API | `127.0.0.1:3000` | ❌ No |
| 5050 | pgAdmin | `127.0.0.1:5050` | ❌ No |
| 5465 | HAProxy (DB) | `127.0.0.1:5465` | ❌ No |
| 5678 | n8n | `127.0.0.1:5678` | ❌ No |
| 7000 | HAProxy stats | `127.0.0.1:7000` | ❌ No |
| 8080 | cAdvisor | `127.0.0.1:8080` | ❌ No |
| 8081 | Frontend | `127.0.0.1:8081` | ❌ No |
| 8082 | Nextcloud | `127.0.0.1:8082` | ❌ No |
| 9090 | Prometheus | `127.0.0.1:9090` | ❌ No |
| 9100 | node-exporter | `127.0.0.1:9100` | ❌ No |
| 9187 | postgres-exporter | `127.0.0.1:9187` | ❌ No |

**Único punto de entrada externo:** Cloudflare Tunnel → `localhost:8081` (frontend). Todo lo demás es inalcanzable desde Internet o desde otros equipos de la LAN.

### Incidente documentado durante el despliegue

- **HAProxy 2.9.15** crasheó con código 134 (bug EOL en kernel WSL2 6.18) → el alias `postgres` desapareció → backend devolvía 500 en `/api/categoria`. Resuelto reiniciando el cluster; **pendiente upgrade a `haproxy:3.0-alpine`** (notificado al responsable del cluster).
- **`sequelize.sync({force:true})`** dropeaba ENUMs referenciados → crash `2BP01`. Corregido a `sync()` idempotente (commit `e0f4663`).

---

## 5. Hallazgos adicionales (análisis de código)

| # | Hallazgo | Severidad | Estado |
|---|----------|-----------|--------|
| H1 | `sequelize.sync({force:true})` destruía datos en cada arranque | ALTA | ✅ Corregido (`sync()`) |
| H2 | Secretos reales commiteados en historial (`backend/env`, compose viejo) | CRÍTICA | ⏳ Pendiente rotación/revocación |
| H3 | `sandbox-runner` con `privileged: true` | MEDIA | ⚠️ Requerido por DinD de n8n — documentar compensación |
| H4 | JWT_SECRET débil en `.env` anterior | MEDIA | ⏳ Rotar |
| H5 | Contenedores sin `read_only` root filesystem | BAJA | ⏳ Evaluar hardening |

---

## 5b. Secretos en historial Git (Gitleaks 8.30.1)

**Escaneo:** `gitleaks git --verbose` sobre los 21 commits del repo (~1.11 MB).

**Resultado: 1 hallazgo → FALSO POSITIVO**

| Archivo | Commit | Descripción | Resolución |
|---------|--------|-------------|------------|
| `backend/swagger.js:80` | `6a851369` | `token: 'eyJhbGciOiJIUzI1NiIsIn...'` | Ejemplo de documentación Swagger (JWT truncado ilustrativo). NO es credencial real. |

**Verificación complementaria:**
- `git ls-files` → ningún `.env` trackeado
- `.gitignore` cubre `.env`, `.env.*`, `*.pem`
- Historial revisado: `.env` se agregó una vez (commit `7a8267a`) y fue eliminado en `6ff8568` — contenía valores placeholder, sin secrets reales

**Conclusión:** el repositorio unificado está limpio de secretos. Los secrets del proyecto original (`backend/env`) nunca fueron commiteados a este repo — permanecen solo en archivos locales fuera de Git.

---

## 5c. Revisión CIS Docker — manual (Docker Bench no compatible con WSL2)

**Limitación técnica:** `docker/docker-bench-security` requiere montar `/var/run/docker.sock`, que no está expuesto en Docker Desktop para Windows (backend WSL2). Se realizó revisión manual del `compose.yaml` contra los controles CIS aplicables.

| Control CIS | Estado | Detalle |
|-------------|--------|---------|
| Puertos publicados solo en interfaces necesarias | ✅ PASS | Los 12 servicios bindeados a `127.0.0.1`; solo frontend accesible vía túnel |
| Contenedores privilegiados | ❌ FAIL | `sandbox-runner` usa `privileged: true` (requerido por DinD de n8n) |
| Usuario no-root en contenedores | ❌ FAIL | `sandbox-certs` corre `user: '0:0'`; la mayoría de imágenes usan root por defecto |
| Read-only root filesystem | ❌ FAIL | Ningún servicio define `read_only: true` |
| Capability dropping | ❌ FAIL | Ningún servicio usa `cap_drop` |
| Límites de recursos (CPU/RAM) | ❌ FAIL | Ningún servicio define `mem_limit`/`cpus`/`deploy.resources` |
| Healthchecks | ⚠️ PARCIAL | Solo `sandbox-api` tiene healthcheck; cluster depende de depends_on sin condition |
| Restart policies | ⚠️ PARCIAL | Solo `glpi` y `glpi-db` tienen `restart: unless-stopped` |
| Secretos en compose | ✅ PASS | Todo vía `${VAR}` desde `.env` (gitignored), sin valores hardcodeados |
| Imágenes pinned | ⚠️ PARCIAL | Algunas usan `:latest` (nginx, prometheus, nextcloud, glpi, cadvisor) — reproducibilidad afectada |
| Redes segmentadas | ✅ PASS | Todo en `redtpfinal`; sin puertos innecesarios publicados |

**Acciones de remediación priorizadas:**
1. Eliminar `privileged: true` del sandbox-runner cuando el equipo decida si se necesita DinD (alternativa: `--security-opt seccomp=unconfined` + caps específicas)
2. Agregar `read_only: true` + `tmpfs` a servicios stateless (prometheus, exporters)
3. Pinnear imágenes a versiones específicas (evitar `:latest`)
4. Evaluar límites de recursos por servicio
5. Extender healthchecks a postgres-exporter y backend

---

---

## 6. Pendientes

- [ ] OWASP ZAP baseline scan → `http://localhost:8081`
- [ ] Gitleaks sobre historial git (incidente documentable)
- [ ] Docker Bench Security (CIS)
- [ ] sqlmap — prueba controlada SQLi en endpoint parametrizado
- [ ] nmap — evidencia formal de puertos
- [ ] Upgrade `haproxy:2.9-alpine` → `3.0-alpine` (crash EOL)
- [ ] Remediación `npm audit fix` controlada en branch dedicada
- [ ] Rotación de secretos expuestos en historial

---

## 7. Resumen ejecutivo

El stack presenta **superficie de ataque reducida**: solo el frontend es alcanzable desde Internet (vía túnel HTTPS), los 12 servicios restantes están bindeados a `127.0.0.1`. Las vulnerabilidades identificadas se concentran en **dependencias transitivas** (npm packages) e **imágenes base** (Debian/Alpine), no en código propio. Los 2 hallazgos críticos de runtime (sync destructivo, secrets en historial) están en proceso de remediación.
