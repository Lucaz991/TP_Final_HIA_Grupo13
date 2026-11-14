# Backup y restauración de PostgreSQL

## Objetivo

Generar copias de seguridad de `tpFinal` y comprobar su recuperación en una instancia PostgreSQL independiente del clúster.

## Archivos

| Archivo | Función |
|---|---|
| `backup.ps1` | Genera un respaldo Custom, verifica su inventario y transferencia y registra tamaño, tiempos y SHA-256. |
| `restaurar.ps1` | Verifica el respaldo y lo restaura en una base de prueba vacía, registrando duración y resultado. |

Los respaldos se guardan fuera del repositorio. No subir archivos `.dump` a Git.

## Requisitos

- Windows con PowerShell y Docker disponibles.
- Clúster iniciado y conexión al líder mediante `proxy:5465`.
- Servicio dedicado `backup` iniciado, con `pg_dump`, `pg_restore`, `psql` y `sha256sum`.
- Variables `DB_ADMIN_USER` y `DB_ADMIN_PASSWORD` configuradas dentro del servicio `backup`.
- Espacio disponible para el respaldo, la base restaurada y los archivos temporales.

Las herramientas verificadas en el servicio `backup` corresponden a PostgreSQL 18.7.

Para comparar el respaldo con el origen, mantener detenidas las cargas y evitar escrituras de la aplicación durante el backup y la captura de los datos de referencia.

## Alcance

El respaldo incluye los objetos y datos de `tpFinal`: tablas, tipos, secuencias, índices, restricciones y controles del esquema `pt23_dataset`.

No incluye los roles globales del servidor ni la configuración de Patroni, etcd, HAProxy o Docker.

La restauración de prueba utiliza `--no-owner --no-privileges`: no reproduce los propietarios ni los permisos originales.

## Servicio dedicado de backup

El servicio `backup` utiliza `postgres:18` como contenedor de herramientas.
No inicia otro servidor PostgreSQL ni publica puertos.

Configuración dentro de `services` en `compose.yaml`:

```yaml
  backup:
    image: postgres:18
    restart: unless-stopped
    entrypoint: ["sleep", "infinity"]
    environment:
      DB_ADMIN_USER: ${DB_ADMIN_USER}
      DB_ADMIN_PASSWORD: ${DB_ADMIN_PASSWORD}
    networks:
      - redtpfinal
```

Para iniciarlo:

```powershell
docker compose up -d --no-deps backup
```

El recorrido del respaldo es:

`backup → proxy:5465 → líder disponible`

Requiere Docker, el servicio backup, HAProxy y un líder accesible.

Si la conexión se interrumpe durante el respaldo, la ejecución falla
y debe generarse un archivo nuevo. 

La ejecución se inicia manualmente desde PowerShell. 

## 1. Ejecutar el backup

Desde PowerShell, en la raíz del proyecto:

```powershell
.\db\backup\backup.ps1 -Destino "C:\Users\alexi\Desktop\TpFinalHIA\Respaldos"
```

El script:

1. Identifica el contenedor del servicio dedicado `backup`.
2. Comprueba que `proxy:5465` conecta al líder de `tpFinal`.
3. Genera el respaldo mediante `pg_dump --format=custom`.
4. Comprueba que `pg_restore --list` pueda leer su inventario.
5. Copia el respaldo y el inventario a Windows.
6. Compara los SHA-256 del archivo del contenedor y de la copia local.
7. Renombra el archivo `.dump.partial` a `.dump` después de verificarlo.
8. Registra el resultado en un archivo JSON.

Los archivos generados son:

- `tpFinal-<identificador>.dump`
- `tpFinal-<identificador>-inventario.txt`
- `tpFinal-<identificador>-registro.json`

El estado esperado es:

```text
backup_verificado_restauracion_pendiente
```

Este estado confirma la generación, lectura del inventario y transferencia del archivo. La recuperación se comprueba restaurándolo.

### Consideración de PowerShell

El programa Linux enviado por stdin termina con un comentario para evitar que el salto de línea agregado por PowerShell altere el nombre del inventario:

```powershell
$programaLinux = $programa.Replace("`r`n", "`n") + "`n# fin"

$programaLinux |
    & docker exec -i $contenedor sh -s -- $remoto
```

Se utiliza `docker cp` para transferir el respaldo binario, evitando redirecciones de texto de PowerShell.

## 2. Preparar la instancia de restauración

Se utiliza una instancia independiente, con volumen propio y sin conexión al backend ni a Cloudflare.

| Elemento | Valor |
|---|---|
| Contenedor | `postgres-restauracion` |
| Imagen | `postgres:18` |
| Base | `tpFinal_restaurada` |
| Usuario de prueba | `backup_admin` |
| Puerto local | `127.0.0.1:5471` |
| Volumen | `postgres_restauracion_data` |

Para una instalación nueva, definir una contraseña local de prueba y ejecutar:

```powershell
$env:POSTGRES_PASSWORD = Read-Host "Contraseña exclusiva del entorno de prueba"

docker run -d --name postgres-restauracion `
    -e POSTGRES_USER=backup_admin `
    -e POSTGRES_PASSWORD `
    -e POSTGRES_DB=tpFinal_restaurada `
    -p 127.0.0.1:5471:5432 `
    -v postgres_restauracion_data:/var/lib/postgresql `
    postgres:18

Remove-Item Env:POSTGRES_PASSWORD
```

No repetir `docker run` si el contenedor ya existe. La inicialización de usuario y base se aplica al crear un volumen vacío.

Comprobar disponibilidad:

```powershell
docker exec postgres-restauracion pg_isready -U backup_admin -d tpFinal_restaurada
```

Resultado esperado:

```text
accepting connections
```

## 3. Ejecutar la restauración

Usar la ruta y el SHA-256 del respaldo registrado:

```powershell
.\db\backup\restaurar.ps1 `
    -Archivo "C:\Users\alexi\Desktop\TpFinalHIA\Respaldos\tpFinal-20261114-172647-f8d5ba2a.dump" `
    -Sha256Esperado "AEF6FF0056C30653231258059766CB07173941BE0069E4B2C80CC02EDB79DFB3"
```

Para otros respaldos, reemplazar ambos valores por los de esa ejecución.

El script:

1. Comprueba el SHA-256 del archivo local.
2. Rechaza una base destino que ya contenga objetos de usuario.
3. Copia el respaldo al contenedor.
4. Verifica que la transferencia conserve el SHA-256.
5. Comprueba la lectura del inventario.
6. Ejecuta `pg_restore` con una sola transacción y salida ante errores.
7. Guarda el log y un registro JSON.

El estado esperado es:

```text
restaurado_verificacion_datos_pendiente
```

El código de salida esperado es `0`.

El script no sobrescribe automáticamente una restauración anterior. Si falla, revisar el log antes de reintentar.

## 4. Verificar los datos restaurados

Abrir la consola de la instancia de prueba:

```powershell
docker exec -it postgres-restauracion psql -U backup_admin -d tpFinal_restaurada
```

### Confirmar destino y cantidades

```sql
SELECT current_database();

SELECT 'usuarios' AS tabla, COUNT(*) AS registros FROM public.usuarios
UNION ALL
SELECT 'categorias', COUNT(*) FROM public.categorias
UNION ALL
SELECT 'precios', COUNT(*) FROM public.precios
UNION ALL
SELECT 'profesores_categorias', COUNT(*) FROM public.profesores_categorias
UNION ALL
SELECT 'horarios_disponibles', COUNT(*) FROM public.horarios_disponibles
UNION ALL
SELECT 'tutorias', COUNT(*) FROM public.tutorias
UNION ALL
SELECT 'calificaciones', COUNT(*) FROM public.calificaciones
ORDER BY tabla;
```

Comparar con los conteos de referencia del origen.

### Comprobar relaciones

```sql
SELECT 'tutorias_sin_alumno' AS comprobacion, COUNT(*) AS invalidos
FROM public.tutorias t
LEFT JOIN public.usuarios u ON u.id = t."alumnoId"
WHERE t."alumnoId" IS NOT NULL AND u.id IS NULL

UNION ALL

SELECT 'tutorias_sin_profesor', COUNT(*)
FROM public.tutorias t
LEFT JOIN public.usuarios u ON u.id = t."profesorId"
WHERE t."profesorId" IS NOT NULL AND u.id IS NULL

UNION ALL

SELECT 'tutorias_sin_categoria', COUNT(*)
FROM public.tutorias t
LEFT JOIN public.categorias c ON c.id = t."categoriaId"
WHERE t."categoriaId" IS NOT NULL AND c.id IS NULL

UNION ALL

SELECT 'calificaciones_sin_tutoria', COUNT(*)
FROM public.calificaciones c
LEFT JOIN public.tutorias t ON t.id = c."tutoriaId"
WHERE c."tutoriaId" IS NOT NULL AND t.id IS NULL;
```

Resultado esperado: cero en las cuatro comprobaciones.

Estas consultas comprueban referencias no nulas sin destino; no verifican por sí solas todas las reglas del modelo.

### Comprobar índices

```sql
SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'tutorias_profesor_estado_categoria',
      'tutorias_alumno',
      'tutorias_categoria',
      'tutorias_creada_id',
      'calificaciones_tutoria',
      'horarios_profesor'
  )
ORDER BY tablename, indexname;
```

Resultado esperado: seis filas.

### Comprobar calificaciones y controles del generador

```sql
SELECT calificacion, COUNT(*) AS cantidad
FROM public.calificaciones
GROUP BY calificacion
ORDER BY calificacion;

SELECT id, usuarios_por_rol, registros_por_lote, version_generador
FROM pt23_dataset.configuracion;

SELECT lote, registros
FROM pt23_dataset.lotes
ORDER BY lote;
```

## 5. Resultados de las ejecuciones mediante scripts

### Backup desde el servicio dedicado

| Medición | Resultado |
|---|---|
| Inicio | 14/11/2026 18:09:09, zona -03:00 |
| Archivo | `tpFinal-20261114-180909-36c7c5fb.dump` |
| Servicio ejecutor | `backup` |
| Herramientas | PostgreSQL 18.7 |
| Conexión | `proxy:5465` |
| Tamaño | 163.045.797 bytes |
| Backup y lectura del inventario | 26,849 segundos |
| Proceso completo | 29,518 segundos |
| SHA-256 local y del contenedor | Coincidentes |
| Estado | Backup verificado; restauración pendiente |

SHA-256:

```text
063ECCE855F8E6326F36EDF3BDC47FEFFFE99A7B6A2249740D95187358DBE59A
```

### Restauración

| Medición | Resultado |
|---|---|
| Inicio | 14/11/2026 17:32:48, zona -03:00 |
| Contenedor | `postgres-restauracion` |
| Base | `tpFinal_restaurada` |
| Código de salida | 0 |
| Restauración | 51,711 segundos |
| Proceso completo | 58,893 segundos |

### Comparación de cantidades

| Tabla | Origen registrado | Restauración |
|---|---:|---:|
| `usuarios` | 200.003 | 200.003 |
| `categorias` | 100 | 100 |
| `precios` | 10 | 10 |
| `profesores_categorias` | 400.000 | 400.000 |
| `horarios_disponibles` | 400.000 | 400.000 |
| `tutorias` | 6.000.003 | 6.000.003 |
| `calificaciones` | 3.600.000 | 3.600.000 |

Los registros adicionales respecto del dataset sintético se conservaron. Los controles de lotes contabilizan las 6.000.000 de tutorías del generador, no los registros adicionales.

### Otras verificaciones

- Cuatro comprobaciones de relaciones: cero referencias huérfanas.
- Seis índices de PT-24 presentes.
- Generador versión 4.
- Configuración de 100.000 usuarios por rol y 1.000.000 de tutorías por lote.
- Seis lotes registrados de 1.000.000 de tutorías.

| Puntuación | Calificaciones restauradas |
|---|---:|
| 1 | 180.000 |
| 2 | 360.000 |
| 3 | 720.000 |
| 4 | 1.080.000 |
| 5 | 1.260.000 |
| Total | 3.600.000 |

## 6. Evidencia de pérdida y recuperación selectiva

Esta prueba se realizó previamente en la instancia independiente `h22-postgres-restauracion`, base `tpFinal_h22`, usando el respaldo manual:

```text
tpFinal-bck-14-11-2026.dump
```

| Medición del respaldo manual | Resultado |
|---|---|
| Tamaño | 163.054.962 bytes |
| Duración informada por pgAdmin | 23,4 segundos |
| Formato | Custom |
| Entradas del inventario | 117 |
| PostgreSQL de origen | 18.7 |
| Herramienta pg_dump utilizada por pgAdmin | 18.6 |

SHA-256 del respaldo manual:

```text
6B33162A920CA1CEEB189416DB2811EA5B5202C25695B90960F1D0B89C25A37F
```

La restauración completa manual terminó sin errores. Su duración fue estimada en hasta cinco minutos, sin medición exacta.

### Simulación realizada

Se vació únicamente `public.calificaciones` en la base de prueba, con una comprobación previa del nombre de la base:

```sql
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'tpFinal_h22' THEN
        RAISE EXCEPTION 'Operación permitida solo en tpFinal_h22';
    END IF;
END;
$$;

TRUNCATE TABLE public.calificaciones;

COMMIT;

SELECT COUNT(*) FROM public.calificaciones;
```

Resultado después de la pérdida: `0`.

Este bloque es destructivo y corresponde exclusivamente a la copia de prueba indicada. No ejecutarlo en `tpFinal` del clúster.

### Recuperación realizada

Con el respaldo copiado como `/tmp/tpFinal.dump` dentro de esa instancia:

```powershell
docker exec h22-postgres-restauracion pg_restore `
    -U h22_admin -d tpFinal_h22 `
    --data-only --table=calificaciones `
    --no-owner --no-privileges `
    --exit-on-error --verbose /tmp/tpFinal.dump
```

Resultados:

- Código de salida: `0`.
- Calificaciones recuperadas: `3.600.000`.
- Calificaciones sin tutoría: `0`.
- Distribución de puntuaciones coincidente con la tabla anterior.
- Tiempo de recuperación selectiva: no registrado.
- No se utilizó `RESTART IDENTITY` al vaciar la tabla.

Esta recuperación selectiva pertenece al respaldo manual. La restauración automatizada documentada en el apartado anterior utilizó un archivo distinto.

## 7. Interpretación de las verificaciones

Las comprobaciones realizadas demuestran:

- Generación y transferencia del respaldo sin alteración de sus bytes.
- Restauración completa ejecutada sin errores.
- Coincidencia de los siete conteos comparados.
- Ausencia de referencias huérfanas en las cuatro relaciones consultadas.
- Presencia de los seis índices adicionales.
- Recuperación de los controles del generador.
- Distribución esperada de calificaciones.
- Recuperación selectiva después de una pérdida controlada.

No se realizó una comparación completa de todos los valores fila por fila ni una verificación exhaustiva de todos los objetos, relaciones y secuencias.

Los campos de verificación pendientes de los JSON reflejan el estado al terminar cada script. Las comprobaciones SQL posteriores se documentan aquí; no se modificaron retroactivamente esos registros.

## 8. Conservación de evidencias

Conservar fuera del repositorio:

- Respaldos `.dump`.
- Inventarios.
- Registros JSON.
- Logs de restauración.
- Capturas o exportaciones de las consultas de comparación.

El SHA-256 permite detectar cambios respecto de la huella registrada; no sustituye la prueba de restauración.

La replicación del clúster aporta disponibilidad, pero no reemplaza el backup: una eliminación accidental también puede propagarse a las réplicas.

