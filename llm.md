# LLMs Locaux — Stack Dev + Sécurité
> MacBook Pro M5 Max 128 Go · Symfony · JavaScript · Python · Node.js · Bash · React · Pentest

---

## Principes de sélection

### Sécurité des modèles
| Niveau | Origine | Statut |
|--------|---------|--------|
| ✅ Confiant | USA / Europe — gouvernance claire, audités | Retenu |
| ⚠️ Sandboxé | Chine — puissant mais guardrails faibles — sandbox obligatoire | Retenu avec restrictions |
| ❌ Éviter | Origine inconnue | Exclu |

### Critères qualité code imposés
Tous les modèles retenus doivent être capables de respecter :
- **Clean Architecture** — séparation claire des couches (Domain, Application, Infrastructure)
- **Scalabilité** — code qui tient la charge
- **Adaptabilité** — interfaces stables, implémentations interchangeables
- **Évolutivité** — SOLID, DDD, patterns extensibles
- **Maintenabilité** — lisibilité, conventions, tests

---

## Stack des modèles retenus

### Modèle 1 — Codestral 22B · Mistral AI (France) 🇫🇷
> Coding quotidien — PHP/Symfony · JS · Python · Bash · React

```bash
ollama pull codestral:22b
```

| Attribut | Valeur |
|----------|--------|
| Origine | Mistral AI — France (EU AI Act compliant) |
| Taille | ~13 Go (Q4) / ~22 Go (Q8) |
| RAM utilisée | ~22 Go à Q8 — laisse 106 Go libres |
| Langages | 80+ dont PHP, JS, Python, Bash, TypeScript |
| Spécialité | Complétion de code, fill-in-the-middle, refactoring |

**Pourquoi pour ton stack :**
- Meilleur modèle open source pour **PHP/Symfony** — surpasse CodeLlama 70B sur PHP
- Excellent sur **React/Node.js/TypeScript**
- Rapide : réponses en < 2s sur M5 Max
- Connaît les patterns Symfony (Repository, Service Layer, Event Dispatcher)

```bash
ollama run codestral:22b
```

---

### Modèle 2 — Devstral 24B · Mistral AI (France) 🇫🇷
> Agentic coding — édition multi-fichiers · refactoring de projet entier

```bash
ollama pull devstral-small-2
```

| Attribut | Valeur |
|----------|--------|
| Origine | Mistral AI — France |
| Taille | ~14 Go (Q4) / ~22 Go (Q8) |
| RAM utilisée | ~22 Go à Q8 |
| Spécialité | Multi-fichiers, workflows agents, navigation de codebase |

**Pourquoi pour ton stack :**
- Conçu pour les **agents de code** (comme Claude Code) — comprend la structure d'un projet entier
- Idéal pour refactorer une **app Symfony** sur plusieurs fichiers simultanément
- Respecte les conventions d'architecture : impose des séparations propres entre couches

```bash
ollama run devstral-small-2
```

---

### Modèle 3 — Llama 3.3 70B · Meta (USA) 🇺🇸
> Architecture · Revue de code · Raisonnement complexe · Pentest (analyse)

```bash
ollama pull llama3.3:70b-instruct-q5_K_M
```

| Attribut | Valeur |
|----------|--------|
| Origine | Meta — USA |
| Taille | ~48 Go à Q5_K_M |
| RAM utilisée | ~48 Go — laisse 80 Go libres |
| Benchmarks | 92.1% instruction-following |
| Contexte | 128K tokens |

**Pourquoi pour ton stack :**
- Le meilleur modèle open source pour les décisions d'**architecture logicielle**
- Comprend profondément **SOLID, DDD, Clean Architecture, Hexagonal**
- **Revue de sécurité** : détecte les injections SQL, XSS, IDOR, mauvaises configs Symfony
- Analyse de vulnérabilités OWASP Top 10 dans du code PHP/JS
- Assez grand pour raisonner sur des patterns complexes et expliquer le POURQUOI

```bash
ollama run llama3.3:70b-instruct-q5_K_M
```

---

### Modèle 4 — Llama 3.1 8B · Meta (USA) 🇺🇸
> Pentest automatisé · Scanning de sécurité rapide · OASIS

```bash
ollama pull phi4-reasoning
```

| Attribut | Valeur |
|----------|--------|
| Origine | Meta — USA |
| Taille | ~5 Go (Q4) |
| RAM utilisée | ~5 Go — ultra léger |
| Spécialité | Sécurité automatisée, scanning rapide, pipeline CI |

**Pourquoi pour ton stack :**
- Modèle recommandé par **OASIS** (Ollama Automated Security Intelligence Scanner)
- Analyse de code en continu dans un pipeline CI/CD
- Rapide : idéal pour scanner chaque commit avant merge
- Combiné avec **Promptfoo** pour red-teaming automatisé

```bash
# Installer les outils de sécurité associés
npm install -g promptfoo          # Red-teaming automatisé
pip install oasis-security        # Scanner sécurité OWASP

ollama run phi4-reasoning
```

---

### Modèle 5 — Phi-4 14B · Microsoft (USA) 🇺🇸
> Raisonnement structuré · Architecture · Analyse de patterns

```bash
ollama pull phi4-reasoning
```

| Attribut | Valeur |
|----------|--------|
| Origine | Microsoft Research — USA |
| Taille | ~9 Go (Q4) |
| RAM utilisée | ~9 Go — très léger |
| Spécialité | Raisonnement structuré, surpasse des modèles 30-70B sur l'analyse |

**Pourquoi pour ton stack :**
- Excellent pour valider des **choix d'architecture** (DDD vs CRUD, MVC vs Hexagonal)
- Léger mais puissant : parfait pour une 2ème opinion rapide
- Bon pour analyser si ton code Symfony respecte les **principes SOLID**

```bash
ollama run phi4-reasoning
```

---

### Modèle 6 — Gemma 3 27B · Google (USA) 🇺🇸
> Tool-calling · Agents · Analyse de vulnérabilités automatisée

```bash
ollama pull gemma4:31b
```

| Attribut | Valeur |
|----------|--------|
| Origine | Google — USA (Apache 2.0) |
| Taille | ~20 Go à Q8 |
| RAM utilisée | ~20 Go |
| Spécialité | Function calling, tool use, agents automatisés |

**Pourquoi pour ton stack :**
- Le meilleur pour construire des **agents de sécurité** qui appellent des outils (nmap, sqlmap, etc.)
- Excellent pour les **workflows automatisés** de revue de code
- Apache 2.0 — le plus permissif pour usage commercial

```bash
ollama run gemma4:31b
```

---

---

## Modèle 7 — qwen3.6:35b · Moonshot AI (Chine) 🇨🇳 ⚠️ Sandboxé
> Meilleur coding open source — usage restreint au code non sensible

```bash
ollama pull qwen3.6:35b
```

| Attribut | Valeur |
|----------|--------|
| Origine | Moonshot AI — Chine (juridiction chinoise) |
| Architecture | MoE — 32B actifs / ~1T total |
| Taille | ~70-80 Go (Q4_K_M) |
| RAM utilisée | ~75 Go — laisse 53 Go libres |
| Licence | MIT modifié (libre pour usage interne) |
| SWE-Bench | **80.2%** — #1 open source mondial |
| Guardrails | **1.55%** — extrêmement faibles |

### Pourquoi l'utiliser malgré les risques
- **80.2% SWE-Bench** — surpasse Devstral (68%) et Llama 3.3 70B (~55%) sur le code réel
- Local via Ollama = **zéro communication réseau** vers la Chine
- Aucun backdoor technique trouvé par HiddenLayer et autres chercheurs
- MoE : 32B actifs seulement — inférence rapide malgré 1T de paramètres

### Ce qui est INTERDIT avec Kimi
- ❌ Code contenant des tokens / clés API / secrets
- ❌ Code propriétaire ou confidentiel
- ❌ Fichiers de configuration avec credentials
- ❌ Accès à des dossiers hors du projet de travail
- ❌ Exécution de commandes shell sans validation humaine

### Sandbox Docker obligatoire pour Kimi

```bash
# Créer le réseau isolé (pas d'accès internet)
docker network create --internal sandbox-net

# Lancer Ollama dans un container sandboxé
docker run -d \
  --name ollama-sandbox \
  --network sandbox-net \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --read-only \
  --tmpfs /tmp:size=512m \
  --tmpfs /root/.ollama:size=100g \
  -v $(pwd):/workspace:ro \
  -e OLLAMA_HOST=127.0.0.1 \
  -e OLLAMA_NO_PRUNE=1 \
  --memory="90g" \
  --cpus="16" \
  -p 127.0.0.1:11435:11434 \
  ollama/ollama

# Charger Kimi dans le container
docker exec ollama-sandbox ollama pull qwen3.6:35b

# Utiliser Kimi via le port dédié (11435 ≠ 11434 pour les autres modèles)
ollama run qwen3.6:35b
```

**Ce que le sandbox impose :**
- `--network sandbox-net --internal` → pas d'accès internet
- `-v $(pwd):/workspace:ro` → lecture seule, dossier courant uniquement
- `--cap-drop ALL` → zéro privilege Linux
- `--read-only` → système de fichiers container en lecture seule
- Port **11435** séparé → Kimi isolé des autres modèles sur 11434

### Hook de validation des sorties Kimi

Créer `/Users/devsecops/projects/macbook/scripts/sandbox-guard.sh` :

```bash
#!/usr/bin/env bash
# Intercepte et valide les sorties de Kimi avant usage

BLOCKED_PATTERNS=(
  "rm -rf"
  "curl.*|.*bash"
  "wget.*|.*bash"
  "eval.*\$("
  "base64.*decode"
  "/etc/passwd"
  "/etc/shadow"
  "ssh-keygen"
  "chmod 777"
  "> /dev/null 2>&1 &"
)

INPUT=$(cat)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$INPUT" | grep -qiE "$pattern"; then
    echo "⚠️  KIMI GUARD: Pattern dangereux détecté → '$pattern'" >&2
    echo "Sortie bloquée. Valider manuellement avant usage." >&2
    exit 1
  fi
done

# Validation Llama 3.3 70B (2ème avis sécurité)
echo "✅ KIMI GUARD: Sortie validée — soumission à Llama 3.3 pour audit..."
echo "$INPUT"
```

```bash
chmod +x /Users/devsecops/projects/macbook/scripts/sandbox-guard.sh

# Usage : toujours passer la sortie de Kimi dans le guard
ollama run qwen3.6:35b "ta question" | ./scripts/sandbox-guard.sh
```

### Workflow sécurisé avec Kimi

```
qwen3.6:35b (sandbox Docker)
        ↓
  sandbox-guard.sh (détection patterns dangereux)
        ↓
  Llama 3.3 70B (audit sécurité de la sortie)
        ↓
  Validation humaine obligatoire avant commit
```

---

## Installation complète (dans l'ordre)

```bash
# 1. Coding quotidien PHP/Symfony/JS/Python
ollama pull codestral:22b

# 2. Agentic coding multi-fichiers
ollama pull devstral-small-2

# 3. Architecture + revue sécurité approfondie
ollama pull llama3.3:70b-instruct-q5_K_M

# 4. Scanning sécurité rapide (pipeline CI)
ollama pull phi4-reasoning

# 5. Raisonnement architecture
ollama pull phi4-reasoning

# 6. Agents & tool-calling sécurité
ollama pull gemma4:31b

# Embeddings pour RAG (recherche dans ta codebase Symfony)
ollama pull nomic-embed-text

# 7. qwen3.6:35b — dans le sandbox Docker uniquement (voir section Sandbox)
docker network create --internal sandbox-net
docker run -d --name ollama-sandbox --network sandbox-net \
  --cap-drop ALL --read-only \
  --tmpfs /tmp:size=512m --tmpfs /root/.ollama:size=100g \
  -v $(pwd):/workspace:ro \
  -e OLLAMA_HOST=127.0.0.1 \
  --memory="90g" --cpus="16" \
  -p 127.0.0.1:11435:11434 ollama/ollama
docker exec ollama-sandbox ollama pull qwen3.6:35b
```

---

## Quel modèle pour quelle tâche ?

| Tâche | Modèle à utiliser |
|-------|------------------|
| Écrire du code Symfony / PHP | `codestral:22b` |
| Écrire du React / Node.js / JS | `codestral:22b` |
| Scripts Bash / DevOps | `codestral:22b` |
| Refactoring multi-fichiers | `devstral-small-2` |
| Revue d'architecture (Clean / DDD) | `llama3.3:70b` |
| Analyse OWASP / vulnérabilités | `llama3.3:70b` |
| Pentest automatisé (CI/CD) | `phi4-reasoning` + OASIS |
| Choix de pattern / 2ème opinion | `phi4-reasoning` |
| Agents sécurité / tool-calling | `gemma4:31b` |
| Coding pur non sensible (max perf) | `qwen3.6:35b` dans sandbox Docker → validé par `llama3.3:70b` |

---

## Budget RAM — combinaisons simultanées

| Modèles chargés simultanément | RAM utilisée | RAM libre |
|-------------------------------|-------------|-----------|
| codestral:22b + llama3.3:70b | ~70 Go | 58 Go |
| devstral-small-2 + llama3.3:70b | ~70 Go | 58 Go |
| codestral + phi4-reasoning + phi4 | ~36 Go | 92 Go |
| qwen3.6:35b (sandbox) + llama3.3:70b (audit) | ~123 Go | 5 Go ⚠️ limite |
| qwen3.6:35b seul (sandbox) | ~75 Go | 53 Go |

---

## État des installations

| Modèle | Origine | Confiance | Taille | Statut |
|--------|---------|-----------|--------|--------|
| codestral:22b | Mistral 🇫🇷 | ✅ | ~22 Go | ⬜ À installer |
| devstral-small-2 | Mistral 🇫🇷 | ✅ | ~22 Go | ⬜ À installer |
| llama3.3:70b Q5 | Meta 🇺🇸 | ✅ | ~48 Go | ⬜ À installer |
| phi4-reasoning | Meta 🇺🇸 | ✅ | ~5 Go | ⬜ À installer |
| phi4-reasoning | Microsoft 🇺🇸 | ✅ | ~9 Go | ⬜ À installer |
| gemma4:31b | Google 🇺🇸 | ✅ | ~20 Go | ⬜ À installer |
| nomic-embed-text | Nomic 🇺🇸 | ✅ | ~274 Mo | ⬜ À installer |
| qwen3.6:35b | Moonshot 🇨🇳 | ⚠️ Sandbox Docker | ~75 Go | ⬜ À installer |
