-- Planes de ejecución de las consultas avanzadas S9 a S12 (Etapa 5, paso 6).
-- psql -d bodegas -f db/bench/explain_avanzadas.sql
\pset pager off
\echo '## S9 · Ficha de un vino (vista v_ficha_vino)'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM v_ficha_vino WHERE cod_vino = 1;
\echo '## S10 · Parcelas que rinden menos que el promedio de su finca (CTE + subconsulta correlacionada)'
EXPLAIN (ANALYZE, BUFFERS)
WITH rendimiento AS (
    SELECT l.id_finca, l.nro_parcela, l.campania, l.kilos / p.superficie_ha AS kg_por_ha
      FROM lote_uva l JOIN parcela p USING (id_finca, nro_parcela))
SELECT r.* FROM rendimiento r
 WHERE r.kg_por_ha < (SELECT AVG(r2.kg_por_ha) FROM rendimiento r2
                       WHERE r2.id_finca = r.id_finca AND r2.campania = r.campania);
\echo '## S11 · Ranking de vinos por sala (RANK OVER PARTITION BY)'
EXPLAIN (ANALYZE, BUFFERS)
WITH ventas AS (
    SELECT c.id_sala, r.cod_vino, SUM(r.cantidad) AS botellas
      FROM renglon_comprobante r JOIN comprobante c USING (nro_comprobante)
     GROUP BY c.id_sala, r.cod_vino)
SELECT * FROM (SELECT id_sala, cod_vino, botellas,
                      RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC) AS puesto
                 FROM ventas) t
 WHERE puesto <= 3;
\echo '## S11b · Ventas mensuales acumuladas (SUM OVER)'
EXPLAIN (ANALYZE, BUFFERS)
WITH mensual AS (SELECT id_sala, date_trunc('month', fecha) AS mes, SUM(total) AS monto_mes
                   FROM comprobante GROUP BY 1, 2)
SELECT id_sala, mes, monto_mes, SUM(monto_mes) OVER (PARTITION BY id_sala ORDER BY mes) FROM mensual;
\echo '## S12b · Clientes que nunca compraron vino tinto (anti-join)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT cl.id_cliente FROM cliente cl
 WHERE EXISTS (SELECT 1 FROM comprobante c WHERE c.id_cliente = cl.id_cliente)
   AND NOT EXISTS (SELECT 1 FROM comprobante c JOIN renglon_comprobante r USING (nro_comprobante)
                    JOIN vino v USING (cod_vino)
                    WHERE c.id_cliente = cl.id_cliente AND v.tipo = 'tinto');
