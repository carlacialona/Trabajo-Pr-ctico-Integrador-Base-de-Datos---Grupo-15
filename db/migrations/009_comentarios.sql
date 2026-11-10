-- =====================================================================
-- 009_comentarios.sql · Diccionario de datos dentro de la base
-- Las descripciones viven en el catálogo de PostgreSQL (COMMENT ON). El
-- documento docs/diccionario_datos.md se GENERA a partir de acá
-- (db/scripts/generar_diccionario.py), así siempre coincide con el esquema.
-- =====================================================================

COMMENT ON TABLE provincia IS 'Provincias argentinas.';
COMMENT ON COLUMN provincia.id_provincia IS 'Identificador subrogado.';
COMMENT ON COLUMN provincia.nombre IS 'Nombre de la provincia (clave candidata).';

COMMENT ON TABLE departamento IS 'Departamentos (división política dentro de una provincia). Tabla propia para evitar la dependencia transitiva finca -> departamento -> provincia.';
COMMENT ON COLUMN departamento.id_departamento IS 'Identificador subrogado.';
COMMENT ON COLUMN departamento.nombre IS 'Nombre del departamento (único dentro de la provincia).';
COMMENT ON COLUMN departamento.id_provincia IS 'Provincia a la que pertenece.';

COMMENT ON TABLE localidad IS 'Localidades. Cada una tiene un único encargado regional (RN-02).';
COMMENT ON COLUMN localidad.id_localidad IS 'Identificador subrogado. El código postal no sirve como clave porque varias localidades lo comparten.';
COMMENT ON COLUMN localidad.nombre IS 'Nombre (único dentro del departamento).';
COMMENT ON COLUMN localidad.codigo_postal IS 'Código postal. Puede repetirse entre localidades.';
COMMENT ON COLUMN localidad.id_departamento IS 'Departamento al que pertenece (de ahí se obtiene la provincia).';
COMMENT ON COLUMN localidad.encargado_regional IS 'Responsable comercial de todas las salas de la localidad. Depende de la localidad, no de la sala (RN-02).';

COMMENT ON TABLE sala_venta IS 'Salas de venta de la red. Una sala está en una sola localidad.';
COMMENT ON COLUMN sala_venta.id_sala IS 'Identificador de la sala.';
COMMENT ON COLUMN sala_venta.calle IS 'Calle del domicilio.';
COMMENT ON COLUMN sala_venta.numero IS 'Número del domicilio (positivo).';
COMMENT ON COLUMN sala_venta.dia_cierre IS 'Día de cierre semanal.';
COMMENT ON COLUMN sala_venta.id_localidad IS 'Localidad donde está la sala (RN-02).';

COMMENT ON TABLE empleado IS 'Empleados. Cada uno trabaja en una sola sala (RN-03).';
COMMENT ON COLUMN empleado.cuit IS 'CUIT del empleado (clave natural, 11 dígitos).';
COMMENT ON COLUMN empleado.nombre IS 'Apellido y nombre.';
COMMENT ON COLUMN empleado.fecha_ingreso IS 'Fecha de ingreso laboral (base de la antigüedad).';
COMMENT ON COLUMN empleado.salario IS 'Salario mensual (positivo).';
COMMENT ON COLUMN empleado.id_sala IS 'Sala donde trabaja. NOT NULL: RN-03.';

COMMENT ON TABLE finca IS 'Fincas donde se cultiva la uva.';
COMMENT ON COLUMN finca.id_finca IS 'Identificador de la finca.';
COMMENT ON COLUMN finca.nombre IS 'Nombre de la finca.';
COMMENT ON COLUMN finca.superficie_ha IS 'Superficie total en hectáreas (positiva).';
COMMENT ON COLUMN finca.id_departamento IS 'Departamento donde se ubica.';

COMMENT ON TABLE cepa IS 'Catálogo de variedades de uva.';
COMMENT ON COLUMN cepa.id_cepa IS 'Identificador de la cepa.';
COMMENT ON COLUMN cepa.nombre IS 'Nombre de la variedad (único).';
COMMENT ON COLUMN cepa.tipo IS 'Tinta o blanca.';

COMMENT ON TABLE parcela IS 'Parcelas de una finca. Entidad débil: se identifica por (finca, número).';
COMMENT ON COLUMN parcela.id_finca IS 'Finca a la que pertenece (parte de la PK).';
COMMENT ON COLUMN parcela.nro_parcela IS 'Número de parcela dentro de la finca (parte de la PK).';
COMMENT ON COLUMN parcela.superficie_ha IS 'Superficie en hectáreas (positiva).';
COMMENT ON COLUMN parcela.anio_plantacion IS 'Año en que se plantó.';
COMMENT ON COLUMN parcela.id_cepa IS 'Única cepa plantada en la parcela (RN-04).';

COMMENT ON TABLE bodega IS 'Bodegas del grupo, que elaboran los vinos y reciben la uva.';
COMMENT ON COLUMN bodega.cuit IS 'CUIT de la bodega (clave natural).';
COMMENT ON COLUMN bodega.razon_social IS 'Razón social (clave candidata).';
COMMENT ON COLUMN bodega.domicilio IS 'Domicilio.';

COMMENT ON TABLE lote_uva IS 'Cosecha de una parcela en una campaña. Una sola por parcela y campaña (RN-04).';
COMMENT ON COLUMN lote_uva.nro_lote IS 'Número de lote (PK elegida).';
COMMENT ON COLUMN lote_uva.id_finca IS 'Finca de la parcela cosechada.';
COMMENT ON COLUMN lote_uva.nro_parcela IS 'Parcela cosechada.';
COMMENT ON COLUMN lote_uva.campania IS 'Año de cosecha. (finca, parcela, campaña) es clave candidata: RN-04.';
COMMENT ON COLUMN lote_uva.fecha_cosecha IS 'Fecha de cosecha; su año debe coincidir con la campaña.';
COMMENT ON COLUMN lote_uva.kilos IS 'Kilos cosechados (positivos).';
COMMENT ON COLUMN lote_uva.cuit_bodega IS 'Bodega a la que se entregó la uva.';

COMMENT ON TABLE analisis_calidad IS 'Análisis de calidad de un lote (uno o más por lote).';
COMMENT ON COLUMN analisis_calidad.id_analisis IS 'Identificador del análisis.';
COMMENT ON COLUMN analisis_calidad.nro_lote IS 'Lote analizado.';
COMMENT ON COLUMN analisis_calidad.fecha IS 'Fecha del análisis.';
COMMENT ON COLUMN analisis_calidad.brix IS 'Grado Brix (azúcar), entre 0 y 40.';
COMMENT ON COLUMN analisis_calidad.ph IS 'pH, entre 2 y 5.';
COMMENT ON COLUMN analisis_calidad.acidez_total IS 'Acidez total en g/L (positiva).';

COMMENT ON TABLE vino IS 'Vinos elaborados. Se distinguen por nombre, añada y presentación.';
COMMENT ON COLUMN vino.cod_vino IS 'Código del vino (subrogado).';
COMMENT ON COLUMN vino.nombre IS 'Nombre comercial. (nombre, añada, volumen) es clave candidata.';
COMMENT ON COLUMN vino.tipo IS 'Tinto, blanco, rosado o espumante.';
COMMENT ON COLUMN vino.anada IS 'Año de la cosecha con que se elaboró.';
COMMENT ON COLUMN vino.volumen_ml IS 'Presentación en ml: 187, 375, 750, 1500 o 3000.';
COMMENT ON COLUMN vino.graduacion IS 'Graduación alcohólica, entre 5 y 20 (RN-15).';
COMMENT ON COLUMN vino.precio IS 'Precio de venta, único para toda la red y mayor que 0 (RN-01). Sus cambios se auditan (RN-13).';
COMMENT ON COLUMN vino.cuit_bodega IS 'Bodega que lo elabora.';

COMMENT ON TABLE composicion IS 'Relación N:M vino-cepa con el porcentaje de corte. Los porcentajes de un vino suman 100 (RN-05).';
COMMENT ON COLUMN composicion.cod_vino IS 'Vino.';
COMMENT ON COLUMN composicion.id_cepa IS 'Cepa que interviene en el corte.';
COMMENT ON COLUMN composicion.porcentaje IS 'Porcentaje de esa cepa en el vino (mayor que 0, hasta 100).';

COMMENT ON TABLE maridaje IS 'Catálogo de maridajes recomendados.';
COMMENT ON COLUMN maridaje.id_maridaje IS 'Identificador del maridaje.';
COMMENT ON COLUMN maridaje.nombre IS 'Nombre (único), por ejemplo "Carnes rojas".';
COMMENT ON COLUMN maridaje.temperatura_servicio IS 'Temperatura de servicio sugerida en °C.';

COMMENT ON TABLE vino_maridaje IS 'Relación N:M entre vinos y maridajes recomendados.';
COMMENT ON COLUMN vino_maridaje.cod_vino IS 'Vino.';
COMMENT ON COLUMN vino_maridaje.id_maridaje IS 'Maridaje recomendado.';

COMMENT ON TABLE cliente IS 'Supertipo de la jerarquía de clientes (socio, distribuidor, exportador).';
COMMENT ON COLUMN cliente.id_cliente IS 'Identificador subrogado.';
COMMENT ON COLUMN cliente.tipo IS 'Discriminador del subtipo.';
COMMENT ON COLUMN cliente.nombre IS 'Apellido y nombre (persona) o razón social (empresa).';
COMMENT ON COLUMN cliente.tipo_doc IS 'Tipo de documento. (tipo_doc, nro_doc) es clave candidata.';
COMMENT ON COLUMN cliente.nro_doc IS 'Número de documento.';
COMMENT ON COLUMN cliente.direccion IS 'Dirección.';
COMMENT ON COLUMN cliente.id_localidad IS 'Localidad del domicilio.';
COMMENT ON COLUMN cliente.fecha_alta IS 'Fecha de alta (por defecto, hoy).';
COMMENT ON COLUMN cliente.descuento IS 'Porcentaje de descuento vigente. Lo inicializa un trigger según el tipo (RN-06); se almacena porque puede ajustarse (consulta U6).';

COMMENT ON TABLE distribuidor IS 'Subtipo distribuidor (20 % de descuento base).';
COMMENT ON COLUMN distribuidor.id_cliente IS 'Cliente (PK y FK al supertipo).';
COMMENT ON COLUMN distribuidor.tipo IS 'Siempre "distribuidor": junto con la FK compuesta garantiza que el cliente sea de este tipo.';
COMMENT ON COLUMN distribuidor.zona_cobertura IS 'Zona de cobertura.';
COMMENT ON COLUMN distribuidor.nro_habilitacion IS 'Número de habilitación (único).';

COMMENT ON TABLE exportador IS 'Subtipo exportador (30 % de descuento base).';
COMMENT ON COLUMN exportador.id_cliente IS 'Cliente (PK y FK al supertipo).';
COMMENT ON COLUMN exportador.tipo IS 'Siempre "exportador".';
COMMENT ON COLUMN exportador.pais_destino IS 'País de destino principal.';

COMMENT ON TABLE permiso_exportacion IS 'Permisos de exportación. Varios por exportador (RN-07).';
COMMENT ON COLUMN permiso_exportacion.cod_permiso IS 'Código del permiso.';
COMMENT ON COLUMN permiso_exportacion.id_cliente IS 'Exportador titular (FK a exportador, no a cliente).';
COMMENT ON COLUMN permiso_exportacion.fecha_emision IS 'Fecha de emisión.';
COMMENT ON COLUMN permiso_exportacion.fecha_vencimiento IS 'Fecha de vencimiento, posterior a la emisión (RN-07).';

COMMENT ON TABLE comprobante IS 'Cabecera de una venta. Los importes son derivados y los calcula un trigger (RN-08).';
COMMENT ON COLUMN comprobante.nro_comprobante IS 'Número de comprobante.';
COMMENT ON COLUMN comprobante.fecha IS 'Fecha de la venta (por defecto, hoy).';
COMMENT ON COLUMN comprobante.id_cliente IS 'Cliente que compra.';
COMMENT ON COLUMN comprobante.id_sala IS 'Sala donde se realizó la venta.';
COMMENT ON COLUMN comprobante.subtotal IS 'Suma de cantidad x precio de los renglones (derivado, almacenado).';
COMMENT ON COLUMN comprobante.descuento IS 'Importe descontado = subtotal - total (derivado, almacenado).';
COMMENT ON COLUMN comprobante.total IS 'Suma de los subtotales de los renglones con descuento (derivado, almacenado, RN-08).';

COMMENT ON TABLE renglon_comprobante IS 'Relación N:M comprobante-vino con los datos de la línea de venta.';
COMMENT ON COLUMN renglon_comprobante.nro_comprobante IS 'Comprobante.';
COMMENT ON COLUMN renglon_comprobante.cod_vino IS 'Vino vendido. Un vino aparece una sola vez por comprobante (PK).';
COMMENT ON COLUMN renglon_comprobante.cantidad IS 'Botellas vendidas (positiva).';
COMMENT ON COLUMN renglon_comprobante.precio_unitario IS 'Precio del vino AL MOMENTO de la venta (lo completa el trigger). No es redundante con vino.precio.';
COMMENT ON COLUMN renglon_comprobante.porcentaje_descuento IS 'Descuento aplicado, el del cliente al momento de la venta.';
COMMENT ON COLUMN renglon_comprobante.subtotal IS 'cantidad x precio x (1 - descuento/100), redondeado a centavos.';

COMMENT ON TABLE transportista IS 'Empresas de transporte que trasladan los ingresos.';
COMMENT ON COLUMN transportista.cod_transporte IS 'Código del transportista.';
COMMENT ON COLUMN transportista.razon_social IS 'Razón social.';
COMMENT ON COLUMN transportista.cuit IS 'CUIT (clave candidata).';
COMMENT ON COLUMN transportista.email IS 'Correo electrónico.';
COMMENT ON COLUMN transportista.telefono IS 'Teléfono.';
COMMENT ON COLUMN transportista.domicilio IS 'Domicilio.';

COMMENT ON TABLE transportista_localidad IS 'Relación N:M: localidades que alcanza el servicio de cada transportista.';
COMMENT ON COLUMN transportista_localidad.cod_transporte IS 'Transportista.';
COMMENT ON COLUMN transportista_localidad.id_localidad IS 'Localidad cubierta.';

COMMENT ON TABLE ingreso IS 'Ingreso de vinos al depósito central. Estados: en_confeccion -> terminado -> procesado (RN-10).';
COMMENT ON COLUMN ingreso.cod_ingreso IS 'Código de ingreso.';
COMMENT ON COLUMN ingreso.fecha IS 'Fecha del ingreso.';
COMMENT ON COLUMN ingreso.estado IS 'Estado del documento. Solo pasa a procesado por sp_procesar_ingreso.';
COMMENT ON COLUMN ingreso.cod_transporte IS 'Transportista que efectuó el traslado.';
COMMENT ON COLUMN ingreso.cuit_bodega IS 'Bodega de origen.';

COMMENT ON TABLE renglon_ingreso IS 'Vinos y cantidades de un ingreso. Solo modificables en confección (RN-12).';
COMMENT ON COLUMN renglon_ingreso.cod_ingreso IS 'Ingreso.';
COMMENT ON COLUMN renglon_ingreso.cod_vino IS 'Vino.';
COMMENT ON COLUMN renglon_ingreso.cantidad IS 'Botellas (positiva).';

COMMENT ON TABLE transferencia IS 'Pedido de una sala al depósito central. Estados como el ingreso (RN-11).';
COMMENT ON COLUMN transferencia.nro_transferencia IS 'Número de solicitud.';
COMMENT ON COLUMN transferencia.id_sala IS 'Sala solicitante.';
COMMENT ON COLUMN transferencia.fecha_confeccion IS 'Fecha actual al crearla; no se modifica (RN-11, trigger).';
COMMENT ON COLUMN transferencia.estado IS 'Estado del documento. Solo pasa a procesado por sp_procesar_transferencia.';

COMMENT ON TABLE renglon_transferencia IS 'Vinos y cantidades de una transferencia. Solo modificables en confección (RN-12).';
COMMENT ON COLUMN renglon_transferencia.nro_transferencia IS 'Transferencia.';
COMMENT ON COLUMN renglon_transferencia.cod_vino IS 'Vino.';
COMMENT ON COLUMN renglon_transferencia.cantidad IS 'Botellas (positiva).';

COMMENT ON TABLE stock_sala IS 'Relación N:M sala-vino con el stock disponible. Lo modifican solo triggers y procedimientos.';
COMMENT ON COLUMN stock_sala.id_sala IS 'Sala.';
COMMENT ON COLUMN stock_sala.cod_vino IS 'Vino.';
COMMENT ON COLUMN stock_sala.cantidad IS 'Botellas disponibles; nunca negativo (RN-09).';

COMMENT ON TABLE stock_deposito IS 'Stock del depósito central (relación 1:1 con vino).';
COMMENT ON COLUMN stock_deposito.cod_vino IS 'Vino (PK y FK).';
COMMENT ON COLUMN stock_deposito.cantidad IS 'Botellas en el depósito; nunca negativo.';

COMMENT ON TABLE auditoria_precio IS 'Historial de cambios de precio. La completa el trigger trg_vino_auditoria_precio (RN-13).';
COMMENT ON COLUMN auditoria_precio.id_auditoria IS 'Identificador del registro.';
COMMENT ON COLUMN auditoria_precio.cod_vino IS 'Vino cuyo precio cambió.';
COMMENT ON COLUMN auditoria_precio.precio_anterior IS 'Precio antes del cambio.';
COMMENT ON COLUMN auditoria_precio.precio_nuevo IS 'Precio después del cambio.';
COMMENT ON COLUMN auditoria_precio.fecha_hora IS 'Momento del cambio.';
COMMENT ON COLUMN auditoria_precio.usuario IS 'Rol de base de datos que hizo el cambio (session_user).';
