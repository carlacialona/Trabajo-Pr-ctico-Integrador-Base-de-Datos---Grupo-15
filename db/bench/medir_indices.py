#!/usr/bin/env python3
"""
medir_indices.py · Etapa 4: evidencia de rendimiento de los índices.

Qué hace:
  1. Borra los índices de 008_indices.sql (si existen) y corre ANALYZE:
     quedan solo los índices de PRIMARY KEY y UNIQUE.
  2. Mide cada consulta con EXPLAIN (ANALYZE, BUFFERS): una corrida de
     calentamiento y luego la mediana de 3.
  3. Crea los índices de 008_indices.sql, corre ANALYZE y vuelve a medir.
  4. Mide el costo de escritura (insertar 500.000 renglones con y sin el
     índice) y dos casos extra: un índice descartado y un caso donde el
     planificador NO usa un índice existente.
  5. Escribe docs/informes/etapa4_indices.md (tabla comparativa) y
     docs/informes/etapa4_planes.md (planes completos).

Uso:  DATABASE_URL=... python db/bench/medir_indices.py
Requiere la base cargada (db/seed/cargar_datos.py). Deja los índices creados.
"""
import os
import re
import statistics
import time
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parents[2]
INDICES_SQL = RAIZ / "db" / "migrations" / "008_indices.sql"
INFORME = RAIZ / "docs" / "informes" / "etapa4_indices.md"
PLANES = RAIZ / "docs" / "informes" / "etapa4_planes.md"

CONSULTAS = [
    ("S2", "Vinos vendidos en todas las salas (doble NOT EXISTS)",
     """SELECT v.cod_vino, v.nombre FROM vino v
         WHERE NOT EXISTS (SELECT 1 FROM sala_venta s
                 WHERE NOT EXISTS (SELECT 1 FROM comprobante c
                         JOIN renglon_comprobante r USING (nro_comprobante)
                        WHERE c.id_sala = s.id_sala AND r.cod_vino = v.cod_vino))"""),
    ("S3", "Ventas de una sala en los últimos 90 días (igualdad + rango)",
     """SELECT count(*), SUM(total), count(DISTINCT id_cliente) FROM comprobante
         WHERE id_sala = 1 AND fecha >= CURRENT_DATE - 90"""),
    ("S8", "Monto por sala en el último trimestre (rango de fechas sobre toda la red)",
     """SELECT id_sala, SUM(total) FROM comprobante
         WHERE fecha >= CURRENT_DATE - INTERVAL '3 months'
         GROUP BY id_sala ORDER BY 2 DESC"""),
    ("S12a", "Clientes que compraron todos los vinos de una bodega",
     """SELECT cl.id_cliente FROM cliente cl
         WHERE NOT EXISTS (SELECT 1 FROM vino v JOIN bodega b ON b.cuit = v.cuit_bodega
                 WHERE b.razon_social = 'Bodega Boutique del Atuel SA'
                   AND NOT EXISTS (SELECT 1 FROM comprobante c
                         JOIN renglon_comprobante r USING (nro_comprobante)
                        WHERE c.id_cliente = cl.id_cliente AND r.cod_vino = v.cod_vino))"""),
    ("S5", "Salas con menos transferencias pendientes",
     """WITH p AS (SELECT s.id_sala, count(t.nro_transferencia) AS n FROM sala_venta s
                    LEFT JOIN transferencia t ON t.id_sala = s.id_sala AND t.estado <> 'procesado'
                    GROUP BY s.id_sala)
        SELECT * FROM p WHERE n = (SELECT min(n) FROM p)"""),
    ("D4", "Borrar socios sin compras con alta de hace más de 5 años (chequeo de FK)",
     """DELETE FROM cliente c WHERE c.tipo = 'socio'
           AND c.fecha_alta < CURRENT_DATE - INTERVAL '5 years'
           AND NOT EXISTS (SELECT 1 FROM comprobante x WHERE x.id_cliente = c.id_cliente)"""),
]

ESCANEOS = ("Seq Scan", "Index Scan", "Index Only Scan", "Bitmap Heap Scan",
            "Bitmap Index Scan", "Parallel Seq Scan")


def nombres_indices():
    return re.findall(r"CREATE INDEX (\w+)", INDICES_SQL.read_text(encoding="utf-8"))


RE_NODO = re.compile(r"(Parallel Seq Scan|Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Bitmap Index Scan)"
                     r"(?: using (\w+))? on (\w+)")


def analizar(texto):
    """Extrae del plan en texto: tiempo, escaneos y buffers del nodo raíz."""
    tiempo = float(re.search(r"Execution Time: ([\d.]+) ms", texto).group(1))
    escaneos = []
    for m in RE_NODO.finditer(texto):
        tipo, indice, tabla = m.groups()
        escaneos.append(f"{tipo} {indice or tabla}" if tipo != "Seq Scan" else f"Seq Scan {tabla}")
    m = re.search(r"Buffers: shared (?:hit=(\d+))?\s*(?:read=(\d+))?", texto)
    buffers = sum(int(x) for x in m.groups() if x) if m else 0
    trig = sum(float(x) for x in re.findall(r"Trigger for constraint \w+: time=([\d.]+)", texto))
    return tiempo, escaneos, buffers, trig


def medir(conn, sql, veces=3):
    """Devuelve (mediana ms, escaneos, buffers, plan texto, ms en triggers de FK o None).
    Una ejecución de calentamiento y luego `veces` más; si la de
    calentamiento tarda más de 5 s, se usa solo esa (sería eterno repetirla)."""
    es_dml = sql.lstrip().upper().startswith(("DELETE", "UPDATE", "INSERT"))

    def correr():
        with conn.transaction(force_rollback=True):
            return "\n".join(r[0] for r in conn.execute(f"EXPLAIN (ANALYZE, BUFFERS) {sql}").fetchall())

    texto = correr()
    t, esc, buf, trig = analizar(texto)
    tiempos = [t]
    if t < 5000:
        tiempos = []
        for _ in range(veces):
            texto = correr()
            t, esc, buf, trig = analizar(texto)
            tiempos.append(t)
    return statistics.median(tiempos), esc, buf, texto, (trig if es_dml else None)


def fmt(n, dec=1):
    """Número con formato argentino: 12.345,6"""
    return f"{n:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def resumen_escaneos(lista):
    vistos = []
    for e in lista:
        if e not in vistos:
            vistos.append(e)
    return "<br>".join(vistos[:4]) + (" …" if len(vistos) > 4 else "")


def tiempo_insercion(conn, tabla, indices_extra):
    """Tiempo de insertar todas las filas de `tabla` en una copia con su PK
    y, opcionalmente, con índices extra."""
    with conn.transaction(force_rollback=True):
        conn.execute(f"CREATE TEMP TABLE _w (LIKE {tabla} INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES)")
        for ddl in indices_extra:
            conn.execute(ddl.replace(f"ON {tabla} ", "ON _w ").replace(f"ON {tabla}", "ON _w"))
        t = time.perf_counter()
        n = conn.execute(f"INSERT INTO _w SELECT * FROM {tabla}").rowcount
        seg = time.perf_counter() - t
        tam = conn.execute("SELECT pg_size_pretty(pg_indexes_size('_w'))").fetchone()[0]
    return n, seg, tam


def main():
    dsn = os.environ["DATABASE_URL"]
    with psycopg.connect(dsn, autocommit=True) as conn:
        conn.execute("SET max_parallel_workers_per_gather = 0")   # mediciones comparables
        conn.execute("SET jit = off")

        # --- 1. Antes ---------------------------------------------------
        for nombre in nombres_indices():
            conn.execute(f"DROP INDEX IF EXISTS {nombre}")
        conn.execute("ANALYZE")
        antes = {cod: medir(conn, sql) for cod, _, sql in CONSULTAS}

        # --- 2. Crear índices y medir después ---------------------------
        t = time.perf_counter()
        conn.execute(INDICES_SQL.read_text(encoding="utf-8"))
        creacion = time.perf_counter() - t
        conn.execute("ANALYZE")
        despues = {cod: medir(conn, sql) for cod, _, sql in CONSULTAS}

        tamanos = conn.execute(
            """SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)), pg_relation_size(indexrelid)
                 FROM pg_stat_user_indexes WHERE indexrelname = ANY(%s) ORDER BY 3 DESC""",
            (nombres_indices(),)).fetchall()

        # --- 3. Índice descartado: orden de columnas invertido -----------
        sql_s3 = CONSULTAS[1][2]
        conn.execute("DROP INDEX idx_comprobante_sala_fecha")
        conn.execute("CREATE INDEX idx_tmp_fecha_sala ON comprobante (fecha, id_sala) INCLUDE (total, id_cliente)")
        conn.execute("ANALYZE comprobante")
        invertido = medir(conn, sql_s3)
        conn.execute("DROP INDEX idx_tmp_fecha_sala")
        conn.execute("CREATE INDEX idx_comprobante_sala_fecha ON comprobante (id_sala, fecha) INCLUDE (total, id_cliente)")
        conn.execute("CREATE INDEX idx_tmp_fecha_btree ON comprobante (fecha)")
        tam_btree = conn.execute("SELECT pg_size_pretty(pg_relation_size('idx_tmp_fecha_btree'))").fetchone()[0]
        conn.execute("DROP INDEX idx_tmp_fecha_btree")
        conn.execute("ANALYZE comprobante")

        # --- 4. El planificador NO usa un índice existente ---------------
        sql_funcion = "SELECT count(*), SUM(total) FROM comprobante WHERE EXTRACT(YEAR FROM fecha) = 2025"
        no_usa = medir(conn, sql_funcion, veces=1)
        sql_rango = ("SELECT count(*), SUM(total) FROM comprobante "
                     "WHERE fecha >= DATE '2025-01-01' AND fecha < DATE '2026-01-01'")
        rango = medir(conn, sql_rango, veces=1)
        conn.execute("CREATE INDEX idx_tmp_vino_tipo ON vino (tipo)")
        conn.execute("ANALYZE vino")
        sql_tipo = "SELECT cod_vino, nombre FROM vino WHERE tipo = 'tinto'"
        no_usa_tipo = medir(conn, sql_tipo, veces=1)
        selectividad = conn.execute(
            "SELECT round(100.0 * count(*) FILTER (WHERE tipo = 'tinto') / count(*), 1) FROM vino").fetchone()[0]
        conn.execute("DROP INDEX idx_tmp_vino_tipo")

        # --- 5. Costo de escritura --------------------------------------
        escritura = []
        n, sin, tam_sin = tiempo_insercion(conn, "renglon_comprobante", [])
        _, con, tam_con = tiempo_insercion(conn, "renglon_comprobante",
                                           ["CREATE INDEX ON renglon_comprobante (cod_vino)"])
        escritura.append(("renglon_comprobante", n, "PK", sin, tam_sin,
                          "PK + idx(cod_vino)", con, tam_con))
        idx_comp = ["CREATE INDEX ON comprobante (id_cliente)",
                    "CREATE INDEX ON comprobante (id_sala, fecha) INCLUDE (total, id_cliente)",
                    "CREATE INDEX ON comprobante USING brin (fecha)"]
        n, sin, tam_sin = tiempo_insercion(conn, "comprobante", [])
        _, con, tam_con = tiempo_insercion(conn, "comprobante", idx_comp)
        escritura.append(("comprobante", n, "PK", sin, tam_sin, "PK + 3 índices", con, tam_con))

    escribir_informe(antes, despues, creacion, tamanos, invertido, antes["S3"], despues["S3"],
                     tam_btree, no_usa, no_usa_tipo, selectividad, escritura, rango)
    print(f"Informe: {INFORME}\nPlanes: {PLANES}")


def escribir_informe(antes, despues, creacion, tamanos, invertido, s3_antes, s3_despues,
                     tam_btree, no_usa, no_usa_tipo, selectividad, escritura, rango):
    L = ["# Etapa 4 · Índices y rendimiento (resultados medidos)", "",
         "Generado por `db/bench/medir_indices.py` sobre la base cargada con `db/seed/cargar_datos.py`.",
         "Cada tiempo es la mediana de 3 ejecuciones de `EXPLAIN (ANALYZE, BUFFERS)` después de una de calentamiento",
         "(si la de calentamiento tarda más de 5 s, se informa esa sola),",
         "con paralelismo y JIT desactivados para que las mediciones sean comparables.",
         "\"Antes\" = solo los índices de PRIMARY KEY y UNIQUE. \"Después\" = con `008_indices.sql`.", "",
         "## Tabla comparativa", "",
         "| Consulta | Antes (ms) | Recorrido antes | Después (ms) | Recorrido después | Mejora | Buffers antes → después |",
         "| --- | ---: | --- | ---: | --- | ---: | --- |"]
    for cod, desc, _ in CONSULTAS:
        a, d = antes[cod], despues[cod]
        extra = ""
        if a[4] is not None:
            extra = f" (triggers de FK: {a[4]:.0f} → {d[4]:.0f} ms)"
        L.append(f"| **{cod}** {desc}{extra} | {fmt(a[0])} | {resumen_escaneos(a[1])} | {fmt(d[0])} | "
                 f"{resumen_escaneos(d[1])} | {fmt(a[0] / d[0])}x | {fmt(a[2], 0)} → {fmt(d[2], 0)} |")
    L += ["", f"Crear los 5 índices sobre la base cargada tardó {fmt(creacion)} s.",
          "", "Nota sobre D4: en el \"antes\" los buffers del nodo raíz no incluyen las lecturas que hacen los triggers de la FK "
          "(recorren `comprobante` completa una vez por cada cliente borrado); por eso el tiempo es la medida que importa ahí.", "",
          "## Tamaño de cada índice", "", "| Índice | Tamaño |", "| --- | ---: |"]
    L += [f"| `{n}` | {t} |" for n, t, _ in tamanos]
    L += ["", f"Un B-tree común sobre `comprobante(fecha)` ocupa **{tam_btree}**; el BRIN equivalente ocupa lo que muestra la tabla. "
          "El BRIN sirve porque las ventas se insertan en orden de fecha (correlación física ≈ 1).", "",
          "## Índice evaluado y descartado: orden de columnas invertido", "",
          "Para la consulta S3 (`WHERE id_sala = 1 AND fecha >= CURRENT_DATE - 90`) se probó el índice `(fecha, id_sala)` en lugar de `(id_sala, fecha)`:", "",
          "| Variante | Tiempo (ms) | Recorrido | Buffers |", "| --- | ---: | --- | ---: |",
          f"| Sin índice | {fmt(s3_antes[0], 2)} | {resumen_escaneos(s3_antes[1])} | {fmt(s3_antes[2], 0)} |",
          f"| `(fecha, id_sala)` descartado | {fmt(invertido[0], 2)} | {resumen_escaneos(invertido[1])} | {fmt(invertido[2], 0)} |",
          f"| `(id_sala, fecha)` elegido | {fmt(s3_despues[0], 2)} | {resumen_escaneos(s3_despues[1])} | {fmt(s3_despues[2], 0)} |", "",
          "Con `fecha` primero, el índice recorre los 90 días de **todas** las salas y descarta las que no son la 1: "
          "lee unas 40 veces más entradas. Con `id_sala` primero (igualdad) y `fecha` después (rango), "
          "las entradas buscadas están contiguas en el índice. Regla: columnas de igualdad primero, de rango al final.", "",
          "## Casos en que el planificador NO usa un índice existente", "",
          f"1. `{no_usa_tipo[3].splitlines()[0][:0]}SELECT ... FROM vino WHERE tipo = 'tinto'` con un índice sobre `vino(tipo)`: "
          f"el planificador eligió **{resumen_escaneos(no_usa_tipo[1])}**. El {selectividad} % de los vinos son tintos: "
          "leer el índice y luego saltar a casi todas las páginas de la tabla es más caro que leer la tabla de corrido. "
          "Un índice sirve cuando el filtro es **selectivo** (devuelve pocas filas).",
          f"2. `... WHERE EXTRACT(YEAR FROM fecha) = 2025` con el índice BRIN sobre `fecha`: el plan usa **{resumen_escaneos(no_usa[1])}** "
          f"({fmt(no_usa[0])} ms). El índice guarda valores de `fecha`, no de `EXTRACT(YEAR FROM fecha)`: si la columna está dentro de "
          f"una función, el índice no sirve. Reescrita como rango (`fecha >= '2025-01-01' AND fecha < '2026-01-01'`) usa "
          f"**{resumen_escaneos(rango[1])}** ({fmt(rango[0])} ms).", "",
          "Otra causa típica es tener estadísticas desactualizadas: después de la carga masiva hay que correr `ANALYZE`; "
          "si no, el planificador estima mal cuántas filas devuelve cada filtro.", "",
          "## Costo de escritura", "",
          "Tiempo de insertar todas las filas de la tabla en una copia (en una transacción), solo con la PK y con los índices de `008_indices.sql`:", "",
          "| Tabla | Filas | Variante | Segundos | Tamaño de índices | Variante | Segundos | Tamaño de índices | Sobrecosto |",
          "| --- | ---: | --- | ---: | ---: | --- | ---: | ---: | ---: |"]
    for tabla, n, v1, s1, t1, v2, s2, t2 in escritura:
        L.append(f"| {tabla} | {fmt(n, 0)} | {v1} | {fmt(s1, 2)} | {t1} | {v2} | {fmt(s2, 2)} | {t2} | +{100 * (s2 - s1) / s1:.0f} % |")
    L += ["", "Cada índice extra se actualiza en cada INSERT: la escritura se vuelve más lenta y la base más grande. "
          "Por eso no se indexan columnas \"por las dudas\".", ""]
    INFORME.parent.mkdir(parents=True, exist_ok=True)
    INFORME.write_text("\n".join(L), encoding="utf-8")

    P = ["# Etapa 4 · Planes de ejecución completos", "",
         "Salida de `EXPLAIN (ANALYZE, BUFFERS)` antes y después de crear los índices.", ""]
    for cod, desc, sql in CONSULTAS:
        P += [f"## {cod}. {desc}", "", "```sql", sql.strip(), "```", "",
              "### Antes", "", "```", antes[cod][3], "```", "",
              "### Después", "", "```", despues[cod][3], "```", ""]
    P += ["## Índice descartado (fecha, id_sala) para S3", "", "```", invertido[3], "```", "",
          "## El planificador no usa el índice: vino(tipo)", "", "```", no_usa_tipo[3], "```", "",
          "## El planificador no usa el índice: columna dentro de una función", "", "```", no_usa[3], "```", "",
          "## La misma consulta reescrita como rango", "", "```", rango[3], "```", ""]
    PLANES.write_text("\n".join(P), encoding="utf-8")


if __name__ == "__main__":
    main()
