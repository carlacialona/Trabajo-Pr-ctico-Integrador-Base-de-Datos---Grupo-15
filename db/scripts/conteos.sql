-- Conteo de filas por tabla: sirve para comparar una base con su backup restaurado.
SELECT * FROM (
SELECT 'provincia' AS tabla, count(*) FROM provincia UNION ALL
SELECT 'departamento', count(*) FROM departamento UNION ALL
SELECT 'localidad', count(*) FROM localidad UNION ALL
SELECT 'sala_venta', count(*) FROM sala_venta UNION ALL
SELECT 'empleado', count(*) FROM empleado UNION ALL
SELECT 'cepa', count(*) FROM cepa UNION ALL
SELECT 'maridaje', count(*) FROM maridaje UNION ALL
SELECT 'bodega', count(*) FROM bodega UNION ALL
SELECT 'transportista', count(*) FROM transportista UNION ALL
SELECT 'transportista_localidad', count(*) FROM transportista_localidad UNION ALL
SELECT 'finca', count(*) FROM finca UNION ALL
SELECT 'parcela', count(*) FROM parcela UNION ALL
SELECT 'lote_uva', count(*) FROM lote_uva UNION ALL
SELECT 'analisis_calidad', count(*) FROM analisis_calidad UNION ALL
SELECT 'vino', count(*) FROM vino UNION ALL
SELECT 'composicion', count(*) FROM composicion UNION ALL
SELECT 'vino_maridaje', count(*) FROM vino_maridaje UNION ALL
SELECT 'cliente', count(*) FROM cliente UNION ALL
SELECT 'distribuidor', count(*) FROM distribuidor UNION ALL
SELECT 'exportador', count(*) FROM exportador UNION ALL
SELECT 'permiso_exportacion', count(*) FROM permiso_exportacion UNION ALL
SELECT 'comprobante', count(*) FROM comprobante UNION ALL
SELECT 'renglon_comprobante', count(*) FROM renglon_comprobante UNION ALL
SELECT 'ingreso', count(*) FROM ingreso UNION ALL
SELECT 'renglon_ingreso', count(*) FROM renglon_ingreso UNION ALL
SELECT 'transferencia', count(*) FROM transferencia UNION ALL
SELECT 'renglon_transferencia', count(*) FROM renglon_transferencia UNION ALL
SELECT 'stock_sala', count(*) FROM stock_sala UNION ALL
SELECT 'stock_deposito', count(*) FROM stock_deposito UNION ALL
SELECT 'auditoria_precio', count(*) FROM auditoria_precio
) t ORDER BY tabla;
