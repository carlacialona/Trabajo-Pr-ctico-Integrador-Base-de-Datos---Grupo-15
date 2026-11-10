const express = require('express');
const dao = require('../dao/clientes');
const { asincrono, entero, paginacion, noEncontrado } = require('./util');

const r = express.Router();

r.get(
  '/',
  asincrono(async (req, res) => {
    res.json(await dao.listar({ tipo: req.query.tipo, q: req.query.q, ...paginacion(req.query) }));
  }),
);

r.get(
  '/:id',
  asincrono(async (req, res) => {
    const cliente = await dao.obtener(entero(req.params.id, 'id'));
    if (!cliente) throw noEncontrado('El cliente');
    res.json(cliente);
  }),
);

r.post(
  '/',
  asincrono(async (req, res) => {
    const id = await dao.crear(req.body);
    res.status(201).location(`/clientes/${id}`).json(await dao.obtener(id));
  }),
);

r.put(
  '/:id',
  asincrono(async (req, res) => {
    const id = entero(req.params.id, 'id');
    if (!(await dao.modificar(id, req.body))) throw noEncontrado('El cliente');
    res.json(await dao.obtener(id));
  }),
);

r.delete(
  '/:id',
  asincrono(async (req, res) => {
    if (!(await dao.borrar(entero(req.params.id, 'id')))) throw noEncontrado('El cliente');
    res.status(204).end();
  }),
);

module.exports = r;
