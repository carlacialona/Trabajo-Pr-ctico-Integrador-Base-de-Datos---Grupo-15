# 2. Integridad y lógica en la base

Etapa 2: que las reglas de negocio vivan dentro de la base y se cumplan sin importar quién la use (la API, `psql`, DBeaver o un script).

Archivos: `db/migrations/002_constraints.sql` a `007_roles.sql` y `db/tests/db_tests.sql`.

## 2.1 ¿Dónde va cada regla?

| Tipo de regla | Herramienta | Por qué ahí | Ejemplo en el proyecto |
| --- | --- | --- | --- |
| Valor válido de una sola fila, siempre igual | `NOT NULL`, `CHECK`, `DOMAIN` | Es lo más barato y lo valida el motor en cada INSERT/UPDATE sin código | `precio > 0`, `graduacion BETWEEN 5 AND 20`, CUIT de 11 dígitos |
| Existencia de un dato relacionado | `FOREIGN KEY` | Integridad referencial: no hay renglones de un vino inexistente | `renglon_comprobante.cod_vino → vino` |
| Unicidad | `PRIMARY KEY` / `UNIQUE` | Las claves candidatas | una cosecha por parcela y campaña |
| Depende de otras filas, de otras tablas o de la fecha actual | Trigger | Un CHECK solo ve la propia fila y debe ser determinístico | stock suficiente, fecha de confección = hoy, máquina de estados |
| Cálculo que se usa en varios lugares | Función | Una sola fórmula para triggers, consultas y API | `fn_total_comprobante`, `fn_subtotal_renglon` |
| Operación de varios pasos, todo o nada | Procedimiento | Valida, bloquea, mueve stock y cambia estado en una transacción | `sp_procesar_transferencia` |
| Formato, experiencia de usuario, autorización de personas | API y front | No es una regla del negocio sino de la interfaz | mensajes claros, botones habilitados según el estado |

**Por qué no `CURRENT_DATE` en un CHECK**: un CHECK debe dar siempre el mismo resultado para la misma fila. Si dependiera de la fecha, una fila válida hoy sería inválida mañana y un backup podría no restaurarse. Por eso la fecha de confección de una transferencia (RN-11) se controla con un trigger.

## 2.2 Trazabilidad: regla → mecanismo → prueba

Las pruebas SQL están en `db/tests/db_tests.sql` (cada caso imprime `OK RN-xx ...`). Las de la API, en `api/tests/api.test.js`.

| Regla | Mecanismo en la base | Archivo | Prueba SQL | Prueba API |
| --- | --- | --- | --- | --- |
| **RN-01** Precio único por vino y > 0 | atributo `vino.precio` + `CHECK ck_vino_precio` | 001, 002 | precio 0 y negativo fallan (23514) | precio negativo → 422 |
| **RN-02** Sala en una localidad; un encargado por localidad | FK `sala_venta.id_localidad NOT NULL`; encargado como columna de `localidad` (3FN) | 001 | sala sin localidad (23502), con localidad inexistente (23503), verificación de que el encargado no está en `sala_venta` | — |
| **RN-03** Empleado en una sola sala | FK `empleado.id_sala NOT NULL` | 001 | empleado sin sala falla; con sala funciona | — |
| **RN-04** Una cepa por parcela; una cosecha por campaña | `parcela.id_cepa NOT NULL`; `UNIQUE (id_finca, nro_parcela, campania)`; `CHECK` año de cosecha = campaña | 001, 002 | segunda cosecha falla (23505); otra campaña funciona; parcela sin cepa falla | — |
| **RN-05** Porcentajes de corte suman 100 | `CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` en `composicion` y en `vino` | 005 | corte de 90 falla; vino sin composición falla; 70 + 30 en dos INSERT funciona | composición de 90 → 409 y no queda el vino |
| **RN-06** Descuento por tipo de cliente | `fn_descuento_por_tipo` + trigger `trg_cliente_descuento` + `CHECK ck_cliente_descuento` | 003, 005, 002 | socio 10, distribuidor 20, exportador 30; fuera de rango falla; subtipo incoherente falla | exportador recibe 30 %; descuento 90 → 422 |
| **RN-07** Varios permisos; vencimiento > emisión | tabla `permiso_exportacion` (FK a `exportador`) + `CHECK ck_permiso_fechas` | 001, 002 | dos permisos funcionan; fechas invertidas fallan; permiso para un socio falla | fechas invertidas → 422 y no queda el cliente |
| **RN-08** Total = suma de renglones con descuento; no se carga a mano | `fn_subtotal_renglon`, `fn_total_comprobante`, `fn_recalcular_comprobante`; triggers `trg_renglon_comprobante_antes/despues` y `trg_comprobante_importes`; `CHECK total = subtotal - descuento`; la API no tiene UPDATE sobre `comprobante` | 003, 005, 002, 007 | trigger completa importes; cabecera correcta; modificar total a mano falla; crear con importes falla | la base calcula precio, descuento y total |
| **RN-09** No vender más que el stock; stock nunca negativo | trigger BEFORE INSERT con `SELECT ... FOR UPDATE` + `CHECK (cantidad >= 0)` | 005, 002 | vender 3 con 2 en stock falla y no deja cambios; stock negativo directo falla | venta sin stock → 409 y no queda nada (todo o nada) |
| **RN-10** Ingresos: estados y solo terminado impacta | ENUM `estado_documento` + trigger `trg_ingreso_estado` + `sp_procesar_ingreso` | 001, 005, 004 | procesar en confección, saltar estados, crear procesado, marcar procesado a mano, retroceder y procesar dos veces fallan | procesar en confección → 409 |
| **RN-11** Igual para transferencias; fecha actual inmodificable | trigger `trg_transferencia_estado`, `trg_a_transferencia_fecha`, `sp_procesar_transferencia` | 005, 004 | fecha forzada a hoy; modificarla falla; procesar sin stock falla sin cambios a medias; vino sin fila en depósito falla | sin stock → 409 y queda terminada |
| **RN-12** Documento fuera de confección no admite cambios en renglones | triggers `trg_renglon_ingreso_bloqueo`, `trg_renglon_transferencia_bloqueo` | 005 | agregar, modificar y borrar renglones de documentos terminados/procesados fallan | agregar renglón a transferencia procesada → 409 |
| **RN-13** Auditoría de cambios de precio | trigger `AFTER UPDATE OF precio` + tabla `auditoria_precio` (SECURITY DEFINER: la API no puede escribirla) | 005, 007 | se audita el cambio; un UPDATE que no cambia el precio no se audita; la venta conserva el precio histórico | cambio de precio queda auditado con usuario `bodegas_api` |
| **RN-14** No borrar transportista, bodega o vino con movimientos | FK `ON DELETE RESTRICT` | 001 | los tres borrados fallan (23503); un vino sin movimientos sí se borra | borrar vino vendido → 409 |
| **RN-15** Cantidades, superficies, kilos y precios positivos; graduación 5-20 | `CHECK` en cada columna | 002 | graduación 25 y 4, superficie negativa, kilos 0, cantidad negativa fallan | precio negativo → 422 |

Además se prueban: DOMAIN de CUIT, ENUM inválido, UNIQUE de vino y de documento, y los roles (la API no puede escribir el stock ni la auditoría ni crear tablas; el rol de lectura no puede insertar).

## 2.3 Cobertura de los mínimos exigidos

| Elemento | Mínimo | Implementado |
| --- | --- | --- |
| PRIMARY KEY | todas las tablas | 30 tablas, todas con PK (compuestas en renglones, stock, composición, parcela) |
| FOREIGN KEY | todas las relaciones, con ON DELETE/UPDATE justificados | 36 FK; ver tabla de acciones en `01_modelo_de_datos.md` |
| NOT NULL | atributos obligatorios | todos los atributos del enunciado son obligatorios |
| UNIQUE | 4 además de las PK | 12 (vino, lote, cliente, bodega, transportista, cepa, maridaje, localidad, departamento, provincia, distribuidor, `cliente(id_cliente, tipo)`) |
| CHECK | 8, uno entre columnas | 34; entre columnas: `ck_permiso_fechas`, `ck_comprobante_total`, `ck_comprobante_descuento`, `ck_lote_fecha_campania` |
| DEFAULT | 3 | 15 (estados, fechas, importes, stock, auditoría, tipo de subtipo) |
| Tipos propios | 1 ENUM y 1 DOMAIN | 6 ENUM, 3 DOMAIN |
| Funciones | 4 | 8: `fn_descuento_por_tipo`, `fn_descuento_cliente`, `fn_stock_sala`, `fn_stock_total`, `fn_subtotal_renglon`, `fn_total_comprobante`, `fn_antiguedad_anios`, `fn_recalcular_comprobante` (+ `fn_refrescar_ventas_mensuales`) |
| Procedimientos | 2 transaccionales | `sp_procesar_ingreso`, `sp_procesar_transferencia` |
| Triggers | 6, con BEFORE, AFTER y constraint diferido | 12 triggers (ver 2.4) |
| Vistas | 3, una materializada | `v_stock_total_vino`, `v_ficha_vino`, `v_documentos_pendientes`, `mv_ventas_mensuales_sala` (materializada) |
| Roles | propietario, API, lectura | propietario (`bodegas_owner` en Docker), `bodegas_api`, `bodegas_lectura` |

## 2.4 Funciones: volatilidad

| Función | Volatilidad | Por qué |
| --- | --- | --- |
| `fn_descuento_por_tipo(tipo)` | IMMUTABLE | Solo depende del argumento. |
| `fn_subtotal_renglon(cant, precio, %)` | IMMUTABLE | Solo aritmética. |
| `fn_descuento_cliente(id)`, `fn_stock_sala`, `fn_stock_total`, `fn_total_comprobante` | STABLE | Leen tablas: dentro de una sentencia dan siempre lo mismo, pero entre sentencias pueden cambiar. |
| `fn_antiguedad_anios(fecha)` | STABLE | Usa `CURRENT_DATE`: cambia de un día a otro. Por eso no puede ser IMMUTABLE ni usarse en un índice o CHECK. |
| `fn_recalcular_comprobante(nro)` | VOLATILE, SECURITY DEFINER | Modifica datos. Corre con permisos del dueño porque la API no tiene UPDATE sobre `comprobante`. |

## 2.5 Triggers

| Trigger | Tabla | Momento | Regla | Por qué en ese momento |
| --- | --- | --- | --- | --- |
| `trg_cliente_descuento` | cliente | BEFORE INSERT | RN-06 | Modifica `NEW` antes de guardar. |
| `trg_renglon_comprobante_antes` | renglon_comprobante | BEFORE INSERT/UPDATE | RN-09, RN-08 | Valida stock (con `FOR UPDATE`) y completa precio, descuento y subtotal antes de guardar. |
| `trg_renglon_comprobante_despues` | renglon_comprobante | AFTER INSERT/UPDATE/DELETE | RN-08, RN-09 | Recién después de guardar la fila la suma la incluye; descuenta el stock. |
| `trg_comprobante_importes` | comprobante | BEFORE INSERT/UPDATE | RN-08 | Rechaza importes cargados a mano. Usa `pg_trigger_depth()` para distinguir un UPDATE directo (profundidad 1) del que hace el trigger de renglones (profundidad 2). |
| `trg_ingreso_estado`, `trg_transferencia_estado` | ingreso, transferencia | BEFORE INSERT/UPDATE | RN-10, RN-11 | Máquina de estados; a `procesado` solo desde el procedimiento (marca de sesión `bodegas.procesando`). |
| `trg_a_transferencia_fecha` | transferencia | BEFORE INSERT/UPDATE | RN-11 | Fuerza `CURRENT_DATE` y prohíbe cambiarla. Su nombre empieza con "a" porque PostgreSQL ejecuta los triggers del mismo momento en orden alfabético. |
| `trg_renglon_ingreso_bloqueo`, `trg_renglon_transferencia_bloqueo` | renglones | BEFORE INSERT/UPDATE/DELETE | RN-12 | Si la cabecera no existe (borrado en cascada, D5) lo permite. |
| `trg_vino_auditoria_precio` | vino | AFTER UPDATE OF precio, `WHEN (OLD.precio IS DISTINCT FROM NEW.precio)` | RN-13 | Solo se audita un cambio que efectivamente se guardó. |
| `trg_composicion_suma_100`, `trg_vino_requiere_composicion` | composicion, vino | CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED | RN-05 | Se verifica al COMMIT: permite cargar 85 % y luego 15 % en la misma transacción. |

## 2.6 Procedimientos transaccionales

`sp_procesar_ingreso(cod)` y `sp_procesar_transferencia(nro)`:

1. `SELECT ... FOR UPDATE` sobre la cabecera: si dos usuarios procesan lo mismo a la vez, el segundo espera y luego ve `procesado`.
2. Validan el estado (`terminado`).
3. La transferencia bloquea las filas de `stock_deposito` **en orden de `cod_vino`**: siempre el mismo orden evita deadlocks entre dos transferencias con vinos en común.
4. Verifican el stock **antes** de mover nada, con un `LEFT JOIN` que detecta también el vino sin fila en el depósito (el caso "para pensar" del anexo A.6: un `UPDATE ... FROM` no daría error y no descontaría nada).
5. Mueven el stock (`INSERT ... ON CONFLICT DO UPDATE` crea la fila si no existía).
6. Cambian el estado.

Si cualquier paso lanza una excepción, PostgreSQL revierte todo lo que hizo la llamada: no quedan cambios a medias (lo verifican las pruebas).

## 2.7 Roles y privilegios mínimos

| Rol | Uso | Privilegios |
| --- | --- | --- |
| Propietario (`bodegas_owner`) | migraciones y carga | dueño de todos los objetos |
| `bodegas_api` | la API | `SELECT` en todo; `INSERT/UPDATE/DELETE` en tablas de negocio; `INSERT/DELETE` (sin UPDATE) en comprobantes; **nada** de escritura en `stock_sala`, `stock_deposito`, `auditoria_precio`; `EXECUTE` en funciones y procedimientos |
| `bodegas_lectura` | reportes | `SELECT` y funciones de consulta |

Se revocan los privilegios por defecto de `PUBLIC` (sobre la base, el esquema, tablas y funciones). Los triggers y procedimientos que escriben stock o auditoría son `SECURITY DEFINER` (corren con los permisos del dueño) y fijan `search_path` para que nadie pueda inyectar una función con el mismo nombre. Consecuencia: **la API no puede alterar el stock ni falsificar la auditoría aunque quisiera**; solo puede vender, transferir o ingresar por los caminos que validan las reglas.

## 2.8 Concurrencia

Ver [`informes/etapa2_concurrencia.md`](informes/etapa2_concurrencia.md): dos sesiones reales venden la última botella al mismo tiempo, sin bloqueo (se vende dos veces), con `FOR UPDATE` (la segunda espera y se rechaza) y con el sistema real (el trigger hace el bloqueo y la segunda venta falla con RN-09). Nivel de aislamiento: READ COMMITTED.
