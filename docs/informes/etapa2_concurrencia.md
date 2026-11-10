# Etapa 2 · Demostración de concurrencia: la última botella

Generado por `db/bench/demo_concurrencia.py`: dos conexiones reales a PostgreSQL, en paralelo, intentan vender la última botella de un vino en la sala 1. Nivel de aislamiento: **READ COMMITTED** (el predeterminado de PostgreSQL: cada sentencia ve lo confirmado hasta el momento en que empieza).

## 1. Sin bloqueo: leer, calcular en la aplicación y escribir

| t (s) | Sesión A | Sesión B |
| ---: | --- | --- |
| 0.00 |  | BEGIN |
| 0.00 | BEGIN |  |
| 0.00 |  | SELECT cantidad (sin FOR UPDATE) -> 1 |
| 0.00 | SELECT cantidad (sin FOR UPDATE) -> 1 |  |
| 0.00 | hay stock según lo leído: UPDATE ... SET cantidad = 0 |  |
| 0.00 | COMMIT · venta registrada |  |
| 0.30 |  | hay stock según lo leído: UPDATE ... SET cantidad = 0 |
| 0.30 |  | COMMIT · venta registrada |

Resultado: ventas registradas = **2** (A, B), stock final = **0**.

Las dos sesiones leyeron `1` antes de que la otra escribiera, las dos creyeron que había stock y las dos escribieron `0`. Se vendieron **dos botellas con una sola en stock** y el stock quedó en 0 en vez de -1: la segunda escritura pisó a la primera (*lost update*). READ COMMITTED no lo evita, porque cada SELECT es correcto en su momento; el problema es decidir con un dato que ya cambió.

## 2. Con `SELECT ... FOR UPDATE`

| t (s) | Sesión A | Sesión B |
| ---: | --- | --- |
| 0.00 | BEGIN |  |
| 0.00 | SELECT cantidad ... FOR UPDATE -> 1 |  |
| 0.00 |  | BEGIN |
| 0.00 |  | SELECT cantidad ... FOR UPDATE -> queda ESPERANDO (A tiene la fila bloqueada) |
| 1.00 | UPDATE ... SET cantidad = cantidad - 1 |  |
| 1.00 | COMMIT · venta registrada |  |
| 1.00 |  | SELECT cantidad ... FOR UPDATE -> 0 |
| 1.00 |  | no hay stock: ROLLBACK · venta rechazada |

Resultado: ventas registradas = **1** (A), stock final = **0**.

`FOR UPDATE` bloquea la fila: la sesión B no puede leerla para modificarla hasta que A termine. Cuando A confirma, B recién obtiene la fila con el valor nuevo (0) y rechaza la venta.

## 3. El sistema real: el trigger de RN-09 hace el bloqueo

| t (s) | Sesión A | Sesión B |
| ---: | --- | --- |
| 0.00 | BEGIN |  |
| 0.01 | INSERT renglón (1 botella) en el comprobante 149982 -> OK, el trigger descontó el stock |  |
| 0.10 |  | BEGIN |
| 0.11 |  | INSERT renglón (1 botella) -> el trigger pide FOR UPDATE y queda ESPERANDO |
| 1.02 |  | ERROR [P0001] RN-09: stock insuficiente del vino 613 en la sala 1 (disponible 0, pedido 1) |
| 1.02 | COMMIT · venta registrada |  |
| 1.02 |  | ROLLBACK · el comprobante tampoco queda |

Resultado: ventas registradas = **1** (A), stock final = **0**.

La API no hace `SELECT ... FOR UPDATE`: solo inserta el renglón. El trigger `trg_renglon_comprobante_antes` bloquea la fila de `stock_sala` con `FOR UPDATE` antes de validar el stock, así que la regla se cumple aunque alguien venda desde `psql` sin pasar por la API. Además el `CHECK (cantidad >= 0)` es una segunda barrera: aunque el trigger no existiera, un `UPDATE ... SET cantidad = cantidad - 1` sobre 0 fallaría.

## Cómo reproducirlo a mano con dos terminales `psql`

1. En ambas: `BEGIN;`
2. En A: `SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = <vino> FOR UPDATE;` (devuelve 1)
3. En B: la misma consulta. **Queda esperando.**
4. En A: `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 1 AND cod_vino = <vino>; COMMIT;`
5. En B: recién ahora devuelve 0 y la venta se rechaza.

Sin `FOR UPDATE`, en el paso 3 B devuelve 1 enseguida y las dos sesiones venden.
