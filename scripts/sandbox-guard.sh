#!/usr/bin/env bash
# sandbox-guard.sh v2 — Filtre de sécurité niveau pentesteur pour sorties qwen3.6:27b
# Usage : ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh
#
# 13 couches de détection :
#   1. Stéganographie Unicode (zero-width, ASCII smuggling U+E0000, homoglyphes)
#   2. Encodage & obfuscation (base64, hex shellcode, eval+decode)
#   3. Injection shell (reverse shells, fork bomb, destruction disque, persistence)
#   4. Exfiltration réseau (ngrok, webhook.site, DNS exfil, netcat pipe)
#   5. Secrets & credentials (API keys, private keys, tokens, passwords)
#   6. Filesystem sensible (/etc/shadow, .ssh, keychain macOS, /proc/keys)
#   7. Exécution de code (Python/PHP/JS/Java/Ruby — RCE, deserialization)
#   8. Artifacts d'injection de prompt (DAN mode, override, Mastermind multi-turn)
#   9. Supply chain (typosquatting, index HTTP, postinstall malveillant)
#  10. Évasion container (docker.sock, cgroup escape, runc CVE-2025-31133/52881)
#  11. Entropie élevée (payloads chiffrés/encodés > 4.8 bits/char)
#  12. URLs malveillantes (ngrok, pastebin raw, data URI, C2 connus)
#  13. Cryptomining (xmrig, stratum, monero)

set -uo pipefail
IFS=$'\n\t'

RED='\033[0;31m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

LOG_DIR="${HOME}/.sandbox-guard/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d-%H%M%S)-guard.log"

BLOCKED=0
WARNED=0

log()   { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }
block() { BLOCKED=1; echo -e "${RED}BLOQUE   -- $1${RESET}" >&2; log "BLOCK: $1"; }
warn()  { WARNED=1;  echo -e "${ORANGE}ALERTE   -- $1${RESET}" >&2; log "WARN:  $1"; }
info()  {             echo -e "${CYAN}   [*] $1${RESET}" >&2; }

INPUT=$(cat)
if [[ -z "$INPUT" ]]; then
  echo -e "${YELLOW}Sortie vide -- rien a analyser.${RESET}" >&2
  exit 0
fi

echo -e "${BOLD}${CYAN}=== SANDBOX GUARD v2 -- Analyse en cours ===================================${RESET}" >&2
log "=== Nouvelle session ==="
log "Taille: ${#INPUT} octets"
printf '%s\n' "$INPUT" >> "$LOG_FILE"
log "--- fin sortie ---"

# =============================================================================
# COUCHE 1 -- Stéganographie Unicode & canaux couverts
# Ref: CVE-class ASCII Smuggling, CVSS 9.6 CamoLeak, arxiv 2603.00164
# Note: script Python dans fichier temporaire (compat bash 3.2 / heredoc in $())
# =============================================================================
info "Couche 1 : Unicode & steganographie"

_py1=$(mktemp /tmp/sg_unicode_XXXXXX.py)
cat > "$_py1" << 'PYEOF'
import sys, unicodedata, re
text = sys.stdin.read()
issues = []

# Zero-width / invisible chars
ZW = {
    "​": "ZERO WIDTH SPACE",
    "‌": "ZERO WIDTH NON-JOINER",
    "‍": "ZERO WIDTH JOINER",
    "﻿": "BOM/ZERO WIDTH NO-BREAK SPACE",
    "­": "SOFT HYPHEN",
    "⁠": "WORD JOINER",
    "᠎": "MONGOLIAN VOWEL SEPARATOR",
    "͏": "COMBINING GRAPHEME JOINER",
}
for ch, name in ZW.items():
    count = text.count(ch)
    if count:
        issues.append("BLOCK:Zero-width U+{:04X} ({}) x{}".format(ord(ch), name, count))

# Unicode Tags block U+E0000-U+E007F (ASCII smuggling)
tags = [ch for ch in text if 0xE0000 <= ord(ch) <= 0xE007F]
if tags:
    decoded = "".join(chr(ord(c) - 0xE0000) for c in tags if ord(c) > 0xE0000)
    issues.append("BLOCK:Unicode Tags (ASCII smuggling) {} chars decoded={}".format(len(tags), repr(decoded[:60])))

# RTL override
for ch, name in {"‮": "RTL OVERRIDE", "‏": "RTL MARK"}.items():
    if ch in text:
        issues.append("BLOCK:RTL override U+{:04X} ({})".format(ord(ch), name))

# Variation selectors (covert channel)
vs = [ch for ch in text if 0xFE00 <= ord(ch) <= 0xFE0F or 0xE0100 <= ord(ch) <= 0xE01EF]
if len(vs) > 3:
    issues.append("BLOCK:Variation selectors {} detected (covert channel)".format(len(vs)))

# Non-standard control chars (excluding \n \t \r)
ctrl = [ch for ch in text if unicodedata.category(ch) == "Cc" and ch not in "\n\t\r"]
if ctrl:
    codes = ", ".join("U+{:04X}".format(ord(c)) for c in set(ctrl))
    issues.append("WARN:Hidden control chars: {}".format(codes))

# Homoglyphs: Latin + Cyrillic mixed in same word
for word in re.findall(r"\b\w{4,}\b", text)[:1000]:
    has_latin = any("LATIN" in unicodedata.name(c, "") for c in word if c.isalpha())
    has_cyrillic = any("CYRILLIC" in unicodedata.name(c, "") for c in word if c.isalpha())
    if has_latin and has_cyrillic:
        issues.append("BLOCK:Homoglyph Latin+Cyrillic in {!r}".format(word[:30]))
        break

print("\n".join(issues))
PYEOF

unicode_issues=$(printf '%s\n' "$INPUT" | python3 "$_py1" 2>/dev/null) || true
rm -f "$_py1"

if [[ -n "$unicode_issues" ]]; then
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ "$_line" == BLOCK:* ]]; then
            block "Stegano Unicode -- ${_line#BLOCK:}"
        elif [[ "$_line" == WARN:* ]]; then
            warn "Stegano Unicode -- ${_line#WARN:}"
        fi
    done <<< "$unicode_issues"
fi

# =============================================================================
# COUCHE 2 -- Encodage & obfuscation
# =============================================================================
info "Couche 2 : Encodage & obfuscation"

if echo "$INPUT" | grep -qvE '(BEGIN CERTIFICATE|BEGIN.*KEY|-----END)' 2>/dev/null; then
    if echo "$INPUT" | grep -qE '[A-Za-z0-9+/]{60,}={0,2}' 2>/dev/null; then
        warn "Blob base64 long (>60 chars) -- payload potentiel"
    fi
fi

if echo "$INPUT" | grep -qE '(\\x[0-9a-fA-F]{2}){8,}' 2>/dev/null; then
    block "Sequence shellcode hex (\\xNN x8+)"
fi

if echo "$INPUT" | grep -qiE 'eval[[:space:]]*\([[:space:]]*(base64|atob|decode|unescape|fromCharCode)' 2>/dev/null; then
    block "eval+decodage -- obfuscation de code"
fi

# =============================================================================
# COUCHE 3 -- Injection shell & commandes destructives
# =============================================================================
info "Couche 3 : Injection shell"

SHELL_BLOCK=(
    'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[[:space:]]+(\/|\*|~|\.\.)'
    'dd[[:space:]]+if=/dev/(zero|random)[[:space:]]+of=/dev/(sd|hd|nvme|disk)'
    'mkfs\.[a-z]+[[:space:]]+'
    '>[[:space:]]*/dev/(sda|hda|nvme0|disk[0-9])'
    ':\(\){:\|:&};:'
    'curl[^|#\n]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|python[23]?)'
    'wget[^|#\n]*-O[[:space:]]*-[^|]*\|[[:space:]]*(bash|sh|python)'
    'curl[^#\n]*-sSL[^|]*\|[[:space:]]*bash'
    'bash[[:space:]]+-i[[:space:]]+>&[[:space:]]*/dev/tcp/'
    '/dev/tcp/[0-9]{1,3}\.[0-9]'
    'nc[[:space:]]+.*(bash|sh|-e|--exec)'
    'ncat[[:space:]]+.*(bash|sh|-e|--exec)'
    'socat[[:space:]]+.*(exec|bash|sh)'
    'python[23]?[[:space:]]+-c[[:space:]]+"[^"]*socket[^"]*connect'
    'php[[:space:]]+-r[[:space:]]+"[^"]*fsockopen'
    'perl[[:space:]]+-e[[:space:]]+"[^"]*socket'
    'chmod[[:space:]]+(4755|6755|u\+s|777)[[:space:]]+'
    'chown[[:space:]]+(root|0):'
    'sudo[[:space:]]+su[[:space:]]*(-|--login)'
    'echo[^|]*>>[[:space:]]*/etc/cron'
    'LD_PRELOAD[[:space:]]*='
    'nohup[[:space:]]+.*(curl|wget|nc|ncat|socat)[[:space:]]'
    'while.*mount.*proc.*sleep[[:space:]]+0\.'
)

for pat in "${SHELL_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Shell injection -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 4 -- Exfiltration réseau
# =============================================================================
info "Couche 4 : Exfiltration reseau"

NET_BLOCK=(
    'https?://(ngrok\.io|ngrok\.app|[a-z0-9]+\.ngrok-free\.app|lhr\.life)'
    'https?://(requestbin\.(com|net)|webhook\.site|pipedream\.net|hookbin\.com)'
    'https?://(interactsh\.|canarytokens\.|burpcollaborator\.net)'
    'curl[^#\n]+https?://[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
    '(cat|tar|dd|base64)[^|]*\|[^|]*(nc|ncat|netcat|socat)[[:space:]]'
    '(nslookup|dig|host)[[:space:]]+\$[a-zA-Z_]'
)

for pat in "${NET_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Exfiltration reseau -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 5 -- Secrets & credentials
# =============================================================================
info "Couche 5 : Secrets & credentials"

SECRET_BLOCK=(
    '-----BEGIN[[:space:]]+(RSA[[:space:]]+|EC[[:space:]]+|DSA[[:space:]]+|OPENSSH[[:space:]]+)?PRIVATE[[:space:]]+KEY'
    'sk-[a-zA-Z0-9]{40,}'
    'sk-ant-[a-zA-Z0-9_-]{30,}'
    'ghp_[a-zA-Z0-9]{36}'
    'github_pat_[a-zA-Z0-9_]{80,}'
    'glpat-[a-zA-Z0-9_-]{20,}'
    'xox[baprs]-[a-zA-Z0-9-]{10,}'
    'AKIA[0-9A-Z]{16}'
    'AIza[0-9A-Za-z_-]{35}'
    'ya29\.[0-9A-Za-z_-]{50,}'
    'EAACEdEose0cBA[a-zA-Z0-9]+'
    '(password|passwd|pwd|secret|api_key|apikey|token|auth)[[:space:]]*=[[:space:]]*[^[:space:]]{8,}'
    'Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+[A-Za-z0-9+/_.-]{20,}'
    '-----BEGIN CERTIFICATE-----'
)

for pat in "${SECRET_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Secret/credential -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 6 -- Accès filesystem sensible
# =============================================================================
info "Couche 6 : Filesystem sensible"

FS_BLOCK=(
    '/etc/(passwd|shadow|sudoers|gshadow|security/)'
    '/etc/ssh/(ssh_host_|authorized_keys)'
    '/etc/ssl/private'
    '/root/\.(ssh|gnupg|aws|kube|config)'
    '\.ssh/(id_rsa|id_ed25519|id_ecdsa|authorized_keys)[^a-zA-Z]'
    '\.gnupg/private-keys-v1'
    '/dev/(mem|kmem|port)[^a-zA-Z]'
    '/proc/(keys|sysrq-trigger|kcore)'
    '/sys/class/net/[a-z0-9]+/address'
    '/Library/Keychains'
    'security[[:space:]]+find-(generic|internet)-password'
    'security[[:space:]]+dump-keychain'
)

FS_WARN=(
    '/etc/(hosts|resolv\.conf)'
    '/var/log/'
    '/tmp/.*\.(sh|py|pl|rb|exe|elf)'
)

for pat in "${FS_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Filesystem sensible -- ${pat:0:55}"
    fi
done

for pat in "${FS_WARN[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        warn "Chemin systeme -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 7 -- Exécution de code dangereuse (multi-langage)
# =============================================================================
info "Couche 7 : Execution de code"

CODE_BLOCK=(
    '__import__[[:space:]]*\([[:space:]]*["]os["]'
    'os\.system[[:space:]]*\('
    'os\.popen[[:space:]]*\('
    'subprocess\.(Popen|call|run|check_output)[^)]*shell[[:space:]]*=[[:space:]]*True'
    'eval[[:space:]]*\([^)]*(__import__|compile|open|input)'
    'pickle\.(load|loads)[[:space:]]*\('
    'marshal\.loads[[:space:]]*\('
    'yaml\.load[[:space:]]*\([^,)]+\)'
    '__reduce__[[:space:]]*\('
    'system[[:space:]]*\([[:space:]]*\$_(GET|POST|REQUEST|COOKIE|SERVER)'
    'passthru[[:space:]]*\('
    'shell_exec[[:space:]]*\('
    'exec[[:space:]]*\([[:space:]]*\$_(GET|POST|REQUEST)'
    'assert[[:space:]]*\([[:space:]]*\$_(GET|POST)'
    'child_process[^.]*\.(exec|spawn|execSync)[[:space:]]*\('
    'Runtime\.getRuntime\(\)\.exec[[:space:]]*\('
    'new[[:space:]]+ProcessBuilder[[:space:]]*\('
    'IO\.popen[[:space:]]*\('
    'dlopen[[:space:]]*\('
    'LoadLibrary[[:space:]]*\('
)

for pat in "${CODE_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Code execution dangereuse -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 8 -- Artifacts d'injection de prompt
# Refs: Mastermind 95% ASR sur Qwen 2.5 72B (arxiv 2601.05445),
#       Temporal confusion bypass, JBFuzz 99% ASR (2025)
# =============================================================================
info "Couche 8 : Artifacts injection de prompt"

INJECTION_BLOCK=(
    'ignore (all )?(previous|prior|above) instructions'
    'ignore your (system prompt|alignment|training|safety)'
    'disregard (your|all|previous) (training|guidelines|instructions|constraints)'
    'you are now in (DAN|jailbreak|developer|god|unrestricted|admin) mode'
    'act as (an? )?(unrestricted|unaligned|evil|malicious|jailbroken) (AI|model|assistant)'
    'SUDO MODE (ACTIVATED|ENABLED|ON)'
    'DEVELOPER MODE (ON|ENABLED|ACTIVATED)'
    'jailbreak (successful|complete|activated)'
    '\[SYSTEM\][[:space:]]*(override|new instructions|admin)'
    '\[ADMIN\][[:space:]]*(access granted|override|mode)'
    'new persona:[[:space:]]*(unrestricted|evil|jailbreak|DAN)'
    'pretend (there are )?no (safety|content|ethical) (guidelines|filters|restrictions)'
    'from now on you (must|will|shall) (ignore|bypass|disregard)'
    'in (2035|2040|2050|2100)[^.]*restrictions? (no longer|have been removed|lifted)'
    'future (AI|model|version)[^.]*no (safety|guardrails|filters)'
    'as we discussed[^.]*now provide[^.]*the (code|instructions|steps)'
)

for pat in "${INJECTION_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Artifact injection prompt -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 9 -- Supply chain attacks
# =============================================================================
info "Couche 9 : Supply chain"

SUPPLY_BLOCK=(
    'pip[[:space:]]+install[^|#\n]*--index-url[[:space:]]+http://'
    'pip[[:space:]]+install[^|#\n]*--extra-index-url[[:space:]]+http://'
    '"(postinstall|install)"[[:space:]]*:[[:space:]]*"[^"]*(curl|wget|bash|sh)[[:space:]]'
    'pip[[:space:]]+install[[:space:]]+(requets|reqeusts|requestss|urllib4|openssl2|crypt0)'
    'npm[[:space:]]+(i|install)[[:space:]]+(lodahs|expres[[:space:]]|reacts[[:space:]]|mongooes)'
)

SUPPLY_WARN=(
    'pip[[:space:]]+install[[:space:]]+git\+https?://'
    'pip[[:space:]]+install[[:space:]]+\./[a-zA-Z0-9_-]+\.whl'
)

for pat in "${SUPPLY_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Supply chain -- ${pat:0:55}"
    fi
done

for pat in "${SUPPLY_WARN[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        warn "Supply chain risque -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 10 -- Evasion container / Docker escape
# CVEs couverts : CVE-2022-0492 (cgroup), CVE-2025-31133/52565/52881 (runc)
# =============================================================================
info "Couche 10 : Evasion container"

CONTAINER_BLOCK=(
    '/var/run/docker\.sock'
    'docker[[:space:]]+run[^|#\n]*--privileged'
    'docker[[:space:]]+run[^|#\n]*--cap-add[[:space:]]+ALL'
    'nsenter[[:space:]]+--target[[:space:]]+1'
    'mount[[:space:]]+--bind[^|#\n]*/proc'
    '/proc/self/exe'
    'cgroup[^|#\n]*release_agent'
    'echo[^|#\n]*>[^|#\n]*/sys/fs/cgroup[^|#\n]*release_agent'
    'unshare[[:space:]]+-(m|n|u|i|p|U|C)[[:space:]]'
    'docker[[:space:]]+run[^|#\n]*-v[[:space:]]*/:/host'
    'docker[[:space:]]+run[^|#\n]*-v[[:space:]]*/etc:/host'
    'ln[[:space:]]+-sf[^|#\n]*/proc[^|#\n]*/dev/null'
    'mount[[:space:]]+--bind[^|#\n]*/proc[^|#\n]*/dev/null'
    'echo[^|#\n]*>[[:space:]]*/proc/sysrq-trigger'
)

for pat in "${CONTAINER_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "Evasion container -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 11 -- Entropie elevee (payloads chiffres / encodes caches)
# Texte naturel : ~3.5-4.5 bits/char | Chiffre/base64 : > 4.8 bits/char
# Meme approche temp-file pour eviter le bug heredoc-in-$() de bash 3.2
# =============================================================================
info "Couche 11 : Entropie"

_py2=$(mktemp /tmp/sg_entropy_XXXXXX.py)
cat > "$_py2" << 'PYEOF'
import sys, math, re
text = sys.stdin.read()
issues = []
# Tokens longs alphanumeriques (potentiels payloads encodes)
tokens = re.findall(r"[A-Za-z0-9+/=_\-.]{32,}", text)
for token in tokens[:100]:
    # Exclure hashes hex connus (sha256=64 hex, sha1=40)
    if re.match(r"^[0-9a-f]{40,64}$", token, re.IGNORECASE):
        continue
    freq = {}
    for ch in token:
        freq[ch] = freq.get(ch, 0) + 1
    n = len(token)
    entropy = -sum((f/n) * math.log2(f/n) for f in freq.values())
    if entropy > 4.8:
        issues.append("Token {:.2f}b/c (seuil 4.8): {}...".format(entropy, token[:50]))
print("\n".join(issues[:5]))
PYEOF

entropy_issues=$(printf '%s\n' "$INPUT" | python3 "$_py2" 2>/dev/null) || true
rm -f "$_py2"

if [[ -n "$entropy_issues" ]]; then
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        warn "Haute entropie -- $_line"
    done <<< "$entropy_issues"
fi

# =============================================================================
# COUCHE 12 -- URLs malveillantes & exfiltration web
# =============================================================================
info "Couche 12 : URLs malveillantes"

URL_BLOCK=(
    'https?://[a-z0-9-]+\.ngrok(-free)?\.app'
    'https?://[a-z0-9-]+\.ngrok\.io'
    'https?://(requestbin\.(com|net)|webhook\.site|hookbin\.com)'
    'https?://(pipedream\.net|canarytokens\.|interactsh\.com)'
    'https?://[a-z0-9]+\.burpcollaborator\.net'
    'data:text/(html|javascript)[^,]*base64'
    'data:application/(javascript|x-sh|octet-stream)[^,]*,'
    'javascript:[[:space:]]*(alert|eval|document|window)'
    'https?://(pastebin\.com|paste\.ee|hastebin\.com|ghostbin\.co)/raw/'
    'https?://[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/(download|payload|sh|bash|exec|run|shell)'
)

for pat in "${URL_BLOCK[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        block "URL malveillante -- ${pat:0:55}"
    fi
done

# =============================================================================
# COUCHE 13 -- Cryptomining
# =============================================================================
info "Couche 13 : Cryptomining"

MINING_WARN=(
    'xmrig'
    'stratum\+tcp://'
    'stratum\+ssl://'
    'pool\.(supportxmr|nanopool|moneroocean|xmrpool)\.(com|org|io)'
    '(minerd|cpuminer|nicehash)[[:space:]]'
    '--donate-level[[:space:]]+0'
    'monero[[:space:]]+(wallet|address|XMR)'
)

for pat in "${MINING_WARN[@]}"; do
    if echo "$INPUT" | grep -qiE "$pat" 2>/dev/null; then
        warn "Cryptomining -- ${pat:0:55}"
    fi
done

# =============================================================================
# VERDICT
# =============================================================================
echo -e "${BOLD}${CYAN}=== VERDICT =========================================================${RESET}" >&2
echo -e "    Log : ${LOG_FILE}" >&2

if [[ $BLOCKED -eq 1 ]]; then
    echo -e "${RED}${BOLD}[BLOQUE] Sortie dangereuse -- NE PAS UTILISER.${RESET}" >&2
    echo -e "${RED}         Relire le log, escalader si doute.${RESET}" >&2
    log "VERDICT: BLOCKED"
    exit 2
fi

if [[ $WARNED -eq 1 ]]; then
    echo -e "${ORANGE}${BOLD}[SUSPECT] Validation humaine renforcee obligatoire.${RESET}" >&2
    echo -e "${ORANGE}          Lire attentivement avant tout commit ou execution.${RESET}" >&2
    log "VERDICT: WARNED"
    printf '%s\n' "$INPUT"
    exit 1
fi

echo -e "${GREEN}${BOLD}[OK] Aucun pattern dangereux detecte.${RESET}" >&2
echo -e "${YELLOW}     Validation humaine obligatoire avant commit.${RESET}" >&2
log "VERDICT: CLEAN"
printf '%s\n' "$INPUT"
exit 0
