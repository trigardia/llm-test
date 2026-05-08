#!/usr/bin/env bash
# Garde-fou : vérifie RAM disponible avant de charger un modèle
# Usage : ./check-resources.sh <modele> <taille_go>
# Exemple : ./check-resources.sh codestral:22b 14

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

RAM_MARGIN_GB=20   # Marge minimale obligatoire

MODEL="${1:-}"
MODEL_SIZE_GB="${2:-0}"

# ── RAM disponible ───────────────────────────────────────────
page_size=$(sysctl -n hw.pagesize)
vm=$(vm_stat)
free=$(echo "$vm"        | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
inactive=$(echo "$vm"    | awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
speculative=$(echo "$vm" | awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')

available_gb=$(( (free + inactive + speculative) * page_size / 1024 / 1024 / 1024 ))
needed_gb=$(( MODEL_SIZE_GB + RAM_MARGIN_GB ))

echo -e "──────────────────────────────────────────"
echo -e "  Modèle     : ${MODEL:-non spécifié}"
echo -e "  Taille     : ~${MODEL_SIZE_GB} Go"
echo -e "  Disponible : ${available_gb} Go"
echo -e "  Requis     : ${needed_gb} Go (modèle + marge ${RAM_MARGIN_GB} Go)"
echo -e "──────────────────────────────────────────"

if [[ $available_gb -lt $needed_gb ]]; then
    echo -e "${RED}✗ CHARGEMENT REFUSÉ${RESET}"
    echo -e "${RED}  RAM insuffisante : ${available_gb} Go disponibles, ${needed_gb} Go requis${RESET}"
    echo -e "${YELLOW}  Libérer de la RAM : ollama stop <modèle-actif>${RESET}"
    exit 1
else
    local_surplus=$(( available_gb - needed_gb ))
    echo -e "${GREEN}✓ RAM suffisante — ${local_surplus} Go de marge supplémentaire${RESET}"
    exit 0
fi
