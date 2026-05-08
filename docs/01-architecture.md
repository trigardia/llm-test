# 01 — Architecture

## Vue d'ensemble

```
┌─────────────────────────────────────────────────────────────┐
│                     MACOS (natif)                           │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  OLLAMA — Port 11434                                │  │
│   │  GPU M5 Max · Mémoire unifiée 128 Go                │  │
│   │                                                     │  │
│   │  codestral:22b · devstral:24b · llama3.3:70b       │  │
│   │  llama3.1:8b · phi4:14b · gemma3:27b               │  │
│   │  nomic-embed-text                                   │  │
│   └─────────────────────┬───────────────────────────────┘  │
│                         │ API REST                          │
└─────────────────────────┼───────────────────────────────────┘
                          │ host.docker.internal:11434
┌─────────────────────────┼───────────────────────────────────┐
│   DOCKER                │                                   │
│                         ▼                                   │
│   ┌─────────────────────────────────┐                       │
│   │  OPEN WEBUI — Port 3000        │                       │
│   │  Interface utilisateur         │                       │
│   │  Auth · RAG · Web Search       │                       │
│   └──────────────┬──────────────────┘                       │
│                  │ Réseau interne llm-search                 │
│                  ▼                                           │
│   ┌─────────────────────────────────┐                       │
│   │  SEARXNG — Port 8080 (interne) │                       │
│   │  Non exposé publiquement       │                       │
│   │  Google · Bing · DDG · Wikipedia│                       │
│   └─────────────────────────────────┘                       │
│                                                             │
│ ─ ─ ─ ─ ─ ─ ─ SANDBOX ISOLÉ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│                                                             │
│   ┌─────────────────────────────────┐                       │
│   │  KIMI K2.6 — Port 11435        │                       │
│   │  Réseau : kimi-sandbox (isolé) │                       │
│   │  Sortie filtrée par kimi-guard │                       │
│   └─────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
```

## Choix techniques

### Pourquoi Ollama natif (pas dans Docker) ?
Docker sur macOS ne transmet pas le GPU Apple Silicon aux containers. Ollama natif utilise pleinement le GPU M5 Max et la mémoire unifiée — performances 5x à 10x supérieures.

### Pourquoi les interfaces dans Docker ?
Isolation, reproductibilité, mise à jour facile (`docker compose pull`), aucun impact sur les performances GPU.

### Pourquoi SearXNG et pas une API Google/Bing directe ?
- Aucune clé API requise
- Agrège 70+ sources simultanément
- Privé — aucun tracking
- Hébergé localement

## Réseaux Docker

| Réseau | Type | Usage |
|--------|------|-------|
| `llm-frontend` | bridge | Open WebUI ↔ localhost |
| `llm-search` | bridge | Open WebUI ↔ SearXNG (interne) |
| `kimi-sandbox` | bridge internal | Isolation totale Kimi |

## Ports exposés

| Port | Service | Accessible depuis |
|------|---------|------------------|
| 11434 | Ollama | localhost uniquement |
| 3000 | Open WebUI | localhost uniquement |
| 11435 | Kimi (Docker) | localhost uniquement |
| 8080 | SearXNG | Interne Docker uniquement |
