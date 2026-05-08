# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Contexte

Ce projet gère la sélection, l'installation et la sécurisation des **LLMs locaux via Ollama** sur le MacBook Pro de Zied (M5 Max, 128 Go RAM). Stack cible : Symfony · JavaScript · React · Node.js · Python · Bash · Pentest.

---

## Structure

```
LLM/
├── llm.md                  ← référence complète : modèles, sécurité, commandes
└── scripts/
    └── sandbox-guard.sh    ← garde-fou obligatoire pour les sorties du modèle sandboxé
```

---

## Règles absolues

### Sécurité des modèles
| Niveau | Origine | Règle |
|--------|---------|-------|
| ✅ Confiant | Mistral 🇫🇷, Meta 🇺🇸, Google 🇺🇸, Microsoft 🇺🇸 | Usage libre |
| ⚠️ Sandboxé | qwen2.5-coder:32b — Alibaba 🇨🇳 | Docker obligatoire + sandbox-guard.sh |
| ❌ Exclu | Tout modèle chinois sans sandbox (Qwen hors Docker, DeepSeek, etc.) | Ne pas suggérer |

> **Pourquoi Qwen2.5-coder dans le sandbox ?**
> Kimi K2.6 (Moonshot) n'existe pas en version locale sur Ollama — uniquement en connecteur cloud (envoie les données vers des serveurs chinois). Qwen2.5-coder:32b est le remplaçant local sandboxé : même niveau de qualité coding, 100% local, isolé dans Docker.

### qwen2.5-coder:32b — protocole obligatoire
- Tourne **exclusivement** dans le sandbox Docker sur le port **11435**
- Toute sortie doit passer par `scripts/sandbox-guard.sh` avant usage
- Interdit sur : secrets, tokens, credentials, code propriétaire, chemins hors dossier de travail
- Workflow : `Qwen → sandbox-guard.sh → validation Llama 3.3 70B → validation humaine → commit`

### Qualité du code généré
Tout code produit ou validé ici doit respecter :
- **Clean Architecture** — Domain / Application / Infrastructure
- **SOLID + DDD** pour les projets Symfony
- **Scalabilité, adaptabilité, évolutivité, maintenabilité**

---

## Modèles retenus

| Modèle | Origine | Port | Tâche principale |
|--------|---------|------|-----------------|
| `codestral:22b` | Mistral 🇫🇷 | 11434 | Coding quotidien PHP/Symfony/JS/Python/Bash/Java |
| `devstral:24b` | Mistral 🇫🇷 | 11434 | Refactoring multi-fichiers, agents, Ansible |
| `llama3.3:70b` | Meta 🇺🇸 | 11434 | Architecture, revue sécurité OWASP, K8s/RedHat |
| `llama3.1:8b` | Meta 🇺🇸 | 11434 | Scanning sécurité rapide, pipeline CI |
| `phi4:14b` | Microsoft 🇺🇸 | 11434 | 2ème opinion architecture, SOLID, Java |
| `gemma4:31b` | Google 🇺🇸 | 11434 | Agents sécurité, tool-calling, ELK, context 256K |
| `qwen2.5-coder:32b` | Alibaba 🇨🇳 | **11435** | Coding pur non sensible — sandbox Docker |
| `nomic-embed-text` | Nomic 🇺🇸 | 11434 | Embeddings RAG |

---

## Commandes essentielles

```bash
# Lister les modèles installés
ollama list

# Modèles standards (port 11434)
ollama run codestral:22b
ollama run llama3.3:70b

# Qwen sandboxé — sandbox uniquement
OLLAMA_HOST=127.0.0.1:11435 ollama run qwen2.5-coder:32b "question" | ./scripts/sandbox-guard.sh

# Rendre le guard exécutable
chmod +x scripts/sandbox-guard.sh

# Démarrer le sandbox Docker
make sandbox-setup

# Vérifier les modèles en cours d'exécution
ollama ps
```

---

## Référence complète

Voir `llm.md` pour : benchmarks, quantization recommandée, budget RAM, état d'installation de chaque modèle.
