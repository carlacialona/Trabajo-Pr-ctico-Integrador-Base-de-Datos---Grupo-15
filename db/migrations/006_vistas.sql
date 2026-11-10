-- =====================================================================
-- 006_vistas.sql · Etapa 2: vistas
-- Una vista guarda una CONSULTA, no datos: siempre muestra lo actual.
-- Una vista materializada guarda el RESULTADO: es rápida de leer, pero
-- hay que refrescarla (REFRESH MATERIALIZED VIEW) para ver datos nuevos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_stock_total_vino: stock de cada vino en el depósito, en las salas y total.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_stock_total_vino AS
SELECT v.cod_vino,
       v.nombre,
       v.anada,
       v.volumen_ml,
       COALESCE(d.cantidad, 0)                       AS stock_deposito,
       COALESCE(s.stock_salas, 0)                    AS stock_salas,
       COALESCE(d.cantidad, 0) + COALESCE(s.stock_salas, 0) AS stock_total
  FROM vino v
  LEFT JOIN stock_deposito d ON d.cod_vino = v.cod_vino
  LEFT JOIN (SELECT cod_vino, SUM(cantidad)::INTEGER AS stock_salas
               FROM stock_sala
              GROUP BY cod_vino) s ON s.cod_vino = v.cod_vino;

-- ---------------------------------------------------------------------
-- v_ficha_vino: ficha completa de un vino (consulta S9).
-- Las cepas y maridajes se agregan en subconsultas separadas para no
-- multiplicar filas (cepas x maridajes) antes de agregar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_ficha_vino AS
SELECT v.cod_vino,
       v.nombre,
       v.tipo,
       v.anada,
       v.volumen_ml,
       v.graduacion,
       v.precio,
       b.razon_social AS bodega,
       (SELECT string_agg(c.nombre || ' ' || co.porcentaje || '%', ', '
                          ORDER BY co.porcentaje DESC, c.nombre)
          FROM composicion co JOIN cepa c ON c.id_cepa = co.id_cepa
         WHERE co.cod_vino = v.cod_vino) AS cepas,
       (SELECT string_agg(m.nombre || ' (' || m.temperatura_servicio || ' °C)', ', '
                          ORDER BY m.nombre)
          FROM vino_maridaje vm JOIN maridaje m ON m.id_maridaje = vm.id_maridaje
         WHERE vm.cod_vino = v.cod_vino) AS maridajes,
       st.stock_deposito,
       st.stock_salas,
       st.stock_total
  FROM vino v
  JOIN bodega b ON b.cuit = v.cuit_bodega
  JOIN v_stock_total_vino st ON st.cod_vino = v.cod_vino;

-- ---------------------------------------------------------------------
-- v_documentos_pendientes: ingresos y transferencias que todavía no se
-- procesaron (en confección o terminados).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_documentos_pendientes AS
SELECT 'ingreso'::TEXT       AS tipo_documento,
       i.cod_ingreso         AS numero,
       i.fecha,
       i.estado,
       'Bodega ' || b.razon_social || ' · ' || t.razon_social AS detalle,
       (SELECT COALESCE(SUM(cantidad), 0) FROM renglon_ingreso r
         WHERE r.cod_ingreso = i.cod_ingreso)::INTEGER AS botellas
  FROM ingreso i
  JOIN bodega b        ON b.cuit = i.cuit_bodega
  JOIN transportista t ON t.cod_transporte = i.cod_transporte
 WHERE i.estado <> 'procesado'
UNION ALL
SELECT 'transferencia',
       tr.nro_transferencia,
       tr.fecha_confeccion,
       tr.estado,
       'Sala ' || tr.id_sala,
       (SELECT COALESCE(SUM(cantidad), 0) FROM renglon_transferencia r
         WHERE r.nro_transferencia = tr.nro_transferencia)::INTEGER
  FROM transferencia tr
 WHERE tr.estado <> 'procesado';

-- ---------------------------------------------------------------------
-- mv_ventas_mensuales_sala (MATERIALIZADA): monto vendido por sala y mes.
-- Recorrer 150.000 comprobantes en cada consulta del tablero es caro; el
-- resultado (salas x meses) es chico y cambia una vez por día.
-- El índice único permite REFRESH ... CONCURRENTLY (sin bloquear lecturas).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW mv_ventas_mensuales_sala AS
SELECT c.id_sala,
       date_trunc('month', c.fecha)::DATE AS mes,
       count(*)                           AS comprobantes,
       SUM(c.total)::NUMERIC(14,2)        AS monto_total
  FROM comprobante c
 GROUP BY c.id_sala, date_trunc('month', c.fecha);

CREATE UNIQUE INDEX uq_mv_ventas_mensuales_sala
    ON mv_ventas_mensuales_sala (id_sala, mes);

-- Refresco con permisos del dueño, para poder darle EXECUTE a la API sin
-- darle la propiedad de la vista.
CREATE OR REPLACE FUNCTION fn_refrescar_ventas_mensuales()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_mensuales_sala;
END;
$$;
