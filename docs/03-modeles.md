# 03 — Modèles LLM

## Catalogue des modèles retenus

| Modèle | Origine | Taille | Port | Cas d'usage principal |
|--------|---------|--------|------|----------------------|
| `codestral:22b` | Mistral 🇫🇷 | ~12 GB | 11434 | Coding quotidien PHP/Symfony/JS/Python/Bash/**Java** |
| `devstral-small-2` | Mistral 🇫🇷 | ~14 GB | 11434 | Refactoring multi-fichiers, agents, **Ansible playbooks** |
| `llama3.3:70b` | Meta 🇺🇸 | ~43 GB | 11434 | Architecture, revue sécurité OWASP, **K8s/RedHat** |
| `phi4-reasoning` | Meta 🇺🇸 | ~4.7 GB | 11434 | Scanning sécurité rapide, pipeline CI, **scripts Linux** |
| `phi4-reasoning` | Microsoft 🇺🇸 | ~8.9 GB | 11434 | 2ème opinion architecture, SOLID, **Java design patterns** |
| `gemma4:31b` | Google 🇺🇸 | ~19 GB | 11434 | Agents sécurité, tool-calling, **ELK/monitoring queries** |
| `qwen3.6:35b` | Moonshot 🇨🇳 | ~? GB | **11435** | Coding pur non sensible — sandbox Docker |
| `nomic-embed-text` | Nomic 🇺🇸 | ~274 MB | 11434 | Embeddings RAG, **indexation logs ELK** |

---

## Politique de confiance

| Niveau | Origine | Règle |
|--------|---------|-------|
| ✅ Confiant | Mistral 🇫🇷, Meta 🇺🇸, Google 🇺🇸, Microsoft 🇺🇸 | Usage libre |
| ⚠️ Sandboxé | qwen3.6:35b — Moonshot 🇨🇳 | Docker obligatoire + sandbox-guard.sh |
| ❌ Exclu | Qwen, DeepSeek, tout modèle chinois sans sandbox | Ne pas installer |

---

## Ordre de téléchargement recommandé

Ordre optimisé : léger → lourd, pour être opérationnel rapidement.

```bash
# 1. Embeddings RAG (274 MB) — indispensable pour la recherche dans documents
ollama pull nomic-embed-text

# 2. Modèle rapide CI/scan (4.7 GB)
ollama pull phi4-reasoning

# 3. Coding quotidien (12 GB)
ollama pull codestral:22b

# 4. 2ème opinion architecture (8.9 GB)
ollama pull phi4-reasoning

# 5. Agents sécurité (17 GB)
ollama pull gemma4:31b

# 6. Refactoring multi-fichiers (14 GB)
ollama pull devstral-small-2

# 7. Architecture & revue sécurité (43 GB) — le plus lourd
ollama pull llama3.3:70b
```

---

## Budget RAM estimé

| Scénario | Modèles actifs | RAM consommée |
|----------|---------------|---------------|
| Léger | phi4-reasoning | ~6 GB |
| Standard | codestral:22b | ~14 GB |
| Lourd | llama3.3:70b | ~45 GB |
| Max simultané | codestral + phi4 | ~25 GB |

> Avec 128 Go de RAM unifiée, tous les modèles peuvent être chargés simultanément.

---

## Vérification

```bash
# Lister les modèles installés
ollama list

# Voir les modèles actifs en mémoire
ollama ps

# Tester un modèle
ollama run phi4-reasoning "Bonjour, tu fonctionne ?"
```
