# 05 — Interfaces

## Open WebUI

### Présentation
Interface web de type ChatGPT connectée à Ollama. Accessible sur http://localhost:3000

### Fonctionnalités clés
- Changement de modèle en un clic
- Recherche web via SearXNG (intégrée)
- Upload de documents (RAG)
- Historique des conversations
- Gestion multi-utilisateurs

### Activer la recherche web
1. Aller dans **Paramètres → Web Search**
2. Moteur : `SearXNG`
3. URL : `http://searxng:8080/search?q=<query>&format=json`
4. Activer le toggle **Enable Web Search**

Dans le chat, cliquer sur l'icône globe 🌐 pour activer la recherche sur un message.

### Mise à jour
```bash
cd docker
docker compose pull open-webui
docker compose up -d open-webui
```

---

## SearXNG

### Présentation
Moteur de recherche privé — agrège Google, Bing, DuckDuckGo, Wikipedia et 70+ autres sources. Fonctionne **uniquement en API** pour Open WebUI, sans interface directe.

### Sources configurées
| Source | Shortcut | Activée |
|--------|----------|---------|
| Google | `g` | Oui |
| Bing | `b` | Oui |
| DuckDuckGo | `d` | Oui |
| Wikipedia FR | `w` | Oui |
| GitHub | `gh` | Oui |

### Configuration
Fichier : `docker/searxng/settings.yml`

Après modification :
```bash
docker compose restart searxng
```

### Mise à jour
```bash
cd docker
docker compose pull searxng
docker compose up -d searxng
```
