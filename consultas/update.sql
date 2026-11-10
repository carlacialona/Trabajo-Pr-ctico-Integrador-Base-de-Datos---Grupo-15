-- =====================================================================
-- consultas/update.sql · Etapa 5 · 8.1 Modificación de datos (UPDATE)
--
-- Cómo correrlo:  psql -d bodegas -f consultas/update.sql
-- Cada consigna se prueba dentro de una transacción:
--   BEGIN -> control previo -> sentencia -> control posterior -> ROLLBACK
-- Así se ve el efecto y la base queda como estaba. Para aplicar un cambio
-- de verdad, reemplazar ROLLBACK por COMMIT.
--
-- PARÁMETROS (cambiar acá):
\set bodega_u3 'Viñedos Lopez SRL'
-- =====================================================================
\pset footer off

-- ---------------------------------------------------------------------
-- U1. Recalcular el total de todos los comprobantes aplicando el descuento
--     que corresponde al tipo de cliente.
--
-- Estrategia: los importes del comprobante NO se actualizan directamente
-- (RN-08: el trigger trg_comprobante_importes lo rechaza). Se corrige el
-- porcentaje de descuento de los RENGLONES que no coinciden con el de su
-- tipo de cliente (fn_descuento_por_tipo); el trigger BEFORE UPDATE
-- recalcula el subtotal del renglón y el AFTER UPDATE recalcula la
-- cabecera con fn_recalcular_comprobante.
-- El WHERE filtra solo los renglones que difieren: actualizar los 500.000
-- renglones dispararía 500.000 recálculos innecesarios.
-- Con datos consistentes afecta 0 filas; para ver el efecto, el control
-- previo "rompe" a propósito 3 renglones (les pone 0 % de descuento).
-- ---------------------------------------------------------------------
\echo '=== U1 ==='
BEGIN;
-- Simulamos un error: 3 renglones sin descuento.
UPDATE renglon_comprobante SET porcentaje_descuento = 0
 WHERE nro_comprobante IN (1, 2, 3);

\echo 'Control previo: comprobantes con renglones cuyo descuento no es el de su tipo de cliente'
SELECT c.nro_comprobante, cl.tipo, c.subtotal, c.descuento, c.total
  FROM comprobante c JOIN cliente cl USING (id_cliente)
 WHERE EXISTS (SELECT 1 FROM renglon_comprobante r
                WHERE r.nro_comprobante = c.nro_comprobante
                  AND r.porcentaje_descuento <> fn_descuento_por_tipo(cl.tipo))
 ORDER BY 1;

UPDATE renglon_comprobante r
   SET porcentaje_descuento = fn_descuento_por_tipo(cl.tipo)
  FROM comprobante c
  JOIN cliente cl USING (id_cliente)
 WHERE c.nro_comprobante = r.nro_comprobante
   AND r.porcentaje_descuento <> fn_descuento_por_tipo(cl.tipo);

\echo 'Control posterior: ya no queda ninguno y las cabeceras se recalcularon solas'
SELECT count(*) AS renglones_inconsistentes
  FROM renglon_comprobante r
  JOIN comprobante c USING (nro_comprobante)
  JOIN cliente cl USING (id_cliente)
 WHERE r.porcentaje_descuento <> fn_descuento_por_tipo(cl.tipo);
SELECT nro_comprobante, subtotal, descuento, total, fn_total_comprobante(nro_comprobante) AS suma_renglones
  FROM comprobante WHERE nro_comprobante IN (1, 2, 3) ORDER BY 1;
ROLLBACK;

-- ---------------------------------------------------------------------
-- U2. Aumentar un 20 % el salario de los empleados con más de 5 años de
--     antigüedad.
-- Estrategia: fn_antiguedad_anios (STABLE) calcula los años completos a
-- partir de CURRENT_DATE; ROUND deja el importe con 2 decimales.
-- ---------------------------------------------------------------------
\echo '=== U2 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS empleados_mas_5_anios, SUM(salario) AS masa_salarial
  FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

UPDATE empleado
   SET salario = ROUND(salario * 1.20, 2)
 WHERE fn_antiguedad_anios(fecha_ingreso) > 5;

\echo 'Control posterior (la masa salarial sube un 20 %)'
SELECT count(*) AS empleados_mas_5_anios, SUM(salario) AS masa_salarial
  FROM empleado WHERE fn_antiguedad_anios(fecha_ingreso) > 5;
ROLLBACK;

-- ---------------------------------------------------------------------
-- U3. Incrementar un 13 % el precio de los vinos de una bodega determinada.
-- Estrategia: subconsulta por razón social (clave candidata UNIQUE).
-- Dispara el trigger de auditoría (RN-13): una fila de auditoria_precio
-- por vino modificado.
-- ---------------------------------------------------------------------
\echo '=== U3 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS vinos, ROUND(AVG(precio), 2) AS precio_promedio,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
  FROM vino WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');

UPDATE vino
   SET precio = ROUND(precio * 1.13, 2)
 WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');

\echo 'Control posterior: precio +13 % y una fila de auditoría por vino (trigger RN-13)'
SELECT count(*) AS vinos, ROUND(AVG(precio), 2) AS precio_promedio,
       (SELECT count(*) FROM auditoria_precio) AS filas_auditoria
  FROM vino WHERE cuit_bodega = (SELECT cuit FROM bodega WHERE razon_social = :'bodega_u3');
SELECT cod_vino, precio_anterior, precio_nuevo, usuario FROM auditoria_precio ORDER BY id_auditoria LIMIT 3;
ROLLBACK;

-- ---------------------------------------------------------------------
-- U4. En las salas cuyo día de cierre es lunes cambiarlo a miércoles y
--     viceversa, en una sola sentencia.
-- Estrategia: un CASE dentro del SET. Como un UPDATE evalúa todas las
-- filas sobre la versión ANTERIOR de la tabla, no hay riesgo de que una
-- sala pase de lunes a miércoles y vuelva a lunes en la misma sentencia.
-- ---------------------------------------------------------------------
\echo '=== U4 ==='
BEGIN;
\echo 'Control previo'
SELECT dia_cierre, count(*) FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre ORDER BY dia_cierre;

UPDATE sala_venta
   SET dia_cierre = CASE dia_cierre
                        WHEN 'lunes'     THEN 'miercoles'::dia_semana
                        WHEN 'miercoles' THEN 'lunes'::dia_semana
                    END
 WHERE dia_cierre IN ('lunes', 'miercoles');

\echo 'Control posterior (las cantidades se intercambian)'
SELECT dia_cierre, count(*) FROM sala_venta
 WHERE dia_cierre IN ('lunes', 'miercoles') GROUP BY dia_cierre ORDER BY dia_cierre;
ROLLBACK;

-- ---------------------------------------------------------------------
-- U5. Aplicar un 15 % de descuento de precio a los 10 vinos menos vendidos
--     de toda la red.
-- Estrategia: CTE con LEFT JOIN para incluir los vinos que no se vendieron
-- nunca (0 botellas, son los "menos vendidos"). Ante empates, se desempata
-- por código para que el resultado sea determinístico.
-- También queda auditado (RN-13).
-- ---------------------------------------------------------------------
\echo '=== U5 ==='
BEGIN;
\echo 'Control previo: los 10 menos vendidos'
WITH ventas AS (
    SELECT v.cod_vino, v.nombre, v.precio, COALESCE(SUM(r.cantidad), 0) AS botellas
      FROM vino v
      LEFT JOIN renglon_comprobante r USING (cod_vino)
     GROUP BY v.cod_vino
     ORDER BY botellas, v.cod_vino
     LIMIT 10)
SELECT * FROM ventas;

WITH menos_vendidos AS (
    SELECT v.cod_vino
      FROM vino v
      LEFT JOIN renglon_comprobante r USING (cod_vino)
     GROUP BY v.cod_vino
     ORDER BY COALESCE(SUM(r.cantidad), 0), v.cod_vino
     LIMIT 10)
UPDATE vino
   SET precio = ROUND(precio * 0.85, 2)
 WHERE cod_vino IN (SELECT cod_vino FROM menos_vendidos);

\echo 'Control posterior: precio_anterior * 0,85 = precio_nuevo'
SELECT cod_vino, precio_anterior, precio_nuevo FROM auditoria_precio ORDER BY id_auditoria;
ROLLBACK;

-- ---------------------------------------------------------------------
-- U6. A los exportadores con más de 3 permisos de exportación, subirles el
--     descuento al 35 %.
-- Estrategia: GROUP BY + HAVING sobre permiso_exportacion. Como la FK de
-- permiso apunta a exportador, todos los clientes que aparecen ahí son
-- exportadores: no hace falta filtrar por tipo.
-- Este UPDATE es posible porque el descuento se ALMACENA en cliente
-- (decisión de diseño). El CHECK ck_cliente_descuento (0 a 50) lo acota.
-- Las ventas ya registradas no cambian: guardan su porcentaje en el renglón.
-- ---------------------------------------------------------------------
\echo '=== U6 ==='
BEGIN;
\echo 'Control previo'
SELECT descuento, count(*) FROM cliente WHERE tipo = 'exportador' GROUP BY descuento ORDER BY 1;

UPDATE cliente
   SET descuento = 35
 WHERE id_cliente IN (SELECT id_cliente
                        FROM permiso_exportacion
                       GROUP BY id_cliente
                      HAVING count(*) > 3);

\echo 'Control posterior'
SELECT descuento, count(*) FROM cliente WHERE tipo = 'exportador' GROUP BY descuento ORDER BY 1;
ROLLBACK;
