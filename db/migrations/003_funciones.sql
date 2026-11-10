-- =====================================================================
-- 003_funciones.sql · Etapa 2: funciones
-- Cálculos que se usan en varios lugares (triggers, procedimientos,
-- consultas y la API). La API NO recalcula: llama a estas funciones.
--
-- Volatilidad:
--   IMMUTABLE -> mismo resultado para los mismos argumentos, siempre.
--   STABLE    -> no modifica datos y da el mismo resultado dentro de una
--                misma sentencia (lee tablas o la fecha actual).
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_descuento_por_tipo(tipo) -> porcentaje
-- Propósito: descuento base que corresponde a cada tipo de cliente (RN-06).
-- Lo usa el trigger que inicializa cliente.descuento.
-- IMMUTABLE: depende solo del argumento.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_por_tipo(p_tipo tipo_cliente)
RETURNS NUMERIC(5,2)
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_tipo
               WHEN 'socio'        THEN 10.00
               WHEN 'distribuidor' THEN 20.00
               WHEN 'exportador'   THEN 30.00
           END::NUMERIC(5,2);
$$;

-- ---------------------------------------------------------------------
-- fn_descuento_cliente(id_cliente) -> porcentaje
-- Propósito: descuento vigente de un cliente (el de su tipo, salvo que se
-- haya ajustado, como en U6). Lo usa el trigger de renglones de venta.
-- STABLE: lee la tabla cliente.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_descuento_cliente(p_id_cliente INTEGER)
RETURNS NUMERIC(5,2)
LANGUAGE sql STABLE AS $$
    SELECT descuento FROM cliente WHERE id_cliente = p_id_cliente;
$$;

-- ---------------------------------------------------------------------
-- fn_stock_sala(sala, vino) -> botellas disponibles en la sala
-- Propósito: consultar stock sin preocuparse de que falte la fila (0).
-- STABLE: lee stock_sala.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_sala(p_sala INTEGER, p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT cantidad FROM stock_sala
          WHERE id_sala = p_sala AND cod_vino = p_vino), 0);
$$;

-- ---------------------------------------------------------------------
-- fn_stock_total(vino) -> depósito + todas las salas
-- STABLE: lee stock_deposito y stock_sala.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_stock_total(p_vino INTEGER)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT cantidad FROM stock_deposito WHERE cod_vino = p_vino), 0)
         + COALESCE((SELECT SUM(cantidad) FROM stock_sala WHERE cod_vino = p_vino), 0)::INTEGER;
$$;

-- ---------------------------------------------------------------------
-- fn_subtotal_renglon(cantidad, precio, porcentaje) -> importe del renglón
-- Propósito: una sola fórmula para el subtotal con descuento (RN-08).
-- IMMUTABLE: solo aritmética sobre los argumentos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_subtotal_renglon(
    p_cantidad INTEGER, p_precio NUMERIC, p_porcentaje NUMERIC)
RETURNS NUMERIC(12,2)
LANGUAGE sql IMMUTABLE AS $$
    SELECT ROUND(p_cantidad * p_precio * (1 - p_porcentaje / 100), 2);
$$;

-- ---------------------------------------------------------------------
-- fn_total_comprobante(nro) -> total con descuento aplicado
-- Propósito: el total de un comprobante es la suma de sus renglones (RN-08).
-- La usan el trigger de recálculo, la consulta de control y la API.
-- STABLE: lee renglon_comprobante.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_total_comprobante(p_nro INTEGER)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(subtotal), 0)::NUMERIC(12,2)
      FROM renglon_comprobante
     WHERE nro_comprobante = p_nro;
$$;

-- ---------------------------------------------------------------------
-- fn_antiguedad_anios(fecha) -> años completos transcurridos hasta hoy
-- Propósito: antigüedad de empleados (U2), clientes (D4), comprobantes (D1).
-- STABLE y NO IMMUTABLE: depende de CURRENT_DATE, que cambia de un día
-- a otro (por eso tampoco se puede usar en un índice ni en un CHECK).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_antiguedad_anios(p_fecha DATE)
RETURNS INTEGER
LANGUAGE sql STABLE AS $$
    SELECT EXTRACT(YEAR FROM age(CURRENT_DATE, p_fecha))::INTEGER;
$$;

-- ---------------------------------------------------------------------
-- fn_recalcular_comprobante(nro)
-- Propósito: guarda en la cabecera subtotal, descuento y total a partir de
-- los renglones (RN-08). Solo la invoca el trigger de renglones.
-- SECURITY DEFINER: la API no tiene permiso UPDATE sobre comprobante;
-- esta función corre con los permisos del dueño.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalcular_comprobante(p_nro INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_bruto NUMERIC(12,2);
    v_neto  NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(cantidad * precio_unitario), 0),
           COALESCE(SUM(subtotal), 0)
      INTO v_bruto, v_neto
      FROM renglon_comprobante
     WHERE nro_comprobante = p_nro;

    UPDATE comprobante
       SET subtotal  = v_bruto,
           descuento = v_bruto - v_neto,
           total     = v_neto
     WHERE nro_comprobante = p_nro;
END;
$$;
