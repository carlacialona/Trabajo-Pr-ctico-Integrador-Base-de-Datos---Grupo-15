-- =====================================================================
-- consultas/select.sql · Etapa 5 · 8.4 y 8.5 Consultas (SELECT)
--
-- Cómo correrlo:  psql -d bodegas -f consultas/select.sql
-- "Última semana", "último mes", etc. se calculan desde CURRENT_DATE.
--
-- PARÁMETROS (cambiar acá):
\set id_sala_s3    1
\set vino_nombre   'Malbec Reserva'
\set vino_anada    2021
\set vino_volumen  750
\set id_sala_s6    3
\set bodega_s12    'Bodega Boutique del Atuel SA'
-- =====================================================================
\pset footer off
\timing on

-- Código del vino de referencia (S4 y S9), buscado por su clave candidata
-- (nombre, añada, volumen) en vez de escribir un número "mágico".
SELECT cod_vino AS vino_ref FROM vino
 WHERE nombre = :'vino_nombre' AND anada = :vino_anada AND volumen_ml = :vino_volumen \gset

-- ---------------------------------------------------------------------
-- S1. Ranking de los 10 vinos con mayor cantidad de botellas vendidas en
--     toda la red de salas.
-- Estrategia: agregar primero los renglones (CTE) y recién después unir
-- con vino: se hace el JOIN sobre 600 filas agregadas y no sobre 500.000.
-- FETCH FIRST ... WITH TIES incluye empates en el puesto 10.
-- ---------------------------------------------------------------------
\echo '=== S1 ==='
WITH ventas AS (
    SELECT cod_vino, SUM(cantidad) AS botellas
      FROM renglon_comprobante
     GROUP BY cod_vino
)
SELECT RANK() OVER (ORDER BY ve.botellas DESC) AS puesto,
       v.cod_vino, v.nombre, v.anada, v.volumen_ml, ve.botellas
  FROM ventas ve
  JOIN vino v USING (cod_vino)
 ORDER BY ve.botellas DESC
 FETCH FIRST 10 ROWS WITH TIES;

-- ---------------------------------------------------------------------
-- S2. Códigos y nombres de los vinos que se vendieron en TODAS las salas
--     (división relacional).
-- Estrategia 1 (doble NOT EXISTS): "vinos para los que NO existe una sala
-- en la que NO se hayan vendido".
-- ---------------------------------------------------------------------
\echo '=== S2 (doble NOT EXISTS) ==='
SELECT v.cod_vino, v.nombre
  FROM vino v
 WHERE NOT EXISTS (
         SELECT 1 FROM sala_venta s
          WHERE NOT EXISTS (
                  SELECT 1
                    FROM comprobante c
                    JOIN renglon_comprobante r USING (nro_comprobante)
                   WHERE c.id_sala = s.id_sala
                     AND r.cod_vino = v.cod_vino))
 ORDER BY v.cod_vino;

-- Estrategia 2 (conteo): cantidad de salas distintas donde se vendió =
-- cantidad total de salas. Equivalente y más fácil de leer; sirve de control.
\echo '=== S2 (conteo, control) ==='
SELECT count(*) AS vinos_vendidos_en_todas_las_salas
  FROM (SELECT r.cod_vino
          FROM renglon_comprobante r
          JOIN comprobante c USING (nro_comprobante)
         GROUP BY r.cod_vino
        HAVING count(DISTINCT c.id_sala) = (SELECT count(*) FROM sala_venta)) t;

-- ---------------------------------------------------------------------
-- S3. Cantidad de clientes de cada tipo que compraron en una sala
--     determinada en la última semana.
-- Estrategia: se parte de los valores del ENUM (enum_range) con LEFT JOIN
-- para que aparezcan también los tipos con 0 clientes. count(DISTINCT)
-- cuenta clientes, no compras.
-- ---------------------------------------------------------------------
\echo '=== S3 ==='
SELECT t.tipo, count(DISTINCT c.id_cliente) AS clientes
  FROM unnest(enum_range(NULL::tipo_cliente)) AS t(tipo)
  LEFT JOIN cliente cl ON cl.tipo = t.tipo
  LEFT JOIN comprobante c ON c.id_cliente = cl.id_cliente
                         AND c.id_sala = :id_sala_s3
                         AND c.fecha > CURRENT_DATE - INTERVAL '7 days'
 GROUP BY t.tipo
 ORDER BY t.tipo;

-- ---------------------------------------------------------------------
-- S4. Top 5 de las salas que solicitaron mayor cantidad de un vino
--     determinado mediante transferencias en los últimos 15 días.
-- Se cuentan todas las transferencias confeccionadas en el período, sin
-- importar su estado (la consigna habla de lo solicitado).
-- ---------------------------------------------------------------------
\echo '=== S4 ==='
SELECT t.id_sala, l.nombre AS localidad, SUM(r.cantidad) AS botellas_solicitadas,
       count(*) AS transferencias
  FROM transferencia t
  JOIN renglon_transferencia r USING (nro_transferencia)
  JOIN sala_venta s USING (id_sala)
  JOIN localidad l USING (id_localidad)
 WHERE r.cod_vino = :vino_ref
   AND t.fecha_confeccion >= CURRENT_DATE - 15
 GROUP BY t.id_sala, l.nombre
 ORDER BY botellas_solicitadas DESC, t.id_sala
 LIMIT 5;

-- ---------------------------------------------------------------------
-- S5. Listado de las salas con menor cantidad de transferencias
--     pendientes (no procesadas).
-- Estrategia: LEFT JOIN con la condición de estado EN EL ON (no en el
-- WHERE) para que las salas con 0 pendientes no desaparezcan. El CTE se
-- usa dos veces: para listar y para calcular el mínimo.
-- ---------------------------------------------------------------------
\echo '=== S5 ==='
WITH pendientes AS (
    SELECT s.id_sala, l.nombre AS localidad, count(t.nro_transferencia) AS pendientes
      FROM sala_venta s
      JOIN localidad l USING (id_localidad)
      LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
     GROUP BY s.id_sala, l.nombre
)
SELECT * FROM pendientes
 WHERE pendientes = (SELECT min(pendientes) FROM pendientes)
 ORDER BY id_sala;

-- ---------------------------------------------------------------------
-- S6. Para una sala determinada, los vinos sin stock en la sala pero con
--     stock en el depósito central.
-- Estrategia: anti-join (NOT EXISTS) contra stock_sala. "Sin stock" incluye
-- tanto la fila con cantidad 0 como la ausencia de fila.
-- ---------------------------------------------------------------------
\echo '=== S6 ==='
SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, d.cantidad AS stock_deposito
  FROM vino v
  JOIN stock_deposito d USING (cod_vino)
 WHERE d.cantidad > 0
   AND NOT EXISTS (SELECT 1 FROM stock_sala s
                    WHERE s.id_sala = :id_sala_s6
                      AND s.cod_vino = v.cod_vino
                      AND s.cantidad > 0)
 ORDER BY d.cantidad DESC, v.cod_vino
 LIMIT 20;

-- ---------------------------------------------------------------------
-- S7. ¿Cuál es la empresa de transporte con mayor actividad en el último mes?
-- Actividad = cantidad de ingresos trasladados (se muestra también la
-- cantidad de botellas). WITH TIES devuelve todas si hay empate.
-- ---------------------------------------------------------------------
\echo '=== S7 ==='
SELECT t.cod_transporte, t.razon_social,
       count(DISTINCT i.cod_ingreso) AS ingresos,
       SUM(r.cantidad)               AS botellas
  FROM ingreso i
  JOIN transportista t USING (cod_transporte)
  JOIN renglon_ingreso r USING (cod_ingreso)
 WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
 GROUP BY t.cod_transporte, t.razon_social
 ORDER BY ingresos DESC
 FETCH FIRST 1 ROWS WITH TIES;

-- ---------------------------------------------------------------------
-- S8. Monto total de ventas por sala en el último trimestre, en orden
--     descendente.
-- Usa el total almacenado del comprobante (derivado, garantizado por RN-08).
-- ---------------------------------------------------------------------
\echo '=== S8 ==='
SELECT c.id_sala, l.nombre AS localidad,
       count(*)     AS comprobantes,
       SUM(c.total) AS monto_total
  FROM comprobante c
  JOIN sala_venta s USING (id_sala)
  JOIN localidad l USING (id_localidad)
 WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY c.id_sala, l.nombre
 ORDER BY monto_total DESC;

-- =====================================================================
-- 8.5 Consultas avanzadas
-- =====================================================================

-- ---------------------------------------------------------------------
-- S9. Ficha de un vino: cepas con sus porcentajes, bodega elaboradora,
--     maridajes y stock total (depósito más salas).
-- Estrategia: la vista v_ficha_vino (006_vistas.sql) encapsula los joins
-- y agregaciones. Las cepas y los maridajes se agregan en subconsultas
-- separadas: si se uniera todo y luego se agrupara, cada cepa se repetiría
-- por cada maridaje (producto cartesiano).
-- ---------------------------------------------------------------------
\echo '=== S9 ==='
\x on
SELECT * FROM v_ficha_vino WHERE cod_vino = :vino_ref;
\x off

-- ---------------------------------------------------------------------
-- S10. Rendimiento en kg por hectárea de cada parcela y campaña, e
--      identificar las parcelas que rinden menos que el promedio de su finca.
-- Estrategia: CTE con el rendimiento + subconsulta CORRELACIONADA que
-- calcula el promedio de la misma finca y campaña para cada fila.
-- ---------------------------------------------------------------------
\echo '=== S10 (rendimiento de cada parcela y campaña, primeras 10) ==='
SELECT l.id_finca, f.nombre AS finca, l.nro_parcela, l.campania,
       l.kilos, p.superficie_ha,
       ROUND(l.kilos / p.superficie_ha, 2) AS kg_por_ha
  FROM lote_uva l
  JOIN parcela p USING (id_finca, nro_parcela)
  JOIN finca f USING (id_finca)
 ORDER BY l.id_finca, l.nro_parcela, l.campania
 LIMIT 10;

\echo '=== S10 (parcelas por debajo del promedio de su finca en la campaña) ==='
WITH rendimiento AS (
    SELECT l.id_finca, l.nro_parcela, l.campania,
           l.kilos / p.superficie_ha AS kg_por_ha
      FROM lote_uva l
      JOIN parcela p USING (id_finca, nro_parcela)
)
SELECT r.id_finca, r.nro_parcela, r.campania,
       ROUND(r.kg_por_ha, 2) AS kg_por_ha,
       ROUND((SELECT AVG(r2.kg_por_ha)
                FROM rendimiento r2
               WHERE r2.id_finca = r.id_finca
                 AND r2.campania = r.campania), 2) AS promedio_finca
  FROM rendimiento r
 WHERE r.kg_por_ha < (SELECT AVG(r2.kg_por_ha)
                        FROM rendimiento r2
                       WHERE r2.id_finca = r.id_finca
                         AND r2.campania = r.campania)
 ORDER BY r.id_finca, r.campania, r.kg_por_ha
 LIMIT 20;

-- ---------------------------------------------------------------------
-- S11. Ranking de vinos dentro de cada sala por botellas vendidas, y
--      ventas acumuladas mensuales por sala.
-- Estrategia: RANK() OVER (PARTITION BY sala ORDER BY botellas DESC)
-- numera dentro de cada sala por separado. Se muestran los 3 primeros de
-- cada sala (el filtro va afuera: una función de ventana no se puede usar
-- en el WHERE de la misma consulta).
-- ---------------------------------------------------------------------
\echo '=== S11a (top 3 de vinos por sala, primeras 4 salas) ==='
WITH ventas AS (
    SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS botellas
      FROM renglon_comprobante r
      JOIN comprobante c USING (nro_comprobante)
     GROUP BY c.id_sala, r.cod_vino
), ranking AS (
    SELECT id_sala, cod_vino, botellas,
           RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC) AS puesto
      FROM ventas
)
SELECT rk.id_sala, rk.puesto, rk.cod_vino, v.nombre, rk.botellas
  FROM ranking rk
  JOIN vino v USING (cod_vino)
 WHERE rk.puesto <= 3 AND rk.id_sala <= 4
 ORDER BY rk.id_sala, rk.puesto;

-- Ventas mensuales y acumuladas: SUM(...) OVER con ORDER BY mes suma desde
-- el primer mes hasta el actual (marco por defecto) dentro de cada sala.
\echo '=== S11b (ventas mensuales y acumuladas de la sala 1, últimos 12 meses) ==='
WITH mensual AS (
    SELECT id_sala, date_trunc('month', fecha)::DATE AS mes, SUM(total) AS monto_mes
      FROM comprobante
     GROUP BY id_sala, date_trunc('month', fecha)
), acumulado AS (
    SELECT id_sala, mes, monto_mes,
           SUM(monto_mes) OVER (PARTITION BY id_sala ORDER BY mes) AS acumulado
      FROM mensual
)
SELECT * FROM acumulado
 WHERE id_sala = 1 AND mes >= date_trunc('month', CURRENT_DATE) - INTERVAL '11 months'
 ORDER BY mes;

-- ---------------------------------------------------------------------
-- S12a. Clientes que compraron TODOS los vinos de una bodega determinada
--       (división relacional con doble NOT EXISTS).
-- "Clientes para los que NO existe un vino de esa bodega que NO hayan
-- comprado nunca."
-- ---------------------------------------------------------------------
\echo '=== S12a ==='
SELECT cl.id_cliente, cl.nombre, cl.tipo
  FROM cliente cl
 WHERE NOT EXISTS (
         SELECT 1
           FROM vino v
           JOIN bodega b ON b.cuit = v.cuit_bodega
          WHERE b.razon_social = :'bodega_s12'
            AND NOT EXISTS (
                  SELECT 1
                    FROM comprobante c
                    JOIN renglon_comprobante r USING (nro_comprobante)
                   WHERE c.id_cliente = cl.id_cliente
                     AND r.cod_vino = v.cod_vino))
 ORDER BY cl.id_cliente;

-- ---------------------------------------------------------------------
-- S12b. Clientes que nunca compraron ningún vino tinto (anti-join).
-- Se consideran los clientes que SÍ compraron algo (si no, la respuesta
-- incluiría a todos los que nunca compraron nada, que es otra pregunta).
-- ---------------------------------------------------------------------
\echo '=== S12b (cantidad y primeros 10) ==='
WITH sin_tintos AS (
    SELECT cl.id_cliente, cl.nombre, cl.tipo
      FROM cliente cl
     WHERE EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
       AND NOT EXISTS (
             SELECT 1
               FROM comprobante c
               JOIN renglon_comprobante r USING (nro_comprobante)
               JOIN vino v USING (cod_vino)
              WHERE c.id_cliente = cl.id_cliente
                AND v.tipo = 'tinto')
)
SELECT (SELECT count(*) FROM sin_tintos) AS total, s.*
  FROM sin_tintos s
 ORDER BY s.id_cliente
 LIMIT 10;
