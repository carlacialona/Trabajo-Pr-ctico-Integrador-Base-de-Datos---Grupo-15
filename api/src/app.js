// =====================================================================
// app.js · Arma la aplicación Express (sin levantar el servidor, para que
// las pruebas automáticas la puedan usar directamente).
// =====================================================================
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const swaggerUi = require('swagger-ui-express');
const YAML = require('yaml');

const { query } = require('./db');
const { manejadorErrores, ApiError } = require('./errors');
const { asincrono } = require('./routes/util');
const reportesDao = require('./dao/reportes');

function crearApp() {
  const app = express();

  // CORS: solo los orígenes configurados (en la nube, la URL del front).
  const origenes = (process.env.CORS_ORIGIN || '*').split(',').map((o) => o.trim());
  app.use(cors({ origin: origenes.includes('*') ? '*' : origenes }));
  app.use(express.json({ limit: '100kb' }));

  // Documentación OpenAPI en /docs
  const spec = YAML.parse(fs.readFileSync(path.join(__dirname, '..', 'openapi.yaml'), 'utf8'));
  app.get('/openapi.json', (req, res) => res.json(spec));
  app.use('/docs', swaggerUi.serve, swaggerUi.setup(spec, { customSiteTitle: 'API Bodegas del Atuel' }));

  app.get('/', (req, res) => res.json({ api: 'Bodegas del Atuel', documentacion: '/docs', salud: '/salud' }));

  // Salud: verifica que la API llega a la base (y con qué rol).
  app.get(
    '/salud',
    asincrono(async (req, res) => {
      const { rows } = await query(
        `SELECT current_user AS rol, current_database() AS base, now() AS hora,
                (SELECT count(*) FROM vino) AS vinos`,
      );
      res.json({ estado: 'ok', ...rows[0] });
    }),
  );

  app.get(
    '/catalogos',
    asincrono(async (req, res) => res.json(await reportesDao.catalogos())),
  );

  app.use('/vinos', require('./routes/vinos'));
  app.use('/clientes', require('./routes/clientes'));
  app.use('/comprobantes', require('./routes/comprobantes'));
  const docs = require('./routes/documentos');
  app.use('/transferencias', docs.transferencias);
  app.use('/ingresos', docs.ingresos);
  app.use('/reportes', require('./routes/reportes'));

  app.use((req, res, next) => next(new ApiError(404, `No existe la ruta ${req.method} ${req.path}.`)));
  app.use(manejadorErrores);
  return app;
}

module.exports = { crearApp };
