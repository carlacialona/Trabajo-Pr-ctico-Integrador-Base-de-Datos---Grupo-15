-- =====================================================================
-- 007_roles.sql · Etapa 2: roles y privilegios mínimos
--
--   Rol               Quién lo usa             Qué puede hacer
--   ----------------  -----------------------  ---------------------------
--   (propietario)     migraciones y carga      todo: es dueño de los objetos.
--                     (bodegas_owner en Docker; el rol administrador del
--                     proveedor en la nube)
--   bodegas_api       la API REST              leer todo; escribir solo las
--                                              tablas de negocio; NO escribe
--                                              stock, auditoría ni importes
--                                              del comprobante (lo hacen los
--                                              triggers y procedimientos).
--   bodegas_lectura   reportes / consultas     solo SELECT.
--
-- Las contraseñas NO están acá: se asignan desde variables de entorno
-- (db/docker-init/00_init.sh o a mano en la nube). Ver README.
-- =====================================================================

-- Los roles son globales del servidor: se crean solo si no existen, para que
-- el script se pueda correr sobre una base nueva en un servidor que ya los tiene.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bodegas_api') THEN
        CREATE ROLE bodegas_api LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'bodegas_lectura') THEN
        CREATE ROLE bodegas_lectura LOGIN;
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 1. Quitar los privilegios que PostgreSQL da por defecto a PUBLIC.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO bodegas_api, bodegas_lectura',
                   current_database());
END
$$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
-- Las funciones y procedimientos nacen con EXECUTE para PUBLIC.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO bodegas_api, bodegas_lectura;

-- ---------------------------------------------------------------------
-- 2. bodegas_lectura: solo lectura.
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodegas_lectura;   -- incluye vistas
GRANT SELECT ON mv_ventas_mensuales_sala TO bodegas_lectura;
GRANT EXECUTE ON FUNCTION
    fn_descuento_por_tipo(tipo_cliente),
    fn_descuento_cliente(INTEGER),
    fn_stock_sala(INTEGER, INTEGER),
    fn_stock_total(INTEGER),
    fn_subtotal_renglon(INTEGER, NUMERIC, NUMERIC),
    fn_total_comprobante(INTEGER),
    fn_antiguedad_anios(DATE)
TO bodegas_lectura;

-- ---------------------------------------------------------------------
-- 3. bodegas_api: lectura de todo + escritura de las tablas de negocio.
-- ---------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodegas_api;
GRANT SELECT ON mv_ventas_mensuales_sala TO bodegas_api;

GRANT INSERT, UPDATE, DELETE ON
    localidad, sala_venta, empleado,
    bodega, vino, composicion, vino_maridaje,
    cliente, distribuidor, exportador, permiso_exportacion,
    transportista, transportista_localidad,
    ingreso, renglon_ingreso,
    transferencia, renglon_transferencia
TO bodegas_api;

-- Ventas: alta y baja, pero NO UPDATE. Los importes los escribe el trigger
-- (que corre como dueño). Así la API no puede cargar un total a mano.
GRANT INSERT, DELETE ON comprobante, renglon_comprobante TO bodegas_api;

-- Sin INSERT/UPDATE/DELETE sobre stock_sala, stock_deposito ni
-- auditoria_precio: el stock solo se mueve por triggers y procedimientos.

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO bodegas_api;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO bodegas_api;
