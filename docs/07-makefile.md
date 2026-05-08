# 07 — Makefile

## Usage

```bash
make <cible>
make help   # afficher toutes les commandes disponibles
```

---

## Stack principale

### `make start`
Démarre Ollama (natif macOS) puis les interfaces Docker (Open WebUI + SearXNG). Vérifie automatiquement qu'Ollama répond avant de démarrer Docker — affiche une erreur claire si Ollama ne se lance pas.

```bash
make start
# → Ollama sur port 11434
# → Open WebUI sur http://localhost:3000
```

### `make ollama-check`
Vérifie qu'Ollama est démarré. S'il ne l'est pas, le démarre automatiquement.

```bash
make ollama-check
# ✓ Ollama actif           (si déjà lancé)
# Ollama non démarré — démarrage...   (le démarre)
```

> **Erreur fréquente** : `could not connect to ollama server` → lancer `make ollama-check` ou `ollama serve`.

### `make stop`
Arrête les containers Docker. **Ollama reste actif** en arrière-plan (les modèles restent en mémoire).

### `make stop-all`
Arrête tout — Docker **et** Ollama. La RAM est entièrement libérée.

### `make restart`
Redémarre uniquement les interfaces Docker (utile après une mise à jour de config).

### `make status`
Affiche l'état complet de tous les services :
- Statut Ollama (actif / non démarré)
- Modèles **en RAM** (chargés, consomment de la mémoire)
- Modèles **sur disque** (installés, prêts à charger)
- État des containers Docker

### `make models-list`
Vue détaillée façon `docker ps` des modèles Ollama :

```
Installés sur disque :
  codestral:22b                  12 GB    il y a 12 min
  llama3.3:70b                   42 GB    il y a 1 heure
  ...

Chargés en RAM :
  ●  codestral:22b               12 GB    RAM: 13 GB

Espace disque modèles :
  Total occupé : 99G
  Disque libre : 3,5Ti sur 3,6Ti
```

---

## Logs

| Commande | Description |
|----------|-------------|
| `make logs` | Logs de tous les containers en temps réel |
| `make logs-webui` | Logs Open WebUI uniquement |
| `make logs-search` | Logs SearXNG uniquement |

Quitter les logs : `Ctrl+C`

---

## Modèles

> Chaque commande vérifie la RAM disponible avant de télécharger (garde-fou 20 Go).

| Commande | Modèles téléchargés | Taille approx. |
|----------|---------------------|----------------|
| `make models-light` | nomic-embed-text · llama3.1:8b | ~18 Go |
| `make models` | + codestral:22b · phi4:14b · gemma4:31b · devstral:24b | ~60 Go |
| `make models-all` | + llama3.3:70b | ~103 Go |

**Recommandation** : commencer par `make models-light` pour tester le setup, puis `make models` pour le stack complet.

---

## Kimi K2.6 — Sandbox sécurisé

### `make kimi-setup`
Crée le réseau Docker isolé `kimi-sandbox` et démarre le container Kimi sur le port **11435**.

```bash
make kimi-setup
# Vérifie : réseau kimi-sandbox créé
# Vérifie : container ollama-kimi actif
# Rend kimi-guard.sh exécutable
```

### `make kimi-stop`
Arrête et supprime le container Kimi. Le réseau sandbox reste.

### `make kimi-status`
Affiche l'état du container Kimi (nom, statut, port).

---

## Veille LLM

### `make models-check-new`
Lance **3 recherches web** automatiques pour détecter les nouveaux modèles disponibles :

| Recherche | Source | Contenu |
|-----------|--------|---------|
| 1 | Ollama Registry | 20 derniers modèles publiés |
| 2 | Ollama Search | Filtres coding · sécurité · devops |
| 3 | GitHub Releases | Dernières versions d'Ollama + changelog |

Compare ensuite avec les modèles du stack et indique ceux installés / manquants.

---

## Monitoring

### `make monitor`
Snapshot instantané :
- RAM utilisée / disponible (alerte si marge < 20 Go)
- Température CPU/GPU et vitesse des ventilateurs
- Modèles Ollama actifs en mémoire
- État des containers Docker

### `make monitor-live`
Même chose en temps réel — rafraîchissement toutes les **5 secondes**. `Ctrl+C` pour quitter.

### `make security`
Rapport sécurité + performance en snapshot :

| Vérification | Détail |
|-------------|--------|
| Ports réseau | Vérifie que tous les ports sont sur `127.0.0.1` |
| Containers privileged | Aucun container ne doit être en mode privileged |
| Isolation Kimi | Kimi doit être sur `kimi-sandbox` uniquement |
| Fichier `.env` | Ne doit pas apparaître dans git |
| Processus suspects | Connexions sortantes inattendues |
| Charge CPU | Alerte si load > 80% des cœurs |
| Latence API Ollama | Temps de réponse sur port 11434 et 11435 |
| Performances Docker | CPU et RAM par container |
| Espace disque | Alerte si < 20 Go libres |

### `make security-live`
Même rapport en continu — rafraîchissement toutes les **30 secondes**.

### `make check-ram MODEL=<nom> SIZE=<go>`
Vérifie si la RAM disponible permet de charger un modèle en respectant la marge de **20 Go**.

```bash
make check-ram MODEL=llama3.3:70b SIZE=43
make check-ram MODEL=codestral:22b SIZE=14
```

Retourne une erreur (exit 1) si la RAM est insuffisante — peut être utilisé dans des scripts CI.

---

## Maintenance

### `make update`
Télécharge les dernières versions des images Docker et redémarre les containers.

```bash
make update
# docker compose pull
# docker compose up -d
```

### `make clean`
⚠ **Destructif** — supprime les volumes Docker (historique des conversations Open WebUI perdu).
Demande une confirmation explicite (`oui`) avant d'exécuter.

---

## Exemples de workflows

### Démarrage quotidien
```bash
make start
make status
```

### Avant de charger un gros modèle
```bash
make check-ram MODEL=llama3.3:70b SIZE=43
ollama run llama3.3:70b
```

### Veille hebdomadaire
```bash
make models-check-new
```

### Audit de sécurité
```bash
make security
```

### Debug d'un problème
```bash
make status
make logs
make monitor
```
