#!/usr/bin/env bash
# Monitoring sécurité + performance de la stack LLM
# Vérifie : ports exposés, containers, processus suspects, latence Ollama, charge CPU

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS="${GREEN}✓${RESET}"; WARN="${YELLOW}⚠${RESET}"; FAIL="${RED}✗${RESET}"

# ════════════════════════════════════════════════════════════
# SECTION SÉCURITÉ
# ════════════════════════════════════════════════════════════

check_ports() {
    echo -e "\n${BOLD}${CYAN}── Sécurité réseau ────────────────────────────────${RESET}"

    local ports=(11434 11435 3000 8888)
    local names=("Ollama" "Kimi sandbox" "Open WebUI" "SearXNG (si exposé)")

    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local name="${names[$i]}"
        local listeners
        listeners=$(lsof -iTCP:"$port" -sTCP:LISTEN -n 2>/dev/null || true)

        if [[ -z "$listeners" ]]; then
            echo -e "  Port $port ($name) : ${YELLOW}non actif${RESET}"
            continue
        fi

        # Vérifier que c'est bien lié à 127.0.0.1 et pas 0.0.0.0
        if echo "$listeners" | grep -q "0.0.0.0\|\*:$port"; then
            echo -e "  Port $port ($name) : ${FAIL} ${RED}EXPOSÉ SUR TOUTES LES INTERFACES — DANGER${RESET}"
        else
            echo -e "  Port $port ($name) : ${PASS} localhost uniquement"
        fi
    done
}

check_docker_security() {
    echo -e "\n${BOLD}${CYAN}── Sécurité Docker ────────────────────────────────${RESET}"

    # Containers avec privileges
    local privileged
    privileged=$(docker ps --quiet 2>/dev/null | xargs -I{} docker inspect {} --format '{{.Name}} privileged={{.HostConfig.Privileged}}' 2>/dev/null | grep "privileged=true" || true)
    if [[ -n "$privileged" ]]; then
        echo -e "  ${FAIL} Containers en mode privileged : ${RED}$privileged${RESET}"
    else
        echo -e "  ${PASS} Aucun container en mode privileged"
    fi

    # Kimi isolé sur son réseau
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ollama-kimi"; then
        local kimi_networks
        kimi_networks=$(docker inspect ollama-kimi --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
        if echo "$kimi_networks" | grep -q "kimi-sandbox"; then
            echo -e "  ${PASS} Kimi K2.6 isolé sur kimi-sandbox"
        else
            echo -e "  ${FAIL} ${RED}Kimi K2.6 pas sur kimi-sandbox !${RESET}"
        fi
    else
        echo -e "  ${WARN}  Kimi K2.6 non démarré"
    fi

    # Vérifier .env non exposé
    if git -C "$(dirname "$0")/.." status --short 2>/dev/null | grep -q "docker/.env"; then
        echo -e "  ${FAIL} ${RED}docker/.env présent dans git — RISQUE DE FUITE DE SECRETS${RESET}"
    else
        echo -e "  ${PASS} docker/.env non tracé par git"
    fi
}

check_suspicious_processes() {
    echo -e "\n${BOLD}${CYAN}── Processus suspects ─────────────────────────────${RESET}"

    # Processus Ollama en dehors des ports attendus
    local ollama_procs
    ollama_procs=$(pgrep -la ollama 2>/dev/null || true)
    if [[ -n "$ollama_procs" ]]; then
        echo -e "  ${PASS} Ollama actif :"
        echo "$ollama_procs" | while read -r line; do
            echo -e "       $line"
        done
    else
        echo -e "  ${WARN}  Ollama non démarré"
    fi

    # Connexions sortantes depuis les containers
    local outbound
    outbound=$(docker ps --quiet 2>/dev/null | xargs -I{} docker exec {} sh -c "ss -tn state established 2>/dev/null | grep -v '127\.' | head -5" 2>/dev/null || true)
    if [[ -n "$outbound" ]]; then
        echo -e "  ${WARN}  Connexions sortantes containers détectées :"
        echo "$outbound" | head -10
    else
        echo -e "  ${PASS} Aucune connexion externe suspecte depuis les containers"
    fi
}

# ════════════════════════════════════════════════════════════
# SECTION PERFORMANCE
# ════════════════════════════════════════════════════════════

check_cpu() {
    echo -e "\n${BOLD}${CYAN}── Performance CPU ────────────────────────────────${RESET}"

    local load
    load=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
    local cores
    cores=$(sysctl -n hw.logicalcpu)
    local load1
    load1=$(echo "$load" | awk '{print $1}')

    echo -e "  Load avg (1/5/15m) : $load"
    echo -e "  CPU logiques       : $cores cœurs"

    # Alerte si load > 80% des cœurs
    local threshold
    threshold=$(echo "$cores * 0.8" | bc 2>/dev/null || echo "$cores")
    if (( $(echo "$load1 > $threshold" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "  ${WARN}  Charge CPU élevée (>${threshold})"
    else
        echo -e "  ${PASS} Charge CPU normale"
    fi
}

check_ollama_latency() {
    echo -e "\n${BOLD}${CYAN}── Performance Ollama (latence API) ───────────────${RESET}"

    if ! pgrep -x ollama &>/dev/null; then
        echo -e "  ${WARN}  Ollama non démarré — test ignoré"
        return
    fi

    local start end latency
    start=$(date +%s%N)
    curl -s http://localhost:11434/api/tags -o /dev/null --max-time 3 2>/dev/null && {
        end=$(date +%s%N)
        latency=$(( (end - start) / 1000000 ))
        local color=$GREEN
        [[ $latency -gt 500 ]] && color=$YELLOW
        [[ $latency -gt 2000 ]] && color=$RED
        echo -e "  Réponse API        : ${color}${latency}ms${RESET}"
    } || echo -e "  ${FAIL} Ollama ne répond pas sur localhost:11434"

    # Kimi sandbox
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "ollama-kimi"; then
        start=$(date +%s%N)
        curl -s http://localhost:11435/api/tags -o /dev/null --max-time 3 2>/dev/null && {
            end=$(date +%s%N)
            latency=$(( (end - start) / 1000000 ))
            echo -e "  Réponse Kimi (11435): ${latency}ms"
        } || echo -e "  ${WARN}  Kimi sandbox ne répond pas"
    fi
}

check_docker_perf() {
    echo -e "\n${BOLD}${CYAN}── Performance Docker ─────────────────────────────${RESET}"

    if ! docker info &>/dev/null 2>&1; then
        echo -e "  ${WARN}  Docker non disponible"
        return
    fi

    docker stats --no-stream --format "  {{.Name}}\tCPU: {{.CPUPerc}}\tRAM: {{.MemUsage}}" 2>/dev/null \
        | grep -E "open-webui|searxng|ollama" \
        || echo -e "  Aucun container LLM actif"
}

check_disk() {
    echo -e "\n${BOLD}${CYAN}── Espace disque (modèles Ollama) ─────────────────${RESET}"

    local ollama_dir="$HOME/.ollama/models"
    if [[ -d "$ollama_dir" ]]; then
        local size
        size=$(du -sh "$ollama_dir" 2>/dev/null | awk '{print $1}')
        echo -e "  Modèles stockés    : $size ($ollama_dir)"
    fi

    local disk
    disk=$(df -h / | awk 'NR==2 {print "Utilisé: "$3" / "$2" ("$5" plein) — Libre: "$4}')
    echo -e "  Disque système     : $disk"

    # Alerte si < 20 Go libre
    local free_gb
    free_gb=$(df -g / | awk 'NR==2 {print $4}')
    if [[ $free_gb -lt 20 ]]; then
        echo -e "  ${FAIL} ${RED}Espace disque critique — moins de 20 Go libres${RESET}"
    else
        echo -e "  ${PASS} Espace disque OK (${free_gb} Go libres)"
    fi
}

# ════════════════════════════════════════════════════════════
# RAPPORT COMPLET
# ════════════════════════════════════════════════════════════

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║     Rapport Sécurité & Performance — LLM Stack       ║${RESET}"
    echo -e "${CYAN}║     $(date '+%Y-%m-%d %H:%M:%S')                          ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
}

# Mode watch
if [[ "${1:-}" == "--watch" ]]; then
    while true; do
        clear
        print_header
        check_ports
        check_docker_security
        check_suspicious_processes
        check_cpu
        check_ollama_latency
        check_docker_perf
        check_disk
        echo -e "\n${CYAN}Rafraîchissement toutes les 30s — Ctrl+C pour quitter${RESET}"
        sleep 30
    done
else
    print_header
    check_ports
    check_docker_security
    check_suspicious_processes
    check_cpu
    check_ollama_latency
    check_docker_perf
    check_disk
fi
