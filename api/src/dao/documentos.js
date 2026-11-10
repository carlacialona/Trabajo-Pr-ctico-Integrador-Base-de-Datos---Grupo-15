// =====================================================================
// dao/documentos.js · Ingresos y transferencias.
// Comparten el mismo circuito: en_confeccion -> terminado -> procesado.
// Las transiciones las valida el trigger de estados (RN-10, RN-11), los
// renglones los bloquea el trigger RN-12 y el stock lo mueve el
// procedimiento sp_procesar_* (la API no toca el stock).
//
// Los nombres de tabla y columna salen de una configuración FIJA de este
// archivo (nunca del usuario), así que no hay riesgo de inyección.
// =====================================================================
const { query, withTransaction } = require('../db');

const CONFIG = {
  ingreso: {
    tabla: 'ingreso',
    id: 'cod_ingreso',
    renglones: 'renglon_ingreso',
    fecha: 'fecha',
    procedimiento: 'sp_procesar_ingreso',
    columnasExtra: `d.cod_transporte, t.razon_social AS transportista, d.cuit_bodega, b.razon_social AS bodega`,
    joinsExtra: `JOIN transportista t USING (cod_transporte) JOIN bodega b ON b.cuit = d.cuit_bodega`,
    filtroSala: null,
  },
  transferencia: {
    tabla: 'transferencia',
    id: 'nro_transferencia',
    renglones: 'renglon_transferencia',
    fecha: 'fecha_confeccion',
    procedimiento: 'sp_procesar_transferencia',
    columnasExtra: `d.id_sala, l.nombre AS localidad`,
    joinsExtra: `JOIN sala_venta s USING (id_sala) JOIN localidad l USING (id_localidad)`,
    filtroSala: 'd.id_sala',
  },
};

function dao(tipo) {
  const c = CONFIG[tipo];

  async function listar({ estado, id_sala, pagina, tamanio }) {
    const { rows } = await query(
      `SELECT d.${c.id} AS numero, d.${c.fecha} AS fecha, d.estado, ${c.columnasExtra},
              (SELECT count(*) FROM ${c.renglones} r WHERE r.${c.id} = d.${c.id}) AS renglones,
              (SELECT COALESCE(SUM(cantidad), 0) FROM ${c.renglones} r WHERE r.${c.id} = d.${c.id})::int AS botellas
         FROM ${c.tabla} d ${c.joinsExtra}
        WHERE ($1::estado_documento IS NULL OR d.estado = $1::estado_documento)
          ${c.filtroSala ? `AND ($2::int IS NULL OR ${c.filtroSala} = $2)` : 'AND ($2::int IS NULL OR TRUE)'}
        ORDER BY d.${c.id} DESC
        LIMIT $3 OFFSET $4`,
      [estado || null, id_sala || null, tamanio, (pagina - 1) * tamanio],
    );
    return { datos: rows, pagina, tamanio };
  }

  async function obtener(numero) {
    const { rows } = await query(
      `SELECT d.${c.id} AS numero, d.${c.fecha} AS fecha, d.estado, ${c.columnasExtra}
         FROM ${c.tabla} d ${c.joinsExtra}
        WHERE d.${c.id} = $1`,
      [numero],
    );
    if (!rows.length) return null;
    const { rows: renglones } = await query(
      `SELECT r.cod_vino, v.nombre, v.anada, v.volumen_ml, r.cantidad,
              COALESCE(sd.cantidad, 0) AS stock_deposito
         FROM ${c.renglones} r
         JOIN vino v USING (cod_vino)
         LEFT JOIN stock_deposito sd USING (cod_vino)
        WHERE r.${c.id} = $1
        ORDER BY v.nombre`,
      [numero],
    );
    return { ...rows[0], renglones };
  }

  /** Alta de la cabecera (y renglones opcionales) en una transacción. */
  async function crear(datos) {
    return withTransaction(async (cx) => {
      const { rows } =
        tipo === 'ingreso'
          ? await cx.query(
              'INSERT INTO ingreso (cod_transporte, cuit_bodega) VALUES ($1, $2) RETURNING cod_ingreso AS numero',
              [datos.cod_transporte, datos.cuit_bodega],
            )
          : await cx.query('INSERT INTO transferencia (id_sala) VALUES ($1) RETURNING nro_transferencia AS numero', [
              datos.id_sala,
            ]);
      const numero = rows[0].numero;
      for (const r of datos.renglones || []) {
        await cx.query(`INSERT INTO ${c.renglones} (${c.id}, cod_vino, cantidad) VALUES ($1, $2, $3)`, [
          numero,
          r.cod_vino,
          r.cantidad,
        ]);
      }
      return numero;
    });
  }

  /** Agrega un renglón o reemplaza la cantidad si el vino ya estaba.
   *  Si el documento no está en confección, el trigger RN-12 lo rechaza. */
  async function guardarRenglon(numero, { cod_vino, cantidad }) {
    await query(
      `INSERT INTO ${c.renglones} (${c.id}, cod_vino, cantidad) VALUES ($1, $2, $3)
       ON CONFLICT (${c.id}, cod_vino) DO UPDATE SET cantidad = EXCLUDED.cantidad`,
      [numero, cod_vino, cantidad],
    );
  }

  async function quitarRenglon(numero, codVino) {
    const { rowCount } = await query(`DELETE FROM ${c.renglones} WHERE ${c.id} = $1 AND cod_vino = $2`, [
      numero,
      codVino,
    ]);
    return rowCount > 0;
  }

  /** en_confeccion -> terminado. El trigger valida la transición. */
  async function terminar(numero) {
    const { rowCount } = await query(`UPDATE ${c.tabla} SET estado = 'terminado' WHERE ${c.id} = $1`, [numero]);
    return rowCount > 0;
  }

  /** terminado -> procesado, moviendo stock: lo hace el procedimiento. */
  async function procesar(numero) {
    await query(`CALL ${c.procedimiento}($1)`, [numero]);
  }

  return { listar, obtener, crear, guardarRenglon, quitarRenglon, terminar, procesar };
}

module.exports = { ingresos: dao('ingreso'), transferencias: dao('transferencia') };
