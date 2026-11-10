# Etapa 4 · Índices y rendimiento (resultados medidos)

Generado por `db/bench/medir_indices.py` sobre la base cargada con `db/seed/cargar_datos.py`.
Cada tiempo es la mediana de 3 ejecuciones de `EXPLAIN (ANALYZE, BUFFERS)` después de una de calentamiento
(si la de calentamiento tarda más de 5 s, se informa esa sola),
con paralelismo y JIT desactivados para que las mediciones sean comparables.
"Antes" = solo los índices de PRIMARY KEY y UNIQUE. "Después" = con `008_indices.sql`.

## Tabla comparativa

| Consulta | Antes (ms) | Recorrido antes | Después (ms) | Recorrido después | Mejora | Buffers antes → después |
| --- | ---: | --- | ---: | --- | ---: | --- |
| **S2** Vinos vendidos en todas las salas (doble NOT EXISTS) | 27.605,5 | Seq Scan vino<br>Seq Scan sala_venta<br>Seq Scan renglon_comprobante<br>Index Scan comprobante_pkey | 2.313,3 | Seq Scan vino<br>Seq Scan sala_venta<br>Bitmap Heap Scan renglon_comprobante<br>Bitmap Index Scan idx_renglon_comprobante_vino … | 11,9x | 8.289.198 → 3.518.615 |
| **S3** Ventas de una sala en los últimos 90 días (igualdad + rango) | 7,3 | Seq Scan comprobante | 0,1 | Index Only Scan idx_comprobante_sala_fecha | 53,6x | 1.408 → 6 |
| **S8** Monto por sala en el último trimestre (rango de fechas sobre toda la red) | 11,8 | Seq Scan comprobante | 3,8 | Bitmap Heap Scan comprobante<br>Bitmap Index Scan idx_comprobante_fecha_brin | 3,1x | 1.408 → 258 |
| **S12a** Clientes que compraron todos los vinos de una bodega | 125.672,6 | Seq Scan cliente<br>Seq Scan vino<br>Seq Scan bodega<br>Seq Scan comprobante … | 589,2 | Seq Scan cliente<br>Seq Scan vino<br>Seq Scan bodega<br>Bitmap Heap Scan comprobante … | 213,3x | 29.928.069 → 686.306 |
| **S5** Salas con menos transferencias pendientes | 0,3 | Seq Scan transferencia<br>Seq Scan sala_venta | 0,1 | Bitmap Heap Scan transferencia<br>Bitmap Index Scan idx_transferencia_pendientes<br>Seq Scan sala_venta | 2,6x | 33 → 4 |
| **D4** Borrar socios sin compras con alta de hace más de 5 años (chequeo de FK) (triggers de FK: 4285 → 7 ms) | 4.315,4 | Seq Scan comprobante<br>Seq Scan cliente | 17,4 | Seq Scan cliente<br>Index Scan idx_comprobante_cliente | 247,7x | 2.992 → 20.740 |

Crear los 5 índices sobre la base cargada tardó 0,4 s.

Nota sobre D4: en el "antes" los buffers del nodo raíz no incluyen las lecturas que hacen los triggers de la FK (recorren `comprobante` completa una vez por cada cliente borrado); por eso el tiempo es la medida que importa ahí.

## Tamaño de cada índice

| Índice | Tamaño |
| --- | ---: |
| `idx_comprobante_sala_fecha` | 5960 kB |
| `idx_renglon_comprobante_vino` | 3608 kB |
| `idx_comprobante_cliente` | 1408 kB |
| `idx_comprobante_fecha_brin` | 24 kB |
| `idx_transferencia_pendientes` | 16 kB |

Un B-tree común sobre `comprobante(fecha)` ocupa **1048 kB**; el BRIN equivalente ocupa lo que muestra la tabla. El BRIN sirve porque las ventas se insertan en orden de fecha (correlación física ≈ 1).

## Índice evaluado y descartado: orden de columnas invertido

Para la consulta S3 (`WHERE id_sala = 1 AND fecha >= CURRENT_DATE - 90`) se probó el índice `(fecha, id_sala)` en lugar de `(id_sala, fecha)`:

| Variante | Tiempo (ms) | Recorrido | Buffers |
| --- | ---: | --- | ---: |
| Sin índice | 7,29 | Seq Scan comprobante | 1.408 |
| `(fecha, id_sala)` descartado | 0,37 | Index Only Scan idx_tmp_fecha_sala | 35 |
| `(id_sala, fecha)` elegido | 0,14 | Index Only Scan idx_comprobante_sala_fecha | 6 |

Con `fecha` primero, el índice recorre los 90 días de **todas** las salas y descarta las que no son la 1: lee unas 40 veces más entradas. Con `id_sala` primero (igualdad) y `fecha` después (rango), las entradas buscadas están contiguas en el índice. Regla: columnas de igualdad primero, de rango al final.

## Casos en que el planificador NO usa un índice existente

1. `SELECT ... FROM vino WHERE tipo = 'tinto'` con un índice sobre `vino(tipo)`: el planificador eligió **Seq Scan vino**. El 61.2 % de los vinos son tintos: leer el índice y luego saltar a casi todas las páginas de la tabla es más caro que leer la tabla de corrido. Un índice sirve cuando el filtro es **selectivo** (devuelve pocas filas).
2. `... WHERE EXTRACT(YEAR FROM fecha) = 2025` con el índice BRIN sobre `fecha`: el plan usa **Seq Scan comprobante** (21,3 ms). El índice guarda valores de `fecha`, no de `EXTRACT(YEAR FROM fecha)`: si la columna está dentro de una función, el índice no sirve. Reescrita como rango (`fecha >= '2025-01-01' AND fecha < '2026-01-01'`) usa **Bitmap Heap Scan comprobante<br>Bitmap Index Scan idx_comprobante_fecha_brin** (8,0 ms).

Otra causa típica es tener estadísticas desactualizadas: después de la carga masiva hay que correr `ANALYZE`; si no, el planificador estima mal cuántas filas devuelve cada filtro.

## Costo de escritura

Tiempo de insertar todas las filas de la tabla en una copia (en una transacción), solo con la PK y con los índices de `008_indices.sql`:

| Tabla | Filas | Variante | Segundos | Tamaño de índices | Variante | Segundos | Tamaño de índices | Sobrecosto |
| --- | ---: | --- | ---: | ---: | --- | ---: | ---: | ---: |
| renglon_comprobante | 523.138 | PK | 0,79 | 15 MB | PK + idx(cod_vino) | 1,06 | 19 MB | +33 % |
| comprobante | 149.972 | PK | 0,47 | 15 MB | PK + 3 índices | 0,82 | 27 MB | +76 % |

Cada índice extra se actualiza en cada INSERT: la escritura se vuelve más lenta y la base más grande. Por eso no se indexan columnas "por las dudas".
