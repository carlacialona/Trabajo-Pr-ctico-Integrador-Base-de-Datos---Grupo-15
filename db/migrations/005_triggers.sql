-- =====================================================================
-- 005_triggers.sql · Etapa 2: triggers
--
-- Un trigger es la herramienta para reglas que dependen de OTRAS filas,
-- de OTRAS tablas o de la fecha actual (un CHECK no puede hacerlo).
--
--   Trigger                                   Momento            Regla
--   ----------------------------------------  -----------------  ----------
--   trg_cliente_descuento                     BEFORE INSERT      RN-06
--   trg_renglon_comprobante_antes             BEFORE INS/UPD     RN-09, RN-08
--   trg_renglon_comprobante_despues           AFTER INS/UPD/DEL  RN-08, RN-09
--   trg_comprobante_importes                  BEFORE INS/UPD     RN-08
--   trg_ingreso_estado / trg_transferencia_estado
--                                             BEFORE INS/UPD     RN-10, RN-11
--   trg_transferencia_fecha                   BEFORE INS/UPD     RN-11
--   trg_renglon_ingreso_bloqueo /
--   trg_renglon_transferencia_bloqueo         BEFORE INS/UPD/DEL RN-12
--   trg_vino_auditoria_precio                 AFTER UPDATE       RN-13
--   trg_composicion_suma_100 /
--   trg_vino_requiere_composicion             CONSTRAINT, DEFERRED  RN-05
-- =====================================================================

-- ---------------------------------------------------------------------
-- RN-06 · Descuento inicial según el tipo de cliente.
-- BEFORE INSERT: modifica NEW antes de guardar. Si quien inserta no manda
-- descuento, se pone el que corresponde al tipo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_cliente_descuento()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.descuento IS NULL THEN
        NEW.descuento := fn_descuento_por_tipo(NEW.tipo);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cliente_descuento
BEFORE INSERT ON cliente
FOR EACH ROW EXECUTE FUNCTION fn_trg_cliente_descuento();

-- ---------------------------------------------------------------------
-- RN-09 · Validación de stock en la venta  +  RN-08 · importes del renglón.
-- BEFORE INSERT OR UPDATE en renglon_comprobante.
--   * Bloquea la fila de stock (FOR UPDATE): si dos ventas piden la última
--     botella al mismo tiempo, la segunda espera y luego ve 0.
--   * Completa precio_unitario (precio vigente del vino), porcentaje de
--     descuento (el del cliente) y subtotal. Quien inserta solo manda
--     vino y cantidad: la API no calcula importes.
--   * Un renglón de venta ya registrado no cambia de vino ni de cantidad.
--     Solo se admite recalcular el descuento (consulta U1).
-- SECURITY DEFINER porque SELECT ... FOR UPDATE sobre stock_sala exige un
-- permiso que la API no tiene.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_renglon_comprobante_antes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sala    INTEGER;
    v_cliente INTEGER;
    v_stock   INTEGER;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.nro_comprobante <> OLD.nro_comprobante
           OR NEW.cod_vino <> OLD.cod_vino
           OR NEW.cantidad <> OLD.cantidad THEN
            RAISE EXCEPTION 'RN-08: un renglón de venta registrado no cambia de vino ni de cantidad (comprobante %). Anule la venta y regístrela de nuevo',
                OLD.nro_comprobante;
        END IF;
        -- El precio histórico se conserva; solo se recalcula el subtotal.
        NEW.precio_unitario := OLD.precio_unitario;
        NEW.subtotal := fn_subtotal_renglon(NEW.cantidad, NEW.precio_unitario,
                                            NEW.porcentaje_descuento);
        RETURN NEW;
    END IF;

    SELECT id_sala, id_cliente INTO v_sala, v_cliente
      FROM comprobante
     WHERE nro_comprobante = NEW.nro_comprobante;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El comprobante % no existe', NEW.nro_comprobante
            USING ERRCODE = '23503';
    END IF;

    SELECT cantidad INTO v_stock
      FROM stock_sala
     WHERE id_sala = v_sala AND cod_vino = NEW.cod_vino
       FOR UPDATE;

    IF COALESCE(v_stock, 0) < NEW.cantidad THEN
        RAISE EXCEPTION 'RN-09: stock insuficiente del vino % en la sala % (disponible %, pedido %)',
            NEW.cod_vino, v_sala, COALESCE(v_stock, 0), NEW.cantidad;
    END IF;

    SELECT precio INTO NEW.precio_unitario FROM vino WHERE cod_vino = NEW.cod_vino;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El vino % no existe', NEW.cod_vino USING ERRCODE = '23503';
    END IF;

    NEW.porcentaje_descuento := fn_descuento_cliente(v_cliente);
    NEW.subtotal := fn_subtotal_renglon(NEW.cantidad, NEW.precio_unitario,
                                        NEW.porcentaje_descuento);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_antes
BEFORE INSERT OR UPDATE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_comprobante_antes();

-- ---------------------------------------------------------------------
-- RN-09 · Descuento de stock  +  RN-08 · cálculo de totales.
-- AFTER INSERT OR UPDATE OR DELETE en renglon_comprobante.
--   * INSERT: resta la cantidad del stock de la sala.
--   * Siempre: recalcula subtotal, descuento y total de la cabecera.
--   * DELETE no devuelve stock: borrar renglones es depurar historial
--     (consulta D1), no anular una venta.
-- Es AFTER porque recién ahí la fila ya está guardada y la suma la incluye.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_renglon_comprobante_despues()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE stock_sala s
           SET cantidad = s.cantidad - NEW.cantidad
          FROM comprobante c
         WHERE c.nro_comprobante = NEW.nro_comprobante
           AND s.id_sala = c.id_sala
           AND s.cod_vino = NEW.cod_vino;
    END IF;

    PERFORM fn_recalcular_comprobante(
        CASE WHEN TG_OP = 'DELETE' THEN OLD.nro_comprobante
             ELSE NEW.nro_comprobante END);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_renglon_comprobante_despues
AFTER INSERT OR UPDATE OR DELETE ON renglon_comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_comprobante_despues();

-- ---------------------------------------------------------------------
-- RN-08 · Los importes del comprobante no se cargan a mano.
-- BEFORE INSERT OR UPDATE en comprobante.
--   * INSERT: la cabecera nace con importes en 0.
--   * UPDATE: solo se aceptan cambios de importes que vengan del trigger
--     de renglones. pg_trigger_depth() = 1 significa que el UPDATE lo
--     escribió alguien directamente; > 1, que lo hizo otro trigger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_comprobante_importes()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.subtotal <> 0 OR NEW.descuento <> 0 OR NEW.total <> 0 THEN
            RAISE EXCEPTION 'RN-08: los importes del comprobante se calculan a partir de sus renglones; no se cargan a mano';
        END IF;
    ELSIF (NEW.subtotal, NEW.descuento, NEW.total)
          IS DISTINCT FROM (OLD.subtotal, OLD.descuento, OLD.total)
          AND pg_trigger_depth() < 2 THEN
        RAISE EXCEPTION 'RN-08: los importes del comprobante % se calculan a partir de sus renglones; no se modifican a mano',
            OLD.nro_comprobante;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_comprobante_importes
BEFORE INSERT OR UPDATE ON comprobante
FOR EACH ROW EXECUTE FUNCTION fn_trg_comprobante_importes();

-- ---------------------------------------------------------------------
-- RN-10 y RN-11 · Máquina de estados de ingresos y transferencias.
-- BEFORE INSERT OR UPDATE en ingreso y transferencia (misma función).
--   * Un documento nace en 'en_confeccion'.
--   * Transiciones válidas: en_confeccion -> terminado -> procesado.
--     No hay retrocesos ni saltos.
--   * No se termina un documento sin renglones.
--   * A 'procesado' solo se llega desde el procedimiento (que es el que
--     mueve el stock). Se reconoce por la marca 'bodegas.procesando'.
--   * Un documento que ya no está en confección no cambia sus datos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_estado_documento()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_doc       TEXT := CASE TG_TABLE_NAME WHEN 'ingreso' THEN 'el ingreso' ELSE 'la transferencia' END;
    v_proc      TEXT := CASE TG_TABLE_NAME WHEN 'ingreso' THEN 'sp_procesar_ingreso' ELSE 'sp_procesar_transferencia' END;
    v_regla     TEXT := CASE TG_TABLE_NAME WHEN 'ingreso' THEN 'RN-10' ELSE 'RN-11' END;
    v_id        INTEGER;
    v_renglones INTEGER;
BEGIN
    IF TG_TABLE_NAME = 'ingreso' THEN
        v_id := NEW.cod_ingreso;
    ELSE
        v_id := NEW.nro_transferencia;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.estado <> 'en_confeccion' THEN
            RAISE EXCEPTION '%: un documento nuevo empieza en estado en_confeccion (se intentó %)',
                v_regla, NEW.estado;
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        IF NOT ((OLD.estado = 'en_confeccion' AND NEW.estado = 'terminado')
             OR (OLD.estado = 'terminado'     AND NEW.estado = 'procesado')) THEN
            RAISE EXCEPTION '%: transición de estado inválida para % % (de % a %). Solo en_confeccion -> terminado -> procesado',
                v_regla, v_doc, v_id, OLD.estado, NEW.estado;
        END IF;

        IF NEW.estado = 'terminado' THEN
            IF TG_TABLE_NAME = 'ingreso' THEN
                SELECT count(*) INTO v_renglones FROM renglon_ingreso WHERE cod_ingreso = v_id;
            ELSE
                SELECT count(*) INTO v_renglones FROM renglon_transferencia WHERE nro_transferencia = v_id;
            END IF;
            IF v_renglones = 0 THEN
                RAISE EXCEPTION '%: % % no tiene renglones y no puede terminarse',
                    v_regla, v_doc, v_id;
            END IF;
        END IF;

        IF NEW.estado = 'procesado'
           AND COALESCE(current_setting('bodegas.procesando', true), 'off') <> 'on' THEN
            RAISE EXCEPTION '%: % % solo puede pasar a procesado mediante %',
                v_regla, v_doc, v_id, v_proc;
        END IF;
    END IF;

    -- Fuera de confección, solo puede cambiar el estado.
    IF OLD.estado <> 'en_confeccion'
       AND (to_jsonb(NEW) - 'estado') IS DISTINCT FROM (to_jsonb(OLD) - 'estado') THEN
        RAISE EXCEPTION '%: % % está % y sus datos no se pueden modificar',
            v_regla, v_doc, v_id, OLD.estado;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ingreso_estado
BEFORE INSERT OR UPDATE ON ingreso
FOR EACH ROW EXECUTE FUNCTION fn_trg_estado_documento();

CREATE TRIGGER trg_transferencia_estado
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_estado_documento();

-- ---------------------------------------------------------------------
-- RN-11 · La fecha de confección de una transferencia es la actual y no
-- se modifica. Va en un trigger porque depende de CURRENT_DATE.
-- (Se llama "trg_a_..." para que se ejecute antes que trg_transferencia_estado:
-- PostgreSQL dispara los triggers del mismo momento por orden alfabético.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_transferencia_fecha()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.fecha_confeccion := CURRENT_DATE;
    ELSIF NEW.fecha_confeccion IS DISTINCT FROM OLD.fecha_confeccion THEN
        RAISE EXCEPTION 'RN-11: la fecha de confección de la transferencia % no se puede modificar',
            OLD.nro_transferencia;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_a_transferencia_fecha
BEFORE INSERT OR UPDATE ON transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_transferencia_fecha();

-- ---------------------------------------------------------------------
-- RN-12 · Un ingreso o una transferencia que no está en confección no
-- admite agregar, modificar ni quitar renglones.
-- BEFORE INSERT OR UPDATE OR DELETE en los renglones.
-- Si la cabecera ya no existe (se está borrando y el CASCADE arrastra los
-- renglones, como en la consulta D5), se permite.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_renglon_documento_bloqueo()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_ids    INTEGER[];
    v_id     INTEGER;
    v_estado estado_documento;
    v_doc    TEXT := CASE TG_TABLE_NAME WHEN 'renglon_ingreso' THEN 'el ingreso' ELSE 'la transferencia' END;
BEGIN
    IF TG_TABLE_NAME = 'renglon_ingreso' THEN
        v_ids := CASE TG_OP
                   WHEN 'INSERT' THEN ARRAY[NEW.cod_ingreso]
                   WHEN 'DELETE' THEN ARRAY[OLD.cod_ingreso]
                   ELSE ARRAY[OLD.cod_ingreso, NEW.cod_ingreso] END;
    ELSE
        v_ids := CASE TG_OP
                   WHEN 'INSERT' THEN ARRAY[NEW.nro_transferencia]
                   WHEN 'DELETE' THEN ARRAY[OLD.nro_transferencia]
                   ELSE ARRAY[OLD.nro_transferencia, NEW.nro_transferencia] END;
    END IF;

    FOREACH v_id IN ARRAY v_ids LOOP
        IF TG_TABLE_NAME = 'renglon_ingreso' THEN
            SELECT estado INTO v_estado FROM ingreso WHERE cod_ingreso = v_id;
        ELSE
            SELECT estado INTO v_estado FROM transferencia WHERE nro_transferencia = v_id;
        END IF;

        -- Cabecera inexistente: en INSERT/UPDATE fallará la FK; en DELETE es
        -- el CASCADE del borrado de la cabecera.
        CONTINUE WHEN NOT FOUND;

        IF v_estado <> 'en_confeccion' THEN
            RAISE EXCEPTION 'RN-12: % % está % y no admite cambios en sus renglones',
                v_doc, v_id, v_estado;
        END IF;
    END LOOP;

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

CREATE TRIGGER trg_renglon_ingreso_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_ingreso
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_documento_bloqueo();

CREATE TRIGGER trg_renglon_transferencia_bloqueo
BEFORE INSERT OR UPDATE OR DELETE ON renglon_transferencia
FOR EACH ROW EXECUTE FUNCTION fn_trg_renglon_documento_bloqueo();

-- ---------------------------------------------------------------------
-- RN-13 · Auditoría de cambios de precio.
-- AFTER UPDATE OF precio en vino, solo si el precio realmente cambió.
-- AFTER porque solo se audita un cambio que efectivamente se guardó.
-- SECURITY DEFINER: la API no puede escribir en auditoria_precio, así
-- que no puede falsificar ni borrar el historial.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_vino_auditoria_precio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo, fecha_hora, usuario)
    VALUES (NEW.cod_vino, OLD.precio, NEW.precio, now(), session_user);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_vino_auditoria_precio
AFTER UPDATE OF precio ON vino
FOR EACH ROW
WHEN (OLD.precio IS DISTINCT FROM NEW.precio)
EXECUTE FUNCTION fn_trg_vino_auditoria_precio();

-- ---------------------------------------------------------------------
-- RN-05 · Los porcentajes de corte de un vino suman exactamente 100.
-- CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED: se verifica al hacer
-- COMMIT y no fila por fila. Así se puede cargar un vino con 85 % Malbec
-- y luego 15 % Cabernet en la misma transacción: después del primer
-- INSERT la suma es 85 (inválida), pero al cerrar la transacción es 100.
-- Se engancha también a vino (AFTER INSERT) para que un vino no pueda
-- quedar sin composición.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_composicion_suma()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_vinos INTEGER[];
    v_vino  INTEGER;
    v_suma  NUMERIC;
BEGIN
    v_vinos := CASE TG_OP
                 WHEN 'INSERT' THEN ARRAY[NEW.cod_vino]
                 WHEN 'DELETE' THEN ARRAY[OLD.cod_vino]
                 ELSE ARRAY[OLD.cod_vino, NEW.cod_vino] END;

    FOREACH v_vino IN ARRAY v_vinos LOOP
        -- Si el vino se borró en la misma transacción, no hay nada que validar.
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM vino WHERE cod_vino = v_vino);

        SELECT COALESCE(SUM(porcentaje), 0) INTO v_suma
          FROM composicion WHERE cod_vino = v_vino;

        IF v_suma <> 100 THEN
            RAISE EXCEPTION 'RN-05: los porcentajes de corte del vino % suman % y deben sumar 100',
                v_vino, v_suma;
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_composicion_suma_100
AFTER INSERT OR UPDATE OR DELETE ON composicion
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_composicion_suma();

CREATE CONSTRAINT TRIGGER trg_vino_requiere_composicion
AFTER INSERT ON vino
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_trg_composicion_suma();
