-- =====================================================================
-- 002_constraints.sql · Etapa 2: restricciones adicionales
-- UNIQUE (claves candidatas), CHECK (valores válidos de una fila) y DEFAULT.
--
-- Regla general aplicada: un CHECK solo mira la propia fila y es
-- determinístico. Nada de CURRENT_DATE dentro de un CHECK (cambiaría con
-- el tiempo y rompería la restauración de un backup): lo que depende de la
-- fecha actual o de otras filas va en un trigger (005).
-- =====================================================================

-- ---------------------------------------------------------------------
-- UNIQUE: claves candidatas que no se eligieron como PK
-- ---------------------------------------------------------------------
ALTER TABLE provincia    ADD CONSTRAINT uq_provincia_nombre    UNIQUE (nombre);
ALTER TABLE departamento ADD CONSTRAINT uq_departamento_nombre UNIQUE (nombre, id_provincia);
ALTER TABLE localidad    ADD CONSTRAINT uq_localidad_nombre    UNIQUE (nombre, id_departamento);
ALTER TABLE cepa         ADD CONSTRAINT uq_cepa_nombre         UNIQUE (nombre);
ALTER TABLE maridaje     ADD CONSTRAINT uq_maridaje_nombre     UNIQUE (nombre);
ALTER TABLE bodega       ADD CONSTRAINT uq_bodega_razon_social UNIQUE (razon_social);
ALTER TABLE transportista ADD CONSTRAINT uq_transportista_cuit UNIQUE (cuit);

-- Un vino se distingue de otro del mismo nombre por añada y presentación.
ALTER TABLE vino ADD CONSTRAINT uq_vino_nombre_anada_volumen
    UNIQUE (nombre, anada, volumen_ml);

-- RN-04: una parcela se cosecha como máximo una vez por campaña.
ALTER TABLE lote_uva ADD CONSTRAINT uq_lote_parcela_campania
    UNIQUE (id_finca, nro_parcela, campania);

-- Una persona o empresa se identifica por su documento.
ALTER TABLE cliente ADD CONSTRAINT uq_cliente_documento UNIQUE (tipo_doc, nro_doc);
ALTER TABLE distribuidor ADD CONSTRAINT uq_distribuidor_habilitacion UNIQUE (nro_habilitacion);

-- ---------------------------------------------------------------------
-- CHECK
-- ---------------------------------------------------------------------
-- RN-01 y RN-15: precio positivo; graduación entre 5 y 20.
ALTER TABLE vino
    ADD CONSTRAINT ck_vino_precio      CHECK (precio > 0),
    ADD CONSTRAINT ck_vino_graduacion  CHECK (graduacion BETWEEN 5 AND 20),
    ADD CONSTRAINT ck_vino_anada       CHECK (anada BETWEEN 1900 AND 2100),
    ADD CONSTRAINT ck_vino_volumen     CHECK (volumen_ml IN (187, 375, 750, 1500, 3000));

ALTER TABLE composicion
    ADD CONSTRAINT ck_composicion_porcentaje CHECK (porcentaje > 0 AND porcentaje <= 100);

ALTER TABLE maridaje
    ADD CONSTRAINT ck_maridaje_temperatura CHECK (temperatura_servicio BETWEEN 0 AND 25);

-- RN-15: superficies y kilos positivos.
ALTER TABLE finca
    ADD CONSTRAINT ck_finca_superficie CHECK (superficie_ha > 0);

ALTER TABLE parcela
    ADD CONSTRAINT ck_parcela_superficie CHECK (superficie_ha > 0),
    ADD CONSTRAINT ck_parcela_nro        CHECK (nro_parcela > 0),
    ADD CONSTRAINT ck_parcela_anio       CHECK (anio_plantacion BETWEEN 1900 AND 2100);

-- CHECK entre columnas: la fecha de cosecha pertenece a la campaña.
ALTER TABLE lote_uva
    ADD CONSTRAINT ck_lote_kilos        CHECK (kilos > 0),
    ADD CONSTRAINT ck_lote_campania     CHECK (campania BETWEEN 1990 AND 2100),
    ADD CONSTRAINT ck_lote_fecha_campania
        CHECK (EXTRACT(YEAR FROM fecha_cosecha) = campania);

ALTER TABLE analisis_calidad
    ADD CONSTRAINT ck_analisis_brix   CHECK (brix BETWEEN 0 AND 40),
    ADD CONSTRAINT ck_analisis_ph     CHECK (ph BETWEEN 2 AND 5),
    ADD CONSTRAINT ck_analisis_acidez CHECK (acidez_total > 0);

ALTER TABLE sala_venta
    ADD CONSTRAINT ck_sala_numero CHECK (numero > 0);

ALTER TABLE empleado
    ADD CONSTRAINT ck_empleado_salario CHECK (salario > 0);

-- RN-06: el descuento queda acotado. El valor inicial lo pone el trigger.
ALTER TABLE cliente
    ADD CONSTRAINT ck_cliente_descuento CHECK (descuento BETWEEN 0 AND 50);

-- El subtipo coincide con el tipo del supertipo (junto con la FK compuesta).
ALTER TABLE distribuidor
    ADD CONSTRAINT ck_distribuidor_tipo CHECK (tipo = 'distribuidor');
ALTER TABLE exportador
    ADD CONSTRAINT ck_exportador_tipo CHECK (tipo = 'exportador');

-- RN-07: CHECK entre columnas, el vencimiento es posterior a la emisión.
ALTER TABLE permiso_exportacion
    ADD CONSTRAINT ck_permiso_fechas CHECK (fecha_vencimiento > fecha_emision);

-- RN-08: el total es siempre subtotal - descuento (CHECK entre columnas).
ALTER TABLE comprobante
    ADD CONSTRAINT ck_comprobante_subtotal  CHECK (subtotal >= 0),
    ADD CONSTRAINT ck_comprobante_descuento CHECK (descuento >= 0 AND descuento <= subtotal),
    ADD CONSTRAINT ck_comprobante_total     CHECK (total = subtotal - descuento);

-- RN-15: cantidades y precios positivos.
ALTER TABLE renglon_comprobante
    ADD CONSTRAINT ck_renglon_comp_cantidad  CHECK (cantidad > 0),
    ADD CONSTRAINT ck_renglon_comp_precio    CHECK (precio_unitario > 0),
    ADD CONSTRAINT ck_renglon_comp_descuento CHECK (porcentaje_descuento BETWEEN 0 AND 100),
    ADD CONSTRAINT ck_renglon_comp_subtotal  CHECK (subtotal >= 0);

ALTER TABLE renglon_ingreso
    ADD CONSTRAINT ck_renglon_ingreso_cantidad CHECK (cantidad > 0);

ALTER TABLE renglon_transferencia
    ADD CONSTRAINT ck_renglon_transf_cantidad CHECK (cantidad > 0);

-- RN-09: el stock nunca es negativo. Es la última barrera: aunque un
-- trigger fallara, el UPDATE que deje stock < 0 se rechaza.
ALTER TABLE stock_sala
    ADD CONSTRAINT ck_stock_sala_cantidad CHECK (cantidad >= 0);
ALTER TABLE stock_deposito
    ADD CONSTRAINT ck_stock_deposito_cantidad CHECK (cantidad >= 0);

ALTER TABLE auditoria_precio
    ADD CONSTRAINT ck_auditoria_precios CHECK (precio_anterior > 0 AND precio_nuevo > 0);

-- ---------------------------------------------------------------------
-- DEFAULT
-- ---------------------------------------------------------------------
-- Estado inicial de los documentos (RN-10, RN-11).
ALTER TABLE ingreso       ALTER COLUMN estado SET DEFAULT 'en_confeccion';
ALTER TABLE transferencia ALTER COLUMN estado SET DEFAULT 'en_confeccion';

-- Fechas por defecto: hoy. (DEFAULT sí puede usar CURRENT_DATE: se evalúa
-- una sola vez al insertar, no queda como regla que cambie con el tiempo.)
ALTER TABLE cliente       ALTER COLUMN fecha_alta       SET DEFAULT CURRENT_DATE;
ALTER TABLE comprobante   ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;
ALTER TABLE ingreso       ALTER COLUMN fecha            SET DEFAULT CURRENT_DATE;
ALTER TABLE transferencia ALTER COLUMN fecha_confeccion SET DEFAULT CURRENT_DATE;

-- Importes del comprobante: arrancan en 0 y los recalcula el trigger.
ALTER TABLE comprobante
    ALTER COLUMN subtotal  SET DEFAULT 0,
    ALTER COLUMN descuento SET DEFAULT 0,
    ALTER COLUMN total     SET DEFAULT 0;

ALTER TABLE stock_sala     ALTER COLUMN cantidad SET DEFAULT 0;
ALTER TABLE stock_deposito ALTER COLUMN cantidad SET DEFAULT 0;

-- Auditoría: session_user (y no current_user) porque el trigger corre con
-- SECURITY DEFINER; current_user sería el dueño, no quien hizo el cambio.
ALTER TABLE auditoria_precio
    ALTER COLUMN fecha_hora SET DEFAULT now(),
    ALTER COLUMN usuario    SET DEFAULT session_user;

-- Los subtipos completan su columna tipo solos.
ALTER TABLE distribuidor ALTER COLUMN tipo SET DEFAULT 'distribuidor';
ALTER TABLE exportador   ALTER COLUMN tipo SET DEFAULT 'exportador';
