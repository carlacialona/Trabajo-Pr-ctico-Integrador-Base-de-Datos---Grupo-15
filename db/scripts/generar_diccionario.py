#!/usr/bin/env python3
"""
generar_diccionario.py · Genera docs/diccionario_datos.md leyendo el
catálogo de PostgreSQL (tipos, nulos, valores por defecto, restricciones y
los COMMENT ON de 009_comentarios.sql). Así el diccionario siempre coincide
con el esquema físico.

Uso:  DATABASE_URL=... python db/scripts/generar_diccionario.py
"""
import os
from collections import defaultdict
from pathlib import Path

import psycopg

SALIDA = Path(__file__).resolve().parents[2] / "docs" / "diccionario_datos.md"

TABLAS = """
SELECT c.relname, obj_description(c.oid, 'pg_class')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'r'
 ORDER BY c.oid
"""

COLUMNAS = """
SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
       pg_get_expr(d.adbin, d.adrelid), a.attidentity, col_description(c.oid, a.attnum),
       t.typtype, format_type(t.typbasetype, t.typtypmod)
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_type t ON t.oid = a.atttypid
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
 WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
 ORDER BY c.relname, a.attnum
"""

RESTRICCIONES = """
SELECT c.relname, k.conname, k.contype, pg_get_constraintdef(k.oid),
       ARRAY(SELECT a.attname FROM unnest(k.conkey) u(n) JOIN pg_attribute a
              ON a.attrelid = k.conrelid AND a.attnum = u.n)
  FROM pg_constraint k
  JOIN pg_class c ON c.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
 ORDER BY c.relname, k.contype, k.conname
"""

TIPOS = """
SELECT t.typname, string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
  JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE n.nspname = 'public'
 GROUP BY t.typname ORDER BY t.typname
"""

DOMINIOS = """
SELECT t.typname, format_type(t.typbasetype, t.typtypmod),
       (SELECT string_agg(pg_get_constraintdef(k.oid), ' ') FROM pg_constraint k WHERE k.contypid = t.oid)
  FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
 WHERE n.nspname = 'public' AND t.typtype = 'd'
 ORDER BY t.typname
"""


def main():
    with psycopg.connect(os.environ["DATABASE_URL"]) as c:
        tablas = c.execute(TABLAS).fetchall()
        columnas = defaultdict(list)
        for fila in c.execute(COLUMNAS).fetchall():
            columnas[fila[0]].append(fila[1:])
        restr = defaultdict(list)
        for tabla, nombre, tipo, definicion, cols in c.execute(RESTRICCIONES).fetchall():
            restr[tabla].append((nombre, tipo, definicion, cols))
        tipos = c.execute(TIPOS).fetchall()
        dominios = c.execute(DOMINIOS).fetchall()

    L = ["# Diccionario de datos", "",
         "Generado automáticamente desde el catálogo de PostgreSQL por `db/scripts/generar_diccionario.py` "
         "(tipos, nulos, valores por defecto y restricciones reales; descripciones de `009_comentarios.sql`).", "",
         "## Tipos enumerados", "", "| Tipo | Valores |", "| --- | --- |"]
    L += [f"| `{t}` | {v} |" for t, v in tipos]
    L += ["", "## Dominios", "", "| Dominio | Tipo base | Restricción |", "| --- | --- | --- |"]
    L += [f"| `{d}` | `{b}` | {('`' + r + '`') if r else '— (la positividad se controla con CHECK en cada columna)'} |" for d, b, r in dominios]
    L += ["", "## Tablas", ""]

    for tabla, descripcion in tablas:
        pk = set()
        fk = defaultdict(list)
        uk = defaultdict(list)
        for nombre, tipo, definicion, cols in restr[tabla]:
            for col in cols:
                if tipo == "p":
                    pk.add(col)
                elif tipo == "f":
                    destino = definicion.split("REFERENCES ")[1].split(")")[0] + ")"
                    accion = " ".join(p for p in ["ON DELETE " + definicion.split("ON DELETE ")[1].split(" ON")[0]
                                                  if "ON DELETE" in definicion else "ON DELETE NO ACTION",
                                                  "ON UPDATE CASCADE" if "ON UPDATE CASCADE" in definicion else ""] if p)
                    fk[col].append(f"FK → {destino} {accion}")
                elif tipo == "u":
                    uk[col].append(f"UNIQUE ({', '.join(cols)})")
        L += [f"### `{tabla}`", "", descripcion or "", "",
              "| Columna | Tipo | Nulo | Por defecto | Claves | Descripción |",
              "| --- | --- | :-: | --- | --- | --- |"]
        for col, tipo, notnull, defecto, identidad, desc, typtype, base in columnas[tabla]:
            if identidad:
                defecto = "IDENTITY (" + ("ALWAYS" if identidad == "a" else "BY DEFAULT") + ")"
            claves = (["PK"] if col in pk else []) + fk.get(col, []) + uk.get(col, [])
            tipo_txt = f"`{tipo}`" + (f" (dominio sobre `{base}`)" if typtype == "d" else "")
            L.append(f"| `{col}` | {tipo_txt} | {'no' if notnull else 'sí'} | "
                     f"{('`' + defecto + '`') if defecto else ''} | {'<br>'.join(claves)} | {desc or ''} |")
        checks = [(n, d) for n, t, d, _ in restr[tabla] if t == "c"]
        if checks:
            L += ["", "Restricciones CHECK:", ""]
            L += [f"- `{n}`: `{d}`" for n, d in checks]
        L.append("")

    SALIDA.write_text("\n".join(L), encoding="utf-8")
    print(f"Diccionario generado en {SALIDA}")


if __name__ == "__main__":
    main()
