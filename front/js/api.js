// =====================================================================
// api.js · Única capa del front que habla con la API.
// Si la API responde un error, se lanza un ApiError con el mensaje TAL
// CUAL lo devolvió la base (por ejemplo "RN-09: stock insuficiente ...").
// =====================================================================
const BASE = (window.API_URL || 'http://localhost:3000').replace(/\/$/, '');

export class ApiError extends Error {
  constructor(status, cuerpo) {
    super(cuerpo?.error?.mensaje || `Error ${status}`);
    this.status = status;
    this.sqlstate = cuerpo?.error?.sqlstate;
    this.regla = cuerpo?.error?.regla;
    this.restriccion = cuerpo?.error?.restriccion;
  }
}

async function pedir(metodo, ruta, cuerpo) {
  let res;
  try {
    res = await fetch(BASE + ruta, {
      method: metodo,
      headers: cuerpo ? { 'Content-Type': 'application/json' } : {},
      body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
  } catch {
    throw new ApiError(0, { error: { mensaje: `No se pudo conectar con la API (${BASE}).` } });
  }
  const texto = await res.text();
  const datos = texto ? JSON.parse(texto) : null;
  if (!res.ok) throw new ApiError(res.status, datos);
  return datos;
}

const qs = (params) => {
  const p = new URLSearchParams();
  Object.entries(params).forEach(([k, v]) => v !== undefined && v !== null && v !== '' && p.set(k, v));
  const s = p.toString();
  return s ? `?${s}` : '';
};

export const api = {
  salud: () => pedir('GET', '/salud'),
  catalogos: () => pedir('GET', '/catalogos'),

  vinos: (filtros) => pedir('GET', `/vinos${qs(filtros)}`),
  vino: (cod) => pedir('GET', `/vinos/${cod}`),
  crearVino: (datos) => pedir('POST', '/vinos', datos),
  modificarVino: (cod, datos) => pedir('PUT', `/vinos/${cod}`, datos),
  precios: (cod) => pedir('GET', `/vinos/${cod}/precios`),

  clientes: (filtros) => pedir('GET', `/clientes${qs(filtros)}`),
  crearVenta: (datos) => pedir('POST', '/comprobantes', datos),

  transferencias: (filtros) => pedir('GET', `/transferencias${qs(filtros)}`),
  transferencia: (nro) => pedir('GET', `/transferencias/${nro}`),
  crearTransferencia: (datos) => pedir('POST', '/transferencias', datos),
  guardarRenglon: (nro, datos) => pedir('POST', `/transferencias/${nro}/renglones`, datos),
  quitarRenglon: (nro, cod) => pedir('DELETE', `/transferencias/${nro}/renglones/${cod}`),
  terminar: (nro) => pedir('POST', `/transferencias/${nro}/terminar`),
  procesar: (nro) => pedir('POST', `/transferencias/${nro}/procesar`),

  topVinos: () => pedir('GET', '/reportes/top-vinos?limite=10'),
  ventasPorSala: () => pedir('GET', '/reportes/ventas-por-sala'),
  vinosSinStock: (sala) => pedir('GET', `/reportes/vinos-sin-stock${qs({ sala })}`),
};
