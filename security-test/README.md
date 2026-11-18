# Laboratorio aislado H24 / PT-33

Cumple la preparacion del entorno de prueba del punto 14. No declara completas
las pruebas de vulnerabilidades ni la respuesta a incidentes.

## Arranque desde PowerShell

Requisitos: Docker Desktop con contenedores Linux, Docker Compose v2 y Python 3
para la verificacion. Ejecutar desde la raiz del repositorio:

```powershell
./security-test/init.ps1
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml up -d --build --wait
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml run --rm seed
python security-test/verify.py
```

Cada comando debe terminar correctamente antes de continuar. El seed requiere
una base sin usuarios; si ya se cargo, omitirlo. Una segunda ejecucion falla sin
borrar datos. No combinar este Compose con `compose.yaml`.

Abrir **http://localhost:9081**. La API esta bajo `/api/`, en el mismo origen.
La respuesta incluye `X-H24-Environment: isolated-test` para identificarla.
Usar un perfil de navegador exclusivo para el laboratorio; nunca una cuenta real.

| Cuenta ficticia | Rol |
|---|---|
| `admin@h24.test` | Administrador |
| `alumno.a@h24.test` | Alumno A |
| `alumno.b@h24.test` | Alumno B |
| `profesor.a@h24.test` | Profesor A |
| `profesor.b@h24.test` | Profesor B |

La clave compartida **solo para estas cuentas ficticias** esta en
`SECURITY_ACCOUNT_PASSWORD` de `.env.security-test`. El inicializador genera claves
aleatorias diferentes para PostgreSQL, el usuario de aplicacion y JWT. El archivo
esta ignorado por Git; no copiar el `.env` de produccion ni publicar sus valores.
Reejecutar `init.ps1` conserva las claves existentes.

Se cargan 5 usuarios, 1 categoria, 2 precios, 2 asignaciones, 2 horarios,
4 tutorias (dos por alumno), 2 calificaciones, 2 solicitudes y 2 respuestas.
Las fechas y los estados son ficticios; los pagos marcados en el seed son datos,
no transacciones con proveedores.

## Aislamiento y diferencias con produccion

| Elemento | Configuracion |
|---|---|
| Proyecto | `hia-security-test`; sin nombres fijos de contenedor |
| Base | PostgreSQL 18.6, `h24_security_test`, volumen `hia-security-test_test_database` |
| Usuario de backend | `h24_app`, sin superusuario, sin creacion de roles o bases |
| Red de datos | `hia-security-test_isolated`, `internal: true`, sin redes del TP |
| Entrada | Solo Nginx tiene ademas `hia-security-test_entry` para publicar `127.0.0.1:9081` |
| Puertos | Backend y PostgreSQL no publican puertos del host |
| Recursos | Limites de memoria, CPU y procesos; sin Docker socket ni modo privilegiado |
| Persistencia | Solo el volumen de PostgreSQL; montajes de archivos de prueba en lectura |
| Tunel | No hay `cloudflared`, Access ni credenciales de Cloudflare |

Backend y base no tienen ruta de salida a Internet. Nginx necesita una red de
entrada no interna para publicar el puerto en Docker; esa red **no bloquea su
salida a Internet**. Su proxy apunta exclusivamente al backend, no funciona como
proxy abierto y no recibe credenciales externas. Docker comparte el motor/kernel:
este laboratorio sirve para pruebas de API/SQLi de alcance controlado, no para
ejecutar malware o ensayar escapes de contenedor.

El frontend y backend se construyen desde sus Dockerfiles actuales, con los
controladores, modelos y middleware existentes. No se modifican los archivos de
produccion. Las diferencias de ejecucion son:

- Nginx usa una CSP local que bloquea scripts, conexiones, frames y recursos
  externos del navegador. Google Sign-In, fuentes remotas, geolocalizacion y
  traducciones remotas de DataTables pueden no estar disponibles; son limitaciones
  deliberadas. CSP no controla la navegacion manual a enlaces externos.
- Las rutas de pagos/webhooks, IA y login/registro con Google devuelven `503`
  desde Nginx. Se usa login local. Este `503` no demuestra que la integracion
  real sea segura; esos endpoints quedan fuera de estas pruebas.
- Calendar se sustituye por `calendar.cjs`: devuelve IDs `h24-simulated-*` y
  ningun enlace Meet ni envio de invitaciones/correos.
- Los adaptadores de pagos e IA tambien se sustituyen por funciones que rechazan
  la operacion si se llama directamente al backend.
- `start.cjs` rechaza variables de proveedores y exige los nombres/credenciales
  de prueba antes de iniciar la aplicacion. No se incluyen claves de Google,
  Mercado Pago, IA ni correo. En el codigo revisado, las invitaciones por correo
  se realizaban a traves de Calendar.
- La clave JWT y la base no se comparten con produccion. El backend puede modificar
  su esquema para `sequelize.sync()`, pero no es superusuario PostgreSQL.
- Se conservan el limitador de login y los headers del proxy. Los intentos pasan
  por Nginx: el comportamiento de IP compartida/trust proxy sigue pendiente de
  evaluacion. No se desactiva el limitador para facilitar un escaneo.

Las dependencias/imagenes se resuelven durante el build con acceso a Internet.
El bloqueo de red corresponde a la ejecucion del backend y base. Repetir la
verificacion tras cualquier cambio de Compose, adaptadores o integraciones.

## Verificacion y uso

`verify.py` comprueba salud, redes, puertos, volumen, montajes, CSP, API y cuentas.
Comprueba TCP bloqueado desde backend hacia `1.1.1.1:443` (con control positivo
desde el host) y un receptor HTTP temporal propio en el host. No sondea servicios
de produccion. Verifica login de alumno y admin, y respuestas 401/403/200 del
endpoint administrativo. No muestra passwords ni JWT.

Consume dos intentos del limitador de login (cinco por 15 minutos). Si se necesita
repetir inmediatamente tras otras pruebas de login, reiniciar **solo** el backend
de este laboratorio; se pierde el contador temporal:

```powershell
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml restart backend
```

Para ZAP configurar un contexto limitado a `http://localhost:9081/.*` y excluir
los endpoints deshabilitados. No seguir enlaces a dominios externos. Acordar
antes cada prueba activa; no comenzar con un escaneo ilimitado o de carga.

El laboratorio permite preparar pruebas de autenticacion, roles, propiedad de
recursos, validacion y SQLi. No cubre alta disponibilidad, volumen de 6M, TLS
publico, Cloudflare, proveedores reales ni n8n. Un control no validado sigue
pendiente aunque el entorno levante correctamente.

## Detener, conservar o reiniciar

Detener conservando los datos:

```powershell
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml down
```

Volver a arrancar conservando los datos: ejecutar `up -d --wait`, sin seed.

**Reiniciar datos borra exclusivamente la base de H24** con este comando:

```powershell
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml down --volumes
```

Despues ejecutar `up -d --wait` y `run --rm seed`. Nunca usar `docker volume prune`,
ni comandos de borrado sin el proyecto y archivo explicitos. No regenerar claves
manteniendo el volumen antiguo: el password inicial de PostgreSQL se aplica solo
al crear el volumen.

## Hallazgos

Registrar: identificador, commit/imagen, endpoint, cuenta ficticia y rol, pasos,
resultado esperado/observado, evidencia sin tokens, impacto, responsable y
correccion. Repetir la prueba tras el fix. Los fallos de la CSP/producto real se
verifican por separado: la CSP mas restrictiva de este laboratorio puede ocultar
vectores de XSS que existen con la politica de produccion.

## Preparacion verificada el 18/11/2026

Base de codigo: `ff2e83e` de `feature/PT-33-seguridad-incidentes`, mas los archivos
del laboratorio incorporados en este cambio. Los tres contenedores quedaron
`healthy` y el unico puerto publicado fue `127.0.0.1:9081`.

- `verify.py` termino correctamente: controles de topologia, salida TCP del
  backend, pagina/API, CSP local, integraciones deshabilitadas y Calendar simulado.
- Login local probado con alumno y administrador. `/api/admin/summary` devolvio
  401 sin token, 403 con alumno y 200 con administrador.
- El listado del alumno A devolvio sus dos tutorias sinteticas. Esto no valida
  aun permisos sobre consulta individual, edicion o borrado de recursos ajenos.
- El seed se ejecuto en transaccion sobre PostgreSQL 18.6 con usuario sin
  privilegios de superusuario. Una segunda carga fue rechazada sin limpiar datos.
- No se ejecutaron escaneos de ZAP, SQLi, pruebas de carga ni pruebas de n8n.
- No se modificaron configuracion, contenedores o volumenes del stack principal.

Para consultar el inventario sin imprimir variables de entorno:

```powershell
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml ps
docker compose --env-file .env.security-test -p hia-security-test -f compose.security-test.yaml images
```
