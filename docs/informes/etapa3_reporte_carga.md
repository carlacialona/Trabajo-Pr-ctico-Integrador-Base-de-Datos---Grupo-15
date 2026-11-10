# Reporte de la carga masiva (generado por `db/seed/cargar_datos.py`)

- Semilla: `2026` · Escala: `1.0` · Fecha de referencia: `2026-11-09`
- Método: `COPY` por tabla, en una sola transacción, con los triggers de usuario deshabilitados (FK y CHECK activos).

## Filas por tabla

| Tabla | Filas |
| --- | ---: |
| provincia | 1 |
| departamento | 18 |
| localidad | 35 |
| sala_venta | 40 |
| empleado | 150 |
| cepa | 12 |
| maridaje | 8 |
| bodega | 13 |
| transportista | 15 |
| transportista_localidad | 57 |
| finca | 30 |
| parcela | 619 |
| lote_uva | 2.850 |
| analisis_calidad | 4.858 |
| vino | 600 |
| composicion | 859 |
| vino_maridaje | 1.206 |
| cliente | 20.000 |
| distribuidor | 3.306 |
| exportador | 1.574 |
| permiso_exportacion | 4.280 |
| ingreso | 1.782 |
| renglon_ingreso | 7.585 |
| transferencia | 5.779 |
| renglon_transferencia | 23.586 |
| stock_deposito | 600 |
| stock_sala | 3.318 |
| comprobante | 149.972 |
| renglon_comprobante | 523.138 |
| auditoria_precio | 0 |

## Tiempos

| Paso | Segundos |
| --- | ---: |
| Generación en Python | 5.99 |
| COPY provincia (1 filas) | 0.01 |
| COPY departamento (18 filas) | 0.00 |
| COPY localidad (35 filas) | 0.00 |
| COPY sala_venta (40 filas) | 0.00 |
| COPY empleado (150 filas) | 0.00 |
| COPY cepa (12 filas) | 0.00 |
| COPY maridaje (8 filas) | 0.00 |
| COPY bodega (13 filas) | 0.00 |
| COPY transportista (15 filas) | 0.00 |
| COPY transportista_localidad (57 filas) | 0.00 |
| COPY finca (30 filas) | 0.00 |
| COPY parcela (619 filas) | 0.01 |
| COPY lote_uva (2.850 filas) | 0.04 |
| COPY analisis_calidad (4.858 filas) | 0.03 |
| COPY vino (600 filas) | 0.01 |
| COPY composicion (859 filas) | 0.01 |
| COPY vino_maridaje (1.206 filas) | 0.02 |
| COPY cliente (20.000 filas) | 0.19 |
| COPY distribuidor (3.306 filas) | 0.04 |
| COPY exportador (1.574 filas) | 0.01 |
| COPY permiso_exportacion (4.280 filas) | 0.03 |
| COPY ingreso (1.782 filas) | 0.02 |
| COPY renglon_ingreso (7.585 filas) | 0.07 |
| COPY transferencia (5.779 filas) | 0.03 |
| COPY renglon_transferencia (23.586 filas) | 0.23 |
| COPY stock_deposito (600 filas) | 0.01 |
| COPY stock_sala (3.318 filas) | 0.04 |
| COPY comprobante (149.972 filas) | 1.98 |
| COPY renglon_comprobante (523.138 filas) | 5.66 |
| Carga total (una transacción) | 8.48 |
| REFRESH de la vista materializada + ANALYZE | 0.40 |

## Consultas de control (todas deben dar 0)

| Control | Resultado |
| --- | ---: |
| Filas huérfanas: renglones de comprobante sin cabecera | 0 |
| Comprobantes sin renglones | 0 |
| Comprobantes cuyo total no coincide con la suma de sus renglones (RN-08) | 0 |
| Renglones cuyo subtotal no coincide con la fórmula (RN-08) | 0 |
| Renglones con descuento distinto al del tipo de cliente (RN-06) | 0 |
| Stock negativo en salas o depósito (RN-09) | 0 |
| Stock de sala distinto de transferido - vendido | 0 |
| Stock de depósito distinto de ingresado - transferido | 0 |
| Vinos cuya composición no suma 100 (RN-05) | 0 |
| Ventas anteriores al alta del cliente | 0 |
| Ventas de un vino antes de su primer ingreso al depósito | 0 |
| Lotes cuya fecha de cosecha no pertenece a su campaña | 0 |
| Subtipos que no coinciden con el tipo del cliente | 0 |

## Fila por fila frente a por lotes (5.000 renglones)

| Método | Segundos | Filas/s | Veces más rápido que fila por fila |
| --- | ---: | ---: | ---: |
| INSERT fila por fila (un COMMIT por fila) | 2.578 | 1.939 | 1.0x |
| executemany en una transacción | 0.141 | 35.534 | 18.3x |
| COPY (por lotes) | 0.026 | 194.638 | 100.4x |
