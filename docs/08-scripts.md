# 08 — Scripts

Tous les scripts se trouvent dans `scripts/`. Ils sont appelés par le Makefile mais peuvent aussi être exécutés directement.

---

## Vue d'ensemble

| Script | Rôle | Appelé par |
|--------|------|-----------|
| `kimi-guard.sh` | Filtre de sécurité obligatoire pour les sorties Kimi K2.6 | Manuel / pipeline |
| `monitor.sh` | Monitoring RAM · température · ventilateurs · modèles | `make monitor` / `make monitor-live` |
| `check-resources.sh` | Garde-fou RAM avant chargement d'un modèle | `make check-ram` / `make models*` |
| `security-perf-monitor.sh` | Audit sécurité réseau + performance stack | `make security` / `make security-live` |
| `check-new-models.sh` | Veille LLM — 3 recherches web (Ollama registry + GitHub) | `make models-check-new` |

---

## `kimi-guard.sh`

### Rôle
Filtre **obligatoire** appliqué à toute sortie du modèle Kimi K2.6. Détecte et bloque :
- Exfiltration de chemins système ou credentials
- Sorties contenant des tokens, secrets ou données sensibles
- Contenu suspect nécessitant validation humaine

### Usage
```bash
OLLAMA_HOST=127.0.0.1:11435 ollama run kimi-k2.6 "ta question" | ./scripts/kimi-guard.sh
```

### Workflow complet Kimi
```
Prompt → Kimi K2.6 (port 11435)
              ↓
        kimi-guard.sh          ← ce script
              ↓
    Validation Llama 3.3 70B
              ↓
      Validation humaine
              ↓
           Commit
```

### Rendre exécutable
```bash
chmod +x scripts/kimi-guard.sh
# ou : make kimi-setup (le fait automatiquement)
```

---

## `monitor.sh`

### Rôle
Monitoring système en temps réel pour surveiller la santé de la stack LLM.

### Ce qu'il affiche
| Section | Détail |
|---------|--------|
| RAM | Total · utilisée · disponible · alerte si < 20 Go |
| Température | CPU Die · GPU Die (via `powermetrics`) |
| Ventilateurs | Vitesse en RPM |
| Modèles Ollama | Modèles actifs en mémoire (`ollama ps`) |
| Docker | État des containers |

### Usage
```bash
# Snapshot unique
./scripts/monitor.sh

# Mode temps réel (rafraîchissement 5s)
./scripts/monitor.sh --watch

# Via Makefile
make monitor
make monitor-live
```

### Note sudo
La température et les ventilateurs nécessitent `sudo` (via `powermetrics`).
Pour un monitoring complet : `sudo make monitor`.

---

## `check-resources.sh`

### Rôle
Vérifie que la RAM disponible permet de charger un modèle tout en conservant une marge minimale de **20 Go**. Bloque le téléchargement si les ressources sont insuffisantes.

### Usage
```bash
./scripts/check-resources.sh <nom-modèle> <taille-go>

# Exemples
./scripts/check-resources.sh codestral:22b 14
./scripts/check-resources.sh llama3.3:70b 43

# Via Makefile
make check-ram MODEL=codestral:22b SIZE=14
```

### Logique de calcul
```
RAM disponible ≥ taille_modèle + 20 Go  →  ✓ autorisé
RAM disponible <  taille_modèle + 20 Go  →  ✗ refusé (exit 1)
```

### Codes de retour
| Code | Signification |
|------|--------------|
| `0` | RAM suffisante — chargement autorisé |
| `1` | RAM insuffisante — chargement bloqué |

Utilisable dans des scripts CI/CD :
```bash
./scripts/check-resources.sh llama3.3:70b 43 && ollama pull llama3.3:70b
```

---

## `security-perf-monitor.sh`

### Rôle
Audit combiné sécurité + performance de toute la stack. Détecte les mauvaises configurations et les anomalies de performance.

### Vérifications sécurité

| Vérification | Ce qui est contrôlé |
|-------------|---------------------|
| Ports réseau | Tous les ports doivent écouter sur `127.0.0.1`, jamais `0.0.0.0` |
| Containers privileged | Aucun container ne doit tourner en mode `privileged` |
| Isolation Kimi | Le container `ollama-kimi` doit être sur `kimi-sandbox` uniquement |
| Secrets git | `docker/.env` ne doit pas apparaître dans `git status` |
| Connexions sortantes | Détecte les connexions réseau inattendues depuis les containers |

### Vérifications performance

| Vérification | Ce qui est contrôlé |
|-------------|---------------------|
| Charge CPU | Load average vs nombre de cœurs (alerte > 80%) |
| Latence API Ollama | Temps de réponse sur port 11434 (standard) et 11435 (Kimi) |
| Stats Docker | CPU et RAM consommés par container |
| Espace disque | Alerte si espace libre < 20 Go |

### Usage
```bash
# Snapshot unique
./scripts/security-perf-monitor.sh

# Mode continu (rafraîchissement 30s)
./scripts/security-perf-monitor.sh --watch

# Via Makefile
make security
make security-live
```

---

## `check-new-models.sh`

### Rôle
Veille automatique sur les nouveaux modèles LLM disponibles. Effectue **3 recherches web** distinctes et compare les résultats avec le stack actuel du projet.

### Les 3 recherches

| # | Source | Filtre | Contenu |
|---|--------|--------|---------|
| 1 | Ollama Registry API | `sort=newest` | 20 derniers modèles publiés |
| 2 | Ollama Search | `code` · `security` · `devops` | Modèles pertinents pour le projet |
| 3 | GitHub API | `ollama/ollama/releases` | Dernières versions Ollama + changelog |

### Ce qu'il détecte
- Nouveaux modèles non encore dans le stack (marqués `★ nouveau candidat`)
- Modèles déjà installés (marqués `✓ déjà dans le stack`)
- Modèles cibles manquants sur la machine locale
- Mise à jour Ollama disponible

### Usage
```bash
./scripts/check-new-models.sh

# Via Makefile
make models-check-new
```

### Dépendances optionnelles
- `jq` : parsing JSON enrichi (résultats plus détaillés). Installer : `brew install jq`
- Sans `jq` : fonctionne en mode dégradé via grep

### Fréquence recommandée
Une fois par semaine — intégrable dans une tâche cron ou un pipeline CI.

---

## Rendre tous les scripts exécutables

```bash
chmod +x scripts/*.sh

# Ou via Makefile lors du setup Kimi :
make kimi-setup
```
