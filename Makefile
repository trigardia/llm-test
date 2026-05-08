.PHONY: help start stop restart status logs logs-webui logs-search update \
        models models-light models-all clean \
        load unload switch \
        sandbox-setup sandbox-stop sandbox-status \
        test test-model monitor monitor-live security security-live \
        check-ram models-list models-check-new ollama-check stop-all

DOCKER_DIR := docker
SCRIPTS_DIR := scripts

# Couleurs
CYAN  := \033[0;36m
GREEN := \033[0;32m
RED   := \033[0;31m
RESET := \033[0m

##@ Aide
help: ## Afficher cette aide
	@awk 'BEGIN {FS = ":.*##"; printf "\n$(CYAN)Stack LLM Local$(RESET)\n\nUsage:\n  make $(CYAN)<cible>$(RESET)\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-20s$(RESET) %s\n", $$1, $$2 } \
	/^##@/ { printf "\n$(GREEN)%s$(RESET)\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Stack principale
start: ## Démarrer Ollama + interfaces Docker
	@echo "$(CYAN)Démarrage d'Ollama...$(RESET)"
	@pgrep -x ollama > /dev/null 2>&1 || (ollama serve &>/dev/null & sleep 3)
	@ollama list &>/dev/null || (echo "$(RED)✗ Ollama ne répond pas — relancer : ollama serve$(RESET)" && exit 1)
	@echo "$(CYAN)Démarrage des interfaces Docker...$(RESET)"
	@cd $(DOCKER_DIR) && docker compose up -d
	@echo "$(GREEN)✓ Stack démarrée — http://localhost:3000$(RESET)"

ollama-check: ## Vérifier qu'Ollama est démarré (et le démarrer si besoin)
	@pgrep -x ollama > /dev/null 2>&1 \
		&& echo "$(GREEN)✓ Ollama actif$(RESET)" \
		|| (echo "$(YELLOW)Ollama non démarré — démarrage...$(RESET)" && ollama serve &>/dev/null & sleep 3 && echo "$(GREEN)✓ Ollama démarré$(RESET)")

stop: ## Arrêter les interfaces Docker (Ollama continue en arrière-plan)
	@echo "$(CYAN)Arrêt des interfaces Docker...$(RESET)"
	@cd $(DOCKER_DIR) && docker compose down
	@echo "$(GREEN)✓ Interfaces arrêtées$(RESET)"

stop-all: ## Arrêter tout (Docker + Ollama)
	@echo "$(CYAN)Arrêt complet...$(RESET)"
	@cd $(DOCKER_DIR) && docker compose down
	@pkill ollama 2>/dev/null && echo "$(GREEN)✓ Ollama arrêté$(RESET)" || echo "Ollama déjà arrêté"
	@echo "$(GREEN)✓ Stack complètement arrêtée$(RESET)"

restart: ## Redémarrer les interfaces Docker
	@echo "$(CYAN)Redémarrage...$(RESET)"
	@cd $(DOCKER_DIR) && docker compose restart
	@echo "$(GREEN)✓ Redémarré$(RESET)"

status: ## Statut complet — Ollama + modèles + Docker
	@echo "\n$(CYAN)── Ollama ──────────────────────────────$(RESET)"
	@pgrep -x ollama > /dev/null 2>&1 && echo "$(GREEN)✓ Ollama actif$(RESET)" || echo "$(RED)✗ Ollama non démarré — make ollama-check$(RESET)"
	@echo "\n$(CYAN)── Modèles en mémoire (RAM) ────────────$(RESET)"
	@ollama ps 2>/dev/null || echo "  $(YELLOW)Aucun modèle chargé$(RESET)"
	@echo "\n$(CYAN)── Modèles installés (disque) ──────────$(RESET)"
	@ollama list 2>/dev/null | awk 'NR==1 {printf "  %-35s %-15s %-10s %s\n", $$1, $$3" "$$4, $$5, $$6} NR>1 {printf "  %-35s %-15s %-10s %s\n", $$1, $$3" "$$4, $$5, $$6}' || echo "  $(RED)Ollama non démarré$(RESET)"
	@echo "\n$(CYAN)── Interfaces Docker ───────────────────$(RESET)"
	@cd $(DOCKER_DIR) && docker compose ps 2>/dev/null || echo "  $(YELLOW)Docker non démarré$(RESET)"

models-list: ## Liste détaillée des modèles : nom · taille disque · RAM · statut
	@echo "\n$(CYAN)╔══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║              Modèles Ollama — Vue complète                   ║$(RESET)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(RESET)"
	@pgrep -x ollama > /dev/null 2>&1 || (echo "$(RED)✗ Ollama non démarré — lancez : make ollama-check$(RESET)" && exit 1)
	@echo "\n$(BOLD)Installés sur disque :$(RESET)"
	@ollama list 2>/dev/null | awk 'NR==1 {next} {printf "  %-30s %8s\n", $$1, $$3" "$$4}' | sort
	@echo "\n$(BOLD)Chargés en RAM :$(RESET)"
	@loaded=$$(ollama ps 2>/dev/null | tail -n +2 | grep -v "^$$"); \
	  if [ -z "$$loaded" ]; then \
	    echo "  $(YELLOW)Aucun modèle en mémoire$(RESET)"; \
	  else \
	    echo "$$loaded" | awk '{printf "  $(GREEN)●$(RESET)  %-30s %8s    RAM: %s\n", $$1, $$3" "$$4, $$5" "$$6}'; \
	  fi
	@echo "\n$(BOLD)Espace disque modèles :$(RESET)"
	@du -sh ~/.ollama/models 2>/dev/null | awk '{printf "  Total occupé : %s\n", $$1}'
	@df -h / | awk 'NR==2 {printf "  Disque libre : %s sur %s\n", $$4, $$2}'
	@echo ""

##@ Logs
logs: ## Logs de tous les containers (live)
	@cd $(DOCKER_DIR) && docker compose logs -f

logs-webui: ## Logs Open WebUI uniquement
	@cd $(DOCKER_DIR) && docker compose logs -f open-webui

logs-search: ## Logs SearXNG uniquement
	@cd $(DOCKER_DIR) && docker compose logs -f searxng

##@ Modèles
models-light: ## Télécharger les modèles légers (rapide, ~18 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-light" 18
	@echo "$(CYAN)Téléchargement des modèles légers...$(RESET)"
	ollama pull nomic-embed-text
	ollama pull llama3.1:8b
	@echo "$(GREEN)✓ Modèles légers installés$(RESET)"

models: ## Télécharger les modèles standards (~60 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-standard" 60
	@echo "$(CYAN)Téléchargement des modèles standards...$(RESET)"
	ollama pull nomic-embed-text
	ollama pull llama3.1:8b
	ollama pull codestral:22b
	ollama pull phi4:14b
	ollama pull gemma3:27b
	ollama pull devstral:24b
	@echo "$(GREEN)✓ Modèles standards installés$(RESET)"

models-all: ## Télécharger TOUS les modèles (~103 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-all" 103
	@echo "$(CYAN)Téléchargement de tous les modèles (long)...$(RESET)"
	ollama pull nomic-embed-text
	ollama pull llama3.1:8b
	ollama pull codestral:22b
	ollama pull phi4:14b
	ollama pull gemma3:27b
	ollama pull devstral:24b
	ollama pull llama3.3:70b
	@echo "$(GREEN)✓ Tous les modèles installés$(RESET)"

##@ Sandbox qwen2.5-coder:32b (modèle chinois isolé)
sandbox-setup: ## Créer le sandbox Docker et télécharger qwen2.5-coder:32b
	@echo "$(CYAN)Création du réseau sandbox isolé inter-containers...$(RESET)"
	@docker network create --driver bridge --internal sandbox-net 2>/dev/null || echo "  Réseau sandbox-net déjà existant"
	@docker volume create qwen-models 2>/dev/null || echo "  Volume qwen-models déjà existant"
	@echo "$(CYAN)Démarrage du container sandbox...$(RESET)"
	@docker rm -f ollama-sandbox 2>/dev/null || true
	docker run -d --name ollama-sandbox \
		--network sandbox-net \
		--cap-drop ALL --read-only \
		--tmpfs /tmp:size=512m \
		-v qwen-models:/root/.ollama \
		-v $$(pwd):/workspace:ro \
		--memory="25g" --cpus="12" \
		-p 127.0.0.1:11435:11434 ollama/ollama
	@echo "$(CYAN)Attente démarrage Ollama dans le container...$(RESET)"
	@sleep 8
	@echo "$(CYAN)Connexion temporaire internet pour le téléchargement...$(RESET)"
	@docker network connect bridge ollama-sandbox
	@echo "$(CYAN)Téléchargement de qwen2.5-coder:32b...$(RESET)"
	OLLAMA_HOST=127.0.0.1:11435 ollama pull qwen2.5-coder:32b
	@echo "$(CYAN)Isolation inter-containers — déconnexion bridge...$(RESET)"
	@docker network disconnect bridge ollama-sandbox
	@chmod +x $(SCRIPTS_DIR)/sandbox-guard.sh
	@echo "$(GREEN)✓ Sandbox prêt — qwen2.5-coder:32b sur port 11435$(RESET)"
	@echo "$(YELLOW)  Note : port mapping actif via sandbox-net (isolation inter-containers garantie)$(RESET)"

sandbox-stop: ## Arrêter le sandbox
	@docker stop ollama-sandbox 2>/dev/null && docker rm ollama-sandbox 2>/dev/null || true
	@echo "$(GREEN)✓ Sandbox arrêté$(RESET)"

sandbox-status: ## Statut et isolation du sandbox
	@echo "\n$(CYAN)── Container sandbox ─────────────────────────$(RESET)"
	@docker ps --filter name=ollama-sandbox --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Non démarré"
	@echo "\n$(CYAN)── Réseaux connectés ─────────────────────────$(RESET)"
	@docker inspect ollama-sandbox --format '{{range $$k,$$v := .NetworkSettings.Networks}}  ● {{$$k}}\n{{end}}' 2>/dev/null || true
	@echo "\n$(CYAN)── Modèles dans le sandbox ───────────────────$(RESET)"
	@OLLAMA_HOST=127.0.0.1:11435 ollama list 2>/dev/null || echo "  Sandbox non accessible"

##@ Gestion RAM — chargement à la demande
load: ## Charger un modèle en RAM (usage: make load MODEL=gemma4:31b)
	@[ -n "$(MODEL)" ] || (echo "$(RED)Usage : make load MODEL=<nom>$(RESET)" && exit 1)
	@bash $(SCRIPTS_DIR)/load-model.sh "$(MODEL)"

switch: ## Changer de modèle — décharge l'actuel, charge le nouveau (usage: make switch MODEL=llama3.3:70b)
	@[ -n "$(MODEL)" ] || (echo "$(RED)Usage : make switch MODEL=<nom>$(RESET)" && exit 1)
	@bash $(SCRIPTS_DIR)/load-model.sh "$(MODEL)"

unload: ## Décharger tous les modèles de la RAM (libère la mémoire)
	@bash $(SCRIPTS_DIR)/load-model.sh --unload

##@ Tests
test: ## Tester tous les modèles un par un (Kimi exclu) — rapport généré dans tests/results/
	@bash $(SCRIPTS_DIR)/test-models.sh

test-model: ## Tester un seul modèle (usage: make test-model MODEL=codestral:22b)
	@bash $(SCRIPTS_DIR)/test-models.sh "$(MODEL)"

##@ Veille LLM
models-check-new: ## 3 recherches web — derniers modèles dispo (Ollama registry + GitHub)
	@bash $(SCRIPTS_DIR)/check-new-models.sh

##@ Monitoring
monitor: ## Snapshot RAM + température + modèles actifs
	@bash $(SCRIPTS_DIR)/monitor.sh

monitor-live: ## Monitoring en temps réel (rafraîchissement 5s)
	@bash $(SCRIPTS_DIR)/monitor.sh --watch

security: ## Rapport sécurité + performance (snapshot)
	@bash $(SCRIPTS_DIR)/security-perf-monitor.sh

security-live: ## Rapport sécurité + performance en continu (30s)
	@bash $(SCRIPTS_DIR)/security-perf-monitor.sh --watch

check-ram: ## Vérifier la RAM avant de charger un modèle (usage: make check-ram MODEL=codestral:22b SIZE=14)
	@bash $(SCRIPTS_DIR)/check-resources.sh "$(MODEL)" "$(SIZE)"

##@ Maintenance
update: ## Mettre à jour toutes les images Docker
	@echo "$(CYAN)Mise à jour des images...$(RESET)"
	@cd $(DOCKER_DIR) && docker compose pull
	@cd $(DOCKER_DIR) && docker compose up -d
	@echo "$(GREEN)✓ Images mises à jour$(RESET)"

clean: ## Supprimer les volumes Docker (⚠ perte des données)
	@echo "$(RED)⚠ Cette action supprime les données Open WebUI$(RESET)"
	@read -p "Confirmer ? (oui/non): " confirm && [ "$$confirm" = "oui" ] || exit 1
	@cd $(DOCKER_DIR) && docker compose down -v
	@echo "$(GREEN)✓ Volumes supprimés$(RESET)"
