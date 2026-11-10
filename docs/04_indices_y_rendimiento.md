# 4. Índices y rendimiento

Etapa 4. Índices: `db/migrations/008_indices.sql`. Medición: `db/bench/medir_indices.py`, que borra los índices, mide, los crea, vuelve a medir y escribe:

- [`informes/etapa4_indices.md`](informes/etapa4_indices.md): tabla comparativa antes/después, tamaños, índice descartado, casos en que no se usa un índice y costo de escritura.
- [`informes/etapa4_planes.md`](informes/etapa4_planes.md): planes completos de `EXPLAIN (ANALYZE, BUFFERS)`.

## 4.1 Método

1. Base cargada (150.000 comprobantes, 523.000 renglones), `ANALYZE`.
2. Solo índices de PK y UNIQUE. Cada consulta con `EXPLAIN (ANALYZE, BUFFERS)`: una ejecución de calentamiento y la mediana de 3 (paralelismo y JIT desactivados para comparar en igualdad de condiciones).
3. Se leyeron los planes: dónde hay `Seq Scan` sobre tablas grandes y cuántos buffers (páginas de 8 kB) se leen.
4. Se crearon los índices, `ANALYZE`, y se repitió la medición.

## 4.2 Los 5 índices y por qué

| Índice | Tipo pedido | Qué resolvió el plan |
| --- | --- | --- |
| `renglon_comprobante (cod_vino)` | sobre **clave foránea** | La PK `(nro_comprobante, cod_vino)` no sirve para buscar por vino (es la segunda columna). S2 y S12 preguntan "¿se vendió este vino?" miles de veces. |
| `comprobante (id_cliente)` | sobre **clave foránea** | PostgreSQL no indexa las FK. Borrar un cliente obliga a verificar que no tenga comprobantes: sin índice, un recorrido completo por cliente borrado (D4 pasó de ~4,3 s a ~17 ms). |
| `comprobante (id_sala, fecha) INCLUDE (total, id_cliente)` | **compuesto** + variante **INCLUDE** | "Ventas de una sala en un período" se resuelve con un `Index Only Scan`: no lee la tabla. |
| `transferencia (id_sala, fecha_confeccion) WHERE estado <> 'procesado'` | **parcial** | Indexa solo las ~150 pendientes de ~5.800. Diminuto (16 kB). |
| `comprobante USING brin (fecha)` | **BRIN** (otro tipo) | Las ventas se insertan en orden de fecha: el BRIN guarda mínimo y máximo por bloque y ocupa 24 kB contra ~1 MB de un B-tree. Sirve para rangos de fecha sobre toda la red (S8). |

## 4.3 Orden de columnas del índice compuesto

`(id_sala, fecha)` y no `(fecha, id_sala)`: en un B-tree las entradas se ordenan por la primera columna y, dentro de ella, por la segunda. Con `id_sala` primero, todas las ventas de la sala 1 en los últimos 90 días están **contiguas**. Con `fecha` primero, el índice recorre los 90 días de **todas** las salas y descarta las que no son la 1. Regla: **columnas de igualdad primero, de rango al final**. El índice `(fecha, id_sala)` se probó y se **descartó** (lee unas 6 veces más páginas; ver informe).

## 4.4 Cuándo el planificador no usa un índice

- **Baja selectividad**: con un índice sobre `vino(tipo)`, `WHERE tipo = 'tinto'` devuelve el 61 % de los vinos y el planificador elige `Seq Scan`: leer la tabla de corrido es más barato que saltar de índice a tabla para casi todas las filas.
- **Columna dentro de una función**: `WHERE EXTRACT(YEAR FROM fecha) = 2025` no puede usar el índice sobre `fecha` (el índice guarda `fecha`, no el año). Reescrita como rango (`fecha >= '2025-01-01' AND fecha < '2026-01-01'`) sí lo usa.
- **Estadísticas desactualizadas**: después de una carga masiva hay que correr `ANALYZE`, si no el planificador estima mal cuántas filas devuelve cada filtro.

## 4.5 Costo de escritura

Cada índice se actualiza en cada INSERT, UPDATE y DELETE de su tabla. El informe mide insertar todas las filas de `renglon_comprobante` y `comprobante` en una copia con solo la PK y con los índices: la escritura es más lenta (entre +33 % y +76 % en la medición) y los índices ocupan varios MB. Por eso no se indexan columnas "por las dudas": cada índice de la lista tiene una consulta que lo justifica.
