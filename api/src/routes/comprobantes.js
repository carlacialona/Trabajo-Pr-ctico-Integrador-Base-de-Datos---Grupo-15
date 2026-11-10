const express = require('express');
const dao = require('../dao/comprobantes');
const { asincrono, entero, paginacion, renglones, noEncontrado } = require('./util');
const { ApiError } = require('../errors');

const r = express.Router();

r.get(
  '/',
  asincrono(async (req, res) => {
    res.json(
      await dao.listar({ id_sala: req.query.sala, id_cliente: req.query.cliente, ...paginacion(req.query) }),
    );
  }),
);

// POST /comprobantes { id_cliente, id_sala, renglones: [{ cod_vino, cantidad }] }
// La venta completa (cabecera y renglones) en una sola transacción.
r.post(
  '/',
  asincrono(async (req, res) => {
    const { id_cliente, id_sala } = req.body;
    // Validación de FORMATO (no de negocio): sin estos datos no hay venta posible.
    if (!id_cliente) throw new ApiError(400, 'Falta el cliente (id_cliente).');
    if (!id_sala) throw new ApiError(400, 'Falta la sala (id_sala).');
    const nro = await dao.crear({ id_cliente, id_sala, renglones: renglones(req.body.renglones) });
    res.status(201).location(`/comprobantes/${nro}`).json(await dao.obtener(nro));
  }),
);

r.get(
  '/:nro',
  asincrono(async (req, res) => {
    const comprobante = await dao.obtener(entero(req.params.nro, 'nro'));
    if (!comprobante) throw noEncontrado('El comprobante');
    res.json(comprobante);
  }),
);

module.exports = r;
