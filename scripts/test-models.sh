#!/usr/bin/env bash
# Test séquentiel des modèles — un seul modèle chargé en RAM à la fois
# Sandbox qwen2.5-coder:32b testé séparément (port 11435)

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

RESULTS_DIR="$(dirname "$0")/../tests/results"
mkdir -p "$RESULTS_DIR"
REPORT="$RESULTS_DIR/rapport-$(date '+%Y%m%d-%H%M%S').md"

RAM_MARGIN_GB=20

# ── Ordre des modèles (léger → lourd) ──────────────────────
MODELS="nomic-embed-text llama3.1:8b phi4:14b codestral:22b devstral:24b gemma4:31b llama3.3:70b"

# ── Taille en Go par modèle ─────────────────────────────────
model_size() {
    case "$1" in
        nomic-embed-text) echo 0 ;;
        llama3.1:8b)      echo 5 ;;
        phi4:14b)         echo 9 ;;
        codestral:22b)    echo 14 ;;
        devstral:24b)     echo 15 ;;
        gemma4:31b)       echo 20 ;;
        gemma4:31b-bf16)  echo 62 ;;
        llama3.3:70b)     echo 43 ;;
        qwen2.5-coder:32b) echo 19 ;;
        *)                echo 0 ;;
    esac
}

# ── Prompt de test par modèle ───────────────────────────────
model_prompt() {
    case "$1" in
        nomic-embed-text)
            echo "LLM local sécurisé sur Apple Silicon M5 Max" ;;
        llama3.1:8b)
            echo "En une phrase : quelle est la première règle OWASP Top 10 pour les API ?" ;;
        phi4:14b)
            echo "Cite 3 principes SOLID appliqués à une API REST Java. Réponse courte." ;;
        codestral:22b)
            echo "Écris une fonction PHP qui sanitise une entrée utilisateur contre les injections SQL. Réponse courte." ;;
        devstral:24b)
            echo "Donne la structure Clean Architecture pour un projet Symfony avec un use case CreateUser. Réponse courte." ;;
        gemma4:31b|gemma4:31b-bf16)
            echo "Donne une requête KQL Kibana pour détecter des tentatives brute-force SSH dans les logs ELK." ;;
        llama3.3:70b)
            echo "Architecture K8s pour déployer une app Java Spring Boot haute disponibilité ? 3 points max." ;;
        qwen2.5-coder:32b)
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
    local loaded
    loaded=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$" || true)
    if [ -n "$loaded" ]; then
        echo -e "  ${YELLOW}Déchargement RAM...${RESET}"
        echo "$loaded" | while IFS= read -r m; do
            [ -z "$m" ] && continue
            ollama stop "$m" 2>/dev/null && echo -e "    ${GREEN}✓${RESET} $m libéré"
        done
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

    echo -e "\n${CYAN}┌── $model ──────────────────────────────────────────${RESET}"
    echo -e "${CYAN}│  RAM dispo : ${available} Go | Taille : ~${size} Go${RESET}"
    echo -e "${CYAN}│  Prompt : $prompt${RESET}"
    echo -e "${CYAN}└────────────────────────────────────────────────────${RESET}\n"

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

    # Test chat standard
    start=$SECONDS
    output=$(ollama run "$model" "$prompt" 2>/dev/null || echo "ERREUR")
    duration=$(( SECONDS - start ))

    if [ "$output" = "ERREUR" ]; then
        echo -e "${RED}✗ Erreur lors du test de $model${RESET}"
        log "\n**Statut** : ❌ ÉCHEC | **Durée** : ${duration}s\n"
    else
        echo -e "${GREEN}✓ Réponse reçue en ${duration}s${RESET}\n"
        echo "$output"
        log "\n**Réponse** :\n\`\`\`\n$output\n\`\`\`\n"
        log "**Durée** : ${duration}s | **Statut** : ✅ OK\n"
    fi
}

# ── Test sandbox qwen2.5-coder:32b (port 11435) ─────────────
run_sandbox_test() {
    local model="qwen2.5-coder:32b"
    local prompt size available start duration output

    prompt=$(model_prompt "$model")
    size=$(model_size "$model")

    echo -e "\n${CYAN}┌── $model (SANDBOX port 11435) ─────────────────────${RESET}"
    echo -e "${CYAN}│  Prompt : $prompt${RESET}"
    echo -e "${CYAN}└────────────────────────────────────────────────────${RESET}\n"

    log "\n---\n## $model (sandbox)\n"
    log "**Port** : 11435 | **Date** : $(date '+%Y-%m-%d %H:%M:%S')"
    log "\n**Prompt** : \`$prompt\`\n"

    if ! curl -sf http://127.0.0.1:11435/api/tags &>/dev/null; then
        echo -e "  ${RED}✗ Sandbox non accessible sur port 11435 — make sandbox-setup${RESET}"
        log "\n**Statut** : ❌ Sandbox non démarré\n"
        return
    fi

    available=$(get_available_ram_gb)
    needed=$(( size + RAM_MARGIN_GB ))
    if [ "$available" -lt "$needed" ]; then
        echo -e "  ${RED}✗ RAM insuffisante : ${available} Go dispo, ${needed} Go requis${RESET}"
        log "\n**Statut** : ❌ RAM insuffisante\n"
        return
    fi

    start=$SECONDS
    output=$(OLLAMA_HOST=127.0.0.1:11435 ollama run "$model" "$prompt" 2>/dev/null \
        | bash "$(dirname "$0")/sandbox-guard.sh" 2>/dev/null || echo "ERREUR")
    duration=$(( SECONDS - start ))

    if [ "$output" = "ERREUR" ]; then
        echo -e "${RED}✗ Erreur sandbox${RESET}"
        log "\n**Statut** : ❌ ÉCHEC | **Durée** : ${duration}s\n"
    else
        echo -e "${GREEN}✓ Réponse sandbox reçue en ${duration}s${RESET}\n"
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
    if [ "$MODEL_ARG" = "qwen2.5-coder:32b" ]; then
        run_sandbox_test
    else
        stop_all_models
        run_test "$MODEL_ARG"
    fi
else
    for model in $MODELS; do
        stop_all_models
        run_test "$model"
        echo -e "\n${CYAN}── Pause 3s ────────────────────────────────────────${RESET}"
        sleep 3
    done
    # Test sandbox en dernier
    echo -e "\n${CYAN}── Sandbox qwen2.5-coder:32b ───────────────────────${RESET}"
    run_sandbox_test
fi

echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║  Tests terminés — rapport : tests/results/           ║${RESET}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${RESET}"
log "\n---\n*Rapport généré automatiquement par test-models.sh*"
