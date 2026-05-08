# 06 — Usage quotidien

## Démarrage

```bash
# 1. Démarrer Ollama (si pas déjà en service)
ollama serve

# 2. Démarrer les interfaces Docker
cd docker && docker compose up -d

# 3. Ouvrir l'interface
open http://localhost:3000
```

---

## Commandes Ollama essentielles

```bash
# Lister les modèles installés
ollama list

# Voir les modèles actifs en mémoire
ollama ps

# Lancer un modèle en mode chat (terminal)
ollama run codestral:22b

# Lancer avec une question directe
ollama run phi4-reasoning "Explique le pattern Repository en PHP"

# Arrêter un modèle de la mémoire
ollama stop codestral:22b
```

---

## Workflow qwen3.6:27b (sandbox obligatoire)

```bash
# Vérifier que le container Kimi tourne
docker ps | grep ollama-sandbox

# Utiliser Kimi avec le filtre de sécurité
ollama run qwen3.6:27b "ta question" | ./scripts/sandbox-guard.sh
```

**Rappel** : Ne jamais envoyer à Kimi des secrets, tokens, code propriétaire ou chemins sensibles.

---

## Choisir le bon modèle

| Tâche | Modèle recommandé |
|-------|------------------|
| Écrire du code PHP/JS/Python/Java | `codestral:22b` |
| Refactoring multi-fichiers / Ansible | `devstral-small-2` |
| Architecture K8s / Revue OWASP / RedHat | `llama3.3:70b` |
| Scan rapide CI/CD / Scripts Linux | `phi4-reasoning` |
| Design patterns Java / SOLID / Architecture | `phi4-reasoning` |
| Agents ELK / Monitoring / Tool-calling | `gemma4:31b` |
| Optimisation Redis / Performance | `codestral:22b` ou `phi4-reasoning` |
| Coding non sensible (rapide) | `qwen3.6:27b` (sandbox) |
| Recherche dans documents / Logs ELK | `nomic-embed-text` + RAG |

---

## Gestion Docker

```bash
# Statut des containers
docker compose ps

# Logs en temps réel
docker compose logs -f

# Redémarrer un service
docker compose restart open-webui

# Arrêter tout
docker compose down

# Mettre à jour toutes les images
docker compose pull && docker compose up -d
```

---

## Arrêt propre

```bash
# Arrêter les interfaces
cd docker && docker compose down

# Arrêter Ollama
pkill ollama
```
