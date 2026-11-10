# Diccionario de datos

Generado automáticamente desde el catálogo de PostgreSQL por `db/scripts/generar_diccionario.py` (tipos, nulos, valores por defecto y restricciones reales; descripciones de `009_comentarios.sql`).

## Tipos enumerados

| Tipo | Valores |
| --- | --- |
| `dia_semana` | lunes, martes, miercoles, jueves, viernes, sabado, domingo |
| `estado_documento` | en_confeccion, terminado, procesado |
| `tipo_cepa` | tinta, blanca |
| `tipo_cliente` | socio, distribuidor, exportador |
| `tipo_documento` | DNI, CUIT, PASAPORTE |
| `tipo_vino` | tinto, blanco, rosado, espumante |

## Dominios

| Dominio | Tipo base | Restricción |
| --- | --- | --- |
| `cuit_dom` | `character(11)` | `CHECK ((VALUE ~ '^[0-9]{11}$'::text))` |
| `dinero` | `numeric(12,2)` | — (la positividad se controla con CHECK en cada columna) |
| `email_dom` | `character varying(120)` | `CHECK (((VALUE)::text ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'::text))` |

## Tablas

### `provincia`

Provincias argentinas.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_provincia` | `smallint` | no | `IDENTITY (ALWAYS)` | PK | Identificador subrogado. |
| `nombre` | `character varying(60)` | no |  | UNIQUE (nombre) | Nombre de la provincia (clave candidata). |

### `departamento`

Departamentos (división política dentro de una provincia). Tabla propia para evitar la dependencia transitiva finca -> departamento -> provincia.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_departamento` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Identificador subrogado. |
| `nombre` | `character varying(60)` | no |  | UNIQUE (nombre, id_provincia) | Nombre del departamento (único dentro de la provincia). |
| `id_provincia` | `smallint` | no |  | FK → provincia(id_provincia) ON DELETE RESTRICT<br>UNIQUE (nombre, id_provincia) | Provincia a la que pertenece. |

### `localidad`

Localidades. Cada una tiene un único encargado regional (RN-02).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_localidad` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Identificador subrogado. El código postal no sirve como clave porque varias localidades lo comparten. |
| `nombre` | `character varying(80)` | no |  | UNIQUE (nombre, id_departamento) | Nombre (único dentro del departamento). |
| `codigo_postal` | `character varying(8)` | no |  |  | Código postal. Puede repetirse entre localidades. |
| `id_departamento` | `integer` | no |  | FK → departamento(id_departamento) ON DELETE RESTRICT<br>UNIQUE (nombre, id_departamento) | Departamento al que pertenece (de ahí se obtiene la provincia). |
| `encargado_regional` | `character varying(80)` | no |  |  | Responsable comercial de todas las salas de la localidad. Depende de la localidad, no de la sala (RN-02). |

### `sala_venta`

Salas de venta de la red. Una sala está en una sola localidad.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_sala` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Identificador de la sala. |
| `calle` | `character varying(80)` | no |  |  | Calle del domicilio. |
| `numero` | `integer` | no |  |  | Número del domicilio (positivo). |
| `dia_cierre` | `dia_semana` | no |  |  | Día de cierre semanal. |
| `id_localidad` | `integer` | no |  | FK → localidad(id_localidad) ON DELETE RESTRICT | Localidad donde está la sala (RN-02). |

Restricciones CHECK:

- `ck_sala_numero`: `CHECK ((numero > 0))`

### `empleado`

Empleados. Cada uno trabaja en una sola sala (RN-03).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cuit` | `cuit_dom` (dominio sobre `character(11)`) | no |  | PK | CUIT del empleado (clave natural, 11 dígitos). |
| `nombre` | `character varying(100)` | no |  |  | Apellido y nombre. |
| `fecha_ingreso` | `date` | no |  |  | Fecha de ingreso laboral (base de la antigüedad). |
| `salario` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | Salario mensual (positivo). |
| `id_sala` | `integer` | no |  | FK → sala_venta(id_sala) ON DELETE RESTRICT | Sala donde trabaja. NOT NULL: RN-03. |

Restricciones CHECK:

- `ck_empleado_salario`: `CHECK (((salario)::numeric > (0)::numeric))`

### `finca`

Fincas donde se cultiva la uva.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_finca` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Identificador de la finca. |
| `nombre` | `character varying(80)` | no |  |  | Nombre de la finca. |
| `superficie_ha` | `numeric(10,2)` | no |  |  | Superficie total en hectáreas (positiva). |
| `id_departamento` | `integer` | no |  | FK → departamento(id_departamento) ON DELETE RESTRICT | Departamento donde se ubica. |

Restricciones CHECK:

- `ck_finca_superficie`: `CHECK ((superficie_ha > (0)::numeric))`

### `cepa`

Catálogo de variedades de uva.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_cepa` | `smallint` | no | `IDENTITY (ALWAYS)` | PK | Identificador de la cepa. |
| `nombre` | `character varying(40)` | no |  | UNIQUE (nombre) | Nombre de la variedad (único). |
| `tipo` | `tipo_cepa` | no |  |  | Tinta o blanca. |

### `parcela`

Parcelas de una finca. Entidad débil: se identifica por (finca, número).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_finca` | `integer` | no |  | PK<br>FK → finca(id_finca) ON DELETE CASCADE | Finca a la que pertenece (parte de la PK). |
| `nro_parcela` | `smallint` | no |  | PK | Número de parcela dentro de la finca (parte de la PK). |
| `superficie_ha` | `numeric(8,2)` | no |  |  | Superficie en hectáreas (positiva). |
| `anio_plantacion` | `smallint` | no |  |  | Año en que se plantó. |
| `id_cepa` | `smallint` | no |  | FK → cepa(id_cepa) ON DELETE RESTRICT | Única cepa plantada en la parcela (RN-04). |

Restricciones CHECK:

- `ck_parcela_anio`: `CHECK (((anio_plantacion >= 1900) AND (anio_plantacion <= 2100)))`
- `ck_parcela_nro`: `CHECK ((nro_parcela > 0))`
- `ck_parcela_superficie`: `CHECK ((superficie_ha > (0)::numeric))`

### `bodega`

Bodegas del grupo, que elaboran los vinos y reciben la uva.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cuit` | `cuit_dom` (dominio sobre `character(11)`) | no |  | PK | CUIT de la bodega (clave natural). |
| `razon_social` | `character varying(120)` | no |  | UNIQUE (razon_social) | Razón social (clave candidata). |
| `domicilio` | `character varying(150)` | no |  |  | Domicilio. |

### `lote_uva`

Cosecha de una parcela en una campaña. Una sola por parcela y campaña (RN-04).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `nro_lote` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Número de lote (PK elegida). |
| `id_finca` | `integer` | no |  | FK → parcela(id_finca, nro_parcela) ON DELETE RESTRICT<br>UNIQUE (id_finca, nro_parcela, campania) | Finca de la parcela cosechada. |
| `nro_parcela` | `smallint` | no |  | FK → parcela(id_finca, nro_parcela) ON DELETE RESTRICT<br>UNIQUE (id_finca, nro_parcela, campania) | Parcela cosechada. |
| `campania` | `smallint` | no |  | UNIQUE (id_finca, nro_parcela, campania) | Año de cosecha. (finca, parcela, campaña) es clave candidata: RN-04. |
| `fecha_cosecha` | `date` | no |  |  | Fecha de cosecha; su año debe coincidir con la campaña. |
| `kilos` | `numeric(12,2)` | no |  |  | Kilos cosechados (positivos). |
| `cuit_bodega` | `cuit_dom` (dominio sobre `character(11)`) | no |  | FK → bodega(cuit) ON DELETE RESTRICT ON UPDATE CASCADE | Bodega a la que se entregó la uva. |

Restricciones CHECK:

- `ck_lote_campania`: `CHECK (((campania >= 1990) AND (campania <= 2100)))`
- `ck_lote_fecha_campania`: `CHECK ((EXTRACT(year FROM fecha_cosecha) = (campania)::numeric))`
- `ck_lote_kilos`: `CHECK ((kilos > (0)::numeric))`

### `analisis_calidad`

Análisis de calidad de un lote (uno o más por lote).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_analisis` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Identificador del análisis. |
| `nro_lote` | `integer` | no |  | FK → lote_uva(nro_lote) ON DELETE CASCADE | Lote analizado. |
| `fecha` | `date` | no |  |  | Fecha del análisis. |
| `brix` | `numeric(4,1)` | no |  |  | Grado Brix (azúcar), entre 0 y 40. |
| `ph` | `numeric(3,2)` | no |  |  | pH, entre 2 y 5. |
| `acidez_total` | `numeric(4,2)` | no |  |  | Acidez total en g/L (positiva). |

Restricciones CHECK:

- `ck_analisis_acidez`: `CHECK ((acidez_total > (0)::numeric))`
- `ck_analisis_brix`: `CHECK (((brix >= (0)::numeric) AND (brix <= (40)::numeric)))`
- `ck_analisis_ph`: `CHECK (((ph >= (2)::numeric) AND (ph <= (5)::numeric)))`

### `vino`

Vinos elaborados. Se distinguen por nombre, añada y presentación.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_vino` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Código del vino (subrogado). |
| `nombre` | `character varying(80)` | no |  | UNIQUE (nombre, anada, volumen_ml) | Nombre comercial. (nombre, añada, volumen) es clave candidata. |
| `tipo` | `tipo_vino` | no |  |  | Tinto, blanco, rosado o espumante. |
| `anada` | `smallint` | no |  | UNIQUE (nombre, anada, volumen_ml) | Año de la cosecha con que se elaboró. |
| `volumen_ml` | `smallint` | no |  | UNIQUE (nombre, anada, volumen_ml) | Presentación en ml: 187, 375, 750, 1500 o 3000. |
| `graduacion` | `numeric(4,2)` | no |  |  | Graduación alcohólica, entre 5 y 20 (RN-15). |
| `precio` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | Precio de venta, único para toda la red y mayor que 0 (RN-01). Sus cambios se auditan (RN-13). |
| `cuit_bodega` | `cuit_dom` (dominio sobre `character(11)`) | no |  | FK → bodega(cuit) ON DELETE RESTRICT ON UPDATE CASCADE | Bodega que lo elabora. |

Restricciones CHECK:

- `ck_vino_anada`: `CHECK (((anada >= 1900) AND (anada <= 2100)))`
- `ck_vino_graduacion`: `CHECK (((graduacion >= (5)::numeric) AND (graduacion <= (20)::numeric)))`
- `ck_vino_precio`: `CHECK (((precio)::numeric > (0)::numeric))`
- `ck_vino_volumen`: `CHECK ((volumen_ml = ANY (ARRAY[187, 375, 750, 1500, 3000])))`

### `composicion`

Relación N:M vino-cepa con el porcentaje de corte. Los porcentajes de un vino suman 100 (RN-05).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE CASCADE | Vino. |
| `id_cepa` | `smallint` | no |  | PK<br>FK → cepa(id_cepa) ON DELETE RESTRICT | Cepa que interviene en el corte. |
| `porcentaje` | `numeric(5,2)` | no |  |  | Porcentaje de esa cepa en el vino (mayor que 0, hasta 100). |

Restricciones CHECK:

- `ck_composicion_porcentaje`: `CHECK (((porcentaje > (0)::numeric) AND (porcentaje <= (100)::numeric)))`

### `maridaje`

Catálogo de maridajes recomendados.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_maridaje` | `smallint` | no | `IDENTITY (ALWAYS)` | PK | Identificador del maridaje. |
| `nombre` | `character varying(60)` | no |  | UNIQUE (nombre) | Nombre (único), por ejemplo "Carnes rojas". |
| `temperatura_servicio` | `numeric(4,1)` | no |  |  | Temperatura de servicio sugerida en °C. |

Restricciones CHECK:

- `ck_maridaje_temperatura`: `CHECK (((temperatura_servicio >= (0)::numeric) AND (temperatura_servicio <= (25)::numeric)))`

### `vino_maridaje`

Relación N:M entre vinos y maridajes recomendados.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE CASCADE | Vino. |
| `id_maridaje` | `smallint` | no |  | PK<br>FK → maridaje(id_maridaje) ON DELETE RESTRICT | Maridaje recomendado. |

### `cliente`

Supertipo de la jerarquía de clientes (socio, distribuidor, exportador).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_cliente` | `integer` | no | `IDENTITY (ALWAYS)` | PK<br>UNIQUE (id_cliente, tipo) | Identificador subrogado. |
| `tipo` | `tipo_cliente` | no |  | UNIQUE (id_cliente, tipo) | Discriminador del subtipo. |
| `nombre` | `character varying(120)` | no |  |  | Apellido y nombre (persona) o razón social (empresa). |
| `tipo_doc` | `tipo_documento` | no |  | UNIQUE (tipo_doc, nro_doc) | Tipo de documento. (tipo_doc, nro_doc) es clave candidata. |
| `nro_doc` | `character varying(20)` | no |  | UNIQUE (tipo_doc, nro_doc) | Número de documento. |
| `direccion` | `character varying(150)` | no |  |  | Dirección. |
| `id_localidad` | `integer` | no |  | FK → localidad(id_localidad) ON DELETE RESTRICT | Localidad del domicilio. |
| `fecha_alta` | `date` | no | `CURRENT_DATE` |  | Fecha de alta (por defecto, hoy). |
| `descuento` | `numeric(5,2)` | no |  |  | Porcentaje de descuento vigente. Lo inicializa un trigger según el tipo (RN-06); se almacena porque puede ajustarse (consulta U6). |

Restricciones CHECK:

- `ck_cliente_descuento`: `CHECK (((descuento >= (0)::numeric) AND (descuento <= (50)::numeric)))`

### `distribuidor`

Subtipo distribuidor (20 % de descuento base).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_cliente` | `integer` | no |  | PK<br>FK → cliente(id_cliente, tipo) ON DELETE CASCADE | Cliente (PK y FK al supertipo). |
| `tipo` | `tipo_cliente` | no | `'distribuidor'::tipo_cliente` | FK → cliente(id_cliente, tipo) ON DELETE CASCADE | Siempre "distribuidor": junto con la FK compuesta garantiza que el cliente sea de este tipo. |
| `zona_cobertura` | `character varying(100)` | no |  |  | Zona de cobertura. |
| `nro_habilitacion` | `character varying(20)` | no |  | UNIQUE (nro_habilitacion) | Número de habilitación (único). |

Restricciones CHECK:

- `ck_distribuidor_tipo`: `CHECK ((tipo = 'distribuidor'::tipo_cliente))`

### `exportador`

Subtipo exportador (30 % de descuento base).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_cliente` | `integer` | no |  | PK<br>FK → cliente(id_cliente, tipo) ON DELETE CASCADE | Cliente (PK y FK al supertipo). |
| `tipo` | `tipo_cliente` | no | `'exportador'::tipo_cliente` | FK → cliente(id_cliente, tipo) ON DELETE CASCADE | Siempre "exportador". |
| `pais_destino` | `character varying(60)` | no |  |  | País de destino principal. |

Restricciones CHECK:

- `ck_exportador_tipo`: `CHECK ((tipo = 'exportador'::tipo_cliente))`

### `permiso_exportacion`

Permisos de exportación. Varios por exportador (RN-07).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_permiso` | `character varying(20)` | no |  | PK | Código del permiso. |
| `id_cliente` | `integer` | no |  | FK → exportador(id_cliente) ON DELETE CASCADE | Exportador titular (FK a exportador, no a cliente). |
| `fecha_emision` | `date` | no |  |  | Fecha de emisión. |
| `fecha_vencimiento` | `date` | no |  |  | Fecha de vencimiento, posterior a la emisión (RN-07). |

Restricciones CHECK:

- `ck_permiso_fechas`: `CHECK ((fecha_vencimiento > fecha_emision))`

### `comprobante`

Cabecera de una venta. Los importes son derivados y los calcula un trigger (RN-08).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `nro_comprobante` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Número de comprobante. |
| `fecha` | `date` | no | `CURRENT_DATE` |  | Fecha de la venta (por defecto, hoy). |
| `id_cliente` | `integer` | no |  | FK → cliente(id_cliente) ON DELETE RESTRICT | Cliente que compra. |
| `id_sala` | `integer` | no |  | FK → sala_venta(id_sala) ON DELETE RESTRICT | Sala donde se realizó la venta. |
| `subtotal` | `dinero` (dominio sobre `numeric(12,2)`) | no | `0` |  | Suma de cantidad x precio de los renglones (derivado, almacenado). |
| `descuento` | `dinero` (dominio sobre `numeric(12,2)`) | no | `0` |  | Importe descontado = subtotal - total (derivado, almacenado). |
| `total` | `dinero` (dominio sobre `numeric(12,2)`) | no | `0` |  | Suma de los subtotales de los renglones con descuento (derivado, almacenado, RN-08). |

Restricciones CHECK:

- `ck_comprobante_descuento`: `CHECK ((((descuento)::numeric >= (0)::numeric) AND ((descuento)::numeric <= (subtotal)::numeric)))`
- `ck_comprobante_subtotal`: `CHECK (((subtotal)::numeric >= (0)::numeric))`
- `ck_comprobante_total`: `CHECK (((total)::numeric = ((subtotal)::numeric - (descuento)::numeric)))`

### `renglon_comprobante`

Relación N:M comprobante-vino con los datos de la línea de venta.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `nro_comprobante` | `integer` | no |  | PK<br>FK → comprobante(nro_comprobante) ON DELETE CASCADE | Comprobante. |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE RESTRICT | Vino vendido. Un vino aparece una sola vez por comprobante (PK). |
| `cantidad` | `integer` | no |  |  | Botellas vendidas (positiva). |
| `precio_unitario` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | Precio del vino AL MOMENTO de la venta (lo completa el trigger). No es redundante con vino.precio. |
| `porcentaje_descuento` | `numeric(5,2)` | no |  |  | Descuento aplicado, el del cliente al momento de la venta. |
| `subtotal` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | cantidad x precio x (1 - descuento/100), redondeado a centavos. |

Restricciones CHECK:

- `ck_renglon_comp_cantidad`: `CHECK ((cantidad > 0))`
- `ck_renglon_comp_descuento`: `CHECK (((porcentaje_descuento >= (0)::numeric) AND (porcentaje_descuento <= (100)::numeric)))`
- `ck_renglon_comp_precio`: `CHECK (((precio_unitario)::numeric > (0)::numeric))`
- `ck_renglon_comp_subtotal`: `CHECK (((subtotal)::numeric >= (0)::numeric))`

### `transportista`

Empresas de transporte que trasladan los ingresos.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_transporte` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Código del transportista. |
| `razon_social` | `character varying(120)` | no |  |  | Razón social. |
| `cuit` | `cuit_dom` (dominio sobre `character(11)`) | no |  | UNIQUE (cuit) | CUIT (clave candidata). |
| `email` | `email_dom` (dominio sobre `character varying(120)`) | no |  |  | Correo electrónico. |
| `telefono` | `character varying(30)` | no |  |  | Teléfono. |
| `domicilio` | `character varying(150)` | no |  |  | Domicilio. |

### `transportista_localidad`

Relación N:M: localidades que alcanza el servicio de cada transportista.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_transporte` | `integer` | no |  | PK<br>FK → transportista(cod_transporte) ON DELETE CASCADE | Transportista. |
| `id_localidad` | `integer` | no |  | PK<br>FK → localidad(id_localidad) ON DELETE CASCADE | Localidad cubierta. |

### `ingreso`

Ingreso de vinos al depósito central. Estados: en_confeccion -> terminado -> procesado (RN-10).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_ingreso` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Código de ingreso. |
| `fecha` | `date` | no | `CURRENT_DATE` |  | Fecha del ingreso. |
| `estado` | `estado_documento` | no | `'en_confeccion'::estado_documento` |  | Estado del documento. Solo pasa a procesado por sp_procesar_ingreso. |
| `cod_transporte` | `integer` | no |  | FK → transportista(cod_transporte) ON DELETE RESTRICT | Transportista que efectuó el traslado. |
| `cuit_bodega` | `cuit_dom` (dominio sobre `character(11)`) | no |  | FK → bodega(cuit) ON DELETE RESTRICT ON UPDATE CASCADE | Bodega de origen. |

### `renglon_ingreso`

Vinos y cantidades de un ingreso. Solo modificables en confección (RN-12).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_ingreso` | `integer` | no |  | PK<br>FK → ingreso(cod_ingreso) ON DELETE CASCADE | Ingreso. |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE RESTRICT | Vino. |
| `cantidad` | `integer` | no |  |  | Botellas (positiva). |

Restricciones CHECK:

- `ck_renglon_ingreso_cantidad`: `CHECK ((cantidad > 0))`

### `transferencia`

Pedido de una sala al depósito central. Estados como el ingreso (RN-11).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `nro_transferencia` | `integer` | no | `IDENTITY (ALWAYS)` | PK | Número de solicitud. |
| `id_sala` | `integer` | no |  | FK → sala_venta(id_sala) ON DELETE RESTRICT | Sala solicitante. |
| `fecha_confeccion` | `date` | no | `CURRENT_DATE` |  | Fecha actual al crearla; no se modifica (RN-11, trigger). |
| `estado` | `estado_documento` | no | `'en_confeccion'::estado_documento` |  | Estado del documento. Solo pasa a procesado por sp_procesar_transferencia. |

### `renglon_transferencia`

Vinos y cantidades de una transferencia. Solo modificables en confección (RN-12).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `nro_transferencia` | `integer` | no |  | PK<br>FK → transferencia(nro_transferencia) ON DELETE CASCADE | Transferencia. |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE RESTRICT | Vino. |
| `cantidad` | `integer` | no |  |  | Botellas (positiva). |

Restricciones CHECK:

- `ck_renglon_transf_cantidad`: `CHECK ((cantidad > 0))`

### `stock_sala`

Relación N:M sala-vino con el stock disponible. Lo modifican solo triggers y procedimientos.

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_sala` | `integer` | no |  | PK<br>FK → sala_venta(id_sala) ON DELETE RESTRICT | Sala. |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE CASCADE | Vino. |
| `cantidad` | `integer` | no | `0` |  | Botellas disponibles; nunca negativo (RN-09). |

Restricciones CHECK:

- `ck_stock_sala_cantidad`: `CHECK ((cantidad >= 0))`

### `stock_deposito`

Stock del depósito central (relación 1:1 con vino).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `cod_vino` | `integer` | no |  | PK<br>FK → vino(cod_vino) ON DELETE CASCADE | Vino (PK y FK). |
| `cantidad` | `integer` | no | `0` |  | Botellas en el depósito; nunca negativo. |

Restricciones CHECK:

- `ck_stock_deposito_cantidad`: `CHECK ((cantidad >= 0))`

### `auditoria_precio`

Historial de cambios de precio. La completa el trigger trg_vino_auditoria_precio (RN-13).

| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |
| --- | --- | :-: | --- | --- | --- |
| `id_auditoria` | `bigint` | no | `IDENTITY (ALWAYS)` | PK | Identificador del registro. |
| `cod_vino` | `integer` | no |  | FK → vino(cod_vino) ON DELETE RESTRICT | Vino cuyo precio cambió. |
| `precio_anterior` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | Precio antes del cambio. |
| `precio_nuevo` | `dinero` (dominio sobre `numeric(12,2)`) | no |  |  | Precio después del cambio. |
| `fecha_hora` | `timestamp with time zone` | no | `now()` |  | Momento del cambio. |
| `usuario` | `character varying(63)` | no | `SESSION_USER` |  | Rol de base de datos que hizo el cambio (session_user). |

Restricciones CHECK:

- `ck_auditoria_precios`: `CHECK ((((precio_anterior)::numeric > (0)::numeric) AND ((precio_nuevo)::numeric > (0)::numeric)))`
