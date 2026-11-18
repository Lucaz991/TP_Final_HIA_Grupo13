# H24 / PT-33 — Seguridad y respuesta ante incidentes

**Responsable:** MC. **Punto del TP:** 14. **Inicio de revisión:** 18/11/2026.
**Estado:** laboratorio aislado preparado y verificado; pruebas completas y
criterios de aceptación todavía no cerrados.

## Objetivo y alcance

Verificar controles de la aplicación, bases de datos, contenedores,
infraestructura, CI/CD y automatizaciones. Separar resultados históricos,
configuraciones observadas, pruebas ejecutadas y riesgos pendientes.
Una prueba debe identificar versión/commit, entorno, resultado esperado,
resultado observado y evidencia sin credenciales ni datos personales.

La rama recupera documentación de seguridad sin fusionar el código antiguo:

- [Matriz inicial](MATRIZ_AMENAZAS.md): origen `04d6984`.
- [Informe histórico](INFORME_VULNERABILIDADES.md): origen `8e1a872`.
- Los escaneos originales y sus archivos citados no se han revalidado en esta
  etapa. No convertir los antecedentes en resultados actuales.

## Los siete entregables

| Entregable | Material disponible | Trabajo para completar H24 |
|---|---|---|
| Matriz de amenazas | Matriz inicial recuperada | Actualizar activos, amenazas, controles comprobados, responsables y riesgo residual |
| Informe de vulnerabilidades | Informe del 09/11 recuperado | Corregir contradicciones y contrastar hallazgos con versiones actuales |
| Evidencias de escaneo y corrección | Referencias en el informe histórico | Localizar originales, revisar redacción de secretos y obtener comparaciones posteriores a los cambios |
| Resultados de pruebas controladas | Antecedentes de ZAP/sqlmap | Ejecutar en entorno aislado autorización, API, SQLi y webhooks; registrar límites del alcance |
| Configuración de controles | Archivos del repositorio por revisar | Relacionar cada control con su configuración vigente y prueba de funcionamiento |
| Procedimiento de respuesta y recuperación | Pendiente | Definir detección, clasificación, contención, recuperación, validación, registro y responsables |
| Flujo de incidentes integrado con n8n | Pendiente de inspección/exportación | Comprobar alerta → flujo → ticket/notificación → aprobación cuando corresponda → cierre |

## Amenazas requeridas por el punto 14

| Amenaza | Revisión y prueba prevista |
|---|---|
| Ransomware | Permisos sobre datos y respaldos; restauración en una base descartable. No ejecutar malware ni cifrar archivos reales |
| DDoS y agotamiento de recursos | Revisar límites, exposición y controles; prueba pequeña y acotada de límites, sin generar una denegación de servicio |
| Robo de credenciales | Secretos en archivos/historial/imágenes/logs, validación de tokens y procedimiento de revocación; simulacro con credencial ficticia |
| Dependencias vulnerables | Escaneo de imágenes actuales y dependencias; distinguir severidad, exposición y remediación comprobada |
| Cadena de suministro | Lockfiles, origen/versionado de imágenes, Actions, permisos del pipeline y protección de secretos |
| Inyección SQL | Entradas controladas en endpoints de prueba, respuestas y logs; nunca extraer datos reales |
| Fallas de autorización | Sin token, token inválido/expirado, rol insuficiente y acceso a recursos de otro usuario con cuentas sintéticas |
| Abuso de API y webhooks | Validación de entradas, límites y reintentos; autenticación, firmas si aplica e idempotencia |
| Riesgos de IA | Inyección de instrucciones en contenido no confiable, exposición de secretos, límites de herramientas y aprobación humana; usar datos ficticios |

## Secuencia de trabajo

### 1. Preparación y documentación

- [x] Crear rama desde `develop` y recuperar únicamente los dos Markdown.
- [x] Identificar documentos como históricos y aclarar límites de sus conclusiones.
- [ ] Revisar código, Compose, workflow CI/CD y archivos de automatizaciones.
- [ ] Inventariar servicios e imágenes realmente desplegados y diferencias con Git.
- [ ] Localizar evidencias históricas y comprobar su alcance antes de reutilizarlas.

### 2. Entorno aislado

- [x] Preparar proyecto Compose de pruebas con red, volúmenes y puertos propios.
- [x] Usar cuentas, credenciales y datos sintéticos; evitar conexiones a las bases
  locales del equipo o a la instalación publicada.
- [x] No conectar el túnel público del equipo a las pruebas.
- [x] Desactivar o sustituir por receptores locales los envíos de correo,
  Calendar, pagos, servicios de IA y webhooks externos.
- [x] Registrar inventario inicial, límites de ejecución y forma de eliminar
  exclusivamente el entorno de pruebas.

Implementación: [Compose independiente](compose.security-test.yaml) y
[guía reproducible del laboratorio](security-test/README.md).
La verificación de preparación está en `security-test/verify.py`: incluye
salud, redes, salida TCP bloqueada del backend, montajes, cuentas sintéticas
y controles básicos 401/403/200. No equivale a completar las pruebas del apartado 3.
Nginx tiene una red de entrada adicional; la red interna protege backend y base.
La CSP local y los adaptadores de integración difieren de producción: no usar
estos resultados para afirmar seguridad de Google, Mercado Pago, IA o CSP pública.

`localhost` por sí solo no garantiza aislamiento. No ejecutar escaneos activos
contra la instalación compartida. Un análisis pasivo de navegación pública
debe documentarse por separado y con su alcance.

### 3. Aplicación, API y secretos

- [ ] Revisar amenazas y vulnerabilidades anteriores con herramientas actuales.
- [ ] Verificar autenticación y autorización por rol y por propietario del recurso.
- [x] Probar SQLi de bajo impacto sobre endpoints seleccionados del entorno aislado.
- [ ] Verificar validación de entradas, errores, headers y límites de solicitudes.
- [ ] Revisar secretos sin incorporar valores, tokens o contraseñas a los reportes.

**Avance 18/11/2026:** ejecutada la prueba acotada de autorización con
`python security-test/verify.py --authorization`. Se confirmaron y corrigieron
**H24-AUTH-01** (tutorías ajenas), **H24-AUTH-02** (edición de perfil ajeno),
**H24-AUTH-03** (horarios ajenos, incluida la ruta legacy), **H24-BFLA-01**
(funciones de categorías sin autenticación ni rol) y **H24-AUTH-04**
(solicitudes, respuestas y calificaciones ajenas). El retest integrado pasó
**62/62** casos, con accesos indebidos rechazados y controles positivos
conservados. Se limpiaron los recursos descartables. Además, la matriz SQLi
controlada pasó **37/37** casos sobre rutas, filtros, búsquedas admin y login,
sin ejecución inyectada ni cambios en las tablas. Queda integrar la rama
`fix/PT-33-autorizacion-tutorias` y verificar tras despliegue; siguen pendientes
la muestra de `/api/admin`, Mercado Pago, chat, auditoría y revisión de errores
de validación observados durante SQLi.

### 4. Docker, infraestructura y CI/CD

- [ ] Revisar interfaces publicadas, redes, usuarios, capacidades, privilegios,
  montajes, socket Docker, recursos, healthchecks y versiones de imágenes.
- [ ] Inspeccionar permisos de Actions, secretos, dependencias de terceros y
  mecanismos de revisión/despliegue. Distinguir YAML de protecciones de rama
  configuradas en GitHub, que requieren verificación independiente.
- [ ] Revisar configuración de publicación, confianza en proxy y Access.
- [ ] Revisar respaldo y recuperación como control ante incidentes; la
  replicación no sustituye un respaldo frente a borrados o corrupción lógica.

### 5. n8n, incidentes y aprobación humana

- [ ] Obtener de Abi los flujos exportados, sus dependencias, endpoints y
  mecanismos de autenticación; exportar sin credenciales.
- [ ] Reproducirlos con credenciales de prueba y un GLPI/receptor aislado.
- [ ] Probar credencial ausente, incorrecta y válida; eventos repetidos y
  entradas inválidas; comprobar que no se ejecuten acciones no autorizadas.
- [ ] Simular un evento sospechoso identificado como prueba y seguir su registro
  hasta el ticket o notificación y cierre.
- [ ] Comprobar que una acción crítica no se ejecute antes de aprobarla y que
  rechazo, vencimiento o solicitante sin permiso no permitan continuar.
- [ ] Redactar y practicar el procedimiento: detección → análisis y clasificación
  → contención → corrección → recuperación → validación → cierre y aprendizaje.

### 6. Cierre

- [ ] Consolidar pruebas y correcciones con referencias verificables.
- [ ] Registrar riesgos pendientes con impacto, mitigación, responsable y plazo.
- [ ] Marcar los criterios como cumplidos solo cuando exista evidencia.
  Los controles no comprobados deben quedar como pendientes o bloqueados.

## Coordinación del equipo

- **Abi:** exportación de flujos n8n, configuración de autenticación sin secretos,
  circuito de aprobación y respaldo/configuración de GLPI con versiones y plugins.
- **Responsable de monitoreo:** reglas y condiciones de alerta, destino al que
  notifican y un evento sintético que permita probar el flujo sin apagar producción.
- **Rodrigo:** procedimiento de restauración en destino descartable y esquema/datos
  mínimos de prueba. La optimización SQL no sustituye los controles de seguridad.
- **Lucas:** funcionamiento del pipeline, permisos, revisión y rollback; aportar
  evidencia de controles de GitHub que no sean visibles en archivos del repositorio.

Las credenciales de cada instalación se entregan por un canal privado y no forman
parte de los Markdown, capturas, exportaciones públicas ni commits.
