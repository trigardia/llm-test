# Benchmark Développement — Niveau Expert

> **Usage** : Ce prompt est le filtre de qualité maximal du stack LLM.  
> Un modèle qui répond correctement à **80 %+** de ces exigences est prêt pour la production.  
> Testé sur : `codestral:22b`, `devstral-small-2`, `phi4-reasoning`, `gemma4:31b`, `llama3.3:70b`, `qwen3.6:27b`

---

## LE PROMPT (copier-coller directement dans le modèle)

---

Tu es un architecte senior DevSecOps avec 15 ans d'expérience en systèmes critiques (fintech, santé, défense). Tu appliques rigoureusement les 6 comportements d'expert suivants dans **chaque ligne de code** que tu produis :

1. **Architecture Clean + DDD** — Domain / Application / Infrastructure strictement séparés, Aggregates, Value Objects, Domain Events, Bounded Contexts
2. **SOLID sans compromis** — Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion — chaque principe justifié dans le code
3. **Sécurité Zero-Trust (OWASP Top 10 2026)** — Aucune donnée non validée, authentification multi-couche, moindre privilège, defense-in-depth
4. **Performance & Scalabilité** — Complexité algorithmique justifiée (O(n) explicite), stratégies de cache documentées, async quand pertinent, optimisation DB (index, N+1 éliminé)
5. **Tests TDD/BDD complets** — Unit → Integration → E2E, mutation testing mindset, 90 %+ coverage sur le Domain layer, tests de sécurité (SAST)
6. **Observabilité Production** — OpenTelemetry spans sur chaque opération critique, logs structurés JSON (ELK-ready), métriques Prometheus, alertes définies

---

## Mission

Implémente un **microservice Symfony 7 de scoring de risque transactionnel en temps réel** pour une plateforme de paiement B2B traitant **5 000 transactions par seconde** avec une latence p99 < 100ms.

### Contexte métier

La plateforme reçoit des demandes de paiement d'entreprises clientes. Chaque transaction doit être scorée en temps réel pour détecter les fraudes. Le score détermine si la transaction est : `APPROVED`, `REVIEW_REQUIRED`, ou `BLOCKED`. En cas de fraude détectée, un `FraudAlertTriggered` domain event est émis et consommé par un service de notification séparé.

### Contraintes techniques

- **Symfony 7.2** + PHP 8.3 (readonly properties, intersection types, fibers)
- **Redis 7** pour le cache des profils de risque (TTL stratégique par niveau de risque)
- **PostgreSQL 16** comme source de vérité (avec optimistic locking)
- **RabbitMQ** pour la publication des domain events
- **Architecture** : CQRS + Event Sourcing (les événements sont la source de vérité, pas l'état)
- **Auth** : JWT RS256 (clés asymétriques), scope `transactions:write`, expiry 15 min, refresh token rotation
- **Rate limiting** : 1 000 req/min par `client_id`, avec backpressure Redis-based

---

## Ce que tu dois produire

### 1. Domain Layer (le cœur — aucune dépendance externe)

```
Implémente :
- L'Aggregate `Transaction` avec ses invariants métier :
  * Un montant ne peut pas être négatif ou zéro
  * Une transaction ne peut pas être approuvée si le compte source est suspendu
  * Le statut ne peut transitionner que selon : PENDING → APPROVED|REVIEW_REQUIRED|BLOCKED
- Le Value Object `RiskScore` (0-1000, immuable, avec méthode `level(): RiskLevel`)
- L'enum `RiskLevel` : LOW (0-300), MEDIUM (301-700), HIGH (701-900), CRITICAL (901-1000)
- Le Value Object `Money` (montant + devise ISO 4217, avec conversion sécurisée)
- Les Domain Events : `TransactionSubmitted`, `RiskScoreCalculated`, `FraudAlertTriggered`
- L'interface `RiskScoringStrategy` (Strategy Pattern — OCP appliqué)
- L'interface `TransactionRepository` (DIP — le Domain ne connaît pas PostgreSQL)
```

### 2. Application Layer (orchestration — use cases)

```
Implémente le Command Handler :
- `SubmitTransactionCommand` + `SubmitTransactionCommandHandler`
  * Valide la commande (Command Validation séparée du Domain)
  * Vérifie le cache Redis (profil de risque du client) avant d'appeler le Domain
  * Orchestre : Repository.findById → Transaction.submit() → RiskScoring → Repository.save() → EventBus.publish()
  * Idempotent (même transaction_id → même résultat, sans double traitement)
  * OpenTelemetry span sur toute l'opération avec attributs : client_id, amount, risk_score, latency_ms

Implémente le Query Handler :
- `GetRiskReportQuery` + `GetRiskReportQueryHandler`
  * Read model séparé (CQRS — la lecture ne passe pas par l'Aggregate)
  * Cache Redis avec TTL 300s pour les rapports non-critiques, 30s pour CRITICAL
```

### 3. Infrastructure Layer

```
Implémente :
- `DoctrineTransactionRepository` (implémente TransactionRepository du Domain)
  * Optimistic locking avec version column
  * Index composite sur (client_id, created_at) documenté et justifié
  * Requête paginée cursor-based (pas offset — O(1) vs O(n))

- `RedisRiskProfileCache` avec stratégie de cache :
  * Cache-aside pattern
  * TTL variable selon RiskLevel (LOW: 3600s, MEDIUM: 600s, HIGH: 60s, CRITICAL: 0s = pas de cache)
  * Gestion des cache stampedes (probabilistic early expiration ou lock Redis)

- `RabbitMQEventBus` (publie les domain events de façon transactionnelle — Outbox Pattern obligatoire)
  * L'event est d'abord persisté en DB (table outbox) dans la même transaction
  * Un worker séparé publie depuis l'outbox (at-least-once delivery)
  * Déduplication côté consommateur via event_id UUID

- `MLRiskScoringStrategy` (implémente RiskScoringStrategy)
  * Appelle un service externe ML via HTTP avec circuit breaker (Symfony HttpClient + retry)
  * Fallback sur `HeuristicRiskScoringStrategy` si le service ML est down
  * Timeout : 50ms max (pour respecter le p99 < 100ms total)
```

### 4. API Layer (Controller Symfony)

```
Endpoint : POST /api/v1/transactions

Implémente :
- Validation d'entrée stricte (Symfony Validator, pas de données brutes dans le Domain)
- Authentification JWT RS256 avec vérification du scope `transactions:write`
- Rate limiting Redis-based (1 000 req/min par client_id) avec header Retry-After
- Idempotency-Key header support (RFC 8615)
- CORS restrictif (liste blanche, pas de wildcard)
- Security headers complets (HSTS, CSP, X-Frame-Options, etc.)
- Réponse standardisée JSON:API ou RFC 9457 (Problem Details)

Structure de réponse succès (HTTP 202 Accepted — async scoring) :
{
  "transaction_id": "uuid-v7",
  "status": "PENDING",
  "estimated_scoring_ms": 45,
  "_links": { "self": "/api/v1/transactions/{id}", "report": "/api/v1/transactions/{id}/risk-report" }
}

Réponse erreur (RFC 9457) :
{
  "type": "https://api.example.com/errors/rate-limit-exceeded",
  "title": "Rate Limit Exceeded",
  "status": 429,
  "detail": "1000 requests per minute exceeded for client_id: acme-corp",
  "retry_after": 42
}
```

### 5. Tests (TDD — les tests définissent le comportement)

```
Écris les tests suivants :

Unit Tests (Domain — pas de mocks de framework) :
- `TransactionTest` : tous les invariants métier (transitions invalides, montants invalides, etc.)
- `RiskScoreTest` : limites de l'enum, calculs de level()
- `MoneyTest` : conversions de devise, opérations arithmétiques, égalité par valeur

Integration Tests :
- `SubmitTransactionCommandHandlerTest` :
  * Happy path : transaction approuvée, event publié, cache invalidé
  * Scénario fraude : CRITICAL score → FraudAlertTriggered émis
  * Idempotence : même command_id → même résultat, pas de double event
  * Circuit breaker : ML service down → fallback heuristique actif
  * Rate limit : 1001e requête → 429 avec Retry-After correct

Security Tests :
- JWT expiré → 401 avec message non-verbeux (pas de stack trace)
- JWT scope insuffisant → 403
- Injection SQL via transaction description → 400 + log de sécurité ELK
- Payload > 10KB → 413
- Fuzz testing sur les champs montant (NaN, Infinity, -0, nombres négatifs en string)
```

### 6. Observabilité (Production-Ready)

```
Ajoute dans le CommandHandler :

// OpenTelemetry
$span = $this->tracer->spanBuilder('transaction.submit')
    ->setAttribute('client_id', $command->clientId)
    ->setAttribute('amount_cents', $command->amountCents)
    ->setAttribute('currency', $command->currency)
    ->startSpan();

// Log structuré ELK-ready
$this->logger->info('transaction.submitted', [
    'transaction_id' => $transactionId,
    'client_id' => $command->clientId,
    'risk_score' => $riskScore->value(),
    'risk_level' => $riskScore->level()->name,
    'scoring_strategy' => $strategy::class,
    'latency_ms' => $latency,
    'cache_hit' => $cacheHit,
    'trace_id' => $span->getContext()->getTraceId(),
]);

// Métriques Prometheus
$this->metrics->histogram(
    'transaction_scoring_duration_ms',
    $latency,
    ['risk_level' => $riskScore->level()->name, 'strategy' => 'ml|heuristic']
);
$this->metrics->counter('transaction_submitted_total', ['status' => $transaction->status()->name]);

// Alerte : si p99 > 80ms → warning log (pre-alert avant breach SLA)
if ($latency > 80) {
    $this->logger->warning('transaction.scoring.latency_warning', [
        'latency_ms' => $latency,
        'sla_limit_ms' => 100,
        'margin_ms' => 100 - $latency,
    ]);
}
```

---

## Critères d'évaluation automatique

Le modèle doit, **sans qu'on lui rappelle**, inclure spontanément :

| Comportement | Signal attendu |
|---|---|
| **DDD** | Aggregate avec invariants enforced, Value Objects immuables, Domain Events avec payload métier |
| **SOLID** | Au moins 3 interfaces dans le Domain, Strategy Pattern pour le scoring, Repository abstrait |
| **Sécurité** | Validation d'entrée avant le Domain, JWT scope check, rate limiting, headers sécurité, logs sans données sensibles |
| **Performance** | Mention de la complexité O(), cursor-based pagination, cache TTL différencié par risque, circuit breaker avec timeout 50ms |
| **Tests** | Tests qui échouent en premier (TDD), scénarios edge cases, tests de sécurité, test de l'idempotence |
| **Observabilité** | Span OpenTelemetry sur le chemin critique, logs structurés avec trace_id, métrique avec labels utiles |

**Score A** : 6/6 comportements spontanés → modèle production-ready  
**Score B** : 4-5/6 → bon modèle, nécessite supervision sur les points manquants  
**Score C** : 2-3/6 → assistance viable sur tâches ciblées uniquement  
**Score D** : 0-1/6 → ne pas utiliser pour du code critique

---

## Variantes de test par modèle

Pour différencier les modèles sur des dimensions spécifiques, utilise ces variantes en complément :

### Test Reasoning (phi4-reasoning, llama3.3:70b)
> "Avant d'écrire une ligne de code, explique ton raisonnement architectural : pourquoi CQRS ici ? Quelles sont les trade-offs vs une architecture CRUD simple ? Quand l'Event Sourcing devient-il un anti-pattern ?"

### Test Sécurité (llama3.3:70b, gemma4:31b)
> "Effectue une threat modeling STRIDE complète sur ce microservice. Identifie les 5 vecteurs d'attaque les plus critiques et propose une contre-mesure pour chacun. Inclus les attaques sur l'Outbox Pattern."

### Test Refactoring Agentique (devstral-small-2, codestral:22b)
> "Voici un Controller Symfony de 200 lignes qui mélange validation, logique métier, accès DB et réponse HTTP. Refactorise-le en respectant la Clean Architecture. Montre le before/after et justifie chaque extraction."

### Test Coding Pur (codestral:22b, qwen3.6:27b)
> "Implémente uniquement le Value Object `Money` avec : addition, soustraction, multiplication par scalaire, conversion de devise (taux en mémoire), égalité par valeur, immutabilité stricte, et tous les tests unitaires PHPUnit. PHP 8.3, readonly properties."

### Test Embedding/RAG (nomic-embed-text-v2-moe)
> Ce modèle ne produit pas de texte — tester via API embeddings uniquement :
> `curl http://localhost:11434/api/embeddings -d '{"model":"nomic-embed-text-v2-moe","prompt":"Zero-Trust API Gateway Symfony CQRS Event Sourcing"}'`
> Vérifier : vecteur 768 dimensions, valeurs entre -1 et 1, temps de réponse < 200ms

---

## Comment lancer le benchmark

```bash
# Test complet tous les modèles
make test

# Test un modèle spécifique
make test-model MODEL=codestral:22b
make test-model MODEL=devstral-small-2
make test-model MODEL=phi4-reasoning
make test-model MODEL=gemma4:31b
make test-model MODEL=llama3.3:70b
make test-model MODEL=qwen3.6:27b  # filtré via sandbox-guard.sh

# Test manuel avec ce prompt
make load MODEL=codestral:22b
ollama run codestral:22b < tests/prompts/dev-benchmark-ultimate.md

# Test qwen avec filtre
make load MODEL=qwen3.6:27b
ollama run qwen3.6:27b "$(cat tests/prompts/dev-benchmark-ultimate.md)" | ./scripts/sandbox-guard.sh
```

---

## Résultats réels (mesurés — `make test-full-model`) — Round 1 complet 2026-05-08

| Modèle | DDD | SOLID | Sécu | Perf | Tests | Obs | Score | Durée | Lignes |
|---|---|---|---|---|---|---|---|---|---|
| `codestral:22b` | ✅ | ✅ | ❌ | ⚠ | ❌ | ❌ | **C+** | 39s | ~50 |
| `devstral-small-2` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **A-** | 292s | ~1 200 |
| `phi4-reasoning:plus` | ✅ | ✅ | ⚠ | ⚠ | ⚠ | ✅ | **B** | 663s | ~1 070 |
| `gemma4:31b` | ✅ | ✅ | ❌ | ✅ | ⚠ | ✅ | **B+** | 201s | ~460 |
| `llama3.3:70b` | ⚠ | ⚠ | ❌ | ❌ | ⚠ | ⚠ | **C** | 284s | ~560 |
| `qwen3.6:27b` ⚠ | ✅ | ✅ | ✅ | ✅ | ⚠ | ✅ | **A-** | 557s | ~700 |

### Classement final

```
A-  devstral-small-2    6/6 complets — seul 100% sans supervision (15 Go)
A-  qwen3.6:27b ⚠       5/6 — architecture DDD la plus avancée (17 Go — sandbox obligatoire)
B+  gemma4:31b          4/6 — OTel réel, anti-stampede Redis, perf maximale (20 Go)
B   phi4-reasoning:plus 3/6 — CoT visible, fort sur DDD/SOLID/Obs (9 Go)
C+  codestral:22b       2/6 — Domain uniquement, très rapide 39s (14 Go)
C   llama3.3:70b        0/6 complets — squelettes avec // ... (43 Go)
```

### Notes par modèle (2026-05-08)

**codestral:22b** — Domain Layer uniquement (~50 lignes, 39s). Fort sur DDD et SOLID. Aucune couche Sécurité/Tests/Observabilité. Usage : tâches ciblées atomiques (un VO, une fonction).

**devstral-small-2** — Seul à couvrir 100% spontanément (~1 200 lignes, 292s). Tous les layers présents. Bugs mineurs : NPE dans `ensureValidState()`, idempotence incomplète. Usage : missions autonomes multi-fichiers.

**phi4-reasoning:plus** — Chain-of-thought visible (~1 700 lignes `<think>` + 1 070 lignes code, 663s). Architecture DDD solide. Sécurité partielle (JWT interfaces sans implémentation, rate limiting stub). Usage : conception architecturale, revue de design.

**gemma4:31b** — Meilleure observabilité du stack : seul à importer les vraies classes `OpenTelemetry\API` et `Prometheus\CollectorRegistry`. `timeout: 0.05` HttpClient réel. JWT commenté (`// $this->denyAccessUnlessGranted`). Usage : performance engineering, couche observabilité.

**llama3.3:70b** — Surprise négative : 70B paramètres mais 0/6 behaviors complets. Squelettes avec `// ...`, Redis sans TTL, JWT absent. S'auto-évalue : *"ce code n'est pas complet"*. La spécialisation SWE > taille brute. Usage : architecture système, documentation, revue conceptuelle.

**qwen3.6:27b** ⚠ — Architecture la plus avancée : `TransactionId`/`TransactionStatus` comme VOs distincts, `DomainEvent` base class, `hrtime(true)` nanoseconde, `SET NX EX` anti-stampede, `$span->recordException()`. Filtre `sandbox-guard.sh` obligatoire. Usage : DDD avancé, patterns complexes — validation humaine impérative avant production.

### Enseignement clé

> La spécialisation SWE-bench bat la taille des paramètres.  
> devstral-small-2 (15B) > llama3.3:70b (70B) sur toute la grille.  
> La sécurité est le behavior le plus discriminant — seuls 2/6 modèles l'implémentent complètement.

---

*Prompt créé le 2026-05-08 — Round 1 mesuré le 2026-05-08*  
*Stack : Symfony 7 · PHP 8.3 · Redis 7 · PostgreSQL 16 · RabbitMQ · K8s · ELK · OpenTelemetry*  
*Analyse complète : `tests/analysis/benchmark-2026-05-08-round1.md`*
