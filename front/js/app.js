// =====================================================================
// app.js · Pantallas del front. Enrutador simple por "hash" (#/catalogo).
// Regla: el front NO calcula importes, descuentos ni stock. Muestra lo que
// devuelve la API y, si la base rechaza algo, muestra su mensaje tal cual.
// =====================================================================
import { api, ApiError } from './api.js';

const $vista = document.getElementById('vista');
let catalogos = null;

// ---------------------------------------------------------------------
// Utilidades de presentación
// ---------------------------------------------------------------------
const esc = (v) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const pesos = (v) =>
  v === null || v === undefined ? '' : Number(v).toLocaleString('es-AR', { style: 'currency', currency: 'ARS' });
const numero = (v) => Number(v ?? 0).toLocaleString('es-AR');
const opciones = (lista, valor, texto, elegido, vacio) =>
  (vacio !== undefined ? `<option value="">${esc(vacio)}</option>` : '') +
  lista
    .map((x) => {
      const v = typeof valor === 'function' ? valor(x) : x[valor];
      const t = typeof texto === 'function' ? texto(x) : x[texto];
      return `<option value="${esc(v)}" ${String(v) === String(elegido ?? '') ? 'selected' : ''}>${esc(t)}</option>`;
    })
    .join('');

function cajaError(err) {
  if (!err) return '';
  const extra = [err.sqlstate && `SQLSTATE ${err.sqlstate}`, err.status && `HTTP ${err.status}`]
    .filter(Boolean)
    .join(' · ');
  return `<div class="error"><strong>${esc(err.message)}</strong>${extra ? `<br><code>${esc(extra)}</code>` : ''}</div>`;
}

function aviso(texto) {
  const el = document.getElementById('aviso');
  el.textContent = texto;
  el.hidden = false;
  clearTimeout(aviso.t);
  aviso.t = setTimeout(() => (el.hidden = true), 3500);
}

async function cargarCatalogos() {
  if (!catalogos) catalogos = await api.catalogos();
  return catalogos;
}

const nombreSala = (s) => `Sala ${s.id_sala} · ${s.localidad} (${s.calle} ${s.numero})`;

// Selector de vinos con búsqueda por nombre (consulta la API).
function selectorVino(id) {
  // salaId (opcional): función que devuelve la sala; si se usa, la API
  // devuelve solo vinos con stock en esa sala y el stock informado por la base.
  return `
    <label>Buscar vino<input id="${id}-q" placeholder="Nombre, por ejemplo Malbec"></label>
    <label>Vino<select id="${id}"><option value="">Escribí para buscar…</option></select></label>`;
}
function activarSelectorVino(id, salaId) {
  const q = document.getElementById(`${id}-q`);
  const sel = document.getElementById(id);
  let t;
  const buscar = async () => {
    const sala = salaId ? salaId() : undefined;
    const r = await api.vinos({ q: q.value, sala, tamanio: 30 });
    sel.innerHTML = opciones(
      r.datos,
      'cod_vino',
      (v) => `${v.nombre} ${v.anada} · ${v.volumen_ml} ml (cód. ${v.cod_vino})` + (sala ? ` · stock en sala: ${v.stock_en_sala}` : ''),
      null,
      sala ? `${r.total} vinos con stock en la sala` : `${r.total} resultados`,
    );
  };
  q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(buscar, 250); });
  return buscar;
}

// ---------------------------------------------------------------------
// 1. Catálogo de vinos
// ---------------------------------------------------------------------
async function pantallaCatalogo() {
  const cat = await cargarCatalogos();
  const filtros = { tipo: '', cepa: '', bodega: '', anada: '', q: '', pagina: 1, tamanio: 15 };

  $vista.innerHTML = `
    <h1>Catálogo de vinos</h1>
    <p class="sub">Filtros y paginación los resuelve la API con SQL parametrizado.</p>
    <div class="panel grilla">
      <label>Nombre<input id="f-q" placeholder="Buscar…"></label>
      <label>Tipo<select id="f-tipo">${opciones(cat.tipos_vino, (x) => x, (x) => x, '', 'Todos')}</select></label>
      <label>Cepa<select id="f-cepa">${opciones(cat.cepas, 'id_cepa', 'nombre', '', 'Todas')}</select></label>
      <label>Bodega<select id="f-bodega">${opciones(cat.bodegas, 'cuit', 'razon_social', '', 'Todas')}</select></label>
      <label>Añada<input id="f-anada" type="number" min="1990" max="2100" placeholder="Ej. 2021"></label>
    </div>
    <div class="dos">
      <div><div id="tabla" class="tabla"></div><div id="paginas" class="paginas"></div></div>
      <div id="ficha" class="panel"><p class="vacio">Elegí un vino para ver su ficha.</p></div>
    </div>`;

  async function listar() {
    try {
      const r = await api.vinos(filtros);
      const paginas = Math.max(1, Math.ceil(r.total / r.tamanio));
      document.getElementById('tabla').innerHTML = r.datos.length
        ? `<table><thead><tr><th>Cód.</th><th>Vino</th><th>Tipo</th><th>Cepas</th><th class="num">Precio</th><th class="num">Stock</th></tr></thead><tbody>
          ${r.datos
            .map(
              (v) => `<tr class="clic" data-cod="${v.cod_vino}"><td>${v.cod_vino}</td>
              <td><strong>${esc(v.nombre)}</strong><br><small>${v.anada} · ${v.volumen_ml} ml · ${esc(v.bodega)}</small></td>
              <td>${esc(v.tipo)}</td><td><small>${esc(v.cepas)}</small></td>
              <td class="num">${pesos(v.precio)}</td><td class="num">${numero(v.stock_total)}</td></tr>`,
            )
            .join('')}</tbody></table>`
        : '<p class="vacio">No hay vinos con esos filtros.</p>';
      document.getElementById('paginas').innerHTML = `
        <button class="sec chico" id="ant" ${filtros.pagina <= 1 ? 'disabled' : ''}>Anterior</button>
        Página ${r.pagina} de ${paginas} · ${numero(r.total)} vinos
        <button class="sec chico" id="sig" ${filtros.pagina >= paginas ? 'disabled' : ''}>Siguiente</button>`;
      document.getElementById('ant').onclick = () => { filtros.pagina--; listar(); };
      document.getElementById('sig').onclick = () => { filtros.pagina++; listar(); };
      document.querySelectorAll('tr[data-cod]').forEach((tr) => (tr.onclick = () => ficha(tr.dataset.cod)));
    } catch (e) {
      document.getElementById('tabla').innerHTML = cajaError(e);
    }
  }

  async function ficha(cod) {
    const v = await api.vino(cod);
    document.getElementById('ficha').innerHTML = `
      <h2 style="margin-top:0">${esc(v.nombre)} ${v.anada}</h2>
      <dl class="ficha">
        <dt>Bodega</dt><dd>${esc(v.bodega)}</dd>
        <dt>Presentación · graduación · precio</dt><dd>${v.volumen_ml} ml · ${v.graduacion}° · ${pesos(v.precio)}</dd>
        <dt>Composición</dt><dd>${v.composicion.map((c) => `${esc(c.cepa)} ${Number(c.porcentaje)} %`).join(', ')}</dd>
        <dt>Maridajes</dt><dd>${v.maridajes.map((m) => `${esc(m.nombre)} (${m.temperatura_servicio} °C)`).join(', ') || '—'}</dd>
        <dt>Stock (calculado por la base)</dt><dd>Depósito ${numero(v.stock_deposito)} · Salas ${numero(v.stock_salas)} · <strong>Total ${numero(v.stock_total)}</strong></dd>
      </dl>
      <div class="acciones"><a href="#/vino/${v.cod_vino}"><button class="sec">Editar</button></a></div>`;
  }

  const aplicar = () => {
    Object.assign(filtros, {
      q: document.getElementById('f-q').value,
      tipo: document.getElementById('f-tipo').value,
      cepa: document.getElementById('f-cepa').value,
      bodega: document.getElementById('f-bodega').value,
      anada: document.getElementById('f-anada').value,
      pagina: 1,
    });
    listar();
  };
  let t;
  ['f-q', 'f-anada'].forEach((id) => document.getElementById(id).addEventListener('input', () => { clearTimeout(t); t = setTimeout(aplicar, 300); }));
  ['f-tipo', 'f-cepa', 'f-bodega'].forEach((id) => document.getElementById(id).addEventListener('change', aplicar));
  listar();
}

// ---------------------------------------------------------------------
// 2. Alta y edición de vino
// ---------------------------------------------------------------------
async function pantallaVino(cod) {
  const cat = await cargarCatalogos();
  const v = cod ? await api.vino(cod) : { composicion: [{}], maridajes: [] };

  $vista.innerHTML = `
    <h1>${cod ? `Editar vino ${cod}` : 'Alta de vino'}</h1>
    <p class="sub">La base verifica al confirmar que la composición sume 100 % (RN-05) y audita los cambios de precio (RN-13).</p>
    <form id="form" class="panel">
      <div class="grilla">
        <label>Nombre<input name="nombre" required value="${esc(v.nombre)}"></label>
        <label>Tipo<select name="tipo">${opciones(cat.tipos_vino, (x) => x, (x) => x, v.tipo)}</select></label>
        <label>Añada<input name="anada" type="number" value="${esc(v.anada)}"></label>
        <label>Presentación (ml)<select name="volumen_ml">${opciones(cat.volumenes_ml, (x) => x, (x) => `${x} ml`, v.volumen_ml ?? 750)}</select></label>
        <label>Graduación<input name="graduacion" type="number" step="0.01" value="${esc(v.graduacion)}"></label>
        <label>Precio<input name="precio" type="number" step="0.01" value="${esc(v.precio)}"></label>
        <label>Bodega<select name="cuit_bodega">${opciones(cat.bodegas, 'cuit', 'razon_social', v.cuit_bodega)}</select></label>
      </div>
      <h2>Composición (cepas y porcentajes de corte)</h2>
      <div id="cortes"></div>
      <button type="button" class="sec chico" id="mas-cepa">+ Agregar cepa</button>
      <h2>Maridajes recomendados</h2>
      <div class="grilla">${cat.maridajes
        .map((m) => `<label style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox" name="maridaje" value="${m.id_maridaje}"
            ${v.maridajes.some((x) => x.id_maridaje === m.id_maridaje) ? 'checked' : ''}> ${esc(m.nombre)}</label>`)
        .join('')}</div>
      <div id="resultado"></div>
      <div class="acciones"><button type="submit">${cod ? 'Guardar cambios' : 'Crear vino'}</button>
        <a href="#/catalogo"><button type="button" class="sec">Volver</button></a></div>
    </form>
    ${cod ? '<h2>Historial de precios (auditoría)</h2><div id="precios" class="tabla"></div>' : ''}`;

  const $cortes = document.getElementById('cortes');
  const filaCorte = (c = {}) => {
    const div = document.createElement('div');
    div.className = 'acciones';
    div.style.marginTop = '4px';
    div.innerHTML = `<label>Cepa<select class="c-cepa">${opciones(cat.cepas, 'id_cepa', (x) => `${x.nombre} (${x.tipo})`, c.id_cepa)}</select></label>
      <label>Porcentaje<input class="c-porc" type="number" step="0.01" min="0" max="100" value="${esc(c.porcentaje)}"></label>
      <button type="button" class="sec chico">Quitar</button>`;
    div.querySelector('button').onclick = () => div.remove();
    $cortes.appendChild(div);
  };
  v.composicion.forEach(filaCorte);
  document.getElementById('mas-cepa').onclick = () => filaCorte();

  if (cod) {
    const precios = await api.precios(cod);
    document.getElementById('precios').innerHTML = precios.length
      ? `<table><thead><tr><th>Fecha y hora</th><th>Usuario</th><th class="num">Anterior</th><th class="num">Nuevo</th></tr></thead><tbody>
        ${precios.map((p) => `<tr><td>${new Date(p.fecha_hora).toLocaleString('es-AR')}</td><td>${esc(p.usuario)}</td><td class="num">${pesos(p.precio_anterior)}</td><td class="num">${pesos(p.precio_nuevo)}</td></tr>`).join('')}</tbody></table>`
      : '<p class="vacio">Sin cambios de precio registrados.</p>';
  }

  document.getElementById('form').onsubmit = async (ev) => {
    ev.preventDefault();
    const f = new FormData(ev.target);
    const datos = {
      nombre: f.get('nombre'),
      tipo: f.get('tipo'),
      anada: f.get('anada') ? Number(f.get('anada')) : null,
      volumen_ml: Number(f.get('volumen_ml')),
      graduacion: f.get('graduacion') || null,
      precio: f.get('precio') || null,
      cuit_bodega: f.get('cuit_bodega'),
      composicion: [...$cortes.children].map((d) => ({
        id_cepa: Number(d.querySelector('.c-cepa').value),
        porcentaje: d.querySelector('.c-porc').value || null,
      })),
      maridajes: f.getAll('maridaje').map(Number),
    };
    const $r = document.getElementById('resultado');
    try {
      const guardado = cod ? await api.modificarVino(cod, datos) : await api.crearVino(datos);
      $r.innerHTML = `<div class="exito">Vino ${guardado.cod_vino} guardado.</div>`;
      aviso(`Vino ${guardado.cod_vino} guardado`);
      if (!cod) location.hash = `#/vino/${guardado.cod_vino}`;
      else pantallaVino(cod);
    } catch (e) {
      $r.innerHTML = cajaError(e);
    }
  };
}

// ---------------------------------------------------------------------
// 3. Nueva venta
// ---------------------------------------------------------------------
async function pantallaVenta() {
  const cat = await cargarCatalogos();
  const renglones = []; // { cod_vino, nombre, cantidad }

  $vista.innerHTML = `
    <h1>Nueva venta</h1>
    <p class="sub">El front envía solo cliente, sala, vinos y cantidades. Precio, descuento, total y stock los calcula la base.</p>
    <div class="panel grilla">
      <label>Sala<select id="sala">${opciones(cat.salas, 'id_sala', nombreSala, 1)}</select></label>
      <label>Buscar cliente<input id="cli-q" placeholder="Nombre o documento"></label>
      <label>Cliente<select id="cliente"><option value="">Escribí para buscar…</option></select></label>
    </div>
    <div class="panel">
      <div class="grilla">${selectorVino('vino')}
        <label>Cantidad<input id="cantidad" type="number" min="1" value="1"></label></div>
      <div class="acciones"><button class="sec" id="agregar">Agregar a la venta</button></div>
      <div id="stock-info" class="sub" style="margin:8px 0 0"></div>
    </div>
    <div id="renglones" class="tabla"></div>
    <div class="acciones"><button id="registrar">Registrar venta</button></div>
    <div id="resultado"></div>`;

  const buscarVinos = activarSelectorVino('vino', () => document.getElementById('sala').value);
  document.getElementById('sala').addEventListener('change', buscarVinos);
  const $cli = document.getElementById('cliente');
  let t;
  document.getElementById('cli-q').addEventListener('input', (e) => {
    clearTimeout(t);
    t = setTimeout(async () => {
      const r = await api.clientes({ q: e.target.value, tamanio: 30 });
      $cli.innerHTML = opciones(r.datos, 'id_cliente', (c) => `${c.nombre} · ${c.tipo} · ${c.tipo_doc} ${c.nro_doc}`, null, `${r.total} resultados`);
    }, 250);
  });

  document.getElementById('stock-info').textContent =
    'El buscador muestra solo vinos con stock en la sala elegida (dato de la base). Igual, la base vuelve a validar el stock al registrar.';

  const dibujar = () => {
    document.getElementById('renglones').innerHTML = renglones.length
      ? `<table><thead><tr><th>Vino</th><th class="num">Cantidad</th><th></th></tr></thead><tbody>
        ${renglones.map((r, i) => `<tr><td>${esc(r.nombre)}</td><td class="num">${r.cantidad}</td>
          <td><button class="sec chico" data-i="${i}">Quitar</button></td></tr>`).join('')}</tbody></table>`
      : '<p class="vacio" style="padding:12px">Todavía no agregaste vinos.</p>';
    document.querySelectorAll('#renglones button[data-i]').forEach((b) => (b.onclick = () => { renglones.splice(b.dataset.i, 1); dibujar(); }));
  };
  dibujar();

  document.getElementById('agregar').onclick = () => {
    const sel = document.getElementById('vino');
    if (!sel.value) return aviso('Elegí un vino.');
    const cod = Number(sel.value);
    const cantidad = Number(document.getElementById('cantidad').value);
    const existente = renglones.find((r) => r.cod_vino === cod);
    // Un vino aparece una sola vez por comprobante (PK del renglón): si ya
    // estaba, se reemplaza la cantidad.
    if (existente) existente.cantidad = cantidad;
    else renglones.push({ cod_vino: cod, nombre: sel.selectedOptions[0].textContent.split(' · stock')[0], cantidad });
    dibujar();
  };

  document.getElementById('registrar').onclick = async () => {
    const $r = document.getElementById('resultado');
    try {
      const c = await api.crearVenta({
        id_cliente: Number($cli.value) || null,
        id_sala: Number(document.getElementById('sala').value),
        renglones: renglones.map(({ cod_vino, cantidad }) => ({ cod_vino, cantidad })),
      });
      $r.innerHTML = `
        <div class="exito">Venta registrada: comprobante N.º ${c.nro_comprobante} (${c.fecha}).</div>
        <div class="panel">
          <p><strong>${esc(c.cliente)}</strong> (${esc(c.tipo_cliente)}) · Sala ${c.id_sala} · ${esc(c.localidad)}</p>
          <div class="tabla"><table><thead><tr><th>Vino</th><th class="num">Cant.</th><th class="num">Precio unit.</th><th class="num">Desc.</th><th class="num">Subtotal</th></tr></thead><tbody>
          ${c.renglones.map((r) => `<tr><td>${esc(r.nombre)} ${r.anada}</td><td class="num">${r.cantidad}</td><td class="num">${pesos(r.precio_unitario)}</td>
            <td class="num">${Number(r.porcentaje_descuento)} %</td><td class="num">${pesos(r.subtotal)}</td></tr>`).join('')}</tbody></table></div>
          <div class="totales" style="margin-top:12px">
            <div><span>Subtotal</span><span>${pesos(c.subtotal)}</span></div>
            <div><span>Descuento</span><span>− ${pesos(c.descuento)}</span></div>
            <div class="total"><span>Total</span><span>${pesos(c.total)}</span></div>
          </div>
          <p class="sub">Importes calculados por la base (trigger RN-08).</p>
        </div>`;
      renglones.length = 0;
      dibujar();
    } catch (e) {
      $r.innerHTML = cajaError(e) + '<p class="sub">La venta no se registró: no quedó ningún dato a medias.</p>';
    }
  };
}

// ---------------------------------------------------------------------
// 4. Transferencias
// ---------------------------------------------------------------------
async function pantallaTransferencias() {
  const cat = await cargarCatalogos();
  let actual = null;
  const filtros = { estado: '', sala: '', tamanio: 25 };

  $vista.innerHTML = `
    <h1>Transferencias</h1>
    <p class="sub">Circuito en_confeccion → terminado → procesado. Los botones se habilitan según el estado; la base valida cada paso.</p>
    <div class="dos">
      <div>
        <div class="panel grilla">
          <label>Estado<select id="t-estado">${opciones(['en_confeccion', 'terminado', 'procesado'], (x) => x, (x) => x, '', 'Todos')}</select></label>
          <label>Sala<select id="t-sala">${opciones(cat.salas, 'id_sala', nombreSala, '', 'Todas')}</select></label>
        </div>
        <div class="panel acciones" style="margin-top:0">
          <label style="flex:1">Nueva transferencia para<select id="nueva-sala">${opciones(cat.salas, 'id_sala', nombreSala)}</select></label>
          <button id="crear">Crear</button>
        </div>
        <div id="lista" class="tabla"></div>
      </div>
      <div id="detalle" class="panel"><p class="vacio">Elegí una transferencia.</p></div>
    </div>`;

  async function listar() {
    try {
      const r = await api.transferencias(filtros);
      document.getElementById('lista').innerHTML = r.datos.length
        ? `<table><thead><tr><th>N.º</th><th>Fecha</th><th>Sala</th><th>Estado</th><th class="num">Botellas</th></tr></thead><tbody>
          ${r.datos.map((t) => `<tr class="clic ${actual === t.numero ? 'sel' : ''}" data-nro="${t.numero}"><td>${t.numero}</td><td>${t.fecha}</td>
            <td>${t.id_sala} · ${esc(t.localidad)}</td><td><span class="chip ${t.estado}">${t.estado}</span></td><td class="num">${numero(t.botellas)}</td></tr>`).join('')}</tbody></table>`
        : '<p class="vacio" style="padding:12px">No hay transferencias con esos filtros.</p>';
      document.querySelectorAll('tr[data-nro]').forEach((tr) => (tr.onclick = () => detalle(Number(tr.dataset.nro))));
    } catch (e) {
      document.getElementById('lista').innerHTML = cajaError(e);
    }
  }

  async function detalle(nro, error) {
    actual = nro;
    const t = await api.transferencia(nro);
    const editable = t.estado === 'en_confeccion';
    document.getElementById('detalle').innerHTML = `
      <h2 style="margin-top:0">Transferencia N.º ${t.numero} <span class="chip ${t.estado}">${t.estado}</span></h2>
      <p class="sub">Sala ${t.id_sala} · ${esc(t.localidad)} · confeccionada el ${t.fecha} (fecha fijada por la base)</p>
      ${cajaError(error)}
      <div class="tabla">${t.renglones.length
        ? `<table><thead><tr><th>Vino</th><th class="num">Cantidad</th><th class="num">Stock depósito</th><th></th></tr></thead><tbody>
          ${t.renglones.map((r) => `<tr><td>${esc(r.nombre)} ${r.anada} · ${r.volumen_ml} ml</td><td class="num">${r.cantidad}</td>
            <td class="num">${numero(r.stock_deposito)}</td><td><button class="sec chico" data-quitar="${r.cod_vino}" ${editable ? '' : 'disabled'}>Quitar</button></td></tr>`).join('')}</tbody></table>`
        : '<p class="vacio" style="padding:12px">Sin renglones.</p>'}</div>
      <div class="grilla" style="margin-top:12px">${selectorVino('t-vino')}
        <label>Cantidad<input id="t-cant" type="number" min="1" value="12"></label></div>
      <div class="acciones">
        <button class="sec" id="t-agregar" ${editable ? '' : 'disabled'}>Agregar renglón</button>
        <button id="t-terminar" ${t.estado === 'en_confeccion' ? '' : 'disabled'}>Terminar</button>
        <button id="t-procesar" ${t.estado === 'terminado' ? '' : 'disabled'}>Procesar</button>
      </div>
      <p class="sub" style="margin-top:8px">Los botones deshabilitados solo ayudan al usuario: aunque se llamara a la API igual, la base rechazaría el cambio (RN-11, RN-12).</p>`;
    activarSelectorVino('t-vino');

    const accion = async (fn, ok) => {
      try {
        await fn();
        aviso(ok);
        await detalle(nro);
      } catch (e) {
        await detalle(nro, e);
      }
      listar();
    };
    document.getElementById('t-agregar').onclick = () => {
      const cod = Number(document.getElementById('t-vino').value);
      if (!cod) return aviso('Elegí un vino.');
      accion(() => api.guardarRenglon(nro, { cod_vino: cod, cantidad: Number(document.getElementById('t-cant').value) }), 'Renglón guardado');
    };
    document.querySelectorAll('[data-quitar]').forEach((b) => (b.onclick = () => accion(() => api.quitarRenglon(nro, b.dataset.quitar), 'Renglón quitado')));
    document.getElementById('t-terminar').onclick = () => accion(() => api.terminar(nro), 'Transferencia terminada');
    document.getElementById('t-procesar').onclick = () => accion(() => api.procesar(nro), 'Transferencia procesada: stock movido');
    listar();
  }

  document.getElementById('t-estado').onchange = (e) => { filtros.estado = e.target.value; listar(); };
  document.getElementById('t-sala').onchange = (e) => { filtros.sala = e.target.value; listar(); };
  document.getElementById('crear').onclick = async () => {
    try {
      const t = await api.crearTransferencia({ id_sala: Number(document.getElementById('nueva-sala').value) });
      aviso(`Transferencia ${t.numero} creada`);
      await detalle(t.numero);
    } catch (e) {
      document.getElementById('detalle').innerHTML = cajaError(e);
    }
  };
  listar();
}

// ---------------------------------------------------------------------
// 5. Tablero
// ---------------------------------------------------------------------
function barras(filas, etiqueta, valor, formato) {
  const max = Math.max(...filas.map((f) => Number(valor(f))), 1);
  return `<div class="barras">${filas
    .map((f) => `<div class="fila"><span class="etiqueta" title="${esc(etiqueta(f))}">${esc(etiqueta(f))}</span>
      <div class="barra-fondo"><div class="barra-valor" style="width:${(100 * Number(valor(f))) / max}%"></div></div>
      <span class="valor">${formato(valor(f))}</span></div>`)
    .join('')}</div>`;
}

async function pantallaTablero() {
  const cat = await cargarCatalogos();
  $vista.innerHTML = `
    <h1>Tablero</h1>
    <p class="sub">Consultas de la sección 8 expuestas por la API (S1, S8 y S6).</p>
    <div class="dos">
      <div class="panel"><h2 style="margin-top:0">Los 10 vinos más vendidos (botellas)</h2><div id="top"></div></div>
      <div class="panel"><h2 style="margin-top:0">Ventas por sala · último trimestre</h2><div id="salas" style="max-height:420px;overflow:auto"></div></div>
    </div>
    <div class="panel">
      <h2 style="margin-top:0">Vinos sin stock en la sala, con stock en el depósito</h2>
      <label style="max-width:420px">Sala<select id="sala-sin">${opciones(cat.salas, 'id_sala', nombreSala, 1)}</select></label>
      <div id="sin-stock" class="tabla" style="margin-top:12px;max-height:360px;overflow:auto"></div>
    </div>`;

  try {
    const [top, salas] = await Promise.all([api.topVinos(), api.ventasPorSala()]);
    document.getElementById('top').innerHTML = barras(top, (v) => `${v.nombre} ${v.anada} · ${v.volumen_ml} ml`, (v) => v.botellas, numero);
    const pesosEnteros = (v) => Number(v).toLocaleString('es-AR', { style: 'currency', currency: 'ARS', maximumFractionDigits: 0 });
    document.getElementById('salas').innerHTML = barras(salas, (s) => `Sala ${s.id_sala} · ${s.localidad}`, (s) => s.monto_total, pesosEnteros);
  } catch (e) {
    document.getElementById('top').innerHTML = cajaError(e);
  }

  const sinStock = async () => {
    const filas = await api.vinosSinStock(document.getElementById('sala-sin').value);
    document.getElementById('sin-stock').innerHTML = filas.length
      ? `<table><thead><tr><th>Cód.</th><th>Vino</th><th class="num">Stock en depósito</th></tr></thead><tbody>
        ${filas.map((v) => `<tr><td>${v.cod_vino}</td><td>${esc(v.nombre)} ${v.anada} · ${v.volumen_ml} ml</td><td class="num">${numero(v.stock_deposito)}</td></tr>`).join('')}</tbody></table>`
      : '<p class="vacio" style="padding:12px">La sala tiene stock de todos los vinos disponibles en el depósito.</p>';
  };
  document.getElementById('sala-sin').onchange = sinStock;
  sinStock();
}

// ---------------------------------------------------------------------
// Enrutador
// ---------------------------------------------------------------------
const rutas = [
  [/^#\/catalogo$/, pantallaCatalogo],
  [/^#\/vino\/nuevo$/, () => pantallaVino(null)],
  [/^#\/vino\/(\d+)$/, (m) => pantallaVino(m[1])],
  [/^#\/venta$/, pantallaVenta],
  [/^#\/transferencias$/, pantallaTransferencias],
  [/^#\/tablero$/, pantallaTablero],
];

async function navegar() {
  const hash = location.hash || '#/catalogo';
  document.querySelectorAll('nav a').forEach((a) => a.classList.toggle('activo', hash.startsWith(a.getAttribute('href'))));
  for (const [patron, pantalla] of rutas) {
    const m = hash.match(patron);
    if (m) {
      $vista.innerHTML = '<p class="vacio">Cargando…</p>';
      try {
        await pantalla(m);
      } catch (e) {
        $vista.innerHTML = cajaError(e instanceof ApiError ? e : new ApiError(0, { error: { mensaje: e.message } }));
      }
      return;
    }
  }
  location.hash = '#/catalogo';
}

async function verificarApi() {
  const el = document.getElementById('estado-api');
  try {
    const s = await api.salud();
    el.textContent = `API ok · rol ${s.rol}`;
    el.className = 'estado ok';
  } catch {
    el.textContent = 'API sin conexión';
    el.className = 'estado mal';
  }
}

window.addEventListener('hashchange', navegar);
navegar();
verificarApi();
