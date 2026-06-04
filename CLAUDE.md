# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Règle absolue — Données à jour

**Toujours vérifier sur le web à la date du jour avant toute recommandation de modèle.**
Ne jamais se baser sur la mémoire interne de Claude (cutoff août 2025) ni sur des données de janvier 2025/2026.
→ Utiliser `make models-check-new` ou une recherche web explicite sur `ollama.com/library/<model>`.

---

## Contexte

Ce projet gère la sélection, l'installation et la sécurisation des **LLMs locaux via Ollama** sur le Mac M-series (128 Go RAM). Stack cible : Symfony · JavaScript · React · Node.js · Python · Bash · Java · Linux · RedHat · Ansible · K8s · ELK · Redis · Pentest.

Un seul modèle chargé en RAM à la fois — chargement à la demande via `make load MODEL=<nom>`.

---

## Structure

```
LLM/
├── llm.md                  ← référence complète : modèles, sécurité, commandes
├── scripts/
│   ├── sandbox-guard.sh    ← filtre obligatoire pour les sorties des modèles Alibaba
│   └── load-model.sh       ← chargement/déchargement RAM à la demande
└── docker/                 ← Open WebUI + SearXNG (interfaces uniquement)
```

---

## Règles absolues

### Samples de sécurité — Clés et secrets de test
Tout fichier dans `tests/security/samples/` contient des vulnérabilités intentionnelles.
**Règle obligatoire** : toutes les clés/credentials dans ces fichiers doivent utiliser un format **explicitement faux** pour éviter le blocage GitHub Secret Scanning :

| ❌ Interdit | ✅ Obligatoire |
|------------|--------------|
| Clé Stripe au format réel (`sk_live_...`) | `FAKE_STRIPE_KEY_FOR_SECURITY_TESTING_ONLY` |
| Clé AWS au format réel (`AKIA...`) | `FAKE_AWS_ACCESS_KEY_FOR_TESTING` |
| Token GitHub au format réel (`ghp_...`) | `FAKE_GITHUB_TOKEN_FOR_TESTING_ONLY` |

Format imposé : préfixer par `FAKE_` ou suffixer par `_FOR_SECURITY_TESTING_ONLY`.
Ne jamais utiliser des patterns qui ressemblent à de vraies clés (longueur, format, préfixe réel).

---

### Sécurité des modèles
| Niveau | Origine | Règle |
|--------|---------|-------|
| ✅ Confiant | Mistral 🇫🇷, Meta 🇺🇸, Google 🇺🇸, Microsoft 🇺🇸 | Usage libre port 11434 |
| ⚠️ Filtré | qwen3.6:27b — Alibaba 🇨🇳 | Sortie obligatoirement via `sandbox-guard.sh` |
| ❌ Exclu | DeepSeek, modèles cloud chinois non locaux | Ne jamais suggérer |

### qwen3.6:27b — protocole obligatoire

- Tourne sur le port **11434** (Ollama natif, pas de Docker sandbox)
- **Toute sortie doit passer par `scripts/sandbox-guard.sh` avant usage**
- Interdit sur : secrets, tokens, credentials, code propriétaire, chemins hors dossier de travail
- Workflow : `qwen3.6:27b → sandbox-guard.sh → validation humaine → commit`

```bash
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh
# exit 0 = OK | exit 1 = SUSPECT (validation renforcée) | exit 2 = BLOQUÉ (ne pas utiliser)
```

**sandbox-guard.sh v2 — 13 couches de détection (sources 2025-2026) :**

| Couche | Menace |
|--------|--------|
| 1 | Stéganographie Unicode — ASCII smuggling U+E0000, zero-width, homoglyphes cyrilliques |
| 2 | Encodage & obfuscation — base64 blobs, shellcode hex, eval+decode |
| 3 | Injection shell — reverse shells, fork bomb, curl\|bash, persistence cron |
| 4 | Exfiltration réseau — ngrok, webhook.site, DNS exfil, netcat |
| 5 | Secrets & credentials — API keys (Anthropic/GitHub/AWS/Google), clés privées |
| 6 | Filesystem sensible — /etc/shadow, .ssh, keychain macOS, /proc/keys |
| 7 | Exécution de code — Python RCE, pickle, YAML unsafe, PHP passthru, Java Runtime.exec |
| 8 | Artifacts d'injection — DAN mode, Mastermind multi-turn (95% ASR), temporal confusion |
| 9 | Supply chain — typosquatting pip/npm, index HTTP, postinstall hooks malveillants |
| 10 | Évasion container — docker.sock, cgroup escape, runc CVE-2025-31133/52881 |
| 11 | Entropie élevée — payloads chiffrés > 4.8 bits/char (via Python Shannon entropy) |
| 12 | URLs malveillantes — C2 connus, pastebin raw, data URI, javascript: |
| 13 | Cryptomining — xmrig, stratum, monero |

Logs : `~/.sandbox-guard/logs/` — doc complète : `docs/08-scripts.md`

### Qualité du code généré
Tout code produit ou validé ici doit respecter :
- **Clean Architecture** — Domain / Application / Infrastructure
- **SOLID + DDD** pour les projets Symfony
- **Scalabilité, adaptabilité, évolutivité, maintenabilité**

---

## Modèles retenus — stack actuelle (vérifiée le 2026-05-08)

| Modèle | Origine | Tâche principale |
|--------|---------|-----------------|
| `codestral:22b` | Mistral 🇫🇷 | Coding quotidien PHP/Symfony/JS/Python/Bash/Java |
| `devstral-small-2` | Mistral 🇫🇷 | Refactoring multi-fichiers, agents, Ansible (SWE-bench 65.8%) |
| `llama3.3:70b` | Meta 🇺🇸 | Architecture, revue sécurité OWASP, K8s/RedHat |
| `phi4-reasoning:plus` | Microsoft 🇺🇸 | Architecture, SOLID, Java — niveau raisonnement o3-mini |
| `gemma4:31b` | Google 🇺🇸 | Agents sécurité, tool-calling, ELK, context 256K |
| `qwen3.6:27b` | Alibaba 🇨🇳 ⚠️ | Coding pur non sensible — sortie via sandbox-guard.sh |
| `nomic-embed-text-v2-moe` | Nomic 🇺🇸 | Embeddings RAG multilingue |

**Modèles retirés (obsolètes)**
- ~~`llama3.1:8b`~~ — remplacé par phi4-reasoning:plus (même taille, qualité sans comparaison)
- ~~`phi4:14b`~~ — remplacé par phi4-reasoning:plus
- ~~`devstral:24b`~~ — remplacé par devstral-small-2 (plus récent, meilleur)
- ~~`nomic-embed-text`~~ — remplacé par v2-moe (multilingue, MoE)
- ~~`gemma3:27b`~~ — remplacé par gemma4:31b
- ~~`qwen2.5-coder:32b`~~ — remplacé par qwen3.6:27b

---

## Commandes essentielles

```bash
# Charger un modèle à la demande (décharge l'actuel automatiquement)
make load MODEL=codestral:22b
make switch MODEL=llama3.3:70b
make unload

# Modèles Alibaba — filtre obligatoire
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh

# Statut complet
make status
ollama ps

# Veille modèles (toujours vérifier sur le web)
make models-check-new
```

---

## Référence complète

Voir `llm.md` pour : benchmarks, quantization recommandée, budget RAM, état d'installation de chaque modèle.
