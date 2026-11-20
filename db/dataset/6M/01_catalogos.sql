-- Catálogo de categorías y tarifas.
-- Ejecutar después de crear el esquema de la aplicación.
-- Requiere los índices únicos de categorías y precios.

BEGIN;

SELECT pg_advisory_xact_lock(23001);

DO $destino$
BEGIN
    IF current_database() <> 'tpFinal' THEN
        RAISE EXCEPTION 'Ejecutar únicamente en tpFinal.';
    END IF;

    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Conectarse al nodo líder.';
    END IF;
END;
$destino$;

-- Catálogo esperado de 100 categorías.
CREATE TEMP TABLE categorias_catalogo ON COMMIT DROP AS
SELECT *
FROM (
    VALUES
        ('Matemática', 'primario'),
        ('Matemática', 'secundario'),
        ('Álgebra', 'secundario'),
        ('Álgebra', 'universitario'),
        ('Análisis Matemático', 'universitario'),
        ('Geometría', 'secundario'),
        ('Geometría', 'universitario'),
        ('Estadística', 'secundario'),
        ('Estadística', 'universitario'),
        ('Probabilidad', 'universitario'),
        ('Programación', 'secundario'),
        ('Programación', 'universitario'),
        ('Algoritmos', 'universitario'),
        ('Estructuras de Datos', 'universitario'),
        ('Bases de Datos', 'universitario'),
        ('Ingeniería de Software', 'universitario'),
        ('Desarrollo Web', 'universitario'),
        ('Desarrollo Móvil', 'universitario'),
        ('Redes de Computadoras', 'universitario'),
        ('Sistemas Operativos', 'universitario'),
        ('Arquitectura de Computadoras', 'universitario'),
        ('Inteligencia Artificial', 'universitario'),
        ('Ciberseguridad', 'universitario'),
        ('Física', 'secundario'),
        ('Física', 'universitario'),
        ('Química', 'secundario'),
        ('Química', 'universitario'),
        ('Biología', 'secundario'),
        ('Biología', 'universitario'),
        ('Contabilidad', 'secundario'),
        ('Contabilidad', 'universitario'),
        ('Economía', 'universitario'),
        ('Administración', 'universitario'),
        ('Marketing', 'universitario'),
        ('Inglés', 'primario'),
        ('Inglés', 'secundario'),
        ('Portugués', 'secundario'),
        ('Francés', 'secundario'),
        ('Historia', 'secundario'),
        ('Geografía', 'secundario'),
        ('Filosofía', 'secundario'),
        ('Derecho', 'universitario'),
        ('Psicología', 'universitario'),
        ('Electrónica', 'universitario'),
        ('Mecánica', 'universitario'),
        ('Dibujo Técnico', 'secundario'),
        ('Investigación Avanzada', 'doctorado'),
        ('Seminario de Tesis', 'doctorado'),
        ('Tópicos Avanzados en Física', 'doctorado'),
        ('Inteligencia Artificial Avanzada', 'doctorado'),
        ('Derecho Comparado', 'doctorado'),
        ('Anatomía', 'universitario'),
        ('Fisiología', 'universitario'),
        ('Histología', 'universitario'),
        ('Bioquímica', 'universitario'),
        ('Microbiología', 'universitario'),
        ('Inmunología', 'universitario'),
        ('Farmacología', 'universitario'),
        ('Patología', 'universitario'),
        ('Enfermería', 'terciario'),
        ('Salud Pública', 'universitario'),
        ('Nutrición', 'universitario'),
        ('Genética', 'universitario'),
        ('Ecología', 'universitario'),
        ('Botánica', 'universitario'),
        ('Zoología', 'universitario'),
        ('Termodinámica', 'universitario'),
        ('Hidráulica', 'universitario'),
        ('Mecánica de Fluidos', 'universitario'),
        ('Resistencia de Materiales', 'universitario'),
        ('Ciencia de Materiales', 'universitario'),
        ('Automatización', 'terciario'),
        ('Control Automático', 'universitario'),
        ('Electrotecnia', 'terciario'),
        ('Ingeniería Ambiental', 'universitario'),
        ('Logística', 'terciario'),
        ('Sistemas Distribuidos', 'universitario'),
        ('Computación en la Nube', 'terciario'),
        ('Pruebas de Software', 'terciario'),
        ('DevOps', 'terciario'),
        ('Compiladores', 'universitario'),
        ('Bases de Datos Avanzadas', 'universitario'),
        ('Análisis de Datos', 'terciario'),
        ('Visión Computacional', 'universitario'),
        ('Procesamiento del Lenguaje Natural', 'universitario'),
        ('Informática', 'primario'),
        ('Cálculo Numérico', 'universitario'),
        ('Matemática Discreta', 'universitario'),
        ('Investigación Operativa', 'universitario'),
        ('Ecuaciones Diferenciales', 'universitario'),
        ('Métodos de Optimización', 'universitario'),
        ('Sociología', 'universitario'),
        ('Antropología', 'universitario'),
        ('Ciencia Política', 'universitario'),
        ('Comunicación Social', 'universitario'),
        ('Pedagogía', 'terciario'),
        ('Didáctica', 'terciario'),
        ('Literatura', 'secundario'),
        ('Lengua', 'primario'),
        ('Educación Cívica', 'secundario')
) AS categorias(nombre, nivel);

CREATE UNIQUE INDEX
    ON categorias_catalogo (nombre, nivel);

INSERT INTO public.categorias (
    nombre,
    nivel,
    descripcion,
    "createdAt",
    "updatedAt"
)
SELECT
    nombre,
    nivel::public.enum_categorias_nivel,
    'Apoyo académico en ' || nombre || ' para nivel ' || nivel || '.',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM categorias_catalogo
ON CONFLICT (nombre, nivel) DO NOTHING;

-- Tarifas por hora, según los valores actuales del proyecto.
CREATE TEMP TABLE precios_catalogo ON COMMIT DROP AS
SELECT *
FROM (
    VALUES
        ('primario', 'presencial', 5000),
        ('primario', 'virtual', 4000),
        ('secundario', 'presencial', 8000),
        ('secundario', 'virtual', 7000),
        ('terciario', 'presencial', 10000),
        ('terciario', 'virtual', 9000),
        ('universitario', 'presencial', 11000),
        ('universitario', 'virtual', 10000),
        ('doctorado', 'presencial', 13000),
        ('doctorado', 'virtual', 12000)
) AS tarifas(nivel, modalidad, precio);

CREATE UNIQUE INDEX
    ON precios_catalogo (nivel, modalidad);

INSERT INTO public.precios (
    nivel,
    modalidad,
    precio,
    "createdAt",
    "updatedAt"
)
SELECT
    nivel::public.enum_precios_nivel,
    modalidad::public.enum_precios_modalidad,
    precio,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM precios_catalogo
ON CONFLICT (nivel, modalidad) DO NOTHING;

DO $verificacion$
BEGIN
    IF (SELECT COUNT(*) FROM categorias_catalogo) <> 100 THEN
    RAISE EXCEPTION 'El catálogo debe definir 100 categorías.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM categorias_catalogo esperado
        LEFT JOIN public.categorias categoria
            ON categoria.nombre = esperado.nombre
           AND categoria.nivel =
               esperado.nivel::public.enum_categorias_nivel
        WHERE categoria.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Faltan categorías del catálogo.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM precios_catalogo esperado
        LEFT JOIN public.precios tarifa
            ON tarifa.nivel =
               esperado.nivel::public.enum_precios_nivel
           AND tarifa.modalidad =
               esperado.modalidad::public.enum_precios_modalidad
        WHERE tarifa.id IS NULL
           OR tarifa.precio IS DISTINCT FROM
               esperado.precio::double precision
    ) THEN
        RAISE EXCEPTION
            'Faltan tarifas o sus importes difieren del catálogo.';
    END IF;

    RAISE NOTICE 'Catálogo de categorías y tarifas verificado.';
END;
$verificacion$;

COMMIT;

SELECT
    (SELECT COUNT(*) FROM public.categorias) AS categorias_totales,
    (SELECT COUNT(*) FROM public.precios) AS tarifas_totales;