#!/usr/bin/env python3
"""
demo_concurrencia.py · Etapa 2: "la última botella".

Dos sesiones (dos conexiones reales a PostgreSQL) intentan vender la
última botella de un vino en la misma sala al mismo tiempo. Se muestran
tres escenarios y se registra, paso a paso, qué ve y qué hace cada sesión:

  1. SIN bloqueo, con el patrón "leo el stock y escribo el valor calculado
     en la aplicación" -> se vende la misma botella dos veces (lost update).
  2. CON SELECT ... FOR UPDATE -> la sesión B espera a que A termine, lee 0
     y rechaza la venta.
  3. El sistema real: dos INSERT de renglón de venta. El trigger
     trg_renglon_comprobante_antes hace el FOR UPDATE por nosotros: la
     segunda venta espera y luego falla con RN-09.

Nivel de aislamiento: READ COMMITTED (el de PostgreSQL por defecto).

Uso:  DATABASE_URL=... python db/bench/demo_concurrencia.py
Todo se hace sobre datos de prueba creados por el script y se borra al final.
Escribe docs/informes/etapa2_concurrencia.md.
"""
import os
import threading
import time
from pathlib import Path

import psycopg

RAIZ = Path(__file__).resolve().parents[2]
INFORME = RAIZ / "docs" / "informes" / "etapa2_concurrencia.md"
T0 = time.perf_counter()
LOG = []
LOCK = threading.Lock()


def log(sesion, texto):
    with LOCK:
        LOG.append((time.perf_counter() - T0, sesion, texto))


def preparar(dsn):
    """Crea un vino de prueba con 1 botella en la sala 1 (por el circuito real)."""
    with psycopg.connect(dsn) as c:
        cuit = c.execute("SELECT cuit FROM bodega ORDER BY cuit LIMIT 1").fetchone()[0]
        cepa = c.execute("SELECT id_cepa FROM cepa LIMIT 1").fetchone()[0]
        transp = c.execute("SELECT cod_transporte FROM transportista LIMIT 1").fetchone()[0]
        cliente = c.execute("SELECT id_cliente FROM cliente WHERE tipo = 'socio' LIMIT 1").fetchone()[0]
        vino = c.execute(
            """INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
               VALUES ('Vino Demo Concurrencia', 'tinto', 2024, 750, 14, 10000, %s) RETURNING cod_vino""",
            (cuit,)).fetchone()[0]
        c.execute("INSERT INTO composicion VALUES (%s, %s, 100)", (vino, cepa))
        ing = c.execute("INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES (%s, %s) RETURNING cod_ingreso",
                        (transp, cuit)).fetchone()[0]
        c.execute("INSERT INTO renglon_ingreso VALUES (%s, %s, 1)", (ing, vino))
        c.execute("UPDATE ingreso SET estado = 'terminado' WHERE cod_ingreso = %s", (ing,))
        c.execute("CALL sp_procesar_ingreso(%s)", (ing,))
        tr = c.execute("INSERT INTO transferencia (id_sala) VALUES (1) RETURNING nro_transferencia").fetchone()[0]
        c.execute("INSERT INTO renglon_transferencia VALUES (%s, %s, 1)", (tr, vino))
        c.execute("UPDATE transferencia SET estado = 'terminado' WHERE nro_transferencia = %s", (tr,))
        c.execute("CALL sp_procesar_transferencia(%s)", (tr,))
        return vino, cliente, ing, tr


def reponer(dsn, vino):
    """Deja el stock en 1 para el siguiente escenario (como dueño, solo para la demo)."""
    with psycopg.connect(dsn) as c:
        c.execute("UPDATE stock_sala SET cantidad = 1 WHERE id_sala = 1 AND cod_vino = %s", (vino,))


def stock(dsn, vino):
    with psycopg.connect(dsn) as c:
        return c.execute("SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = %s", (vino,)).fetchone()[0]


def escenario_1(dsn, vino):
    """Sin bloqueo: leer, calcular en la aplicación y escribir el valor."""
    barrera = threading.Barrier(2)
    vendidas = []

    def sesion(nombre, demora):
        with psycopg.connect(dsn) as c:
            c.execute("BEGIN")
            log(nombre, "BEGIN")
            q = c.execute("SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = %s", (vino,)).fetchone()[0]
            log(nombre, f"SELECT cantidad (sin FOR UPDATE) -> {q}")
            barrera.wait()                     # las dos ya leyeron 1
            time.sleep(demora)
            if q >= 1:
                c.execute("UPDATE stock_sala SET cantidad = %s WHERE id_sala = 1 AND cod_vino = %s", (q - 1, vino))
                log(nombre, f"hay stock según lo leído: UPDATE ... SET cantidad = {q - 1}")
                c.execute("COMMIT")
                log(nombre, "COMMIT · venta registrada")
                vendidas.append(nombre)

    hilos = [threading.Thread(target=sesion, args=("A", 0)), threading.Thread(target=sesion, args=("B", 0.3))]
    [h.start() for h in hilos]
    [h.join() for h in hilos]
    return vendidas


def escenario_2(dsn, vino):
    """Con SELECT ... FOR UPDATE."""
    vendidas = []
    a_bloqueo = threading.Event()

    def sesion(nombre):
        with psycopg.connect(dsn) as c:
            c.execute("BEGIN")
            log(nombre, "BEGIN")
            if nombre == "B":
                a_bloqueo.wait()
                log(nombre, "SELECT cantidad ... FOR UPDATE -> queda ESPERANDO (A tiene la fila bloqueada)")
            q = c.execute("SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = %s FOR UPDATE",
                          (vino,)).fetchone()[0]
            log(nombre, f"SELECT cantidad ... FOR UPDATE -> {q}")
            if nombre == "A":
                a_bloqueo.set()
                time.sleep(1.0)               # A tarda en confirmar; B espera
            if q >= 1:
                c.execute("UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 1 AND cod_vino = %s", (vino,))
                log(nombre, "UPDATE ... SET cantidad = cantidad - 1")
                c.execute("COMMIT")
                log(nombre, "COMMIT · venta registrada")
                vendidas.append(nombre)
            else:
                c.execute("ROLLBACK")
                log(nombre, "no hay stock: ROLLBACK · venta rechazada")

    hilos = [threading.Thread(target=sesion, args=(n,)) for n in ("A", "B")]
    [h.start() for h in hilos]
    [h.join() for h in hilos]
    return vendidas


def escenario_3(dsn, vino, cliente):
    """El sistema real: INSERT de renglón; el trigger hace el bloqueo."""
    vendidas = []
    a_inserto = threading.Event()

    def sesion(nombre):
        with psycopg.connect(dsn) as c:
            c.execute("BEGIN")
            log(nombre, "BEGIN")
            nro = c.execute("INSERT INTO comprobante (id_cliente, id_sala) VALUES (%s, 1) RETURNING nro_comprobante",
                            (cliente,)).fetchone()[0]
            if nombre == "B":
                a_inserto.wait()
                log(nombre, "INSERT renglón (1 botella) -> el trigger pide FOR UPDATE y queda ESPERANDO")
            try:
                c.execute("INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES (%s, %s, 1)",
                          (nro, vino))
                log(nombre, f"INSERT renglón (1 botella) en el comprobante {nro} -> OK, el trigger descontó el stock")
                if nombre == "A":
                    a_inserto.set()
                    time.sleep(1.0)
                c.execute("COMMIT")
                log(nombre, "COMMIT · venta registrada")
                vendidas.append(nombre)
            except psycopg.Error as e:
                log(nombre, f"ERROR [{e.sqlstate}] {e.diag.message_primary}")
                c.execute("ROLLBACK")
                log(nombre, "ROLLBACK · el comprobante tampoco queda")

    hilos = [threading.Thread(target=sesion, args=(n,)) for n in ("A", "B")]
    hilos[0].start()
    time.sleep(0.1)
    hilos[1].start()
    [h.join() for h in hilos]
    return vendidas


def limpiar(dsn, vino, ing, tr):
    with psycopg.connect(dsn) as c:
        c.execute("DELETE FROM comprobante WHERE nro_comprobante IN "
                  "(SELECT nro_comprobante FROM renglon_comprobante WHERE cod_vino = %s)", (vino,))
        c.execute("DELETE FROM ingreso WHERE cod_ingreso = %s", (ing,))
        c.execute("DELETE FROM transferencia WHERE nro_transferencia = %s", (tr,))
        c.execute("DELETE FROM vino WHERE cod_vino = %s", (vino,))


def tabla(desde, hasta):
    filas = [f for f in LOG[desde:hasta]]
    L = ["| t (s) | Sesión A | Sesión B |", "| ---: | --- | --- |"]
    for t, s, texto in filas:
        L.append(f"| {t - filas[0][0]:.2f} | {texto if s == 'A' else ''} | {texto if s == 'B' else ''} |")
    return L


def main():
    dsn = os.environ["DATABASE_URL"]
    vino, cliente, ing, tr = preparar(dsn)
    try:
        i0 = len(LOG)
        v1 = escenario_1(dsn, vino)
        s1 = stock(dsn, vino)
        i1 = len(LOG)
        reponer(dsn, vino)
        v2 = escenario_2(dsn, vino)
        s2 = stock(dsn, vino)
        i2 = len(LOG)
        reponer(dsn, vino)
        v3 = escenario_3(dsn, vino, cliente)
        s3 = stock(dsn, vino)
        i3 = len(LOG)
    finally:
        limpiar(dsn, vino, ing, tr)

    L = ["# Etapa 2 · Demostración de concurrencia: la última botella", "",
         "Generado por `db/bench/demo_concurrencia.py`: dos conexiones reales a PostgreSQL, en paralelo, "
         "intentan vender la última botella de un vino en la sala 1. Nivel de aislamiento: **READ COMMITTED** "
         "(el predeterminado de PostgreSQL: cada sentencia ve lo confirmado hasta el momento en que empieza).", "",
         "## 1. Sin bloqueo: leer, calcular en la aplicación y escribir", ""]
    L += tabla(i0, i1)
    L += ["", f"Resultado: ventas registradas = **{len(v1)}** ({', '.join(v1)}), stock final = **{s1}**.", "",
          "Las dos sesiones leyeron `1` antes de que la otra escribiera, las dos creyeron que había stock y las dos "
          "escribieron `0`. Se vendieron **dos botellas con una sola en stock** y el stock quedó en 0 en vez de -1: "
          "la segunda escritura pisó a la primera (*lost update*). READ COMMITTED no lo evita, porque cada SELECT "
          "es correcto en su momento; el problema es decidir con un dato que ya cambió.", "",
          "## 2. Con `SELECT ... FOR UPDATE`", ""]
    L += tabla(i1, i2)
    L += ["", f"Resultado: ventas registradas = **{len(v2)}** ({', '.join(v2)}), stock final = **{s2}**.", "",
          "`FOR UPDATE` bloquea la fila: la sesión B no puede leerla para modificarla hasta que A termine. "
          "Cuando A confirma, B recién obtiene la fila con el valor nuevo (0) y rechaza la venta.", "",
          "## 3. El sistema real: el trigger de RN-09 hace el bloqueo", ""]
    L += tabla(i2, i3)
    L += ["", f"Resultado: ventas registradas = **{len(v3)}** ({', '.join(v3)}), stock final = **{s3}**.", "",
          "La API no hace `SELECT ... FOR UPDATE`: solo inserta el renglón. El trigger "
          "`trg_renglon_comprobante_antes` bloquea la fila de `stock_sala` con `FOR UPDATE` antes de validar el "
          "stock, así que la regla se cumple aunque alguien venda desde `psql` sin pasar por la API. Además el "
          "`CHECK (cantidad >= 0)` es una segunda barrera: aunque el trigger no existiera, un "
          "`UPDATE ... SET cantidad = cantidad - 1` sobre 0 fallaría.", "",
          "## Cómo reproducirlo a mano con dos terminales `psql`", "",
          "1. En ambas: `BEGIN;`",
          "2. En A: `SELECT cantidad FROM stock_sala WHERE id_sala = 1 AND cod_vino = <vino> FOR UPDATE;` (devuelve 1)",
          "3. En B: la misma consulta. **Queda esperando.**",
          "4. En A: `UPDATE stock_sala SET cantidad = cantidad - 1 WHERE id_sala = 1 AND cod_vino = <vino>; COMMIT;`",
          "5. En B: recién ahora devuelve 0 y la venta se rechaza.", "",
          "Sin `FOR UPDATE`, en el paso 3 B devuelve 1 enseguida y las dos sesiones venden.", ""]
    INFORME.parent.mkdir(parents=True, exist_ok=True)
    INFORME.write_text("\n".join(L), encoding="utf-8")
    print("\n".join(L))


if __name__ == "__main__":
    main()
