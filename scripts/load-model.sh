#!/usr/bin/env bash
# load-model.sh — Chargement/déchargement de modèles Ollama à la demande
# Usage : bash scripts/load-model.sh <model>
#         bash scripts/load-model.sh --unload

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

OLLAMA_PORT_MAIN=11434
OLLAMA_PORT_SANDBOX=11435
RAM_MARGIN_GB=20

# ── Modèle demandé ───────────────────────────────────────────
MODEL="${1:-}"

# ── Taille en Go par modèle ──────────────────────────────────
model_size() {
    case "$1" in
        nomic-embed-text)   echo 1  ;;
        llama3.1:8b)        echo 5  ;;
        phi4:14b)           echo 9  ;;
        codestral:22b)      echo 14 ;;
        devstral:24b)       echo 15 ;;
        gemma4:31b)         echo 20 ;;
        gemma4:31b-bf16)    echo 62 ;;
        gemma4:26b)         echo 18 ;;
        llama3.3:70b)       echo 43 ;;
        qwen2.5-coder:32b)  echo 19 ;;
        *)                  echo 10 ;;
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
    local port="${1:-$OLLAMA_PORT_MAIN}"
    local host="127.0.0.1:$port"
    local loaded

    loaded=$(OLLAMA_HOST="$host" ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^$" || true)

    if [ -z "$loaded" ]; then
        echo -e "  ${YELLOW}Aucun modèle en RAM sur port $port${RESET}"
        return
    fi

    echo "$loaded" | while IFS= read -r m; do
        [ -z "$m" ] && continue
        OLLAMA_HOST="$host" ollama stop "$m" 2>/dev/null \
            && echo -e "  ${GREEN}✓${RESET} $m déchargé (port $port)" \
            || echo -e "  ${YELLOW}⚠${RESET} $m — déjà déchargé"
    done
}

# ── Mode --unload ────────────────────────────────────────────
if [ "${MODEL}" = "--unload" ]; then
    echo -e "\n${CYAN}━━━ Déchargement RAM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    unload_all "$OLLAMA_PORT_MAIN"
    unload_all "$OLLAMA_PORT_SANDBOX"
    echo -e "\n${GREEN}✓ RAM libérée${RESET}"
    echo -e "  RAM dispo : $(get_available_ram_gb) Go\n"
    exit 0
fi

# ── Validation ───────────────────────────────────────────────
if [ -z "$MODEL" ]; then
    echo -e "${RED}Usage : make load MODEL=<nom>${RESET}"
    echo -e "        make load MODEL=gemma4:31b"
    echo -e "        make load MODEL=gemma4:31b-bf16"
    echo -e "        make unload"
    exit 1
fi

# ── Détection sandbox ────────────────────────────────────────
IS_SANDBOX=0
PORT=$OLLAMA_PORT_MAIN
if [ "$MODEL" = "qwen2.5-coder:32b" ]; then
    IS_SANDBOX=1
    PORT=$OLLAMA_PORT_SANDBOX
fi
HOST="127.0.0.1:$PORT"

echo -e "\n${CYAN}━━━ Chargement modèle ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "  Modèle  : ${BOLD}$MODEL${RESET}"
[ $IS_SANDBOX -eq 1 ] && echo -e "  Mode    : ${YELLOW}SANDBOX (port $PORT)${RESET}" \
                       || echo -e "  Port    : $PORT"

# ── RAM avant ────────────────────────────────────────────────
RAM_BEFORE=$(get_available_ram_gb)
SIZE=$(model_size "$MODEL")
NEEDED=$(( SIZE + RAM_MARGIN_GB ))

echo -e "  RAM dispo : ${RAM_BEFORE} Go  |  Requis : ~${SIZE} Go + ${RAM_MARGIN_GB} Go marge = ${NEEDED} Go"

if [ "$RAM_BEFORE" -lt "$NEEDED" ]; then
    echo -e "\n${RED}✗ RAM insuffisante — déchargement des modèles actifs...${RESET}"
    unload_all "$OLLAMA_PORT_MAIN"
    unload_all "$OLLAMA_PORT_SANDBOX"
    sleep 2
    RAM_AFTER=$(get_available_ram_gb)
    echo -e "  RAM dispo après déchargement : ${RAM_AFTER} Go"
    if [ "$RAM_AFTER" -lt "$NEEDED" ]; then
        echo -e "${RED}✗ RAM toujours insuffisante (${RAM_AFTER} Go dispo, ${NEEDED} Go requis)${RESET}\n"
        exit 1
    fi
else
    # Décharger les modèles actuels pour libérer la RAM (un seul à la fois)
    echo -e "\n${CYAN}  Déchargement du modèle actuel...${RESET}"
    unload_all "$OLLAMA_PORT_MAIN"
    [ $IS_SANDBOX -eq 0 ] || unload_all "$OLLAMA_PORT_SANDBOX"
    sleep 1
fi

# ── Vérification modèle installé ─────────────────────────────
MODEL_BASE="${MODEL%%:*}"
MODEL_TAG="${MODEL#*:}"
# Gestion tag bf16 : le nom de base reste "gemma4", tag "31b-bf16"
MANIFEST_PATH=~/.ollama/models/manifests/registry.ollama.ai/library/"$MODEL_BASE"
if ! ls "$MANIFEST_PATH"/ 2>/dev/null | grep -q .; then
    echo -e "${RED}✗ Modèle '$MODEL' non installé — lancez : ollama pull $MODEL${RESET}\n"
    exit 1
fi

# ── Chargement en RAM (warm-up API, keep_alive=-1) ───────────
echo -e "\n${CYAN}  Chargement en RAM (keep_alive infini)...${RESET}"
START=$SECONDS

curl -sf --max-time 120 -X POST "http://$HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"\",\"keep_alive\":-1}" \
    > /dev/null 2>&1 &

CURL_PID=$!

# Attente avec spinner jusqu'à ce que le modèle soit visible dans ollama ps
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
echo -e "\n${CYAN}  Modèles actifs en RAM :${RESET}"
OLLAMA_HOST="$HOST" ollama ps 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    echo -e "  ${GREEN}●${RESET}  $line"
done

if [ $IS_SANDBOX -eq 1 ]; then
    echo -e "\n${YELLOW}  ⚠ Modèle sandboxé — passer les sorties par sandbox-guard.sh${RESET}"
    echo -e "  Usage : OLLAMA_HOST=127.0.0.1:11435 ollama run $MODEL \"<prompt>\" | ./scripts/sandbox-guard.sh"
else
    echo -e "\n  Usage : ollama run $MODEL \"<prompt>\""
    echo -e "         ou Open WebUI → http://localhost:3000"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
