# 03 — Modèles LLM

## Catalogue des modèles retenus

| Modèle | Origine | Taille | Port | Cas d'usage principal |
|--------|---------|--------|------|----------------------|
| `codestral:22b` | Mistral 🇫🇷 | ~12 GB | 11434 | Coding quotidien PHP/Symfony/JS/Python/Bash/**Java** |
| `devstral:24b` | Mistral 🇫🇷 | ~14 GB | 11434 | Refactoring multi-fichiers, agents, **Ansible playbooks** |
| `llama3.3:70b` | Meta 🇺🇸 | ~43 GB | 11434 | Architecture, revue sécurité OWASP, **K8s/RedHat** |
| `llama3.1:8b` | Meta 🇺🇸 | ~4.7 GB | 11434 | Scanning sécurité rapide, pipeline CI, **scripts Linux** |
| `phi4:14b` | Microsoft 🇺🇸 | ~8.9 GB | 11434 | 2ème opinion architecture, SOLID, **Java design patterns** |
| `gemma3:27b` | Google 🇺🇸 | ~17 GB | 11434 | Agents sécurité, tool-calling, **ELK/monitoring queries** |
| `kimi-k2.6` | Moonshot 🇨🇳 | ~? GB | **11435** | Coding pur non sensible — sandbox Docker |
| `nomic-embed-text` | Nomic 🇺🇸 | ~274 MB | 11434 | Embeddings RAG, **indexation logs ELK** |

---

## Politique de confiance

| Niveau | Origine | Règle |
|--------|---------|-------|
| ✅ Confiant | Mistral 🇫🇷, Meta 🇺🇸, Google 🇺🇸, Microsoft 🇺🇸 | Usage libre |
| ⚠️ Sandboxé | Kimi K2.6 — Moonshot 🇨🇳 | Docker obligatoire + kimi-guard.sh |
| ❌ Exclu | Qwen, DeepSeek, tout modèle chinois sans sandbox | Ne pas installer |

---

## Ordre de téléchargement recommandé

Ordre optimisé : léger → lourd, pour être opérationnel rapidement.

```bash
# 1. Embeddings RAG (274 MB) — indispensable pour la recherche dans documents
ollama pull nomic-embed-text

# 2. Modèle rapide CI/scan (4.7 GB)
ollama pull llama3.1:8b

# 3. Coding quotidien (12 GB)
ollama pull codestral:22b

# 4. 2ème opinion architecture (8.9 GB)
ollama pull phi4:14b

# 5. Agents sécurité (17 GB)
ollama pull gemma3:27b

# 6. Refactoring multi-fichiers (14 GB)
ollama pull devstral:24b

# 7. Architecture & revue sécurité (43 GB) — le plus lourd
ollama pull llama3.3:70b
```

---

## Budget RAM estimé

| Scénario | Modèles actifs | RAM consommée |
|----------|---------------|---------------|
| Léger | llama3.1:8b | ~6 GB |
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
ollama run llama3.1:8b "Bonjour, tu fonctionne ?"
```
