// =====================================================================
// tests/api.test.js · Pruebas automáticas de la API (node:test).
//
// Requisitos: la base creada con las migraciones y cargada con la semilla
// (catálogos, bodegas, salas, clientes). Variables: DATABASE_URL con el rol
// bodegas_api.   Correr:  npm test
//
// Las pruebas crean sus propios datos (vinos, ingresos, transferencias,
// ventas) con nombres únicos, para no depender del estado de la carga.
// Varias pruebas provocan A PROPÓSITO violaciones de reglas de la base y
// verifican el código HTTP y que no queden datos a medias.
// =====================================================================
const { test, before, after, describe } = require('node:test');
const assert = require('node:assert/strict');
const { crearApp } = require('../src/app');
const { pool } = require('../src/db');

let servidor;
let base;
let cat;
const sufijo = `${Date.now()}`.slice(-7);

async function api(metodo, ruta, cuerpo) {
  const res = await fetch(base + ruta, {
    method: metodo,
    headers: cuerpo ? { 'Content-Type': 'application/json' } : {},
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  const texto = await res.text();
  return { status: res.status, body: texto ? JSON.parse(texto) : null };
}

before(async () => {
  servidor = crearApp().listen(0);
  base = `http://127.0.0.1:${servidor.address().port}`;
  cat = (await api('GET', '/catalogos')).body;
});

after(async () => {
  servidor.close();
  await pool.end();
});

// Crea un vino nuevo de prueba (100 % de una cepa) y devuelve su código.
async function vinoDePrueba(extra = {}) {
  const r = await api('POST', '/vinos', {
    nombre: `Vino Test ${sufijo} ${Math.random().toString(36).slice(2, 7)}`,
    tipo: 'tinto',
    anada: 2023,
    volumen_ml: 750,
    graduacion: 14.2,
    precio: 10000,
    cuit_bodega: cat.bodegas[0].cuit,
    composicion: [{ id_cepa: cat.cepas[0].id_cepa, porcentaje: 100 }],
    maridajes: [cat.maridajes[0].id_maridaje],
    ...extra,
  });
  assert.equal(r.status, 201, JSON.stringify(r.body));
  return r.body.cod_vino;
}

// Lleva `cantidad` botellas de un vino hasta una sala por el circuito real:
// ingreso -> terminar -> procesar -> transferencia -> terminar -> procesar.
async function abastecerSala(codVino, idSala, cantidad) {
  const ing = await api('POST', '/ingresos', {
    cod_transporte: cat.transportistas[0].cod_transporte,
    cuit_bodega: cat.bodegas[0].cuit,
    renglones: [{ cod_vino: codVino, cantidad }],
  });
  assert.equal(ing.status, 201, JSON.stringify(ing.body));
  assert.equal((await api('POST', `/ingresos/${ing.body.numero}/terminar`)).status, 200);
  assert.equal((await api('POST', `/ingresos/${ing.body.numero}/procesar`)).status, 200);

  const tr = await api('POST', '/transferencias', { id_sala: idSala, renglones: [{ cod_vino: codVino, cantidad }] });
  assert.equal(tr.status, 201);
  assert.equal((await api('POST', `/transferencias/${tr.body.numero}/terminar`)).status, 200);
  const proc = await api('POST', `/transferencias/${tr.body.numero}/procesar`);
  assert.equal(proc.status, 200, JSON.stringify(proc.body));
  return tr.body.numero;
}

describe('Infraestructura', () => {
  test('GET /salud responde y la API usa el rol bodegas_api (no el propietario)', async () => {
    const r = await api('GET', '/salud');
    assert.equal(r.status, 200);
    assert.equal(r.body.estado, 'ok');
    assert.equal(r.body.rol, 'bodegas_api');
  });

  test('una ruta inexistente devuelve 404', async () => {
    assert.equal((await api('GET', '/no-existe')).status, 404);
  });
});

describe('Catálogo de vinos', () => {
  test('GET /vinos pagina y filtra por tipo', async () => {
    const r = await api('GET', '/vinos?tipo=blanco&tamanio=5&pagina=2');
    assert.equal(r.status, 200);
    assert.equal(r.body.pagina, 2);
    assert.ok(r.body.datos.length <= 5);
    assert.ok(r.body.datos.every((v) => v.tipo === 'blanco'));
    assert.ok(r.body.total > 5);
  });

  test('inyección SQL fallida: el texto malicioso se trata como texto', async () => {
    const malicioso = "' OR 1=1; DROP TABLE vino; --";
    const r = await api('GET', `/vinos?q=${encodeURIComponent(malicioso)}`);
    assert.equal(r.status, 200);
    assert.equal(r.body.total, 0);
    const sigue = await api('GET', '/vinos?tamanio=1');
    assert.ok(sigue.body.total > 0, 'la tabla vino sigue existiendo');
  });

  test('un tipo de vino inexistente se rechaza con 400 (enum, 22P02)', async () => {
    const r = await api('GET', '/vinos?tipo=gaseoso');
    assert.equal(r.status, 400);
    assert.equal(r.body.error.sqlstate, '22P02');
  });

  test('POST /vinos crea el vino con su composición y GET devuelve la ficha', async () => {
    const cod = await vinoDePrueba();
    const r = await api('GET', `/vinos/${cod}`);
    assert.equal(r.status, 200);
    assert.equal(r.body.composicion.length, 1);
    assert.equal(Number(r.body.composicion[0].porcentaje), 100);
    assert.equal(r.body.stock_total, 0);
  });

  test('RN-05: composición que no suma 100 -> 409 y no queda el vino', async () => {
    const nombre = `Corte Malo ${sufijo}`;
    const r = await api('POST', '/vinos', {
      nombre,
      tipo: 'tinto',
      anada: 2022,
      volumen_ml: 750,
      graduacion: 13.5,
      precio: 9000,
      cuit_bodega: cat.bodegas[0].cuit,
      composicion: [
        { id_cepa: cat.cepas[0].id_cepa, porcentaje: 60 },
        { id_cepa: cat.cepas[1].id_cepa, porcentaje: 30 },
      ],
    });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.regla, 'RN-05');
    const busqueda = await api('GET', `/vinos?q=${encodeURIComponent(nombre)}`);
    assert.equal(busqueda.body.total, 0, 'el ROLLBACK no dejó el vino a medias');
  });

  test('RN-01: precio negativo -> 422 (CHECK)', async () => {
    const r = await api('POST', '/vinos', {
      nombre: `Precio Negativo ${sufijo}`,
      tipo: 'blanco',
      anada: 2024,
      volumen_ml: 750,
      graduacion: 12,
      precio: -5,
      cuit_bodega: cat.bodegas[0].cuit,
      composicion: [{ id_cepa: cat.cepas[0].id_cepa, porcentaje: 100 }],
    });
    assert.equal(r.status, 422);
    assert.equal(r.body.error.restriccion, 'ck_vino_precio');
  });

  test('UNIQUE (nombre, añada, volumen): vino duplicado -> 409', async () => {
    const cod = await vinoDePrueba();
    const original = (await api('GET', `/vinos/${cod}`)).body;
    const r = await api('POST', '/vinos', {
      nombre: original.nombre,
      tipo: 'tinto',
      anada: original.anada,
      volumen_ml: original.volumen_ml,
      graduacion: 13,
      precio: 5000,
      cuit_bodega: cat.bodegas[0].cuit,
      composicion: [{ id_cepa: cat.cepas[0].id_cepa, porcentaje: 100 }],
    });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.sqlstate, '23505');
  });

  test('RN-13: un cambio de precio queda auditado', async () => {
    const cod = await vinoDePrueba();
    const r = await api('PUT', `/vinos/${cod}`, { precio: 11500 });
    assert.equal(r.status, 200);
    const historial = (await api('GET', `/vinos/${cod}/precios`)).body;
    assert.equal(historial.length, 1);
    assert.equal(Number(historial[0].precio_anterior), 10000);
    assert.equal(Number(historial[0].precio_nuevo), 11500);
    assert.equal(historial[0].usuario, 'bodegas_api');
  });

  test('GET de un vino inexistente -> 404', async () => {
    assert.equal((await api('GET', '/vinos/99999999')).status, 404);
  });
});

describe('Ventas, stock y documentos', () => {
  const idSala = 1;
  let cod;
  let cod2;
  let idCliente;

  before(async () => {
    cod = await vinoDePrueba();
    cod2 = await vinoDePrueba();
    await abastecerSala(cod, idSala, 5);
    await abastecerSala(cod2, idSala, 5);
    const socios = (await api('GET', '/clientes?tipo=socio&tamanio=1')).body;
    idCliente = socios.datos[0].id_cliente;
  });

  test('venta OK: la base calcula precio, descuento, total y descuenta stock', async () => {
    const r = await api('POST', '/comprobantes', {
      id_cliente: idCliente,
      id_sala: idSala,
      renglones: [{ cod_vino: cod, cantidad: 2 }],
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    const renglon = r.body.renglones[0];
    assert.equal(Number(renglon.precio_unitario), 10000);
    assert.equal(Number(renglon.porcentaje_descuento), 10); // socio
    assert.equal(Number(renglon.subtotal), 18000);
    assert.equal(Number(r.body.total), 18000);
    assert.equal(r.body.total, r.body.total_segun_renglones);
    const vino = (await api('GET', `/vinos/${cod}`)).body;
    assert.equal(vino.stock_por_sala.find((s) => s.id_sala === idSala).cantidad, 3);
  });

  test('RN-09: vender más que el stock -> 409 y la venta no queda a medias', async () => {
    const antes = (await api('GET', `/comprobantes?sala=${idSala}&tamanio=1`)).body.datos[0].nro_comprobante;
    const r = await api('POST', '/comprobantes', {
      id_cliente: idCliente,
      id_sala: idSala,
      // El primer renglón es válido; el segundo pide más de lo que hay.
      renglones: [
        { cod_vino: cod2, cantidad: 1 },
        { cod_vino: cod, cantidad: 999 },
      ],
    });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.regla, 'RN-09');
    const despues = (await api('GET', `/comprobantes?sala=${idSala}&tamanio=1`)).body.datos[0].nro_comprobante;
    assert.equal(despues, antes, 'no se creó el comprobante');
    const vino = (await api('GET', `/vinos/${cod}`)).body;
    assert.equal(vino.stock_por_sala.find((s) => s.id_sala === idSala).cantidad, 3, 'el stock no cambió');
    const vino2 = (await api('GET', `/vinos/${cod2}`)).body;
    assert.equal(vino2.stock_por_sala.find((s) => s.id_sala === idSala).cantidad, 5,
      'el renglón válido también se revirtió (todo o nada)');
  });

  test('RN-14: no se puede borrar un vino con movimientos -> 409', async () => {
    const r = await api('DELETE', `/vinos/${cod}`);
    assert.equal(r.status, 409);
    assert.equal(r.body.error.sqlstate, '23503');
  });

  test('RN-11: procesar una transferencia sin stock en el depósito -> 409 y queda terminada', async () => {
    const tr = await api('POST', '/transferencias', { id_sala: idSala, renglones: [{ cod_vino: cod, cantidad: 1000 }] });
    await api('POST', `/transferencias/${tr.body.numero}/terminar`);
    const r = await api('POST', `/transferencias/${tr.body.numero}/procesar`);
    assert.equal(r.status, 409);
    assert.equal(r.body.error.regla, 'RN-11');
    const doc = (await api('GET', `/transferencias/${tr.body.numero}`)).body;
    assert.equal(doc.estado, 'terminado');
  });

  test('RN-10: procesar un ingreso en confección -> 409', async () => {
    const ing = await api('POST', '/ingresos', {
      cod_transporte: cat.transportistas[0].cod_transporte,
      cuit_bodega: cat.bodegas[0].cuit,
      renglones: [{ cod_vino: cod, cantidad: 12 }],
    });
    const r = await api('POST', `/ingresos/${ing.body.numero}/procesar`);
    assert.equal(r.status, 409);
    assert.equal(r.body.error.regla, 'RN-10');
  });

  test('RN-12: no se agregan renglones a una transferencia procesada -> 409', async () => {
    const nro = await abastecerSala(cod, idSala, 1);
    const r = await api('POST', `/transferencias/${nro}/renglones`, { cod_vino: cod, cantidad: 5 });
    assert.equal(r.status, 409);
    assert.equal(r.body.error.regla, 'RN-12');
  });

  test('procesar una transferencia inexistente -> 404', async () => {
    assert.equal((await api('POST', '/transferencias/99999999/procesar')).status, 404);
  });
});

describe('Clientes', () => {
  test('alta de exportador: la base asigna 30 % de descuento (RN-06) y guarda sus permisos', async () => {
    const r = await api('POST', '/clientes', {
      tipo: 'exportador',
      nombre: `Export Test ${sufijo} SA`,
      tipo_doc: 'CUIT',
      nro_doc: `30${sufijo}99`,
      direccion: 'Ruta 143 km 5',
      id_localidad: cat.localidades[0].id_localidad,
      pais_destino: 'Brasil',
      permisos: [{ cod_permiso: `PT-${sufijo}`, fecha_emision: '2025-01-01', fecha_vencimiento: '2026-01-01' }],
    });
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(Number(r.body.descuento), 30);
    assert.equal(r.body.lista_permisos.length, 1);
    assert.equal((await api('DELETE', `/clientes/${r.body.id_cliente}`)).status, 204);
  });

  test('RN-07: permiso con vencimiento anterior a la emisión -> 422 y no queda el cliente', async () => {
    const nroDoc = `30${sufijo}88`;
    const r = await api('POST', '/clientes', {
      tipo: 'exportador',
      nombre: `Export Malo ${sufijo} SA`,
      tipo_doc: 'CUIT',
      nro_doc: nroDoc,
      direccion: 'Ruta 7',
      id_localidad: cat.localidades[0].id_localidad,
      pais_destino: 'Chile',
      permisos: [{ cod_permiso: `PM-${sufijo}`, fecha_emision: '2025-06-01', fecha_vencimiento: '2025-01-01' }],
    });
    assert.equal(r.status, 422);
    assert.equal(r.body.error.restriccion, 'ck_permiso_fechas');
    assert.equal((await api('GET', `/clientes?q=${nroDoc}`)).body.total, 0);
  });

  test('RN-06: descuento fuera de rango -> 422', async () => {
    const socio = (await api('GET', '/clientes?tipo=socio&tamanio=1')).body.datos[0];
    const r = await api('PUT', `/clientes/${socio.id_cliente}`, { descuento: 90 });
    assert.equal(r.status, 422);
    assert.equal(r.body.error.restriccion, 'ck_cliente_descuento');
  });
});

describe('Reportes', () => {
  test('top de vinos, ventas por sala y trazabilidad responden', async () => {
    const top = await api('GET', '/reportes/top-vinos?limite=10');
    assert.equal(top.status, 200);
    assert.equal(top.body.length, 10);
    assert.ok(top.body[0].botellas >= top.body[9].botellas);
    assert.equal((await api('GET', '/reportes/ventas-por-sala')).status, 200);
    const traza = await api('GET', `/reportes/trazabilidad/${top.body[0].cod_vino}`);
    assert.equal(traza.status, 200);
    assert.ok(traza.body.ventas_por_sala.length > 0);
  });
});
