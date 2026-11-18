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
> **Revisión necesaria:** incluir explícitamente ransomware, cadena de suministro,
> fallas de autorización entre usuarios, abuso de API/webhooks y riesgos de IA.
> JWT no garantiza protección CSRF, bcrypt no valida tokens JWT y una red Docker
> compartida no equivale a segmentación. Verificar cada control en su contexto
> antes de asignarle eficacia o marcarlo como implementado.

## Validación actual H24 — 18/11/2026

| ID | Amenaza | Evidencia actual | Impacto / prioridad | Control faltante | Estado |
|---|---|---|---|---|---|
| AM-16 / H24-AUTH-01 | Acceso a tutorías ajenas por ID (BOLA/IDOR) | Falla inicial confirmada y retest integrado aprobado en H24 | Alto; integración pendiente | Autorización por recurso en GET/PUT/DELETE y control de campos por rol | Corregido en laboratorio; despliegue pendiente |
| AM-17 / H24-AUTH-02 | Modificación del perfil de otro usuario por ID | Falla confirmada en BD y retest 403/200 aprobado | Alto; integración pendiente | Comparar `:id` con JWT/admin y limitar campos actualizables | Corregido en laboratorio; despliegue pendiente |
| AM-18 / H24-AUTH-03 | Alta/desactivación de horarios de otro profesor | Falla confirmada en BD y retest 403/200 aprobado | Alto; integración pendiente | Validar `profesorId` con JWT en rutas actual y legacy | Corregido en laboratorio; despliegue pendiente |
| AM-19 / H24-BFLA-01 | Funciones de categorías sin autenticación ni rol | Acciones sin token confirmadas y retest 401/403/200 aprobado | Alto; integración pendiente | `verifyToken`, `verifyAdmin` y propiedad del profesor en asociaciones | Corregido en laboratorio; despliegue pendiente |

El JWT impidió acceso sin token válido y el listado filtró por usuario, pero
ninguno de esos controles evitó el acceso individual a recursos ajenos.
La explotación se confirmó solo en el laboratorio, no en producción. El retest
integrado cubrió **34/34** casos.
Ver [resultados y plan de acción](INFORME_VULNERABILIDADES.md#validación-actual-h24--18112026)
y [evidencia](security-test/authorization-results.json).
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