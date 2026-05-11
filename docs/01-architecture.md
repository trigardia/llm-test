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
│   │  codestral:22b · devstral-small-2 · llama3.3:70b       │  │
│   │  phi4-reasoning · phi4-reasoning · gemma4:31b               │  │
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
│   │  qwen3.6:27b — Port 11435      │                       │
│   │  Réseau : sandbox-net (isolé) │                       │
│   │  Sortie filtrée par sandbox-guard│                      │
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
| `sandbox-net` | bridge internal | Isolation totale qwen3.6:27b |

## Ports exposés

| Port | Service | Accessible depuis |
|------|---------|------------------|
| 11434 | Ollama | localhost uniquement |
| 3000 | Open WebUI | localhost uniquement |
| 11435 | qwen3.6:27b (sandbox Docker) | localhost uniquement |
| 8080 | SearXNG | Interne Docker uniquement |

> **Note** : Kimi K2.6 (Moonshot AI) est un service **cloud uniquement** — non utilisé dans ce stack local.
