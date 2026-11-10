-- =====================================================================
-- consultas/delete.sql · Etapa 5 · 8.3 Borrado de datos (DELETE)
--
-- Cómo correrlo:  psql -d bodegas -f consultas/delete.sql
-- Cada consigna: BEGIN -> control previo -> sentencia -> control posterior
-- -> ROLLBACK (reemplazar por COMMIT para aplicarla).
--
-- PARÁMETROS (cambiar acá):
\set localidad_d3 'Real del Padre'
\set localidad_d6 'San Rafael'
-- =====================================================================
\pset footer off
\timing on

-- ---------------------------------------------------------------------
-- D1. Borrar los comprobantes con más de 5 años de antigüedad asociados a
--     clientes socios del club.
--
-- Estrategia: DELETE ... USING para filtrar por el tipo del cliente.
-- Los renglones se borran solos por ON DELETE CASCADE (no existen sin su
-- cabecera). El trigger AFTER DELETE de renglones NO devuelve stock: es una
-- depuración del historial, no una anulación de la venta.
-- Observación: el stock está ALMACENADO (no se calcula desde el historial),
-- por eso se puede depurar el historial sin perder el stock actual.
-- ---------------------------------------------------------------------
\echo '=== D1 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS comprobantes_a_borrar,
       (SELECT count(*) FROM renglon_comprobante r
          JOIN comprobante c USING (nro_comprobante)
          JOIN cliente cl USING (id_cliente)
         WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years') AS renglones_que_arrastra,
       (SELECT SUM(cantidad) FROM stock_sala) AS stock_total_salas
  FROM comprobante c JOIN cliente cl USING (id_cliente)
 WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';

DELETE FROM comprobante c
 USING cliente cl
 WHERE cl.id_cliente = c.id_cliente
   AND cl.tipo = 'socio'
   AND c.fecha < CURRENT_DATE - INTERVAL '5 years';

\echo 'Control posterior: no quedan, no hay renglones huérfanos y el stock no cambió'
SELECT count(*) AS quedan,
       (SELECT count(*) FROM renglon_comprobante r
         WHERE NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.nro_comprobante = r.nro_comprobante)) AS renglones_huerfanos,
       (SELECT SUM(cantidad) FROM stock_sala) AS stock_total_salas
  FROM comprobante c JOIN cliente cl USING (id_cliente)
 WHERE cl.tipo = 'socio' AND c.fecha < CURRENT_DATE - INTERVAL '5 years';
ROLLBACK;

-- ---------------------------------------------------------------------
-- D2. Eliminar las cepas que no componen ningún vino ni están plantadas en
--     ninguna parcela.
--
-- Estrategia: doble NOT EXISTS (anti-join). Aunque se olvidara una
-- condición, las FK con ON DELETE RESTRICT impedirían borrar una cepa en
-- uso. En el dataset las 12 cepas se usan, así que el control previo
-- agrega dos cepas de catálogo sin uso para ver el efecto.
-- ---------------------------------------------------------------------
\echo '=== D2 ==='
BEGIN;
INSERT INTO cepa (nombre, tipo) VALUES ('Criolla Grande', 'tinta'), ('Pedro Giménez', 'blanca');
\echo 'Control previo: cepas sin uso'
SELECT c.id_cepa, c.nombre FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

DELETE FROM cepa c
 WHERE NOT EXISTS (SELECT 1 FROM composicion co WHERE co.id_cepa = c.id_cepa)
   AND NOT EXISTS (SELECT 1 FROM parcela p WHERE p.id_cepa = c.id_cepa);

\echo 'Control posterior'
SELECT count(*) AS cepas FROM cepa;
ROLLBACK;

-- ---------------------------------------------------------------------
-- D3. La sala de una localidad determinada fue dada de baja: eliminar los
--     empleados de esa sala que trabajaron menos de dos años.
--
-- Estrategia: DELETE ... USING con sala y localidad. "Menos de dos años"
-- se calcula con fn_antiguedad_anios (años completos < 2).
-- Los empleados con más antigüedad se conservan (se reubicarían). La sala
-- en sí no se puede borrar mientras tenga empleados, stock o ventas
-- (ON DELETE RESTRICT).
-- ---------------------------------------------------------------------
\echo '=== D3 ==='
BEGIN;
\echo 'Control previo: empleados de la sala'
SELECT e.cuit, e.nombre, e.fecha_ingreso, fn_antiguedad_anios(e.fecha_ingreso) AS anios
  FROM empleado e
  JOIN sala_venta s USING (id_sala)
  JOIN localidad l USING (id_localidad)
 WHERE l.nombre = :'localidad_d3'
 ORDER BY e.fecha_ingreso;

DELETE FROM empleado e
 USING sala_venta s
  JOIN localidad l USING (id_localidad)
 WHERE e.id_sala = s.id_sala
   AND l.nombre = :'localidad_d3'
   AND fn_antiguedad_anios(e.fecha_ingreso) < 2;

\echo 'Control posterior'
SELECT e.cuit, e.nombre, fn_antiguedad_anios(e.fecha_ingreso) AS anios
  FROM empleado e JOIN sala_venta s USING (id_sala) JOIN localidad l USING (id_localidad)
 WHERE l.nombre = :'localidad_d3';
ROLLBACK;

-- ---------------------------------------------------------------------
-- D4. Borrar los clientes socios que nunca compraron y se dieron de alta
--     hace más de 5 años.
--
-- Estrategia: anti-join con NOT EXISTS. Un socio con compras no se podría
-- borrar igual (comprobante -> cliente es ON DELETE RESTRICT).
-- Los socios no tienen tabla de subtipo, así que no hay nada que arrastrar.
-- ---------------------------------------------------------------------
\echo '=== D4 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS socios_a_borrar FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);

DELETE FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);

\echo 'Control posterior'
SELECT count(*) AS quedan FROM cliente c
 WHERE c.tipo = 'socio'
   AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);
ROLLBACK;

-- ---------------------------------------------------------------------
-- D5. Eliminar los ingresos en estado procesado de hace más de 365 días.
--
-- Estrategia: DELETE directo; los renglones se van por CASCADE.
-- Interacción con triggers: el trigger RN-12 bloquea borrar renglones de
-- un ingreso que no está en confección, PERO cuando el borrado viene del
-- CASCADE la cabecera ya no existe y el trigger lo permite. Así se puede
-- depurar un ingreso completo, pero no "retocar" uno procesado.
-- El stock del depósito no cambia: ya fue impactado al procesarlo.
-- ---------------------------------------------------------------------
\echo '=== D5 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS ingresos_a_borrar,
       (SELECT count(*) FROM renglon_ingreso r JOIN ingreso i USING (cod_ingreso)
         WHERE i.estado = 'procesado' AND i.fecha < CURRENT_DATE - INTERVAL '365 days') AS renglones,
       (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito
  FROM ingreso WHERE estado = 'procesado' AND fecha < CURRENT_DATE - INTERVAL '365 days';

DELETE FROM ingreso
 WHERE estado = 'procesado'
   AND fecha < CURRENT_DATE - INTERVAL '365 days';

\echo 'Control posterior'
SELECT count(*) AS quedan, (SELECT SUM(cantidad) FROM stock_deposito) AS stock_deposito
  FROM ingreso WHERE estado = 'procesado' AND fecha < CURRENT_DATE - INTERVAL '365 days';

\echo 'En cambio, borrar un renglón suelto de un ingreso procesado sigue prohibido (RN-12):'
SAVEPOINT antes_rn12;
\set ON_ERROR_STOP off
DELETE FROM renglon_ingreso
 WHERE cod_ingreso = (SELECT min(cod_ingreso) FROM ingreso WHERE estado = 'procesado');
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT antes_rn12;
ROLLBACK;

-- ---------------------------------------------------------------------
-- D6. Borrar los clientes socios sin compras que viven en una localidad
--     específica.
-- Estrategia: igual que D4, filtrando por localidad con USING.
-- ---------------------------------------------------------------------
\echo '=== D6 ==='
BEGIN;
\echo 'Control previo'
SELECT count(*) AS socios_a_borrar
  FROM cliente c JOIN localidad l USING (id_localidad)
 WHERE c.tipo = 'socio' AND l.nombre = :'localidad_d6'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);

DELETE FROM cliente c
 USING localidad l
 WHERE l.id_localidad = c.id_localidad
   AND l.nombre = :'localidad_d6'
   AND c.tipo = 'socio'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);

\echo 'Control posterior'
SELECT count(*) AS quedan
  FROM cliente c JOIN localidad l USING (id_localidad)
 WHERE c.tipo = 'socio' AND l.nombre = :'localidad_d6'
   AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente);
ROLLBACK;
