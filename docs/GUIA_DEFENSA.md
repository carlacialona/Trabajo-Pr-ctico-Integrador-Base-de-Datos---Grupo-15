# Guía de estudio para la defensa oral

Esta guía está pensada para que cada integrante pueda explicar **cualquier** parte del trabajo. Está ordenada como los criterios de evaluación. Cada respuesta indica dónde está el código para mostrarlo en vivo.

Consejo general: ante una pregunta, contestar con la estructura **regla → decisión → mecanismo → alternativa descartada**. Por ejemplo: "RN-09 dice que no se vende más que el stock (regla). Como depende de otra tabla, no alcanza un CHECK (decisión), así que va en un trigger BEFORE INSERT que bloquea la fila con FOR UPDATE (mecanismo). No lo validamos en la API porque alguien podría vender desde psql (alternativa descartada)."

---

## 1. Teoría que sostiene todo

**Dependencia funcional (DF).** X → Y: si dos filas coinciden en X, coinciden en Y. Ejemplo: `localidad → encargado_regional`. Las DF salen del enunciado, no de los datos.

**Superclave, clave candidata, clave primaria.** Superclave: cualquier conjunto de atributos que identifica una fila. Clave candidata: superclave **mínima** (si le sacás un atributo, deja de identificar). Primaria: la candidata elegida. Las otras candidatas se protegen con UNIQUE. Ejemplo: en `lote_uva`, `nro_lote` y `(id_finca, nro_parcela, campania)` son candidatas.

**Formas normales.**
- 1FN: valores atómicos, sin grupos repetidos. "Un vino con varias cepas" no va en una columna `cepas = 'Malbec, Cabernet'`: va en `composicion`.
- 2FN: 1FN y sin **dependencias parciales** (un atributo no clave que depende de parte de una clave compuesta). Si `renglon_comprobante` guardara la fecha, dependería solo de `nro_comprobante`, que es parte de su PK.
- 3FN: 2FN y sin **dependencias transitivas** (no clave → no clave). Si `sala_venta` guardara el encargado: sala → localidad → encargado.
- Para qué sirve: evitar **anomalías**. De actualización (cambiar el encargado en 8 salas y olvidarse una), de inserción (no poder registrar un encargado sin una sala) y de borrado (borrar la única sala y perder quién es el encargado).

**Integridad referencial.** Toda FK apunta a una fila que existe. La base la garantiza con las FOREIGN KEY y sus acciones (`RESTRICT`, `CASCADE`).

**Entidad débil.** No se identifica sola sino junto con su entidad fuerte: `parcela` (finca + número). Su PK incluye la FK.

**Transacción (ACID).** Atomicidad (todo o nada), Consistencia (respeta las reglas), Aislamiento (las transacciones concurrentes no se pisan según el nivel), Durabilidad (lo confirmado no se pierde).

---

## 2. Entidades y claves

**¿Por qué `departamento` es una tabla y no una columna de finca?**
Porque tiene un atributo propio (la provincia). Si finca guardara departamento y provincia, tendríamos finca → departamento → provincia: una dependencia transitiva (viola 3FN). La provincia se repetiría en cada finca y podría quedar inconsistente.

**¿Y por qué la campaña es una columna?**
No tiene atributos propios: es un año. Una tabla `campania(anio)` no agregaría información.

**¿Por qué el encargado regional está en `localidad`?** (pregunta casi segura)
El enunciado dice que hay un único encargado por localidad, y que en las localidades con varias salas todas tienen el mismo. La DF es `localidad → encargado`. En `sala_venta` sería transitiva y permitiría encargados distintos en la misma localidad (rompe RN-02). Lo dejamos como texto y no como FK a empleado porque el encargado no trabaja en una sala (RN-03 obliga a que todo empleado tenga sala) y crearía un ciclo de FK.

**¿Por qué no usaron el código postal como clave de localidad?**
Porque no identifica: San Carlos y Eugenio Bustos comparten el 5569, Perdriel y Agrelo el 5509 (están en los catálogos cargados). Una clave tiene que ser única.

**¿Natural o subrogada? ¿Por qué CUIT en bodega pero id en cliente?**
CUIT es único, estable y simple (una columna): sirve como PK natural en bodega y empleado. En cliente la clave natural sería compuesta (tipo y número de documento, porque una persona tiene DNI y una empresa CUIT) y la referencian varias tablas: una FK de un entero es más simple y liviana. La natural igual queda protegida con `UNIQUE (tipo_doc, nro_doc)`.

**¿Por qué `parcela` tiene PK compuesta?** Es entidad débil: "parcela 3" existe en muchas fincas.

**El lote tiene dos claves candidatas. ¿Qué hicieron con la otra?**
`nro_lote` es la PK (la usan los análisis). `(id_finca, nro_parcela, campania)` se declaró UNIQUE: esa restricción **es** RN-04 (una cosecha por parcela y campaña). Archivo: `002_constraints.sql`, `uq_lote_parcela_campania`.

---

## 3. Relaciones y cardinalidades

**¿Cuándo hace falta una tabla intermedia?** En las N:M. Ejemplo: un vino tiene varias cepas y una cepa está en varios vinos → `composicion`.

**¿Dónde vive el porcentaje de corte?** En `composicion`: depende del vino **y** de la cepa. No puede ir en vino (¿qué cepa?) ni en cepa (¿qué vino?).

**Si el vino ya tiene precio, ¿por qué el renglón guarda `precio_unitario`?** (pregunta casi segura)
No es redundancia. El precio del vino cambia (y se audita, RN-13); el renglón guarda el precio **al momento de esa venta**. Depende de (comprobante, vino). Si no lo guardáramos, subir un precio cambiaría retroactivamente todas las facturas viejas. Lo completa el trigger, no la API.

**¿Por qué el stock del depósito no es una columna de vino?**
(1) Cambia con cada movimiento y el precio casi nunca: separarlos evita reescribir la fila del vino en cada transferencia. (2) La auditoría de precio es un trigger AFTER UPDATE sobre vino: se dispararía en cada movimiento de stock. (3) Si hubiera otro depósito, se agrega una columna a `stock_deposito` sin tocar vino. Es una relación 1:1.

**¿Por qué `stock_sala` tiene PK (id_sala, cod_vino)?** Hay una sola cantidad por sala y vino.

---

## 4. Jerarquía de clientes

**¿Qué alternativas evaluaron?** Tabla única con tipo (muchos NULL y un permiso podría apuntar a un socio), una tabla por subtipo sin supertipo (comprobante tendría que apuntar a tres tablas) y supertipo + subtipos (elegida).

**¿Por qué no hay tabla `socio`?** El socio no tiene atributos propios; queda representado por `cliente.tipo = 'socio'`.

**¿Qué impide que un distribuidor apunte a un cliente socio?**
La FK compuesta `(id_cliente, tipo) → cliente(id_cliente, tipo)` + `CHECK (tipo = 'distribuidor')` en la tabla del subtipo. Para eso cliente tiene `UNIQUE (id_cliente, tipo)`. Lo prueba `db_tests.sql`: "RN-06 subtipo distribuidor sobre un cliente socio" falla con 23503.

**¿Y que un permiso sea de un socio?** La FK de `permiso_exportacion` apunta a `exportador`, no a `cliente`.

**¿El descuento se guarda o se calcula?**
Se guarda. RN-06 dice que depende del tipo, pero la consulta U6 pide subirlo al 35 % para algunos exportadores: si fuera solo función del tipo, U6 sería imposible. Entonces `fn_descuento_por_tipo` da el valor base, un trigger BEFORE INSERT lo pone al crear el cliente, y un CHECK lo acota entre 0 y 50. El renglón guarda el porcentaje aplicado, así un cambio posterior no altera ventas viejas.

**Limitación que conocemos**: la base no obliga a que un cliente tipo distribuidor tenga su fila en `distribuidor`. Se podría con un constraint trigger diferido; lo resuelve la API creando ambos en una transacción.

---

## 5. Normalización y redundancias

**¿En qué forma normal está el modelo?** 3FN. Mostrar la tabla de dependencias de `01_modelo_de_datos.md` (sección 1.5).

**¿Qué redundancias conservaron y por qué?**
- Importes del comprobante (subtotal, descuento, total): derivados de los renglones, guardados por rendimiento y para conservar el histórico. Consistencia: triggers (RN-08), un trigger que rechaza modificarlos a mano, `CHECK (total = subtotal - descuento)`, y la API no tiene UPDATE sobre comprobante.
- Stock: derivable del historial, pero se guarda porque calcularlo en cada venta es lento y el historial se depura (D1, D5). Lo mueven solo triggers y procedimientos.
- `cliente.descuento`: ver sección 4.

**Si borro comprobantes viejos (D1), ¿el stock cambia?** No: el stock está almacenado y no se recalcula desde el historial. Borrar historial no es anular ventas. Por eso conviene guardarlo.

---

## 6. Reglas de negocio: ¿por qué ahí?

**¿Cuándo un CHECK y cuándo un trigger?**
CHECK: la regla mira **una sola fila** y su resultado no cambia con el tiempo (precio > 0). Trigger: depende de **otras filas, otras tablas o la fecha actual** (stock suficiente, estados, fecha de hoy).

**¿Por qué no se puede usar `CURRENT_DATE` en un CHECK?** Un CHECK debe ser determinístico: una fila válida hoy sería inválida mañana, y un backup podría no restaurarse. Por eso RN-11 (fecha de confección = hoy) está en un trigger.

**RN-05 (suma 100). ¿Por qué un constraint trigger diferido?**
Al cargar un vino 85 % Malbec + 15 % Cabernet se hacen dos INSERT. Después del primero la suma es 85: si se verificara fila por fila, fallaría. `DEFERRABLE INITIALLY DEFERRED` lo verifica al COMMIT, cuando ya están todas. También está enganchado a `vino` para que un vino no quede sin composición. Demostración: la API (`POST /vinos` con 60 + 30) devuelve 409 y no queda el vino.

**RN-08. ¿Cómo garantizan que el total no se cargue a mano?**
Cuatro capas: (1) el renglón solo recibe vino y cantidad; el trigger BEFORE completa precio, descuento y subtotal; (2) el trigger AFTER recalcula la cabecera; (3) `trg_comprobante_importes` rechaza un UPDATE directo de importes (usa `pg_trigger_depth()`: 1 = alguien lo escribió directamente; 2 = lo hizo el trigger de renglones); (4) la API no tiene permiso UPDATE sobre comprobante.

**RN-09. ¿Cómo evitan vender la misma botella dos veces?**
El trigger BEFORE INSERT del renglón hace `SELECT ... FROM stock_sala ... FOR UPDATE`: bloquea la fila hasta el fin de la transacción. Una segunda venta concurrente espera, luego lee el stock actualizado y falla. Además `CHECK (cantidad >= 0)` es una segunda barrera. Ver `informes/etapa2_concurrencia.md`.

**RN-10/11. ¿Cómo impiden pasar a procesado sin mover el stock?**
El trigger de estados solo acepta `terminado → procesado` si la sesión tiene la marca `bodegas.procesando = 'on'`, que pone el procedimiento con `set_config(..., true)` (dura solo la transacción). Un `UPDATE ... SET estado = 'procesado'` directo falla. Limitación honesta: alguien con acceso a `psql` podría poner la marca a mano; lo mitigan los permisos (la API no ejecuta SQL arbitrario).

**¿Por qué el procedimiento bloquea las filas en orden de `cod_vino`?** Si dos transferencias con vinos en común bloquearan en distinto orden (A bloquea 5 y espera 9; B bloquea 9 y espera 5), habría un deadlock. Con el mismo orden siempre, una espera a la otra.

**¿Qué pasa si un vino de la transferencia no tiene fila en `stock_deposito`?** (el "para pensar" del anexo A.6) Un `UPDATE ... FROM` no lo encontraría y no daría error. Nuestro procedimiento verifica antes con `LEFT JOIN ... COALESCE(cantidad, 0) < pedido` y lanza RN-11. Hay una prueba para eso.

**RN-12 y la consulta D5.** RN-12 prohíbe tocar renglones de un documento que no está en confección. D5 borra ingresos procesados: el `CASCADE` borra sus renglones. El trigger permite ese caso porque la cabecera ya no existe. Pero borrar un renglón suelto sigue prohibido.

**RN-13. ¿Por qué AFTER y no BEFORE?** Solo se audita un cambio que efectivamente se guardó. Además tiene `WHEN (OLD.precio IS DISTINCT FROM NEW.precio)`: un UPDATE que no cambia el precio no se audita. ¿Por qué `session_user`? La función es SECURITY DEFINER: `current_user` sería el dueño; `session_user` es quien se conectó (`bodegas_api`).

**RN-14.** `ON DELETE RESTRICT` en las FK de los movimientos. ¿Y CASCADE dónde? Solo en lo que no existe sin su cabecera: renglones, parcelas, composición, subtipos, permisos.

---

## 7. Funciones, procedimientos, vistas y roles

**¿Función o procedimiento?** Función: devuelve un valor y se usa dentro de una consulta (`SELECT fn_total_comprobante(5)`). Procedimiento: se invoca con `CALL`, hace una operación (puede no devolver nada) y en PostgreSQL puede manejar transacciones.

**IMMUTABLE vs. STABLE.** IMMUTABLE: mismo resultado para los mismos argumentos siempre (`fn_descuento_por_tipo`). STABLE: no modifica datos y es constante dentro de una sentencia, pero lee tablas o la fecha (`fn_antiguedad_anios` usa CURRENT_DATE: no puede ser IMMUTABLE).

**¿Qué es SECURITY DEFINER y por qué lo usan?** La función corre con los permisos de su dueño. La API no tiene permiso para escribir el stock; los triggers y procedimientos que lo mueven son SECURITY DEFINER, así que la API solo puede mover stock por los caminos que validan las reglas. Se fija `search_path` para que nadie inyecte una función con el mismo nombre.

**Vista vs. vista materializada.** La vista guarda la consulta (siempre actual). La materializada guarda el resultado (rápida, pero hay que refrescarla). Usamos `mv_ventas_mensuales_sala` porque recorrer 150.000 comprobantes en cada consulta del tablero es caro y el resultado cambia una vez por día.

**Roles.** Propietario (migraciones y carga), `bodegas_api` (la API, sin escritura de stock ni auditoría ni UPDATE de comprobantes) y `bodegas_lectura` (solo SELECT). Se revocan los privilegios de PUBLIC. Lo prueban los casos "ROL ..." de `db_tests.sql`.

---

## 8. Carga masiva

**¿Cómo lograron datos coherentes?** Simulando día por día: ingresos → depósito → transferencias → salas → ventas, siempre con stock disponible y fechas lógicas. Los importes con la misma fórmula que la base. Al final, 13 consultas de control dan 0.

**¿Qué hicieron con los triggers?** Los deshabilitamos (`DISABLE TRIGGER USER`) durante la carga histórica porque rechazarían datos históricos válidos (fechas viejas de transferencia, documentos ya procesados) y recalcular 150.000 cabeceras sería lento. Riesgos y mitigación: todo en una transacción (si falla, ni datos ni triggers deshabilitados), FK y CHECK siguen activos, y las consultas de control verifican lo que vigilaban los triggers.

**¿Por qué COPY?** Un comando transmite todas las filas en un flujo. Fila por fila con commit cada una implica un viaje de red y una escritura al WAL con espera por fila. Ver el benchmark en el reporte de carga.

**¿Reproducible?** Semilla fija en `random` y Faker + fecha de referencia. Lo verificamos con un hash MD5 de dos cargas.

---

## 9. Índices

**¿PostgreSQL indexa las FK?** No. Solo PK y UNIQUE. Por eso D4 (borrar 650 clientes) tardaba ~4 s: cada borrado verificaba la FK recorriendo los 150.000 comprobantes. Con el índice: ~17 ms.

**¿Por qué `(id_sala, fecha)` y no `(fecha, id_sala)`?** Igualdad primero, rango al final: las ventas de la sala 1 en el período quedan contiguas en el índice. Probamos el otro orden y lo descartamos (lee unas 6 veces más páginas).

**¿Qué es INCLUDE?** Agrega columnas a las hojas del índice sin ordenar por ellas: la consulta se resuelve con un Index Only Scan, sin leer la tabla.

**¿Qué es un índice parcial?** Indexa solo las filas que cumplen un WHERE (las transferencias pendientes): diminuto y siempre en memoria.

**¿Qué es BRIN y por qué sirve acá?** Guarda mínimo y máximo por bloque de páginas. Sirve cuando el orden físico sigue a la columna: las ventas se insertan en orden de fecha. Ocupa 24 kB contra ~1 MB de un B-tree.

**¿Por qué el planificador a veces no usa un índice?** Baja selectividad (61 % de los vinos son tintos: leer la tabla entera es más barato), columna dentro de una función (`EXTRACT(YEAR FROM fecha)`) o estadísticas viejas (correr ANALYZE).

**¿Cuál es el costo de un índice?** Espacio y escrituras más lentas (cada INSERT actualiza todos los índices de la tabla). Medido en el informe.

**Leer un plan.** `Seq Scan`: recorre toda la tabla. `Index Scan`: busca en el índice y va a la tabla. `Index Only Scan`: solo el índice. `Bitmap Heap Scan`: arma un mapa de páginas con el índice y las lee en orden. `actual time`: tiempo real; `rows`: filas; `Buffers: shared hit/read`: páginas leídas de memoria o de disco.

---

## 10. Consultas

Saber explicar al menos: división relacional (S2, S12a) con doble NOT EXISTS ("no existe un vino de la bodega que el cliente no haya comprado"); anti-join (S12b); por qué el LEFT JOIN con la condición en el ON (I1, S5); funciones de ventana (S11: `RANK() OVER (PARTITION BY ...)`, por qué el filtro va afuera); subconsulta correlacionada (S10); CTE que modifica datos (I2); `UPDATE` con CASE (U4). Ver `05_consultas_sql.md`.

---

## 11. API y front

**¿La API calcula algo?** No. La venta manda cliente, sala, vino y cantidad; la base completa todo. Procesar es `CALL sp_procesar_transferencia($1)`.

**¿Cómo evitan la inyección SQL?** Consultas parametrizadas: el texto viaja como parámetro, separado del SQL. Demostración: `GET /vinos?q=' OR 1=1; DROP TABLE vino; --` devuelve 0 resultados y la tabla sigue existiendo.

**¿Cómo traducen los errores?** Por SQLSTATE (`errors.js`): 23505 → 409, 23514 → 422, P0001 → 409 con la regla, etc. El mensaje es el de la base.

**¿Qué pasa si falla el segundo renglón de una venta?** Todo está en una transacción: ROLLBACK, no queda el comprobante ni se descuenta el stock del primer renglón. Lo prueba un test.

**¿Con qué rol se conecta?** `bodegas_api` (lo muestra `/salud`).

---

## 12. Qué mostrar en la demo (10 a 15 minutos)

1. `docker compose up --build` (o la URL de la nube) y `/salud` con el rol `bodegas_api`.
2. Catálogo con filtros → ficha de "Malbec Reserva 2021".
3. Nueva venta correcta → mostrar que el total lo calculó la base (y el descuento según el tipo de cliente).
4. Venta sin stock → mensaje RN-09 → mostrar en `psql` que no quedó el comprobante.
5. Transferencia: crear, agregar renglón, terminar, procesar → ver el stock en la sala. Intentar agregar un renglón después → RN-12.
6. Alta de vino con 60 + 30 → RN-05.
7. En `psql`: `EXPLAIN (ANALYZE, BUFFERS)` de S3 mostrando el Index Only Scan.
8. Si preguntan por concurrencia: dos `psql` con `FOR UPDATE` (pasos al final de `informes/etapa2_concurrencia.md`).

## 13. Cosas que pueden pedir modificar en vivo (y cómo)

- **Agregar una regla con CHECK** (por ejemplo, salario mínimo): `ALTER TABLE empleado ADD CONSTRAINT ck_salario_minimo CHECK (salario >= 500000);` Si hay filas que no cumplen, falla: se puede usar `NOT VALID` y luego `VALIDATE CONSTRAINT`.
- **Cambiar el descuento de un tipo**: modificar `fn_descuento_por_tipo` (solo afecta clientes nuevos; los existentes tienen su descuento guardado).
- **Agregar una columna al vino**: `ALTER TABLE vino ADD COLUMN ...`, actualizar el DAO y el OpenAPI.
- **Una consulta nueva**: escribirla en `psql`, mirar su plan, decidir si necesita índice.
- **Prohibir que un ingreso tenga vinos de otra bodega**: trigger BEFORE INSERT en `renglon_ingreso` que compare `vino.cuit_bodega` con `ingreso.cuit_bodega`.
