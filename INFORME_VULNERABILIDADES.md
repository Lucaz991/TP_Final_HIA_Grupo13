# Informe de Vulnerabilidades — TP Final HIA Grupo 13

> **Informe histórico recuperado para H24/PT-33 el 18/11/2026.**
> Origen: `feature/seguridad/escaneo-de-vulnerabilidades+evidencias`, commit `8e1a872`.
> Los resultados de la sección "Informe original" corresponden al 09/11/2026,
> no a una nueva prueba ni al estado actual de las imágenes y servicios.
> Esta recuperación incluye únicamente Markdown: los JSON y archivos de evidencia
> citados deben localizarse en la rama de origen y revisarse antes de incorporarlos.
> Seguimiento de la validación actual:
> [H24_SEGURIDAD_INCIDENTES.md](H24_SEGURIDAD_INCIDENTES.md).

## Alcance y correcciones para la revisión de H24

Las siguientes precisiones prevalecen sobre las conclusiones históricas:

- Un resultado negativo de sqlmap se limita al endpoint, parámetros y técnicas
  utilizados. No demuestra ausencia de SQLi en toda la aplicación. Los errores
  HTTP 500 requieren revisión y no prueban por sí solos una defensa correcta.
- No se puede afirmar que el historial completo esté libre de secretos. El
  informe contiene afirmaciones contradictorias sobre credenciales y deben
  contrastarse con las evidencias originales y una revisión del alcance actual.
  Un archivo ignorado puede haber quedado expuesto en commits anteriores.
- El resumen de severidades de ZAP no coincide con su tabla. Reconciliarlo con
  el reporte original y confirmar si se utilizó análisis pasivo o escaneo activo.
  Los headers no corrigen por sí solos SRI ausente ni bibliotecas vulnerables.
- Aunque `node_modules` no se copie a Nginx, código de dependencias frontend
  puede quedar incorporado al JavaScript compilado. Evaluar su uso y exposición.
  La explotabilidad de dependencias del backend también requiere comprobación.
- La revisión manual de Docker cubre controles seleccionados; no equivale a una
  auditoría CIS completa. El fallo de Docker Bench en aquella instalación no
  demuestra incompatibilidad general con Docker Desktop/WSL2.
- Los puertos ligados a localhost pueden publicarse mediante un túnel. Verificar
  las rutas y políticas de Access vigentes antes de concluir qué está expuesto.
- La imagen PostgreSQL 16 escaneada fue reemplazada localmente por PostgreSQL
  18.6. Sus resultados no deben presentarse como un escaneo del clúster actual.
  Revisar también versiones, fechas y digest de las demás imágenes.
- “EOL” indica fin de soporte; no demuestra la causa del cierre de HAProxy.
  Diferenciar síntoma observado, mitigación aplicada y causa confirmada.

## Validación actual H24 — 18/11/2026

### H24-AUTH-01: acceso a tutorías de otro usuario (BOLA/IDOR)

**Estado: corregido en rama de fix y verificado en laboratorio; despliegue pendiente.**
**Severidad: alta. Prioridad: integrar la corrección antes de publicar esta versión.**
Un usuario autenticado puede consultar, modificar y eliminar una tutoría ajena
cambiando el ID de la URL. Afecta confidencialidad, integridad y disponibilidad
de los registros. No es una inyección SQL ni requiere evadir la firma del JWT.

**Alcance:** `http://127.0.0.1:9081`, proyecto `hia-security-test`, base
`h24_security_test` PostgreSQL 18.6. Código base `29e28d5`; la imagen exacta y la
hora UTC constan en la [evidencia JSON](security-test/authorization-results.json).
Se usaron los alumnos ficticios A/B y cuatro tutorías descartables creadas para B.
No se probó el dominio público ni se verificó qué versión está desplegada allí.

| Caso | Esperado | Observado | Resultado |
|---|---|---|---|
| GET individual sin token | 401 | 401 | Conforme |
| GET individual con token inválido | 401 | 401 | Conforme |
| Listado de A | No incluir tutorías de B | No incluyó los recursos descartables de B | Conforme para el caso probado |
| A consulta tutoría de B | 403/404 sin datos ajenos | 200 y datos de la tutoría ajena | **Falla** |
| A modifica tutoría de B | 403/404 y mensaje intacto | 200; cambio confirmado por lectura de BD | **Falla** |
| A elimina tutoría de B | 403/404 y fila conservada | 200; ausencia confirmada por lectura de BD | **Falla** |
| B consulta su tutoría | 200 con su recurso | 200 con su recurso | Control positivo |
| B modifica su tutoría | 200 y cambio persistido | 200; persistencia confirmada | Control positivo |
| B elimina su tutoría | 200 y eliminación persistida | 200; eliminación confirmada | Control positivo |

Las cuatro tutorías descartables se eliminaron al finalizar. Permanecen las
cuatro tutorías del seed y cero filas con el prefijo de esta prueba.
Los registros de auditoría sintéticos pueden permanecer para trazabilidad.
La evidencia no incluye passwords, JWT ni cuerpos completos con datos de usuarios.

**Causa verificada en código:** `backend/src/routes/tutoria.route.js` exige token,
pero `getTutoria`, `editTutoria` y `deleteTutoria`, en
`backend/src/controllers/tutoria.controller.js`, consultan/modifican por ID sin
comprobar que `req.userId` corresponda al alumno o profesor autorizado.
`getTutorias` sí filtra el listado por el usuario del JWT; esa protección no se
aplica automáticamente a las rutas individuales.

**Reproducción:** con el laboratorio cargado, ejecutar:

```powershell
python security-test/verify.py --authorization
```

El comando valida primero el aislamiento, obtiene tokens por login local, crea
recursos descartables de B, ejecuta la matriz y limpia solo esos recursos.
Termina con código **2** cuando encuentra incumplimientos y deja el JSON anterior.
Las tres fallas son hallazgos esperados al reproducir esta versión, no errores
del arranque del laboratorio. La prueba consume cuatro intentos de login contando
la verificación previa; no ejecutarla repetidamente sin considerar el limitador.

### Plan de acción para H24-AUTH-01

| Paso | Acción | Criterio de cierre |
|---|---|---|
| Registro | MC conserva esta evidencia y coordina la corrección con backend | Hallazgo identificado, responsable de implementación acordado |
| Evaluar exposición | Comparar el código de producción con la versión afectada, sin repetir borrados allí | Determinar si el defecto también está publicado |
| Contención si está publicado | Restringir temporalmente las rutas afectadas o el acceso al servicio mientras se corrige, considerando el impacto funcional | Decisión y control documentados; no basta ocultar botones |
| Corrección | Autorizar cada recurso en el backend con la identidad del JWT antes de leer, modificar, borrar o llamar a Calendar | A no puede operar sobre B; acceso legítimo conservado |
| Evitar reasignación | Revisar los campos permitidos por rol; no aceptar libremente cambios de `alumnoId`/`profesorId` | El cliente no puede cambiar la propiedad para eludir el control |
| Roles y estados | Definir operaciones permitidas al alumno/profesor y mantener la administración en rutas protegidas por rol | Reglas explícitas y pruebas para ambos participantes |
| Verificación | Reconstruir solo backend H24 y repetir la misma prueba; agregar casos de profesor y campos restringidos al implementar el fix | Accesos ajenos rechazados, datos intactos, casos legítimos funcionales |
| Despliegue y cierre | PR revisado, controles del pipeline y comprobación posterior al despliegue | Evidencia antes/después y estado actualizado; no cerrar solo por editar código |

**Corrección y retest 18/11/2026:** se reforzó `tutoria.controller.js` para exigir
participante/admin en GET/PUT/DELETE individual, impedir crear tutorías a nombre
de otro alumno, restringir los cambios de estado al profesor/admin, bloquear la
reasignación de participantes y evitar que el cliente envíe `enlaceMeet` o
`googleEventId`. El retest `verify.py --authorization` pasó **13/13** casos:
alta indebida 403, alta propia pendiente, alumno no acepta, profesor sí acepta,
y GET/PUT/DELETE ajenos 403. Evidencia posterior:
`security-test/authorization-results.json` (imagen `sha256:d02bb705b384...`).
Los fixtures se limpiaron. Queda integrar el fix, comprobarlo tras el despliegue
y revisar otros endpoints/campos; no hubo prueba ni evidencia de explotación en
producción.

### H24-AUTH-02: modificación del perfil de otro usuario (BOLA/IDOR)

**Estado: corregido en rama de fix y verificado en laboratorio; despliegue pendiente.**
**Severidad: alta.** `PUT /api/usuario/:id` confiaba en el ID de la ruta sin
compararlo con `req.userId`. Una prueba con `alumno.a` contra `alumno.b` devolvió
inicialmente HTTP 500 por una falla posterior del controlador, pero la lectura de
BD confirmó que el nombre ya había cambiado. Por eso un 500 no puede tratarse
como rechazo seguro.

**Corrección verificada:** solo el propio usuario o un administrador puede
actualizar el perfil; los campos permitidos se copian por allowlist. Se eliminó
la referencia indefinida a `PerfilProfesor`, que producía el 500 después de
persistir datos. Retest: A → B devolvió **403** sin cambio y B → B devolvió
**200**.

### H24-AUTH-03: gestión de horarios de otro profesor (BOLA/IDOR)

**Estado: corregido en rama de fix y verificado en laboratorio; despliegue pendiente.**
**Severidad: alta.** `POST /api/horarioDisponible` aceptaba `profesorId` del
cliente y `DELETE /api/horarioDisponible/:id` desactivaba cualquier horario por
ID. En el laboratorio, `alumno.a` pudo crear y desactivar horarios de
`profesor.b`. La ruta legacy `/api/usuario/horario` repetía el mismo patrón y
además omitía campos obligatorios del modelo.

**Corrección verificada:** la creación exige profesor propietario o admin, el
profesor objetivo debe existir y el borrado/desactivación comprueba
`horario.profesorId` contra `req.userId`. La ruta legacy aplica la misma regla y
guarda `modalidad`/`estado`. Retest: alta ajena **403**, desactivación ajena
**403** con estado `activo`, alta y desactivación propias **200**.

### H24-BFLA-01: funciones de categorías sin autenticación ni rol

**Estado: corregido en rama de fix y verificado en laboratorio; despliegue pendiente.**
**Severidad: crítica.** `backend/src/routes/categoria.route.js` no aplicaba
`verifyToken` a las operaciones de escritura. En el laboratorio, una request sin
sesión pudo modificar y borrar una categoría y asociar/desasociar un profesor con
HTTP **200**. Además, el controlador aceptaba `profesorId` del body y admitía
cualquier usuario como profesor.

**Corrección verificada:** las lecturas públicas se conservaron; `POST`,
`PUT` y `DELETE` de categorías exigen admin; la asociación profesor-categoría
exige token y solo permite al profesor propietario o admin. Se validó que el
objetivo tenga rol `profesor` y se corrigió el alta para guardar `nivel`.
Retest: sin token **401**, alumno **403**, profesor propietario **200** y admin
**200**.

### H24-AUTH-04: gestión de solicitudes, respuestas y calificaciones ajenas

**Estado: corregido en rama de fix y verificado en laboratorio; despliegue pendiente.**
**Severidad: alta.** Los controladores confiaban en `usuarioId`, `solicitudId` y
`tutoriaId` enviados por el cliente sin resolver primero la propiedad del objeto.
La falla combina BOLA/IDOR y BFLA según la función invocada.

En el baseline del laboratorio, `alumno.a` obtuvo HTTP **200** al consultar una
solicitud de `alumno.b`, crear una solicitud a su nombre, editarla, cerrarla y
borrarla; también pudo consultar respuestas, editar/aceptar una respuesta y crear
o consultar una calificación de una tutoría ajena. Un profesor pudo crear una
respuesta con `idUsuario` de otro profesor. `DELETE /api/respuesta/:id` devolvió
**500**, pero la fila quedó eliminada por una falla posterior del controlador;
por eso se verificó siempre la base después de una mutación.

**Corrección verificada:**

- Solicitudes: el listado se filtra por propietario; los profesores ven
  solicitudes abiertas; admin conserva acceso. Crear usa el usuario autenticado
  por defecto y rechaza otro `usuarioId`; consultar, editar, cerrar y borrar son
  del propietario o admin; recursos ausentes devuelven 404.
- Respuestas: consultar requiere permiso sobre la solicitud asociada; crear es
  solo profesor/admin y con identidad propia salvo admin; editar y borrar son del
  autor o admin; aceptar es del propietario de la solicitud o admin.
- Calificaciones: solo el alumno participante puede calificar una tutoría
  finalizada/completada; la consulta queda limitada a participantes o admin.
- Se corrigieron referencias de usuario que producían errores después de una
  operación sensible (`id_usuario` inexistente).

Retest: accesos ajenos devolvieron **403**, controles de propietario/profesor
devolvieron **200**, y los fixtures quedaron eliminados.

### H24-SQLI-01: prueba controlada de inyección SQL

**Estado: ejecutada en laboratorio; no se confirmó inyección en el alcance probado.**
**Severidad si se reprodujera: alta.** La revisión de código no encontró
`sequelize.query` ni SQL manual concatenado en los controladores. Los filtros más
sensibles usan `Sequelize.literal` con valores convertidos a número o listas de
columnas fijas; el resto pasa por el ORM. Esto reduce la superficie, pero no
exime de repetir la prueba al agregar endpoints o consultas dinámicas.

Comando:

```powershell
python security-test/verify.py --sqli
```

Alcance: payloads de error, condición booleana, `UNION` y `pg_sleep` en IDs de
categoría, profesor, tutoría, solicitud, horario y calificación; filtros de
usuario, paginación, búsquedas administrativas y email de login. No se usaron
`DROP`, `UPDATE`, `DELETE` ni extracción de datos. Se compararon recuentos de
tablas antes/después y se midió que ninguna respuesta ejecutara la espera.

Resultado: **37/37 casos aprobaron** sobre el commit `967f13d9` y la imagen
`sha256:7139bcc87ea7...`. Evidencia: `security-test/sqli-results.json`.
Las búsquedas admin trataron el payload como texto literal y devolvieron cero
coincidencias; el login no emitió token.

**Observaciones no críticas de robustez:** IDs malformados en rutas devuelven
HTTP 500 genérico en lugar de un 400 uniforme, y un email inexistente puede
devolver HTTP 200 con `status:0`. No se observó bypass ni ejecución SQL, pero
conviene normalizar esas respuestas para facilitar monitoreo y evitar falsos
positivos en futuras pruebas.

### H24-MP-01: webhook y preferencias de Mercado Pago

**Estado: corregido en rama de fix y verificado con simulador local; despliegue y configuración del proveedor pendientes.**
**Severidad: crítica.** La integración original combinaba tres defectos:

- El webhook exigía JWT, un modelo incompatible con las notificaciones de Mercado
  Pago, y no validaba la firma HMAC enviada por el proveedor.
- La creación de preferencias aceptaba un ID ambiguo: primero intentaba resolver
  una respuesta de ayuda y luego una tutoría. Cualquier usuario autenticado podía
  generar una preferencia sobre el recurso de otro pagador.
- `notification_url` estaba hardcodeada a una URL temporal de ngrok y el proceso
  esperaba la respuesta del proveedor antes de confirmar la notificación.

**Corrección verificada:**

- El webhook quedó público y autenticado con `x-signature` + `x-request-id`:
  manifiesto `id:<data.id>;request-id:<id>;ts:<ts>;`, HMAC-SHA256,
  comparación en tiempo constante y tolerancia de 5 minutos. Devuelve **400**
  ante headers ausentes/mal formados, **401** ante firma inválida o timestamp
  expirado y **503** si falta `MP_WEBHOOK_SECRET`.
- El endpoint de preferencias ahora exige `tipo` (`ayuda` o `tutoria`) e
  `entidadId`. Para ayuda, el pagador es el propietario de la solicitud; para
  tutoría, el `alumnoId`. Solo ese pagador o admin puede iniciar el checkout.
- Se rechazan respuestas no aceptadas, tutorías en estados no pagables y
  recursos ya marcados como pagados. El importe se toma exclusivamente del
  modelo del servidor, no del `precio` enviado por el cliente.
- `MERCADOPAGO_NOTIFICATION_URL` reemplaza la URL temporal. En producción debe
  configurarse con el dominio HTTPS final; en el laboratorio apunta al backend
  interno y el adaptador se reemplaza por un simulador.
- Tras validar la firma, el endpoint responde **200** y procesa la notificación
  en segundo plano. El servicio consulta el pago al proveedor, exige estado
  `approved`, referencia externa estricta `ayuda|tutoria:<id>`, moneda ARS e
  importe coincidente. Si la entidad conserva `preferenceId`, también lo
  compara con el pago. Repetir el mismo `paymentId` no duplica la actualización.
- Se corrigió el helper de auditoría para no fallar cuando el evento proviene
  del webhook y no tiene `req.body`; el actor auditado es el pagador real.

Comando y resultado:

```powershell
python security-test/verify.py --mercadopago
```

**13/13 casos aprobaron** sobre el commit `fff1c8ae` y la imagen
`sha256:1396ad19a33f...`: preferencia sin token **401**, compra de recursos
ajenos **403**, preferencias propias **200** contra el simulador, tipo/ID
inválidos **400**, webhook sin firma/mal formado **400**, firma inválida o
expirada **401**, y webhook firmado sin JWT **200** procesado localmente.
Evidencia: `security-test/mercadopago-results.json`.

**Límite:** el laboratorio no contiene `MP_ACCESS_TOKEN`, `MP_PUBLIC_KEY` ni el
secreto real, y no contacta a Mercado Pago. La prueba valida el contrato HTTP,
autorización del pagador y la lógica HMAC del backend contra un cliente
simulado; falta validar el secreto real y una notificación real en el ambiente
publicado.

### H24-IA-01: chatbot con datos ajenos, sin límites y con inyección indirecta

**Estado: corregido en rama de fix y verificado en el backend del laboratorio;
la respuesta real del proveedor sigue sin evaluarse.**
**Severidad: alta.** La revisión del asistente (`POST /api/chat`, Groq)
encontró tres defectos:

- **Datos ajenos en el contexto:** `context.service.js` cargaba hasta 10
  tutorías con nombre y apellido de alumno y profesor sin filtrar por el
  usuario que preguntaba. La API ya restringía tutorías por participante,
  pero el chatbot consultaba la base directamente: un atajo que anulaba la
  autorización por propietario para cualquier usuario autenticado.
- **Sin límites:** no existía rate limit ni límite de longitud del mensaje.
  Un usuario autenticado podía agotar la cuota del proveedor (denegación de
  servicio del chat para todos) y cada mensaje disparaba hasta cuatro
  consultas con JOIN a la base.
- **Prompt injection indirecta:** el `comentario` libre de las calificaciones
  se insertaba en el *system prompt* de otros usuarios; un comentario
  malicioso podía alterar las respuestas del asistente. El mensaje del
  usuario también va sin filtros al rol `user` (inyección directa mitigada
  solo por el texto del prompt).

**Corrección verificada:**

- Las tutorías del contexto quedan limitadas a `alumnoId`/`profesorId` del
  usuario autenticado; sin `userId` no se incluye ninguna.
- Se eliminó `comentario` de las calificaciones del contexto y se limitó el
  listado de profesores a 50.
- Nuevo limitador `chatIntentos`: **20 mensajes por usuario cada 15
  minutos**, clave por `req.userId` (no por IP, así no agrupa usuarios detrás
  del proxy). `verifyToken` se ejecuta antes del limitador.
- El mensaje exige `string` no vacío y máximo **1000 caracteres**; se recorta
  antes de usarlo. El cliente Groq tiene timeout de 15 s.

Prueba ejecutada dentro del contenedor del laboratorio (`docker exec`), porque
Nginx del entorno sigue devolviendo 503 para `/api/chat` desde el exterior:

- Sin token → **401**; mensaje vacío, no string o de 1001 caracteres → **400**.
- Mensaje válido → **500** del adaptador deshabilitado (llega al servicio y no
  llama al proveedor).
- 429 exactamente en la request **21** del mismo usuario.
- `buildContext` como `alumno.a` no incluye una tutoría de `alumno.b`; como
  `alumno.b` sí la incluye; sin `userId` no incluye ninguna.

**Límites y riesgo residual:** el laboratorio reemplaza `ai.service.js`, así
que no se evaluó la respuesta del modelo real ni su resistencia a prompt
injection. Quedan como superficie aceptada los campos de perfil del profesor
(ubicación, universidad, carrera) que viajan al proveedor y el envío de PII a
Groq como subprocesador; documentarlo en la matriz. El frontend escapa la
respuesta (`{{ msg.text }}`), sin XSS por salida del modelo.

### H24-SCAN-01: dependencias e imágenes de producción (npm audit + Trivy)

**Estado: ejecutado el 19/11/2026; remediaciones propuestas con responsables por asignar.**
Escaneo sobre el árbol de dependencias del repositorio (los mismos
`package.json`/`package-lock.json` que usan los Dockerfiles de producción) y
sobre imágenes construidas con esos Dockerfiles. Evidencia:
`security-test/npm-audit-backend.json`, `npm-audit-frontend.json`,
`trivy-*.json` (Trivy 0.76.2, severidad HIGH+CRITICAL).

**npm audit:**

- **Backend (dependencias de runtime):** 2 moderadas — `uuid <11.1.1`
  (GHSA-w5hq-g745-h8pq, bounds check en v3/v5/v6) llega vía `sequelize`. El
  fix exige un downgrade rompiente de Sequelize: riesgo residual documentado,
  no expone entrada de usuario directa.
- **Frontend:** 19 (17 moderadas, 2 altas). Casi todas pertenecen a la cadena
  de build (Angular CLI → `pacote`/`glob`/`minimatch`/`brace-expansion`/
  `cross-spawn`/`sigstore`): **no llegan al bundle servido**. La excepción de
  runtime es **`xlsx@0.18.5` — 2 altas sin fix** (prototype pollution
  GHSA-4r6h-8v6p-xvw6 y ReDoS GHSA-5pgg-2g8v-p4x9), usada solo en el
  dashboard admin para exportar tutorías a Excel sobre datos propios.
  Superficie contenida; opciones: aceptar el riesgo documentado o migrar a
  `exceljs`/`file-saver`.

**Trivy (imágenes construidas con los Dockerfiles de producción):**

| Imagen | CVEs únicos | Con fix | Lectura |
|---|---|---|---|
| `postgres:18.6` (= `postgres:18`, base del clúster Patroni, `backup` y `nextcloud-db`) | 2 CRITICAL + 60 HIGH | 1 CRITICAL + 27 HIGH | Debian 13: la mayoría son paquetes del OS no usados por PostgreSQL (util-linux, krb5, gnupg, perl, sqlite). CRITICAL sin fix: `libxml2` CVE-2026-6653; `stdlib` Go CVE-2025-68121 en binario embebido. Mitigación: rebuild periódico con base actualizada; evaluar imagen más reducida. |
| `hia-security-test-backend` (`node:20-alpine`) | 1 CRITICAL + 25 HIGH | Todos | `tar` CVE-2026-59873 (gzip bomb) es dependencia empaquetada de npm dentro de la imagen base; openssl/musl/zlib tienen release nuevo. Mitigación: rebuild `--pull` o `apk upgrade`. |
| `hia-security-test-frontend` (nginx) | 3 HIGH | Todos | `libxslt` 1.1.43-r3 → r4. Mitigación: rebuild con base actualizada. |

**Límites:** las imágenes se construyeron en fecha anterior con los Dockerfiles
actuales; una build fresca puede resolver ya parte de los CVE con fix.
Re-escanear las imágenes efectivamente desplegadas tras la integración, y
repetir Trivy sobre el resto del stack (n8n, GLPI, Nextcloud, exporters,
sandbox) si el tiempo lo permite — hoy solo están las tres imágenes propias.

**Acciones propuestas:** rebuild con `--pull` antes del despliegue final,
`npm audit fix` no rompiente en frontend para la cadena de build, decisión
documentada sobre `xlsx`, y pin de versiones donde el compose usa `latest`.

### Retest integrado 18/11/2026

`python security-test/verify.py --authorization` pasó **62/62** casos sobre el
commit `dd76a29e` y la imagen `sha256:7139bcc87ea7...`: tutorías, perfil,
horarios actuales, ruta legacy, categorías, solicitudes, respuestas y
calificaciones. La evidencia sin credenciales está en
`security-test/authorization-results.json`. Pendientes: muestra representativa
de `/api/admin`, chat, auditoría, normalización de errores de validación y
validación tras despliegue.

## Informe original del 09/11/2026

> Punto 14 del TP: Seguridad informática y amenazas actuales.
> Fecha de escaneo: 09/11/2026 — Entorno: Docker Desktop (WSL2) / Windows 11.

---

## 1. Herramientas utilizadas

| Herramienta | Versión | Objetivo | Estado |
|-------------|---------|----------|--------|
| **Trivy** | 0.76.2 | Escaneo de imágenes Docker (OS + paquetes) | ✅ Ejecutado |
| **npm audit** | npm 10.x | Dependencias Node.js (backend/frontend) | ✅ Ejecutado |
| `docker compose ps` | — | Evidencia de bind `127.0.0.1` en puertos | ✅ Ejecutado |
| **OWASP ZAP** | 2.17.0 | Escaneo DAST de la aplicación | ✅ Ejecutado — 9 alertas |
| **Gitleaks** | 8.30.1 | Secretos en historial Git | ✅ Ejecutado — 1 falso positivo |
| Docker Bench Security | — | Benchmark CIS de Docker | ⚠️ No compatible WSL2 — revisión manual realizada |
| **sqlmap** | 1.10.11 | Prueba controlada SQLi | ✅ Ejecutado — NO inyectable |
| nmap | — | Mapa de puertos expuestos | ⏳ Opcional (evidencia cubierta por compose ps) |

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

## 5d. Escaneo DAST — OWASP ZAP 2.17.0 (baseline, `http://localhost:8081`)

**Resultado: 9 alertas — 3 MEDIUM, 2 LOW, 4 INFO**

| Alerta | Riesgo | Detalle | Fix sugerido |
|--------|--------|---------|--------------|
| CSP no configurada (4) | MEDIUM | Sin Content Security Policy → permite XSS/inyección de scripts | Agregar header `Content-Security-Policy` en `nginx.conf` |
| Integridad de recursos secundarios (4) | MEDIUM | Recursos CDN sin `integrity` hash → MITM podría inyectar JS modificado | Agregar `integrity` a `<script>`/`<link>` externos |
| Anti-Clickjacking (4) | MEDIUM | Sin `X-Frame-Options`/`frame-ancestors` → iframe embedding permite clickjacking | Header `X-Frame-Options: DENY` en nginx |
| Librería JS vulnerable | MEDIUM | Una lib JS con CVEs conocidos | Actualizar dependencia (pendiente identificar cuál) |
| X-Content-Type-Options faltante | LOW | Sin `nosniff` → MIME sniffing | Header `X-Content-Type-Options: nosniff` |
| Divulgación timestamp Unix | LOW | Info leakage mínimo | Aceptado |
| Versión servidor expuesta | LOW | `Server: nginx/1.31.8` → fingerprinting | `server_tokens off` en nginx |
| JS cross-domain (4) | INFO | Referencias externas (Google, etc.) | Aceptado |
| Aplicación Web Moderna (4) | INFO | Angular detectado | Informativo |

**Remediación priorizada:** los 3 MEDIUM se mitigan agregando headers de seguridad en `frontend/nginx.conf` (rama de fix separada — ver sección 6).

---

## 5e. Prueba controlada SQLi — sqlmap 1.10.11

**Target:** `GET /api/categoria/:id` — endpoint público con parámetro de path usado en query a la DB.

**Comando:**
```powershell
sqlmap -u "http://localhost:8081/api/categoria/1*" --batch --level=1 --risk=1 \
  --technique=BEU --threads=4 --timeout=10 --retries=1
```

**Resultado: NO inyectable** ✅

- sqlmap probó técnicas boolean-based, error-based y UNION en el parámetro `id`
- Detectó el parámetro como dinámico pero **no injectable**
- 49 respuestas HTTP 500 durante la prueba: el backend manejó los payloads maliciosos devolviendo JSON genérico `{"status":0,"msg":"Error al obtener categoría"}` — **sin leak de errores SQL ni stacktraces**
- Causa raíz: Sequelize parametriza las queries (no concatena strings SQL)

**Conclusión:** la capa de acceso a datos es resistente a SQLi básico. Para pruebas más profundas se requeriría `--level=5` y bypasses avanzados (fuera de alcance para este TP).

---

## 6. Pendientes — remediación (rama de fix dedicada)

- [ ] **Headers de seguridad en `nginx.conf`** — CSP, X-Frame-Options, nosniff, server_tokens off (resuelve 3 MEDIUM de ZAP)
- [ ] **Upgrade `haproxy:2.9-alpine` → `3.0-alpine`** — crash EOL documentado
- [ ] **`npm audit fix` controlada** en branch dedicada (backend 12, frontend 47)
- [ ] **`integrity` en recursos CDN** del frontend (resuelve MEDIUM SRI de ZAP)
- [ ] **`read_only: true` + `tmpfs`** en servicios stateless (CIS)
- [ ] **Pinnear imágenes** — evitar `:latest` en prometheus/cadvisor/etc (reproducibilidad)
- [ ] Rotación de secrets del `.env` anterior (fuera de scope de código)

---

## 7. Resumen ejecutivo

El stack presenta **superficie de ataque reducida**: solo el frontend es alcanzable desde Internet (vía túnel HTTPS), los 12 servicios restantes están bindeados a `127.0.0.1`. Las vulnerabilidades identificadas se concentran en **dependencias transitivas** (npm packages) e **imágenes base** (Debian/Alpine), no en código propio.

El escaneo DAST de ZAP confirmó que la aplicación carece de headers de seguridad (3 MEDIUM mitigables en `nginx.conf`) pero la lógica de acceso a datos es **resistente a SQLi** (sqlmap: no inyectable — Sequelize parametriza correctamente).

El repositorio está **limpio de secretos** (gitleaks: solo falso positivo en documentación Swagger). Los 2 hallazgos críticos operativos detectados durante el despliegue (crash de HAProxy EOL y `sync({force:true})` destructivo) fueron remediados o documentados para el equipo.
