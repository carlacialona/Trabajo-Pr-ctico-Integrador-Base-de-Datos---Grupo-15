# 5. Consultas SQL

Etapa 5. Archivos en `consultas/`:

| Archivo | Consignas | Cómo se prueba |
| --- | --- | --- |
| `update.sql` | U1 a U6 | `BEGIN` → control previo → sentencia → control posterior → `ROLLBACK` |
| `insert.sql` | I1 a I6 | ídem |
| `delete.sql` | D1 a D6 | ídem, con `\timing` |
| `select.sql` | S1 a S12 | resultados y tiempos |

Correr: `psql -d bodegas -f consultas/update.sql` (y los demás). Los parámetros (bodega, sala, localidad, vino) están al principio de cada archivo como variables de `psql` (`\set bodega_u3 'Viñedos Lopez SRL'`); se cambian ahí. Los planes de S9 a S12 están en [`informes/etapa5_explain_avanzadas.md`](informes/etapa5_explain_avanzadas.md) y los de S2, S3, S5, S8, S12a y D4 en [`informes/etapa4_planes.md`](informes/etapa4_planes.md).

## 5.1 Comentarios sobre las consultas más interesantes

**U1 · Recalcular totales con el descuento del tipo.** No se puede hacer `UPDATE comprobante SET total = ...`: el trigger de RN-08 lo rechaza (y la API ni siquiera tiene el permiso). Se corrige el porcentaje de los **renglones** que no coinciden con su tipo de cliente y los triggers recalculan subtotales y cabeceras. El `WHERE` filtra solo los renglones que difieren: con datos consistentes afecta 0 filas, así que el script primero "rompe" tres renglones para mostrar el efecto.

**U4 · Lunes ↔ miércoles en una sola sentencia.** Un `CASE` en el `SET`. No hay riesgo de "ida y vuelta" porque un UPDATE evalúa todas las filas sobre la versión anterior de la tabla.

**U5 · 10 menos vendidos.** `LEFT JOIN` para incluir los vinos que nunca se vendieron (0 botellas): con un JOIN común desaparecerían, y son justamente los menos vendidos. Desempate por código para un resultado determinístico. Dispara la auditoría (RN-13).

**U6 · Descuento al 35 %.** Posible porque el descuento se almacena en `cliente` (decisión de diseño). No hace falta filtrar por tipo: la FK de `permiso_exportacion` apunta a `exportador`.

**I1 · Cobertura para el transportista con menos envíos.** `LEFT JOIN` con la condición de fecha **en el ON**: si estuviera en el WHERE, el transportista con 0 envíos no aparecería. `ON CONFLICT DO NOTHING` por si ya cubría la localidad.

**I2 · "Cordero al disco".** Un CTE que modifica datos (`INSERT ... RETURNING`) alimenta el segundo INSERT en una sola sentencia. El `WHERE EXISTS` implementa el "si existe algún vino...".

**I3 · Venta en una transacción.** Exactamente lo que hace la API: cabecera con importes en 0, renglones con solo vino y cantidad; los triggers completan todo y `fn_total_comprobante` lo verifica.

**D1 · Comprobantes viejos de socios.** `DELETE ... USING`; los renglones se van por `CASCADE`. El stock no cambia: es depuración de historial, no anulación.

**D5 · Ingresos procesados viejos.** Interacción con triggers: RN-12 prohíbe borrar renglones de un ingreso procesado, pero en el borrado en cascada la cabecera ya no existe y el trigger lo permite. El script muestra además que borrar un renglón suelto sigue prohibido.

**S2 · Vendidos en todas las salas (división relacional).** Doble `NOT EXISTS`: "vinos para los que no existe una sala en la que no se hayan vendido". Se incluye la versión con `count(DISTINCT id_sala) = (SELECT count(*) FROM sala_venta)` como control: dan el mismo resultado (43 vinos).

**S3 · Clientes por tipo en la última semana.** Se parte de `enum_range(NULL::tipo_cliente)` para que aparezcan también los tipos con 0 clientes.

**S5 · Salas con menos pendientes.** `LEFT JOIN` con el estado en el ON para que las salas con 0 pendientes cuenten (son las que tienen "menos").

**S9 · Ficha del vino.** La vista `v_ficha_vino` agrega cepas y maridajes en subconsultas separadas: si se uniera todo y luego se agrupara, cada cepa se repetiría por cada maridaje (producto cartesiano).

**S10 · Rendimiento por hectárea.** CTE con kg/ha + subconsulta **correlacionada** que calcula el promedio de la misma finca y campaña para cada fila.

**S11 · Ranking por sala y acumulado mensual.** `RANK() OVER (PARTITION BY id_sala ORDER BY botellas DESC)` numera dentro de cada sala; el filtro `puesto <= 3` va en una consulta externa porque una función de ventana no puede usarse en el WHERE de su propia consulta. El acumulado usa `SUM(...) OVER (PARTITION BY id_sala ORDER BY mes)`.

**S12 · Todos los vinos de una bodega / nunca un tinto.** División con doble `NOT EXISTS` y anti-join con `NOT EXISTS`. En S12b se consideran solo clientes que compraron algo (si no, la respuesta incluiría a los que nunca compraron nada, que es otra pregunta). S12a pasó de ~126 s a ~0,6 s con los índices sobre las FK.

## 5.2 Triggers y constraints que se activaron

| Consigna | Qué pasó |
| --- | --- |
| U1 | Triggers BEFORE/AFTER de renglones recalcularon subtotales y cabeceras. |
| U3, U5 | Trigger de auditoría: una fila en `auditoria_precio` por vino. |
| I3 | Triggers de renglones: validación de stock, importes y descuento de stock. |
| D1 | `ON DELETE CASCADE` sobre renglones; el trigger AFTER DELETE no devuelve stock. |
| D4 | La FK `comprobante → cliente` (RESTRICT) obliga a verificar cada cliente borrado: era lenta sin índice. |
| D5 | Trigger RN-12 permite el borrado en cascada pero no el borrado suelto. |
