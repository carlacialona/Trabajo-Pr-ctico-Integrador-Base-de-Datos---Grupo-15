// =====================================================================
// db.js · Conexión con PostgreSQL usando el driver nativo "pg" (sin ORM).
//
// * Pool de conexiones: se reutilizan en vez de abrir una por pedido.
// * La configuración viene de variables de entorno (nunca del código).
// * La API se conecta con el rol bodegas_api, que NO es el propietario.
// * withTransaction() encapsula BEGIN / COMMIT / ROLLBACK para las
//   operaciones de varias sentencias (ventas, alta de vinos, etc.).
// =====================================================================
const { Pool } = require('pg');

const ssl =
  process.env.DB_SSL === 'require'
    ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false' }
    : undefined;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.DB_POOL_MAX || 10),
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  ssl,
});

// Los NUMERIC llegan como texto para no perder precisión (el driver no los
// convierte a float a propósito). Los devolvemos como string en el JSON:
// la API no hace cuentas con ellos, solo los muestra.
// Los DATE se devuelven como 'AAAA-MM-DD' (sin convertirlos a Date de JS,
// que les agregaría una zona horaria).
const types = require('pg').types;
types.setTypeParser(1082, (valor) => valor); // DATE
types.setTypeParser(20, (valor) => Number(valor)); // BIGINT (count(*))

/** Ejecuta una consulta parametrizada con una conexión del pool. */
function query(texto, parametros = []) {
  return pool.query(texto, parametros);
}

/**
 * Ejecuta `trabajo(cliente)` dentro de una transacción.
 * Si `trabajo` lanza un error (o falla el COMMIT por un constraint trigger
 * diferido), se hace ROLLBACK y el error sigue hacia el manejador central.
 */
async function withTransaction(trabajo) {
  const cliente = await pool.connect();
  try {
    await cliente.query('BEGIN');
    const resultado = await trabajo(cliente);
    await cliente.query('COMMIT');
    return resultado;
  } catch (err) {
    await cliente.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    cliente.release();
  }
}

module.exports = { pool, query, withTransaction };
