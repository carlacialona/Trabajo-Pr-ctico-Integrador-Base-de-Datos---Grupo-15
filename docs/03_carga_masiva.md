# 3. Carga masiva

Etapa 3. Script: `db/seed/cargar_datos.py`. Catálogos: `db/seed/catalogos/*.csv`. Controles: `db/seed/consultas_control.sql`. Resultado de la última ejecución (conteos, tiempos, controles y comparación fila por fila vs. lotes): [`informes/etapa3_reporte_carga.md`](informes/etapa3_reporte_carga.md).

## 3.1 Cómo ejecutarla

```bash
# Con Docker: la hace sola el servicio "seed" la primera vez.
docker compose up --build

# A mano (rol propietario, base con las migraciones aplicadas):
pip install -r db/seed/requirements.txt
DATABASE_URL=postgresql://bodegas_owner:CLAVE@localhost:5432/bodegas \
  python db/seed/cargar_datos.py --benchmark --reporte docs/informes/etapa3_reporte_carga.md

# Recargar desde cero sobre una base con datos:
python db/seed/cargar_datos.py --forzar
# Carga reducida (por ejemplo para un plan gratuito en la nube):
python db/seed/cargar_datos.py --escala 0.1
```

En Windows (PowerShell) las variables se definen con `$env:DATABASE_URL = "..."` antes del comando.

## 3.2 Volúmenes

| Tabla | Filas (escala 1) |
| --- | ---: |
| `renglon_comprobante` | ~523.000 |
| `comprobante` | ~150.000 |
| `renglon_transferencia` | ~23.600 |
| `cliente` | 20.000 |
| `renglon_ingreso` | ~7.600 |
| `transferencia` | ~5.800 |
| `analisis_calidad` | ~4.900 |
| `permiso_exportacion` | ~4.300 |
| `distribuidor` | ~3.300 |
| `lote_uva` | ~2.850 |
| `stock_sala` | ~3.300 |
| `ingreso` | ~1.800 |
| `vino` / `stock_deposito` | 600 |
| catálogos (localidades, cepas, maridajes, bodegas, transportistas) | 8 a 60 |

Todas las tablas tienen filas, más de tres superan las 10.000 y `renglon_comprobante` supera las 500.000. Los valores exactos están en el reporte.

## 3.3 Catálogos reales

Desde CSV, no al azar: 18 departamentos de Mendoza, 35 localidades reales con su código postal (incluye casos de CP compartido: San Carlos y Eugenio Bustos 5569, Perdriel y Agrelo 5509), las 12 cepas y los 8 maridajes del anexo B. Nombres de bodegas, fincas, clientes y transportistas: Faker (`es_AR`), ficticios.

## 3.4 Orden de carga

Se carga primero lo que no depende de nada y después lo que depende de eso (orden topológico de las FK):

```mermaid
flowchart LR
  subgraph N0[Sin dependencias]
    provincia; cepa; maridaje; bodega; transportista
  end
  provincia --> departamento --> localidad
  localidad --> sala_venta --> empleado
  localidad --> transportista_localidad
  transportista --> transportista_localidad
  departamento --> finca --> parcela
  cepa --> parcela --> lote_uva --> analisis_calidad
  bodega --> lote_uva
  bodega --> vino --> composicion
  cepa --> composicion
  vino --> vino_maridaje
  maridaje --> vino_maridaje
  localidad --> cliente --> distribuidor
  cliente --> exportador --> permiso_exportacion
  vino --> renglon_ingreso
  transportista --> ingreso --> renglon_ingreso
  sala_venta --> transferencia --> renglon_transferencia
  vino --> stock_deposito
  vino --> stock_sala
  sala_venta --> stock_sala
  cliente --> comprobante
  sala_venta --> comprobante --> renglon_comprobante
  vino --> renglon_comprobante
```

## 3.5 Datos coherentes: el historial se simula

Generar cada tabla al azar por separado daría stocks negativos y fechas imposibles. Por eso el script **simula día por día** los últimos 6 años:

1. **Ingresos**: cada día llegan ingresos de una bodega con sus vinos de menor stock; un vino recién puede ingresar un año después de su añada.
2. **Transferencias**: cada sala se repone cada ~15 días con los vinos de su surtido que tienen menos stock, limitado por lo que hay en el depósito.
3. **Ventas**: ~68 por día; cada una elige un cliente dado de alta antes de esa fecha y vinos **con stock en esa sala en ese momento**. La cantidad nunca supera el stock.
4. Los importes se calculan con la misma fórmula que `fn_subtotal_renglon` y el descuento del tipo de cliente.
5. Al final se generan algunos documentos pendientes (en confección y terminados) de los últimos 20 días, que no mueven stock.

Además: los porcentajes de corte suman 100; el vino de ejemplo del enunciado ("Malbec Reserva" 2021, 750 ml, $12.500, 85 % Malbec + 15 % Cabernet) está cargado; hay una bodega "boutique" con 3 vinos que algunos distribuidores compran completos (para S12); ~10 % de los clientes nunca compran (D4, D6).

## 3.6 Reproducibilidad

`random.Random(semilla)` y `Faker.seed_instance(semilla)` con semilla fija (`SEMILLA`, por defecto 2026). Las fechas se generan relativas a una **fecha de referencia** (por defecto, hoy) para que "la última semana" o "el último trimestre" siempre tengan datos. Con la misma semilla **y** la misma `FECHA_REFERENCIA`, dos ejecuciones generan exactamente los mismos datos. Se verificó cargando dos bases y comparando un hash MD5 del contenido de varias tablas: idéntico.

```bash
SEMILLA=2026 FECHA_REFERENCIA=2026-11-09 python db/seed/cargar_datos.py
```

## 3.7 Cómo se manejaron los triggers durante la carga

**Decisión**: deshabilitar los triggers de usuario de las tablas de movimientos durante la carga histórica, dentro de una única transacción:

```sql
BEGIN;
ALTER TABLE renglon_comprobante DISABLE TRIGGER USER;   -- (y las demás)
COPY ... ;
ALTER TABLE renglon_comprobante ENABLE TRIGGER USER;
COMMIT;
```

**Por qué**:

- Los triggers rechazarían datos históricos válidos: la fecha de confección de una transferencia vieja (el trigger fuerza la fecha de hoy) y documentos que ya nacen `procesado` (el trigger exige empezar en confección).
- Recalcular 150.000 cabeceras fila por fila (un UPDATE por renglón) haría la carga muchísimo más lenta.

**Riesgos y cómo se mitigaron**:

| Riesgo | Mitigación |
| --- | --- |
| Cargar datos que violen una regla que vigilaba el trigger | El generador calcula todo con las mismas fórmulas, y al final corren **13 consultas de control** (totales vs. renglones, subtotales, descuentos por tipo, stock = ingresado − transferido − vendido, stock no negativo, composición = 100, fechas lógicas, subtipos). Todas dan 0. |
| Que los triggers queden deshabilitados si la carga falla | Todo está en una transacción: `ALTER TABLE` también es transaccional, así que un error revierte los datos **y** el deshabilitado. |
| Romper la integridad referencial | `DISABLE TRIGGER USER` no toca los triggers internos de las FK ni los CHECK: siguen validando cada fila. |
| Otras sesiones viendo la tabla sin reglas | `ALTER TABLE` toma un bloqueo exclusivo: nadie más usa esas tablas hasta el COMMIT. |

Después de la carga: `setval` de cada secuencia IDENTITY al máximo cargado (COPY escribe los IDs tal cual), `REFRESH` de la vista materializada y `ANALYZE` para que el planificador tenga estadísticas.

## 3.8 Eficiencia: fila por fila contra lotes

Se usa `COPY` (protocolo de copia masiva) por tabla. El script con `--benchmark` compara tres formas de insertar los mismos renglones en una tabla de prueba (los números están en el reporte):

- `INSERT` fila por fila con un COMMIT por fila: un viaje de red y una escritura al log (WAL) con espera de confirmación por fila.
- `executemany` en una sola transacción: un solo COMMIT.
- `COPY`: un solo comando que transmite todas las filas en un flujo.

## 3.9 Volcado

```bash
pg_dump "$DATABASE_URL" --format=custom --no-owner --file=backups/dump_completo.dump
# o, comprimido en texto plano:
pg_dump "$DATABASE_URL" | gzip > backups/dump_completo.sql.gz
```

Con Docker: `docker compose exec db pg_dump -U bodegas_owner -d bodegas -Fc > backups/dump_completo.dump`. El volcado completo pesa unos 7 MB en formato custom; no se sube al repositorio (`.gitignore`) porque se regenera con la semilla. Restauración: ver `07_despliegue_nube.md`.
