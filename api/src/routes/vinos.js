const express = require('express');
const dao = require('../dao/vinos');
const { asincrono, entero, paginacion, noEncontrado } = require('./util');

const r = express.Router();

// GET /vinos?tipo=&cepa=&bodega=&anada=&q=&pagina=&tamanio=
r.get(
  '/',
  asincrono(async (req, res) => {
    const { tipo, cepa, bodega, anada, q, sala } = req.query;
    res.json(await dao.listar({ tipo, cepa, bodega, anada, q, sala, ...paginacion(req.query) }));
  }),
);

r.get(
  '/:cod',
  asincrono(async (req, res) => {
    const vino = await dao.obtener(entero(req.params.cod, 'cod'));
    if (!vino) throw noEncontrado('El vino');
    res.json(vino);
  }),
);

r.get(
  '/:cod/precios',
  asincrono(async (req, res) => {
    res.json(await dao.historialPrecios(entero(req.params.cod, 'cod')));
  }),
);

r.post(
  '/',
  asincrono(async (req, res) => {
    const cod = await dao.crear(req.body);
    res.status(201).location(`/vinos/${cod}`).json(await dao.obtener(cod));
  }),
);

r.put(
  '/:cod',
  asincrono(async (req, res) => {
    const cod = entero(req.params.cod, 'cod');
    if (!(await dao.modificar(cod, req.body))) throw noEncontrado('El vino');
    res.json(await dao.obtener(cod));
  }),
);

r.delete(
  '/:cod',
  asincrono(async (req, res) => {
    if (!(await dao.borrar(entero(req.params.cod, 'cod')))) throw noEncontrado('El vino');
    res.status(204).end();
  }),
);

module.exports = r;
