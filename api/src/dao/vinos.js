// =====================================================================
// dao/vinos.js · Capa de acceso a datos: vinos.
// Una función por consulta. Todo el SQL es parametrizado ($1, $2, ...):
// el texto que manda el usuario NUNCA se concatena dentro del SQL.
// =====================================================================
const { query, withTransaction } = require('../db');

/**
 * Catálogo con filtros y paginación.
 * Los filtros se agregan como condiciones con su propio parámetro; lo único
 * que se arma dinámicamente es QUÉ condiciones van, nunca su contenido.
 */
async function listar({ tipo, cepa, bodega, anada, q, sala, pagina, tamanio }) {
  const condiciones = [];
  const params = [];
  const agregar = (sql, valor) => {
    params.push(valor);
    condiciones.push(sql.replace('?', `$${params.length}`));
  };
  if (tipo) agregar('v.tipo = ?::tipo_vino', tipo);
  if (bodega) agregar('v.cuit_bodega = ?', bodega);
  if (anada) agregar('v.anada = ?::smallint', anada);
  if (cepa) agregar('EXISTS (SELECT 1 FROM composicion c WHERE c.cod_vino = v.cod_vino AND c.id_cepa = ?::smallint)', cepa);
  if (q) agregar("v.nombre ILIKE '%' || ? || '%'", q);
  // sala: solo los vinos con stock en esa sala (para la pantalla de venta)
  if (sala) agregar('EXISTS (SELECT 1 FROM stock_sala s WHERE s.cod_vino = v.cod_vino AND s.id_sala = ?::int AND s.cantidad > 0)', sala);
  params.push(sala || null);
  const pSala = params.length;

  params.push(tamanio, (pagina - 1) * tamanio);
  const where = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';
  const { rows } = await query(
    `SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
            v.cuit_bodega, b.razon_social AS bodega,
            (SELECT string_agg(ce.nombre || ' ' || co.porcentaje::int || '%', ', ' ORDER BY co.porcentaje DESC)
               FROM composicion co JOIN cepa ce USING (id_cepa)
              WHERE co.cod_vino = v.cod_vino) AS cepas,
            fn_stock_total(v.cod_vino) AS stock_total,
            CASE WHEN $${pSala}::int IS NULL THEN NULL ELSE fn_stock_sala($${pSala}::int, v.cod_vino) END AS stock_en_sala,
            count(*) OVER () AS total_filas
       FROM vino v
       JOIN bodega b ON b.cuit = v.cuit_bodega
       ${where}
      ORDER BY v.nombre, v.anada DESC, v.volumen_ml
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );
  const total = rows.length ? rows[0].total_filas : 0;
  return { datos: rows.map(({ total_filas, ...r }) => r), pagina, tamanio, total };
}

async function obtener(cod) {
  const { rows } = await query(
    `SELECT v.cod_vino, v.nombre, v.tipo, v.anada, v.volumen_ml, v.graduacion, v.precio,
            v.cuit_bodega, b.razon_social AS bodega,
            st.stock_deposito, st.stock_salas, st.stock_total
       FROM vino v
       JOIN bodega b ON b.cuit = v.cuit_bodega
       JOIN v_stock_total_vino st USING (cod_vino)
      WHERE v.cod_vino = $1`,
    [cod],
  );
  if (!rows.length) return null;
  const vino = rows[0];
  const [composicion, maridajes, stockSalas] = await Promise.all([
    query(
      `SELECT co.id_cepa, ce.nombre AS cepa, ce.tipo, co.porcentaje
         FROM composicion co JOIN cepa ce USING (id_cepa)
        WHERE co.cod_vino = $1 ORDER BY co.porcentaje DESC`,
      [cod],
    ),
    query(
      `SELECT m.id_maridaje, m.nombre, m.temperatura_servicio
         FROM vino_maridaje vm JOIN maridaje m USING (id_maridaje)
        WHERE vm.cod_vino = $1 ORDER BY m.nombre`,
      [cod],
    ),
    query(
      `SELECT s.id_sala, l.nombre AS localidad, s.cantidad
         FROM stock_sala s JOIN sala_venta sv USING (id_sala) JOIN localidad l USING (id_localidad)
        WHERE s.cod_vino = $1 AND s.cantidad > 0 ORDER BY s.id_sala`,
      [cod],
    ),
  ]);
  vino.composicion = composicion.rows;
  vino.maridajes = maridajes.rows;
  vino.stock_por_sala = stockSalas.rows;
  return vino;
}

/** Inserta composición y maridajes de un vino (dentro de la transacción). */
async function guardarDetalle(cliente, cod, composicion = [], maridajes = []) {
  if (composicion.length) {
    await cliente.query(
      `INSERT INTO composicion (cod_vino, id_cepa, porcentaje)
       SELECT $1, c.id_cepa, c.porcentaje
         FROM jsonb_to_recordset($2::jsonb) AS c(id_cepa smallint, porcentaje numeric)`,
      [cod, JSON.stringify(composicion)],
    );
  }
  if (maridajes.length) {
    await cliente.query(
      `INSERT INTO vino_maridaje (cod_vino, id_maridaje)
       SELECT $1, unnest($2::smallint[])`,
      [cod, maridajes],
    );
  }
}

/**
 * Alta de un vino con su composición, en UNA transacción.
 * La suma 100 % (RN-05) la verifica el constraint trigger diferido al hacer
 * COMMIT: si no suma 100, falla el COMMIT y no queda nada guardado.
 */
async function crear(datos) {
  return withTransaction(async (cliente) => {
    const { rows } = await cliente.query(
      `INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING cod_vino`,
      [datos.nombre, datos.tipo, datos.anada, datos.volumen_ml, datos.graduacion, datos.precio, datos.cuit_bodega],
    );
    const cod = rows[0].cod_vino;
    await guardarDetalle(cliente, cod, datos.composicion, datos.maridajes);
    return cod;
  });
}

/**
 * Modificación. Si cambia el precio, el trigger AFTER UPDATE lo audita (RN-13).
 * Si se manda composición o maridajes, se reemplazan completos.
 */
async function modificar(cod, datos) {
  return withTransaction(async (cliente) => {
    const { rowCount } = await cliente.query(
      `UPDATE vino
          SET nombre      = COALESCE($2, nombre),
              tipo        = COALESCE($3::tipo_vino, tipo),
              anada       = COALESCE($4, anada),
              volumen_ml  = COALESCE($5, volumen_ml),
              graduacion  = COALESCE($6, graduacion),
              precio      = COALESCE($7, precio),
              cuit_bodega = COALESCE($8, cuit_bodega)
        WHERE cod_vino = $1`,
      [cod, datos.nombre, datos.tipo, datos.anada, datos.volumen_ml, datos.graduacion, datos.precio, datos.cuit_bodega],
    );
    if (!rowCount) return false;
    if (Array.isArray(datos.composicion)) {
      await cliente.query('DELETE FROM composicion WHERE cod_vino = $1', [cod]);
      await guardarDetalle(cliente, cod, datos.composicion, []);
    }
    if (Array.isArray(datos.maridajes)) {
      await cliente.query('DELETE FROM vino_maridaje WHERE cod_vino = $1', [cod]);
      await guardarDetalle(cliente, cod, [], datos.maridajes);
    }
    return true;
  });
}

/** Baja. Si tiene movimientos, la FK ON DELETE RESTRICT lo impide (RN-14). */
async function borrar(cod) {
  const { rowCount } = await query('DELETE FROM vino WHERE cod_vino = $1', [cod]);
  return rowCount > 0;
}

async function historialPrecios(cod) {
  const { rows } = await query(
    `SELECT id_auditoria, precio_anterior, precio_nuevo, fecha_hora, usuario
       FROM auditoria_precio WHERE cod_vino = $1 ORDER BY fecha_hora DESC`,
    [cod],
  );
  return rows;
}

module.exports = { listar, obtener, crear, modificar, borrar, historialPrecios };
