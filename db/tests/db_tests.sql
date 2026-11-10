-- =====================================================================
-- db/tests/db_tests.sql · Etapa 2: pruebas de las reglas de negocio
--
-- Cómo correrlo (sobre una base con las migraciones aplicadas, vacía o
-- cargada; no deja cambios porque todo termina en ROLLBACK):
--
--   psql -v ON_ERROR_STOP=1 -d bodegas -f db/tests/db_tests.sql
--
-- Cada caso imprime una línea "OK ..." en un NOTICE. Si un caso que debía
-- fallar no falla, o falla con otro error, el script se corta con "FAIL".
--
-- Los casos que deben fallar indican el SQLSTATE esperado:
--   P0001 = RAISE EXCEPTION de un trigger o procedimiento (regla de negocio)
--   23514 = CHECK      23505 = UNIQUE      23503 = FOREIGN KEY
--   23502 = NOT NULL   42501 = permiso denegado
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
SET client_min_messages = notice;
-- Los resultados de los SELECT van a /dev/null: solo interesan los NOTICE.
\o /dev/null

BEGIN;

-- ---------------------------------------------------------------------
-- Funciones auxiliares de prueba (solo existen en esta sesión: pg_temp)
-- ---------------------------------------------------------------------
-- Ejecuta una sentencia que DEBE fallar con el SQLSTATE indicado.
-- El bloque BEGIN ... EXCEPTION crea un savepoint: lo que hizo la sentencia
-- fallida se deshace y la transacción de pruebas sigue viva.
CREATE FUNCTION pg_temp.debe_fallar(p_caso TEXT, p_sqlstate TEXT, p_sql TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = p_sqlstate THEN
            RAISE NOTICE 'OK   % -> falla como se espera [%] %', p_caso, SQLSTATE, SQLERRM;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FAIL % -> esperaba SQLSTATE % y falló con [%] %',
            p_caso, p_sqlstate, SQLSTATE, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL % -> debía fallar y NO falló', p_caso;
END;
$$;

-- Ejecuta una sentencia que DEBE funcionar.
CREATE FUNCTION pg_temp.debe_funcionar(p_caso TEXT, p_sql TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE NOTICE 'OK   % -> funciona', p_caso;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL % -> debía funcionar y falló con [%] %', p_caso, SQLSTATE, SQLERRM;
END;
$$;

-- Verifica una condición.
CREATE FUNCTION pg_temp.verificar(p_caso TEXT, p_condicion BOOLEAN)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_condicion IS TRUE THEN
        RAISE NOTICE 'OK   % -> se cumple', p_caso;
    ELSE
        RAISE EXCEPTION 'FAIL % -> la condición no se cumple', p_caso;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Datos de prueba propios (no dependen de la carga masiva).
-- Se usan identificadores altos/fijos guardados en variables de psql.
-- ---------------------------------------------------------------------
INSERT INTO provincia (nombre) VALUES ('Provincia Test') RETURNING id_provincia AS prov \gset
INSERT INTO departamento (nombre, id_provincia) VALUES ('Depto Test', :prov) RETURNING id_departamento AS depto \gset
INSERT INTO localidad (nombre, codigo_postal, id_departamento, encargado_regional)
VALUES ('Localidad Test', '5600', :depto, 'Encargada Test') RETURNING id_localidad AS loc \gset
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
VALUES ('Calle Test', 100, 'lunes', :loc) RETURNING id_sala AS sala \gset
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30999999991', 'Bodega Test SA', 'Ruta 143 km 1');
INSERT INTO transportista (razon_social, cuit, email, telefono, domicilio)
VALUES ('Transporte Test', '30999999992', 'test@transporte.com', '260-4000000', 'Ruta 40')
RETURNING cod_transporte AS transp \gset
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Test Tinta', 'tinta') RETURNING id_cepa AS cepa1 \gset
INSERT INTO cepa (nombre, tipo) VALUES ('Cepa Test Blanca', 'blanca') RETURNING id_cepa AS cepa2 \gset

-- Vino de prueba: 85 % + 15 % en la misma transacción (RN-05 diferido).
INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino Test', 'tinto', 2021, 750, 14.00, 12500, '30999999991')
RETURNING cod_vino AS vino \gset
INSERT INTO composicion VALUES (:vino, :cepa1, 85), (:vino, :cepa2, 15);

-- Socio de prueba
INSERT INTO cliente (tipo, nombre, tipo_doc, nro_doc, direccion, id_localidad)
VALUES ('socio', 'Pérez, Ana', 'DNI', '99000001', 'San Martín 1', :loc)
RETURNING id_cliente AS socio \gset

-- Stock inicial por el circuito real: ingreso -> terminar -> procesar ->
-- transferencia -> terminar -> procesar.
INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (:transp, '30999999991')
RETURNING cod_ingreso AS ing \gset
INSERT INTO renglon_ingreso VALUES (:ing, :vino, 10);
UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = :ing;
CALL sp_procesar_ingreso(:ing);

INSERT INTO transferencia (id_sala) VALUES (:sala) RETURNING nro_transferencia AS tr \gset
INSERT INTO renglon_transferencia VALUES (:tr, :vino, 4);
UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = :tr;
CALL sp_procesar_transferencia(:tr);

-- Comprobante de prueba
INSERT INTO comprobante (id_cliente, id_sala) VALUES (:socio, :sala)
RETURNING nro_comprobante AS comp \gset

\echo '--- Datos de prueba creados ---'

-- =====================================================================
-- RN-01 · Precio único por vino y mayor que cero
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-01 precio 0', '23514',
    format('UPDATE vino SET precio = 0 WHERE cod_vino = %s', :vino));
SELECT pg_temp.debe_fallar('RN-01 precio negativo', '23514',
    format('UPDATE vino SET precio = -10 WHERE cod_vino = %s', :vino));

-- =====================================================================
-- RN-02 · Una sala pertenece a una sola localidad; cada localidad tiene un
-- único encargado (dato de localidad, 3FN).
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-02 sala sin localidad', '23502',
    'INSERT INTO sala_venta (calle, numero, dia_cierre) VALUES (''X'', 1, ''lunes'')');
SELECT pg_temp.debe_fallar('RN-02 sala con localidad inexistente', '23503',
    'INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad) VALUES (''X'', 1, ''lunes'', -1)');
SELECT pg_temp.verificar('RN-02 el encargado es una columna de localidad, no de sala',
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'localidad' AND column_name = 'encargado_regional')
    AND NOT EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'sala_venta' AND column_name = 'encargado_regional'));

-- =====================================================================
-- RN-03 · Cada empleado trabaja en una sola sala (FK NOT NULL)
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-03 empleado sin sala', '23502',
    'INSERT INTO empleado (cuit, nombre, fecha_ingreso, salario) VALUES (''20999999993'', ''Juan'', ''2020-01-01'', 900000)');
SELECT pg_temp.debe_funcionar('RN-03 empleado con sala',
    format('INSERT INTO empleado VALUES (''20999999993'', ''Juan'', ''2020-01-01'', 900000, %s)', :sala));

-- =====================================================================
-- RN-04 · Una parcela tiene una sola cepa y se cosecha una vez por campaña
-- =====================================================================
INSERT INTO finca (nombre, superficie_ha, id_departamento) VALUES ('Finca Test', 50, :depto)
RETURNING id_finca AS finca \gset
INSERT INTO parcela VALUES (:finca, 1, 5.5, 2005, :cepa1);
INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
VALUES (:finca, 1, 2024, '2024-03-10', 40000, '30999999991');

SELECT pg_temp.debe_fallar('RN-04 segunda cosecha de la misma parcela y campaña', '23505',
    format('INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
            VALUES (%s, 1, 2024, ''2024-04-01'', 1000, ''30999999991'')', :finca));
SELECT pg_temp.debe_funcionar('RN-04 misma parcela, otra campaña',
    format('INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
            VALUES (%s, 1, 2025, ''2025-03-05'', 38000, ''30999999991'')', :finca));
SELECT pg_temp.debe_fallar('RN-04 parcela sin cepa', '23502',
    format('INSERT INTO parcela (id_finca, nro_parcela, superficie_ha, anio_plantacion) VALUES (%s, 2, 3, 2010)', :finca));
SELECT pg_temp.debe_fallar('RN-04 fecha de cosecha fuera de la campaña (CHECK entre columnas)', '23514',
    format('INSERT INTO lote_uva (id_finca, nro_parcela, campania, fecha_cosecha, kilos, cuit_bodega)
            VALUES (%s, 1, 2023, ''2024-03-01'', 1000, ''30999999991'')', :finca));

-- =====================================================================
-- RN-05 · Los porcentajes de corte suman 100 (constraint trigger diferido)
-- Para probarlo dentro de esta transacción se fuerza la verificación con
-- SET CONSTRAINTS ... IMMEDIATE dentro de cada caso.
-- =====================================================================
DO $$
DECLARE v INTEGER;
BEGIN
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino Corte Malo', 'tinto', 2022, 750, 13.5, 9000, '30999999991')
        RETURNING cod_vino INTO v;
        INSERT INTO composicion SELECT v, id_cepa, 60 FROM cepa WHERE nombre = 'Cepa Test Tinta';
        INSERT INTO composicion SELECT v, id_cepa, 30 FROM cepa WHERE nombre = 'Cepa Test Blanca';
        SET CONSTRAINTS trg_composicion_suma_100, trg_vino_requiere_composicion IMMEDIATE;
        RAISE EXCEPTION 'FAIL RN-05 un corte que suma 90 no falló';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'RN-05%' THEN
            RAISE NOTICE 'OK   RN-05 corte que suma 90 -> falla al verificar [%] %', SQLSTATE, SQLERRM;
        ELSE
            RAISE;
        END IF;
    END;
    SET CONSTRAINTS ALL DEFERRED;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
        VALUES ('Vino Sin Cepas', 'blanco', 2022, 750, 12.5, 7000, '30999999991');
        SET CONSTRAINTS trg_vino_requiere_composicion IMMEDIATE;
        RAISE EXCEPTION 'FAIL RN-05 un vino sin composición no falló';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'RN-05%' THEN
            RAISE NOTICE 'OK   RN-05 vino sin composición -> falla al verificar [%] %', SQLSTATE, SQLERRM;
        ELSE
            RAISE;
        END IF;
    END;
    SET CONSTRAINTS ALL DEFERRED;
END $$;

DO $$
BEGIN
    -- Un corte correcto cargado en dos pasos: a mitad de camino suma 70,
    -- pero como la verificación es diferida, no falla.
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Corte Bueno', 'tinto', 2022, 1500, 14.5, 25000, '30999999991');
    INSERT INTO composicion SELECT currval(pg_get_serial_sequence('vino','cod_vino')), id_cepa, 70
      FROM cepa WHERE nombre = 'Cepa Test Tinta';
    INSERT INTO composicion SELECT currval(pg_get_serial_sequence('vino','cod_vino')), id_cepa, 30
      FROM cepa WHERE nombre = 'Cepa Test Blanca';
    SET CONSTRAINTS trg_composicion_suma_100, trg_vino_requiere_composicion IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    RAISE NOTICE 'OK   RN-05 corte 70 + 30 cargado en dos INSERT -> funciona';
END $$;

SELECT pg_temp.debe_fallar('RN-05 porcentaje mayor a 100', '23514',
    format('UPDATE composicion SET porcentaje = 150 WHERE cod_vino = %s AND id_cepa = %s', :vino, :cepa1));

-- =====================================================================
-- RN-06 · Descuento según el tipo de cliente
-- =====================================================================
INSERT INTO cliente (tipo, nombre, tipo_doc, nro_doc, direccion, id_localidad)
VALUES ('distribuidor', 'Distribuidora Test SRL', 'CUIT', '30999999994', 'Ruta 7', :loc)
RETURNING id_cliente AS distrib \gset
INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (:distrib, 'Sur', 'HAB-TEST-1');
INSERT INTO cliente (tipo, nombre, tipo_doc, nro_doc, direccion, id_localidad)
VALUES ('exportador', 'Export Test SA', 'CUIT', '30999999995', 'Ruta 8', :loc)
RETURNING id_cliente AS export \gset
INSERT INTO exportador (id_cliente, pais_destino) VALUES (:export, 'Brasil');

SELECT pg_temp.verificar('RN-06 socio recibe 10 %',        fn_descuento_cliente(:socio)   = 10);
SELECT pg_temp.verificar('RN-06 distribuidor recibe 20 %', fn_descuento_cliente(:distrib) = 20);
SELECT pg_temp.verificar('RN-06 exportador recibe 30 %',   fn_descuento_cliente(:export)  = 30);
SELECT pg_temp.debe_fallar('RN-06 descuento fuera de rango', '23514',
    format('UPDATE cliente SET descuento = 80 WHERE id_cliente = %s', :socio));
SELECT pg_temp.debe_fallar('RN-06 subtipo distribuidor sobre un cliente socio', '23503',
    format('INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES (%s, ''Norte'', ''HAB-X'')', :socio));

-- =====================================================================
-- RN-07 · Varios permisos por exportador; vencimiento posterior a emisión
-- =====================================================================
SELECT pg_temp.debe_funcionar('RN-07 dos permisos del mismo exportador',
    format('INSERT INTO permiso_exportacion VALUES
              (''PE-T-1'', %1$s, ''2025-01-01'', ''2026-01-01''),
              (''PE-T-2'', %1$s, ''2025-06-01'', ''2026-06-01'')', :export));
SELECT pg_temp.debe_fallar('RN-07 vencimiento anterior a la emisión', '23514',
    format('INSERT INTO permiso_exportacion VALUES (''PE-T-3'', %s, ''2025-05-01'', ''2025-01-01'')', :export));
SELECT pg_temp.debe_fallar('RN-07 permiso para un cliente que no es exportador', '23503',
    format('INSERT INTO permiso_exportacion VALUES (''PE-T-4'', %s, ''2025-01-01'', ''2026-01-01'')', :socio));

-- =====================================================================
-- RN-08 · El total es la suma de los renglones con descuento; no se carga a mano
-- =====================================================================
INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (:comp, :vino, 2);

SELECT pg_temp.verificar('RN-08 el trigger completó precio, descuento y subtotal del renglón',
    (SELECT precio_unitario = 12500 AND porcentaje_descuento = 10 AND subtotal = 22500
       FROM renglon_comprobante WHERE nro_comprobante = :comp AND cod_vino = :vino));
SELECT pg_temp.verificar('RN-08 cabecera: subtotal 25000, descuento 2500, total 22500',
    (SELECT subtotal = 25000 AND descuento = 2500 AND total = 22500
       FROM comprobante WHERE nro_comprobante = :comp));
SELECT pg_temp.verificar('RN-08 fn_total_comprobante coincide con la cabecera',
    fn_total_comprobante(:comp) = (SELECT total FROM comprobante WHERE nro_comprobante = :comp));
SELECT pg_temp.debe_fallar('RN-08 modificar el total a mano', 'P0001',
    format('UPDATE comprobante SET subtotal = 1, descuento = 0, total = 1 WHERE nro_comprobante = %s', :comp));
SELECT pg_temp.debe_fallar('RN-08 crear un comprobante con importes cargados', 'P0001',
    format('INSERT INTO comprobante (id_cliente, id_sala, subtotal, descuento, total) VALUES (%s, %s, 100, 0, 100)', :socio, :sala));
SELECT pg_temp.debe_fallar('RN-08 cambiar la cantidad de un renglón ya registrado', 'P0001',
    format('UPDATE renglon_comprobante SET cantidad = 1 WHERE nro_comprobante = %s', :comp));

-- =====================================================================
-- RN-09 · No se vende más de lo que hay; el stock nunca es negativo
-- =====================================================================
SELECT pg_temp.verificar('RN-09 la venta descontó stock (4 - 2 = 2)', fn_stock_sala(:sala, :vino) = 2);
SELECT pg_temp.debe_fallar('RN-09 vender 3 botellas cuando hay 2', 'P0001',
    format('INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, %s);
            INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
            VALUES (currval(pg_get_serial_sequence(''comprobante'',''nro_comprobante'')), %s, 3)',
           :socio, :sala, :vino));
SELECT pg_temp.verificar('RN-09 la venta rechazada no dejó cambios', fn_stock_sala(:sala, :vino) = 2);
SELECT pg_temp.debe_fallar('RN-09 stock negativo directo (CHECK)', '23514',
    format('UPDATE stock_sala SET cantidad = -1 WHERE id_sala = %s AND cod_vino = %s', :sala, :vino));
SELECT pg_temp.debe_fallar('RN-09 cantidad 0 en un renglón', '23514',
    format('INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 0)', :comp, :vino));

-- =====================================================================
-- RN-10 · Ingresos: solo un ingreso terminado impacta y pasa a procesado
-- =====================================================================
INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (:transp, '30999999991')
RETURNING cod_ingreso AS ing2 \gset
INSERT INTO renglon_ingreso VALUES (:ing2, :vino, 5);

SELECT pg_temp.debe_fallar('RN-10 procesar un ingreso en confección', 'P0001',
    format('CALL sp_procesar_ingreso(%s)', :ing2));
SELECT pg_temp.debe_fallar('RN-10 saltar de en_confeccion a procesado', 'P0001',
    format('UPDATE ingreso SET estado = ''procesado'' WHERE cod_ingreso = %s', :ing2));
SELECT pg_temp.debe_fallar('RN-10 crear un ingreso ya procesado', 'P0001',
    format('INSERT INTO ingreso (cod_transporte, cuit_bodega, estado) VALUES (%s, ''30999999991'', ''procesado'')', :transp));
SELECT pg_temp.debe_funcionar('RN-10 en_confeccion -> terminado',
    format('UPDATE ingreso SET estado = ''terminado'' WHERE cod_ingreso = %s', :ing2));
SELECT pg_temp.debe_fallar('RN-10 marcar procesado a mano (sin mover stock)', 'P0001',
    format('UPDATE ingreso SET estado = ''procesado'' WHERE cod_ingreso = %s', :ing2));
SELECT pg_temp.debe_funcionar('RN-10 procesar con el procedimiento',
    format('CALL sp_procesar_ingreso(%s)', :ing2));
SELECT pg_temp.verificar('RN-10 el depósito sumó las 5 botellas (10 - 4 + 5 = 11)',
    (SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino) = 11);
SELECT pg_temp.debe_fallar('RN-10 retroceder de procesado a terminado', 'P0001',
    format('UPDATE ingreso SET estado = ''terminado'' WHERE cod_ingreso = %s', :ing2));
SELECT pg_temp.debe_fallar('RN-10 procesar dos veces', 'P0001',
    format('CALL sp_procesar_ingreso(%s)', :ing2));
SELECT pg_temp.debe_fallar('RN-10 terminar un ingreso sin renglones', 'P0001',
    format('INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (%s, ''30999999991'');
            UPDATE ingreso SET estado = ''terminado''
             WHERE cod_ingreso = currval(pg_get_serial_sequence(''ingreso'',''cod_ingreso''))', :transp));

-- =====================================================================
-- RN-11 · Transferencias: estados, fecha actual inmodificable, stock
-- =====================================================================
INSERT INTO transferencia (id_sala, fecha_confeccion) VALUES (:sala, '2020-01-01')
RETURNING nro_transferencia AS tr2 \gset
SELECT pg_temp.verificar('RN-11 la fecha de confección es la actual aunque se mande otra',
    (SELECT fecha_confeccion = CURRENT_DATE FROM transferencia WHERE nro_transferencia = :tr2));
SELECT pg_temp.debe_fallar('RN-11 modificar la fecha de confección', 'P0001',
    format('UPDATE transferencia SET fecha_confeccion = CURRENT_DATE - 1 WHERE nro_transferencia = %s', :tr2));

-- Pide 50 botellas cuando el depósito tiene 11.
INSERT INTO renglon_transferencia VALUES (:tr2, :vino, 50);
UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = :tr2;
SELECT pg_temp.debe_fallar('RN-11 procesar sin stock suficiente en el depósito', 'P0001',
    format('CALL sp_procesar_transferencia(%s)', :tr2));
SELECT pg_temp.verificar('RN-11 la transferencia fallida no dejó cambios a medias',
    (SELECT cantidad FROM stock_deposito WHERE cod_vino = :vino) = 11
    AND fn_stock_sala(:sala, :vino) = 2
    AND (SELECT estado FROM transferencia WHERE nro_transferencia = :tr2) = 'terminado');

-- Vino sin fila en stock_deposito (caso "para pensar" del anexo A.6).
DO $$
BEGIN
    INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
    VALUES ('Vino Sin Deposito', 'blanco', 2023, 750, 12.5, 8000, '30999999991');
    INSERT INTO composicion SELECT currval(pg_get_serial_sequence('vino','cod_vino')), id_cepa, 100
      FROM cepa WHERE nombre = 'Cepa Test Blanca';
END $$;
INSERT INTO transferencia (id_sala) VALUES (:sala) RETURNING nro_transferencia AS tr3 \gset
INSERT INTO renglon_transferencia
SELECT :tr3, cod_vino, 1 FROM vino WHERE nombre = 'Vino Sin Deposito';
UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = :tr3;
SELECT pg_temp.debe_fallar('RN-11 vino que no tiene fila en el depósito', 'P0001',
    format('CALL sp_procesar_transferencia(%s)', :tr3));

SELECT pg_temp.verificar('RN-11 la transferencia procesada sumó a la sala y restó al depósito',
    (SELECT estado FROM transferencia WHERE nro_transferencia = :tr) = 'procesado');

-- =====================================================================
-- RN-12 · Documento fuera de confección: no se tocan sus renglones
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-12 agregar renglón a un ingreso procesado', 'P0001',
    format('INSERT INTO renglon_ingreso VALUES (%s, %s, 1)', :ing2,
           (SELECT cod_vino FROM vino WHERE nombre = 'Vino Corte Bueno')));
SELECT pg_temp.debe_fallar('RN-12 modificar renglón de un ingreso procesado', 'P0001',
    format('UPDATE renglon_ingreso SET cantidad = 99 WHERE cod_ingreso = %s', :ing2));
SELECT pg_temp.debe_fallar('RN-12 borrar renglón de una transferencia terminada', 'P0001',
    format('DELETE FROM renglon_transferencia WHERE nro_transferencia = %s', :tr2));
SELECT pg_temp.debe_fallar('RN-12 modificar los datos de un ingreso procesado', 'P0001',
    format('UPDATE ingreso SET fecha = fecha - 1 WHERE cod_ingreso = %s', :ing2));

INSERT INTO transferencia (id_sala) VALUES (:sala) RETURNING nro_transferencia AS tr4 \gset
SELECT pg_temp.debe_funcionar('RN-12 en confección sí se agregan y quitan renglones',
    format('INSERT INTO renglon_transferencia VALUES (%1$s, %2$s, 1);
            UPDATE renglon_transferencia SET cantidad = 2 WHERE nro_transferencia = %1$s;
            DELETE FROM renglon_transferencia WHERE nro_transferencia = %1$s', :tr4, :vino));

-- =====================================================================
-- RN-13 · Todo cambio de precio queda auditado
-- =====================================================================
UPDATE vino SET precio = 13000 WHERE cod_vino = :vino;
UPDATE vino SET graduacion = 14.10 WHERE cod_vino = :vino;   -- no cambia el precio
SELECT pg_temp.verificar('RN-13 se auditó el cambio de precio (anterior 12500, nuevo 13000)',
    (SELECT count(*) = 1 AND min(precio_anterior) = 12500 AND min(precio_nuevo) = 13000
       FROM auditoria_precio WHERE cod_vino = :vino));
SELECT pg_temp.verificar('RN-13 un UPDATE que no cambia el precio no se audita',
    (SELECT count(*) FROM auditoria_precio WHERE cod_vino = :vino) = 1);
SELECT pg_temp.verificar('RN-13 la venta anterior conserva su precio histórico',
    (SELECT precio_unitario FROM renglon_comprobante WHERE nro_comprobante = :comp) = 12500);

-- =====================================================================
-- RN-14 · No se borra un transportista, bodega o vino con movimientos
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-14 borrar transportista con ingresos', '23503',
    format('DELETE FROM transportista WHERE cod_transporte = %s', :transp));
SELECT pg_temp.debe_fallar('RN-14 borrar bodega con vinos', '23503',
    'DELETE FROM bodega WHERE cuit = ''30999999991''');
SELECT pg_temp.debe_fallar('RN-14 borrar vino vendido', '23503',
    format('DELETE FROM vino WHERE cod_vino = %s', :vino));
SELECT pg_temp.debe_funcionar('RN-14 borrar un vino sin movimientos (arrastra su composición)',
    'DELETE FROM vino WHERE nombre = ''Vino Corte Bueno''');

-- =====================================================================
-- RN-15 · Cantidades, superficies, kilos y precios positivos; graduación 5-20
-- =====================================================================
SELECT pg_temp.debe_fallar('RN-15 graduación 25', '23514',
    format('UPDATE vino SET graduacion = 25 WHERE cod_vino = %s', :vino));
SELECT pg_temp.debe_fallar('RN-15 graduación 4', '23514',
    format('UPDATE vino SET graduacion = 4 WHERE cod_vino = %s', :vino));
SELECT pg_temp.debe_fallar('RN-15 superficie negativa', '23514',
    format('UPDATE finca SET superficie_ha = -1 WHERE id_finca = %s', :finca));
SELECT pg_temp.debe_fallar('RN-15 kilos en cero', '23514',
    format('UPDATE lote_uva SET kilos = 0 WHERE id_finca = %s', :finca));
SELECT pg_temp.debe_fallar('RN-15 cantidad negativa en una transferencia', '23514',
    format('INSERT INTO renglon_transferencia VALUES (%s, %s, -5)', :tr4, :vino));

-- =====================================================================
-- Tipos propios y otros constraints
-- =====================================================================
SELECT pg_temp.debe_fallar('DOMAIN cuit_dom rechaza un CUIT con guiones', '23514',
    'INSERT INTO bodega VALUES (''30-12345678'', ''Bodega Guiones'', ''X'')');
SELECT pg_temp.debe_fallar('ENUM rechaza un estado inexistente', '22P02',
    format('UPDATE ingreso SET estado = ''anulado'' WHERE cod_ingreso = %s', :ing));
SELECT pg_temp.debe_fallar('UNIQUE vino (nombre, añada, volumen)', '23505',
    'INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
     VALUES (''Vino Test'', ''tinto'', 2021, 750, 14, 100, ''30999999991'')');
SELECT pg_temp.debe_fallar('UNIQUE documento de cliente', '23505',
    format('INSERT INTO cliente (tipo, nombre, tipo_doc, nro_doc, direccion, id_localidad)
            VALUES (''socio'', ''Otro'', ''DNI'', ''99000001'', ''X'', %s)', :loc));
SELECT pg_temp.debe_fallar('CHECK volumen de presentación inexistente', '23514',
    format('UPDATE vino SET volumen_ml = 700 WHERE cod_vino = %s', :vino));

-- =====================================================================
-- Roles: la API no es propietaria y no tiene permisos de sobra
-- =====================================================================
SET LOCAL ROLE bodegas_api;
SELECT pg_temp.debe_fallar('ROL api no puede escribir el stock directamente', '42501',
    format('UPDATE stock_sala SET cantidad = 1000 WHERE id_sala = %s', :sala));
SELECT pg_temp.debe_fallar('ROL api no puede escribir la auditoría', '42501',
    format('INSERT INTO auditoria_precio (cod_vino, precio_anterior, precio_nuevo) VALUES (%s, 1, 2)', :vino));
SELECT pg_temp.debe_fallar('ROL api no puede crear tablas', '42501',
    'CREATE TABLE public.tabla_intrusa (x int)');
SELECT pg_temp.debe_funcionar('ROL api sí puede vender (el trigger mueve el stock por ella)',
    format('INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, %s);
            INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
            VALUES (currval(pg_get_serial_sequence(''comprobante'',''nro_comprobante'')), %s, 1)',
           :socio, :sala, :vino));
SELECT pg_temp.verificar('ROL api la venta hecha por la API descontó el stock (2 - 1 = 1)',
    fn_stock_sala(:sala, :vino) = 1);
SELECT pg_temp.debe_funcionar('ROL api sí puede consultar y llamar funciones',
    format('SELECT fn_stock_sala(%s, %s), fn_total_comprobante(%s)', :sala, :vino, :comp));
RESET ROLE;

SET LOCAL ROLE bodegas_lectura;
SELECT pg_temp.debe_fallar('ROL lectura no puede insertar', '42501',
    format('INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, %s)', :socio, :sala));
SELECT pg_temp.debe_funcionar('ROL lectura puede consultar vistas',
    'SELECT count(*) FROM v_ficha_vino');
RESET ROLE;

\echo ''
\echo '=== Todas las pruebas pasaron. Se hace ROLLBACK: la base queda como estaba. ==='
ROLLBACK;
