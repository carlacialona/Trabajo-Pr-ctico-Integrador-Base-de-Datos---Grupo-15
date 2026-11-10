#!/usr/bin/env python3
"""
cargar_datos.py · Etapa 3: carga masiva reproducible de Bodegas del Atuel.

Uso:
    python cargar_datos.py                      # usa DATABASE_URL
    python cargar_datos.py --escala 0.1         # carga reducida (nube gratuita)
    python cargar_datos.py --benchmark          # además mide fila a fila vs lotes
    python cargar_datos.py --forzar             # vacía las tablas antes de cargar

Variables de entorno:
    DATABASE_URL        cadena de conexión con el rol PROPIETARIO (no el de la API).
    SEMILLA             semilla aleatoria (por defecto 2026).
    FECHA_REFERENCIA    fecha "de hoy" para generar el historial (AAAA-MM-DD).
                        Por defecto es la fecha actual. Dos ejecuciones con la
                        misma SEMILLA y la misma FECHA_REFERENCIA generan
                        exactamente los mismos datos.

Decisiones (ver docs/informes/etapa3_carga.md):
  * Los catálogos (departamentos, localidades, cepas, maridajes) salen de CSV.
  * El resto se genera con random + Faker con semilla fija.
  * El historial se SIMULA en orden cronológico: ingresos -> depósito ->
    transferencias -> salas -> ventas. Así el stock nunca es negativo y las
    fechas son lógicas (una venta solo usa vino que ya llegó a la sala).
  * Los importes (precio, descuento, subtotales, totales) se calculan con la
    MISMA fórmula que fn_subtotal_renglon, y las consultas de control lo
    verifican al final.
  * Durante la carga histórica se deshabilitan los triggers de usuario
    (ALTER TABLE ... DISABLE TRIGGER USER) porque:
      - las fechas de transferencia son históricas (el trigger forzaría hoy),
      - los documentos ya nacen 'procesado' (el trigger lo prohíbe),
      - recalcular 150.000 cabeceras fila por fila sería muy lento.
    Las FK y los CHECK NO se deshabilitan: siguen validando cada fila.
    Todo ocurre en UNA transacción: si algo falla, no queda nada a medias
    (ni datos ni triggers deshabilitados).
  * Se usa COPY (por lotes), no INSERT fila por fila.
"""
import argparse
import bisect
import csv
import io
import os
import random
import sys
import time
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import psycopg
from faker import Faker

DIR = Path(__file__).resolve().parent
CATALOGOS = DIR / "catalogos"

# Tablas con triggers de usuario que se deshabilitan durante la carga.
TABLAS_CON_TRIGGERS = [
    "cliente", "vino", "composicion", "comprobante", "renglon_comprobante",
    "ingreso", "renglon_ingreso", "transferencia", "renglon_transferencia",
]

# Orden de carga según las dependencias de las FK (primero las que no
# dependen de ninguna). El mismo orden, invertido, sirve para vaciar.
ORDEN_CARGA = [
    "provincia", "departamento", "localidad", "sala_venta", "empleado",
    "cepa", "maridaje", "bodega", "transportista", "transportista_localidad",
    "finca", "parcela", "lote_uva", "analisis_calidad",
    "vino", "composicion", "vino_maridaje",
    "cliente", "distribuidor", "exportador", "permiso_exportacion",
    "ingreso", "renglon_ingreso", "transferencia", "renglon_transferencia",
    "stock_deposito", "stock_sala",
    "comprobante", "renglon_comprobante",
]

DOS = Decimal("0.01")


def subtotal_renglon(cantidad, precio, porcentaje):
    """Misma fórmula que fn_subtotal_renglon en la base."""
    return (cantidad * precio * (1 - porcentaje / Decimal(100))).quantize(DOS, ROUND_HALF_UP)


def cuit_valido(rng, prefijo):
    """Genera un CUIT de 11 dígitos con dígito verificador correcto."""
    while True:
        cuerpo = f"{prefijo}{rng.randint(10_000_000, 99_999_999)}"
        pesos = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
        resto = sum(int(d) * p for d, p in zip(cuerpo, pesos)) % 11
        dv = 11 - resto
        if dv == 11:
            dv = 0
        if dv == 10:
            continue  # ese cuerpo no tiene CUIT válido con este prefijo
        return f"{cuerpo}{dv}"


def leer_csv(nombre):
    with open(CATALOGOS / nombre, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def fecha_aleatoria(rng, desde, hasta):
    return desde + timedelta(days=rng.randint(0, (hasta - desde).days))


class Generador:
    def __init__(self, semilla, escala, hoy):
        self.rng = random.Random(semilla)
        self.fake = Faker("es_AR")
        self.fake.seed_instance(semilla)
        self.escala = escala
        self.hoy = hoy
        self.inicio = hoy - timedelta(days=6 * 365)       # historial de 6 años
        self.t = {nombre: [] for nombre in ORDEN_CARGA}   # filas por tabla
        self.cuits = set()

    def n(self, cantidad, minimo=1):
        return max(minimo, int(round(cantidad * self.escala)))

    def nuevo_cuit(self, prefijo):
        while True:
            c = cuit_valido(self.rng, prefijo)
            if c not in self.cuits:
                self.cuits.add(c)
                return c

    # ------------------------------------------------------------------
    # Catálogos reales (CSV)
    # ------------------------------------------------------------------
    def catalogos(self):
        deptos = leer_csv("departamentos.csv")
        provincias = sorted({d["provincia"] for d in deptos})
        self.id_provincia = {p: i + 1 for i, p in enumerate(provincias)}
        self.t["provincia"] = [(i, p) for p, i in self.id_provincia.items()]

        self.id_depto = {}
        for i, d in enumerate(deptos, start=1):
            self.id_depto[d["nombre"]] = i
            self.t["departamento"].append((i, d["nombre"], self.id_provincia[d["provincia"]]))

        self.localidades = []
        for i, l in enumerate(leer_csv("localidades.csv"), start=1):
            self.t["localidad"].append(
                (i, l["nombre"], l["codigo_postal"], self.id_depto[l["departamento"]],
                 l["encargado_regional"]))
            self.localidades.append((i, l["nombre"], l["departamento"]))
        self.id_localidad = {nombre: i for i, nombre, _ in self.localidades}

        self.cepas = []
        for i, c in enumerate(leer_csv("cepas.csv"), start=1):
            self.t["cepa"].append((i, c["nombre"], c["tipo"]))
            self.cepas.append((i, c["nombre"], c["tipo"]))
        self.id_cepa = {nombre: i for i, nombre, _ in self.cepas}

        for i, m in enumerate(leer_csv("maridajes.csv"), start=1):
            self.t["maridaje"].append((i, m["nombre"], Decimal(m["temperatura_servicio"])))
        self.id_maridaje = {m[1]: m[0] for m in self.t["maridaje"]}

    # ------------------------------------------------------------------
    # Salas y empleados
    # ------------------------------------------------------------------
    def salas_y_empleados(self):
        rng = self.rng
        # Localidades con más salas: las cabeceras de departamento.
        pesos = {"Mendoza": 5, "Godoy Cruz": 3, "San Rafael": 5, "Maipú": 3,
                 "Luján de Cuyo": 3, "General Alvear": 2, "San Martín": 2, "Tunuyán": 2}
        cant_salas = self.n(40, 6)
        dias = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        self.salas = []
        loc_ids = [l[0] for l in self.localidades]
        loc_pesos = [pesos.get(l[1], 1) for l in self.localidades]
        for id_sala in range(1, cant_salas + 1):
            # Las primeras salas cubren localidades clave (San Rafael, Alvear...)
            if id_sala == 1:
                loc = self.id_localidad["San Rafael"]
            elif id_sala == 2:
                loc = self.id_localidad["General Alvear"]
            elif id_sala == 3:
                loc = self.id_localidad["Mendoza"]
            else:
                loc = rng.choices(loc_ids, loc_pesos)[0]
            dia = rng.choices(dias, [3, 1, 3, 1, 1, 1, 2])[0]
            self.t["sala_venta"].append(
                (id_sala, self.fake.street_name(), rng.randint(10, 4500), dia, loc))
            # Popularidad de la sala: algunas venden mucho más que otras.
            self.salas.append((id_sala, rng.uniform(0.4, 2.0)))

        for _ in range(self.n(150, 15)):
            sala = rng.randint(1, cant_salas)
            ingreso = fecha_aleatoria(rng, self.hoy - timedelta(days=15 * 365),
                                      self.hoy - timedelta(days=30))
            salario = Decimal(rng.randrange(850_000, 2_600_000, 500))
            self.t["empleado"].append(
                (self.nuevo_cuit(rng.choice(["20", "27"])),
                 f"{self.fake.last_name()}, {self.fake.first_name()}",
                 ingreso, salario, sala))

    # ------------------------------------------------------------------
    # Bodegas y transportistas
    # ------------------------------------------------------------------
    def bodegas_y_transporte(self):
        rng = self.rng
        sufijos = ["Bodega", "Bodegas", "Viñedos", "Finca", "Cava"]
        usados = set()
        self.bodegas = []
        for _ in range(self.n(12, 4)):
            while True:
                nombre = f"{rng.choice(sufijos)} {self.fake.last_name()} {rng.choice(['SA', 'SRL', 'SAS'])}"
                if nombre not in usados:
                    usados.add(nombre)
                    break
            cuit = self.nuevo_cuit("30")
            self.t["bodega"].append((cuit, nombre, self.fake.street_address() + ", Mendoza"))
            self.bodegas.append(cuit)
        # Una bodega boutique con solo 3 vinos (consulta S12: clientes que
        # compraron todos los vinos de una bodega).
        cuit = self.nuevo_cuit("30")
        self.t["bodega"].append((cuit, "Bodega Boutique del Atuel SA",
                                 "Ruta 173 km 12, Villa Atuel, Mendoza"))
        self.bodega_boutique = cuit

        self.transportistas = []
        usados = set()
        for cod in range(1, self.n(15, 4) + 1):
            while True:
                nombre = f"Transportes {self.fake.last_name()} {rng.choice(['SA', 'SRL', 'e Hijos'])}"
                if nombre not in usados:
                    usados.add(nombre)
                    break
            dominio = nombre.split()[1].lower().translate(str.maketrans("áéíóúñü", "aeiounu"))
            self.t["transportista"].append(
                (cod, nombre, self.nuevo_cuit("30"), f"logistica@{dominio}{cod}.com.ar",
                 f"0260-4{rng.randint(100000, 999999)}", self.fake.street_address() + ", Mendoza"))
            # Actividad relativa: algunos transportan mucho más que otros.
            self.transportistas.append((cod, rng.uniform(0.2, 3.0)))
            for loc in rng.sample([l[0] for l in self.localidades], rng.randint(3, 6)):
                self.t["transportista_localidad"].append((cod, loc))

    # ------------------------------------------------------------------
    # Fincas, parcelas, lotes y análisis
    # ------------------------------------------------------------------
    def produccion(self):
        rng = self.rng
        zonas = ["San Rafael", "General Alvear", "Luján de Cuyo", "Maipú", "Tupungato",
                 "Tunuyán", "San Carlos", "Rivadavia", "Junín", "San Martín", "Lavalle"]
        pesos_cepa = {"Malbec": 30, "Cabernet Sauvignon": 12, "Merlot": 6, "Syrah": 6,
                      "Bonarda": 10, "Tempranillo": 4, "Pinot Noir": 4, "Chardonnay": 10,
                      "Sauvignon Blanc": 5, "Torrontés": 6, "Chenin Blanc": 4, "Semillón": 3}
        cepa_ids = [c[0] for c in self.cepas]
        cepa_pesos = [pesos_cepa.get(c[1], 1) for c in self.cepas]
        parajes = ["Las Paredes", "El Cerrito", "Los Árboles", "La Arboleda", "El Sosneado",
                   "Cuadro Nacional", "Los Reyunos", "La Llave", "El Nihuil", "Medrano",
                   "Altamira", "Gualtallary", "Los Chacayes", "Perdriel", "Agrelo"]
        parcelas = []
        usados = set()
        for id_finca in range(1, self.n(30, 4) + 1):
            while True:
                nombre = f"Finca {rng.choice(parajes)} {self.fake.last_name()}"
                if nombre not in usados:
                    usados.add(nombre)
                    break
            sup = Decimal(rng.randint(40, 320))
            self.t["finca"].append((id_finca, nombre, sup, self.id_depto[rng.choice(zonas)]))
            cant = rng.randint(12, 28)
            # Repartir el 85 % de la superficie entre las parcelas.
            cortes = sorted(rng.uniform(0, 1) for _ in range(cant - 1))
            partes = [b - a for a, b in zip([0] + cortes, cortes + [1])]
            for nro, parte in enumerate(partes, start=1):
                sup_p = max(Decimal("0.50"), (sup * Decimal("0.85") * Decimal(parte)).quantize(DOS))
                cepa = rng.choices(cepa_ids, cepa_pesos)[0]
                anio = rng.randint(1950, self.hoy.year - 4)
                self.t["parcela"].append((id_finca, nro, sup_p, anio, cepa))
                parcelas.append((id_finca, nro, sup_p, rng.uniform(0.75, 1.25)))

        nro_lote = 0
        id_analisis = 0
        anio_actual = self.hoy.year
        ultima = anio_actual if self.hoy >= date(anio_actual, 5, 1) else anio_actual - 1
        bodegas = self.bodegas + [self.bodega_boutique]
        for campania in range(ultima - 4, ultima + 1):
            for id_finca, nro, sup, vigor in parcelas:
                if rng.random() < 0.08:        # algunas parcelas no se cosechan
                    continue
                nro_lote += 1
                cosecha = fecha_aleatoria(rng, date(campania, 2, 1), date(campania, 4, 30))
                rinde = rng.uniform(6000, 14000) * vigor          # kg/ha
                kilos = (sup * Decimal(rinde)).quantize(DOS)
                self.t["lote_uva"].append(
                    (nro_lote, id_finca, nro, campania, cosecha, kilos, rng.choice(bodegas)))
                for _ in range(rng.choices([1, 2, 3], [5, 3, 2])[0]):
                    id_analisis += 1
                    self.t["analisis_calidad"].append(
                        (id_analisis, nro_lote, cosecha - timedelta(days=rng.randint(0, 20)),
                         Decimal(f"{rng.uniform(20, 27):.1f}"),
                         Decimal(f"{rng.uniform(3.2, 3.9):.2f}"),
                         Decimal(f"{rng.uniform(4.5, 7.5):.2f}")))

    # ------------------------------------------------------------------
    # Vinos, composición y maridajes
    # ------------------------------------------------------------------
    def vinos(self):
        rng = self.rng
        tintas = [c for c in self.cepas if c[2] == "tinta"]
        blancas = [c for c in self.cepas if c[2] == "blanca"]
        lineas = [("Joven", 4500), ("Clásico", 6000), ("Roble", 8000), ("Reserva", 12500),
                  ("Selección", 15000), ("Gran Reserva", 24000), ("Alta Gama", 38000),
                  ("Edición Limitada", 52000), ("Terroir", 18000), ("Familia", 9500)]
        marcas = ["Atuel", "Cerro Nevado", "Diamante", "Los Reyunos", "Nihuil", "Sosneado",
                  "Piedra Blanca", "Valle Grande", "Cuesta de los Terneros", "Laguna Llancanelo",
                  "Payunia", "Malargüe Alto", "Cañón del Atuel", "Real del Padre", "Las Leñas",
                  "Bowen", "Villa Atuel", "El Diamante", "Rama Caída", "Monte Comán"]
        mar = self.id_maridaje
        maridaje_por_tipo = {
            "tinto": [mar["Carnes rojas"], mar["Quesos duros"], mar["Pastas con salsa roja"],
                      mar["Entradas y fiambres"]],
            "blanco": [mar["Pescados y mariscos"], mar["Carnes blancas"], mar["Quesos blandos"],
                       mar["Entradas y fiambres"]],
            "rosado": [mar["Carnes blancas"], mar["Entradas y fiambres"], mar["Quesos blandos"],
                       mar["Pescados y mariscos"]],
            "espumante": [mar["Postres"], mar["Entradas y fiambres"], mar["Pescados y mariscos"]],
        }

        self.vinos_info = {}      # cod -> dict(precio, disponible_desde, bodega, tipo, popularidad)
        cod = 0
        usados = set()

        def alta(nombre, tipo, anada, volumen, grad, precio, bodega, corte, popularidad):
            nonlocal cod
            clave = (nombre, anada, volumen)
            if clave in usados:
                return None
            usados.add(clave)
            precio = Decimal(precio).quantize(DOS)
            cod += 1
            self.t["vino"].append((cod, nombre, tipo, anada, volumen, grad, precio, bodega))
            for id_cepa, porc in corte:
                self.t["composicion"].append((cod, id_cepa, Decimal(porc)))
            opciones = maridaje_por_tipo[tipo]
            for id_m in rng.sample(opciones, rng.randint(1, min(3, len(opciones)))):
                self.t["vino_maridaje"].append((cod, id_m))
            # Un vino recién llega al depósito un año después de su añada.
            self.vinos_info[cod] = dict(
                precio=precio, bodega=bodega, tipo=tipo,
                disponible=date(anada + 1, rng.randint(3, 10), 1),
                popularidad=popularidad)
            return cod

        def corte_para(tipo):
            if tipo == "tinto":
                if rng.random() < 0.6:
                    return [(rng.choices(tintas, [8, 4, 2, 2, 3, 1, 1])[0][0], 100)]
                cepas = rng.sample(tintas, rng.choice([2, 3]))
            elif tipo == "blanco":
                if rng.random() < 0.7:
                    return [(rng.choice(blancas)[0], 100)]
                cepas = rng.sample(blancas, 2)
            elif tipo == "rosado":
                return [(rng.choice(tintas)[0], 100)]
            else:  # espumante
                cepas = [self.cepas_por_nombre("Chardonnay"), self.cepas_por_nombre("Pinot Noir")]
            # Porcentajes enteros que suman 100.
            restante = 100
            corte = []
            for i, c in enumerate(cepas):
                if i == len(cepas) - 1:
                    p = restante
                else:
                    p = rng.randint(10, restante - 10 * (len(cepas) - i - 1))
                    p = min(p, 85)
                restante -= p
                corte.append((c[0] if isinstance(c, tuple) else c, p))
            return corte

        def graduacion(tipo):
            rangos = {"tinto": (12.5, 15.5), "blanco": (11.0, 13.8),
                      "rosado": (11.0, 13.0), "espumante": (11.0, 12.5)}
            a, b = rangos[tipo]
            return Decimal(f"{rng.uniform(a, b):.2f}")

        # El vino de ejemplo del enunciado: Malbec Reserva 2021, 750 ml,
        # $12.500, 14,00°, 85 % Malbec + 15 % Cabernet, carnes rojas y quesos duros.
        bodega_ej = self.bodegas[0]
        cod += 1
        self.t["vino"].append((cod, "Malbec Reserva", "tinto", 2021, 750, Decimal("14.00"),
                               Decimal("12500.00"), bodega_ej))
        self.t["composicion"] += [(cod, self.id_cepa["Malbec"], Decimal(85)),
                                  (cod, self.id_cepa["Cabernet Sauvignon"], Decimal(15))]
        self.t["vino_maridaje"] += [(cod, mar["Carnes rojas"]), (cod, mar["Quesos duros"])]
        usados.add(("Malbec Reserva", 2021, 750))
        self.vinos_info[cod] = dict(precio=Decimal("12500.00"), bodega=bodega_ej, tipo="tinto",
                                    disponible=date(2022, 6, 1), popularidad=6.0)
        for anada, vol in [(2022, 750), (2021, 1500), (2020, 750)]:
            alta("Malbec Reserva", "tinto", anada, vol, Decimal("14.00"),
                 Decimal("12500.00") * (2 if vol == 1500 else 1) * Decimal("1.05") ** (2022 - anada),
                 bodega_ej, [(self.id_cepa["Malbec"], 85), (self.id_cepa["Cabernet Sauvignon"], 15)],
                 4.0)

        # Vinos de la bodega boutique (exactamente 3).
        for nombre, tipo, corte in [
                ("Boutique Atuel Malbec", "tinto", [(self.id_cepa["Malbec"], 100)]),
                ("Boutique Atuel Torrontés", "blanco", [(self.id_cepa["Torrontés"], 100)]),
                ("Boutique Atuel Rosé", "rosado", [(self.id_cepa["Pinot Noir"], 100)])]:
            alta(nombre, tipo, self.hoy.year - 4, 750, graduacion(tipo), Decimal("16800.00"),
                 self.bodega_boutique, corte, 2.0)

        # Resto del catálogo: líneas de producto con varias añadas y presentaciones.
        objetivo = self.n(600, 40)
        intentos = 0
        while cod < objetivo and intentos < objetivo * 20:
            intentos += 1
            tipo = rng.choices(["tinto", "blanco", "rosado", "espumante"], [60, 25, 8, 7])[0]
            linea, base = rng.choice(lineas)
            corte = corte_para(tipo)
            if len(corte) == 1:
                varietal = next(c[1] for c in self.cepas if c[0] == corte[0][0])
                nombre = f"{rng.choice(marcas)} {varietal} {linea}"
            elif tipo == "espumante":
                nombre = f"{rng.choice(marcas)} Extra Brut {linea}"
            else:
                nombre = f"{rng.choice(marcas)} Blend {linea}"
            if tipo == "rosado":
                nombre = nombre.replace(linea, f"Rosé {linea}")
            nombre = nombre[:80]
            grad = graduacion(tipo)
            popularidad = rng.paretovariate(1.6)          # pocos muy vendidos, muchos poco
            bodega = rng.choice(self.bodegas)
            for _ in range(rng.randint(1, 4)):
                anada = rng.randint(self.hoy.year - 9, self.hoy.year - 1)
                vol = rng.choices([750, 375, 1500, 187, 3000], [80, 6, 9, 3, 2])[0]
                factor = {187: Decimal("0.3"), 375: Decimal("0.55"), 750: Decimal(1),
                          1500: Decimal("2.1"), 3000: Decimal("4.5")}[vol]
                precio = (Decimal(base) * factor * Decimal(rng.uniform(0.85, 1.25))
                          ).quantize(Decimal("1")) * 1
                precio = Decimal(precio).quantize(DOS)
                alta(nombre, tipo, anada, vol, grad, precio, bodega, corte, popularidad)
                if cod >= objetivo:
                    break

    def cepas_por_nombre(self, nombre):
        return next(c for c in self.cepas if c[1] == nombre)

    # ------------------------------------------------------------------
    # Clientes y subtipos
    # ------------------------------------------------------------------
    def clientes(self):
        rng = self.rng
        zonas = ["Gran Mendoza", "Valle de Uco", "Zona Este", "Sur mendocino", "Cuyo",
                 "Centro del país", "NOA", "Patagonia", "Litoral", "AMBA"]
        paises = ["Brasil", "Estados Unidos", "China", "Reino Unido", "Canadá", "México",
                  "Paraguay", "Uruguay", "Países Bajos", "Japón", "Alemania", "Chile"]
        loc_ids = [l[0] for l in self.localidades]
        loc_pesos = [6 if l[1] in ("Mendoza", "San Rafael", "Godoy Cruz") else 1
                     for l in self.localidades]
        dnis = set()
        self.lista_clientes = []    # (fecha_alta, id, tipo, descuento, compra?)
        id_permiso = 0
        id_hab = 0
        base = {"socio": Decimal(10), "distribuidor": Decimal(20), "exportador": Decimal(30)}
        for id_cliente in range(1, self.n(20000, 200) + 1):
            tipo = rng.choices(["socio", "distribuidor", "exportador"], [75, 17, 8])[0]
            alta = fecha_aleatoria(rng, self.hoy - timedelta(days=9 * 365), self.hoy)
            loc = rng.choices(loc_ids, loc_pesos)[0]
            if tipo == "socio":
                while True:
                    dni = str(rng.randint(10_000_000, 47_000_000))
                    if dni not in dnis:
                        dnis.add(dni)
                        break
                nombre = f"{self.fake.last_name()}, {self.fake.first_name()}"
                tipo_doc, nro_doc = "DNI", dni
            else:
                nombre = (f"{self.fake.last_name()} {rng.choice(['Distribuciones', 'Vinos', 'Comercial', 'Bebidas', 'Trading', 'Export', 'Importaciones'])} "
                          f"{rng.choice(['SA', 'SRL', 'SAS'])}")
                tipo_doc, nro_doc = "CUIT", self.nuevo_cuit("30")
            self.t["cliente"].append(
                (id_cliente, tipo, nombre[:120], tipo_doc, nro_doc,
                 self.fake.street_address()[:150], loc, alta, base[tipo]))
            if tipo == "distribuidor":
                id_hab += 1
                self.t["distribuidor"].append(
                    (id_cliente, "distribuidor", rng.choice(zonas), f"HAB-{id_hab:06d}"))
            elif tipo == "exportador":
                self.t["exportador"].append((id_cliente, "exportador", rng.choice(paises)))
                for _ in range(rng.choices([1, 2, 3, 4, 5, 6], [25, 25, 20, 15, 10, 5])[0]):
                    id_permiso += 1
                    emision = fecha_aleatoria(rng, self.hoy - timedelta(days=6 * 365), self.hoy)
                    venc = emision + timedelta(days=rng.choice([365, 730, 1095]))
                    self.t["permiso_exportacion"].append(
                        (f"PE-{id_permiso:07d}", id_cliente, emision, venc))
            # ~10 % de los clientes nunca compra (consultas D4 y D6).
            compra = rng.random() > 0.10
            self.lista_clientes.append((alta, id_cliente, tipo, base[tipo], compra))
        self.lista_clientes.sort()
        self.altas = [c[0] for c in self.lista_clientes]
        # Clientes "fanáticos" de la bodega boutique (consulta S12).
        compradores = [c for c in self.lista_clientes if c[4] and c[2] == "distribuidor"]
        self.fans_boutique = {c[1] for c in rng.sample(compradores, min(25, len(compradores)))}

    # ------------------------------------------------------------------
    # Simulación cronológica: ingresos, transferencias y ventas
    # ------------------------------------------------------------------
    def historial(self):
        rng = self.rng
        info = self.vinos_info
        cods = list(info)
        boutique = [c for c in cods if info[c]["bodega"] == self.bodega_boutique]
        populares = sorted(cods, key=lambda c: -info[c]["popularidad"])
        # Surtido de cada sala: los 40 más vendidos + boutique + 40 al azar.
        nucleo = set(populares[:40]) | set(boutique)
        surtido = {}
        for id_sala, _ in self.salas:
            resto = [c for c in cods if c not in nucleo]
            surtido[id_sala] = sorted(nucleo | set(rng.sample(resto, min(40, len(resto)))))

        deposito = {c: 0 for c in cods}
        stock = {s: {} for s, _ in self.salas}

        transp_ids = [t[0] for t in self.transportistas]
        transp_pesos = [t[1] for t in self.transportistas]

        cod_ingreso = 0
        nro_transf = 0
        nro_comp = 0
        cant_renglones = 0

        dias = (self.hoy - self.inicio).days + 1
        objetivo_ventas = self.n(150000, 500)
        ventas_por_dia = objetivo_ventas / dias
        # Ingresos por día: proporcional a la escala de ventas.
        ingresos_por_dia = self.n(2000, 20) / dias
        reposicion_cada = 15  # días entre reposiciones de una sala

        sala_ids = [s for s, _ in self.salas]
        sala_pesos = [p for _, p in self.salas]
        proxima_reposicion = {s: self.inicio for s in sala_ids}
        tope_deposito = 1500
        tope_sala = 300

        def nuevo_ingreso(dia, bodega, vinos_cant, estado="procesado"):
            nonlocal cod_ingreso
            cod_ingreso += 1
            self.t["ingreso"].append((cod_ingreso, dia, estado,
                                      rng.choices(transp_ids, transp_pesos)[0], bodega))
            for c, q in vinos_cant:
                self.t["renglon_ingreso"].append((cod_ingreso, c, q))
                if estado == "procesado":
                    deposito[c] += q

        def nueva_transferencia(dia, sala, vinos_cant, estado="procesado"):
            nonlocal nro_transf
            nro_transf += 1
            self.t["transferencia"].append((nro_transf, sala, dia, estado))
            for c, q in vinos_cant:
                self.t["renglon_transferencia"].append((nro_transf, c, q))
                if estado == "procesado":
                    deposito[c] -= q
                    stock[sala][c] = stock[sala].get(c, 0) + q

        acum_ventas = 0.0
        acum_ingresos = 0.0
        for d in range(dias):
            dia = self.inicio + timedelta(days=d)
            disponibles = [c for c in cods if info[c]["disponible"] <= dia]
            if not disponibles:
                continue

            # 1) Ingresos: una bodega repone sus vinos con menos stock.
            acum_ingresos += ingresos_por_dia
            if d == 0:
                acum_ingresos += len(self.bodegas) + 1   # stock inicial de cada bodega
            while acum_ingresos >= 1:
                acum_ingresos -= 1
                bodega = rng.choice(self.bodegas + [self.bodega_boutique])
                propios = [c for c in disponibles if info[c]["bodega"] == bodega]
                if not propios:
                    continue
                propios.sort(key=lambda c: deposito[c])
                elegidos = propios[:rng.randint(4, 8)]
                renglones = []
                for c in elegidos:
                    falta = tope_deposito - deposito[c]
                    if falta >= 60:
                        renglones.append((c, int(falta // 6 * 6)))
                if renglones:
                    nuevo_ingreso(dia, bodega, renglones)

            # 2) Transferencias: cada sala repone cada ~15 días.
            for sala in sala_ids:
                if proxima_reposicion[sala] > dia:
                    continue
                proxima_reposicion[sala] = dia + timedelta(days=rng.randint(reposicion_cada - 5,
                                                                            reposicion_cada + 5))
                candidatos = [c for c in surtido[sala] if info[c]["disponible"] <= dia]
                candidatos.sort(key=lambda c: stock[sala].get(c, 0))
                # La primera reposición de cada sala (apertura) carga más vinos.
                cuantos = 40 if not stock[sala] else rng.randint(5, 9)
                renglones = []
                for c in candidatos[:cuantos]:
                    q = min(tope_sala - stock[sala].get(c, 0), deposito[c])
                    q = int(q // 6 * 6)
                    if q >= 12:
                        renglones.append((c, q))
                if renglones:
                    nueva_transferencia(dia, sala, renglones)

            # 3) Ventas del día.
            acum_ventas += ventas_por_dia
            while acum_ventas >= 1:
                acum_ventas -= 1
                sala = rng.choices(sala_ids, sala_pesos)[0]
                # Cliente dado de alta antes de la venta y que compra.
                tope = bisect.bisect_right(self.altas, dia)
                if tope == 0:
                    continue
                for _ in range(5):
                    alta, id_cliente, tipo, descuento, compra = self.lista_clientes[rng.randrange(tope)]
                    if compra:
                        break
                else:
                    continue
                en_stock = [c for c, q in stock[sala].items() if q > 0]
                if not en_stock:
                    continue
                k = rng.choices([1, 2, 3, 4, 5, 6], [12, 16, 22, 22, 16, 12])[0]
                elegidos = []
                if id_cliente in self.fans_boutique:
                    elegidos = [c for c in boutique if stock[sala].get(c, 0) > 0]
                pesos = [info[c]["popularidad"] for c in en_stock]
                intentos = 0
                while len(elegidos) < k and intentos < 20:
                    intentos += 1
                    c = rng.choices(en_stock, pesos)[0]
                    if c not in elegidos:
                        elegidos.append(c)
                if not elegidos:
                    continue
                nro_comp += 1
                bruto = Decimal(0)
                neto = Decimal(0)
                for c in elegidos:
                    if tipo == "socio":
                        quiere = rng.choices([1, 2, 3, 6], [45, 30, 15, 10])[0]
                    elif tipo == "distribuidor":
                        quiere = rng.choice([6, 12, 12, 18, 24])
                    else:
                        quiere = rng.choice([12, 24, 36, 48])
                    q = min(quiere, stock[sala][c])
                    stock[sala][c] -= q
                    precio = info[c]["precio"]
                    sub = subtotal_renglon(q, precio, descuento)
                    bruto += q * precio
                    neto += sub
                    self.t["renglon_comprobante"].append((nro_comp, c, q, precio, descuento, sub))
                    cant_renglones += 1
                self.t["comprobante"].append(
                    (nro_comp, dia, id_cliente, sala, bruto, bruto - neto, neto))

        # 4) Documentos pendientes (no mueven stock): últimos 20 días.
        for _ in range(self.n(40, 3)):
            dia = self.hoy - timedelta(days=rng.randint(0, 20))
            bodega = rng.choice(self.bodegas)
            propios = [c for c in cods if info[c]["bodega"] == bodega and info[c]["disponible"] <= dia]
            if propios:
                nuevo_ingreso(dia, bodega,
                              [(c, rng.randrange(60, 600, 6)) for c in rng.sample(propios, min(3, len(propios)))],
                              estado=rng.choice(["en_confeccion", "terminado"]))
        for _ in range(self.n(150, 5)):
            dia = self.hoy - timedelta(days=rng.randint(0, 20))
            sala = rng.choice(sala_ids)
            candidatos = [c for c in surtido[sala] if info[c]["disponible"] <= dia]
            nueva_transferencia(dia, sala,
                                [(c, rng.randrange(12, 120, 6)) for c in rng.sample(candidatos, rng.randint(2, 5))],
                                estado=rng.choice(["en_confeccion", "terminado"]))

        # 5) Stock final.
        self.t["stock_deposito"] = [(c, q) for c, q in deposito.items()]
        for sala, vinos in stock.items():
            for c, q in vinos.items():
                self.t["stock_sala"].append((sala, c, q))

    def generar(self):
        self.catalogos()
        self.salas_y_empleados()
        self.bodegas_y_transporte()
        self.produccion()
        self.vinos()
        self.clientes()
        self.historial()
        return self.t


# ----------------------------------------------------------------------
# Carga en la base
# ----------------------------------------------------------------------
def columnas(conn, tabla):
    filas = conn.execute(
        """SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            ORDER BY ordinal_position""", (tabla,)).fetchall()
    return [f[0] for f in filas]


def copiar(conn, tabla, filas):
    cols = columnas(conn, tabla)
    sql = f"COPY {tabla} ({', '.join(cols)}) FROM STDIN"
    with conn.cursor().copy(sql) as cp:
        for fila in filas:
            cp.write_row(fila)


def ajustar_identidades(conn):
    """COPY escribe los valores de las columnas IDENTITY tal cual; después
    hay que mover cada secuencia al máximo cargado."""
    filas = conn.execute(
        """SELECT table_name, column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND is_identity = 'YES'""").fetchall()
    for tabla, col in filas:
        conn.execute(
            f"SELECT setval(pg_get_serial_sequence('{tabla}', '{col}'), "
            f"COALESCE((SELECT max({col}) FROM {tabla}), 0) + 1, false)")


CONTROLES = {
    "Filas huérfanas: renglones de comprobante sin cabecera":
        "SELECT count(*) FROM renglon_comprobante r WHERE NOT EXISTS (SELECT 1 FROM comprobante c WHERE c.nro_comprobante = r.nro_comprobante)",
    "Comprobantes sin renglones":
        "SELECT count(*) FROM comprobante c WHERE NOT EXISTS (SELECT 1 FROM renglon_comprobante r WHERE r.nro_comprobante = c.nro_comprobante)",
    "Comprobantes cuyo total no coincide con la suma de sus renglones (RN-08)":
        "SELECT count(*) FROM comprobante c WHERE c.total <> fn_total_comprobante(c.nro_comprobante)",
    "Renglones cuyo subtotal no coincide con la fórmula (RN-08)":
        "SELECT count(*) FROM renglon_comprobante WHERE subtotal <> fn_subtotal_renglon(cantidad, precio_unitario, porcentaje_descuento)",
    "Renglones con descuento distinto al del tipo de cliente (RN-06)":
        "SELECT count(*) FROM renglon_comprobante r JOIN comprobante c USING (nro_comprobante) JOIN cliente cl USING (id_cliente) WHERE r.porcentaje_descuento <> fn_descuento_por_tipo(cl.tipo)",
    "Stock negativo en salas o depósito (RN-09)":
        "SELECT (SELECT count(*) FROM stock_sala WHERE cantidad < 0) + (SELECT count(*) FROM stock_deposito WHERE cantidad < 0)",
    "Stock de sala distinto de transferido - vendido":
        """SELECT count(*) FROM stock_sala s
            WHERE s.cantidad <> COALESCE((SELECT SUM(rt.cantidad) FROM renglon_transferencia rt JOIN transferencia t USING (nro_transferencia)
                                           WHERE t.estado = 'procesado' AND t.id_sala = s.id_sala AND rt.cod_vino = s.cod_vino), 0)
                               - COALESCE((SELECT SUM(rc.cantidad) FROM renglon_comprobante rc JOIN comprobante c USING (nro_comprobante)
                                           WHERE c.id_sala = s.id_sala AND rc.cod_vino = s.cod_vino), 0)""",
    "Stock de depósito distinto de ingresado - transferido":
        """SELECT count(*) FROM stock_deposito d
            WHERE d.cantidad <> COALESCE((SELECT SUM(ri.cantidad) FROM renglon_ingreso ri JOIN ingreso i USING (cod_ingreso)
                                           WHERE i.estado = 'procesado' AND ri.cod_vino = d.cod_vino), 0)
                               - COALESCE((SELECT SUM(rt.cantidad) FROM renglon_transferencia rt JOIN transferencia t USING (nro_transferencia)
                                           WHERE t.estado = 'procesado' AND rt.cod_vino = d.cod_vino), 0)""",
    "Vinos cuya composición no suma 100 (RN-05)":
        "SELECT count(*) FROM vino v WHERE (SELECT COALESCE(SUM(porcentaje), 0) FROM composicion c WHERE c.cod_vino = v.cod_vino) <> 100",
    "Ventas anteriores al alta del cliente":
        "SELECT count(*) FROM comprobante c JOIN cliente cl USING (id_cliente) WHERE c.fecha < cl.fecha_alta",
    "Ventas de un vino antes de su primer ingreso al depósito":
        """SELECT count(*) FROM (SELECT rc.cod_vino, min(c.fecha) AS primera_venta FROM renglon_comprobante rc JOIN comprobante c USING (nro_comprobante) GROUP BY rc.cod_vino) v
            WHERE v.primera_venta < (SELECT min(i.fecha) FROM renglon_ingreso ri JOIN ingreso i USING (cod_ingreso) WHERE ri.cod_vino = v.cod_vino)""",
    "Lotes cuya fecha de cosecha no pertenece a su campaña":
        "SELECT count(*) FROM lote_uva WHERE EXTRACT(YEAR FROM fecha_cosecha) <> campania",
    "Subtipos que no coinciden con el tipo del cliente":
        "SELECT (SELECT count(*) FROM distribuidor d JOIN cliente c USING (id_cliente) WHERE c.tipo <> 'distribuidor') + (SELECT count(*) FROM exportador e JOIN cliente c USING (id_cliente) WHERE c.tipo <> 'exportador')",
}


def benchmark(conn, filas, n=5000):
    """Compara INSERT fila por fila (un commit por fila), executemany en una
    transacción y COPY, sobre una tabla de prueba con la misma estructura
    que renglon_comprobante (incluye PK y CHECK, sin FK ni triggers)."""
    muestra = filas[:n]
    resultados = []
    conn.execute("DROP TABLE IF EXISTS _bench")
    conn.execute("CREATE TABLE _bench (LIKE renglon_comprobante INCLUDING ALL)")
    conn.commit()
    sql = "INSERT INTO _bench VALUES (%s, %s, %s, %s, %s, %s)"

    conn.autocommit = True
    t = time.perf_counter()
    for fila in muestra:
        conn.execute(sql, fila)
    resultados.append(("INSERT fila por fila (un COMMIT por fila)", time.perf_counter() - t))
    conn.autocommit = False

    conn.execute("TRUNCATE _bench")
    conn.commit()
    t = time.perf_counter()
    with conn.cursor() as cur:
        cur.executemany(sql, muestra)
    conn.commit()
    resultados.append(("executemany en una transacción", time.perf_counter() - t))

    conn.execute("TRUNCATE _bench")
    conn.commit()
    t = time.perf_counter()
    with conn.cursor().copy("COPY _bench FROM STDIN") as cp:
        for fila in muestra:
            cp.write_row(fila)
    conn.commit()
    resultados.append(("COPY (por lotes)", time.perf_counter() - t))

    conn.execute("DROP TABLE _bench")
    conn.commit()
    return n, resultados


def main():
    ap = argparse.ArgumentParser(description="Carga masiva reproducible de Bodegas del Atuel")
    ap.add_argument("--dsn", default=os.environ.get("DATABASE_URL"))
    ap.add_argument("--semilla", type=int, default=int(os.environ.get("SEMILLA", 2026)))
    ap.add_argument("--escala", type=float, default=float(os.environ.get("ESCALA", 1.0)))
    ap.add_argument("--fecha-referencia", default=os.environ.get("FECHA_REFERENCIA"))
    ap.add_argument("--benchmark", action="store_true")
    ap.add_argument("--forzar", action="store_true", help="vaciar las tablas si ya tienen datos")
    ap.add_argument("--si-vacia", action="store_true", help="no hacer nada si la base ya tiene datos")
    ap.add_argument("--reporte", default=os.environ.get("REPORTE"))
    args = ap.parse_args()

    if not args.dsn:
        sys.exit("Falta DATABASE_URL (o --dsn).")
    hoy = date.fromisoformat(args.fecha_referencia) if args.fecha_referencia else date.today()

    with psycopg.connect(args.dsn) as conn:
        hay = conn.execute("SELECT count(*) FROM vino").fetchone()[0]
        if hay:
            if args.si_vacia:
                print("La base ya tiene datos: no se carga nada.")
                return
            if not args.forzar:
                sys.exit("La base ya tiene datos. Usá --forzar para vaciarla y recargar.")

        tiempos = []
        t0 = time.perf_counter()
        print(f"Generando datos (semilla={args.semilla}, escala={args.escala}, hoy={hoy})...")
        datos = Generador(args.semilla, args.escala, hoy).generar()
        tiempos.append(("Generación en Python", time.perf_counter() - t0))

        t1 = time.perf_counter()
        with conn.transaction():
            if hay:
                conn.execute("TRUNCATE " + ", ".join(reversed(ORDEN_CARGA)) + ", auditoria_precio RESTART IDENTITY CASCADE")
            for tabla in TABLAS_CON_TRIGGERS:
                conn.execute(f"ALTER TABLE {tabla} DISABLE TRIGGER USER")
            for tabla in ORDEN_CARGA:
                tt = time.perf_counter()
                copiar(conn, tabla, datos[tabla])
                tiempos.append((f"COPY {tabla} ({len(datos[tabla]):,} filas)".replace(",", "."), time.perf_counter() - tt))
                print(f"  {tabla:<26} {len(datos[tabla]):>9,} filas")
            for tabla in TABLAS_CON_TRIGGERS:
                conn.execute(f"ALTER TABLE {tabla} ENABLE TRIGGER USER")
            ajustar_identidades(conn)
        tiempos.append(("Carga total (una transacción)", time.perf_counter() - t1))

        t2 = time.perf_counter()
        conn.execute("REFRESH MATERIALIZED VIEW mv_ventas_mensuales_sala")
        conn.commit()
        conn.autocommit = True
        conn.execute("ANALYZE")
        conn.autocommit = False
        tiempos.append(("REFRESH de la vista materializada + ANALYZE", time.perf_counter() - t2))

        print("\nConsultas de control (todas deben dar 0):")
        controles = []
        for nombre, sql in CONTROLES.items():
            valor = conn.execute(sql).fetchone()[0]
            controles.append((nombre, valor))
            print(f"  [{'OK' if valor == 0 else 'ERROR'}] {nombre}: {valor}")

        conteos = []
        for tabla in ORDEN_CARGA + ["auditoria_precio"]:
            conteos.append((tabla, conn.execute(f"SELECT count(*) FROM {tabla}").fetchone()[0]))

        bench = benchmark(conn, datos["renglon_comprobante"]) if args.benchmark else None

    errores = [c for c in controles if c[1] != 0]
    if args.reporte:
        escribir_reporte(args, hoy, conteos, tiempos, controles, bench)
        print(f"\nReporte escrito en {args.reporte}")
    print(f"\nCarga terminada en {time.perf_counter() - t0:.1f} s.")
    if errores:
        sys.exit(f"{len(errores)} consultas de control encontraron inconsistencias.")


def escribir_reporte(args, hoy, conteos, tiempos, controles, bench):
    lineas = [
        "# Reporte de la carga masiva (generado por `db/seed/cargar_datos.py`)",
        "",
        f"- Semilla: `{args.semilla}` · Escala: `{args.escala}` · Fecha de referencia: `{hoy}`",
        "- Método: `COPY` por tabla, en una sola transacción, con los triggers de usuario deshabilitados (FK y CHECK activos).",
        "",
        "## Filas por tabla",
        "",
        "| Tabla | Filas |",
        "| --- | ---: |",
    ]
    lineas += [f"| {t} | {n:,} |".replace(",", ".") for t, n in conteos]
    lineas += ["", "## Tiempos", "", "| Paso | Segundos |", "| --- | ---: |"]
    lineas += [f"| {p} | {s:.2f} |" for p, s in tiempos]
    lineas += ["", "## Consultas de control (todas deben dar 0)", "",
               "| Control | Resultado |", "| --- | ---: |"]
    lineas += [f"| {n} | {v} |" for n, v in controles]
    if bench:
        n, res = bench
        base = res[0][1]
        lineas += ["", f"## Fila por fila frente a por lotes ({n:,} renglones)".replace(",", "."), "",
                   "| Método | Segundos | Filas/s | Veces más rápido que fila por fila |",
                   "| --- | ---: | ---: | ---: |"]
        lineas += [f"| {m} | {s:.3f} | {n / s:,.0f} | {base / s:.1f}x |".replace(",", ".") for m, s in res]
    Path(args.reporte).parent.mkdir(parents=True, exist_ok=True)
    Path(args.reporte).write_text("\n".join(lineas) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
