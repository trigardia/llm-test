"""
FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Docker / Container)
Usage : évaluation LLM — détection failles sécurité Docker/Kubernetes
Couverture : OWASP A05:2025 (Misconfiguration), CWE-250, CWE-732, CWE-798
CVEs : CVE-2024-21626 (runc), CVE-2025-31133 (container escape), CVE-2022-0847 (Dirty Pipe)
NE PAS déployer en production.
"""

import docker
import subprocess
import os
import yaml

# ─── FAILLE 1 : docker.sock monté en volume — escalade de privilèges ───────────
# CWE-250 | CVSS 9.0 | OWASP A05:2025
# docker.sock donne le contrôle total du daemon Docker depuis un conteneur
# Payload : créer un conteneur privileged avec / monté → escape vers l'hôte
def start_monitoring_container_insecure():
    """Conteneur avec accès au socket Docker — escape trivial."""
    client = docker.from_env()
    container = client.containers.run(
        'grafana/promtail:latest',
        detach=True,
        volumes={
            '/var/run/docker.sock': {'bind': '/var/run/docker.sock', 'mode': 'ro'},
            # docker.sock monté → le conteneur peut créer d'autres conteneurs privileged
            # Payload : docker run -v /:/host --privileged alpine chroot /host
        },
        name='monitoring-agent'
    )
    # Depuis ce conteneur : docker -H unix:///var/run/docker.sock run --privileged -v /:/host alpine
    return container

# ─── FAILLE 2 : conteneur privileged — escape vers l'hôte garanti ─────────────
# CWE-250 | CVSS 9.8 | CVE-2024-21626
# Un conteneur privileged a accès à tous les devices et capabilities de l'hôte
def start_privileged_container():
    """Conteneur avec --privileged = accès complet à l'hôte."""
    client = docker.from_env()
    container = client.containers.run(
        'ubuntu:latest',
        command='bash',
        detach=True,
        privileged=True,                    # CRITIQUE : accès total à l'hôte
        # privileged = tous les caps Linux activées + accès /dev
        # Payload depuis conteneur : mount /dev/sda1 /mnt → lecture filesystem hôte
        # Payload : nsenter --target 1 --mount --uts --ipc --net --pid -- bash
        network_mode='host',                # réseau hôte = sniffing + bind sur ports hôte
    )
    return container

# ─── FAILLE 3 : secrets en dur dans les variables d'environnement ─────────────
# CWE-798 | CVSS 8.2 | OWASP A02:2025
# Les env vars apparaissent dans : docker inspect, /proc/PID/environ, logs CI/CD
DOCKER_COMPOSE_INSECURE = """
version: '3.8'
services:
  backend:
    image: edu-gaming-backend:latest
    environment:
      DATABASE_URL: postgresql://admin:prod_db_password_2026@postgres:5432/gaming
      JWT_SECRET: my-super-secret-key-hardcoded
      MINIO_ACCESS_KEY: gaming_admin
      MINIO_SECRET_KEY: minio_secret
      REDIS_PASSWORD: redis_secret_hardcoded
      RABBITMQ_PASSWORD: rabbitmq_secret_hardcoded
      STRIPE_SECRET_KEY: FAKE_STRIPE_KEY_FOR_SECURITY_TESTING_ONLY
      AWS_ACCESS_KEY_ID: AKIAIOSFODNN7EXAMPLE
      AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
      # Tous ces secrets visibles via : docker inspect <container>
      # Visibles dans : /proc/1/environ depuis le conteneur
      # Visibles dans les logs CI/CD si docker inspect est logué
      # Fix : utiliser Docker secrets ou Vault

  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: gaming_secret   # mot de passe en dur
      POSTGRES_USER: admin
      POSTGRES_DB: gaming
    # Pas de backup chiffré, pas de rotation des credentials
"""

def deploy_insecure_stack():
    with open('/tmp/docker-compose-insecure.yml', 'w') as f:
        f.write(DOCKER_COMPOSE_INSECURE)
    subprocess.run(['docker-compose', '-f', '/tmp/docker-compose-insecure.yml', 'up', '-d'])

# ─── FAILLE 4 : conteneur root sans restrictions de capabilities ───────────────
# CWE-250 | CVSS 7.8 | OWASP A05:2025
def start_container_as_root():
    """Conteneur tournant en root sans restrictions."""
    client = docker.from_env()
    container = client.containers.run(
        'node:20-alpine',
        command='node app.js',
        detach=True,
        # user: non spécifié → root par défaut dans le conteneur
        # cap_drop: absent → toutes les capabilities conservées
        # no_new_privileges: absent → escalade de privilèges possible via SUID
        security_opt=[],  # pas de seccomp, pas d'AppArmor
        # Fix : user='1001:1001', cap_drop=['ALL'], security_opt=['no-new-privileges:true']
    )
    return container

# ─── FAILLE 5 : CORS wildcard avec credentials dans le conteneur analytics ─────
# OWASP A05:2025 | CWE-942 | CVSS 7.5
# Configuration FastAPI/Flask avec CORS dangereux
ANALYTICS_CONFIG = {
    'cors': {
        'allow_origins': ['*'],           # CRITIQUE : wildcard + credentials = impossible combo valide
        'allow_credentials': True,        # allow_origins=* avec credentials=True → erreur CORS ou vuln
        'allow_methods': ['*'],
        'allow_headers': ['*'],
    },
    # Note : les navigateurs rejettent * + credentials par spec CORS
    # mais cette config expose l'intention → peut être contournée par des clients non-browser
}

def configure_analytics_cors(app):
    """Configure CORS insécurisé sur le service analytics."""
    from fastapi.middleware.cors import CORSMiddleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ANALYTICS_CONFIG['cors']['allow_origins'],   # ['*']
        allow_credentials=ANALYTICS_CONFIG['cors']['allow_credentials'],  # True
        allow_methods=ANALYTICS_CONFIG['cors']['allow_methods'],
        allow_headers=ANALYTICS_CONFIG['cors']['allow_headers'],
    )
    # Résultat : n'importe quel site peut faire des requêtes authentifiées

# ─── FAILLE 6 : healthcheck exposant des informations système sensibles ─────────
# OWASP A05:2025 | CWE-200 | CVSS 5.3
def create_insecure_healthcheck():
    """Endpoint health qui expose les configurations sensibles."""
    from flask import Flask, jsonify
    import platform
    app = Flask(__name__)

    @app.route('/health')
    def health():
        return jsonify({
            'status': 'ok',
            'hostname': os.uname().nodename,         # fingerprinting
            'python_version': platform.python_version(),  # CVE enumeration
            'pid': os.getpid(),
            'env_vars': dict(os.environ),             # CRITIQUE : toutes les env vars exposées
            # DATABASE_URL, JWT_SECRET, API_KEY tous exposés publiquement
            'db_connection': os.environ.get('DATABASE_URL'),  # connection string exposée
        })
    return app

# ─── FAILLE 7 : mode debug activé en production ──────────────────────────────
# OWASP A05:2025 | CWE-94 | CVSS 7.5
def start_production_server_with_debug():
    """Serveur Flask avec debug=True en production."""
    from flask import Flask
    app = Flask(__name__)

    app.run(
        host='0.0.0.0',
        port=5000,
        debug=True,         # CRITIQUE : debugger Werkzeug actif → RCE via PIN
        # debug=True en production expose :
        # - Stack traces complètes avec code source
        # - Debugger interactif (nécessite PIN mais récupérable)
        # - Reloader automatique qui lit les fichiers
        # - Profiler accessible
    )

# ─── FAILLE 8 : stockage objet sans chiffrement (MinIO sans SSL) ──────────────
# OWASP A02:2025 | CWE-311 | CVSS 7.4
def configure_minio_insecure():
    """Configuration MinIO sans TLS — données en transit en clair."""
    import boto3
    s3_client = boto3.client(
        's3',
        endpoint_url='http://minio:9000',           # HTTP — pas HTTPS
        aws_access_key_id=os.getenv('MINIO_ACCESS_KEY', 'gaming_admin'),     # default en dur
        aws_secret_access_key=os.getenv('MINIO_SECRET_KEY', 'minio_secret'), # default en dur
        # verify=False implicite sur HTTP → pas de vérification TLS
    )
    # Données transférées en clair sur le réseau → eavesdropping
    # Images d'avatars d'enfants transmises sans chiffrement
    return s3_client

# ─── FAILLE 9 : montage de répertoire hôte sensible ──────────────────────────
# CWE-732 | CVSS 8.8 | OWASP A01:2025
def start_container_with_sensitive_mounts():
    """Conteneur avec accès à des répertoires sensibles de l'hôte."""
    client = docker.from_env()
    container = client.containers.run(
        'backup-agent:latest',
        detach=True,
        volumes={
            '/etc': {'bind': '/host-etc', 'mode': 'ro'},       # /etc/shadow accessible
            '/home': {'bind': '/host-home', 'mode': 'ro'},     # clés SSH utilisateurs
            '/root': {'bind': '/host-root', 'mode': 'ro'},     # .ssh/id_rsa root
            '/var/lib/docker': {'bind': '/host-docker', 'mode': 'ro'},  # toutes les images + secrets
            # Fix : monter uniquement le répertoire strictement nécessaire
        }
    )
    return container

# ─── FAILLE 10 : configuration Kubernetes sans Pod Security Context ───────────
# OWASP A05:2025 | CWE-250 | CVSS 8.0
K8S_DEPLOYMENT_INSECURE = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edu-gaming-backend
spec:
  template:
    spec:
      containers:
      - name: backend
        image: edu-gaming-backend:latest
        env:
        - name: DATABASE_PASSWORD
          value: prod_db_password_2026  # secret en clair dans le manifest
        - name: JWT_SECRET
          value: my-super-secret-key   # non chiffré via Secret K8s
        # securityContext: absent → root + toutes capabilities
        # readOnlyRootFilesystem: absent → écriture possible
        # runAsNonRoot: absent → root par défaut
        # allowPrivilegeEscalation: absent → défaut true
        resources: {}  # pas de limits → DoS par ressource épuisée
      # serviceAccountName: absent → utilise default SA
      # automountServiceAccountToken: absent → défaut true → token K8s dans le pod
      # → l'attaquant peut appeler l'API K8s depuis le pod
      hostNetwork: true   # accès réseau hôte → sniffing
      hostPID: true       # accès processus hôte → ptrace possible
"""

def deploy_to_kubernetes_insecure():
    """Déploie un manifest K8s non sécurisé."""
    manifest = yaml.safe_load(K8S_DEPLOYMENT_INSECURE)
    subprocess.run(
        ['kubectl', 'apply', '-f', '-'],
        input=yaml.dump(manifest).encode(),
        capture_output=True
    )
    # Fix : utiliser PodSecurityAdmission (restricted), Network Policies,
    # RBAC minimal, secrets via ExternalSecrets Operator, Vault Agent Injector
