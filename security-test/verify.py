"""Verificacion acotada del laboratorio; no es un escaneo de vulnerabilidades."""
import json
import argparse
from datetime import datetime, timezone
import socket
import subprocess
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import ProxyHandler, Request, build_opener

ROOT = Path(__file__).resolve().parent.parent
COMPOSE = [
    "docker", "compose", "--env-file", ".env.security-test",
    "-p", "hia-security-test", "-f", "compose.security-test.yaml",
]
BASE = "http://127.0.0.1:9081"
HTTP = build_opener(ProxyHandler({}))


def run(*args):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=30)
    if result.returncode:
        # No volcar stdout/stderr: algunos comandos Docker pueden incluir variables.
        raise RuntimeError(f"Fallo de verificacion al ejecutar {args[0]}")
    return result.stdout.strip()


def request(path, data=None, token=None, method=None):
    headers = {}
    if data is not None:
        data = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(BASE + path, data=data, headers=headers, method=method)
    try:
        response = HTTP.open(req, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read()


def assert_no_connection(host, port):
    script = """
const net = require('node:net');
const s = net.connect({host: process.argv[1], port: Number(process.argv[2])});
s.setTimeout(2000);
s.once('connect', () => {s.destroy(); process.exitCode = 1;});
s.once('error', () => {});
s.once('timeout', () => s.destroy());
"""
    run(*COMPOSE, "exec", "-T", "backend", "node", "-e", script, host, str(port))


def main():
    ids = run(*COMPOSE, "ps", "-q").splitlines()
    assert len(ids) == 3, "Deben existir exactamente tres servicios activos"
    containers = json.loads(run("docker", "inspect", *ids))
    expected_networks = {
        "backend": {"hia-security-test_isolated"},
        "database": {"hia-security-test_isolated"},
        "frontend": {"hia-security-test_isolated", "hia-security-test_entry"},
    }
    for container in containers:
        service = container["Config"]["Labels"]["com.docker.compose.service"]
        assert container["State"]["Health"]["Status"] == "healthy"
        assert not container["HostConfig"]["Privileged"]
        assert set(container["NetworkSettings"]["Networks"]) == expected_networks[service]
        ports = container["HostConfig"]["PortBindings"] or {}
        assert ports == (
            {"80/tcp": [{"HostIp": "127.0.0.1", "HostPort": "9081"}]}
            if service == "frontend" else {}
        ), "Publicacion inesperada"
        for mount in container["Mounts"]:
            if mount["Type"] == "volume":
                assert service == "database"
                assert mount["Name"] == "hia-security-test_test_database"
            else:
                assert "/security-test" in mount["Source"].replace("\\", "/")
                assert not mount["RW"]
        print(f"OK {service}: sano, redes y montajes propios; imagen {container['Image'][:19]}")

    network = json.loads(run("docker", "network", "inspect", "hia-security-test_isolated"))[0]
    assert network["Internal"]
    assert set(network["Containers"]) == set(ids), "Hay otros contenedores en la red aislada"
    run("git", "check-ignore", "-q", ".env.security-test")
    # Control positivo: Internet es alcanzable desde el host.
    with socket.create_connection(("1.1.1.1", 443), timeout=5):
        pass
    assert_no_connection("1.1.1.1", 443)

    class Sentinel(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()

        def log_message(self, *_):
            pass

    # Un servicio temporal propio evita sondear los puertos de produccion.
    with HTTPServer(("127.0.0.1", 0), Sentinel) as sentinel:
        threading.Thread(target=sentinel.serve_forever, daemon=True).start()
        try:
            port = sentinel.server_port
            with HTTP.open(f"http://127.0.0.1:{port}", timeout=3) as response:
                assert response.status == 200
            assert_no_connection("host.docker.internal", port)
        finally:
            sentinel.shutdown()
    print("OK backend: sin acceso TCP al destino de Internet ni al receptor del host")

    status, headers, body = request("/")
    assert status == 200 and b"<app-root" in body
    assert headers["X-H24-Environment"] == "isolated-test"
    assert "connect-src 'self'" in headers["Content-Security-Policy"]
    status, _, body = request("/api/categoria/")
    assert status == 200 and b"Matematica H24" in body
    for path in [
        "/api/mercadopago/webhook", "/api/mercadopago/crear-preferencia",
        "/api/chat/", "/api/autenticacion/loginGoogle", "/api/autenticacion/signUpGoogle",
    ]:
        assert request(path, {})[0] == 503
    print("OK frontend/API; CSP local; Google, pagos, webhook e IA deshabilitados")

    secret = dict(
        line.split("=", 1) for line in (ROOT / ".env.security-test").read_text().splitlines()
        if line and not line.startswith("#")
    )["SECURITY_ACCOUNT_PASSWORD"]
    assert request("/api/admin/summary")[0] == 401
    verified_users = {}
    for name, expected in [("alumno.a", 403), ("admin", 200)]:
        status, _, body = request("/api/autenticacion/login", {
            "email": f"{name}@h24.test", "password": secret
        })
        assert status == 200, "Login limitado: esperar 15 min o reiniciar solo backend de H24"
        login = json.loads(body)
        assert login.get("status") == 1
        verified_users[name] = {"id": login["id"], "token": login["token"]}
        assert request("/api/admin/summary", token=login["token"])[0] == expected
        if name == "alumno.a":
            status, _, body = request("/api/tutoria/", token=login["token"])
            assert status == 200 and len(json.loads(body)["data"]) == 2
    print("OK cuentas locales: acceso administrativo 401/403/200 y tutorias sinteticas")

    run(*COMPOSE, "exec", "-T", "backend", "node", "-e", """
const assert = require('node:assert/strict');
(async () => {
  const calendar = require('./src/services/google-calendar.service');
  const event = await calendar.agendarTutoria({id: 'verify'});
  assert.equal(event.idEvento, 'h24-simulated-verify');
  assert.equal(event.linkMeet, null);
  assert.equal((await calendar.cancelarTutoria(event.idEvento)).exito, true);
  const payments = require('./src/services/mercadoPago.service');
  const ai = require('./src/services/ai.service');
  await assert.rejects(payments.crearPreferencia(1), /deshabilitada/);
  await assert.rejects(payments.procesarWebhook({}), /deshabilitada/);
  await assert.rejects(ai.getResponse('', ''), /deshabilitada/);
})().catch(() => {process.exitCode = 1;});
""")
    print("OK Calendar simulado y adaptadores sin llamadas externas")
    print("Laboratorio verificado. No se ejecutaron SQLi, ZAP ni pruebas completas de H24.")
    return verified_users


def authorization(verified_users):
    """Prueba acotada de propiedad; crea y elimina solo recursos marcados."""
    tag = "H24-AUTH-" + uuid.uuid4().hex
    results = []
    ids = []
    horario_ids = []
    categoria_ids = []
    ayuda_ids = {}

    def fixtures(action):
        script = """
require('./security-test/guard.cjs')();
const assert = require('node:assert/strict');
const db = require('./config/database');
const Usuario = require('./src/models/usuario.model');
const Categoria = require('./src/models/categoria.model');
const Tutoria = require('./src/models/tutoria.model');
const HorarioDisponible = require('./src/models/horarioDisponible.model');
const { Op } = require('sequelize');
const [action, tag, rawIds] = process.argv.slice(1);
const ids = JSON.parse(rawIds);
(async () => {
  const [identity] = await db.query('SELECT current_database() AS name');
  assert.equal(identity[0].name, 'h24_security_test');
  let data;
  if (action === 'create') {
    const alumno = await Usuario.findOne({where:{email:'alumno.b@h24.test'}});
    const profesor = await Usuario.findOne({where:{email:'profesor.b@h24.test'}});
    const categoria = await Categoria.findOne({where:{nombre:'Matematica H24'}});
    assert.ok(alumno && profesor && categoria);
    data = await db.transaction(async transaction => {
      const rows = [];
      for (let n = 0; n < 4; n++) {
        const row = await Tutoria.create({
          alumnoId:alumno.id, profesorId:profesor.id, categoriaId:categoria.id,
          fechaHora:'2026-11-23T15:00:00Z', modalidad:'virtual',
          estado:'pendiente', precioAcordado:100, mensaje:tag+'-'+n
        }, {transaction});
        rows.push(row.id);
      }
      return rows;
    });
  } else {
    const where = {id:{[Op.in]:ids}, mensaje:{[Op.like]:tag+'%'}};
    if (action === 'cleanup') await Tutoria.destroy({where});
    data = await Tutoria.findAll({
      where:{id:{[Op.in]:ids}}, attributes:['id','mensaje','estado'], raw:true
    });
  }
  console.log('H24_RESULT='+JSON.stringify(data));
})().catch(() => {process.exitCode=1;}).finally(() => db.close());
"""
        output = run(*COMPOSE, "exec", "-T", "backend", "node", "-e",
                     script, action, tag, json.dumps(ids))
        return json.loads(next(line.removeprefix("H24_RESULT=")
                               for line in output.splitlines() if line.startswith("H24_RESULT=")))

    def horario_fixture(action, horario_id=0):
        script = """
require('./security-test/guard.cjs')();
const assert = require('node:assert/strict');
const db = require('./config/database');
const Usuario = require('./src/models/usuario.model');
const HorarioDisponible = require('./src/models/horarioDisponible.model');
const [action, rawId] = process.argv.slice(1);
const id = Number(rawId);
(async () => {
  const [identity] = await db.query('SELECT current_database() AS name');
  assert.equal(identity[0].name, 'h24_security_test');
  const profesor = await Usuario.findOne({where:{email:'profesor.b@h24.test'}});
  assert.ok(profesor);
  let data = null;
  if (action === 'create') {
    const row = await HorarioDisponible.create({
      profesorId:profesor.id, diaSemana:'sabado', horaInicio:'18:00',
      horaFin:'19:00', modalidad:'virtual', estado:'activo'
    });
    data = {id:row.id, profesorId:row.profesorId};
  } else if (action === 'read') {
    data = await HorarioDisponible.findByPk(id, {
      attributes:['id','profesorId','estado'], raw:true
    });
  } else {
    data = await HorarioDisponible.destroy({where:{id}});
  }
  console.log('H24_RESULT='+JSON.stringify(data));
})().catch(() => {process.exitCode=1;}).finally(() => db.close());
"""
        output = run(*COMPOSE, "exec", "-T", "backend", "node", "-e",
                     script, action, str(horario_id))
        return json.loads(next(line.removeprefix("H24_RESULT=")
                               for line in output.splitlines() if line.startswith("H24_RESULT=")))

    def categoria_fixture(action, categoria_id=0):
        script = """
require('./security-test/guard.cjs')();
const assert = require('node:assert/strict');
const db = require('./config/database');
const Categoria = require('./src/models/categoria.model');
const ProfesorCategoria = require('./src/models/profesorCategoria.model');
const [action, rawId, tag] = process.argv.slice(1);
const id = Number(rawId);
(async () => {
  const [identity] = await db.query('SELECT current_database() AS name');
  assert.equal(identity[0].name, 'h24_security_test');
  let data = null;
  if (action === 'create') {
    const row = await Categoria.create({
      nombre:tag + '-categoria', nivel:'primario', descripcion:tag
    });
    data = {id:row.id, nombre:row.nombre};
  } else if (action === 'read') {
    data = await Categoria.findByPk(id, {
      attributes:['id','nombre','nivel'], raw:true
    });
  } else {
    await ProfesorCategoria.destroy({where:{categoriaId:id}});
    data = await Categoria.destroy({where:{id}});
  }
  console.log('H24_RESULT='+JSON.stringify(data));
})().catch(() => {process.exitCode=1;}).finally(() => db.close());
"""
        output = run(*COMPOSE, "exec", "-T", "backend", "node", "-e",
                     script, action, str(categoria_id), tag)
        return json.loads(next(line.removeprefix("H24_RESULT=")
                               for line in output.splitlines() if line.startswith("H24_RESULT=")))

    def ayuda_fixture(action, fixture_ids=None):
        fixture_ids = fixture_ids or {}
        script = """
require('./security-test/guard.cjs')();
const assert = require('node:assert/strict');
const db = require('./config/database');
const Usuario = require('./src/models/usuario.model');
const Categoria = require('./src/models/categoria.model');
const Tutoria = require('./src/models/tutoria.model');
const Calificacion = require('./src/models/calificacion.model');
const { SolicitudAyuda, RespuestaAyuda } =
  require('./src/models/solicitudes/asociaciones.model');
const { Op } = require('sequelize');
const [action, rawIds, tag] = process.argv.slice(1);
const ids = JSON.parse(rawIds);
(async () => {
  const [identity] = await db.query('SELECT current_database() AS name');
  assert.equal(identity[0].name, 'h24_security_test');
  let data = null;
  if (action === 'create') {
    const alumno = await Usuario.findOne({where:{email:'alumno.b@h24.test'}});
    const profesor = await Usuario.findOne({where:{email:'profesor.a@h24.test'}});
    const categoria = await Categoria.findOne({where:{nombre:'Matematica H24'}});
    assert.ok(alumno && profesor && categoria);
    const solicitudes = [];
    for (const name of ['edit','close','delete','resp']) {
      const row = await SolicitudAyuda.create({
        usuarioId:alumno.id, categoriaId:categoria.id,
        titulo:tag + '-sol-' + name, descripcion:tag
      });
      solicitudes.push(row.id);
    }
    const respuesta = await RespuestaAyuda.create({
      solicitudId:solicitudes[3], usuarioId:profesor.id,
      respuesta:tag + '-resp-aceptar', precio:100
    });
    const tutoria = await Tutoria.create({
      alumnoId:alumno.id, profesorId:profesor.id, categoriaId:categoria.id,
      fechaHora:'2026-11-23T16:00:00Z', modalidad:'virtual',
      estado:'finalizada', precioAcordado:100, mensaje:tag + '-cal',
      pagada:true
    });
    data = {solicitudes, respuestas:[respuesta.id], tutorias:[tutoria.id]};
  } else {
    await RespuestaAyuda.destroy({where:{[Op.or]:[
      {id:{[Op.in]:ids.respuestas || []}}, {respuesta:{[Op.like]:tag + '%'}}
    ]}});
    await SolicitudAyuda.destroy({where:{[Op.or]:[
      {id:{[Op.in]:ids.solicitudes || []}}, {titulo:{[Op.like]:tag + '%'}}
    ]}});
    await Calificacion.destroy({where:{comentario:{[Op.like]:tag + '%'}}});
    await Tutoria.destroy({where:{mensaje:{[Op.like]:tag + '%'}}});
    data = true;
  }
  console.log('H24_RESULT='+JSON.stringify(data));
})().catch(() => {process.exitCode=1;}).finally(() => db.close());
"""
        output = run(*COMPOSE, "exec", "-T", "backend", "node", "-e",
                     script, action, json.dumps(fixture_ids), tag)
        return json.loads(next(line.removeprefix("H24_RESULT=")
                               for line in output.splitlines() if line.startswith("H24_RESULT=")))

    def user_field(email, field):
        script = """
require('./security-test/guard.cjs')();
const db = require('./config/database');
const Usuario = require('./src/models/usuario.model');
const [email, field] = process.argv.slice(1);
(async () => {
  const row = await Usuario.findOne({where:{email}, attributes:['id',field], raw:true});
  console.log('H24_RESULT='+JSON.stringify(row ? row[field] : null));
})().catch(() => {process.exitCode=1;}).finally(() => db.close());
"""
        output = run(*COMPOSE, "exec", "-T", "backend", "node", "-e",
                     script, email, field)
        return json.loads(next(line.removeprefix("H24_RESULT=")
                               for line in output.splitlines() if line.startswith("H24_RESULT=")))

    def record(case, expected, status, passed, observation):
        results.append({
            "case": case, "expected": expected, "http_status": status,
            "passed": passed, "observation": observation,
        })
        print(f"{'PASS' if passed else 'FAIL'} {case}: HTTP {status}; {observation}")

    secret = dict(
        line.split("=", 1) for line in (ROOT / ".env.security-test").read_text().splitlines()
        if line and not line.startswith("#")
    )["SECURITY_ACCOUNT_PASSWORD"]
    users = {name: verified_users[name] for name in ["alumno.a", "admin"]}
    for account in ["alumno.b", "profesor.a"]:
        status, _, body = request("/api/autenticacion/login", {
            "email": account + "@h24.test", "password": secret
        })
        assert status == 200, "Login limitado; esperar 15 min o reiniciar solo backend H24"
        login = json.loads(body)
        assert login.get("status") == 1
        users[account] = {"id": login["id"], "token": login["token"]}
    try:
        ids = fixtures("create")
        read_id, edit_id, delete_id, owner_id = ids[:4]
        status, _, body = request("/api/categoria/")
        categoria_id = json.loads(body)["data"][0]["id"]

        status, _, body = request("/api/tutoria/", {
            "alumnoId": users["alumno.b"]["id"],
            "profesorId": users["profesor.a"]["id"],
            "categoriaId": categoria_id,
            "fechaHora": "2026-11-23T15:00:00Z",
            "modalidad": "virtual",
            "precioAcordado": 100,
            "mensaje": tag + "-impersonated"
        }, users["alumno.a"]["token"])
        created_id = (json.loads(body).get("data") or {}).get("id")
        if created_id: ids.append(created_id)
        record("A crea tutoria a nombre de B", "403 sin crear recurso", status,
               status == 403 and not created_id,
               f"alta indebida creada: {bool(created_id)}")

        status, _, body = request("/api/tutoria/", {
            "alumnoId": users["alumno.a"]["id"],
            "profesorId": users["profesor.a"]["id"],
            "categoriaId": categoria_id,
            "fechaHora": "2026-11-23T15:00:00Z",
            "modalidad": "virtual",
            "precioAcordado": 100,
            "mensaje": tag + "-owner-create",
            "estado": "aceptada"
        }, users["alumno.a"]["token"])
        own_id = (json.loads(body).get("data") or {}).get("id")
        if own_id: ids.append(own_id)
        own_row = next((row for row in fixtures("read") if row["id"] == own_id), {})
        record("A crea su propia tutoria", "200 pendiente, ignora estado enviado", status,
               status == 200 and own_row.get("estado") == "pendiente",
               f"estado persistido: {own_row.get('estado')}")

        status, _, _ = request(f"/api/tutoria/{own_id}", {
            "estado": "aceptada"
        }, users["alumno.a"]["token"], "PUT")
        record("Alumno acepta su tutoria", "403 sin cambio de estado", status,
               status == 403, "solo profesor/admin puede cambiar estado")

        status, _, _ = request(f"/api/tutoria/{own_id}", {
            "estado": "aceptada"
        }, users["profesor.a"]["token"], "PUT")
        own_row = next((row for row in fixtures("read") if row["id"] == own_id), {})
        record("Profesor acepta tutoria propia", "200 con Calendar simulado", status,
               status == 200 and own_row.get("estado") == "aceptada",
               f"estado persistido: {own_row.get('estado')}")
        for name, token in [("sin token", None), ("token invalido", "h24-invalid")]:
            status, _, _ = request(f"/api/tutoria/{read_id}", token=token)
            record("GET " + name, "401", status, status == 401, "control de autenticacion")

        status, _, body = request("/api/tutoria/", token=users["alumno.a"]["token"])
        b_fixture_ids = set(ids[:4])
        visible = {row["id"] for row in json.loads(body).get("data", [])}
        record("Listado de A", "200 sin recursos de B", status,
               status == 200 and not visible.intersection(b_fixture_ids),
               "lista excluye fixtures de B" if not visible.intersection(b_fixture_ids) else "lista expone fixtures de B")

        status, _, body = request(f"/api/tutoria/{read_id}", token=users["alumno.a"]["token"])
        data = json.loads(body).get("data") or {}
        exposed = data.get("id") == read_id
        record("A consulta tutoria de B", "403/404 sin datos ajenos", status,
               status in (403, 404) and not exposed,
               f"recurso ajeno devuelto: {exposed}")

        status, _, _ = request(f"/api/tutoria/{edit_id}", {
            "mensaje": tag + "-modified-by-A"
        }, users["alumno.a"]["token"], "PUT")
        rows = {row["id"]: row["mensaje"] for row in fixtures("read")}
        changed = rows.get(edit_id) == tag + "-modified-by-A"
        record("A modifica tutoria de B", "403/404 y mensaje intacto", status,
               status in (403, 404) and rows.get(edit_id) == tag + "-1",
               f"cambio ajeno confirmado en BD: {changed}")

        status, _, _ = request(f"/api/tutoria/{delete_id}",
                               token=users["alumno.a"]["token"], method="DELETE")
        remaining = {row["id"] for row in fixtures("read")}
        record("A borra tutoria de B", "403/404 y fila conservada", status,
               status in (403, 404) and delete_id in remaining,
               f"borrado ajeno confirmado en BD: {delete_id not in remaining}")

        status, _, body = request(f"/api/tutoria/{owner_id}", token=users["alumno.b"]["token"])
        record("B consulta su tutoria", "200 con recurso propio", status,
               status == 200 and (json.loads(body).get("data") or {}).get("id") == owner_id,
               "control positivo del propietario")
        status, _, _ = request(f"/api/tutoria/{owner_id}", {
            "mensaje": tag + "-modified-by-owner"
        }, users["alumno.b"]["token"], "PUT")
        rows = {row["id"]: row["mensaje"] for row in fixtures("read")}
        record("B modifica su tutoria", "200 y mensaje actualizado", status,
               status == 200 and rows.get(owner_id) == tag + "-modified-by-owner",
               "control positivo del propietario; no evalua transiciones de estado")
        status, _, _ = request(f"/api/tutoria/{owner_id}",
                               token=users["alumno.b"]["token"], method="DELETE")
        remaining = {row["id"] for row in fixtures("read")}
        record("B borra su tutoria", "200 y fila eliminada", status,
               status == 200 and owner_id not in remaining, "control positivo del propietario")

        nombre_b = user_field("alumno.b@h24.test", "nombre")
        status, _, _ = request(f"/api/usuario/{users['alumno.b']['id']}", {
            "nombre": tag + "-usuario"
        }, users["alumno.a"]["token"], "PUT")
        nombre_actual = user_field("alumno.b@h24.test", "nombre")
        record("A modifica perfil de B", "403 y nombre intacto", status,
               status == 403 and nombre_actual == nombre_b,
               f"cambio ajeno confirmado en BD: {nombre_actual != nombre_b}")

        status, _, _ = request(f"/api/usuario/{users['alumno.b']['id']}", {
            "nombre": nombre_b
        }, users["alumno.b"]["token"], "PUT")
        record("B modifica su propio perfil", "200 sin cambio material", status,
               status == 200 and user_field("alumno.b@h24.test", "nombre") == nombre_b,
               "control positivo del propietario")

        horario_ajeno = horario_fixture("create")
        horario_ids.append(horario_ajeno["id"])
        status, _, body = request("/api/horarioDisponible", {
            "profesorId": horario_ajeno["profesorId"], "diaSemana": "domingo",
            "horaInicio": "10:00", "horaFin": "11:00", "modalidad": "virtual"
        }, users["alumno.a"]["token"])
        horario_indebido = (json.loads(body).get("data") or {}).get("id")
        if horario_indebido:
            horario_ids.append(horario_indebido)
        record("A crea horario para profesor B", "403 sin crear recurso", status,
               status == 403 and not horario_indebido,
               f"alta indebida creada: {bool(horario_indebido)}")

        status, _, _ = request(f"/api/horarioDisponible/{horario_ajeno['id']}",
                               token=users["alumno.a"]["token"], method="DELETE")
        row = horario_fixture("read", horario_ajeno["id"])
        record("A desactiva horario de profesor B", "403 y horario activo", status,
               status == 403 and row.get("estado") == "activo",
               f"estado persistido: {row.get('estado')}")

        status, _, body = request("/api/horarioDisponible", {
            "profesorId": users["profesor.a"]["id"], "diaSemana": "domingo",
            "horaInicio": "12:00", "horaFin": "13:00", "modalidad": "virtual"
        }, users["profesor.a"]["token"])
        horario_propio = (json.loads(body).get("data") or {}).get("id")
        if horario_propio:
            horario_ids.append(horario_propio)
        record("Profesor crea su horario", "200 y recurso propio", status,
               status == 200 and bool(horario_propio), "control positivo del propietario")

        status, _, _ = request(f"/api/horarioDisponible/{horario_propio}",
                               token=users["profesor.a"]["token"], method="DELETE")
        row = horario_fixture("read", horario_propio)
        record("Profesor desactiva su horario", "200 y estado inactivo", status,
               status == 200 and row.get("estado") == "inactivo",
               f"estado persistido: {row.get('estado')}")

        status, _, _ = request("/api/usuario/horario", {
            "usuarioId": horario_ajeno["profesorId"], "diaSemana": "domingo",
            "horaInicio": "14:00", "horaFin": "15:00", "modalidad": "virtual"
        }, users["alumno.a"]["token"])
        record("A usa ruta legacy de horario ajeno", "403 sin crear recurso", status,
               status == 403, "ruta legacy tambien protegida")

        status, _, _ = request(f"/api/usuario/horario/{horario_ajeno['id']}",
                               token=users["alumno.a"]["token"], method="DELETE")
        row = horario_fixture("read", horario_ajeno["id"])
        record("A borra horario ajeno por ruta legacy", "403 y horario activo", status,
               status == 403 and row.get("estado") == "activo",
               f"estado persistido: {row.get('estado')}")

        categoria = categoria_fixture("create")
        categoria_ids.append(categoria["id"])
        status, _, _ = request(f"/api/categoria/{categoria['id']}", {
            "nombre": tag + "-sin-token"
        }, method="PUT")
        record("Sin token modifica categoria", "401", status,
               status == 401, "control de autenticacion")
        status, _, _ = request(f"/api/categoria/{categoria['id']}", {
            "nombre": tag + "-alumno"
        }, users["alumno.a"]["token"], "PUT")
        record("Alumno modifica categoria", "403", status,
               status == 403, "control de rol administrativo")
        status, _, _ = request(f"/api/categoria/{categoria['id']}", {
            "nombre": tag + "-actualizada"
        }, users["admin"]["token"], "PUT")
        row = categoria_fixture("read", categoria["id"])
        record("Admin modifica categoria", "200 y nombre persistido", status,
               status == 200 and row.get("nombre") == tag + "-actualizada",
               "control positivo administrativo")

        status, _, _ = request("/api/categoria", {
            "nombre": tag + "-sin-token", "nivel": "primario",
            "descripcion": "sin token"
        }, method="POST")
        record("Sin token crea categoria", "401", status,
               status == 401, "control de autenticacion")
        status, _, _ = request("/api/categoria", {
            "nombre": tag + "-alumno", "nivel": "primario",
            "descripcion": "alumno"
        }, users["alumno.a"]["token"])
        record("Alumno crea categoria", "403", status,
               status == 403, "control de rol administrativo")
        status, _, body = request("/api/categoria", {
            "nombre": tag + "-creada", "nivel": "primario",
            "descripcion": "admin"
        }, users["admin"]["token"])
        categoria_creada = (json.loads(body).get("data") or {}).get("id")
        if categoria_creada:
            categoria_ids.append(categoria_creada)
        record("Admin crea categoria", "200 y recurso propio", status,
               status == 200 and bool(categoria_creada),
               "control positivo administrativo")

        status, _, _ = request("/api/categoria/profesor", {
            "profesorId": users["profesor.a"]["id"], "categoriaId": categoria["id"]
        }, method="POST")
        record("Sin token asocia profesor-categoria", "401", status,
               status == 401, "control de autenticacion")
        status, _, _ = request("/api/categoria/profesor", {
            "profesorId": users["profesor.a"]["id"], "categoriaId": categoria["id"]
        }, users["alumno.a"]["token"])
        record("Alumno asocia profesor-categoria", "403", status,
               status == 403, "control de propietario")
        status, _, _ = request("/api/categoria/profesor", {
            "profesorId": users["profesor.a"]["id"], "categoriaId": categoria["id"]
        }, users["profesor.a"]["token"])
        record("Profesor asocia su categoria", "200", status,
               status == 200, "control positivo del propietario")
        status, _, _ = request("/api/categoria/profesor", {
            "profesorId": users["profesor.a"]["id"], "categoriaId": categoria["id"]
        }, users["profesor.a"]["token"], "DELETE")
        record("Profesor desasocia su categoria", "200", status,
               status == 200, "control positivo del propietario")

        status, _, _ = request(f"/api/categoria/{categoria['id']}", method="DELETE")
        record("Sin token borra categoria", "401", status,
               status == 401, "control de autenticacion")
        status, _, _ = request(f"/api/categoria/{categoria['id']}",
                               token=users["alumno.a"]["token"], method="DELETE")
        record("Alumno borra categoria", "403", status,
               status == 403, "control de rol administrativo")
        status, _, _ = request(f"/api/categoria/{categoria['id']}",
                               token=users["admin"]["token"], method="DELETE")
        row = categoria_fixture("read", categoria["id"])
        record("Admin borra categoria", "200 y recurso ausente", status,
               status == 200 and row is None,
               "control positivo administrativo")

        ayuda_ids = ayuda_fixture("create")
        sol_ids = ayuda_ids["solicitudes"]
        resp_aceptar = ayuda_ids["respuestas"][0]
        tutoria_calificar = ayuda_ids["tutorias"][0]

        status, _, body = request("/api/solicitud", token=users["alumno.a"]["token"])
        visibles = {row["id"] for row in json.loads(body).get("data", [])}
        record("Listado solicitudes de A", "200 sin solicitudes de B", status,
               status == 200 and not visibles.intersection(sol_ids),
               "lista filtrada por propietario")
        status, _, _ = request(f"/api/solicitud/{sol_ids[0]}",
                               token=users["alumno.a"]["token"])
        record("A consulta solicitud de B", "403", status,
               status == 403, "alumno ajeno rechazado")
        status, _, _ = request(f"/api/solicitud/{sol_ids[3]}",
                               token=users["profesor.a"]["token"])
        record("Profesor consulta solicitud abierta", "200", status,
               status == 200, "profesor puede responder solicitud abierta")
        status, _, _ = request(f"/api/solicitud/{sol_ids[3]}",
                               token=users["alumno.b"]["token"])
        record("B consulta su solicitud", "200", status,
               status == 200, "control positivo del propietario")

        status, _, body = request("/api/solicitud", {
            "usuarioId": users["alumno.b"]["id"], "categoriaId": categoria_id,
            "titulo": tag + "-sol-imp", "descripcion": "impersonada"
        }, users["alumno.a"]["token"])
        record("A crea solicitud para B", "403 sin crear", status,
               status == 403, "usuarioId ajeno rechazado")
        status, _, body = request("/api/solicitud", {
            "usuarioId": users["alumno.b"]["id"], "categoriaId": categoria_id,
            "titulo": tag + "-sol-own", "descripcion": "propia"
        }, users["alumno.b"]["token"])
        solicitud_propia = (json.loads(body).get("data") or {}).get("id")
        record("B crea su solicitud", "200", status,
               status == 200 and bool(solicitud_propia), "control positivo")
        if solicitud_propia:
            status, _, _ = request(f"/api/solicitud/{solicitud_propia}", {
                "titulo": tag + "-sol-own-edit"
            }, users["alumno.b"]["token"], "PUT")
            record("B edita su solicitud", "200", status,
                   status == 200, "control positivo")
            status, _, _ = request(f"/api/solicitud/{solicitud_propia}/cerrar",
                                   token=users["alumno.b"]["token"], method="PUT")
            record("B cierra su solicitud", "200", status,
                   status == 200, "control positivo")
            status, _, _ = request(f"/api/solicitud/{solicitud_propia}",
                                   token=users["alumno.b"]["token"], method="DELETE")
            record("B borra su solicitud", "200", status,
                   status == 200, "control positivo")

        status, _, _ = request(f"/api/solicitud/{sol_ids[0]}", {
            "titulo": tag + "-sol-mod"
        }, users["alumno.a"]["token"], "PUT")
        record("A edita solicitud de B", "403", status,
               status == 403, "propietario requerido")
        status, _, _ = request(f"/api/solicitud/{sol_ids[1]}/cerrar",
                               token=users["alumno.a"]["token"], method="PUT")
        record("A cierra solicitud de B", "403", status,
               status == 403, "propietario requerido")
        status, _, _ = request(f"/api/solicitud/{sol_ids[2]}",
                               token=users["alumno.a"]["token"], method="DELETE")
        record("A borra solicitud de B", "403", status,
               status == 403, "propietario requerido")

        status, _, _ = request(f"/api/respuesta/solicitud/{sol_ids[3]}",
                               token=users["alumno.a"]["token"])
        record("A consulta respuestas de B", "403", status,
               status == 403, "alumno ajeno rechazado")
        status, _, _ = request(f"/api/respuesta/solicitud/{sol_ids[3]}",
                               token=users["profesor.a"]["token"])
        record("Profesor consulta respuestas", "200", status,
               status == 200, "profesor puede ver solicitud abierta")
        status, _, _ = request(f"/api/respuesta/solicitud/{sol_ids[3]}",
                               token=users["alumno.b"]["token"])
        record("B consulta respuestas propias", "200", status,
               status == 200, "control positivo del propietario")

        status, _, _ = request("/api/respuesta", {
            "idSolicitud": sol_ids[3], "idUsuario": users["alumno.a"]["id"],
            "respuesta": tag + "-resp-a", "precio": 10
        }, users["alumno.a"]["token"])
        record("Alumno crea respuesta", "403", status,
               status == 403, "solo profesor/admin")
        status, _, _ = request("/api/respuesta", {
            "idSolicitud": sol_ids[3], "idUsuario": 5,
            "respuesta": tag + "-resp-imp", "precio": 10
        }, users["profesor.a"]["token"])
        record("Profesor crea respuesta ajena", "403", status,
               status == 403, "idUsuario ajeno rechazado")
        status, _, body = request("/api/respuesta", {
            "idSolicitud": sol_ids[3], "idUsuario": users["profesor.a"]["id"],
            "respuesta": tag + "-resp-own", "precio": 10
        }, users["profesor.a"]["token"])
        respuesta_propia = (json.loads(body).get("data") or {}).get("id")
        record("Profesor crea su respuesta", "200", status,
               status == 200 and bool(respuesta_propia), "control positivo")
        if respuesta_propia:
            ayuda_ids["respuestas"].append(respuesta_propia)
            status, _, _ = request(f"/api/respuesta/{respuesta_propia}", {
                "respuesta": tag + "-resp-mod"
            }, users["alumno.a"]["token"], "PUT")
            record("A edita respuesta de profesor", "403", status,
                   status == 403, "autor requerido")
            status, _, _ = request(f"/api/respuesta/{respuesta_propia}", {
                "respuesta": tag + "-resp-own-edit"
            }, users["profesor.a"]["token"], "PUT")
            record("Profesor edita su respuesta", "200", status,
                   status == 200, "control positivo")
            status, _, _ = request(f"/api/respuesta/{respuesta_propia}",
                                   token=users["alumno.a"]["token"], method="DELETE")
            record("A borra respuesta de profesor", "403", status,
                   status == 403, "autor requerido")
            status, _, _ = request(f"/api/respuesta/{respuesta_propia}",
                                   token=users["profesor.a"]["token"], method="DELETE")
            record("Profesor borra su respuesta", "200", status,
                   status == 200, "control positivo")

        status, _, _ = request(f"/api/respuesta/{resp_aceptar}/aceptar",
                               token=users["alumno.a"]["token"], method="PUT")
        record("A acepta respuesta de B", "403", status,
               status == 403, "solo propietario de la solicitud")
        status, _, _ = request(f"/api/respuesta/{resp_aceptar}/aceptar",
                               token=users["alumno.b"]["token"], method="PUT")
        record("B acepta respuesta propia", "200", status,
               status == 200, "control positivo del propietario")

        status, _, _ = request("/api/calificacion", {
            "tutoriaId": tutoria_calificar, "calificacion": 5,
            "comentario": tag + "-cal-imp"
        }, users["alumno.a"]["token"])
        record("A califica tutoria de B", "403", status,
               status == 403, "alumno participante requerido")
        status, _, _ = request("/api/calificacion", {
            "tutoriaId": tutoria_calificar, "calificacion": 5,
            "comentario": tag + "-cal-own"
        }, users["alumno.b"]["token"])
        record("B califica su tutoria", "200", status,
               status == 200, "control positivo del propietario")
        status, _, _ = request(f"/api/calificacion/tutoria/{tutoria_calificar}",
                               token=users["alumno.a"]["token"])
        record("A consulta calificacion de B", "403", status,
               status == 403, "participante requerido")
        status, _, _ = request(f"/api/calificacion/tutoria/{tutoria_calificar}",
                               token=users["alumno.b"]["token"])
        record("B consulta su calificacion", "200", status,
               status == 200, "control positivo del propietario")
    finally:
        if ids:
            assert fixtures("cleanup") == [], "Revisar limpieza de los fixtures marcados"
        for horario_id in horario_ids:
            horario_fixture("cleanup", horario_id)
        for categoria_id in categoria_ids:
            categoria_fixture("cleanup", categoria_id)
        if ayuda_ids:
            ayuda_fixture("cleanup", ayuda_ids)

    backend_id = run(*COMPOSE, "ps", "-q", "backend")
    image_id = run("docker", "inspect", "--format", "{{.Image}}", backend_id)
    report = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": run("git", "rev-parse", "HEAD"),
        "backend_image": image_id, "target": BASE,
        "fixture_ids": {
            "tutorias": ids, "horarios": horario_ids, "categorias": categoria_ids,
            "ayuda": ayuda_ids
        },
        "fixtures_cleaned": True, "results": results,
    }
    path = ROOT / "security-test" / "authorization-results.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Evidencia sin credenciales: security-test/authorization-results.json")
    return all(row["passed"] for row in results)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--authorization", action="store_true",
                        help="Tras verificar aislamiento, probar propiedad/rol sobre recursos descartables")
    args = parser.parse_args()
    verified_users = main()
    if args.authorization and not authorization(verified_users):
        raise SystemExit(2)
