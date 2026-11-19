import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const rutas = {
  profesores: '/api/usuario?rol=profesor&page=1&limit=12',
  tutorias: '/api/tutoria?page=1&limit=50',
  listado: '/api/admin/full-tutorials?page=1&limit=50',
  resumen: '/api/admin/summary',
  mensual: '/api/admin/tutorials-by-month',
};
const escenario = __ENV.ESCENARIO || 'profesores';
if (!rutas[escenario]) throw new Error('ESCENARIO desconocido');
const token = __ENV.RENDIMIENTO_TOKEN || __ENV.H23_TOKEN;
if (!token) throw new Error('Falta RENDIMIENTO_TOKEN');
const base = (__ENV.BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const errores = new Rate('errores_funcionales');
export const options = {
  vus: Number(__ENV.USUARIOS || 1),
  duration: __ENV.DURACION || '15s',
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
  thresholds: {
    errores_funcionales: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '15s' }],
  },
};
function consultar() {
  const r = http.get(base + rutas[escenario], {
    headers: { Authorization: `Bearer ${token}` },
    tags: { name: escenario }, timeout: '30s', redirects: 0,
  });
  let body;
  try { body = r.json(); } catch (_) { body = null; }
  const valido = r.status === 200 && body &&
    (escenario === 'profesores'
      ? Array.isArray(body.data) && !!body.pagination
      : body.status === 1 && body.data !== undefined);
  const ok = check(r, { 'HTTP 200 y respuesta funcional': () => !!valido });
  errores.add(!ok);
  return ok;
}
export function setup() {
  if (!consultar()) throw new Error('Prevalidacion fallida: revisar token, rol y endpoint');
}
export default function () {
  consultar();
  sleep(1);
}
