-- =====================================================================
-- db/seed/consultas_control.sql · Etapa 3: consultas de control
-- Se corren después de la carga. TODAS deben devolver 0.
-- (Las mismas consultas las ejecuta cargar_datos.py al terminar.)
--   psql -d bodegas -f db/seed/consultas_control.sql
-- =====================================================================

-- Filas huérfanas: renglones de comprobante sin cabecera
SELECT 'Filas huérfanas: renglones de comprobante sin cabecera' AS control, (SELECT count(*) FROM renglon_comprobante r WHERE NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.nro_comprobante = r.nro_comprobante)) AS resultado;

-- Comprobantes sin renglones
SELECT 'Comprobantes sin renglones' AS control, (SELECT count(*) FROM comprobante c WHERE NOT EXISTS (SELECT 1 FROM renglon_comprobante r WHERE r.nro_comprobante = c.nro_comprobante)) AS resultado;

-- Comprobantes cuyo total no coincide con la suma de sus renglones (RN-08)
SELECT 'Comprobantes cuyo total no coincide con la suma de sus renglones (RN-08)' AS control, (SELECT count(*) FROM comprobante c WHERE c.total <> fn_total_comprobante(c.nro_comprobante)) AS resultado;

-- Renglones cuyo subtotal no coincide con la fórmula (RN-08)
SELECT 'Renglones cuyo subtotal no coincide con la fórmula (RN-08)' AS control, (SELECT count(*) FROM renglon_comprobante WHERE subtotal <> fn_subtotal_renglon(cantidad, precio_unitario, porcentaje_descuento)) AS resultado;

-- Renglones con descuento distinto al del tipo de cliente (RN-06)
SELECT 'Renglones con descuento distinto al del tipo de cliente (RN-06)' AS control, (SELECT count(*) FROM renglon_comprobante r JOIN comprobante c USING (nro_comprobante) JOIN cliente cl USING (id_cliente) WHERE r.porcentaje_descuento <> fn_descuento_por_tipo(cl.tipo)) AS resultado;

-- Stock negativo en salas o depósito (RN-09)
SELECT 'Stock negativo en salas o depósito (RN-09)' AS control, (SELECT (SELECT count(*) FROM stock_sala WHERE cantidad < 0) + (SELECT count(*) FROM stock_deposito WHERE cantidad < 0)) AS resultado;

-- Stock de sala distinto de transferido - vendido
SELECT 'Stock de sala distinto de transferido - vendido' AS control, (SELECT count(*) FROM stock_sala s WHERE s.cantidad <> COALESCE((SELECT SUM(rt.cantidad) FROM renglon_transferencia rt JOIN transferencia t USING (nro_transferencia) WHERE t.estado = 'procesado' AND t.id_sala = s.id_sala AND rt.cod_vino = s.cod_vino), 0) - COALESCE((SELECT SUM(rc.cantidad) FROM renglon_comprobante rc JOIN comprobante c USING (nro_comprobante) WHERE c.id_sala = s.id_sala AND rc.cod_vino = s.cod_vino), 0)) AS resultado;

-- Stock de depósito distinto de ingresado - transferido
SELECT 'Stock de depósito distinto de ingresado - transferido' AS control, (SELECT count(*) FROM stock_deposito d WHERE d.cantidad <> COALESCE((SELECT SUM(ri.cantidad) FROM renglon_ingreso ri JOIN ingreso i USING (cod_ingreso) WHERE i.estado = 'procesado' AND ri.cod_vino = d.cod_vino), 0) - COALESCE((SELECT SUM(rt.cantidad) FROM renglon_transferencia rt JOIN transferencia t USING (nro_transferencia) WHERE t.estado = 'procesado' AND rt.cod_vino = d.cod_vino), 0)) AS resultado;

-- Vinos cuya composición no suma 100 (RN-05)
SELECT 'Vinos cuya composición no suma 100 (RN-05)' AS control, (SELECT count(*) FROM vino v WHERE (SELECT COALESCE(SUM(porcentaje), 0) FROM composicion c WHERE c.cod_vino = v.cod_vino) <> 100) AS resultado;

-- Ventas anteriores al alta del cliente
SELECT 'Ventas anteriores al alta del cliente' AS control, (SELECT count(*) FROM comprobante c JOIN cliente cl USING (id_cliente) WHERE c.fecha < cl.fecha_alta) AS resultado;

-- Ventas de un vino antes de su primer ingreso al depósito
SELECT 'Ventas de un vino antes de su primer ingreso al depósito' AS control, (SELECT count(*) FROM (SELECT rc.cod_vino, min(c.fecha) AS primera_venta FROM renglon_comprobante rc JOIN comprobante c USING (nro_comprobante) GROUP BY rc.cod_vino) v WHERE v.primera_venta < (SELECT min(i.fecha) FROM renglon_ingreso ri JOIN ingreso i USING (cod_ingreso) WHERE ri.cod_vino = v.cod_vino)) AS resultado;

-- Lotes cuya fecha de cosecha no pertenece a su campaña
SELECT 'Lotes cuya fecha de cosecha no pertenece a su campaña' AS control, (SELECT count(*) FROM lote_uva WHERE EXTRACT(YEAR FROM fecha_cosecha) <> campania) AS resultado;

-- Subtipos que no coinciden con el tipo del cliente
SELECT 'Subtipos que no coinciden con el tipo del cliente' AS control, (SELECT (SELECT count(*) FROM distribuidor d JOIN cliente c USING (id_cliente) WHERE c.tipo <> 'distribuidor') + (SELECT count(*) FROM exportador e JOIN cliente c USING (id_cliente) WHERE c.tipo <> 'exportador')) AS resultado;
