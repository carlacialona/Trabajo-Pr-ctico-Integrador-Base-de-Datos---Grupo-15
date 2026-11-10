// =====================================================================
// errors.js · Traducción de errores de PostgreSQL a respuestas HTTP.
//
// La API NO valida reglas de negocio por su cuenta: deja que la base las
// rechace y traduce el SQLSTATE a un código HTTP claro, conservando el
// mensaje de la regla (por ejemplo "RN-09: stock insuficiente ...").
// =====================================================================

class ApiError extends Error {
  constructor(status, mensaje, extra = {}) {
    super(mensaje);
    this.status = status;
    this.extra = extra;
  }
}

// Mensajes legibles para los CHECK y UNIQUE más comunes. Si una restricción
// no está en la lista, se devuelve el mensaje original de PostgreSQL.
const MENSAJES_RESTRICCION = {
  ck_vino_precio: 'El precio del vino debe ser mayor que cero (RN-01).',
  ck_vino_graduacion: 'La graduación debe estar entre 5 y 20 (RN-15).',
  ck_vino_volumen: 'La presentación debe ser de 187, 375, 750, 1500 o 3000 ml.',
  ck_vino_anada: 'La añada debe estar entre 1900 y 2100.',
  ck_composicion_porcentaje: 'Cada porcentaje de corte debe ser mayor que 0 y como máximo 100.',
  ck_cliente_descuento: 'El descuento del cliente debe estar entre 0 y 50 (RN-06).',
  ck_permiso_fechas: 'La fecha de vencimiento del permiso debe ser posterior a la de emisión (RN-07).',
  ck_renglon_comp_cantidad: 'La cantidad debe ser mayor que cero (RN-15).',
  ck_renglon_transf_cantidad: 'La cantidad debe ser mayor que cero (RN-15).',
  ck_renglon_ingreso_cantidad: 'La cantidad debe ser mayor que cero (RN-15).',
  ck_stock_sala_cantidad: 'El stock de la sala no puede quedar negativo (RN-09).',
  ck_stock_deposito_cantidad: 'El stock del depósito no puede quedar negativo (RN-11).',
  uq_vino_nombre_anada_volumen: 'Ya existe un vino con ese nombre, añada y presentación.',
  uq_cliente_documento: 'Ya existe un cliente con ese tipo y número de documento.',
  uq_distribuidor_habilitacion: 'Ya existe un distribuidor con ese número de habilitación.',
  uq_bodega_razon_social: 'Ya existe una bodega con esa razón social.',
  fk_distribuidor_cliente: 'El cliente no es de tipo distribuidor.',
  fk_exportador_cliente: 'El cliente no es de tipo exportador.',
};

// SQLSTATE -> código HTTP
function statusPara(err) {
  switch (err.code) {
    case '23505': // UNIQUE
      return 409;
    case '23503': // FOREIGN KEY
      // "is still referenced" = se intenta borrar algo que tiene dependientes.
      return /still referenced/i.test(err.detail || '') ? 409 : 422;
    case '23514': // CHECK
    case '23502': // NOT NULL
    case '22003': // número fuera de rango
    case '22001': // texto demasiado largo
      return 422;
    case 'P0001': // RAISE EXCEPTION de un trigger o procedimiento (regla de negocio)
      return 409;
    case 'P0002': // RAISE ... USING ERRCODE = 'P0002' (no existe)
      return 404;
    case '22P02': // formato inválido para el tipo (enum, número, ...)
    case '22007': // fecha inválida
    case '22008':
      return 400;
    case '40001': // fallo de serialización
    case '40P01': // deadlock
      return 503;
    case '42501': // permiso denegado
      return 403;
    default:
      return 500;
  }
}

function aRespuesta(err) {
  if (err instanceof ApiError) {
    return { status: err.status, cuerpo: { error: { mensaje: err.message, ...err.extra } } };
  }
  if (err.type === 'entity.parse.failed') {
    return { status: 400, cuerpo: { error: { mensaje: 'El cuerpo de la petición no es un JSON válido.' } } };
  }
  if (!err.code) {
    return { status: 500, cuerpo: { error: { mensaje: 'Error interno del servidor.' } } };
  }
  const status = statusPara(err);
  const mensaje =
    (err.constraint && MENSAJES_RESTRICCION[err.constraint]) ||
    (status === 409 && err.code === '23503'
      ? 'No se puede borrar: tiene movimientos o datos asociados (RN-14).'
      : err.message);
  const cuerpo = {
    error: {
      mensaje,
      sqlstate: err.code,
      ...(err.constraint && { restriccion: err.constraint }),
      ...(err.detail && { detalle: err.detail }),
      ...(err.code === 'P0001' && { regla: (err.message.match(/^RN-\d+/) || [null])[0] }),
    },
  };
  if (status === 503) cuerpo.error.reintentar = true;
  return { status, cuerpo };
}

/** Middleware de Express: manejador central de errores. */
// eslint-disable-next-line no-unused-vars
function manejadorErrores(err, req, res, next) {
  const { status, cuerpo } = aRespuesta(err);
  if (status >= 500) console.error(err);
  if (status === 503) res.set('Retry-After', '1');
  res.status(status).json(cuerpo);
}

module.exports = { ApiError, manejadorErrores, statusPara };
