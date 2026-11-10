-- =====================================================================
-- consultas/insert.sql · Etapa 5 · 8.2 Inserción de datos (INSERT)
--
-- Cómo correrlo:  psql -d bodegas -f consultas/insert.sql
-- Cada consigna: BEGIN -> control previo -> sentencia -> control posterior
-- -> ROLLBACK (reemplazar por COMMIT para aplicarla).
--
-- PARÁMETROS (cambiar acá):
\set localidad_i1     'General Alvear'
\set id_cliente_i3    1
\set id_sala_i3       1
\set bodega_i6        'Viñedos Lopez SRL'
\set transportista_i6 'Transportes Sosa e Hijos'
-- =====================================================================
\pset footer off

-- ---------------------------------------------------------------------
-- I1. Insertar en transportista-localidad una nueva cobertura que vincule
--     General Alvear con el transportista que menos envíos (ingresos
--     trasladados) haya realizado en el último trimestre.
--
-- Estrategia: LEFT JOIN de transportista con sus ingresos de los últimos
-- 3 meses, para que cuente también al que hizo 0 envíos (con un JOIN
-- común ese transportista desaparecería y nunca sería "el que menos").
-- ORDER BY cantidad, código + LIMIT 1 resuelve empates de forma estable.
-- ON CONFLICT DO NOTHING: si ya cubría General Alvear, no falla por PK.
-- ---------------------------------------------------------------------
\echo '=== I1 ==='
BEGIN;
\echo 'Control previo: envíos del último trimestre por transportista (los 3 que menos)'
SELECT t.cod_transporte, t.razon_social, count(i.cod_ingreso) AS envios
  FROM transportista t
  LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                     AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.cod_transporte
 ORDER BY envios, t.cod_transporte
 LIMIT 3;

INSERT INTO transportista_localidad (cod_transporte, id_localidad)
SELECT t.cod_transporte,
       (SELECT id_localidad FROM localidad WHERE nombre = :'localidad_i1')
  FROM transportista t
  LEFT JOIN ingreso i ON i.cod_transporte = t.cod_transporte
                     AND i.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY t.cod_transporte
 ORDER BY count(i.cod_ingreso), t.cod_transporte
 LIMIT 1
ON CONFLICT DO NOTHING;

\echo 'Control posterior: transportistas que cubren General Alvear'
SELECT tl.cod_transporte, t.razon_social
  FROM transportista_localidad tl
  JOIN transportista t USING (cod_transporte)
  JOIN localidad l USING (id_localidad)
 WHERE l.nombre = :'localidad_i1'
 ORDER BY 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- I2. Si existe algún vino tinto con graduación de 14° o más, crear el
--     maridaje "Cordero al disco" y asociarlo a todos esos vinos.
--
-- Estrategia: una sola sentencia con un CTE que modifica datos. El INSERT
-- del maridaje tiene un WHERE EXISTS: si no hay tintos de 14° o más, no
-- inserta nada y el segundo INSERT tampoco (CROSS JOIN con un CTE vacío).
-- RETURNING pasa el id generado al segundo INSERT sin consultarlo de nuevo.
-- ---------------------------------------------------------------------
\echo '=== I2 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS tintos_14_o_mas FROM vino WHERE tipo = 'tinto' AND graduacion >= 14;

WITH nuevo_maridaje AS (
    INSERT INTO maridaje (nombre, temperatura_servicio)
    SELECT 'Cordero al disco', 17
     WHERE EXISTS (SELECT 1 FROM vino WHERE tipo = 'tinto' AND graduacion >= 14)
    RETURNING id_maridaje
)
INSERT INTO vino_maridaje (cod_vino, id_maridaje)
SELECT v.cod_vino, m.id_maridaje
  FROM vino v
 CROSS JOIN nuevo_maridaje m
 WHERE v.tipo = 'tinto' AND v.graduacion >= 14;

\echo 'Control posterior'
SELECT m.nombre, m.temperatura_servicio, count(vm.cod_vino) AS vinos_asociados
  FROM maridaje m LEFT JOIN vino_maridaje vm USING (id_maridaje)
 WHERE m.nombre = 'Cordero al disco'
 GROUP BY m.id_maridaje;
ROLLBACK;

-- ---------------------------------------------------------------------
-- I3. Crear un nuevo comprobante con tres renglones para un cliente dado,
--     en la sala con ID 1, dentro de una transacción y usando las
--     funciones de cálculo.
--
-- Estrategia: es exactamente lo que hace la API en POST /comprobantes.
--   1. INSERT de la cabecera: nace con importes en 0 (DEFAULT).
--   2. INSERT de los renglones: solo vino y cantidad. Los triggers validan
--      stock (RN-09), completan precio, descuento y subtotal, descuentan
--      el stock y recalculan la cabecera (RN-08).
--   3. fn_total_comprobante y fn_stock_sala muestran el resultado.
-- Se eligen 3 vinos con stock en la sala (los de mayor stock).
-- Si un renglón fallara (sin stock), ROLLBACK deshace TODO el comprobante.
-- ---------------------------------------------------------------------
\echo '=== I3 ==='
BEGIN;
\echo 'Control previo: stock en la sala de los 3 vinos elegidos'
SELECT cod_vino, cantidad AS stock_antes
  FROM stock_sala WHERE id_sala = :id_sala_i3 AND cantidad >= 2
 ORDER BY cantidad DESC, cod_vino LIMIT 3;

INSERT INTO comprobante (id_cliente, id_sala)
VALUES (:id_cliente_i3, :id_sala_i3)
RETURNING nro_comprobante AS nro_i3 \gset

INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad)
SELECT :nro_i3, cod_vino, 2
  FROM stock_sala WHERE id_sala = :id_sala_i3 AND cantidad >= 2
 ORDER BY cantidad DESC, cod_vino
 LIMIT 3;

\echo 'Control posterior: renglones completados por el trigger'
SELECT r.cod_vino, r.cantidad, r.precio_unitario, r.porcentaje_descuento, r.subtotal,
       fn_stock_sala(:id_sala_i3, r.cod_vino) AS stock_despues
  FROM renglon_comprobante r WHERE r.nro_comprobante = :nro_i3 ORDER BY 1;
SELECT nro_comprobante, fecha, subtotal, descuento, total,
       fn_total_comprobante(nro_comprobante) AS total_calculado,
       fn_descuento_cliente(id_cliente)      AS descuento_cliente
  FROM comprobante WHERE nro_comprobante = :nro_i3;
ROLLBACK;

-- ---------------------------------------------------------------------
-- I4. Insertar una nueva bodega.
-- El CUIT tiene dígito verificador válido; el DOMAIN cuit_dom exige 11 dígitos.
-- ---------------------------------------------------------------------
\echo '=== I4 ==='
BEGIN;
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('30716548879', 'Bodega Los Reyunos SA', 'Ruta 150 km 32, San Rafael, Mendoza')
RETURNING *;
\echo 'Control posterior'
SELECT count(*) AS bodegas FROM bodega;
ROLLBACK;

-- ---------------------------------------------------------------------
-- I5. Insertar una nueva sala de venta.
-- Estrategia: INSERT ... SELECT para obtener la localidad por su nombre en
-- vez de escribir un id "mágico". RETURNING muestra el id generado.
-- ---------------------------------------------------------------------
\echo '=== I5 ==='
BEGIN;
INSERT INTO sala_venta (calle, numero, dia_cierre, id_localidad)
SELECT 'Av. Hipólito Yrigoyen', 1250, 'lunes', id_localidad
  FROM localidad WHERE nombre = 'San Rafael'
RETURNING *;
ROLLBACK;

-- ---------------------------------------------------------------------
-- I6. Crear un ingreso en confección de 120 botellas de un vino
--     determinado ("Malbec Reserva" de 750 ml), elaborado por una bodega
--     dada y trasladado por un transportista dado.
--
-- Estrategia: dos INSERT en la misma transacción. El ingreso nace
-- 'en_confeccion' por DEFAULT. El vino se busca por nombre + presentación
-- + bodega (añada 2021). No impacta el stock: recién lo hará al
-- terminarlo y procesarlo con sp_procesar_ingreso (RN-10).
-- ---------------------------------------------------------------------
\echo '=== I6 ==='
BEGIN;
INSERT INTO ingreso (cod_transporte, cuit_bodega)
SELECT t.cod_transporte, b.cuit
  FROM transportista t, bodega b
 WHERE t.razon_social = :'transportista_i6'
   AND b.razon_social = :'bodega_i6'
RETURNING cod_ingreso AS ingreso_i6 \gset

INSERT INTO renglon_ingreso (cod_ingreso, cod_vino, cantidad)
SELECT :ingreso_i6, v.cod_vino, 120
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
 WHERE v.nombre = 'Malbec Reserva' AND v.volumen_ml = 750 AND v.anada = 2021
   AND b.razon_social = :'bodega_i6';

\echo 'Control posterior'
SELECT i.cod_ingreso, i.fecha, i.estado, t.razon_social AS transportista,
       b.razon_social AS bodega, v.nombre, v.anada, v.volumen_ml, r.cantidad
  FROM ingreso i
  JOIN transportista t USING (cod_transporte)
  JOIN bodega b ON b.cuit = i.cuit_bodega
  JOIN renglon_ingreso r USING (cod_ingreso)
  JOIN vino v USING (cod_vino)
 WHERE i.cod_ingreso = :ingreso_i6;
ROLLBACK;
