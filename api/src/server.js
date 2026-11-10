// Punto de entrada: levanta el servidor HTTP.
const { crearApp } = require('./app');
const { pool } = require('./db');

if (!process.env.DATABASE_URL) {
  console.error('Falta la variable de entorno DATABASE_URL (ver .env.example).');
  process.exit(1);
}

const puerto = Number(process.env.PORT || 3000);
const servidor = crearApp().listen(puerto, () => {
  console.log(`API Bodegas del Atuel escuchando en el puerto ${puerto} (documentación en /docs)`);
});

// Cierre ordenado: terminar los pedidos en curso y cerrar el pool.
for (const senal of ['SIGINT', 'SIGTERM']) {
  process.on(senal, () => {
    servidor.close(() => pool.end().then(() => process.exit(0)));
  });
}
