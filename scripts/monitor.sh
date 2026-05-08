#!/usr/bin/env bash
# Monitoring temps réel : RAM · Température · Ventilateurs · Modèles actifs

set -euo pipefail

# ── Couleurs ────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

RAM_MARGIN_GB=20   # Marge minimale obligatoire en Go

# ── Fonctions ───────────────────────────────────────────────

get_ram_stats() {
    local page_size
    page_size=$(sysctl -n hw.pagesize)
    local total_bytes
    total_bytes=$(sysctl -n hw.memsize)

    local vm
    vm=$(vm_stat)

    local free inactive speculative
    free=$(echo "$vm"       | awk '/Pages free/        {gsub(/\./,"",$3); print $3}')
    inactive=$(echo "$vm"   | awk '/Pages inactive/    {gsub(/\./,"",$3); print $3}')
    speculative=$(echo "$vm"| awk '/Pages speculative/ {gsub(/\./,"",$3); print $3}')

    local available_bytes used_bytes total_gb available_gb used_gb
    available_bytes=$(( (free + inactive + speculative) * page_size ))
    used_bytes=$(( total_bytes - available_bytes ))

    total_gb=$(( total_bytes / 1024 / 1024 / 1024 ))
    available_gb=$(( available_bytes / 1024 / 1024 / 1024 ))
    used_gb=$(( used_bytes / 1024 / 1024 / 1024 ))

    echo "$total_gb $used_gb $available_gb"
}

print_ram() {
    read -r total used available <<< "$(get_ram_stats)"
    local pct=$(( used * 100 / total ))
    local margin_ok=true
    [[ $available -lt $RAM_MARGIN_GB ]] && margin_ok=false

    local color=$GREEN
    [[ $pct -gt 60 ]] && color=$YELLOW
    [[ $pct -gt 80 ]] && color=$RED
    [[ $margin_ok == false ]] && color=$RED

    echo -e "${BOLD}RAM${RESET}"
    echo -e "  Total      : ${total} Go"
    echo -e "  Utilisée   : ${color}${used} Go (${pct}%)${RESET}"
    echo -e "  Disponible : ${color}${available} Go${RESET}"

    if [[ $margin_ok == false ]]; then
        echo -e "  ${RED}⚠  MARGE CRITIQUE — moins de ${RAM_MARGIN_GB} Go libres !${RESET}"
        echo -e "  ${RED}   Arrêter des modèles : ollama stop <modèle>${RESET}"
    else
        local surplus=$(( available - RAM_MARGIN_GB ))
        echo -e "  ${GREEN}✓  Marge OK (+${surplus} Go au-dessus du seuil de ${RAM_MARGIN_GB} Go)${RESET}"
    fi
}

print_temperature() {
    echo -e "\n${BOLD}Température & Ventilateurs${RESET}"
    if command -v sudo &>/dev/null; then
        local data
        data=$(sudo powermetrics --samplers smc -n 1 -i 500 2>/dev/null) || {
            echo "  (sudo requis pour la température — lancez : sudo make monitor)"
            return
        }

        # CPU die temperature
        local cpu_temp
        cpu_temp=$(echo "$data" | grep -i "CPU die temperature" | awk '{print $NF}' | head -1)
        if [[ -n "$cpu_temp" ]]; then
            local temp_int=${cpu_temp%.*}
            local color=$GREEN
            [[ $temp_int -gt 70 ]] && color=$YELLOW
            [[ $temp_int -gt 85 ]] && color=$RED
            echo -e "  CPU Die    : ${color}${cpu_temp}°C${RESET}"
        fi

        # GPU temperature
        local gpu_temp
        gpu_temp=$(echo "$data" | grep -i "GPU die temperature" | awk '{print $NF}' | head -1)
        [[ -n "$gpu_temp" ]] && echo -e "  GPU Die    : ${gpu_temp}°C"

        # Fan speed
        local fan
        fan=$(echo "$data" | grep -i "Fan" | grep -i "speed\|rpm" | awk '{print $(NF-1), $NF}' | head -1)
        [[ -n "$fan" ]] && echo -e "  Ventilateur: ${fan}"
    else
        echo "  (powermetrics non disponible)"
    fi
}

print_ollama() {
    echo -e "\n${BOLD}Modèles Ollama actifs${RESET}"
    if pgrep -x ollama &>/dev/null; then
        local ps_out
        ps_out=$(ollama ps 2>/dev/null)
        if echo "$ps_out" | grep -q "NAME"; then
            echo "$ps_out" | tail -n +2 | while read -r line; do
                [[ -z "$line" ]] && continue
                echo -e "  ${GREEN}●${RESET} $line"
            done
        else
            echo -e "  ${YELLOW}Aucun modèle chargé en mémoire${RESET}"
        fi
    else
        echo -e "  ${RED}Ollama non démarré${RESET}"
    fi
}

print_docker() {
    echo -e "\n${BOLD}Docker${RESET}"
    if docker compose -f docker/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | grep -v "^$"; then
        :
    else
        echo -e "  ${YELLOW}Interfaces non démarrées${RESET}"
    fi
}

# ── Mode live (watch) ────────────────────────────────────────
if [[ "${1:-}" == "--watch" ]]; then
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}║      LLM Stack Monitor — $(date '+%H:%M:%S')          ║${RESET}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${RESET}"
        print_ram
        print_temperature
        print_ollama
        print_docker
        echo -e "\n${CYAN}Rafraîchissement toutes les 5s — Ctrl+C pour quitter${RESET}"
        sleep 5
    done
else
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║           LLM Stack Monitor                 ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${RESET}"
    print_ram
    print_temperature
    print_ollama
    print_docker
fi
