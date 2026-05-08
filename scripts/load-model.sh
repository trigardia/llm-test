#!/usr/bin/env bash
# load-model.sh — Chargement/déchargement de modèles Ollama à la demande
# Usage : bash scripts/load-model.sh <model>
#         bash scripts/load-model.sh --unload

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

MODEL="${1:-}"
RAM_MARGIN_GB=20

# ── Taille approximative en Go par modèle ────────────────────
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
        *)                       echo 10 ;;
    esac
}

# ── RAM disponible (Go) ──────────────────────────────────────
get_available_ram_gb() {
    local page_size free inactive spec vm
    page_size=$(sysctl -n hw.pagesize)
    vm=$(vm_stat)
    free=$(echo "$vm"     | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
    inactive=$(echo "$vm" | awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
    spec=$(echo "$vm"     | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')
    echo $(( (free + inactive + spec) * page_size / 1024 / 1024 / 1024 ))
}

# ── Déchargement de tous les modèles ────────────────────────
unload_all() {
    local loaded
    loaded=$(ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$" || true)
    if [ -z "$loaded" ]; then
        echo -e "  ${YELLOW}Aucun modèle en RAM${RESET}"
        return
    fi
    echo "$loaded" | while IFS= read -r m; do
        [ -z "$m" ] && continue
        ollama stop "$m" 2>/dev/null \
            && echo -e "  ${GREEN}✓${RESET} $m déchargé" \
            || echo -e "  ${YELLOW}⚠${RESET} $m — déjà déchargé"
    done
}

# ── Mode --unload ────────────────────────────────────────────
if [ "${MODEL}" = "--unload" ]; then
    echo -e "\n${CYAN}━━━ Déchargement RAM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    unload_all
    echo -e "\n${GREEN}✓ RAM libérée — $(get_available_ram_gb) Go disponibles${RESET}\n"
    exit 0
fi

# ── Validation argument ──────────────────────────────────────
if [ -z "$MODEL" ]; then
    echo -e "${RED}Usage : make load MODEL=<nom>${RESET}"
    echo -e "        make load MODEL=gemma4:31b"
    echo -e "        make load MODEL=qwen3.6:27b"
    echo -e "        make unload"
    exit 1
fi

# ── Avertissement modèle chinois ─────────────────────────────
case "$MODEL" in
    qwen*)
        echo -e "${YELLOW}⚠ Modèle Alibaba 🇨🇳 — toujours piper via sandbox-guard.sh${RESET}"
        echo -e "${YELLOW}  ollama run $MODEL \"prompt\" | ./scripts/sandbox-guard.sh${RESET}"
        ;;
esac

echo -e "\n${CYAN}━━━ Chargement : $MODEL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ── Vérification RAM ─────────────────────────────────────────
RAM_BEFORE=$(get_available_ram_gb)
SIZE=$(model_size "$MODEL")
NEEDED=$(( SIZE + RAM_MARGIN_GB ))

echo -e "  RAM dispo : ${RAM_BEFORE} Go  |  Requis : ~${SIZE} Go + ${RAM_MARGIN_GB} Go marge = ${NEEDED} Go"

if [ "$RAM_BEFORE" -lt "$NEEDED" ]; then
    echo -e "\n${CYAN}  RAM insuffisante — déchargement des modèles actifs...${RESET}"
    unload_all
    sleep 2
    RAM_BEFORE=$(get_available_ram_gb)
    if [ "$RAM_BEFORE" -lt "$NEEDED" ]; then
        echo -e "${RED}✗ RAM toujours insuffisante (${RAM_BEFORE} Go dispo, ${NEEDED} Go requis)${RESET}\n"
        exit 1
    fi
else
    echo -e "\n${CYAN}  Déchargement du modèle actuel...${RESET}"
    unload_all
    sleep 1
fi

# ── Vérification modèle installé ─────────────────────────────
MODEL_BASE="${MODEL%%:*}"
if ! ls ~/.ollama/models/manifests/registry.ollama.ai/library/"$MODEL_BASE"/ 2>/dev/null | grep -q .; then
    echo -e "${RED}✗ '$MODEL' non installé — lancez : ollama pull $MODEL${RESET}\n"
    exit 1
fi

# ── Chargement en RAM (keep_alive infini) ────────────────────
echo -e "\n${CYAN}  Chargement en RAM...${RESET}"
START=$SECONDS

curl -sf --max-time 120 -X POST "http://127.0.0.1:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"\",\"keep_alive\":-1}" \
    > /dev/null 2>&1 &

CURL_PID=$!
SPINNER="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
i=0
while kill -0 $CURL_PID 2>/dev/null; do
    printf "\r  ${CYAN}%s${RESET} Chargement en cours..." "${SPINNER:$((i % ${#SPINNER})):1}"
    i=$(( i + 1 ))
    sleep 0.2
done
printf "\r  %-40s\r" " "

DURATION=$(( SECONDS - START ))
RAM_AFTER=$(get_available_ram_gb)
RAM_USED=$(( RAM_BEFORE - RAM_AFTER ))

echo -e "${GREEN}✓ $MODEL chargé en ${DURATION}s${RESET}"
echo -e "  RAM consommée : ~${RAM_USED} Go  |  RAM dispo : ${RAM_AFTER} Go"

# ── État final ───────────────────────────────────────────────
echo -e "\n${CYAN}  Modèles actifs :${RESET}"
ollama ps 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    echo -e "  ${GREEN}●${RESET}  $line"
done

echo -e "\n  Usage : ollama run $MODEL \"<prompt>\""
echo -e "         ou Open WebUI → http://localhost:3000"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
