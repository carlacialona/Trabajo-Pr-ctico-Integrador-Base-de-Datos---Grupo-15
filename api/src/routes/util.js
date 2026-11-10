// Utilidades comunes de las rutas.
const { ApiError } = require('../errors');

/** Express 4 no captura errores de funciones async: este envoltorio los
 *  pasa al manejador central. */
const asincrono = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Lee un entero positivo de la URL; si no lo es, responde 400. */
function entero(valor, nombre) {
  const n = Number(valor);
  if (!Number.isInteger(n) || n <= 0) throw new ApiError(400, `El parámetro "${nombre}" debe ser un entero positivo.`);
  return n;
}

function paginacion(q) {
  const pagina = q.pagina ? entero(q.pagina, 'pagina') : 1;
  const tamanio = Math.min(q.tamanio ? entero(q.tamanio, 'tamanio') : 20, 100);
  return { pagina, tamanio };
}

/** Exige que el cuerpo tenga una lista no vacía de renglones {cod_vino, cantidad}. */
function renglones(lista, obligatoria = true) {
  if (lista === undefined && !obligatoria) return [];
  if (!Array.isArray(lista) || (obligatoria && lista.length === 0)) {
    throw new ApiError(400, 'Hay que enviar "renglones": una lista de { cod_vino, cantidad }.');
  }
  return lista;
}

function noEncontrado(recurso) {
  return new ApiError(404, `${recurso} no existe.`);
}

module.exports = { asincrono, entero, paginacion, renglones, noEncontrado };
