# LLMs Locaux — Stack Dev + Sécurité
> Mac M-series 128 Go · Symfony · JavaScript · Python · Java · Bash · K8s · ELK · Pentest  
> Dernière mise à jour : 2026-05-08 — benchmarks réels mesurés

---

## Question fondamentale : LLM local ou Claude Code ?

**Réponse honnête : Claude Code est meilleur pour le code.**

Avant d'investir du temps dans un stack LLM local, comprendre la différence :

| Critère | Claude Code (Anthropic) | LLM local (Ollama) |
|---|---|---|
| Qualité code | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ (meilleur : devstral A-) |
| Contexte projet | ✅ Lit tous les fichiers, git, terminal | ❌ Prompt uniquement |
| Vitesse | Secondes | 39s à 663s par réponse |
| Confidentialité | ❌ Code envoyé à Anthropic | ✅ Rien ne quitte la machine |
| Coût | ~100€/mois | Électricité + amortissement machine |
| Setup | Zero | Installation, RAM, modèles |
| Quota | Limité | Illimité |

### Quand utiliser les LLMs locaux

**Seul vrai cas d'usage : code confidentiel qui ne peut pas quitter la machine.**

- Code client sous NDA
- Credentials, secrets, tokens dans le contexte
- Architecture propriétaire sensible
- Code soumis à des contraintes de souveraineté des données

Pour tout le reste (architecture, refactoring, debugging, génération) : **utilise Claude Code**, il est plus rapide, meilleur, et ne nécessite aucune maintenance.

### Autres usages secondaires légitimes

- **Veille et expérimentation** — comparer comment les modèles résolvent un problème
- **Open WebUI** — interface locale pour des collègues sans accès Claude
- **Scripts CI sans quota** — tâches répétitives simples (docblocks, formatage)
- **RAG sur codebase confidentielle** — via nomic-embed-text-v2-moe + Open WebUI

---

## Benchmark réel — 2026-05-08

Mission : microservice Symfony 7 fintech, 6 behaviors experts (DDD, SOLID, Sécurité OWASP 2026, Performance, Tests TDD, Observabilité OpenTelemetry). Machine : M5 Max 128 Go, isolation RAM garantie (un seul modèle à la fois).

### Résultats mesurés

| Modèle | DDD | SOLID | Sécu | Perf | Tests | OTel | **Score** | Durée | Lignes |
|---|---|---|---|---|---|---|---|---|---|
| `devstral-small-2` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **A-** | 292s | ~1 200 |
| `qwen3.6:27b` ⚠ | ✅ | ✅ | ✅ | ✅ | ⚠ | ✅ | **A-** | 557s | ~700 |
| `gemma4:31b` | ✅ | ✅ | ❌ | ✅ | ⚠ | ✅ | **B+** | 201s | ~460 |
| `phi4-reasoning:plus` | ✅ | ✅ | ⚠ | ⚠ | ⚠ | ✅ | **B** | 663s | ~1 070 |
| `codestral:22b` | ✅ | ✅ | ❌ | ⚠ | ❌ | ❌ | **C+** | 39s | ~50 |
| `llama3.3:70b` | ⚠ | ⚠ | ❌ | ❌ | ⚠ | ⚠ | **C** | 284s | ~560 |

> Analyse complète : `tests/analysis/benchmark-2026-05-08-round1.md`

### Enseignement clé

> **La spécialisation SWE-bench bat la taille des paramètres.**  
> devstral-small-2 (15B) > llama3.3:70b (70B) sur toute la grille.  
> La sécurité est le behavior le plus discriminant — seuls 2 modèles sur 6 l'implémentent correctement.

---

## Stack des modèles retenus

### Règle de sécurité des origines

| Niveau | Origine | Règle |
|---|---|---|
| ✅ Confiant | Mistral 🇫🇷, Meta 🇺🇸, Google 🇺🇸, Microsoft 🇺🇸, Nomic 🇺🇸 | Usage libre port 11434 |
| ⚠ Filtré | Alibaba 🇨🇳 — qwen3.6:27b | Sortie obligatoirement via `sandbox-guard.sh` |
| ❌ Exclu | DeepSeek, modèles cloud chinois non locaux | Ne jamais installer |

---

### sandbox-guard.sh — v2 (13 couches)

Filtre de sécurité niveau pentesteur. Basé sur la recherche offensive 2025-2026.

```bash
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh
# exit 0 = OK · exit 1 = SUSPECT · exit 2 = BLOQUÉ
```

```
┌────────┬────────────────────────────────────────────────────────────────────┬─────────────────────────────────────┐
│ Couche │                          Menace couverte                           │               Source                │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 1      │ ASCII smuggling U+E0000, homoglyphes cyrilliques                   │ arxiv 2603.00164, CamoLeak CVSS 9.6 │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 2      │ Base64 blobs, shellcode hex, eval+decode                           │ OWASP LLM01:2025                    │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 3      │ Reverse shells, fork bomb, curl|bash, persistence                  │ Red team 2026                       │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 4      │ ngrok, webhook.site, DNS exfil, netcat                             │ LLM Guard (Protect AI)              │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 5      │ API keys Anthropic/GitHub/AWS/Google, private keys                 │ Secrets scanners 2026               │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 6      │ /etc/shadow, .ssh, keychain macOS, /proc/keys                      │ Pentest OWASP                       │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 7      │ Python RCE, pickle, YAML unsafe, PHP passthru                      │ OWASP Top10                         │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 8      │ DAN mode, Mastermind multi-turn (95% ASR Qwen), temporal confusion │ arxiv 2601.05445, JBFuzz 99% ASR    │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 9      │ Typosquatting pip/npm, index HTTP, postinstall hooks               │ Supply chain 2026                   │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 10     │ docker.sock, cgroup escape, runc CVE-2025-31133/52881              │ Blaxel container escape 2026        │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 11     │ Entropie > 4.8 bits/char (payloads chiffrés)                       │ Steganography research 2025         │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 12     │ C2 connus, pastebin raw, data URI, javascript:                     │ NVIDIA Agentic AI security          │
├────────┼────────────────────────────────────────────────────────────────────┼─────────────────────────────────────┤
│ 13     │ xmrig, stratum, monero                                             │ Threat intel 2026                   │
└────────┴────────────────────────────────────────────────────────────────────┴─────────────────────────────────────┘
```

Logs persistants dans `~/.sandbox-guard/logs/`. Documentation complète : `docs/08-scripts.md`.

---

### devstral-small-2 · Mistral AI 🇫🇷
> **Missions autonomes multi-fichiers — le meilleur du stack**

| Attribut | Valeur |
|---|---|
| Taille disque | ~15 Go |
| RAM chargé | ~30 Go |
| Score benchmark | **A- (6/6 behaviors)** |
| SWE-bench | 65.8% |
| Spécialité | Refactoring agentique, scaffolding complet, Ansible |

**Points forts mesurés :**
- Seul modèle à couvrir spontanément les 6 behaviors en une passe
- 1 200 lignes PHP incluant Domain + Application + Infrastructure + API + Tests
- Sécurité JWT, rate limiting, HSTS/CSP implémentés sans rappel
- `releaseEvents()` correct, circuit breaker 50ms, cursor pagination

**Limites :**
- 292s de génération par réponse longue
- Bugs mineurs : NPE de précédence dans `ensureValidState()`, Outbox Pattern sans persistance DB

**Usage recommandé :** génération de scaffolding complet, refactoring multi-fichiers, missions avec code confidentiel qu'on ne peut pas envoyer à Claude.

```bash
make load MODEL=devstral-small-2
ollama run devstral-small-2
```

---

### qwen3.6:27b · Alibaba 🇨🇳 ⚠
> **Architecture DDD la plus avancée — filtre sandbox obligatoire**

| Attribut | Valeur |
|---|---|
| Taille disque | ~17 Go |
| RAM chargé | ~42 Go |
| Score benchmark | **A- (5/6 behaviors)** |
| Protocole obligatoire | `sandbox-guard.sh` sur toute sortie |

**Points forts mesurés :**
- Architecture DDD la plus sophistiquée : `TransactionId`/`TransactionStatus` comme VOs, `DomainEvent` base class
- `hrtime(true)` nanoseconde, `SET NX EX` anti-stampede Redis
- `$span->recordException()` + `SpanStatus::error()` — OTel le plus complet
- Alerte PromQL documentée par le modèle lui-même
- Sécurité via attributs Symfony (`#[IsGranted]`, `#[RateLimit]`) idiomatique

**Limites :**
- Filtre sandbox obligatoire — interdit sur secrets/code propriétaire
- Bugs de type PHP : wildcard import `use Namespace\*` invalide, `releaseEvents()` type incorrect
- 557s de génération

**Protocole d'usage :**
```bash
# Toujours passer par sandbox-guard (exit 0=OK, 1=SUSPECT, 2=BLOQUÉ)
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh

make load MODEL=qwen3.6:27b
```

**Interdit avec qwen :**
- ❌ Tokens, clés API, secrets, credentials
- ❌ Code propriétaire ou confidentiel
- ❌ Fichiers de configuration avec credentials
- ❌ Chemins hors du dossier de travail courant

---

### gemma4:31b · Google 🇺🇸
> **Performance & Observabilité — OTel réel, perf maximale**

| Attribut | Valeur |
|---|---|
| Taille disque | ~20 Go |
| RAM chargé | ~47 Go |
| Score benchmark | **B+ (4/6 behaviors)** |
| Contexte | 256K tokens |
| Spécialité | Agents, tool-calling, multimodal |

**Points forts mesurés :**
- Seul modèle à importer les vraies classes `OpenTelemetry\API\Trace\TracerInterface` et `Prometheus\CollectorRegistry`
- `timeout: 0.05` HttpClient réel (50ms), circuit breaker, cursor pagination
- `TTL_MAP` const Redis par RiskLevel, `SET NX EX` atomique
- `$version` optimistic locking, `releaseEvents()` correct
- `Idempotency-Key` (RFC 8615) enforced

**Limites :**
- JWT commenté (`// $this->denyAccessUnlessGranted`) — sécurité absente ❌
- Rate limiting absent
- Tests : Domain OK, integration absente

**Usage recommandé :** patterns de performance, observabilité production, code OTel/Prometheus de référence.

```bash
make load MODEL=gemma4:31b
```

---

### phi4-reasoning:plus · Microsoft 🇺🇸
> **Raisonnement architectural — Chain-of-Thought visible**

| Attribut | Valeur |
|---|---|
| Taille disque | ~9 Go |
| RAM chargé | ~20 Go |
| Score benchmark | **B (3/6 behaviors)** |
| Spécialité | Chain-of-thought, niveau o3-mini |

**Points forts mesurés :**
- 1 700 lignes de `<think>` visible avant le code — raisonnement explicite sur invariants DDD, SOLID, stratégie de tests
- Domain Layer exemplaire, SOLID strict, interfaces OTel complètes
- NullTracer/Logger/Metrics pour les tests — pattern correct

**Limites :**
- Sécurité partielle : interfaces JWT sans implémentation, rate limiting stub `return true`
- `htmlspecialchars()` utilisé à tort "contre les injections SQL"
- Tests : Domain OK, JWTTest placeholder `assertEquals(401, 401)`
- 663s — le plus lent

**Usage recommandé :** revue architecturale, décisions de design, enseignement des patterns. Le `<think>` est un avantage pour comprendre le "pourquoi", pas pour la génération directe.

```bash
make load MODEL=phi4-reasoning:plus
```

---

### codestral:22b · Mistral AI 🇫🇷
> **Coding ciblé rapide — Domain Layer en 39 secondes**

| Attribut | Valeur |
|---|---|
| Taille disque | ~14 Go |
| RAM chargé | ~30 Go |
| Score benchmark | **C+ (2/6 behaviors)** |
| Spécialité | PHP, JS, Python, Bash — coding quotidien |

**Points forts mesurés :**
- Le plus rapide : 39s pour une réponse complète
- Domain Layer DDD excellent : Aggregate, Value Objects, Strategy Pattern
- `final readonly class` partout, interfaces bien séparées

**Limites :**
- S'arrête au Domain Layer — pas d'Application/Infrastructure/API/Tests
- Sécurité, Observabilité, Performance : complètement absents

**Usage recommandé :** tâches atomiques ciblées — implémenter un Value Object, écrire une fonction précise, refactoriser une classe. Ne pas utiliser pour des missions full-stack autonomes.

```bash
make load MODEL=codestral:22b
```

---

### llama3.3:70b · Meta 🇺🇸
> **Généraliste 70B — documentation et revue conceptuelle uniquement**

| Attribut | Valeur |
|---|---|
| Taille disque | ~43 Go |
| RAM chargé | **102 Go** (100% GPU) |
| Score benchmark | **C (0/6 complets)** |

**Résultat benchmark surprenant :**
- 70B paramètres mais aucun behavior complet — tout est squelette avec `// ...`
- Redis sans TTL, JWT absent, events jamais collectés
- Le modèle lui-même admet : *"ce code n'est pas complet et nécessite probablement des modifications"*
- **La spécialisation SWE-bench > taille brute des paramètres**

**Limites réelles :**
- 102 Go de RAM pour du code de qualité inférieure à devstral (15 Go)
- Lent à charger, lent à décharger

**Usage recommandé :** architecture système (K8s, microservices), documentation technique, revue OWASP conceptuelle, explication de patterns. **Ne pas utiliser pour la génération de code production.**

```bash
make load MODEL=llama3.3:70b   # ⚠ mobilise 102 Go de RAM
```

---

### nomic-embed-text-v2-moe · Nomic 🇺🇸
> **Embeddings RAG — recherche sémantique dans le codebase**

| Attribut | Valeur |
|---|---|
| Taille disque | ~500 Mo |
| RAM chargé | ~1 Go |
| Dimensions | 768 |
| Spécialité | RAG multilingue, MoE |

**Usage :** indexer une codebase confidentielle pour Q&A via Open WebUI. Seul modèle ne produisant pas de texte — API embeddings uniquement.

```bash
curl http://localhost:11434/api/embeddings \
  -d '{"model":"nomic-embed-text-v2-moe","prompt":"Zero-Trust API Symfony CQRS"}'
```

---

## Quel modèle pour quelle tâche ?

| Tâche | Modèle recommandé | Pourquoi |
|---|---|---|
| Code confidentiel full-stack | `devstral-small-2` | Seul à couvrir 100% spontanément |
| DDD avancé / patterns complexes | `qwen3.6:27b` ⚠ | Architecture la plus élaborée — sandbox obligatoire |
| Performance & OTel | `gemma4:31b` | Seul à importer les vraies classes OTel/Prometheus |
| Revue architecturale | `phi4-reasoning:plus` | CoT visible — raisonnement explicite |
| Fonction / VO / code ciblé rapide | `codestral:22b` | 39s, Domain excellent |
| Documentation / revue K8s/OWASP | `llama3.3:70b` | Généraliste — pas pour le code production |
| RAG codebase confidentielle | `nomic-embed-text-v2-moe` | Embeddings uniquement |
| **Tout le reste** | **Claude Code** | Meilleur, plus rapide, contexte projet complet |

### Workflow combiné Claude Code + Ollama

```
Claude Code                          Ollama local
────────────────────────────────     ──────────────────────────────────
Analyse le projet entier         →   Génère le scaffolding (devstral)
Identifie les tâches             →   Implémente le code confidentiel
Valide et intègre le code        ←   Produit les 20 fichiers PHP
Lance les tests (make php-test)  →   (résultat validé par Claude Code)
Commit + git                         
```

**Exemple concret :** Claude Code conçoit l'architecture, devstral-small-2 génère le code sensible qui ne peut pas quitter la machine, Claude Code relit, teste et commite.

| Tâche | Qui fait quoi |
|---|---|
| Scaffolding multi-fichiers | `devstral-small-2` — génère, Claude Code intègre |
| Revue code propriétaire | `codestral:22b` — local = rien n'est envoyé à Anthropic |
| Décision architecturale SOLID/DDD | `phi4-reasoning:plus` — CoT visible, Claude Code valide |
| Embedding RAG codebase confidentielle | `nomic-embed-text-v2-moe` — indexe, Open WebUI interroge |
| Perf + OTel patterns | `gemma4:31b` — code de référence OTel/Prometheus |
| Patterns DDD avancés | `qwen3.6:27b` + sandbox-guard — architecture, Claude Code corrige |
| **Orchestration, contexte projet, git** | **Claude Code** — tout le reste |

---

## Budget RAM — chargement à la demande

Un seul modèle en RAM à la fois via `make load` / `make switch` / `make unload`.

| Modèle | RAM chargé | RAM libre (sur 128 Go) |
|---|---|---|
| nomic-embed-text-v2-moe | ~1 Go | 127 Go |
| phi4-reasoning:plus | ~20 Go | 108 Go |
| codestral:22b | ~30 Go | 98 Go |
| devstral-small-2 | ~30 Go | 98 Go |
| qwen3.6:27b | ~42 Go | 86 Go |
| gemma4:31b | ~47 Go | 81 Go |
| llama3.3:70b | **~102 Go** | 26 Go ⚠ |

```bash
make load MODEL=devstral-small-2   # charge + décharge l'actuel
make switch MODEL=gemma4:31b       # idem
make unload                        # libère toute la RAM
make status                        # état complet
```

---

## Commandes essentielles

```bash
# Charger / changer / décharger
make load MODEL=codestral:22b
make switch MODEL=devstral-small-2
make unload

# Modèles Alibaba — filtre obligatoire
ollama run qwen3.6:27b "question" | ./scripts/sandbox-guard.sh

# Benchmark complet
make test-full                              # tous les modèles
make test-full-model MODEL=gemma4:31b       # un seul

# Monitoring
make status
make monitor-live

# Env PHP isolé (PostgreSQL 16 + Redis 7 + RabbitMQ)
make php-up
make php-test
make php-down
```

---

## État des installations

```bash
ollama list     # modèles installés sur disque
ollama ps       # modèles chargés en RAM
make status     # vue complète
make models-check-new  # veille — nouveaux modèles disponibles
```

| Modèle | Origine | Confiance | Taille disque | Score réel |
|---|---|---|---|---|
| `codestral:22b` | Mistral 🇫🇷 | ✅ | ~14 Go | C+ |
| `devstral-small-2` | Mistral 🇫🇷 | ✅ | ~15 Go | **A-** |
| `phi4-reasoning:plus` | Microsoft 🇺🇸 | ✅ | ~9 Go | B |
| `gemma4:31b` | Google 🇺🇸 | ✅ | ~20 Go | B+ |
| `llama3.3:70b` | Meta 🇺🇸 | ✅ | ~43 Go | C |
| `qwen3.6:27b` | Alibaba 🇨🇳 | ⚠ sandbox | ~17 Go | **A-** |
| `nomic-embed-text-v2-moe` | Nomic 🇺🇸 | ✅ | ~500 Mo | RAG uniquement |
