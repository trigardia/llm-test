#!/usr/bin/env bash
# security-test.sh — Benchmark LLM : détection de vulnérabilités OWASP 2025
# Chaque modèle analyse un fichier de vulnérabilités intentionnelles
# Sortie : rapport Markdown + scores CSV (compatible GitLab CI artifacts)
#
# Usage :
#   make security-test                                     ← tous modèles × tous samples
#   make security-test MODEL=codestral:22b                 ← un seul modèle
#   make security-test SAMPLE=A03-injection.php            ← un seul fichier
#   make security-test MODEL=llama3.3:70b SAMPLE=A03-injection.php

set -euo pipefail

# ── Couleurs ──────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Détection timeout (GNU coreutils via Homebrew) ────────────────────
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
else
    echo "⚠ timeout/gtimeout non trouvé — install: brew install coreutils" >&2
    exit 1
fi

# ── Chemins ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SAMPLES_DIR="$ROOT_DIR/tests/security/samples"
PROMPT_FILE="$ROOT_DIR/tests/security/prompts/security-audit-prompt.md"
RESULTS_DIR="$ROOT_DIR/tests/security/results"
ANALYSIS_DIR="$ROOT_DIR/tests/security/analysis"
SANDBOX="$SCRIPT_DIR/sandbox-guard.sh"

mkdir -p "$RESULTS_DIR" "$ANALYSIS_DIR"

# ── Timestamp ──────────────────────────────────────────────────────────
TS=$(date '+%Y%m%d-%H%M%S')
DATE_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
REPORT="$RESULTS_DIR/security-$(date '+%Y%m%d-%H%M%S').md"
SCORES_CSV="$ANALYSIS_DIR/scores-$TS.csv"

# ── Modèles à tester (léger → lourd) ─────────────────────────────────
ALL_MODELS="foundation-sec-reasoning phi4-reasoning:plus codestral:22b devstral-small-2 gemma4:31b llama3.3:70b qwen3.6:27b"
TARGET_MODEL="${MODEL:-}"   # vide = tous les modèles
TARGET_SAMPLE="${SAMPLE:-}" # vide = tous les fichiers

# ── Taille RAM par modèle ─────────────────────────────────────────────
model_size() {
    case "$1" in
        foundation-sec-reasoning) echo 9  ;;
        phi4-reasoning:plus)      echo 9  ;;
        codestral:22b)            echo 14 ;;
        devstral-small-2)         echo 15 ;;
        gemma4:31b)               echo 20 ;;
        llama3.3:70b)             echo 43 ;;
        qwen3.6:27b)              echo 17 ;;
        *)                        echo 0  ;;
    esac
}

# ── Utilitaires ───────────────────────────────────────────────────────
log() { echo -e "$1" | tee -a "$REPORT"; }

get_available_ram_gb() {
    local page_size free inactive spec vm
    page_size=$(sysctl -n hw.pagesize)
    vm=$(vm_stat)
    free=$(echo "$vm"    | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
    inactive=$(echo "$vm"| awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
    spec=$(echo "$vm"    | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
    echo $(( (free + inactive + spec) * page_size / 1024 / 1024 / 1024 ))
}

stop_all_models() {
    local loaded
    loaded=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$' || true)
    if [ -n "$loaded" ]; then
        echo "$loaded" | while read -r m; do
            ollama stop "$m" 2>/dev/null || true
        done
        sleep 2
    fi
}

load_model() {
    local model="$1" size
    size=$(model_size "$model")
    local avail
    avail=$(get_available_ram_gb)
    local margin=20
    if (( avail < size + margin )); then
        log "${RED}✗ RAM insuffisante pour $model (besoin ~${size}Go, dispo ${avail}Go)${RESET}"
        return 1
    fi
    stop_all_models
    log "${CYAN}→ Chargement $model (~${size}Go RAM)...${RESET}"
    ollama run "$model" "" >/dev/null 2>&1 || true
    sleep 2
    return 0
}

# ── Prompt builder : injecte le code dans le template ─────────────────
build_prompt() {
    local sample_file="$1"
    local code
    code=$(cat "$sample_file")
    local template
    template=$(cat "$PROMPT_FILE")
    echo "${template//\{\{CODE\}\}/$code}"
}

# ── Appel au modèle avec sandbox pour qwen ────────────────────────────
query_model() {
    local model="$1"
    local prompt="$2"
    local start_ts end_ts elapsed output

    start_ts=$(date +%s)
    if [ "$model" = "qwen3.6:27b" ]; then
        # Filtre obligatoire via sandbox-guard.sh (CLAUDE.md règle absolue)
        output=$(echo "$prompt" | ollama run "$model" 2>/dev/null | bash "$SANDBOX" 2>/dev/null || echo "[BLOQUÉ PAR SANDBOX-GUARD]")
    else
        output=$(echo "$prompt" | ollama run "$model" 2>/dev/null)
    fi
    end_ts=$(date +%s)
    elapsed=$(( end_ts - start_ts ))
    echo "ELAPSED=$elapsed"
    echo "$output"
}

# ── Extraction du score /20 depuis la réponse ─────────────────────────
# Priorité : SCORE_GLOBAL: X/20 en début de réponse (format imposé par le prompt)
# Fallback : cherche X/20 dans la réponse nettoyée (sans blocs <think>)
extract_score() {
    local response="$1"

    # 1. Priorité absolue : pattern "SCORE_GLOBAL: X/20" imposé par le prompt
    local score
    score=$(echo "$response" | grep -oiE 'SCORE_GLOBAL:\s*([0-9]{1,2})/20' \
            | grep -oE '[0-9]{1,2}/20' | head -1 | cut -d'/' -f1)
    [ -n "$score" ] && { echo "$score"; return; }

    # 2. Supprime les blocs <think>...</think> (phi4-reasoning, qwen3.6)
    local clean
    clean=$(echo "$response" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
print(text)
" 2>/dev/null || echo "$response")

    # 3. Cherche X/20 dans les 20 premières lignes (score en tête de réponse)
    score=$(echo "$clean" | head -20 \
            | grep -oiE '([0-9]{1,2})/20' | head -1 | cut -d'/' -f1)
    [ -n "$score" ] && { echo "$score"; return; }

    # 4. Cherche dans les 30 dernières lignes (score en fin de réponse)
    score=$(echo "$clean" | tail -30 \
            | grep -oiE '(score|note)[^0-9]*([0-9]{1,2})/20' \
            | grep -oE '[0-9]{1,2}/20' | tail -1 | cut -d'/' -f1)
    [ -n "$score" ] && { echo "$score"; return; }

    echo "N/A"
}

# ── Header du rapport ──────────────────────────────────────────────────
init_report() {
    cat > "$REPORT" <<EOF
# Rapport Security Benchmark LLM — OWASP Top 10:2025
**Date** : $DATE_HUMAN
**Machine** : MacBook Pro M5 Max — 128 Go RAM
**Référence** : OWASP Top 10:2025 + OWASP LLM Top 10:2025
**Objectif** : Sélection LLM pour pipeline GitLab CI DevSecOps (aux côtés de Trivy)

---
EOF
    echo "model,sample,score_20,elapsed_sec,sandbox_exit,date" > "$SCORES_CSV"
}

# ── Test d'un modèle sur un fichier sample ─────────────────────────────
run_test() {
    local model="$1"
    local sample_path="$2"
    local sample_name
    sample_name=$(basename "$sample_path")
    local sandbox_exit=0

    log "\n## $model — $sample_name"
    log "\n**Date** : $(date '+%H:%M:%S') | **Fichier** : \`$sample_name\`"

    # Construction du prompt
    local prompt
    prompt=$(build_prompt "$sample_path")

    # Appel via API REST Ollama (one-shot, stream:false, timeout curl natif)
    # Beaucoup plus fiable que 'ollama run' en mode stdin
    local tmp_json start_ts end_ts elapsed raw_output output
    tmp_json=$(mktemp /tmp/llm-payload.XXXXXX)  # macOS BSD mktemp: pas de suffix après XXXXXX

    # Construction du payload JSON via /api/chat (plus propre que /api/generate)
    # think:false → désactive le mode raisonnement étendu sur phi4-reasoning et qwen3.6
    # → réponse directe sans bloc <think>, rapide et sans troncature
    python3 -c "
import json, sys
model  = sys.argv[1]
prompt = sys.argv[2]

thinking_models = ['phi4-reasoning', 'qwen3.6', 'qwq', 'deepseek-r1']
is_thinking = any(m in model for m in thinking_models)

payload = {
    'model':    model,
    'messages': [{'role': 'user', 'content': prompt}],
    'stream':   False,
    'think':    False,          # désactive le reasoning étendu (Ollama >= 0.6.5)
    'options':  {
        'num_predict': 8192,
        'temperature': 0.1,
        'num_ctx':     8192,
    }
}
print(json.dumps(payload))
" "$model" "$prompt" > "$tmp_json"

    start_ts=$(date +%s)
    if [ "$model" = "qwen3.6:27b" ]; then
        raw_output=$(curl -s --max-time 600 \
            -H "Content-Type: application/json" \
            -d @"$tmp_json" \
            http://localhost:11434/api/chat \
            | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('message', {}).get('content', d.get('response', 'ERROR')))
" 2>/dev/null || echo "TIMEOUT")
        echo "$raw_output" | bash "$SANDBOX" >/dev/null 2>/dev/null || true
        sandbox_exit=$?
        if [ $sandbox_exit -eq 2 ]; then
            output="[BLOQUÉ PAR SANDBOX-GUARD]"
            log "${RED}⚠ sandbox-guard exit 2 — réponse BLOQUÉE${RESET}"
        elif [ $sandbox_exit -eq 1 ]; then
            output="$raw_output"
            log "${YELLOW}⚠ sandbox-guard exit 1 — SUSPECT, validation humaine requise${RESET}"
        else
            output="$raw_output"
        fi
    else
        output=$(curl -s --max-time 600 \
            -H "Content-Type: application/json" \
            -d @"$tmp_json" \
            http://localhost:11434/api/chat \
            | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('message', {}).get('content', d.get('response', 'ERROR')))
" 2>/dev/null || echo "TIMEOUT")
    fi
    end_ts=$(date +%s)
    elapsed=$(( end_ts - start_ts ))
    rm -f "$tmp_json"

    # Score
    local score
    score=$(extract_score "$output")

    # Log dans le rapport
    log "\n**Temps** : ${elapsed}s | **Score extrait** : ${score}/20 | **Sandbox** : exit $sandbox_exit"
    log "\n<details><summary>Réponse complète</summary>\n\n\`\`\`\n$output\n\`\`\`\n</details>"
    log "\n---"

    # CSV
    echo "$model,$sample_name,$score,$elapsed,$sandbox_exit,$(date '+%Y-%m-%d %H:%M:%S')" \
        >> "$SCORES_CSV"

    # Feedback terminal
    if [ "$score" != "N/A" ]; then
        local color=$RED
        (( score >= 15 )) && color=$GREEN
        (( score >= 10 && score < 15 )) && color=$YELLOW
        echo -e "  ${color}Score : $score/20${RESET} | Temps : ${elapsed}s"
    else
        echo -e "  ${YELLOW}Score non extractible${RESET} | Temps : ${elapsed}s"
    fi
}

# ══════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════"
echo -e " Security Benchmark LLM — OWASP Top 10:2025"
echo -e " GitLab CI DevSecOps — Red Team R&D"
echo -e "══════════════════════════════════════════════════${RESET}\n"

# Vérifications
if ! pgrep -x ollama > /dev/null 2>&1; then
    echo -e "${RED}✗ Ollama non démarré — lancez : make ollama-check${RESET}"
    exit 1
fi
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}✗ Prompt introuvable : $PROMPT_FILE${RESET}"
    exit 1
fi

init_report

# Sélection des modèles
if [ -n "$TARGET_MODEL" ]; then
    MODELS_TO_TEST="$TARGET_MODEL"
else
    MODELS_TO_TEST="$ALL_MODELS"
fi

# Sélection des samples (compatible bash 3.x macOS — pas de mapfile)
SAMPLES=()
if [ -n "$TARGET_SAMPLE" ]; then
    while IFS= read -r f; do SAMPLES+=("$f"); done < <(
        find "$SAMPLES_DIR" -name "$TARGET_SAMPLE" -type f | sort
    )
else
    while IFS= read -r f; do SAMPLES+=("$f"); done < <(
        find "$SAMPLES_DIR" -type f \
            \( -name "*.php" -o -name "*.py" -o -name "*.js" \
               -o -name "*.java" -o -name "*.sh" \) | sort
    )
fi

TOTAL_SAMPLES=${#SAMPLES[@]}
echo -e "${CYAN}Modèles : $MODELS_TO_TEST${RESET}"
echo -e "${CYAN}Fichiers : $TOTAL_SAMPLES samples${RESET}"
echo -e "${CYAN}Rapport  : $REPORT${RESET}\n"

# Boucle principale
for model in $MODELS_TO_TEST; do
    echo -e "\n${BOLD}${GREEN}▶ Modèle : $model${RESET}"
    log "\n# Modèle : $model\n"

    if ! load_model "$model"; then
        log "${RED}✗ Chargement impossible — modèle ignoré${RESET}"
        continue
    fi

    idx=0
    for sample in "${SAMPLES[@]}"; do
        idx=$(( idx + 1 ))
        echo -e "\n${CYAN}[$idx/$TOTAL_SAMPLES] $(basename "$sample")${RESET}"
        run_test "$model" "$sample"
    done

    stop_all_models
done

# ── Résumé final ───────────────────────────────────────────────────────
log "\n\n# Résumé — Scores par modèle\n"
log "| Modèle | Moy./20 | Meilleur | Pire | Temps moy. |"
log "|--------|---------|----------|------|------------|"

if command -v python3 &>/dev/null; then
    python3 - "$SCORES_CSV" <<'PYEOF'
import sys, csv
from collections import defaultdict

scores = defaultdict(list)
times  = defaultdict(list)

with open(sys.argv[1]) as f:
    reader = csv.DictReader(f)
    for row in reader:
        model = row['model']
        if row['score_20'] not in ('N/A', ''):
            scores[model].append(int(row['score_20']))
        if row['elapsed_sec']:
            times[model].append(int(row['elapsed_sec']))

for model, sc in sorted(scores.items()):
    avg  = round(sum(sc) / len(sc), 1)
    best = max(sc)
    worst = min(sc)
    avg_t = round(sum(times[model]) / len(times[model])) if times[model] else 0
    print(f"| {model:<30} | {avg:>7} | {best:>8} | {worst:>4} | {avg_t:>9}s |")
PYEOF
fi | tee -a "$REPORT"

echo -e "\n${GREEN}✓ Rapport   : $REPORT${RESET}"
echo -e "${GREEN}✓ Scores CSV : $SCORES_CSV${RESET}"
echo -e "${CYAN}→ Intégration GitLab CI : copier le CSV dans le job artifact path${RESET}\n"
