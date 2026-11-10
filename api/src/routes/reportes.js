const express = require('express');
const dao = require('../dao/reportes');
const { asincrono, entero, noEncontrado } = require('./util');

const r = express.Router();

r.get(
  '/top-vinos',
  asincrono(async (req, res) => {
    const limite = req.query.limite ? Math.min(entero(req.query.limite, 'limite'), 100) : 10;
    res.json(await dao.topVinos(limite));
  }),
);

r.get(
  '/ventas-por-sala',
  asincrono(async (req, res) => res.json(await dao.ventasPorSala())),
);

r.get(
  '/vinos-sin-stock',
  asincrono(async (req, res) => res.json(await dao.vinosSinStock(entero(req.query.sala, 'sala')))),
);

r.get(
  '/transportista-activo',
  asincrono(async (req, res) => res.json(await dao.transportistaActivo())),
);

r.get(
  '/trazabilidad/:cod',
  asincrono(async (req, res) => {
    const datos = await dao.trazabilidad(entero(req.params.cod, 'cod'));
    if (!datos) throw noEncontrado('El vino');
    res.json(datos);
  }),
);

r.get(
  '/ventas-mensuales',
  asincrono(async (req, res) =>
    res.json(await dao.ventasMensuales(req.query.sala ? entero(req.query.sala, 'sala') : null)),
  ),
);

r.get(
  '/documentos-pendientes',
  asincrono(async (req, res) => res.json(await dao.documentosPendientes())),
);

module.exports = r;
