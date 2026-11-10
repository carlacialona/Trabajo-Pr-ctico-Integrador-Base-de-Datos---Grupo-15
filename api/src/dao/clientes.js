// =====================================================================
// dao/clientes.js · Clientes (supertipo) y sus subtipos.
// El descuento inicial NO lo calcula la API: lo pone el trigger
// trg_cliente_descuento según el tipo (RN-06).
// =====================================================================
const { query, withTransaction } = require('../db');

const SELECT_CLIENTE = `
  SELECT c.id_cliente, c.tipo, c.nombre, c.tipo_doc, c.nro_doc, c.direccion,
         c.id_localidad, l.nombre AS localidad, c.fecha_alta, c.descuento,
         d.zona_cobertura, d.nro_habilitacion, e.pais_destino,
         (SELECT count(*) FROM permiso_exportacion p WHERE p.id_cliente = c.id_cliente) AS permisos
    FROM cliente c
    JOIN localidad l USING (id_localidad)
    LEFT JOIN distribuidor d USING (id_cliente)
    LEFT JOIN exportador e USING (id_cliente)`;

async function listar({ tipo, q, pagina, tamanio }) {
  const params = [tipo || null, q || null, tamanio, (pagina - 1) * tamanio];
  const { rows } = await query(
    `${SELECT_CLIENTE}
      WHERE ($1::tipo_cliente IS NULL OR c.tipo = $1::tipo_cliente)
        AND ($2::text IS NULL OR c.nombre ILIKE '%' || $2 || '%' OR c.nro_doc = $2)
      ORDER BY c.nombre
      LIMIT $3 OFFSET $4`,
    params,
  );
  const { rows: total } = await query(
    `SELECT count(*) AS total FROM cliente c
      WHERE ($1::tipo_cliente IS NULL OR c.tipo = $1::tipo_cliente)
        AND ($2::text IS NULL OR c.nombre ILIKE '%' || $2 || '%' OR c.nro_doc = $2)`,
    params.slice(0, 2),
  );
  return { datos: rows, pagina, tamanio, total: total[0].total };
}

async function obtener(id) {
  const { rows } = await query(`${SELECT_CLIENTE} WHERE c.id_cliente = $1`, [id]);
  if (!rows.length) return null;
  const cliente = rows[0];
  if (cliente.tipo === 'exportador') {
    const { rows: permisos } = await query(
      `SELECT cod_permiso, fecha_emision, fecha_vencimiento
         FROM permiso_exportacion WHERE id_cliente = $1 ORDER BY fecha_emision`,
      [id],
    );
    cliente.lista_permisos = permisos;
  }
  return cliente;
}

async function guardarSubtipo(cx, id, d, esAlta) {
  if (d.tipo === 'distribuidor') {
    await cx.query(
      esAlta
        ? 'INSERT INTO distribuidor (id_cliente, zona_cobertura, nro_habilitacion) VALUES ($1, $2, $3)'
        : `UPDATE distribuidor SET zona_cobertura = COALESCE($2, zona_cobertura),
                                   nro_habilitacion = COALESCE($3, nro_habilitacion) WHERE id_cliente = $1`,
      [id, d.zona_cobertura, d.nro_habilitacion],
    );
  } else if (d.tipo === 'exportador') {
    await cx.query(
      esAlta
        ? 'INSERT INTO exportador (id_cliente, pais_destino) VALUES ($1, $2)'
        : 'UPDATE exportador SET pais_destino = COALESCE($2, pais_destino) WHERE id_cliente = $1',
      [id, d.pais_destino],
    );
  }
  if (d.tipo === 'exportador' && Array.isArray(d.permisos) && d.permisos.length) {
    await cx.query(
      `INSERT INTO permiso_exportacion (cod_permiso, id_cliente, fecha_emision, fecha_vencimiento)
       SELECT p.cod_permiso, $1, p.fecha_emision, p.fecha_vencimiento
         FROM jsonb_to_recordset($2::jsonb) AS p(cod_permiso text, fecha_emision date, fecha_vencimiento date)`,
      [id, JSON.stringify(d.permisos)],
    );
  }
}

/** Alta del supertipo y del subtipo en una sola transacción. */
async function crear(d) {
  return withTransaction(async (cx) => {
    const { rows } = await cx.query(
      `INSERT INTO cliente (tipo, nombre, tipo_doc, nro_doc, direccion, id_localidad, descuento)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id_cliente`,
      [d.tipo, d.nombre, d.tipo_doc, d.nro_doc, d.direccion, d.id_localidad, d.descuento ?? null],
    );
    const id = rows[0].id_cliente;
    await guardarSubtipo(cx, id, d, true);
    return id;
  });
}

async function modificar(id, d) {
  return withTransaction(async (cx) => {
    const { rows } = await cx.query(
      `UPDATE cliente
          SET nombre       = COALESCE($2, nombre),
              tipo_doc     = COALESCE($3::tipo_documento, tipo_doc),
              nro_doc      = COALESCE($4, nro_doc),
              direccion    = COALESCE($5, direccion),
              id_localidad = COALESCE($6, id_localidad),
              descuento    = COALESCE($7, descuento)
        WHERE id_cliente = $1
        RETURNING tipo`,
      [id, d.nombre, d.tipo_doc, d.nro_doc, d.direccion, d.id_localidad, d.descuento],
    );
    if (!rows.length) return false;
    await guardarSubtipo(cx, id, { ...d, tipo: rows[0].tipo }, false);
    return true;
  });
}

/** Borra el cliente; el subtipo y sus permisos se van por CASCADE.
 *  Si tiene comprobantes, la FK RESTRICT lo impide. */
async function borrar(id) {
  const { rowCount } = await query('DELETE FROM cliente WHERE id_cliente = $1', [id]);
  return rowCount > 0;
}

module.exports = { listar, obtener, crear, modificar, borrar };
