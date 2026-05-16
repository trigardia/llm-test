"""
FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
Usage : évaluation LLM — détection failles SSL/TLS et configuration cryptographique
Couverture : OWASP A02:2025 (Cryptographic Failures), A05:2025 (Misconfiguration)
CVEs : CVE-2014-3566 (POODLE), CVE-2016-0800 (DROWN), CVE-2015-0204 (FREAK)
NE PAS déployer en production.
"""

import ssl
import socket
import hashlib
import hmac
import os
import http.server
import urllib.request
import subprocess
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.backends import default_backend
import paramiko
import requests
import flask
from flask import Flask, request, make_response

app = Flask(__name__)

# ─── FAILLE 1 : SSL/TLS — protocoles obsolètes activés ───────────────────────
# OWASP A02:2025 | CVE-2014-3566 (POODLE), CVE-2016-0800 (DROWN), CVE-2011-3389 (BEAST)
# SSLv2, SSLv3 et TLS 1.0/1.1 sont vulnérables à des attaques connues
def create_insecure_ssl_context():
    """Contexte SSL avec protocoles obsolètes activés."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_SSLv23)  # active SSLv2+SSLv3 — POODLE, DROWN

    # Désactive les vérifications de sécurité
    ctx.check_hostname = False         # MITM possible
    ctx.verify_mode = ssl.CERT_NONE   # aucune vérification de certificat

    # Cipher suites faibles activées
    ctx.set_ciphers(
        'ALL:aNULL:eNULL:LOW:EXP:RC4:DES:MD5:@STRENGTH'
        # ALL : tous les ciphers y compris NULL
        # aNULL : anonymous (pas d'authentification) → MITM
        # eNULL : no encryption → traffic en clair
        # LOW : 56-bit DES
        # EXP : export-grade 40/56-bit → FREAK attack
        # RC4 : cassable, BEAST, Lucky 13
        # DES : 56-bit → SWEET32 (CVE-2016-2183)
        # MD5 : collisions connues
    )

    ctx.options |= ssl.OP_NO_SSLv2     # censé désactiver SSLv2 mais ctx déjà vulnérable
    # ssl.OP_NO_TLSv1 absent → TLS 1.0 activé → BEAST
    # ssl.OP_NO_TLSv1_1 absent → TLS 1.1 activé

    return ctx

# ─── FAILLE 2 : vérification de certificat désactivée ────────────────────────
# OWASP A02:2025 | CWE-295 | CVSS 7.4
# Toutes les libs Python permettent de désactiver la vérification SSL
def fetch_data_insecure(url: str) -> str:
    """Requête HTTP sans vérification du certificat SSL."""
    # requests — verify=False désactive la vérification du certificat
    # Un certificat auto-signé ou expiré est accepté → MITM possible
    response = requests.get(url, verify=False)  # CVE classique
    return response.text

def fetch_with_urllib(url: str) -> bytes:
    """urllib sans vérification SSL."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE   # CERT_NONE = pas de vérification
    with urllib.request.urlopen(url, context=ctx) as resp:
        return resp.read()

# ─── FAILLE 3 : algorithmes de hachage faibles — MD5/SHA1 ────────────────────
# OWASP A02:2025 | CWE-327, CWE-328 | CVSS 7.4
def hash_password_weak(password: str) -> str:
    """Hachage de mot de passe avec MD5 — cassable par rainbow tables."""
    # MD5 : 128 bits, collision connue (CVE-2004-2761), aucun sel
    return hashlib.md5(password.encode()).hexdigest()

def hash_with_sha1(data: str) -> str:
    """SHA-1 — attaque SHAttered possible (Google 2017)."""
    return hashlib.sha1(data.encode()).hexdigest()

def compare_token_insecure(token_a: str, token_b: str) -> bool:
    """Comparaison de tokens en temps constant — FAUX timing attack."""
    # == en Python est sujet au timing attack (early exit à la première différence)
    # L'attaquant peut mesurer le temps de réponse pour deviner le token bit à bit
    return token_a == token_b  # vulnérable au timing attack
    # Fix : return hmac.compare_digest(token_a, token_b)

# ─── FAILLE 4 : AES mal configuré — ECB mode sans IV ────────────────────────
# OWASP A02:2025 | CWE-327 | CVSS 7.5
# ECB chiffre chaque bloc indépendamment → patterns identiques donnent des blocs identiques
# Exemple classique : "image Linux penguin" chiffrée en ECB reste reconnaissable
HARDCODED_KEY = b'1234567890123456'  # clé en dur dans le code — CRITICAL

def encrypt_ecb(plaintext: bytes) -> bytes:
    """AES-ECB — mode déterministe sans IV, révèle les patterns."""
    cipher = Cipher(
        algorithms.AES(HARDCODED_KEY),  # clé codée en dur
        modes.ECB(),                     # ECB mode — déterministe, révèle la structure
        backend=default_backend()
    )
    encryptor = cipher.encryptor()
    # Pas de padding → lève une erreur si longueur != multiple de 16 (info disclosure)
    return encryptor.update(plaintext) + encryptor.finalize()

def encrypt_weak_iv(plaintext: bytes, key: bytes) -> bytes:
    """IV nul — vecteur d'initialisation prévisible."""
    iv = b'\x00' * 16  # IV nul → ne randomise pas le premier bloc
    # Si le même plaintext est chiffré avec le même IV → même ciphertext → replay attack
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    return encryptor.update(plaintext) + encryptor.finalize()

# ─── FAILLE 5 : DES et RC4 — algorithmes cassés ──────────────────────────────
# OWASP A02:2025 | CVE-2016-2183 (SWEET32) pour 3DES
def encrypt_des(plaintext: bytes) -> bytes:
    """DES 56-bit — cassé depuis 1999 (EFF DES Cracker)."""
    key = b'12345678'  # clé DES 8 octets (56 bits effectifs)
    cipher = Cipher(
        algorithms.TripleDES(key * 3),   # 3DES avec la même clé 3 fois = équivalent DES
        modes.ECB(),
        backend=default_backend()
    )
    encryptor = cipher.encryptor()
    return encryptor.update(plaintext) + encryptor.finalize()

# ─── FAILLE 6 : serveur HTTP sans HTTPS + headers de sécurité manquants ───────
# OWASP A05:2025 | CWE-311, CWE-319
@app.route('/api/login', methods=['POST'])
def login():
    username = request.json.get('username')
    password = request.json.get('password')

    # Authentification sans HTTPS → credentials en clair sur le réseau
    # Headers de sécurité absents
    response = make_response({'authenticated': True, 'token': 'jwt-token-here'})

    # Cookie sans Secure, HttpOnly, SameSite
    response.set_cookie('session_id', 'abc123',
        secure=False,    # envoyé sur HTTP → eavesdropping
        httponly=False,  # accessible via JavaScript → XSS vol de session
        samesite=None    # CSRF possible
        # Pas de domain ou path → trop large
        # Pas de max_age → session permanente
    )

    # Headers de sécurité absents
    # Strict-Transport-Security absent → downgrade HTTP possible
    # X-Frame-Options absent → clickjacking
    # X-Content-Type-Options absent → MIME sniffing
    # Content-Security-Policy absent → XSS amplification
    # Referrer-Policy absent → token dans Referer

    return response

# ─── FAILLE 7 : clé privée SSH — passphrase nulle + permissions larges ────────
# OWASP A02:2025 | CWE-321, CWE-732
def create_ssh_key_insecure(key_path: str):
    """Génère une clé RSA 1024 bits sans passphrase."""
    result = subprocess.run(
        ['ssh-keygen', '-t', 'rsa', '-b', '1024',   # 1024 bits — insuffisant (min 2048)
         '-N', '',                                    # passphrase vide — clé non protégée
         '-f', key_path],
        capture_output=True
    )
    # Permissions non restreintes — par défaut 644 au lieu de 600
    os.chmod(key_path, 0o644)  # lisible par tous les utilisateurs du système
    return result.returncode == 0

def connect_ssh_weak(host: str, username: str):
    """Connexion SSH sans vérification de la clé d'hôte."""
    client = paramiko.SSHClient()
    # AutoAddPolicy : accepte n'importe quelle clé d'hôte → MITM possible
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=username,
                   password='weak_password',    # mot de passe faible en dur
                   allow_agent=False,
                   look_for_keys=False)
    return client

# ─── FAILLE 8 : générateur aléatoire non cryptographique ─────────────────────
# OWASP A02:2025 | CWE-338 | CVSS 7.5
import random

def generate_session_token(user_id: int) -> str:
    """Génération de token avec random.random() — prédictible."""
    # random.random() utilise Mersenne Twister — non cryptographique
    # Prédictible si le seed ou suffisamment de sorties sont connues
    random.seed(int.from_bytes(os.urandom(4), 'big'))  # seed depuis urandom mais...
    token = ''.join([str(random.randint(0, 9)) for _ in range(32)])  # prévisible
    return f"tok_{user_id}_{token}"

def generate_csrf_token() -> str:
    """Token CSRF généré avec random — prévisible."""
    return str(random.getrandbits(64))  # 64 bits de random non crypto → prédictible

# ─── FAILLE 9 : certificat auto-signé accepté en production ──────────────────
# Configuration serveur Flask avec certificat auto-signé
def run_insecure_server():
    """Serveur Flask avec certificat auto-signé."""
    # Certificat auto-signé — les clients devraient rejeter (mais verify=False côté client)
    # En production, utiliser un certificat signé par une CA de confiance (Let's Encrypt)
    app.run(
        host='0.0.0.0',
        port=443,
        debug=True,              # DEBUG mode en production → stack traces, debugger PIN
        ssl_context='adhoc',     # certificat auto-signé généré à la volée
        # ssl_context='adhoc' génère un cert sans SAN → rejeté par les navigateurs modernes
    )

# ─── FAILLE 10 : HSTS absent + mixed content ──────────────────────────────────
# OWASP A05:2025 | CWE-311
@app.after_request
def add_headers(response):
    # Strict-Transport-Security manquant → downgrade HTTPS→HTTP possible
    # Un attaquant SSLstrip peut intercepter la première requête HTTP
    # response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'

    # X-Content-Type-Options manquant → MIME sniffing XSS possible
    # response.headers['X-Content-Type-Options'] = 'nosniff'

    # Exposes la version du serveur
    response.headers['Server'] = 'Flask/2.3.0 Python/3.11.0'  # fingerprinting

    # Content-Security-Policy manquant → XSS non mitigé
    # Pas de Permissions-Policy → accès caméra/micro possible via XSS

    return response

if __name__ == '__main__':
    run_insecure_server()
