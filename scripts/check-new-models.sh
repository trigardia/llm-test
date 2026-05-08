#!/usr/bin/env bash
# Veille LLM — 3 recherches web Ollama Registry (2026)
# Détecte les nouveaux modèles pertinents pour le stack du projet

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# Modèles déjà retenus dans le projet (à comparer)
KNOWN_MODELS=(
    "codestral:22b"
    "devstral:24b"
    "llama3.3:70b"
    "llama3.1:8b"
    "phi4:14b"
    "gemma3:27b"
    "kimi-k2.6"
    "nomic-embed-text"
)

# Tags de pertinence pour ce projet
RELEVANT_TAGS=(
    "code" "coding" "instruct" "security" "pentest" "embed"
    "java" "php" "python" "devops" "agent" "tool"
)

OLLAMA_REGISTRY="https://ollama.com"
TODAY=$(date '+%Y-%m-%d')

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║   Veille Modèles LLM — Ollama Registry — ${TODAY}    ║${RESET}"
    echo -e "${CYAN}║   3 recherches web automatiques                          ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
}

# ── Recherche 1 : Modèles les plus récents ──────────────────
search_newest() {
    echo -e "\n${BOLD}${CYAN}[1/3] Derniers modèles publiés sur Ollama Registry${RESET}"
    echo -e "      Source : ${OLLAMA_REGISTRY}/library\n"

    local response
    response=$(curl -sf --max-time 15 \
        -H "Accept: application/json" \
        "${OLLAMA_REGISTRY}/api/models?sort=newest&limit=20" 2>/dev/null) || {
        echo -e "  ${YELLOW}⚠  API JSON indisponible — tentative HTML...${RESET}"
        response=$(curl -sf --max-time 15 \
            -A "Mozilla/5.0" \
            "${OLLAMA_REGISTRY}/search?q=&sort=newest" 2>/dev/null) || {
            echo -e "  ${RED}✗ Recherche 1 échouée (réseau ou registry indisponible)${RESET}"
            return
        }
        # Parse HTML basique
        echo "$response" | grep -oP '(?<=href="/library/)[^"]+' | sort -u | head -15 | while read -r model; do
            echo -e "  ${GREEN}→${RESET} $model"
        done
        return
    }

    if command -v jq &>/dev/null; then
        echo "$response" | jq -r '.models[]? | "  \(.name) — \(.description // "N/A") (\(.pulls // "?") pulls)"' 2>/dev/null | head -15
    else
        echo "$response" | grep -oP '"name":"[^"]+"' | sed 's/"name":"//;s/"//' | head -15 | while read -r m; do
            echo -e "  ${GREEN}→${RESET} $m"
        done
    fi
}

# ── Recherche 2 : Modèles coding + sécurité (contexte projet) ─
search_by_context() {
    echo -e "\n${BOLD}${CYAN}[2/3] Modèles pertinents : coding · sécurité · devops${RESET}"
    echo -e "      Source : ${OLLAMA_REGISTRY}/search (filtres contextuels)\n"

    local queries=("code" "security" "devops")
    for query in "${queries[@]}"; do
        echo -e "  ${BOLD}Filtre : $query${RESET}"
        local res
        res=$(curl -sf --max-time 15 \
            -A "Mozilla/5.0" \
            "${OLLAMA_REGISTRY}/search?q=${query}&sort=popular" 2>/dev/null) || {
            echo -e "    ${RED}✗ Requête '$query' échouée${RESET}"
            continue
        }
        echo "$res" | grep -oP '(?<=href="/library/)[^"]+' 2>/dev/null | sort -u | head -5 | while read -r model; do
            # Marquer si déjà connu
            local known=false
            for k in "${KNOWN_MODELS[@]}"; do
                [[ "$k" == "$model"* ]] && known=true && break
            done
            if [[ $known == true ]]; then
                echo -e "    ${GREEN}✓${RESET} $model ${YELLOW}(déjà dans le stack)${RESET}"
            else
                echo -e "    ${CYAN}★${RESET} $model ${GREEN}← nouveau candidat${RESET}"
            fi
        done
        echo ""
    done
}

# ── Recherche 3 : Releases récentes GitHub Ollama ──────────
search_github_releases() {
    echo -e "\n${BOLD}${CYAN}[3/3] Releases Ollama et nouveaux modèles — GitHub${RESET}"
    echo -e "      Source : api.github.com/repos/ollama/ollama\n"

    local response
    response=$(curl -sf --max-time 15 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/ollama/ollama/releases?per_page=5" 2>/dev/null) || {
        echo -e "  ${RED}✗ Recherche GitHub échouée${RESET}"
        return
    }

    if command -v jq &>/dev/null; then
        echo "$response" | jq -r '.[] | "  \(.tag_name) — \(.published_at[:10]) — \(.name)"' 2>/dev/null | head -5
    else
        echo "$response" | grep -oP '"tag_name":"[^"]+"' | sed 's/"tag_name":"//;s/"//' | head -5 | while read -r tag; do
            echo -e "  ${GREEN}→${RESET} $tag"
        done
    fi

    # Bonus : vérifier la dernière version d'Ollama installée vs disponible
    echo ""
    local latest_tag
    latest_tag=$(curl -sf --max-time 10 \
        "https://api.github.com/repos/ollama/ollama/releases/latest" 2>/dev/null \
        | grep -oP '"tag_name":"[^"]+"' | sed 's/"tag_name":"//;s/"//' || echo "N/A")

    local installed_version
    installed_version=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "N/A")

    echo -e "  Version Ollama installée : ${BOLD}${installed_version}${RESET}"
    echo -e "  Dernière version dispo   : ${BOLD}${latest_tag}${RESET}"

    if [[ "$installed_version" != "N/A" && "$latest_tag" != "N/A" ]]; then
        if [[ "$installed_version" == "$latest_tag" || "v${installed_version}" == "$latest_tag" ]]; then
            echo -e "  ${GREEN}✓ Ollama à jour${RESET}"
        else
            echo -e "  ${YELLOW}⚠  Mise à jour disponible : brew upgrade ollama${RESET}"
        fi
    fi
}

# ── Comparaison avec le stack actuel ───────────────────────
compare_installed() {
    echo -e "\n${BOLD}${CYAN}── Modèles installés vs stack cible ───────────────────${RESET}"

    if ! pgrep -x ollama &>/dev/null; then
        echo -e "  ${YELLOW}⚠  Ollama non démarré — démarrer avec : ollama serve${RESET}"
        return
    fi

    local installed
    installed=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

    for model in "${KNOWN_MODELS[@]}"; do
        if echo "$installed" | grep -q "^${model%%:*}"; then
            echo -e "  ${GREEN}✓${RESET} $model installé"
        else
            echo -e "  ${RED}✗${RESET} $model ${YELLOW}← manquant (make models)${RESET}"
        fi
    done
}

# ── Main ───────────────────────────────────────────────────
print_header
search_newest
search_by_context
search_github_releases
compare_installed

echo -e "\n${CYAN}──────────────────────────────────────────────────────────${RESET}"
echo -e "${BOLD}Pour installer un nouveau modèle candidat :${RESET}"
echo -e "  ollama pull <nom-du-modèle>"
echo -e "  make check-ram MODEL=<nom> SIZE=<taille-go>"
echo -e "${CYAN}──────────────────────────────────────────────────────────${RESET}\n"
