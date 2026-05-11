# 02 — Installation

## Prérequis

- macOS (Apple Silicon M1/M2/M3/M4/M5)
- [Homebrew](https://brew.sh) installé
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installé et démarré
- Minimum 16 Go RAM (128 Go recommandé pour les gros modèles)

---

## Étape 1 — Installer Ollama (natif macOS)

```bash
brew install ollama
```

Démarrer le service Ollama :

```bash
ollama serve
```

> Ollama tourne en arrière-plan sur le port **11434**. Il doit être démarré avant les interfaces Docker.

Vérifier l'installation :

```bash
ollama --version
ollama list
```

---

## Étape 2 — Cloner le projet

```bash
git clone <url-du-repo> LLM
cd LLM
```

---

## Étape 3 — Configurer les variables d'environnement

```bash
cd docker
cp .env.example .env   # si le fichier exemple existe
```

Les clés secrètes sont déjà générées dans `.env`. Ne pas les modifier sauf si nécessaire.

> **Important** : `.env` ne doit jamais être commité (protégé par `.gitignore`).

---

## Étape 4 — Démarrer les interfaces Docker

```bash
cd docker
docker compose up -d
```

Vérifier que tout tourne :

```bash
docker compose ps
docker compose logs -f
```

---

## Étape 5 — Accéder à Open WebUI

Ouvrir http://localhost:3000 dans le navigateur.

Au premier lancement :
1. Créer un compte administrateur
2. L'inscription publique est désactivée (`ENABLE_SIGNUP=false`)
3. Aller dans **Paramètres → Web Search** pour vérifier la connexion SearXNG

---

## Étape 6 — Télécharger les modèles

Voir [03-modeles.md](03-modeles.md) pour l'ordre recommandé et les commandes.

---

## Étape 7 — Sandbox qwen3.6:27b (optionnel)

```bash
# Créer le réseau isolé
docker network create --driver bridge --internal sandbox-net

# Démarrer le container sandbox qwen3.6:27b
docker run -d --name ollama-sandbox --network sandbox-net \
  --cap-drop ALL --read-only \
  --tmpfs /tmp:size=512m --tmpfs /root/.ollama:size=100g \
  -v $(pwd):/workspace:ro \
  --memory="90g" --cpus="16" \
  -p 127.0.0.1:11435:11434 ollama/ollama

# Rendre le guard exécutable
chmod +x scripts/sandbox-guard.sh
```

---

## Commandes utiles

```bash
# Démarrer tout
ollama serve & cd docker && docker compose up -d

# Arrêter tout
docker compose down

# Mettre à jour les images
docker compose pull && docker compose up -d

# Voir les logs en temps réel
docker compose logs -f open-webui
docker compose logs -f searxng
```
