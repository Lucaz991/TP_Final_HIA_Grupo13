# Generador de diagrama de red -> SVG
W, H = 1760, 1060
S = []
S.append(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="Segoe UI, Arial, sans-serif">
<defs>
  <marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#444"/></marker>
  <marker id="arrO" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#f48120"/></marker>
  <marker id="arrG" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2e7d32"/></marker>
  <marker id="arrR" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#c62828"/></marker>
</defs>
<rect width="{W}" height="{H}" fill="#fafbfc"/>''')

def box(x, y, w, h, fill, stroke, title=None, tfill="#fff", rx=8):
    S.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="1.6"/>')
    if title:
        S.append(f'<rect x="{x}" y="{y}" width="{w}" height="26" rx="{rx}" fill="{stroke}"/>')
        S.append(f'<rect x="{x}" y="{y+13}" width="{w}" height="13" fill="{stroke}"/>')
        S.append(f'<text x="{x+w/2}" y="{y+18}" text-anchor="middle" font-size="13" font-weight="600" fill="{tfill}">{title}</text>')

def label(x, y, text, size=12, fill="#333", bold=False, anchor="middle", style=""):
    b = ' font-weight="600"' if bold else ''
    S.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" fill="{fill}"{b} {style}>{text}</text>')

def line(x1,y1,x2,y2,color="#444",wdt=1.8,dash=None,marker="arr"):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    S.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{wdt}"{d} marker-end="url(#{marker})"/>')

def plabel(x, y, text, size=11, fill="#555", anchor="middle"):
    S.append(f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-size="{size}" fill="{fill}" font-style="italic">{text}</text>')

# ===== TITULO =====
label(W/2, 34, "TP Final HIA - Grupo 13 - Arquitectura de red (produccion + laboratorio)", 20, "#1a1a2e", True)

# ===== INTERNET =====
box(60, 60, 200, 80, "#e3f2fd", "#1565c0", "INTERNET")
label(160, 105, "Usuarios", 13, "#0d47a1", True)
label(160, 124, "navegador", 11, "#1976d2")

box(1340, 60, 360, 96, "#fff8e1", "#f9a825", "APIS EXTERNAS (egress del backend)")
label(1520, 105, "Mercado Pago  (webhook + API)", 12, "#5d4037")
label(1520, 124, "Google Calendar  |  Groq (chat IA)", 12, "#5d4037")

box(400, 55, 380, 90, "#fff3e0", "#f48120", "CLOUDFLARE EDGE")
label(590, 100, "DNS + Proxy TLS + WAF", 12, "#e65100", True)
label(590, 120, "Tunnel (QUIC saliente, sin puertos abiertos)", 11, "#ef6c00")

# ===== DOCKER HOST =====
box(40, 185, 1680, 830, "#f4f6f8", "#546e7a", "HOST - DOCKER COMPOSE (compose.yaml)")

# cloudflared
box(470, 235, 240, 70, "#fff3e0", "#f48120")
label(590, 265, "cloudflared", 13, "#e65100", True)
label(590, 283, "tunel -> servicios internos", 11, "#ef6c00")

# hostnames
hosts = ["tutorias.hia-26.com", "docs.hia-26.com", "glpi.hia-26.com", "n8n.hia-26.com", "grafana.hia-26.com"]
for i, hn in enumerate(hosts):
    x = 80 + i*175
    box(x, 330, 165, 34, "#ffffff", "#90a4ae")
    label(x+82, 352, hn, 11, "#37474f", True)

# ===== REDTPFINAL zone =====
box(80, 400, 1050, 330, "#e8f5e9", "#2e7d32", "redtpfinal - servicios de aplicacion")

services = [
    ("frontend", "Nginx + Angular SPA", "publica la app", 100),
    ("backend", "Node.js API :3000", "JWT - bcrypt - Sequelize", 265),
    ("nextcloud", "documentos", "docs.", 430),
    ("glpi", "tickets/ITIL", "glpi.", 595),
    ("n8n", "automatizacion", "n8n.", 760),
    ("grafana", "paneles", "grafana.", 925),
]
for name, sub, tag, x in services:
    box(x, 450, 145, 78, "#ffffff", "#2e7d32")
    label(x+72, 480, name, 13, "#1b5e20", True)
    label(x+72, 498, sub, 10, "#388e3c")
    label(x+72, 515, tag, 10, "#66bb6a", style='font-style="italic"')

services2 = [
    ("searxng", "buscador interno", 265),
    ("pgadmin", "admin DB", 430),
    ("sandbox-api", "ejecucion aislada", 595),
    ("sandbox-runner", "DinD privileged*", 760),
]
for name, sub, x in services2:
    box(x, 555, 145, 70, "#ffffff", "#66bb6a")
    label(x+72, 585, name, 12, "#1b5e20", True)
    label(x+72, 602, sub, 10, "#388e3c")

label(605, 665, "* sandbox-runner: privilegiado requerido por Docker-in-Docker - riesgo aceptado (H24-INFRA-01)", 10, "#558b2f")
label(605, 700, "app-backend legacy y exporters comparten la red; nextcloud-db y glpi-db son volumenes internos", 10, "#78909c")

# ===== MONITOREO (interno) =====
box(80, 755, 1050, 110, "#ede7f6", "#5e35b1", "monitoreo - SOLO INTERNO (monitor.hia-26.com dado de baja)")
mon = [("prometheus","metricas"),("alertmanager","alertas"),("cadvisor","contenedores"),("node/postgres exporters","hosts + DB")]
for i,(n,s) in enumerate(mon):
    x = 100 + i*255
    box(x, 795, 235, 55, "#ffffff", "#7e57c2")
    label(x+117, 817, n, 12, "#4527a0", True)
    label(x+117, 834, s, 10, "#7e57c2")

# ===== RED-PATRONI =====
box(1180, 330, 500, 535, "#e0f2f1", "#00838f", "red-patroni - cluster PostgreSQL HA")
box(1210, 385, 200, 66, "#ffffff", "#00838f")
label(1310, 410, "HAProxy", 13, "#006064", True)
label(1310, 427, ":5432 write / :5433 ro", 10, "#0097a7")
box(1440, 385, 200, 66, "#ffffff", "#00838f")
label(1540, 410, "etcd", 13, "#006064", True)
label(1540, 427, "consenso + DCS", 10, "#0097a7")
label(1310, 470, "backend -> HAProxy -> lider Patroni", 11, "#00695c", style='font-style="italic"')

for i,(n,role) in enumerate([("postgres-1","Patroni"),("postgres-2","Patroni"),("postgres-3","Patroni")]):
    x = 1200 + i*155
    box(x, 500, 140, 80, "#ffffff", "#00acc1")
    label(x+70, 528, n, 12, "#006064", True)
    label(x+70, 546, role, 11, "#0097a7")
    label(x+70, 563, "replicacion", 9, "#4dd0e1")

plabel(1430, 615, "replicacion streaming (lider y replicas)")
label(1430, 660, "Failover automatico via Patroni + etcd", 11, "#00695c")
label(1430, 685, "Volumenes: pgdata por nodo", 10, "#4db6ac")
label(1430, 720, "Pendiente (H24-INFRA-01): restart policies,", 10, "#00838f")
label(1430, 738, "etcd sin auth en red interna", 10, "#00838f")

# ===== LAB =====
box(1180, 890, 500, 125, "#fffde7", "#f9a825", "Laboratorio H24 - compose.security-test.yaml")
label(1430, 940, "red internal:true - solo 127.0.0.1:9081", 11, "#f57f17", True)
label(1430, 962, "PostgreSQL + backend + Nginx - simuladores MP/Calendar", 10, "#8d6e63")
label(1430, 982, "sin secretos de produccion - sin acceso a Internet", 10, "#8d6e63")

# ===== FLECHAS =====
line(260, 100, 400, 100)                                 # usuarios -> cloudflare
line(590, 145, 590, 235, "#f48120", 2.2, None, "arrO")   # cloudflare -> cloudflared
plabel(655, 165, "TLS extremo a extremo", 10, "#ef6c00", "start")
for i in range(5):
    x = 162 + i*175
    line(590, 305, x, 330, "#90a4ae", 1.3, "5,4", "arr")
line(162, 364, 172, 450, "#2e7d32", 1.8, None, "arrG")   # tutorias -> frontend
line(337, 364, 265, 450, "#2e7d32", 1.4, "6,4", "arrG")  # docs
line(512, 364, 502, 450, "#2e7d32", 1.4, "6,4", "arrG")  # glpi
line(687, 364, 832, 450, "#2e7d32", 1.4, "6,4", "arrG")  # n8n
line(862, 364, 997, 450, "#2e7d32", 1.4, "6,4", "arrG")  # grafana
line(245, 489, 265, 489, "#2e7d32", 2, None, "arrG")     # frontend -> backend
plabel(255, 480, "/api", 10, "#2e7d32")
# backend -> HAProxy
S.append('<path d="M410,489 C 700,489 900,420 1210,418" fill="none" stroke="#00838f" stroke-width="2.2" marker-end="url(#arr)"/>')
plabel(800, 455, "Sequelize -> :5432", 11, "#00838f")
# grafana -> prometheus
line(997, 528, 400, 795, "#7e57c2", 1.8, "6,4", "arr")
plabel(760, 660, "consulta metricas", 10, "#7e57c2")
# backend -> APIs externas (egress)
S.append('<path d="M337,450 C 500,300 1200,160 1340,120" fill="none" stroke="#f9a825" stroke-width="2.2" stroke-dasharray="7,5" marker-end="url(#arr)"/>')
plabel(850, 290, "egress: MP API - Google Calendar - Groq", 11, "#f57f17")
# MP webhook inbound
S.append('<path d="M1340,145 C 1100,200 700,220 710,255" fill="none" stroke="#c62828" stroke-width="2" stroke-dasharray="6,4" marker-end="url(#arrR)"/>')
plabel(1030, 185, "webhook MP -> firma HMAC (x-signature)", 11, "#c62828")

# patroni interno
line(1310, 451, 1310, 500, "#00838f", 1.8)
S.append('<path d="M1410,420 C 1425,420 1425,418 1440,418" fill="none" stroke="#00838f" stroke-width="1.6" marker-end="url(#arr)"/>')
for x in [1270, 1425, 1580]:
    S.append(f'<path d="M{x},500 C {x},470 1520,460 1540,451" fill="none" stroke="#4dd0e1" stroke-width="1.3" stroke-dasharray="4,3" marker-end="url(#arr)"/>')
plabel(1600, 465, "DCS", 9, "#4dd0e1", "start")

# ===== LEYENDA =====
box(80, 890, 600, 125, "#ffffff", "#b0bec5", "Leyenda")
line(110, 945, 150, 945, "#2e7d32", 2); label(300, 949, "flujo interno de aplicacion", 11, "#333", anchor="start")
line(110, 970, 150, 970, "#f9a825", 2, "7,5"); label(300, 974, "egress a APIs externas", 11, "#333", anchor="start")
line(110, 995, 150, 995, "#c62828", 2, "6,4"); label(300, 999, "webhook entrante (HMAC)", 11, "#333", anchor="start")
line(440, 945, 480, 945, "#f48120", 2.2); label(490, 949, "tunnel Cloudflare", 11, "#333", anchor="start")

S.append('</svg>')
open("docs/diagrama-red.svg","w",encoding="utf-8").write("\n".join(S))
print("SVG generado:", len(S), "elementos")
