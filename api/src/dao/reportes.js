// =====================================================================
// dao/reportes.js · Consultas de la sección 8 expuestas como endpoints
// de solo lectura, y catálogos para los formularios del front.
// =====================================================================
const { query } = require('../db');

/** S1 · Top de vinos por botellas vendidas en toda la red. */
async function topVinos(limite) {
  const { rows } = await query(
    `WITH ventas AS (
         SELECT cod_vino, SUM(cantidad) AS botellas
           FROM renglon_comprobante GROUP BY cod_vino)
     SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, ve.botellas::int
       FROM ventas ve JOIN vino v USING (cod_vino)
      ORDER BY ve.botellas DESC, v.cod_vino
      LIMIT $1`,
    [limite],
  );
  return rows;
}

/** S8 · Monto de ventas por sala en el último trimestre. */
async function ventasPorSala() {
  const { rows } = await query(
    `SELECT c.id_sala, l.nombre AS localidad, count(*) AS comprobantes, SUM(c.total) AS monto_total
       FROM comprobante c
       JOIN sala_venta s USING (id_sala)
       JOIN localidad l USING (id_localidad)
      WHERE c.fecha >= CURRENT_DATE - INTERVAL '3 months'
      GROUP BY c.id_sala, l.nombre
      ORDER BY monto_total DESC`,
  );
  return rows;
}

/** S6 · Vinos sin stock en la sala pero con stock en el depósito. */
async function vinosSinStock(idSala) {
  const { rows } = await query(
    `SELECT v.cod_vino, v.nombre, v.anada, v.volumen_ml, d.cantidad AS stock_deposito
       FROM vino v JOIN stock_deposito d USING (cod_vino)
      WHERE d.cantidad > 0
        AND NOT EXISTS (SELECT 1 FROM stock_sala s
                         WHERE s.id_sala = $1 AND s.cod_vino = v.cod_vino AND s.cantidad > 0)
      ORDER BY v.nombre, v.anada`,
    [idSala],
  );
  return rows;
}

/** S7 · Transportista con mayor actividad en el último mes. */
async function transportistaActivo() {
  const { rows } = await query(
    `SELECT t.cod_transporte, t.razon_social, count(DISTINCT i.cod_ingreso) AS ingresos,
            SUM(r.cantidad)::int AS botellas
       FROM ingreso i
       JOIN transportista t USING (cod_transporte)
       JOIN renglon_ingreso r USING (cod_ingreso)
      WHERE i.fecha >= CURRENT_DATE - INTERVAL '1 month'
      GROUP BY t.cod_transporte, t.razon_social
      ORDER BY ingresos DESC
      FETCH FIRST 1 ROWS WITH TIES`,
  );
  return rows;
}

/** Trazabilidad de un vino: de dónde vino y adónde fue cada botella. */
async function trazabilidad(cod) {
  const ficha = await query('SELECT * FROM v_ficha_vino WHERE cod_vino = $1', [cod]);
  if (!ficha.rows.length) return null;
  const [ingresos, transferencias, ventas] = await Promise.all([
    query(
      `SELECT i.cod_ingreso, i.fecha, i.estado, b.razon_social AS bodega, t.razon_social AS transportista, r.cantidad
         FROM renglon_ingreso r
         JOIN ingreso i USING (cod_ingreso)
         JOIN bodega b ON b.cuit = i.cuit_bodega
         JOIN transportista t USING (cod_transporte)
        WHERE r.cod_vino = $1
        ORDER BY i.fecha DESC LIMIT 50`,
      [cod],
    ),
    query(
      `SELECT t.nro_transferencia, t.fecha_confeccion, t.estado, t.id_sala, l.nombre AS localidad, r.cantidad
         FROM renglon_transferencia r
         JOIN transferencia t USING (nro_transferencia)
         JOIN sala_venta s USING (id_sala)
         JOIN localidad l USING (id_localidad)
        WHERE r.cod_vino = $1
        ORDER BY t.fecha_confeccion DESC LIMIT 50`,
      [cod],
    ),
    query(
      `SELECT c.id_sala, l.nombre AS localidad, SUM(r.cantidad)::int AS botellas_vendidas,
              SUM(r.subtotal) AS monto, fn_stock_sala(c.id_sala, $1) AS stock_actual
         FROM renglon_comprobante r
         JOIN comprobante c USING (nro_comprobante)
         JOIN sala_venta s USING (id_sala)
         JOIN localidad l USING (id_localidad)
        WHERE r.cod_vino = $1
        GROUP BY c.id_sala, l.nombre
        ORDER BY botellas_vendidas DESC`,
      [cod],
    ),
  ]);
  return {
    vino: ficha.rows[0],
    ingresos: ingresos.rows,
    transferencias: transferencias.rows,
    ventas_por_sala: ventas.rows,
  };
}

/** Ventas mensuales por sala (vista materializada). */
async function ventasMensuales(idSala) {
  const { rows } = await query(
    `SELECT id_sala, mes, comprobantes, monto_total,
            SUM(monto_total) OVER (PARTITION BY id_sala ORDER BY mes) AS acumulado
       FROM mv_ventas_mensuales_sala
      WHERE ($1::int IS NULL OR id_sala = $1)
      ORDER BY id_sala, mes`,
    [idSala || null],
  );
  return rows;
}

async function documentosPendientes() {
  const { rows } = await query('SELECT * FROM v_documentos_pendientes ORDER BY fecha DESC, numero DESC');
  return rows;
}

/** Catálogos para los selectores del front. */
async function catalogos() {
  const [bodegas, cepas, maridajes, salas, transportistas, localidades] = await Promise.all([
    query('SELECT cuit, razon_social FROM bodega ORDER BY razon_social'),
    query('SELECT id_cepa, nombre, tipo FROM cepa ORDER BY nombre'),
    query('SELECT id_maridaje, nombre, temperatura_servicio FROM maridaje ORDER BY nombre'),
    query(
      `SELECT s.id_sala, s.calle, s.numero, s.dia_cierre, l.nombre AS localidad
         FROM sala_venta s JOIN localidad l USING (id_localidad) ORDER BY s.id_sala`,
    ),
    query('SELECT cod_transporte, razon_social FROM transportista ORDER BY razon_social'),
    query('SELECT id_localidad, nombre, codigo_postal FROM localidad ORDER BY nombre'),
  ]);
  return {
    bodegas: bodegas.rows,
    cepas: cepas.rows,
    maridajes: maridajes.rows,
    salas: salas.rows,
    transportistas: transportistas.rows,
    localidades: localidades.rows,
    tipos_vino: ['tinto', 'blanco', 'rosado', 'espumante'],
    tipos_cliente: ['socio', 'distribuidor', 'exportador'],
    volumenes_ml: [187, 375, 750, 1500, 3000],
  };
}

module.exports = {
  topVinos,
  ventasPorSala,
  vinosSinStock,
  transportistaActivo,
  trazabilidad,
  ventasMensuales,
  documentosPendientes,
  catalogos,
};
