# 04 — Sécurité

## Principes fondamentaux

La sécurité est la **priorité absolue** de cette stack. Aucun compromis.

---

## Règles absolues

### 1. Exposition réseau
- Tous les ports sont liés à `127.0.0.1` — jamais à `0.0.0.0`
- Aucun service n'est accessible depuis le réseau local ou internet
- SearXNG n'est **jamais exposé** directement (accessible uniquement via Open WebUI)

### 2. Politique des modèles
| Niveau | Modèles | Règle |
|--------|---------|-------|
| ✅ Confiant | Mistral, Meta, Google, Microsoft | Usage libre |
| ⚠️ Sandboxé | qwen3.6:27b | Docker isolé + sandbox-guard.sh obligatoire |
| ❌ Exclu | Qwen, DeepSeek, modèles chinois non sandboxés | Interdit |

### 3. Données interdites avec qwen3.6:27b
- Secrets, tokens, credentials
- Code propriétaire
- Chemins hors dossier de travail
- Informations personnelles

---

## Protocole qwen3.6:27b

```
Prompt → qwen3.6:27b (port 11435)
              ↓
        sandbox-guard.sh          ← filtre automatique
              ↓
    Validation Llama 3.3 70B  ← 2ème avis
              ↓
      Validation humaine       ← obligatoire
              ↓
           Commit
```

Utilisation :

```bash
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh
```

---

## Sécurité Docker

### Mesures appliquées sur tous les containers

| Mesure | Détail |
|--------|--------|
| `no-new-privileges` | Empêche l'élévation de privilèges |
| `cap_drop: ALL` | Supprime toutes les capabilities Linux |
| `read_only: true` | Filesystem en lecture seule (SearXNG) |
| `mem_limit` | Limite la RAM par container |
| `cpus` | Limite le CPU par container |
| Ports sur `127.0.0.1` | Jamais exposé sur le réseau |

### Réseaux isolés

```
llm-frontend  →  Open WebUI ↔ localhost
llm-search    →  Open WebUI ↔ SearXNG (interne)
sandbox-net  →  Kimi isolé (--internal)
```

---

## Gestion des secrets

- Les clés secrètes sont dans `docker/.env`
- `.env` est dans `.gitignore` — **jamais commité**
- Utiliser `docker/.env.dist` comme template (sans valeurs réelles)
- Régénérer les clés si compromission suspectée :

```bash
openssl rand -hex 32
```

---

## Checklist de sécurité

Avant chaque mise en production :

- [ ] `.env` absent du dépôt git (`git status` ne le montre pas)
- [ ] Ports vérifiés sur `127.0.0.1` uniquement
- [ ] `ENABLE_SIGNUP=false` dans Open WebUI
- [ ] `WEBUI_AUTH=true` dans Open WebUI
- [ ] qwen3.6:27b uniquement sur port 11435
- [ ] `sandbox-guard.sh` exécutable (`chmod +x`)
- [ ] Aucun modèle exclu installé (`ollama list`)
