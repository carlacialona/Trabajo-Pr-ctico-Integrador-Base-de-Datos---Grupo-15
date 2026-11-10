-- =====================================================================
-- 004_procedimientos.sql · Etapa 2: procedimientos transaccionales
--
-- Procesar un ingreso o una transferencia es una operación de varios
-- pasos que debe ser "todo o nada": validar el estado, bloquear filas,
-- mover stock y cambiar el estado. Si cualquier paso lanza una excepción,
-- PostgreSQL revierte TODO lo que hizo la llamada (no quedan cambios a
-- medias). Por eso va en un procedimiento y no en la API.
--
-- Ambos son SECURITY DEFINER: la API no tiene permiso para escribir el
-- stock directamente; solo puede moverlo a través de estos procedimientos.
--
-- La marca de sesión 'bodegas.procesando' le avisa al trigger de estados
-- que el pase a 'procesado' viene del procedimiento (y no de un UPDATE
-- manual que no movería stock). Con is_local = true dura solo hasta el
-- fin de la transacción.
-- =====================================================================

-- ---------------------------------------------------------------------
-- sp_procesar_ingreso(cod_ingreso)  · RN-10
-- Suma al depósito central las botellas de un ingreso TERMINADO y lo
-- pasa a PROCESADO.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_ingreso(p_cod_ingreso INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_estado estado_documento;
BEGIN
    -- 1. Bloquear la cabecera: si dos sesiones intentan procesar el mismo
    --    ingreso a la vez, la segunda espera y luego ve 'procesado'.
    SELECT estado INTO v_estado
      FROM ingreso
     WHERE cod_ingreso = p_cod_ingreso
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El ingreso % no existe', p_cod_ingreso
            USING ERRCODE = 'P0002';
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'RN-10: solo se procesa un ingreso terminado (el ingreso % está %)',
            p_cod_ingreso, v_estado;
    END IF;

    -- 2. Sumar al depósito (crea la fila si el vino todavía no tenía stock).
    INSERT INTO stock_deposito (cod_vino, cantidad)
    SELECT cod_vino, cantidad
      FROM renglon_ingreso
     WHERE cod_ingreso = p_cod_ingreso
    ON CONFLICT (cod_vino)
    DO UPDATE SET cantidad = stock_deposito.cantidad + EXCLUDED.cantidad;

    -- 3. Cambiar el estado (el trigger valida terminado -> procesado).
    PERFORM set_config('bodegas.procesando', 'on', true);
    UPDATE ingreso SET estado = 'procesado' WHERE cod_ingreso = p_cod_ingreso;
    PERFORM set_config('bodegas.procesando', 'off', true);
END;
$$;

-- ---------------------------------------------------------------------
-- sp_procesar_transferencia(nro_transferencia)  · RN-11
-- Descuenta del depósito y suma a la sala las botellas de una transferencia
-- TERMINADA, y la pasa a PROCESADA. Si el depósito no alcanza para algún
-- vino, no se mueve nada.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_procesar_transferencia(p_nro INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_estado   estado_documento;
    v_sala     INTEGER;
    v_faltante RECORD;
BEGIN
    -- 1. Bloquear la cabecera.
    SELECT estado, id_sala INTO v_estado, v_sala
      FROM transferencia
     WHERE nro_transferencia = p_nro
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La transferencia % no existe', p_nro
            USING ERRCODE = 'P0002';
    END IF;

    IF v_estado <> 'terminado' THEN
        RAISE EXCEPTION 'RN-11: solo se procesa una transferencia terminada (la % está %)',
            p_nro, v_estado;
    END IF;

    -- 2. Bloquear las filas de stock del depósito que se van a tocar, en
    --    orden de cod_vino (siempre el mismo orden evita deadlocks entre
    --    dos transferencias que comparten vinos).
    PERFORM 1
       FROM stock_deposito d
       JOIN renglon_transferencia r ON r.cod_vino = d.cod_vino
      WHERE r.nro_transferencia = p_nro
      ORDER BY d.cod_vino
        FOR UPDATE OF d;

    -- 3. Verificar ANTES de mover nada. Un LEFT JOIN detecta también el vino
    --    que no tiene fila en stock_deposito (el UPDATE no lo vería y no
    --    daría error: es el caso "para pensar" del anexo A.6).
    SELECT r.cod_vino, r.cantidad AS pedido, COALESCE(d.cantidad, 0) AS disponible
      INTO v_faltante
      FROM renglon_transferencia r
      LEFT JOIN stock_deposito d ON d.cod_vino = r.cod_vino
     WHERE r.nro_transferencia = p_nro
       AND COALESCE(d.cantidad, 0) < r.cantidad
     ORDER BY r.cod_vino
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'RN-11: stock insuficiente en el depósito para el vino % (disponible %, pedido %). La transferencia % no se procesó',
            v_faltante.cod_vino, v_faltante.disponible, v_faltante.pedido, p_nro;
    END IF;

    -- 4. Descontar del depósito. El CHECK (cantidad >= 0) es una segunda
    --    barrera si algo cambiara entre la verificación y el UPDATE.
    UPDATE stock_deposito d
       SET cantidad = d.cantidad - r.cantidad
      FROM renglon_transferencia r
     WHERE r.nro_transferencia = p_nro
       AND d.cod_vino = r.cod_vino;

    -- 5. Sumar a la sala (crea la fila si no existía).
    INSERT INTO stock_sala (id_sala, cod_vino, cantidad)
    SELECT v_sala, cod_vino, cantidad
      FROM renglon_transferencia
     WHERE nro_transferencia = p_nro
    ON CONFLICT (id_sala, cod_vino)
    DO UPDATE SET cantidad = stock_sala.cantidad + EXCLUDED.cantidad;

    -- 6. Cambiar el estado.
    PERFORM set_config('bodegas.procesando', 'on', true);
    UPDATE transferencia SET estado = 'procesado' WHERE nro_transferencia = p_nro;
    PERFORM set_config('bodegas.procesando', 'off', true);
END;
$$;
