// Rutas de ingresos y transferencias: el mismo circuito para los dos.
const express = require('express');
const { ingresos, transferencias } = require('../dao/documentos');
const { asincrono, entero, paginacion, renglones, noEncontrado } = require('./util');

function router(dao, nombre) {
  const r = express.Router();

  r.get(
    '/',
    asincrono(async (req, res) => {
      res.json(await dao.listar({ estado: req.query.estado, id_sala: req.query.sala, ...paginacion(req.query) }));
    }),
  );

  r.get(
    '/:nro',
    asincrono(async (req, res) => {
      const doc = await dao.obtener(entero(req.params.nro, 'nro'));
      if (!doc) throw noEncontrado(nombre);
      res.json(doc);
    }),
  );

  // Alta en confección (los renglones son opcionales)
  r.post(
    '/',
    asincrono(async (req, res) => {
      const numero = await dao.crear({ ...req.body, renglones: renglones(req.body.renglones, false) });
      res.status(201).json(await dao.obtener(numero));
    }),
  );

  // Agregar un renglón (o cambiar su cantidad) mientras está en confección
  r.post(
    '/:nro/renglones',
    asincrono(async (req, res) => {
      const nro = entero(req.params.nro, 'nro');
      if (!(await dao.obtener(nro))) throw noEncontrado(nombre);
      await dao.guardarRenglon(nro, req.body);
      res.status(201).json(await dao.obtener(nro));
    }),
  );

  r.delete(
    '/:nro/renglones/:cod',
    asincrono(async (req, res) => {
      const nro = entero(req.params.nro, 'nro');
      if (!(await dao.quitarRenglon(nro, entero(req.params.cod, 'cod')))) throw noEncontrado('El renglón');
      res.json(await dao.obtener(nro));
    }),
  );

  r.post(
    '/:nro/terminar',
    asincrono(async (req, res) => {
      const nro = entero(req.params.nro, 'nro');
      if (!(await dao.terminar(nro))) throw noEncontrado(nombre);
      res.json(await dao.obtener(nro));
    }),
  );

  // Procesar: invoca el procedimiento almacenado (mueve el stock).
  r.post(
    '/:nro/procesar',
    asincrono(async (req, res) => {
      const nro = entero(req.params.nro, 'nro');
      await dao.procesar(nro);
      res.json(await dao.obtener(nro));
    }),
  );

  return r;
}

module.exports = {
  ingresos: router(ingresos, 'El ingreso'),
  transferencias: router(transferencias, 'La transferencia'),
};
