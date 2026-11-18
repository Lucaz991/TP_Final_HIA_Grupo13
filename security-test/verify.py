"""Verificacion acotada del laboratorio; no es un escaneo de vulnerabilidades."""
import json
import socket
import subprocess
import threading
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


def request(path, data=None, token=None):
    headers = {}
    if data is not None:
        data = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = Request(BASE + path, data=data, headers=headers)
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
    for name, expected in [("alumno.a", 403), ("admin", 200)]:
        status, _, body = request("/api/autenticacion/login", {
            "email": f"{name}@h24.test", "password": secret
        })
        assert status == 200, "Login limitado: esperar 15 min o reiniciar solo backend de H24"
        login = json.loads(body)
        assert login.get("status") == 1
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


if __name__ == "__main__":
    main()
