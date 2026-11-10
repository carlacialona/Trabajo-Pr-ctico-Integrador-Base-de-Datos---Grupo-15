# Etapa 4 · Planes de ejecución completos

Salida de `EXPLAIN (ANALYZE, BUFFERS)` antes y después de crear los índices.

## S2. Vinos vendidos en todas las salas (doble NOT EXISTS)

```sql
SELECT v.cod_vino, v.nombre FROM vino v
         WHERE NOT EXISTS (SELECT 1 FROM sala_venta s
                 WHERE NOT EXISTS (SELECT 1 FROM comprobante c
                         JOIN renglon_comprobante r USING (nro_comprobante)
                        WHERE c.id_sala = s.id_sala AND r.cod_vino = v.cod_vino))
```

### Antes

```
Nested Loop Anti Join  (cost=0.00..7690668.51 rows=300 width=35) (actual time=526.283..27605.379 rows=43 loops=1)
  Join Filter: (NOT (SubPlan 1))
  Rows Removed by Join Filter: 1760
  Buffers: shared hit=8289198
  ->  Seq Scan on vino v  (cost=0.00..15.00 rows=600 width=35) (actual time=0.005..0.770 rows=600 loops=1)
        Buffers: shared hit=9
  ->  Materialize  (cost=0.00..1.60 rows=40 width=4) (actual time=0.001..0.003 rows=4 loops=600)
        Buffers: shared hit=1
        ->  Seq Scan on sala_venta s  (cost=0.00..1.40 rows=40 width=4) (actual time=0.003..0.051 rows=40 loops=1)
              Buffers: shared hit=1
  SubPlan 1
    ->  Nested Loop  (cost=0.42..15877.23 rows=26 width=0) (actual time=11.909..11.909 rows=1 loops=2317)
          Buffers: shared hit=8289188
          ->  Seq Scan on renglon_comprobante r  (cost=0.00..10699.23 rows=1050 width=4) (actual time=7.622..11.428 rows=347 loops=2317)
                Filter: (cod_vino = v.cod_vino)
                Rows Removed by Filter: 275291
                Buffers: shared hit=5070572
          ->  Index Scan using comprobante_pkey on comprobante c  (cost=0.42..4.93 rows=1 width=4) (actual time=0.001..0.001 rows=0 loops=804654)
                Index Cond: (nro_comprobante = r.nro_comprobante)
                Filter: (id_sala = s.id_sala)
                Rows Removed by Filter: 1
                Buffers: shared hit=3218616
Planning:
  Buffers: shared hit=123
Planning Time: 0.533 ms
Execution Time: 27605.467 ms
```

### Después

```
Nested Loop Anti Join  (cost=0.00..3792833.30 rows=300 width=35) (actual time=15.704..2386.457 rows=43 loops=1)
  Join Filter: (NOT (SubPlan 1))
  Rows Removed by Join Filter: 1760
  Buffers: shared hit=3518615
  ->  Seq Scan on vino v  (cost=0.00..15.00 rows=600 width=35) (actual time=0.004..0.304 rows=600 loops=1)
        Buffers: shared hit=9
  ->  Materialize  (cost=0.00..1.60 rows=40 width=4) (actual time=0.000..0.001 rows=4 loops=600)
        Buffers: shared hit=1
        ->  Seq Scan on sala_venta s  (cost=0.00..1.40 rows=40 width=4) (actual time=0.004..0.023 rows=40 loops=1)
              Buffers: shared hit=1
  SubPlan 1
    ->  Nested Loop  (cost=12.79..7515.37 rows=26 width=0) (actual time=1.028..1.028 rows=1 loops=2317)
          Buffers: shared hit=3518605
          ->  Bitmap Heap Scan on renglon_comprobante r  (cost=12.37..2395.93 rows=1026 width=4) (actual time=0.439..0.571 rows=347 loops=2317)
                Recheck Cond: (cod_vino = v.cod_vino)
                Heap Blocks: exact=279094
                Buffers: shared hit=299989
                ->  Bitmap Index Scan on idx_renglon_comprobante_vino  (cost=0.00..12.12 rows=1026 width=0) (actual time=0.223..0.223 rows=7193 loops=2317)
                      Index Cond: (cod_vino = v.cod_vino)
                      Buffers: shared hit=20895
          ->  Index Scan using comprobante_pkey on comprobante c  (cost=0.42..4.99 rows=1 width=4) (actual time=0.001..0.001 rows=0 loops=804654)
                Index Cond: (nro_comprobante = r.nro_comprobante)
                Filter: (id_sala = s.id_sala)
                Rows Removed by Filter: 1
                Buffers: shared hit=3218616
Planning:
  Buffers: shared hit=34
Planning Time: 0.359 ms
Execution Time: 2386.536 ms
```

## S3. Ventas de una sala en los últimos 90 días (igualdad + rango)

```sql
SELECT count(*), SUM(total), count(DISTINCT id_cliente) FROM comprobante
         WHERE id_sala = 1 AND fecha >= CURRENT_DATE - 90
```

### Antes

```
Aggregate  (cost=4419.67..4419.68 rows=1 width=48) (actual time=6.770..6.772 rows=1 loops=1)
  Buffers: shared hit=1408
  ->  Sort  (cost=4417.21..4417.82 rows=246 width=12) (actual time=6.721..6.732 rows=235 loops=1)
        Sort Key: id_cliente
        Sort Method: quicksort  Memory: 34kB
        Buffers: shared hit=1408
        ->  Seq Scan on comprobante  (cost=0.00..4407.44 rows=246 width=12) (actual time=6.359..6.672 rows=235 loops=1)
              Filter: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 90)))
              Rows Removed by Filter: 149737
              Buffers: shared hit=1408
Planning Time: 0.082 ms
Execution Time: 7.621 ms
```

### Después

```
Aggregate  (cost=76.40..76.41 rows=1 width=48) (actual time=0.106..0.106 rows=1 loops=1)
  Buffers: shared hit=6
  ->  Sort  (cost=74.09..74.66 rows=231 width=12) (actual time=0.062..0.072 rows=235 loops=1)
        Sort Key: id_cliente
        Sort Method: quicksort  Memory: 34kB
        Buffers: shared hit=6
        ->  Index Only Scan using idx_comprobante_sala_fecha on comprobante  (cost=0.42..65.02 rows=231 width=12) (actual time=0.008..0.027 rows=235 loops=1)
              Index Cond: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 90)))
              Heap Fetches: 3
              Buffers: shared hit=6
Planning:
  Buffers: shared hit=1
Planning Time: 0.037 ms
Execution Time: 0.116 ms
```

## S8. Monto por sala en el último trimestre (rango de fechas sobre toda la red)

```sql
SELECT id_sala, SUM(total) FROM comprobante
         WHERE fecha >= CURRENT_DATE - INTERVAL '3 months'
         GROUP BY id_sala ORDER BY 2 DESC
```

### Antes

```
Sort  (cost=4067.09..4067.19 rows=40 width=36) (actual time=11.652..11.655 rows=40 loops=1)
  Sort Key: (sum((total)::numeric)) DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=1408
  ->  HashAggregate  (cost=4065.53..4066.03 rows=40 width=36) (actual time=11.631..11.639 rows=40 loops=1)
        Group Key: id_sala
        Batches: 1  Memory Usage: 32kB
        Buffers: shared hit=1408
        ->  Seq Scan on comprobante  (cost=0.00..4032.51 rows=6604 width=12) (actual time=0.717..10.419 rows=6367 loops=1)
              Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
              Rows Removed by Filter: 143605
              Buffers: shared hit=1408
Planning Time: 0.067 ms
Execution Time: 11.690 ms
```

### Después

```
Sort  (cost=1692.81..1692.91 rows=40 width=36) (actual time=5.083..5.086 rows=40 loops=1)
  Sort Key: (sum((total)::numeric)) DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=258
  ->  HashAggregate  (cost=1691.25..1691.75 rows=40 width=36) (actual time=5.059..5.068 rows=40 loops=1)
        Group Key: id_sala
        Batches: 1  Memory Usage: 32kB
        Buffers: shared hit=258
        ->  Bitmap Heap Scan on comprobante  (cost=13.59..1660.19 rows=6213 width=12) (actual time=0.937..2.487 rows=6367 loops=1)
              Recheck Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
              Rows Removed by Index Recheck: 15320
              Heap Blocks: lossy=256
              Buffers: shared hit=258
              ->  Bitmap Index Scan on idx_comprobante_fecha_brin  (cost=0.00..12.04 rows=13634 width=0) (actual time=0.012..0.013 rows=2560 loops=1)
                    Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                    Buffers: shared hit=2
Planning:
  Buffers: shared hit=1
Planning Time: 0.329 ms
Execution Time: 5.119 ms
```

## S12a. Clientes que compraron todos los vinos de una bodega

```sql
SELECT cl.id_cliente FROM cliente cl
         WHERE NOT EXISTS (SELECT 1 FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega
                 WHERE b.razon_social = 'Bodega Boutique del Atuel SA'
                   AND NOT EXISTS (SELECT 1 FROM comprobante c
                         JOIN renglon_comprobante r USING (nro_comprobante)
                        WHERE c.id_cliente = cl.id_cliente AND r.cod_vino = v.cod_vino))
```

### Antes

```
Nested Loop Anti Join  (cost=1.18..1599639522.44 rows=10000 width=4) (actual time=4906.014..125672.519 rows=32 loops=1)
  Join Filter: (NOT (SubPlan 1))
  Rows Removed by Join Filter: 1435
  Buffers: shared hit=29928069
  ->  Seq Scan on cliente cl  (cost=0.00..478.00 rows=20000 width=4) (actual time=0.003..17.347 rows=20000 loops=1)
        Buffers: shared hit=278
  ->  Materialize  (cost=1.18..18.49 rows=46 width=4) (actual time=0.000..0.001 rows=1 loops=20000)
        Buffers: shared hit=10
        ->  Hash Join  (cost=1.18..18.26 rows=46 width=4) (actual time=0.016..0.131 rows=3 loops=1)
              Hash Cond: ((v.cuit_bodega)::bpchar = (b.cuit)::bpchar)
              Buffers: shared hit=10
              ->  Seq Scan on vino v  (cost=0.00..15.00 rows=600 width=16) (actual time=0.003..0.056 rows=600 loops=1)
                    Buffers: shared hit=9
              ->  Hash  (cost=1.16..1.16 rows=1 width=12) (actual time=0.007..0.009 rows=1 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    Buffers: shared hit=1
                    ->  Seq Scan on bodega b  (cost=0.00..1.16 rows=1 width=12) (actual time=0.004..0.004 rows=1 loops=1)
                          Filter: ((razon_social)::text = 'Bodega Boutique del Atuel SA'::text)
                          Rows Removed by Filter: 12
                          Buffers: shared hit=1
  SubPlan 1
    ->  Nested Loop  (cost=0.42..3335.53 rows=1 width=0) (actual time=5.866..5.866 rows=0 loops=21403)
          Buffers: shared hit=29927781
          ->  Seq Scan on comprobante c  (cost=0.00..3282.65 rows=11 width=4) (actual time=2.647..5.819 rows=8 loops=21403)
                Filter: (id_cliente = cl.id_cliente)
                Rows Removed by Filter: 146823
                Buffers: shared hit=29444747
          ->  Index Only Scan using renglon_comprobante_pkey on renglon_comprobante r  (cost=0.42..4.81 rows=1 width=4) (actual time=0.005..0.005 rows=0 loops=161011)
                Index Cond: ((nro_comprobante = c.nro_comprobante) AND (cod_vino = v.cod_vino))
                Heap Fetches: 0
                Buffers: shared hit=483034
Planning:
  Buffers: shared hit=155
Planning Time: 0.565 ms
Execution Time: 125672.582 ms
```

### Después

```
Nested Loop Anti Join  (cost=1.18..43361393.65 rows=10000 width=4) (actual time=19.524..681.780 rows=32 loops=1)
  Join Filter: (NOT (SubPlan 1))
  Rows Removed by Join Filter: 1435
  Buffers: shared hit=686306
  ->  Seq Scan on cliente cl  (cost=0.00..478.00 rows=20000 width=4) (actual time=0.004..3.382 rows=20000 loops=1)
        Buffers: shared hit=278
  ->  Materialize  (cost=1.18..18.49 rows=46 width=4) (actual time=0.000..0.000 rows=1 loops=20000)
        Buffers: shared hit=10
        ->  Hash Join  (cost=1.18..18.26 rows=46 width=4) (actual time=0.017..0.142 rows=3 loops=1)
              Hash Cond: ((v.cuit_bodega)::bpchar = (b.cuit)::bpchar)
              Buffers: shared hit=10
              ->  Seq Scan on vino v  (cost=0.00..15.00 rows=600 width=16) (actual time=0.002..0.051 rows=600 loops=1)
                    Buffers: shared hit=9
              ->  Hash  (cost=1.16..1.16 rows=1 width=12) (actual time=0.009..0.011 rows=1 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 9kB
                    Buffers: shared hit=1
                    ->  Seq Scan on bodega b  (cost=0.00..1.16 rows=1 width=12) (actual time=0.005..0.006 rows=1 loops=1)
                          Filter: ((razon_social)::text = 'Bodega Boutique del Atuel SA'::text)
                          Rows Removed by Filter: 12
                          Buffers: shared hit=1
  SubPlan 1
    ->  Nested Loop  (cost=4.80..90.40 rows=1 width=0) (actual time=0.031..0.031 rows=0 loops=21403)
          Buffers: shared hit=686018
          ->  Bitmap Heap Scan on comprobante c  (cost=4.37..41.97 rows=10 width=4) (actual time=0.003..0.010 rows=8 loops=21403)
                Recheck Cond: (id_cliente = cl.id_cliente)
                Heap Blocks: exact=160178
                Buffers: shared hit=202984
                ->  Bitmap Index Scan on idx_comprobante_cliente  (cost=0.00..4.37 rows=10 width=0) (actual time=0.001..0.001 rows=8 loops=21403)
                      Index Cond: (id_cliente = cl.id_cliente)
                      Buffers: shared hit=42806
          ->  Index Only Scan using renglon_comprobante_pkey on renglon_comprobante r  (cost=0.42..4.84 rows=1 width=4) (actual time=0.002..0.002 rows=0 loops=161011)
                Index Cond: ((nro_comprobante = c.nro_comprobante) AND (cod_vino = v.cod_vino))
                Heap Fetches: 0
                Buffers: shared hit=483034
Planning:
  Buffers: shared hit=38
Planning Time: 0.556 ms
Execution Time: 681.860 ms
```

## S5. Salas con menos transferencias pendientes

```sql
WITH p AS (SELECT s.id_sala, count(t.nro_transferencia) AS n FROM sala_venta s
                    LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
                    GROUP BY s.id_sala)
        SELECT * FROM p WHERE n = (SELECT min(n) FROM p)
```

### Antes

```
CTE Scan on p  (cost=108.64..109.54 rows=1 width=12) (actual time=0.269..0.271 rows=1 loops=1)
  Filter: (n = $1)
  Rows Removed by Filter: 39
  Buffers: shared hit=33
  CTE p
    ->  HashAggregate  (cost=107.33..107.73 rows=40 width=12) (actual time=0.253..0.257 rows=40 loops=1)
          Group Key: s.id_sala
          Batches: 1  Memory Usage: 24kB
          Buffers: shared hit=33
          ->  Hash Right Join  (cost=1.90..106.58 rows=150 width=8) (actual time=0.203..0.233 rows=151 loops=1)
                Hash Cond: (t.id_sala = s.id_sala)
                Buffers: shared hit=33
                ->  Seq Scan on transferencia t  (cost=0.00..104.24 rows=150 width=8) (actual time=0.189..0.200 rows=150 loops=1)
                      Filter: (estado <> 'procesado'::estado_documento)
                      Rows Removed by Filter: 5629
                      Buffers: shared hit=32
                ->  Hash  (cost=1.40..1.40 rows=40 width=4) (actual time=0.011..0.011 rows=40 loops=1)
                      Buckets: 1024  Batches: 1  Memory Usage: 10kB
                      Buffers: shared hit=1
                      ->  Seq Scan on sala_venta s  (cost=0.00..1.40 rows=40 width=4) (actual time=0.003..0.006 rows=40 loops=1)
                            Buffers: shared hit=1
  InitPlan 2 (returns $1)
    ->  Aggregate  (cost=0.90..0.91 rows=1 width=8) (actual time=0.014..0.014 rows=1 loops=1)
          ->  CTE Scan on p p_1  (cost=0.00..0.80 rows=40 width=8) (actual time=0.000..0.010 rows=40 loops=1)
Planning:
  Buffers: shared hit=4
Planning Time: 0.105 ms
Execution Time: 0.299 ms
```

### Después

```
CTE Scan on p  (cost=47.21..48.11 rows=1 width=12) (actual time=0.088..0.091 rows=1 loops=1)
  Filter: (n = $1)
  Rows Removed by Filter: 39
  Buffers: shared hit=4
  CTE p
    ->  HashAggregate  (cost=45.90..46.30 rows=40 width=12) (actual time=0.072..0.076 rows=40 loops=1)
          Group Key: s.id_sala
          Batches: 1  Memory Usage: 24kB
          Buffers: shared hit=4
          ->  Hash Right Join  (cost=10.83..45.15 rows=150 width=8) (actual time=0.022..0.052 rows=151 loops=1)
                Hash Cond: (t.id_sala = s.id_sala)
                Buffers: shared hit=4
                ->  Bitmap Heap Scan on transferencia t  (cost=8.93..42.81 rows=150 width=8) (actual time=0.009..0.018 rows=150 loops=1)
                      Recheck Cond: (estado <> 'procesado'::estado_documento)
                      Heap Blocks: exact=2
                      Buffers: shared hit=3
                      ->  Bitmap Index Scan on idx_transferencia_pendientes  (cost=0.00..8.89 rows=150 width=0) (actual time=0.005..0.005 rows=150 loops=1)
                            Buffers: shared hit=1
                ->  Hash  (cost=1.40..1.40 rows=40 width=4) (actual time=0.010..0.010 rows=40 loops=1)
                      Buckets: 1024  Batches: 1  Memory Usage: 10kB
                      Buffers: shared hit=1
                      ->  Seq Scan on sala_venta s  (cost=0.00..1.40 rows=40 width=4) (actual time=0.002..0.005 rows=40 loops=1)
                            Buffers: shared hit=1
  InitPlan 2 (returns $1)
    ->  Aggregate  (cost=0.90..0.91 rows=1 width=8) (actual time=0.014..0.014 rows=1 loops=1)
          ->  CTE Scan on p p_1  (cost=0.00..0.80 rows=40 width=8) (actual time=0.000..0.010 rows=40 loops=1)
Planning:
  Buffers: shared hit=4
Planning Time: 0.120 ms
Execution Time: 0.114 ms
```

## D4. Borrar socios sin compras con alta de hace más de 5 años (chequeo de FK)

```sql
DELETE FROM cliente c WHERE c.tipo = 'socio'
           AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
           AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente)
```

### Antes

```
Delete on cliente c  (cost=760.48..5245.96 rows=0 width=0) (actual time=29.778..29.782 rows=0 loops=1)
  Buffers: shared hit=2992
  ->  Hash Right Anti Join  (cost=760.48..5245.96 rows=1915 width=12) (actual time=28.861..29.006 rows=653 loops=1)
        Hash Cond: (x.id_cliente = c.id_cliente)
        Buffers: shared hit=1686
        ->  Seq Scan on comprobante x  (cost=0.00..2907.72 rows=149972 width=10) (actual time=0.006..11.751 rows=149972 loops=1)
              Buffers: shared hit=1408
        ->  Hash  (cost=678.00..678.00 rows=6598 width=10) (actual time=3.587..3.589 rows=6603 loops=1)
              Buckets: 8192  Batches: 1  Memory Usage: 348kB
              Buffers: shared hit=278
              ->  Seq Scan on cliente c  (cost=0.00..678.00 rows=6598 width=10) (actual time=0.006..2.854 rows=6603 loops=1)
                    Filter: ((tipo = 'socio'::tipo_cliente) AND (fecha_alta < (CURRENT_DATE - '5 years'::interval)))
                    Rows Removed by Filter: 13397
                    Buffers: shared hit=278
Planning:
  Buffers: shared hit=8
Planning Time: 0.221 ms
Trigger for constraint fk_distribuidor_cliente: time=21.768 calls=653
Trigger for constraint fk_exportador_cliente: time=6.378 calls=653
Trigger for constraint comprobante_id_cliente_fkey: time=4256.895 calls=653
Execution Time: 4315.441 ms
```

### Después

```
Delete on cliente c  (cost=0.29..3853.78 rows=0 width=0) (actual time=10.753..10.755 rows=0 loops=1)
  Buffers: shared hit=20740
  ->  Nested Loop Anti Join  (cost=0.29..3853.78 rows=1876 width=12) (actual time=0.030..10.300 rows=653 loops=1)
        Buffers: shared hit=19434
        ->  Seq Scan on cliente c  (cost=0.00..678.00 rows=6598 width=10) (actual time=0.007..3.025 rows=6603 loops=1)
              Filter: ((tipo = 'socio'::tipo_cliente) AND (fecha_alta < (CURRENT_DATE - '5 years'::interval)))
              Rows Removed by Filter: 13397
              Buffers: shared hit=278
        ->  Index Scan using idx_comprobante_cliente on comprobante x  (cost=0.29..1.43 rows=10 width=10) (actual time=0.001..0.001 rows=1 loops=6603)
              Index Cond: (id_cliente = c.id_cliente)
              Buffers: shared hit=19156
Planning:
  Buffers: shared hit=14
Planning Time: 0.220 ms
Trigger for constraint fk_distribuidor_cliente: time=2.178 calls=653
Trigger for constraint fk_exportador_cliente: time=1.934 calls=653
Trigger for constraint comprobante_id_cliente_fkey: time=2.413 calls=653
Execution Time: 17.424 ms
```

## Índice descartado (fecha, id_sala) para S3

```
Aggregate  (cost=224.02..224.03 rows=1 width=48) (actual time=0.328..0.329 rows=1 loops=1)
  Buffers: shared hit=35
  ->  Sort  (cost=221.76..222.33 rows=226 width=12) (actual time=0.260..0.275 rows=235 loops=1)
        Sort Key: id_cliente
        Sort Method: quicksort  Memory: 34kB
        Buffers: shared hit=35
        ->  Index Only Scan using idx_tmp_fecha_sala on comprobante  (cost=0.42..212.92 rows=226 width=12) (actual time=0.015..0.191 rows=235 loops=1)
              Index Cond: ((fecha >= (CURRENT_DATE - 90)) AND (id_sala = 1))
              Heap Fetches: 3
              Buffers: shared hit=35
Planning:
  Buffers: shared hit=1
Planning Time: 0.090 ms
Execution Time: 0.352 ms
```

## El planificador no usa el índice: vino(tipo)

```
Seq Scan on vino  (cost=0.00..16.50 rows=367 width=35) (actual time=0.005..0.052 rows=367 loops=1)
  Filter: (tipo = 'tinto'::tipo_vino)
  Rows Removed by Filter: 233
  Buffers: shared hit=9
Planning Time: 0.042 ms
Execution Time: 0.071 ms
```

## El planificador no usa el índice: columna dentro de una función

```
Aggregate  (cost=3661.33..3661.34 rows=1 width=40) (actual time=21.250..21.252 rows=1 loops=1)
  Buffers: shared hit=1408
  ->  Seq Scan on comprobante  (cost=0.00..3657.58 rows=750 width=8) (actual time=1.190..17.480 rows=24989 loops=1)
        Filter: (EXTRACT(year FROM fecha) = '2025'::numeric)
        Rows Removed by Filter: 124983
        Buffers: shared hit=1408
Planning Time: 0.137 ms
Execution Time: 21.279 ms
```

## La misma consulta reescrita como rango

```
Aggregate  (cost=1959.64..1959.65 rows=1 width=40) (actual time=7.989..7.990 rows=1 loops=1)
  Buffers: shared hit=514
  ->  Bitmap Heap Scan on comprobante  (cost=18.28..1835.30 rows=24867 width=8) (actual time=0.992..4.776 rows=24989 loops=1)
        Recheck Cond: ((fecha >= '2025-01-01'::date) AND (fecha < '2026-01-01'::date))
        Rows Removed by Index Recheck: 32087
        Heap Blocks: lossy=512
        Buffers: shared hit=514
        ->  Bitmap Index Scan on idx_comprobante_fecha_brin  (cost=0.00..12.06 rows=27268 width=0) (actual time=0.068..0.068 rows=5120 loops=1)
              Index Cond: ((fecha >= '2025-01-01'::date) AND (fecha < '2026-01-01'::date))
              Buffers: shared hit=2
Planning:
  Buffers: shared hit=1
Planning Time: 0.128 ms
Execution Time: 8.026 ms
```
