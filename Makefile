.PHONY: help start stop restart status logs logs-webui logs-search update \
        models models-light models-all qwen-pull clean \
        load unload switch \
        test test-model test-full test-full-model monitor monitor-live security security-live \
        check-ram models-list models-check-new ollama-check stop-all \
        php-up php-down php-run php-test php-lint php-shell

DOCKER_DIR := docker
PHP_TEST_DIR := docker/php-test
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
		|| (echo "$(CYAN)Ollama non démarré — démarrage...$(RESET)" && ollama serve &>/dev/null & sleep 3 && echo "$(GREEN)✓ Ollama démarré$(RESET)")

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
	@ollama ps 2>/dev/null || echo "  Aucun modèle chargé"
	@echo "\n$(CYAN)── Modèles installés (disque) ──────────$(RESET)"
	@ollama list 2>/dev/null | awk 'NR==1 {printf "  %-35s %-15s %-10s %s\n", $$1, $$3" "$$4, $$5, $$6} NR>1 {printf "  %-35s %-15s %-10s %s\n", $$1, $$3" "$$4, $$5, $$6}' || echo "  $(RED)Ollama non démarré$(RESET)"
	@echo "\n$(CYAN)── Interfaces Docker ───────────────────$(RESET)"
	@cd $(DOCKER_DIR) && docker compose ps 2>/dev/null || echo "  Docker non démarré"

models-list: ## Liste détaillée des modèles : nom · taille disque · RAM · statut
	@echo "\n$(CYAN)╔══════════════════════════════════════════════════════════════╗$(RESET)"
	@echo "$(CYAN)║              Modèles Ollama — Vue complète                   ║$(RESET)"
	@echo "$(CYAN)╚══════════════════════════════════════════════════════════════╝$(RESET)"
	@pgrep -x ollama > /dev/null 2>&1 || (echo "$(RED)✗ Ollama non démarré — lancez : make ollama-check$(RESET)" && exit 1)
	@echo "\nInstallés sur disque :"
	@ollama list 2>/dev/null | awk 'NR==1 {next} {printf "  %-30s %8s\n", $$1, $$3" "$$4}' | sort
	@echo "\nChargés en RAM :"
	@loaded=$$(ollama ps 2>/dev/null | tail -n +2 | grep -v "^$$"); \
	  if [ -z "$$loaded" ]; then \
	    echo "  Aucun modèle en mémoire"; \
	  else \
	    echo "$$loaded" | awk '{printf "  $(GREEN)●$(RESET)  %-30s %8s    RAM: %s\n", $$1, $$3" "$$4, $$5" "$$6}'; \
	  fi
	@echo "\nEspace disque modèles :"
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
models-light: ## Télécharger les modèles légers (~10 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-light" 10
	@echo "$(CYAN)Téléchargement des modèles légers...$(RESET)"
	ollama pull nomic-embed-text-v2-moe
	ollama pull phi4-reasoning:plus
	@echo "$(GREEN)✓ Modèles légers installés$(RESET)"

models: ## Télécharger les modèles standards (~70 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-standard" 70
	@echo "$(CYAN)Téléchargement des modèles standards...$(RESET)"
	ollama pull nomic-embed-text-v2-moe
	ollama pull phi4-reasoning:plus
	ollama pull codestral:22b
	ollama pull gemma4:31b
	ollama pull devstral-small-2
	@echo "$(GREEN)✓ Modèles standards installés$(RESET)"

models-all: ## Télécharger TOUS les modèles (~160 GB)
	@echo "$(CYAN)Vérification RAM...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "pack-all" 160
	@echo "$(CYAN)Téléchargement de tous les modèles (long)...$(RESET)"
	ollama pull nomic-embed-text-v2-moe
	ollama pull phi4-reasoning:plus
	ollama pull codestral:22b
	ollama pull gemma4:31b
	ollama pull devstral-small-2
	ollama pull llama3.3:70b
	ollama pull qwen3.6:27b
	@echo "$(GREEN)✓ Tous les modèles installés$(RESET)"

qwen-pull: ## Télécharger qwen3.6:27b (⚠ modèle Alibaba — sortie via sandbox-guard.sh)
	@echo "$(CYAN)Téléchargement de qwen3.6:27b...$(RESET)"
	@bash $(SCRIPTS_DIR)/check-resources.sh "qwen3.6:27b" 24
	ollama pull qwen3.6:27b
	@chmod +x $(SCRIPTS_DIR)/sandbox-guard.sh
	@echo "$(GREEN)✓ qwen3.6:27b installé$(RESET)"
	@echo "$(RED)⚠ Usage obligatoire : ollama run qwen3.6:27b \"prompt\" | ./scripts/sandbox-guard.sh$(RESET)"

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
test: ## Tester tous les modèles — prompts rapides ciblés — rapport dans tests/results/
	@bash $(SCRIPTS_DIR)/test-models.sh

test-model: ## Tester un seul modèle (usage: make test-model MODEL=codestral:22b)
	@bash $(SCRIPTS_DIR)/test-models.sh "$(MODEL)"

test-full: ## Benchmark ultime 6 behaviors — tous les modèles (long — 20-40 min)
	@MODEL_MODE=full bash $(SCRIPTS_DIR)/test-models.sh

test-full-model: ## Benchmark ultime sur un seul modèle (usage: make test-full-model MODEL=gemma4:31b)
	@[ -n "$(MODEL)" ] || (echo "$(RED)Usage : make test-full-model MODEL=<nom>$(RESET)" && exit 1)
	@MODEL_MODE=full bash $(SCRIPTS_DIR)/test-models.sh "$(MODEL)"

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

##@ Validation code PHP (Docker isolé — PHP 8.3 + PostgreSQL 16 + Redis 7 + RabbitMQ)
php-up: ## Démarrer l'env PHP de test (PostgreSQL + Redis + RabbitMQ)
	@echo "$(CYAN)Démarrage env PHP test...$(RESET)"
	@cd $(PHP_TEST_DIR) && docker compose up -d --build
	@echo "$(GREEN)✓ Env PHP prêt — code dans tests/generated/$(RESET)"
	@echo "  PostgreSQL : localhost:5433  |  Redis : localhost:6380  |  RabbitMQ : localhost:15673"

php-down: ## Arrêter l'env PHP de test
	@cd $(PHP_TEST_DIR) && docker compose down
	@echo "$(GREEN)✓ Env PHP arrêté$(RESET)"

php-shell: ## Shell interactif dans le container PHP (pour déboguer)
	@cd $(PHP_TEST_DIR) && docker compose run --rm php-test bash

php-lint: ## Vérifier la syntaxe PHP de tout le code généré
	@echo "$(CYAN)Lint PHP 8.3 sur tests/generated/...$(RESET)"
	@cd $(PHP_TEST_DIR) && docker compose run --rm php-test \
		bash -c "find /app/src -name '*.php' -exec php -l {} \; 2>&1 | grep -v 'No syntax errors' || echo 'Syntaxe OK'"

php-test: ## Lancer PHPUnit dans le container (usage: make php-test ou make php-test ARGS="--filter MoneyTest")
	@echo "$(CYAN)PHPUnit dans Docker PHP 8.3...$(RESET)"
	@cd $(PHP_TEST_DIR) && docker compose run --rm php-test \
		bash -c "cd /app && composer install -q && vendor/bin/phpunit $(ARGS) --colors=never"

php-run: ## Commande arbitraire dans PHP (usage: make php-run CMD="php bin/console debug:router")
	@[ -n "$(CMD)" ] || (echo "$(RED)Usage : make php-run CMD='...'$(RESET)" && exit 1)
	@cd $(PHP_TEST_DIR) && docker compose run --rm php-test bash -c "$(CMD)"

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
