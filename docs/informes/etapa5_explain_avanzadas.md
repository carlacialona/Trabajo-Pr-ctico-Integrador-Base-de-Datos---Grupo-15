# Etapa 5 · Planes de ejecución de las consultas avanzadas (S9 a S12)

Salida de `db/bench/explain_avanzadas.sql` con los índices de `008_indices.sql` creados. El plan de S12a (división relacional) está en `etapa4_planes.md`.

Pager usage is off.

## S9 · Ficha de un vino (vista v_ficha_vino)

```
 Nested Loop Left Join  (cost=0.83..100.77 rows=1 width=149) (actual time=0.423..0.428 rows=1 loops=1)
   Buffers: shared hit=42
   ->  Nested Loop Left Join  (cost=0.83..26.19 rows=1 width=81) (actual time=0.046..0.048 rows=1 loops=1)
         Buffers: shared hit=10
         ->  Nested Loop  (cost=0.55..17.89 rows=1 width=77) (actual time=0.035..0.037 rows=1 loops=1)
               Join Filter: ((b.cuit)::bpchar = (v.cuit_bodega)::bpchar)
               Buffers: shared hit=7
               ->  Nested Loop  (cost=0.55..16.60 rows=1 width=71) (actual time=0.030..0.031 rows=1 loops=1)
                     Buffers: shared hit=6
                     ->  Index Scan using vino_pkey on vino v  (cost=0.28..8.29 rows=1 width=67) (actual time=0.020..0.020 rows=1 loops=1)
                           Index Cond: (cod_vino = 1)
                           Buffers: shared hit=3
                     ->  Index Only Scan using vino_pkey on vino v_1  (cost=0.28..8.29 rows=1 width=4) (actual time=0.007..0.008 rows=1 loops=1)
                           Index Cond: (cod_vino = 1)
                           Heap Fetches: 1
                           Buffers: shared hit=3
               ->  Seq Scan on bodega b  (cost=0.00..1.13 rows=13 width=30) (actual time=0.003..0.003 rows=1 loops=1)
                     Buffers: shared hit=1
         ->  Index Scan using stock_deposito_pkey on stock_deposito d  (cost=0.28..8.29 rows=1 width=8) (actual time=0.010..0.010 rows=1 loops=1)
               Index Cond: (cod_vino = 1)
               Buffers: shared hit=3
   ->  GroupAggregate  (cost=0.00..59.49 rows=1 width=8) (actual time=0.141..0.141 rows=1 loops=1)
         Buffers: shared hit=18
         ->  Seq Scan on stock_sala  (cost=0.00..59.48 rows=3 width=8) (actual time=0.056..0.137 rows=2 loops=1)
               Filter: (cod_vino = 1)
               Rows Removed by Filter: 3316
               Buffers: shared hit=18
   SubPlan 1
     ->  Aggregate  (cost=9.50..9.51 rows=1 width=32) (actual time=0.183..0.184 rows=1 loops=1)
           Buffers: shared hit=10
           ->  Sort  (cost=9.48..9.48 rows=1 width=15) (actual time=0.172..0.174 rows=2 loops=1)
                 Sort Key: co.porcentaje DESC, c.nombre
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=10
                 ->  Hash Join  (cost=8.30..9.47 rows=1 width=15) (actual time=0.039..0.043 rows=2 loops=1)
                       Hash Cond: (c.id_cepa = co.id_cepa)
                       Buffers: shared hit=4
                       ->  Seq Scan on cepa c  (cost=0.00..1.12 rows=12 width=12) (actual time=0.003..0.004 rows=12 loops=1)
                             Buffers: shared hit=1
                       ->  Hash  (cost=8.29..8.29 rows=1 width=7) (actual time=0.023..0.023 rows=2 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=3
                             ->  Index Scan using composicion_pkey on composicion co  (cost=0.28..8.29 rows=1 width=7) (actual time=0.012..0.013 rows=2 loops=1)
                                   Index Cond: (cod_vino = v.cod_vino)
                                   Buffers: shared hit=3
   SubPlan 2
     ->  Aggregate  (cost=5.55..5.56 rows=1 width=32) (actual time=0.047..0.048 rows=1 loops=1)
           Buffers: shared hit=4
           ->  Sort  (cost=5.51..5.51 rows=2 width=20) (actual time=0.043..0.044 rows=2 loops=1)
                 Sort Key: m.nombre
                 Sort Method: quicksort  Memory: 25kB
                 Buffers: shared hit=4
                 ->  Hash Join  (cost=1.46..5.50 rows=2 width=20) (actual time=0.034..0.035 rows=2 loops=1)
                       Hash Cond: (vm.id_maridaje = m.id_maridaje)
                       Buffers: shared hit=4
                       ->  Index Only Scan using vino_maridaje_pkey on vino_maridaje vm  (cost=0.28..4.31 rows=2 width=2) (actual time=0.016..0.017 rows=2 loops=1)
                             Index Cond: (cod_vino = v.cod_vino)
                             Heap Fetches: 0
                             Buffers: shared hit=3
                       ->  Hash  (cost=1.08..1.08 rows=8 width=22) (actual time=0.005..0.006 rows=8 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 9kB
                             Buffers: shared hit=1
                             ->  Seq Scan on maridaje m  (cost=0.00..1.08 rows=8 width=22) (actual time=0.002..0.003 rows=8 loops=1)
                                   Buffers: shared hit=1
 Planning:
   Buffers: shared hit=734
 Planning Time: 1.879 ms
 Execution Time: 0.880 ms

```

## S10 · Parcelas que rinden menos que el promedio de su finca (CTE + subconsulta correlacionada)

```
 CTE Scan on rendimiento r  (cost=84.68..203254.06 rows=950 width=40) (actual time=15.369..354.566 rows=1510 loops=1)
   Filter: (kg_por_ha < (SubPlan 2))
   Rows Removed by Filter: 1340
   Buffers: shared hit=4092
   CTE rendimiento
     ->  Nested Loop  (cost=0.29..84.68 rows=2850 width=40) (actual time=11.650..14.782 rows=2850 loops=1)
           Buffers: shared hit=4092
           ->  Seq Scan on parcela p  (cost=0.00..10.19 rows=619 width=12) (actual time=0.017..0.062 rows=619 loops=1)
                 Buffers: shared hit=4
           ->  Memoize  (cost=0.29..0.59 rows=3 width=16) (actual time=0.020..0.022 rows=5 loops=619)
                 Cache Key: p.id_finca, p.nro_parcela
                 Cache Mode: logical
                 Hits: 0  Misses: 619  Evictions: 0  Overflows: 0  Memory Usage: 178kB
                 Buffers: shared hit=4088
                 ->  Index Scan using uq_lote_parcela_campania on lote_uva l  (cost=0.28..0.58 rows=3 width=16) (actual time=0.001..0.002 rows=5 loops=619)
                       Index Cond: ((id_finca = p.id_finca) AND (nro_parcela = p.nro_parcela))
                       Buffers: shared hit=4088
   SubPlan 2
     ->  Aggregate  (cost=71.25..71.27 rows=1 width=32) (actual time=0.119..0.119 rows=1 loops=2850)
           Buffers: shared hit=4088
           ->  CTE Scan on rendimiento r2  (cost=0.00..71.25 rows=1 width=32) (actual time=0.052..0.115 rows=20 loops=2850)
                 Filter: ((id_finca = r.id_finca) AND (campania = r.campania))
                 Rows Removed by Filter: 2830
                 Buffers: shared hit=4088
 Planning:
   Buffers: shared hit=100
 Planning Time: 0.260 ms
 JIT:
   Functions: 24
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 0.743 ms, Inlining 0.000 ms, Optimization 0.479 ms, Emission 11.112 ms, Total 12.334 ms
 Execution Time: 369.433 ms

```

## S11 · Ranking de vinos por sala (RANK OVER PARTITION BY)

```
 WindowAgg  (cost=19193.93..19601.93 rows=20400 width=24) (actual time=152.531..155.619 rows=120 loops=1)
   Run Condition: (rank() OVER (?) <= 3)
   Buffers: shared hit=5580
   ->  Sort  (cost=19193.93..19244.93 rows=20400 width=16) (actual time=152.520..155.397 rows=3286 loops=1)
         Sort Key: ventas.id_sala, ventas.botellas DESC
         Sort Method: quicksort  Memory: 251kB
         Buffers: shared hit=5580
         ->  Subquery Scan on ventas  (cost=17529.67..17733.67 rows=20400 width=16) (actual time=150.946..154.337 rows=3286 loops=1)
               Buffers: shared hit=5574
               ->  Finalize HashAggregate  (cost=17529.67..17733.67 rows=20400 width=16) (actual time=150.944..154.085 rows=3286 loops=1)
                     Group Key: c.id_sala, r.cod_vino
                     Batches: 1  Memory Usage: 1041kB
                     Buffers: shared hit=5574
                     ->  Gather  (cost=12939.67..17223.67 rows=40800 width=16) (actual time=145.075..151.545 rows=9645 loops=1)
                           Workers Planned: 2
                           Workers Launched: 2
                           Buffers: shared hit=5574
                           ->  Partial HashAggregate  (cost=11939.67..12143.67 rows=20400 width=16) (actual time=117.653..118.072 rows=3215 loops=3)
                                 Group Key: c.id_sala, r.cod_vino
                                 Batches: 1  Memory Usage: 1041kB
                                 Buffers: shared hit=5574
                                 Worker 0:  Batches: 1  Memory Usage: 1041kB
                                 Worker 1:  Batches: 1  Memory Usage: 1041kB
                                 ->  Parallel Hash Join  (cost=3392.93..10304.86 rows=217974 width=12) (actual time=17.216..81.995 rows=174379 loops=3)
                                       Hash Cond: (r.nro_comprobante = c.nro_comprobante)
                                       Buffers: shared hit=5574
                                       ->  Parallel Seq Scan on renglon_comprobante r  (cost=0.00..6339.74 rows=217974 width=12) (actual time=0.010..13.884 rows=174379 loops=3)
                                             Buffers: shared hit=4160
                                       ->  Parallel Hash  (cost=2290.19..2290.19 rows=88219 width=8) (actual time=16.280..16.281 rows=49991 loops=3)
                                             Buckets: 262144  Batches: 1  Memory Usage: 7968kB
                                             Buffers: shared hit=1408
                                             ->  Parallel Seq Scan on comprobante c  (cost=0.00..2290.19 rows=88219 width=8) (actual time=0.015..4.778 rows=49991 loops=3)
                                                   Buffers: shared hit=1408
 Planning:
   Buffers: shared hit=178
 Planning Time: 0.604 ms
 Execution Time: 156.370 ms

```

## S11b · Ventas mensuales acumuladas (SUM OVER)

```
 WindowAgg  (cost=6085.04..6384.98 rows=14997 width=76) (actual time=66.441..68.916 rows=2920 loops=1)
   Buffers: shared hit=1411
   ->  Sort  (cost=6085.04..6122.53 rows=14997 width=44) (actual time=66.412..66.737 rows=2920 loops=1)
         Sort Key: comprobante.id_sala, (date_trunc('month'::text, (comprobante.fecha)::timestamp with time zone))
         Sort Method: quicksort  Memory: 254kB
         Buffers: shared hit=1411
         ->  HashAggregate  (cost=4782.37..5044.82 rows=14997 width=44) (actual time=63.837..65.304 rows=2920 loops=1)
               Group Key: comprobante.id_sala, date_trunc('month'::text, (comprobante.fecha)::timestamp with time zone)
               Batches: 1  Memory Usage: 2065kB
               Buffers: shared hit=1408
               ->  Seq Scan on comprobante  (cost=0.00..3657.58 rows=149972 width=20) (actual time=0.017..33.907 rows=149972 loops=1)
                     Buffers: shared hit=1408
 Planning:
   Buffers: shared hit=32
 Planning Time: 0.231 ms
 Execution Time: 69.186 ms

```

## S12b · Clientes que nunca compraron vino tinto (anti-join)

```
 Nested Loop Semi Join  (cost=5531.75..22510.97 rows=4110 width=4) (actual time=224.862..228.860 rows=223 loops=1)
   Buffers: shared hit=12912
   ->  Hash Right Anti Join  (cost=5531.46..20516.60 rows=5781 width=4) (actual time=224.763..225.495 rows=3528 loops=1)
         Hash Cond: (c_1.id_cliente = cl.id_cliente)
         Buffers: shared hit=5855
         ->  Hash Join  (cost=4803.46..16417.76 rows=319986 width=4) (actual time=39.549..187.026 rows=254187 loops=1)
               Hash Cond: (r.nro_comprobante = c_1.nro_comprobante)
               Buffers: shared hit=5577
               ->  Hash Join  (cost=21.09..10795.41 rows=319986 width=4) (actual time=0.101..88.320 rows=254187 loops=1)
                     Hash Cond: (r.cod_vino = v.cod_vino)
                     Buffers: shared hit=4169
                     ->  Seq Scan on renglon_comprobante r  (cost=0.00..9391.38 rows=523138 width=8) (actual time=0.005..31.200 rows=523138 loops=1)
                           Buffers: shared hit=4160
                     ->  Hash  (cost=16.50..16.50 rows=367 width=4) (actual time=0.089..0.090 rows=367 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 21kB
                           Buffers: shared hit=9
                           ->  Seq Scan on vino v  (cost=0.00..16.50 rows=367 width=4) (actual time=0.007..0.059 rows=367 loops=1)
                                 Filter: (tipo = 'tinto'::tipo_vino)
                                 Rows Removed by Filter: 233
                                 Buffers: shared hit=9
               ->  Hash  (cost=2907.72..2907.72 rows=149972 width=8) (actual time=38.717..38.718 rows=149972 loops=1)
                     Buckets: 262144  Batches: 1  Memory Usage: 7907kB
                     Buffers: shared hit=1408
                     ->  Seq Scan on comprobante c_1  (cost=0.00..2907.72 rows=149972 width=8) (actual time=0.007..13.819 rows=149972 loops=1)
                           Buffers: shared hit=1408
         ->  Hash  (cost=478.00..478.00 rows=20000 width=4) (actual time=3.829..3.830 rows=20000 loops=1)
               Buckets: 32768  Batches: 1  Memory Usage: 960kB
               Buffers: shared hit=278
               ->  Seq Scan on cliente cl  (cost=0.00..478.00 rows=20000 width=4) (actual time=0.004..2.077 rows=20000 loops=1)
                     Buffers: shared hit=278
   ->  Index Only Scan using idx_comprobante_cliente on comprobante c  (cost=0.29..0.54 rows=11 width=4) (actual time=0.001..0.001 rows=0 loops=3528)
         Index Cond: (id_cliente = cl.id_cliente)
         Heap Fetches: 0
         Buffers: shared hit=7057
 Planning:
   Buffers: shared hit=133
 Planning Time: 0.743 ms
 Execution Time: 228.948 ms

```
