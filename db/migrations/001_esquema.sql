-- =====================================================================
-- 001_esquema.sql · Etapa 1: esquema físico
-- Bodegas del Atuel · TPI Bases de Datos · UTN FRSR
--
-- Contenido: tipos enumerados, dominios, tablas, claves primarias,
-- claves foráneas (con sus acciones referenciales) y NOT NULL.
-- Las restricciones adicionales (UNIQUE, CHECK, DEFAULT) están en 002.
--
-- Convenciones:
--   * PK subrogadas con GENERATED ALWAYS AS IDENTITY cuando no hay una
--     clave natural estable; CUIT como PK natural en bodega y empleado.
--   * Dinero siempre NUMERIC (dominio "dinero"), nunca FLOAT.
--   * Estados con tipo ENUM, nunca texto libre.
--   * ON DELETE RESTRICT en todo lo que es un "movimiento" o un catálogo
--     referenciado; ON DELETE CASCADE solo en tablas que no existen sin
--     su cabecera (renglones, parcelas, subtipos, composición).
--   * ON UPDATE CASCADE solo donde la PK es natural (CUIT), porque es la
--     única que se puede corregir. Las IDENTITY no se actualizan.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------
CREATE TYPE estado_documento AS ENUM ('en_confeccion', 'terminado', 'procesado');
CREATE TYPE tipo_cliente     AS ENUM ('socio', 'distribuidor', 'exportador');
CREATE TYPE tipo_vino        AS ENUM ('tinto', 'blanco', 'rosado', 'espumante');
CREATE TYPE tipo_cepa        AS ENUM ('tinta', 'blanca');
CREATE TYPE tipo_documento   AS ENUM ('DNI', 'CUIT', 'PASAPORTE');
CREATE TYPE dia_semana       AS ENUM ('lunes', 'martes', 'miercoles', 'jueves',
                                      'viernes', 'sabado', 'domingo');

-- ---------------------------------------------------------------------
-- Dominios
-- ---------------------------------------------------------------------
-- CUIT argentino: exactamente 11 dígitos, sin guiones.
CREATE DOMAIN cuit_dom AS CHAR(11)
    CHECK (VALUE ~ '^[0-9]{11}$');

-- Importes de dinero. La positividad se controla con CHECK en cada columna,
-- porque algunos importes pueden ser 0 (descuento) y otros no (precio).
CREATE DOMAIN dinero AS NUMERIC(12, 2);

-- Correo electrónico con formato mínimo válido.
CREATE DOMAIN email_dom AS VARCHAR(120)
    CHECK (VALUE ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');

-- =====================================================================
-- Geografía
-- =====================================================================
CREATE TABLE provincia (
    id_provincia  SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        VARCHAR(60) NOT NULL
);

-- Departamento es tabla propia (y no dos columnas en finca) para evitar la
-- dependencia transitiva finca -> departamento -> provincia (3FN).
CREATE TABLE departamento (
    id_departamento INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(60) NOT NULL,
    id_provincia    SMALLINT    NOT NULL
        REFERENCES provincia (id_provincia) ON DELETE RESTRICT
);

-- El encargado regional depende de la LOCALIDAD (RN-02). Por eso vive acá y
-- no en sala_venta: si estuviera en la sala, sala -> localidad -> encargado
-- sería una dependencia transitiva y dos salas de la misma localidad podrían
-- tener encargados distintos.
-- El código postal NO es clave: en Argentina varias localidades lo comparten.
CREATE TABLE localidad (
    id_localidad       INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre             VARCHAR(80) NOT NULL,
    codigo_postal      VARCHAR(8)  NOT NULL,
    id_departamento    INTEGER     NOT NULL
        REFERENCES departamento (id_departamento) ON DELETE RESTRICT,
    encargado_regional VARCHAR(80) NOT NULL
);

-- =====================================================================
-- Salas y empleados
-- =====================================================================
CREATE TABLE sala_venta (
    id_sala      INTEGER     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    calle        VARCHAR(80) NOT NULL,
    numero       INTEGER     NOT NULL,
    dia_cierre   dia_semana  NOT NULL,
    id_localidad INTEGER     NOT NULL
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT
);

-- RN-03: cada empleado trabaja en una sola sala -> FK NOT NULL.
CREATE TABLE empleado (
    cuit          cuit_dom     PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,
    fecha_ingreso DATE         NOT NULL,
    salario       dinero       NOT NULL,
    id_sala       INTEGER      NOT NULL
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT
);

-- =====================================================================
-- Producción de uva
-- =====================================================================
CREATE TABLE finca (
    id_finca        INTEGER       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(80)   NOT NULL,
    superficie_ha   NUMERIC(10,2) NOT NULL,
    id_departamento INTEGER       NOT NULL
        REFERENCES departamento (id_departamento) ON DELETE RESTRICT
);

CREATE TABLE cepa (
    id_cepa SMALLINT    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre  VARCHAR(40) NOT NULL,
    tipo    tipo_cepa   NOT NULL
);

-- Entidad débil: la parcela se identifica por (finca, número).
-- ON DELETE CASCADE desde finca porque una parcela no existe sin su finca.
-- RN-04 (una sola cepa): id_cepa es un atributo monovaluado NOT NULL.
CREATE TABLE parcela (
    id_finca        INTEGER      NOT NULL
        REFERENCES finca (id_finca) ON DELETE CASCADE,
    nro_parcela     SMALLINT     NOT NULL,
    superficie_ha   NUMERIC(8,2) NOT NULL,
    anio_plantacion SMALLINT     NOT NULL,
    id_cepa         SMALLINT     NOT NULL
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT,
    PRIMARY KEY (id_finca, nro_parcela)
);

CREATE TABLE bodega (
    cuit         cuit_dom     PRIMARY KEY,
    razon_social VARCHAR(120) NOT NULL,
    domicilio    VARCHAR(150) NOT NULL
);

-- Lote de uva: tiene dos claves candidatas.
--   * nro_lote (elegida como PK, la usan los análisis)
--   * (id_finca, nro_parcela, campania) -> UNIQUE en 002 = RN-04
CREATE TABLE lote_uva (
    nro_lote      INTEGER       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_finca      INTEGER       NOT NULL,
    nro_parcela   SMALLINT      NOT NULL,
    campania      SMALLINT      NOT NULL,
    fecha_cosecha DATE          NOT NULL,
    kilos         NUMERIC(12,2) NOT NULL,
    cuit_bodega   cuit_dom      NOT NULL
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (id_finca, nro_parcela)
        REFERENCES parcela (id_finca, nro_parcela) ON DELETE RESTRICT
);

-- Varios análisis por lote (atributo multivaluado -> tabla propia, 1FN).
CREATE TABLE analisis_calidad (
    id_analisis  INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nro_lote     INTEGER      NOT NULL
        REFERENCES lote_uva (nro_lote) ON DELETE CASCADE,
    fecha        DATE         NOT NULL,
    brix         NUMERIC(4,1) NOT NULL,
    ph           NUMERIC(3,2) NOT NULL,
    acidez_total NUMERIC(4,2) NOT NULL
);

-- =====================================================================
-- Vinos
-- =====================================================================
-- RN-01: el precio es un atributo de vino (uno solo para toda la red).
CREATE TABLE vino (
    cod_vino    INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(80)  NOT NULL,
    tipo        tipo_vino    NOT NULL,
    anada       SMALLINT     NOT NULL,
    volumen_ml  SMALLINT     NOT NULL,
    graduacion  NUMERIC(4,2) NOT NULL,
    precio      dinero       NOT NULL,
    cuit_bodega cuit_dom     NOT NULL
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

-- N:M vino-cepa con atributo (porcentaje de corte).
CREATE TABLE composicion (
    cod_vino   INTEGER      NOT NULL
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    id_cepa    SMALLINT     NOT NULL
        REFERENCES cepa (id_cepa) ON DELETE RESTRICT,
    porcentaje NUMERIC(5,2) NOT NULL,
    PRIMARY KEY (cod_vino, id_cepa)
);

CREATE TABLE maridaje (
    id_maridaje          SMALLINT     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre               VARCHAR(60)  NOT NULL,
    temperatura_servicio NUMERIC(4,1) NOT NULL
);

CREATE TABLE vino_maridaje (
    cod_vino    INTEGER  NOT NULL
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    id_maridaje SMALLINT NOT NULL
        REFERENCES maridaje (id_maridaje) ON DELETE RESTRICT,
    PRIMARY KEY (cod_vino, id_maridaje)
);

-- =====================================================================
-- Clientes: supertipo + subtipos
-- =====================================================================
-- "nombre" guarda el apellido y nombre (personas) o la razón social (empresas).
-- El descuento se ALMACENA: se inicializa por trigger según el tipo (RN-06)
-- y puede ajustarse después (consulta U6 lo sube al 35 % a ciertos exportadores).
-- UNIQUE (id_cliente, tipo) existe solo para que los subtipos lo referencien
-- y así sea imposible cargar un distribuidor que apunte a un cliente socio.
CREATE TABLE cliente (
    id_cliente   INTEGER        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo         tipo_cliente   NOT NULL,
    nombre       VARCHAR(120)   NOT NULL,
    tipo_doc     tipo_documento NOT NULL,
    nro_doc      VARCHAR(20)    NOT NULL,
    direccion    VARCHAR(150)   NOT NULL,
    id_localidad INTEGER        NOT NULL
        REFERENCES localidad (id_localidad) ON DELETE RESTRICT,
    fecha_alta   DATE           NOT NULL,
    descuento    NUMERIC(5,2)   NOT NULL,
    CONSTRAINT uq_cliente_id_tipo UNIQUE (id_cliente, tipo)
);

-- Subtipo sin atributos propios (socio) NO tiene tabla: queda representado
-- por cliente.tipo = 'socio'.
-- La FK compuesta (id_cliente, tipo) + CHECK (tipo = 'distribuidor') en 002
-- garantiza que el subtipo coincide con el tipo del supertipo.
CREATE TABLE distribuidor (
    id_cliente       INTEGER      PRIMARY KEY,
    tipo             tipo_cliente NOT NULL,
    zona_cobertura   VARCHAR(100) NOT NULL,
    nro_habilitacion VARCHAR(20)  NOT NULL,
    CONSTRAINT fk_distribuidor_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE
);

CREATE TABLE exportador (
    id_cliente   INTEGER      PRIMARY KEY,
    tipo         tipo_cliente NOT NULL,
    pais_destino VARCHAR(60)  NOT NULL,
    CONSTRAINT fk_exportador_cliente FOREIGN KEY (id_cliente, tipo)
        REFERENCES cliente (id_cliente, tipo) ON DELETE CASCADE
);

-- RN-07: varios permisos por exportador. La FK apunta a EXPORTADOR (no a
-- cliente), así que es imposible darle un permiso a un socio o distribuidor.
CREATE TABLE permiso_exportacion (
    cod_permiso       VARCHAR(20) PRIMARY KEY,
    id_cliente        INTEGER     NOT NULL
        REFERENCES exportador (id_cliente) ON DELETE CASCADE,
    fecha_emision     DATE        NOT NULL,
    fecha_vencimiento DATE        NOT NULL
);

-- =====================================================================
-- Ventas
-- =====================================================================
-- subtotal, descuento y total son atributos DERIVADOS que se almacenan
-- (por rendimiento y para conservar el histórico). Su consistencia la
-- garantizan los triggers de 005 (RN-08): nunca se cargan a mano.
CREATE TABLE comprobante (
    nro_comprobante INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha           DATE    NOT NULL,
    id_cliente      INTEGER NOT NULL
        REFERENCES cliente (id_cliente) ON DELETE RESTRICT,
    id_sala         INTEGER NOT NULL
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT,
    subtotal        dinero  NOT NULL,
    descuento       dinero  NOT NULL,
    total           dinero  NOT NULL
);

-- N:M comprobante-vino con atributos. precio_unitario NO es redundante con
-- vino.precio: es el precio AL MOMENTO de la venta, depende de
-- (comprobante, vino) y conserva el histórico si el precio cambia.
CREATE TABLE renglon_comprobante (
    nro_comprobante      INTEGER      NOT NULL
        REFERENCES comprobante (nro_comprobante) ON DELETE CASCADE,
    cod_vino             INTEGER      NOT NULL
        REFERENCES vino (cod_vino) ON DELETE RESTRICT,
    cantidad             INTEGER      NOT NULL,
    precio_unitario      dinero       NOT NULL,
    porcentaje_descuento NUMERIC(5,2) NOT NULL,
    subtotal             dinero       NOT NULL,
    PRIMARY KEY (nro_comprobante, cod_vino)
);

-- =====================================================================
-- Transporte, ingresos y transferencias
-- =====================================================================
CREATE TABLE transportista (
    cod_transporte INTEGER      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    razon_social   VARCHAR(120) NOT NULL,
    cuit           cuit_dom     NOT NULL,
    email          email_dom    NOT NULL,
    telefono       VARCHAR(30)  NOT NULL,
    domicilio      VARCHAR(150) NOT NULL
);

CREATE TABLE transportista_localidad (
    cod_transporte INTEGER NOT NULL
        REFERENCES transportista (cod_transporte) ON DELETE CASCADE,
    id_localidad   INTEGER NOT NULL
        REFERENCES localidad (id_localidad) ON DELETE CASCADE,
    PRIMARY KEY (cod_transporte, id_localidad)
);

-- RN-14: un transportista o una bodega con ingresos no se puede borrar.
CREATE TABLE ingreso (
    cod_ingreso    INTEGER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha          DATE             NOT NULL,
    estado         estado_documento NOT NULL,
    cod_transporte INTEGER          NOT NULL
        REFERENCES transportista (cod_transporte) ON DELETE RESTRICT,
    cuit_bodega    cuit_dom         NOT NULL
        REFERENCES bodega (cuit) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE renglon_ingreso (
    cod_ingreso INTEGER NOT NULL
        REFERENCES ingreso (cod_ingreso) ON DELETE CASCADE,
    cod_vino    INTEGER NOT NULL
        REFERENCES vino (cod_vino) ON DELETE RESTRICT,
    cantidad    INTEGER NOT NULL,
    PRIMARY KEY (cod_ingreso, cod_vino)
);

CREATE TABLE transferencia (
    nro_transferencia INTEGER          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_sala           INTEGER          NOT NULL
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT,
    fecha_confeccion  DATE             NOT NULL,
    estado            estado_documento NOT NULL
);

CREATE TABLE renglon_transferencia (
    nro_transferencia INTEGER NOT NULL
        REFERENCES transferencia (nro_transferencia) ON DELETE CASCADE,
    cod_vino          INTEGER NOT NULL
        REFERENCES vino (cod_vino) ON DELETE RESTRICT,
    cantidad          INTEGER NOT NULL,
    PRIMARY KEY (nro_transferencia, cod_vino)
);

-- =====================================================================
-- Stock
-- =====================================================================
-- N:M sala-vino con atributo cantidad. CASCADE desde vino: un vino solo
-- puede tener stock a través de movimientos (que son RESTRICT), así que
-- borrar un vino sin movimientos solo arrastra filas en cero.
CREATE TABLE stock_sala (
    id_sala  INTEGER NOT NULL
        REFERENCES sala_venta (id_sala) ON DELETE RESTRICT,
    cod_vino INTEGER NOT NULL
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_sala, cod_vino)
);

-- Relación 1:1 con vino (un solo depósito central). Tabla aparte y no
-- columna de vino porque cambia con cada movimiento (el precio casi nunca)
-- y para no disparar la auditoría de precio en cada movimiento de stock.
CREATE TABLE stock_deposito (
    cod_vino INTEGER PRIMARY KEY
        REFERENCES vino (cod_vino) ON DELETE CASCADE,
    cantidad INTEGER NOT NULL
);

-- =====================================================================
-- Auditoría (RN-13). La completa un trigger; nadie la escribe a mano.
-- RESTRICT: un vino con historial de precios no se borra (no se pierde
-- la auditoría).
-- =====================================================================
CREATE TABLE auditoria_precio (
    id_auditoria    BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cod_vino        INTEGER     NOT NULL
        REFERENCES vino (cod_vino) ON DELETE RESTRICT,
    precio_anterior dinero      NOT NULL,
    precio_nuevo    dinero      NOT NULL,
    fecha_hora      TIMESTAMPTZ NOT NULL,
    usuario         VARCHAR(63) NOT NULL
);
