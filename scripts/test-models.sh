#!/usr/bin/env bash
# Test séquentiel des modèles — un seul modèle chargé en RAM à la fois
# Sandbox qwen2.5-coder:32b testé séparément (port 11435)

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

RESULTS_DIR="$(dirname "$0")/../tests/perf/results"
PROMPTS_DIR="$(dirname "$0")/../tests/perf/prompts"
mkdir -p "$RESULTS_DIR"
REPORT="$RESULTS_DIR/rapport-$(date '+%Y%m%d-%H%M%S').md"
BENCHMARK_PROMPT="$PROMPTS_DIR/dev-benchmark-mission.md"

RAM_MARGIN_GB=20

# ── Ordre des modèles (léger → lourd) ──────────────────────
MODELS="nomic-embed-text-v2-moe phi4-reasoning:plus codestral:22b devstral-small-2 gemma4:31b llama3.3:70b qwen3.6:27b"

# ── Taille en Go par modèle ─────────────────────────────────
model_size() {
    case "$1" in
        nomic-embed-text-v2-moe) echo 1  ;;
        phi4-reasoning:plus)          echo 9  ;;
        codestral:22b)           echo 14 ;;
        devstral-small-2)        echo 15 ;;
        gemma4:31b)              echo 20 ;;
        gemma4:31b-bf16)         echo 62 ;;
        llama3.3:70b)            echo 43 ;;
        qwen3.6:27b)             echo 17 ;;
        *)                       echo 0  ;;
    esac
}

# ── Prompt de test par modèle ───────────────────────────────
# MODE=quick  → prompt ciblé rapide (défaut pour make test)
# MODE=full   → benchmark ultime 6 behaviors (make test-full)
MODEL_MODE="${MODEL_MODE:-quick}"

model_prompt() {
    if [ "$MODEL_MODE" = "full" ] && [ -f "$BENCHMARK_PROMPT" ]; then
        cat "$BENCHMARK_PROMPT"
        return
    fi
    case "$1" in
        nomic-embed-text-v2-moe)
            echo "Stack LLM local sécurisée sur Apple Silicon M5 Max — Symfony Java K8s ELK" ;;
        phi4-reasoning:plus)
            echo "Cite 3 principes SOLID appliqués à une API REST Java Spring Boot. Réponse courte." ;;
        codestral:22b)
            echo "Écris une fonction PHP qui sanitise une entrée utilisateur contre les injections SQL. Réponse courte." ;;
        devstral-small-2)
            echo "Donne la structure Clean Architecture pour un projet Symfony avec un use case CreateUser. Réponse courte." ;;
        gemma4:31b|gemma4:31b-bf16)
            echo "Donne une requête KQL Kibana pour détecter des tentatives brute-force SSH dans les logs ELK." ;;
        llama3.3:70b)
            echo "Architecture K8s pour déployer une app Java Spring Boot haute disponibilité ? 3 points max." ;;
        qwen3.6:27b)
            echo "Écris une fonction Python qui parse un fichier YAML de config Ansible. Réponse courte." ;;
        *)
            echo "Tu fonctionnes correctement ? Réponds en une phrase." ;;
    esac
}

# ── Utilitaires ─────────────────────────────────────────────
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
    local loaded ram_before ram_after waited
    loaded=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$" || true)
    if [ -n "$loaded" ]; then
        ram_before=$(get_available_ram_gb)
        echo -e "  ${YELLOW}Déchargement RAM... (avant : ${ram_before} Go dispo)${RESET}"
        echo "$loaded" | while IFS= read -r m; do
            [ -z "$m" ] && continue
            ollama stop "$m" 2>/dev/null && echo -e "    ${GREEN}✓${RESET} $m arrêté"
        done
        # Attendre que ollama ps soit vide (max 15s)
        waited=0
        while [ "$waited" -lt 15 ]; do
            sleep 1
            waited=$(( waited + 1 ))
            [ -z "$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$' || true)" ] && break
        done
        sleep 2  # laisser macOS reclaimer la RAM physique
        ram_after=$(get_available_ram_gb)
        echo -e "  ${GREEN}✓ RAM libérée : ${ram_before} → ${ram_after} Go disponibles${RESET}"
    else
        echo -e "  ${GREEN}✓ Aucun modèle en RAM — prêt${RESET}"
    fi
}

check_model_installed() {
    local name="${1%%:*}"
    ls ~/.ollama/models/manifests/registry.ollama.ai/library/"$name"/ 2>/dev/null | grep -q . && return 0 || return 1
}

# ── Test d'un modèle standard (port 11434) ──────────────────
run_test() {
    local model="$1"
    local prompt size available needed start duration output

    prompt=$(model_prompt "$model")
    size=$(model_size "$model")

    log "\n---\n## $model\n"
    log "**Taille** : ~${size} Go | **Date** : $(date '+%Y-%m-%d %H:%M:%S')"

    if ! check_model_installed "$model"; then
        log "\n> ⚠ Non installé — \`ollama pull $model\`\n"
        echo -e "  ${YELLOW}⚠ $model non installé — ignoré${RESET}"
        return
    fi

    available=$(get_available_ram_gb)
    needed=$(( size + RAM_MARGIN_GB ))

    if [ "$size" -gt 0 ] && [ "$available" -lt "$needed" ]; then
        log "\n> ✗ RAM insuffisante : ${available} Go dispo, ${needed} Go requis\n"
        echo -e "  ${RED}✗ RAM insuffisante pour $model${RESET}"
        return
    fi

    # Vérification finale : aucun autre modèle en RAM
    local active_models
    active_models=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$" || true)
    if [ -n "$active_models" ]; then
        echo -e "  ${RED}✗ Modèle(s) encore en RAM : $active_models — test annulé pour isolation${RESET}"
        log "\n> ✗ Isolation RAM non garantie — test ignoré\n"
        return
    fi

    echo -e "\n${CYAN}┌── $model ──────────────────────────────────────────${RESET}"
    echo -e "${CYAN}│  RAM dispo : ${available} Go | Taille : ~${size} Go | Modèles en RAM : aucun ✓${RESET}"
    echo -e "${CYAN}│  Mode : ${MODEL_MODE}${RESET}"
    echo -e "${CYAN}└────────────────────────────────────────────────────${RESET}\n"

    log "\n**RAM avant test** : ${available} Go | **Mode** : ${MODEL_MODE}\n"
    log "\n**Prompt** : \`$prompt\`\n"

    # Cas spécial : embedding
    if [ "$model" = "nomic-embed-text" ]; then
        start=$SECONDS
        output=$(curl -sf --max-time 60 http://localhost:11434/api/embeddings \
            -d "{\"model\":\"nomic-embed-text\",\"prompt\":\"$prompt\"}" 2>/dev/null \
            | python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d['embedding']
print(f'Vecteur {len(v)} dimensions — min={min(v):.4f} max={max(v):.4f}')
" 2>/dev/null || echo "Erreur embedding")
        duration=$(( SECONDS - start ))
        echo -e "${GREEN}✓ $output${RESET} (${duration}s)"
        log "\n**Résultat** : $output | **Durée** : ${duration}s | **Statut** : ✅ OK\n"
        return
    fi

    # Test chat via API (pas de ollama run — sortie propre sans ANSI)
    local timeout_s=600
    [ "$MODEL_MODE" = "full" ] && timeout_s=1200
    local payload
    payload=$(python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'prompt': sys.argv[2], 'stream': False}))
" "$model" "$prompt" 2>/dev/null)

    start=$SECONDS
    local raw
    raw=$(curl -sf --max-time "$timeout_s" \
        -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo "ERREUR_CURL")
    duration=$(( SECONDS - start ))

    if [ "$raw" = "ERREUR_CURL" ] || [ -z "$raw" ]; then
        echo -e "${RED}✗ Erreur API pour $model${RESET}"
        log "\n**Statut** : ❌ ÉCHEC API | **Durée** : ${duration}s\n"
        return
    fi

    output=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', 'ERREUR_JSON'))
except Exception as e:
    print('ERREUR_PARSE: ' + str(e))
" 2>/dev/null || echo "ERREUR")

    if [[ "$output" == ERREUR* ]]; then
        echo -e "${RED}✗ $output${RESET}"
        log "\n**Statut** : ❌ ÉCHEC | **Durée** : ${duration}s\n"
    else
        echo -e "${GREEN}✓ Réponse reçue en ${duration}s${RESET}\n"
        echo "$output"
        log "\n**Réponse** :\n\`\`\`\n$output\n\`\`\`\n"
        log "**Durée** : ${duration}s | **Statut** : ✅ OK\n"
    fi
}

# ── Test modèle Alibaba (avec filtre sandbox-guard.sh) ──────
run_qwen_test() {
    local model="$1"
    local prompt size available needed start duration output

    prompt=$(model_prompt "$model")
    size=$(model_size "$model")

    log "\n---\n## $model (⚠ Alibaba — filtré via sandbox-guard.sh)\n"
    log "**Date** : $(date '+%Y-%m-%d %H:%M:%S')"
    log "\n**Prompt** : \`$prompt\`\n"

    if ! check_model_installed "$model"; then
        log "\n> ⚠ Non installé — \`ollama pull $model\`\n"
        echo -e "  ${YELLOW}⚠ $model non installé — ignoré${RESET}"
        return
    fi

    available=$(get_available_ram_gb)
    needed=$(( size + RAM_MARGIN_GB ))
    if [ "$available" -lt "$needed" ]; then
        echo -e "  ${RED}✗ RAM insuffisante : ${available} Go dispo, ${needed} Go requis${RESET}"
        log "\n**Statut** : ❌ RAM insuffisante\n"
        return
    fi

    echo -e "\n${CYAN}┌── $model (⚠ Alibaba 🇨🇳 — sandbox-guard.sh actif) ─${RESET}"
    echo -e "${CYAN}│  Prompt : $prompt${RESET}"
    echo -e "${CYAN}└────────────────────────────────────────────────────${RESET}\n"

    local timeout_s=600
    [ "$MODEL_MODE" = "full" ] && timeout_s=1200
    local payload
    payload=$(python3 -c "
import json, sys
print(json.dumps({'model': sys.argv[1], 'prompt': sys.argv[2], 'stream': False}))
" "$model" "$prompt" 2>/dev/null)

    start=$SECONDS
    local raw
    raw=$(curl -sf --max-time "$timeout_s" \
        -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo "ERREUR_CURL")
    duration=$(( SECONDS - start ))

    output=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('response', 'ERREUR_JSON'))
except:
    print('ERREUR_PARSE')
" 2>/dev/null || echo "ERREUR")

    # Filtre sandbox-guard sur la sortie
    output=$(echo "$output" | bash "$(dirname "$0")/sandbox-guard.sh" 2>/dev/null || echo "ERREUR_SANDBOX")

    if [[ "$output" == ERREUR* ]]; then
        echo -e "${RED}✗ $output${RESET}"
        log "\n**Statut** : ❌ ÉCHEC | **Durée** : ${duration}s\n"
    else
        echo -e "${GREEN}✓ Réponse reçue en ${duration}s (filtrée sandbox-guard)${RESET}\n"
        echo "$output"
        log "\n**Réponse** :\n\`\`\`\n$output\n\`\`\`\n"
        log "**Durée** : ${duration}s | **Statut** : ✅ OK\n"
    fi
}

# ── Main ─────────────────────────────────────────────────────
MODEL_ARG="${1:-}"

cat > "$REPORT" << EOF
# Rapport de tests — Modèles LLM
**Date** : $(date '+%Y-%m-%d %H:%M:%S')
**Machine** : MacBook Pro M5 Max — 128 Go RAM
**Mode** : Un modèle chargé à la fois — marge ${RAM_MARGIN_GB} Go
EOF

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║     Test séquentiel — tous les modèles LLM           ║${RESET}"
echo -e "${CYAN}║     Rapport : tests/results/                         ║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"

if [ -n "$MODEL_ARG" ]; then
    stop_all_models
    case "$MODEL_ARG" in
        qwen*)
            run_qwen_test "$MODEL_ARG"
            ;;
        *)
            run_test "$MODEL_ARG"
            ;;
    esac
else
    for model in $MODELS; do
        stop_all_models
        case "$model" in
            qwen*)
                run_qwen_test "$model"
                ;;
            *)
                run_test "$model"
                ;;
        esac
        echo -e "\n${CYAN}── Pause 3s ────────────────────────────────────────${RESET}"
        sleep 3
    done
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║  Tests terminés — rapport : tests/results/           ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
log "\n---\n*Rapport généré automatiquement par test-models.sh*"
