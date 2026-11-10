// =====================================================================
// dao/comprobantes.js · Ventas.
// La API manda SOLO cliente, sala, vinos y cantidades. Precio, descuento,
// subtotales, totales y stock los resuelve la base con sus triggers y
// funciones (RN-08, RN-09). Todo en UNA transacción: si un renglón no
// tiene stock, se revierte la venta completa.
// =====================================================================
const { query, withTransaction } = require('../db');

async function crear({ id_cliente, id_sala, renglones }) {
  return withTransaction(async (cx) => {
    const { rows } = await cx.query(
      `INSERT INTO comprobante (id_cliente, id_sala) VALUES ($1, $2) RETURNING nro_comprobante`,
      [id_cliente, id_sala],
    );
    const nro = rows[0].nro_comprobante;
    for (const r of renglones) {
      await cx.query(
        `INSERT INTO renglon_comprobante (nro_comprobante, cod_vino, cantidad) VALUES ($1, $2, $3)`,
        [nro, r.cod_vino, r.cantidad],
      );
    }
    return nro;
  });
}

async function obtener(nro) {
  const { rows } = await query(
    `SELECT c.nro_comprobante, c.fecha, c.id_cliente, cl.nombre AS cliente, cl.tipo AS tipo_cliente,
            c.id_sala, l.nombre AS localidad, c.subtotal, c.descuento, c.total,
            fn_total_comprobante(c.nro_comprobante) AS total_segun_renglones
       FROM comprobante c
       JOIN cliente cl USING (id_cliente)
       JOIN sala_venta s USING (id_sala)
       JOIN localidad l ON l.id_localidad = s.id_localidad
      WHERE c.nro_comprobante = $1`,
    [nro],
  );
  if (!rows.length) return null;
  const { rows: renglones } = await query(
    `SELECT r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad, r.precio_unitario,
            r.porcentaje_descuento, r.subtotal
       FROM renglon_comprobante r JOIN vino v USING (cod_vino)
      WHERE r.nro_comprobante = $1 ORDER BY v.nombre`,
    [nro],
  );
  return { ...rows[0], renglones };
}

async function listar({ id_sala, id_cliente, pagina, tamanio }) {
  const { rows } = await query(
    `SELECT c.nro_comprobante, c.fecha, c.id_cliente, cl.nombre AS cliente, c.id_sala, c.total
       FROM comprobante c JOIN cliente cl USING (id_cliente)
      WHERE ($1::int IS NULL OR c.id_sala = $1)
        AND ($2::int IS NULL OR c.id_cliente = $2)
      ORDER BY c.nro_comprobante DESC
      LIMIT $3 OFFSET $4`,
    [id_sala || null, id_cliente || null, tamanio, (pagina - 1) * tamanio],
  );
  return { datos: rows, pagina, tamanio };
}

module.exports = { crear, obtener, listar };
