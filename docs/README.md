# Documentation — Stack LLM Local

> Infrastructure LLMs locaux sécurisée sur MacBook Pro M5 Max (128 Go RAM)
> Stack : Ollama · Open WebUI · SearXNG · Docker

---

## Table des matières

| # | Document | Description |
|---|----------|-------------|
| 01 | [Architecture](01-architecture.md) | Vue d'ensemble, schémas, choix techniques |
| 02 | [Installation](02-installation.md) | Guide pas à pas, prérequis, démarrage |
| 03 | [Modèles LLM](03-modeles.md) | Catalogue, benchmarks, RAM, cas d'usage |
| 04 | [Sécurité](04-securite.md) | Politique, sandbox qwen3.6:27b, règles absolues |
| 05 | [Interfaces](05-interfaces.md) | Open WebUI, SearXNG — configuration et usage |
| 06 | [Usage quotidien](06-usage.md) | Commandes, workflows, bonnes pratiques |
| 07 | [Makefile](07-makefile.md) | Toutes les commandes `make` documentées |
| 08 | [Scripts](08-scripts.md) | Scripts shell — rôle, usage, paramètres |

---

## Environnement cible

| Composant | Détail |
|-----------|--------|
| Machine | MacBook Pro M5 Max |
| RAM | 128 Go (mémoire unifiée) |
| OS | macOS |
| Runtime LLM | Ollama (natif macOS) |
| Interfaces | Docker |

## Accès rapide

| Service | URL | Description |
|---------|-----|-------------|
| Open WebUI | http://localhost:3000 | Interface principale (ChatGPT-like) |
| SearXNG | Interne uniquement | Moteur de recherche privé (API) |

---

*Documentation maintenue par l'équipe — mise à jour continue.*
