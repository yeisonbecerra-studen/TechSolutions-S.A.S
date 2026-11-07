-- =====================================================================
-- TechSolutions S.A.S. - 01 Esquema
-- Sistema de Gestión de Activos TI y Mesa de Ayuda
-- Se ejecuta automáticamente al crear el contenedor por primera vez.
-- =====================================================================

-- Extensión de monitoreo de consultas (requiere shared_preload_libraries)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Separación lógica: datos del negocio vs. evidencias de auditoría
CREATE SCHEMA app;
CREATE SCHEMA auditoria;

COMMENT ON SCHEMA app IS 'Datos operativos: empleados, activos TI y mesa de ayuda';
COMMENT ON SCHEMA auditoria IS 'Registro de cambios y de respaldos (solo lectura para auditores)';

-- ---------------------------------------------------------------------
-- Tablas del negocio (6)
-- ---------------------------------------------------------------------
CREATE TABLE app.departamentos (
    id            serial PRIMARY KEY,
    nombre        varchar(60) NOT NULL UNIQUE,
    centro_costo  varchar(10) NOT NULL
);

CREATE TABLE app.empleados (
    id               serial PRIMARY KEY,
    documento        varchar(15) NOT NULL UNIQUE,      -- dato personal (Ley 1581 de 2012)
    nombres          varchar(60) NOT NULL,
    apellidos        varchar(60) NOT NULL,
    correo           varchar(120) NOT NULL UNIQUE,
    cargo            varchar(60) NOT NULL,
    departamento_id  int NOT NULL REFERENCES app.departamentos(id),
    mfa_activo       boolean NOT NULL DEFAULT false,
    fecha_ingreso    date NOT NULL,
    activo           boolean NOT NULL DEFAULT true
);

CREATE TABLE app.categorias_activo (
    id               serial PRIMARY KEY,
    nombre           varchar(40) NOT NULL UNIQUE,
    vida_util_meses  int NOT NULL CHECK (vida_util_meses > 0)
);

-- Inventario de activos tecnológicos (hallazgo de auditoría: no existía)
CREATE TABLE app.activos (
    id                      serial PRIMARY KEY,
    codigo                  varchar(20) NOT NULL UNIQUE,
    categoria_id            int NOT NULL REFERENCES app.categorias_activo(id),
    marca                   varchar(40) NOT NULL,
    modelo                  varchar(60) NOT NULL,
    serial                  varchar(40) NOT NULL UNIQUE,
    empleado_id             int REFERENCES app.empleados(id),
    estado                  varchar(15) NOT NULL DEFAULT 'BODEGA'
                            CHECK (estado IN ('EN_USO','BODEGA','MANTENIMIENTO','DADO_DE_BAJA')),
    ubicacion               varchar(20) NOT NULL DEFAULT 'OFICINA_BOGOTA'
                            CHECK (ubicacion IN ('OFICINA_BOGOTA','REMOTO','NUBE_AWS')),
    fecha_compra            date NOT NULL,
    valor_compra            numeric(14,2) NOT NULL CHECK (valor_compra >= 0),
    ultima_actualizacion_so date            -- hallazgo: equipos sin parches
);

CREATE TABLE app.tickets (
    id              bigserial PRIMARY KEY,
    activo_id       int REFERENCES app.activos(id),
    solicitante_id  int NOT NULL REFERENCES app.empleados(id),
    tecnico_id      int REFERENCES app.empleados(id),
    categoria       varchar(12) NOT NULL
                    CHECK (categoria IN ('HARDWARE','SOFTWARE','ACCESOS','RED','SEGURIDAD')),
    prioridad       varchar(8) NOT NULL DEFAULT 'MEDIA'
                    CHECK (prioridad IN ('BAJA','MEDIA','ALTA','CRITICA')),
    estado          varchar(12) NOT NULL DEFAULT 'ABIERTO'
                    CHECK (estado IN ('ABIERTO','EN_PROCESO','CERRADO')),
    titulo          varchar(120) NOT NULL,
    descripcion     text,
    creado_en       timestamptz NOT NULL DEFAULT now(),
    cerrado_en      timestamptz
);
-- NOTA: a propósito NO se crean índices sobre tickets(estado, creado_en) ni
-- sobre las llaves foráneas. sql/optimizacion.sql los crea y mide la mejora.

CREATE TABLE app.mantenimientos (
    id           serial PRIMARY KEY,
    activo_id    int NOT NULL REFERENCES app.activos(id),
    tipo         varchar(12) NOT NULL CHECK (tipo IN ('PREVENTIVO','CORRECTIVO','PARCHE_SO')),
    fecha        date NOT NULL DEFAULT current_date,
    descripcion  varchar(200) NOT NULL,
    costo        numeric(12,2) NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------
-- Tablas de auditoría (2)
-- ---------------------------------------------------------------------
CREATE TABLE auditoria.log_cambios (
    id             bigserial PRIMARY KEY,
    fecha          timestamptz NOT NULL DEFAULT now(),
    usuario_bd     text NOT NULL DEFAULT session_user,
    aplicacion     text DEFAULT current_setting('application_name', true),
    ip_cliente     inet DEFAULT inet_client_addr(),
    tabla          text NOT NULL,
    operacion      text NOT NULL,
    datos_antes    jsonb,
    datos_despues  jsonb
);

CREATE TABLE auditoria.log_respaldos (
    id            serial PRIMARY KEY,
    archivo       text NOT NULL,
    tamano_bytes  bigint NOT NULL,
    sha256        char(64) NOT NULL,
    inicio        timestamptz NOT NULL,
    fin           timestamptz NOT NULL DEFAULT now(),
    estado        varchar(10) NOT NULL CHECK (estado IN ('OK','FALLIDO'))
);

-- ---------------------------------------------------------------------
-- Vistas de apoyo a la auditoría de sistemas
-- ---------------------------------------------------------------------
CREATE VIEW app.v_equipos_sin_parches AS
SELECT a.codigo, c.nombre AS categoria, a.marca, a.modelo,
       e.nombres || ' ' || e.apellidos AS responsable,
       a.ultima_actualizacion_so,
       current_date - a.ultima_actualizacion_so AS dias_sin_actualizar
FROM app.activos a
JOIN app.categorias_activo c ON c.id = a.categoria_id
LEFT JOIN app.empleados e ON e.id = a.empleado_id
WHERE c.nombre IN ('Portátil','Equipo de escritorio','Servidor')
  AND a.estado <> 'DADO_DE_BAJA'
  AND (a.ultima_actualizacion_so IS NULL OR a.ultima_actualizacion_so < current_date - 30);

CREATE VIEW app.v_empleados_sin_mfa AS
SELECT d.nombre AS departamento,
       count(*) AS empleados,
       count(*) FILTER (WHERE NOT e.mfa_activo) AS sin_mfa,
       round(100.0 * count(*) FILTER (WHERE NOT e.mfa_activo) / count(*), 1) AS pct_sin_mfa
FROM app.empleados e
JOIN app.departamentos d ON d.id = e.departamento_id
WHERE e.activo
GROUP BY d.nombre;
