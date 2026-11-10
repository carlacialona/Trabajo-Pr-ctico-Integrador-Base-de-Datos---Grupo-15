-- =====================================================================
-- 008_indices.sql · Etapa 4: índices
--
-- PostgreSQL crea índices solo para PRIMARY KEY y UNIQUE. Las claves
-- foráneas NO se indexan solas. Cada índice de este archivo nació de un
-- plan de ejecución medido (docs/informes/etapa4_indices.md) y tiene un
-- costo: ocupa espacio y hace más lento cada INSERT/UPDATE/DELETE de su
-- tabla. Por eso hay pocos y justificados.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Índice sobre CLAVE FORÁNEA: renglon_comprobante(cod_vino)
-- La PK es (nro_comprobante, cod_vino): sirve para buscar por comprobante,
-- pero NO por vino solo (cod_vino es la segunda columna).
-- Lo usan: S2 y S12 (¿se vendió este vino?), U5 (ventas por vino), el
-- detalle de un vino y el chequeo de la FK al borrar un vino (RN-14).
-- ---------------------------------------------------------------------
CREATE INDEX idx_renglon_comprobante_vino
    ON renglon_comprobante (cod_vino);

-- ---------------------------------------------------------------------
-- 2. Índice sobre CLAVE FORÁNEA: comprobante(id_cliente)
-- Sin él, borrar un cliente obliga a recorrer los 150.000 comprobantes
-- para verificar la FK (D4 tardaba ~4 s para 650 clientes). También lo
-- usan S12 (compras de un cliente) y el anti-join "nunca compró".
-- ---------------------------------------------------------------------
CREATE INDEX idx_comprobante_cliente
    ON comprobante (id_cliente);

-- ---------------------------------------------------------------------
-- 3. Índice COMPUESTO con INCLUDE: comprobante(id_sala, fecha) INCLUDE (total)
-- Orden de columnas: primero id_sala (se filtra por IGUALDAD), después
-- fecha (se filtra por RANGO). Con el orden inverso, el índice tendría
-- que recorrer todo el rango de fechas de todas las salas y descartar.
-- INCLUDE (total) agrega el monto en las hojas del índice: "ventas de la
-- sala X en el período" se resuelve con un Index Only Scan, sin leer la
-- tabla. Lo usan S3, S11b, el tablero y la API (ventas por sala).
-- ---------------------------------------------------------------------
CREATE INDEX idx_comprobante_sala_fecha
    ON comprobante (id_sala, fecha) INCLUDE (total, id_cliente);

-- ---------------------------------------------------------------------
-- 4. Índice PARCIAL: transferencias pendientes
-- Solo indexa las transferencias que NO están procesadas (unas 150 de
-- 5.800): es diminuto y siempre está en memoria. Lo usan S5, la vista
-- v_documentos_pendientes y la pantalla de transferencias.
-- ---------------------------------------------------------------------
CREATE INDEX idx_transferencia_pendientes
    ON transferencia (id_sala, fecha_confeccion)
    WHERE estado <> 'procesado';

-- ---------------------------------------------------------------------
-- 5. Índice BRIN: comprobante(fecha)
-- Las ventas se insertan en orden cronológico, así que el orden físico de
-- la tabla sigue a la fecha. Un BRIN guarda solo el mínimo y el máximo de
-- cada bloque de páginas: ocupa unas pocas páginas (un B-tree sobre la
-- misma columna ocupa varios MB) y sirve para rangos de fechas sobre toda
-- la red (S8: "último trimestre", D1: "más de 5 años").
-- ---------------------------------------------------------------------
CREATE INDEX idx_comprobante_fecha_brin
    ON comprobante USING brin (fecha);
