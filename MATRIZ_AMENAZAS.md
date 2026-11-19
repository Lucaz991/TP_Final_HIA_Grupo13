# Matriz Inicial de Amenazas

> **Antecedente recuperado para H24/PT-33 el 18/11/2026.**
> Origen: `feature/seguridad/matriz-de-amenazas`, commit `04d6984`.
> El contenido original se conserva debajo para su revisión. Las marcas ✅ y los
> “controles existentes” no constituyen evidencia de implementación actual.
> Las probabilidades porcentuales no tienen una medición adjunta y se tratarán
> como estimaciones cualitativas, no como estadísticas.
> La validación actual y los entregables pendientes se coordinan en
> [H24_SEGURIDAD_INCIDENTES.md](H24_SEGURIDAD_INCIDENTES.md).
>
> **Revisión al 19/11/2026:** la tabla de validación ya cubre ransomware
> (AM-24), cadena de suministro (AM-23), fallas de autorización entre usuarios
> (AM-16 a AM-20), abuso de API/webhooks (AM-21), riesgos de IA (AM-22),
> DDoS (AM-04), robo de credenciales (AM-05/AM-14) y exposición de red
> (AM-11). JWT no garantiza protección CSRF, bcrypt no valida tokens JWT y una
> red Docker compartida no equivale a segmentación. Verificar cada control en
> su contexto antes de asignarle eficacia o marcarlo como implementado.

## Validación actual H24 — 18/11/2026

| ID | Amenaza | Evidencia actual | Impacto / prioridad | Control faltante | Estado |
|---|---|---|---|---|---|
| AM-16 / H24-AUTH-01 | Acceso a tutorías ajenas por ID (BOLA/IDOR) | Falla inicial confirmada y retest integrado aprobado en H24 | Alto; integración pendiente | Autorización por recurso en GET/PUT/DELETE y control de campos por rol | Corregido en laboratorio; despliegue pendiente |
| AM-17 / H24-AUTH-02 | Modificación del perfil de otro usuario por ID | Falla confirmada en BD y retest 403/200 aprobado | Alto; integración pendiente | Comparar `:id` con JWT/admin y limitar campos actualizables | Corregido en laboratorio; despliegue pendiente |
| AM-18 / H24-AUTH-03 | Alta/desactivación de horarios de otro profesor | Falla confirmada en BD y retest 403/200 aprobado | Alto; integración pendiente | Validar `profesorId` con JWT en rutas actual y legacy | Corregido en laboratorio; despliegue pendiente |
| AM-19 / H24-BFLA-01 | Funciones de categorías sin autenticación ni rol | Acciones sin token confirmadas y retest 401/403/200 aprobado | Alto; integración pendiente | `verifyToken`, `verifyAdmin` y propiedad del profesor en asociaciones | Corregido en laboratorio; despliegue pendiente |
| AM-20 / H24-AUTH-04 | Solicitudes, respuestas y calificaciones ajenas por ID | Operaciones cruzadas confirmadas y retest 403/200 aprobado | Alto; integración pendiente | Validar propietario, autor, rol profesor y participación en la solicitud/tutoría | Corregido en laboratorio; despliegue pendiente |
| AM-21 / H24-MP-01 | Pago de recursos ajenos y webhook falsificable de Mercado Pago | 13/13 casos de autorización y firma HMAC aprobados contra simulador local | Crítico; integración y validación del proveedor pendientes | Firma `x-signature`, tipo/ID explícito, pagador propietario, URL configurable, importe servidor e idempotencia | Corregido en laboratorio; despliegue y secreto real pendientes |
| AM-01 / H24-SQLI-01 | Inyección SQL en rutas, filtros, búsquedas admin y login | 37/37 probes controlados sin ejecución ni cambios en tablas | Residual: alcance limitado a endpoints y técnicas seleccionadas | Mantener parametrización y validación; repetir si cambian consultas o se agregan endpoints | Probado en laboratorio; no hallada en el alcance ejecutado |
| AM-22 / H24-IA-01 | Chatbot: tutorías ajenas en el contexto, cuota sin límite e inyección indirecta vía comentarios | Contexto filtrado por usuario, 429 en request 21, 400 por mensaje inválido y adaptador local verificados | Alto; respuesta del modelo real pendiente | Scope por propietario, limitador por `userId`, máximo 1000 caracteres, comentarios fuera del contexto y timeout de 15 s | Corregido en laboratorio; proveedor e inyección directa residual pendientes |
| AM-23 / H24-SCAN-01 | Vulnerabilidades de dependencias e imágenes (supply chain) | npm audit + Trivy 19/11/2026: backend 2 moderadas, frontend 19 (`xlsx` alta sin fix), postgres:18.6 con 2 críticas, backend/frontend con fix por rebuild | Alto; remediación parcial por rebuild y decisión sobre `xlsx` | Rebuild `--pull`, `npm audit fix` de cadena de build, evaluar reemplazo de `xlsx`, pin de `latest`, re-escaneo tras despliegue | Analizado; remediaciones propuestas |
| AM-04 / H24-DDOS-01 | DDoS sobre la aplicación publicada | Borde en Cloudflare (oculta el origen y absorbe L3/L4), limitadores de login 5/15min y de chat 20/15min por usuario | Alto residual: sin prueba de saturación acordada | Revisar límites globales en Nginx/Cloudflare, alertas de consumo y plan de escalado | Analizado; mitigación por diseño de borde |
| AM-24 / H24-RANSOM-01 | Ransomware sobre datos y volúmenes Docker | Servicio `backup` interno y restauración verificada y documentada por el equipo; clúster Patroni replicado | Crítico residual: respaldo reside en el mismo host/motor | Copia externa o inmutable, procedimiento de respuesta, separar credenciales de respaldo | Analizado; restauración evidenciada por el equipo |
| AM-05 / AM-14 / H24-CRED-01 | Robo y fuerza bruta de credenciales | bcrypt + JWT + limitador de login por IP real (`trust proxy` verificado); Gitleaks 8.30.1 sobre 71 commits sin secretos reales; `.env` fuera del repo y credenciales del lab separadas | Medio residual: spoofing de XFF solo desde la red interna | MFA opcional en paneles, normalizar respuestas de login, borrar `gitleaks-report.json` del historial | Parcial: limitador e historial verificados |
| AM-11 / H24-NET-01 | Exposición de puertos y superficie de red | Compose revisado: todos los binds a `127.0.0.1`; publicación solo por túnel saliente; laboratorio con un único puerto | Medio | Mantener la regla "sin binds a 0.0.0.0", re-verificar tras cambios de compose | Verificado por configuración |
| AM-25 / H24-INFRA-01 | Configuración insegura de infraestructura Docker | Grafana `admin/admin` corregido; revisión completa documentada (H24-INFRA-01): `privileged` en sandbox, `env_file` completo a n8n, `latest`, restart y etcd sin auth | Alto residual hasta aplicar remediaciones | Env acotado a n8n, restart uniforme, pin de `latest`, healthchecks y límites | Corregido lo crítico; backlog de hardening documentado |

El JWT impidió acceso sin token válido y el listado filtró por usuario, pero
ninguno de esos controles evitó el acceso individual a recursos ajenos.
La explotación se confirmó solo en el laboratorio, no en producción. El retest
integrado cubrió **62/62** casos; la matriz de Mercado Pago agregó **13/13**
casos contra el adaptador local, sin llamadas al proveedor real.
Ver [resultados y plan de acción](INFORME_VULNERABILIDADES.md#validación-actual-h24--18112026),
[autorización](security-test/authorization-results.json) y
[pagos](security-test/mercadopago-results.json).

**Decisión de publicación (19/11/2026):** el grupo descartó Cloudflare Access.
GLPI, Nextcloud, n8n y Grafana se publican con su propia autenticación y
Prometheus queda sin hostname (`grafana.hia-26.com` reemplaza a `monitor.`).
Riesgo aceptado: sin una capa adicional en el borde, la seguridad de esos
paneles depende por completo de la fortaleza de sus credenciales; se
recomienda revisión de passwords y no reutilizar las del sistema.

Las estimaciones y marcas históricas siguientes no reemplazan esta verificación.

## Antecedente original

**Responsable:** Matias (MC)
**Fecha:** 4 de noviembre de 2026
**Objetivo:** Identificar amenazas, evaluar riesgos y proponer controles de mitigación

## Escalas de Evaluación

### Probabilidad
- **Alta:** >70% de ocurrencia
- **Media:** 30-70% de ocurrencia
- **Baja:** <30% de ocurrencia

### Impacto
- **Crítico:** Compromiso total del sistema o pérdida de datos
- **Alto:** Impacto significativo en funcionalidad
- **Medio:** Impacto parcial en funcionalidad
- **Bajo:** Impacto menor

### Nivel de Riesgo
| Impacto \ Probabilidad | Alta | Media | Baja |
|------------------------|------|-------|------|
| Crítico | 🔴 Crítico | 🔴 Alto | 🟡 Medio |
| Alto | 🔴 Alto | 🔴 Alto | 🟡 Medio |
| Medio | 🔴 Alto | 🟡 Medio | 🟢 Bajo |
| Bajo | 🟡 Medio | 🟢 Bajo | 🟢 Bajo |

## Matriz de Amenazas

| ID | Amenaza | Categoría | Probabilidad | Impacto | Nivel de Riesgo | Controles Existentes | Controles Propuestos | Responsable | Prioridad |
|----|---------|-----------|--------------|---------|----------------|---------------------|---------------------|-------------|-----------|
| AM-01 | Inyección SQL | Aplicación | Media | Alto | 🔴 Alto | Sequelize ORM | Validación adicional + Preparación de consultas | Rodrigo | P1 |
| AM-02 | XSS (Cross-Site Scripting) | Aplicación | Media | Alto | 🔴 Alto | sanitize-html | CSP Headers + Validación estricta | Lucas | P1 |
| AM-03 | CSRF (Cross-Site Request Forgery) | Aplicación | Baja | Alto | 🟡 Medio | JWT | SameSite cookies + CSRF tokens | Lucas | P2 |
| AM-04 | DDoS Attack | Infraestructura | Media | Alto | 🔴 Alto | Ninguno | Cloudflare DDoS Protection + Rate Limiting | Matias | P1 |
| AM-05 | Robo de Credenciales | Seguridad | Baja | Crítico | 🔴 Alto | Variables de entorno | Rotación periódica + No en código | Matias | P0 |
| AM-06 | Vulnerabilidades de Dependencias | Seguridad | Alta | Alto | 🔴 Alto | Ninguno | npm audit + Snyk + Actualizaciones | Matias | P0 |
| AM-07 | Escalación de Privilegios en Docker | Seguridad | Baja | Alto | 🟡 Medio | Ninguno | Contenedores non-root + ReadOnly filesystem | Lucas | P2 |
| AM-08 | Pérdida de Datos (BD) | Datos | Media | Crítico | 🔴 Alto | Ninguno | Backups + Replicación + Retention | Rodrigo | P0 |
| AM-09 | Acceso No Autorizado a pgAdmin | Seguridad | Baja | Alto | 🟡 Medio | Autenticación básica | IP whitelist + Autenticación LDAP | Rodrigo | P2 |
| AM-10 | Fallo de Autenticación JWT | Aplicación | Media | Alto | 🔴 Alto | bcrypt | Refresh tokens + Expiración corta | Lucas | P1 |
| AM-11 | Exposición de Puertos Innecesarios | Infraestructura | Media | Alto | 🔴 Alto | Firewall | Solo puertos necesarios + Docker network | Matias | P1 |
| AM-12 | Configuración Insegura de CORS | Aplicación | Media | Medio | 🟡 Medio | CORS configurado | Restringir a dominios específicos | Lucas | P2 |
| AM-13 | Logs con Información Sensible | Seguridad | Baja | Alto | 🟡 Medio | Logging básico | Sanitizar logs + No logs de passwords | Lucas | P2 |
| AM-14 | Ataque de Fuerza Bruta (Login) | Aplicación | Media | Alto | 🔴 Alto | Rate limiting | Intentos máximos + Captcha + Bloqueo IP | Lucas | P1 |
| AM-15 | Compromiso de Contenedor Docker | Seguridad | Baja | Alto | 🟡 Medio | Ninguno | Escaneo de imágenes + Actualizaciones | Lucas | P2 |

## Análisis por Categoría

### 🔴 Críticos (P0) - Mitigar Inmediatamente (Sprint 1)

| ID | Amenaza | Acción Inmediata |
|----|---------|-----------------|
| AM-05 | Robo de Credenciales | Mover secretos a .env, revocar credenciales expuestas |
| AM-06 | Vulnerabilidades de Dependencias | Ejecutar npm audit, actualizar paquetes |
| AM-08 | Pérdida de Datos (BD) | Implementar backups automáticos + replicación |

### 🔴 Altos (P1) - Mitigar Sprint 1-2

| ID | Amenaza | Acción |
|----|---------|--------|
| AM-01 | Inyección SQL | Validación adicional en backend |
| AM-02 | XSS | CSP Headers + validación estricta |
| AM-04 | DDoS Attack | Cloudflare Tunnel + Rate Limiting |
| AM-10 | Fallo JWT | Refresh tokens + expiración corta |
| AM-11 | Exposición de Puertos | Firewall + Docker network |
| AM-14 | Fuerza Bruta | Rate limiting + Captcha |

### 🟡 Medios (P2) - Mitigar Sprint 2-3

| ID | Amenaza | Acción |
|----|---------|--------|
| AM-03 | CSRF | SameSite cookies + CSRF tokens |
| AM-07 | Escalación Privilegios Docker | Contenedores non-root |
| AM-09 | Acceso pgAdmin | IP whitelist + LDAP |
| AM-12 | CORS Inseguro | Restringir dominios |
| AM-13 | Logs Sensibles | Sanitizar logs |
| AM-15 | Compromiso Docker | Escaneo imágenes |

## Priorización de Mitigación

### Sprint 1 (Días 1-4) - Críticos y Altos Prioridad 0-1

**Acciones:**
1. ✅ Mover secretos a .env (Lucas)
2. ✅ Revocar credenciales expuestas (Lucas)
3. ✅ Ejecutar npm audit (Matias)
4. ✅ Configurar Cloudflare Tunnel (Matias)
5. ✅ Configurar Rate Limiting (Lucas)
6. ✅ Implementar backups básicos (Rodrigo)

### Sprint 2 (Días 5-9) - Altos y Medios Prioridad 1-2

**Acciones:**
1. ✅ Implementar replicación BD (Rodrigo)
2. ✅ Configurar CSP Headers (Lucas)
3. ✅ Configurar SameSite cookies (Lucas)
4. ✅ Implementar captcha en login (Lucas)
5. ✅ Configurar contenedores non-root (Lucas)
6. ✅ Configurar IP whitelist pgAdmin (Rodrigo)

### Sprint 3 (Días 10-14) - Medios y Documentación

**Acciones:**
1. ✅ Sanitizar logs (Lucas)
2. ✅ Escanear imágenes Docker (Lucas)
3. ✅ Documentar todas las amenazas
4. ✅ Documentar controles implementados
5. ✅ Elaborar informe de seguridad final

## Métricas de Éxito

- [ ] 0 vulnerabilidades críticas en dependencias
- [ ] 0 vulnerabilidades altas en dependencias
- [ ] < 5 vulnerabilidades moderadas
- [ ] Todos los secretos en .env
- [ ] Backups automáticos funcionando
- [ ] Replicación BD funcionando
- [ ] Cloudflare Tunnel configurado
- [ ] Rate Limiting activo
- [ ] CSP Headers configurados
- [ ] Matriz de amenazas documentada

## Riesgos y Mitigaciones

### Riesgo 1: Tiempo Insuficiente

**Descripción:** No se pueden mitigar todas las amenazas en 14 días

**Mitigación:**
- Priorizar P0 y P1
- Documentar P2 como "mejoras futuras"
- Aceptar riesgos residuales documentados

### Riesgo 2: Dependencias sin Actualización

**Descripción:** Algunos paquetes no tienen actualizaciones disponibles

**Mitigación:**
- Buscar alternativas
- Aceptar riesgo documentado
- Monitorear actualizaciones futuras

### Riesgo 3: Conflicto con Funcionalidad

**Descripción:** Algunos controles pueden afectar funcionalidad

**Mitigación:**
- Probar en rama separada
- Testing exhaustivo
- Rollback planificado

## Referencias

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CWE Top 25: https://cwe.mitre.org/top25/
- Docker Security: https://docs.docker.com/engine/security/
- NIST Cybersecurity Framework: https://www.nist.gov/cyberframework

## Próximos Pasos

1. [ ] Presentar matriz al equipo
2. [ ] Asignar responsables para cada amenaza
3. [ ] Crear tareas en Jira para mitigación P0 y P1
4. [ ] Priorizar en Sprint 1
5. [ ] Documentar progreso semanal
6. [ ] Actualizar matriz según se implementen controles

## Estado del Documento

✅ **Completado:**
- [x] Identificación de amenazas
- [x] Evaluación de probabilidad e impacto
- [x] Determinación de nivel de riesgo
- [x] Documentación de controles existentes
- [x] Propuesta de controles adicionales
- [x] Asignación de responsables
- [x] Priorización (P0, P1, P2)

⏳ **Pendiente:**
- [ ] Revisión y aprobación por equipo
- [ ] Creación de tareas en Jira
- [ ] Implementación de controles
- [ ] Actualización según progreso