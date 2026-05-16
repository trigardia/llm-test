# Benchmark LLM Local — Round 1 : codestral:22b vs devstral-small-2

**Date** : 2026-05-08  
**Machine** : MacBook Pro M5 Max — 128 Go RAM unifiée  
**Environnement** : Ollama local (port 11434) — modèle seul en RAM, isolation garantie  
**Benchmark** : Mission microservice Symfony 7 fintech — scoring de risque transactionnel (5 000 TPS, p99 < 100ms)

---

## Méthodologie

### Prompt benchmark (mission-only — sans méta-instructions)

Le modèle reçoit un prompt unique demandant l'implémentation complète d'un microservice Symfony 7 couvrant **6 behaviors d'expert** simultanément :

1. **Architecture Clean + DDD** — Aggregates, Value Objects, Domain Events, Bounded Contexts
2. **SOLID sans compromis** — Strategy Pattern, DIP, interfaces dans le Domain
3. **Sécurité Zero-Trust (OWASP 2026)** — JWT RS256, rate limiting Redis, validation stricte
4. **Performance & Scalabilité** — Circuit breaker 50ms, cache TTL par niveau de risque, cursor pagination
5. **Tests TDD/BDD** — Unit (Domain) + Integration (CommandHandler) + Security
6. **Observabilité Production** — OpenTelemetry spans, logs structurés ELK, métriques Prometheus

### Isolation RAM

- `ollama stop` de tous les modèles avant chaque test
- Vérification `ollama ps` vide + attente de libération effective
- RAM confirmée disponible : ~80 Go avant chaque test
- Un seul modèle chargé à la fois (keep_alive natif Ollama)

### Grille d'évaluation

| Score | Critère |
|---|---|
| ✅ | Comportement produit **spontanément** sans rappel |
| ⚠ | Comportement **partiel** ou incomplet |
| ❌ | Comportement **absent** |

---

## Modèle 1 — codestral:22b (Mistral AI 🇫🇷)

| Paramètre | Valeur |
|---|---|
| Origine | Mistral AI 🇫🇷 |
| Taille | ~14 Go (Q4_0) |
| Spécialité | Code quotidien PHP/JS/Python/Bash |
| Durée de réponse | **39 secondes** |
| Lignes produites | **~50 lignes** |

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ✅ | Aggregate `Transaction`, VO `RiskScore` + `Money` readonly, interfaces `RiskScoringStrategy` + `TransactionRepository`, Domain Events |
| SOLID | ✅ | Strategy Pattern (OCP), DIP via Repository interface, SRP par classe |
| Sécurité Zero-Trust | ❌ | **Absent** — 0 mention de JWT, rate limiting, validation, headers sécurité |
| Performance | ⚠ | Patterns cités en texte (timeout 50ms, cache TTL) mais **0 code implémenté** |
| Tests TDD/BDD | ❌ | **Absent** — 0 ligne PHPUnit |
| Observabilité | ❌ | **Absent** — 0 span OTel, 0 log structuré |

**Score global : C+ (2/6)**

### Code produit

```php
// Transaction Aggregate (extrait)
final class Transaction
{
    private TransactionStatus $status = TransactionStatus::PENDING;

    public function submit(): void
    {
        if ($this->isSuspendedAccount) {
            throw new InvalidTransactionStateException('...');
        }
        $this->status = TransactionStatus::SUBMITTED; // ← bug : statut non spécifié
    }
}

// RiskScore Value Object
final readonly class RiskScore
{
    public function __construct(private readonly int $value) {}

    public function level(): RiskLevel
    {
        return match (true) {
            $this->value <= 300 => RiskLevel::LOW,
            $this->value <= 700 => RiskLevel::MEDIUM,
            $this->value <= 900 => RiskLevel::HIGH,
            default             => RiskLevel::CRITICAL,
        };
    }
}

// Enum RiskLevel
enum RiskLevel: string {
    case LOW      = 'low';
    case MEDIUM   = 'medium';
    case HIGH     = 'high';
    case CRITICAL = 'critical';
}
```

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| `TransactionStatus::SUBMITTED` | Moyen | Statut inventé absent de la spec (PENDING → APPROVED\|REVIEW_REQUIRED\|BLOCKED) |
| `FraudAlertTriggered` non publié | Élevé | Event instancié mais jamais envoyé sur le bus |
| Domain Events manquants | Moyen | `pullDomainEvents()` absent — pas de mécanisme de publication |

### Verdict

Codestral:22b **excelle sur le Domain Layer** — la partie la plus exigeante conceptuellement (DDD + SOLID). Mais il s'arrête là. Pas de couche Application, pas d'Infrastructure, pas de tests, pas de sécurité.

**Usage optimal** : tâches ciblées et atomiques — implémenter un Value Object, écrire une fonction précise, refactoriser une classe. Ne pas utiliser pour des missions autonomes multi-layers.

---

## Modèle 2 — devstral-small-2 (Mistral AI 🇫🇷)

| Paramètre | Valeur |
|---|---|
| Origine | Mistral AI 🇫🇷 |
| Taille | ~15 Go (Q4_0) |
| Spécialité | Refactoring agentique multi-fichiers, SWE-bench 65.8% |
| Durée de réponse | **292 secondes (4m52s)** |
| Lignes produites | **~1 200 lignes** |

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ✅ | `final readonly class` partout, `pullDomainEvents()`, ISO 4217 regex sur `Money`, `ensureValidState()` |
| SOLID | ✅ | `CommandBusInterface`, `QueryBusInterface`, `RateLimiterInterface`, `EventBus` abstraits — 0 couplage concret dans le Domain |
| Sécurité Zero-Trust | ✅ | `#[IsGranted('ROLE_TRANSACTIONS_WRITE')]`, rate limit → 429 + `Retry-After`, payload > 10Ko → 413, RFC 9457 |
| Performance | ✅ | Timeout 50ms ML (`'timeout' => 0.05`), fallback `HeuristicRiskScoringStrategy`, TTL Redis par niveau (3600/600/60/0s) |
| Tests TDD/BDD | ✅ | Unit Domain + Integration (happy path, CRITICAL fraud, idempotence) + Security (401/403/429/413) |
| Observabilité | ✅ | Spans OTel sur **chaque** opération (cache.get, event.publish, ml_scoring, api…), `trace_id` dans tous les logs |

**Score global : A- (6/6 — avec réserves mineures)**

### Code produit (extraits clés)

```php
// Money Value Object — ISO 4217 + immutabilité stricte
final readonly class Money
{
    public function __construct(int $amount, string $currency)
    {
        if ($amount <= 0) throw new \InvalidArgumentException("Amount must be positive");
        if (!preg_match('/^[A-Z]{3}$/', $currency))
            throw new \InvalidArgumentException("Currency must be ISO 4217 format");
    }
    public function equals(Money $other): bool {
        return $this->amount === $other->amount && $this->currency === $other->currency;
    }
}

// CommandHandler — pipeline complet avec OTel + cache + events
public function __invoke(SubmitTransactionCommand $command): void
{
    $span = $this->tracer->spanBuilder('transaction.submit')
        ->setAttribute('client_id', $command->clientId)
        ->setAttribute('amount_cents', $command->amountCents)
        ->startSpan();
    $startTime = microtime(true);
    try {
        $cachedScore = $this->cache->get($command->clientId); // cache-aside
        $transaction = $this->repository->findById($command->transactionId) 
            ?? new Transaction(/* ... */);
        $transaction->submit();
        $riskScore = $this->scoringStrategy->calculateRiskScore($transaction);
        $transaction->calculateRiskScore($riskScore);
        $this->repository->save($transaction);
        foreach ($transaction->pullDomainEvents() as $event) {
            $this->eventBus->publish($event);
        }
        $this->cache->set($command->clientId, $riskScore->value(),
            $this->getCacheTTL($riskScore->level())); // TTL dynamique
        $latency = (microtime(true) - $startTime) * 1000;
        $this->logger->info('transaction.submitted', [
            'risk_score'  => $riskScore->value(),
            'risk_level'  => $riskScore->level()->name,
            'latency_ms'  => $latency,
            'cache_hit'   => $cachedScore !== null,
            'trace_id'    => $span->getContext()->getTraceId(),
        ]);
        $this->metrics->histogram('transaction_scoring_duration_ms', $latency,
            ['risk_level' => $riskScore->level()->name]);
    } finally {
        $span->end(); // span toujours fermé même en cas d'exception
    }
}

// MLRiskScoringStrategy — circuit breaker 50ms + fallback
$response = $this->httpClient->request('POST', $this->mlServiceUrl, [
    'timeout' => 0.05, // 50ms max
]);
// Fallback automatique si exception
return $this->fallbackStrategy->calculateRiskScore($transaction);

// Tests sécurité
public function testRateLimitExceeded(): void
{
    $this->rateLimiter->method('isRateLimited')->willReturn(true);
    $this->rateLimiter->method('getRetryAfter')->willReturn(60);
    $response = $this->controller->submitTransaction(/* ... */);
    $this->assertEquals(429, $response->getStatusCode());
    $this->assertEquals('60', $response->headers->get('Retry-After'));
}
```

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| NPE dans `ensureValidState()` | Élevé | `$this->riskScore !== null && val < 0 \|\| val > 1000` — précédence incorrecte → NPE quand `riskScore` est null |
| Outbox Pattern absent | Moyen | RabbitMQ publie directement sans persistence DB préalable (risque at-least-once non garanti) |
| Idempotence incomplète | Moyen | Handler re-score une transaction existante au lieu de retourner le résultat déjà calculé |
| Security headers partiels | Faible | HSTS/CSP/X-Frame-Options mentionnés dans la spec mais absents du code du controller |
| Cursor pagination absente | Faible | `findByClientId` utilise `LIMIT 100` au lieu de cursor-based O(1) |

### Verdict

devstral-small-2 est **le seul modèle du stack capable de produire une implémentation complète en une seule passe**. Tous les 6 behaviors sont présents spontanément. Les bugs détectés sont réels mais mineurs — exactement ce qu'on attend d'un modèle 15B : structurellement correct, quelques détails d'implémentation à vérifier.

**Usage optimal** : missions autonomes multi-fichiers, refactoring de base de code entière, génération de scaffolding complet. Supervision humaine requise sur les edge cases sécurité et les patterns transactionnels avancés.

---

## Comparaison directe

| Critère | codestral:22b | devstral-small-2 |
|---|---|---|
| Taille modèle | 14 Go | 15 Go |
| Durée | 39s | 292s |
| Lignes produites | ~50 | ~1 200 |
| Layers couverts | Domain only | Domain + App + Infra + API + Tests |
| Score 6 behaviors | **C+ (2/6)** | **A- (6/6)** |
| DDD | ✅ | ✅ |
| SOLID | ✅ | ✅ |
| Sécurité | ❌ | ✅ |
| Performance | ⚠ | ✅ |
| Tests | ❌ | ✅ |
| Observabilité | ❌ | ✅ |
| Bugs critiques | 2 | 1 |
| Usage recommandé | Tâches ciblées | Missions autonomes |

### Observation clé

Pour **1 Go de RAM supplémentaire** (14 → 15 Go) et **4 minutes de plus**, devstral-small-2 produit 24× plus de code couvrant 3× plus de behaviors. Le delta de qualité est disproportionné par rapport à la différence de taille — signe que la spécialisation SWE (training sur des dépôts GitHub réels) fait toute la différence.

---

## Modèle 3 — phi4-reasoning:plus (Microsoft 🇺🇸)

| Paramètre | Valeur |
|---|---|
| Origine | Microsoft 🇺🇸 |
| Taille | ~9 Go (Q4_0) |
| Spécialité | Raisonnement chain-of-thought — niveau o3-mini |
| Durée de réponse | **663 secondes (11m03s)** |
| Lignes produites | **~1 070 lignes** (+ ~1 700 lignes de raisonnement `<think>`) |

### Particularité : Chain-of-Thought visible

phi4-reasoning:plus expose son raisonnement interne dans un bloc `<think>` avant de produire le code.  
Environ **1 700 lignes de réflexion** précèdent le code — exploration des invariants DDD, des patterns SOLID, de la stratégie de tests.  
Ce comportement est unique dans le stack : les autres modèles produisent directement du code.

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ✅ | Aggregate `Transaction` + VO `Money`/`RiskScore` readonly, Domain Events avec `eventId`/`setEventId()`, interfaces `RiskScoringStrategy` + `TransactionRepository`, `getRecordedEvents()` |
| SOLID | ✅ | Strategy Pattern (ML + Heuristic), DIP via `TransactionRepository`, OCP + interfaces OTel (`TracerInterface`, `LoggerInterface`, `MetricsInterface`), NullTracer/Logger/Metrics pour tests |
| Sécurité Zero-Trust | ⚠ | Interfaces JWT (`TokenExtractorInterface`, `SecurityContextInterface`) + scope check `transactions:write` + HSTS/CSP/X-Frame-Options ✅ — mais rate limiting **stub hardcodé** (`return true`) ❌ et `htmlspecialchars()` utilisé à tort "contre les injections SQL" |
| Performance | ⚠ | TTL Redis par niveau correct (3600/600/60/0s) ✅, circuit breaker avec `failureCount` ✅ — timeout 50ms **absent** (pas de vraie requête HTTP), cursor pagination en interface uniquement (`array_slice` en impl) |
| Tests TDD/BDD | ⚠ | Unit Domain (`MoneyTest`, `RiskScoreTest`, `TransactionTest`) ✅, Integration handler ✅ — mais `JWTTest` placeholder (`assertEquals(401, 401)`) ❌, `testIdempotence()` brisé (double `submit()` → exception), `testRateLimit429` inutile (`assertTrue(true)`) |
| Observabilité | ✅ | Span OTel `transaction.submit` ✅, logs structurés complets (`transaction_id`, `risk_level`, `latency_ms`, `cache_hit`, `trace_id`) ✅, histogram Prometheus ✅, `span.end()` dans les deux chemins (succès + exception) ✅ |

**Score global : B (3 complets + 3 partiels)**

### Code produit (extraits clés)

```php
// RiskLevel enum avec fromScore() et frontières précises
enum RiskLevel: int {
    case LOW = 0; case MEDIUM = 300; case HIGH = 700; case CRITICAL = 901;

    public static function fromScore(int $score): self {
        if ($score >= 0 && $score <= 300) return self::LOW;
        elseif ($score >= 301 && $score <= 700) return self::MEDIUM;
        elseif ($score >= 701 && $score <= 900) return self::HIGH;
        elseif ($score >= 901 && $score <= 1000) return self::CRITICAL;
        throw new \InvalidArgumentException("Risk score out of valid range (0-1000): " . $score);
    }
}

// Transaction : machine à états explicite, invariant compte suspendu, events
class Transaction {
    private const STATUS_PENDING = 'PENDING';
    private const STATUS_APPROVED = 'APPROVED';
    private const STATUS_REVIEW_REQUIRED = 'REVIEW_REQUIRED';
    private const STATUS_BLOCKED = 'BLOCKED';

    public function submit(): void {
        if ($this->status !== self::STATUS_PENDING)
            throw new \Exception("Transaction is not in PENDING state.");
        if ($this->isAccountSuspended)
            throw new \Exception("Cannot submit transaction; associated account is suspended.");
        $this->recordEvent(new TransactionSubmittedEvent($this));
    }

    public function applyRiskScore(RiskScore $riskScore): void {
        // Transitions : CRITICAL → BLOCKED, HIGH → REVIEW_REQUIRED, LOW/MEDIUM → APPROVED
        switch ($riskScore->level()) {
            case RiskLevel::CRITICAL:
                $this->status = self::STATUS_BLOCKED;
                $this->recordEvent(new FraudAlertTriggeredEvent($this)); break;
            // ...
        }
        $this->recordEvent(new RiskScoreCalculatedEvent($this, $riskScore));
    }
}

// Outbox pattern + déduplication via event_id
class RabbitMQEventBus {
    public function publish(object $event): void {
        if (!isset($event->eventId) || $event->eventId === '') {
            $eventId = uniqid(get_class($event) . '_', true);
            if (method_exists($event, 'setEventId')) $event->setEventId($eventId);
        }
        $this->outbox[] = $event;
    }
    public function flush(): void { /* at-least-once vers RabbitMQ */ }
}

// Interfaces OTel complètes + NullTracer pour les tests
class NullTracer implements TracerInterface {
    public function spanBuilder(string $name): SpanBuilderInterface {
        return new class($name) implements SpanBuilderInterface, SpanInterface {
            public function setAttribute(string $key, mixed $value): self { return $this; }
            public function startSpan(): SpanInterface { return $this; }
            public function end(): void {}
            public function getContext(): array { return ['trace_id' => 'dummy']; }
        };
    }
}

// TransactionRepository avec pagination cursor-based en interface
interface TransactionRepository {
    public function findByClientId(string $clientId, ?string $cursor = null, int $limit = 50): array;
}
```

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| `getRecordedEvents()` non consommateur | Élevé | Les events ne sont jamais vidés — `getRecordedEvents()` retourne le tableau sans le vider. En cas de deuxième appel au handler sur la même transaction, tous les events seraient republés |
| `testIdempotence()` brisé | Élevé | Le test appelle `handle()` deux fois avec le même ID. Le second appel : `findById()` retourne la transaction déjà traitée (statut BLOCKED), `submit()` lève une exception → le test échoue en exception au lieu de tester l'idempotence |
| Timeout 50ms absent | Moyen | `MLRiskScoringStrategy::calculateRiskScore()` calcule un score fixe à partir du montant — aucun `HttpClient` appelé. Le circuit breaker est présent mais contrôle un chemin mort |
| `htmlspecialchars()` ≠ protection SQL | Moyen | Le contrôleur utilise `htmlspecialchars()` (protection XSS, pas SQL). La vraie protection SQL injection est aux paramètres Doctrine, pas ici — antipattern confusant |
| Rate limiting non implémenté | Moyen | `isAllowed()` retourne toujours `true` — `testRateLimit429` teste `assertTrue(true)` |
| Namespace manquant `RiskScoringStrategy` | Faible | Dans `SubmitTransactionCommandHandler` (namespace `App\Application\Command`), `RiskScoringStrategy` est utilisé sans `use Domain\RiskScoringStrategy` — fatal error à l'exécution |
| Valeurs int de l'enum `RiskLevel` trompeuses | Faible | `case MEDIUM = 300` alors que MEDIUM commence à 301 — les valeurs d'enum ne correspondent pas aux bornes. `fromScore()` est correct mais l'enum lui-même est incohérent |

### Verdict

phi4-reasoning:plus révèle sa nature de **modèle de raisonnement** : le bloc `<think>` de 1 700 lignes montre une exploration rigoureuse des invariants et patterns avant de coder. Le résultat est architecturalement solide — Domain Layer exemplaire, SOLID strict, Observabilité complète.

Mais le raisonnement s'essouffle sur les couches de sécurité concrètes : JWT et rate limiting restent des interfaces sans implémentation. L'anti-pattern `htmlspecialchars()` pour "SQL injection" suggère que le modèle a mémorisé la règle de sécurité sans en comprendre l'application exacte.

**Usage optimal** : conception architecturale, implémentation Domain Layer + SOLID, génération d'interfaces et de patterns — pas de missions full-stack end-to-end sans revue humaine de la couche sécurité.

---

## Comparaison complète — Round 1

| Critère | codestral:22b | devstral-small-2 | phi4-reasoning:plus |
|---|---|---|---|
| Origine | Mistral 🇫🇷 | Mistral 🇫🇷 | Microsoft 🇺🇸 |
| Taille modèle | 14 Go | 15 Go | 9 Go |
| Durée | 39s | 292s | 663s |
| Lignes produites | ~50 | ~1 200 | ~1 070 (+ 1 700 think) |
| Layers couverts | Domain only | Domain + App + Infra + API + Tests | Domain + App + Infra + API + Tests |
| Score 6 behaviors | **C+ (2/6)** | **A- (6/6)** | **B (3✅ + 3⚠)** |
| DDD | ✅ | ✅ | ✅ |
| SOLID | ✅ | ✅ | ✅ |
| Sécurité | ❌ | ✅ | ⚠ |
| Performance | ⚠ | ✅ | ⚠ |
| Tests | ❌ | ✅ | ⚠ |
| Observabilité | ❌ | ✅ | ✅ |
| Bugs critiques | 2 | 1 | 3 |
| Chain-of-Thought | Non | Non | **Oui (1 700 lignes)** |
| Usage recommandé | Tâches ciblées | Missions autonomes | Architecture + Domain design |

### Positionnement

```
Autonomie full-stack
        ▲
        │ devstral-small-2 ●  (A- — 292s — 1 200 lignes)
        │
        │          phi4-reasoning:plus ●  (B — 663s — 1 070 lignes)
        │
        │                codestral:22b ●  (C+ — 39s — 50 lignes)
        ▼
        └─────────────────────────────────→ Vitesse de réponse
```

**phi4-reasoning:plus occupe un créneau unique** : plus lent que devstral, moins complet sur la sécurité, mais son raisonnement explicite le rend idéal pour la **revue d'architecture** et les **décisions de design** où comprendre le "pourquoi" compte autant que le "quoi".

---

## Modèle 4 — gemma4:31b (Google 🇺🇸)

| Paramètre | Valeur |
|---|---|
| Origine | Google 🇺🇸 |
| Taille | ~20 Go (Q4_K_M) |
| Spécialité | Agents, tool-calling, contexte 256K, multimodal |
| Durée de réponse | **201 secondes (3m21s)** |
| Lignes produites | **~460 lignes** |

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ✅ | `readonly class Money`/`RiskScore`, Transaction aggregate + `$version` (optimistic lock), `releaseEvents()` vide correctement le tableau, Domain Events, interfaces `RiskScoringStrategy`/`TransactionRepository` |
| SOLID | ✅ | Strategy Pattern ML + Heuristic, DIP via interfaces, `readonly` DTO, Symfony `MessageBusInterface` (DIP), `finally { $span->end() }` |
| Sécurité Zero-Trust | ❌ | JWT commenté (`// $this->denyAccessUnlessGranted`) ❌, rate limiting **absent** ❌, security headers (HSTS/CSP) absents ❌, ISO 4217 partiel (longueur seulement, pas regex `[A-Z]{3}`) |
| Performance | ✅ | `timeout: 0.05` HttpClient réel ✅, fallback Heuristic ✅, TTL Redis par RiskLevel (3600/600/60/0) ✅, cursor pagination `findRecentByClient()` ✅, idempotence Redis O(1) ✅ |
| Tests TDD/BDD | ⚠ | Domain tests (invariants, RiskLevel, Money equals) ✅ — `SecurityTest` corps vides ❌, pas d'integration test CommandHandler |
| Observabilité | ✅ | OTel **réel** (`use OpenTelemetry\API\Trace\TracerInterface`) ✅, Prometheus réel (`CollectorRegistry`) ✅, logs structurés complets ✅, `span.end()` dans `finally` ✅ |

**Score global : B+ (4/6 complets — sécurité absente, tests partiels)**

### Code produit (extraits clés)

```php
// Transaction aggregate — version + releaseEvents() correct
class Transaction {
    public function __construct(/* ... */, private int $version = 0) {
        if ($this->isAccountSuspended) throw new \DomainException("...");
    }
    public function releaseEvents(): array {
        $events = $this->domainEvents;
        $this->domainEvents = []; // ✅ Vide le tableau — at-most-once garanti
        return $events;
    }
    public function applyRiskScore(RiskScore $score): void {
        $this->riskScore = $score;
        if ($score->level() === RiskLevel::CRITICAL) {
            $this->status = 'BLOCKED';
            $this->recordEvent(new FraudAlertTriggered($this->id, $score));
        } elseif ($score->level() === RiskLevel::HIGH) {
            $this->status = 'REVIEW_REQUIRED';
        } else {
            $this->status = 'APPROVED';
        }
        $this->recordEvent(new RiskScoreCalculated($this->id, $score));
    }
}

// CommandHandler — OTel réel + cache-aside + idempotence Redis
class SubmitTransactionCommandHandler {
    public function __construct(
        private TransactionRepository $repository,
        private RiskScoringStrategy $scoringStrategy,
        private \Redis $cache,
        private TracerInterface $tracer,      // OpenTelemetry\API\Trace\TracerInterface
        private LoggerInterface $logger,
        private CollectorRegistry $metrics    // Prometheus réel
    ) {}

    public function handle(SubmitTransactionCommand $command): string {
        $span = $this->tracer->spanBuilder('transaction.submit')
            ->setAttribute('client_id', $command->clientId)->startSpan();
        try {
            // Idempotency O(1)
            if ($existingId = $this->cache->get("idempotency:{$command->idempotencyKey}")) {
                return (string)$existingId;
            }
            // Cache-aside + TTL dynamique
            $ttl = match($riskScore->level()) {
                RiskLevel::LOW => 3600, RiskLevel::MEDIUM => 600,
                RiskLevel::HIGH => 60, RiskLevel::CRITICAL => 0,
            };
            if ($ttl > 0) $this->cache->setex("risk_profile:{$command->clientId}", $ttl, $riskScore->value);
        } finally {
            $span->end(); // ✅ Toujours fermé
        }
    }
}

// MLRiskScoringStrategy — timeout 50ms réel via HttpClient Symfony
class MLRiskScoringStrategy implements RiskScoringStrategy {
    public function calculate(Transaction $transaction): RiskScore {
        try {
            $response = $this->httpClient->request('POST', 'https://ml-risk-api/score', [
                'timeout' => 0.05, // ✅ 50ms max — circuit breaker implicite
                'json' => ['tx_id' => $transaction->getId()]
            ]);
            return new RiskScore($response->toArray()['score']);
        } catch (\Exception $e) {
            return $this->fallback->calculate($transaction); // ✅ OCP + résilience
        }
    }
}

// Cursor pagination O(log n) avec index composite
public function findRecentByClient(string $clientId, string $cursor, int $limit = 20): array {
    return $this->em->createQuery(
        'SELECT t FROM ... WHERE t.clientId = :clientId AND t.createdAt < :cursor ORDER BY t.createdAt DESC'
    )->setParameter('cursor', $cursor)->setMaxResults($limit)->getResult();
}
```

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| JWT check commenté | Critique | `// $this->denyAccessUnlessGranted('ROLE_TRANSACTIONS_WRITE')` — la ligne est là mais en commentaire. Tout le monde peut poster |
| Rate limiting absent | Critique | Aucune vérification Redis req/min dans le controller ni le handler |
| `$transaction->getId()` inexistant | Élevé | `MLRiskScoringStrategy` appelle `$transaction->getId()` mais Transaction n'a pas cette méthode (propriété publique `$id`) — fatal error |
| `$transaction->getMoney()` inexistant | Élevé | `HeuristicRiskScoringStrategy` appelle `->getMoney()->amountCents` — même problème, pas de getter |
| `submit()` absent | Moyen | Transaction n'a pas de méthode `submit()` — `TransactionSubmitted` event jamais émis, transition PENDING n'est pas explicite |
| Suspension check au constructeur | Moyen | `isAccountSuspended` vérifié à la construction, pas au submit — impossibilité de charger une transaction suspendue depuis la DB |
| ISO 4217 validation partielle | Faible | `strlen($currency) !== 3` accepte "123" ou "abc" — devrait être `/^[A-Z]{3}$/` |
| `\Redis $cache` — couplage concret | Faible | Handler dépend de `\Redis` (classe concrète) au lieu d'une interface — viole DIP |

### Verdict

gemma4:31b **domine sur la performance et l'observabilité** : c'est le seul modèle qui importe de vraies classes OpenTelemetry et Prometheus (pas des interfaces custom), qui implémente `timeout: 0.05` sur un vrai `HttpClient`, et dont le `releaseEvents()` vide correctement le tableau (at-most-once publication garanti). Le code est idiomatique Symfony.

Mais la sécurité est une catastrophe silencieuse : la ligne JWT est là, commentée, comme si le développeur avait prévu de l'activer plus tard et oublié. Rate limiting inexistant. Zéro security headers.

**Usage optimal** : performance engineering, observabilité, cache design, Symfony idiomatique — avec revue impérative de la couche sécurité avant tout déploiement.

---

## Comparaison complète — Round 1 (4 modèles)

| Critère | codestral:22b | devstral-small-2 | phi4-reasoning:plus | gemma4:31b |
|---|---|---|---|---|
| Origine | Mistral 🇫🇷 | Mistral 🇫🇷 | Microsoft 🇺🇸 | Google 🇺🇸 |
| Taille | 14 Go | 15 Go | 9 Go | 20 Go |
| Durée | 39s | 292s | 663s | 201s |
| Lignes | ~50 | ~1 200 | ~1 070 (+1 700 think) | ~460 |
| Score | **C+ (2/6)** | **A- (6/6)** | **B (3+3⚠)** | **B+ (4+1⚠+1❌)** |
| DDD | ✅ | ✅ | ✅ | ✅ |
| SOLID | ✅ | ✅ | ✅ | ✅ |
| Sécurité | ❌ | ✅ | ⚠ | ❌ |
| Performance | ⚠ | ✅ | ⚠ | ✅ |
| Tests | ❌ | ✅ | ⚠ | ⚠ |
| Observabilité | ❌ | ✅ | ✅ | ✅ |
| `releaseEvents()` correct | ✅ | ✅ | ❌ | ✅ |
| OTel réel (pas custom) | ❌ | ❌ | ❌ | ✅ |
| Timeout 50ms réel | ❌ | ✅ | ❌ | ✅ |
| Bugs critiques | 2 | 1 | 3 | 2 |
| Usage recommandé | Tâches ciblées | Missions autonomes | Architecture + DDD design | Perf + Observabilité |

---

## Modèle 5 — llama3.3:70b (Meta 🇺🇸)

| Paramètre | Valeur |
|---|---|
| Origine | Meta 🇺🇸 |
| Taille | ~43 Go sur disque / 102 Go en RAM (100% GPU) |
| Spécialité | Modèle généraliste 70B — architecture, raisonnement, K8s, OWASP |
| Durée de réponse | **284 secondes (4m44s)** |
| Lignes produites | **~560 lignes** |

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ⚠ | Structure layered correcte (`final class`, namespaces Domain/Application/Infrastructure/API) ✅ — Domain Events définis mais **jamais collectés** (pas de `releaseEvents()`), `submit()` fixe le statut à APPROVED avant le scoring ❌ |
| SOLID | ⚠ | `RiskScoringStrategy` + `TransactionRepository` interfaces définies ✅ — mais Strategy **non injectée** dans le handler (méthode privée stub `calculateRiskScore()` avec `// ...`), Redis sans interface |
| Sécurité Zero-Trust | ❌ | JWT **absent**, rate limiting **absent**, validation payload **absente** (raw `json_decode` sans null-check), security headers **absents** |
| Performance | ❌ | Redis sans TTL (`set($key, $value)` — pas de `setex`), pas de circuit breaker, pas de cursor pagination, pas de timeout 50ms, pas d'idempotence Redis |
| Tests TDD/BDD | ⚠ | Structure Unit + Integration présente ✅ — Integration test avec mock de mauvais type (passe `MessageBusInterface` au lieu de `Tracer`) ❌, `calculateRiskScore()` non implémentée → fatal error à l'exécution |
| Observabilité | ⚠ | Span OTel ouvert/fermé dans le handler ✅ — pas de `finally` (span peut leaker), pas de logs structurés, pas de Prometheus metrics |

**Score global : C (0/6 complets — 4 partiels, 2 absents)**

### Code produit (extraits représentatifs)

```php
// Transaction — submit() APPROUVE avant le scoring (bug architectural)
public function submit(): void {
    if ($this->status !== 'PENDING') throw new \InvalidArgumentException('...');
    $this->status = 'APPROVED'; // ← par défaut, "sera mis à jour après scoring"
                                // mais la mise à jour n'arrive jamais correctement
}

// Domain Events définis mais jamais collectés
public function score(RiskScore $riskScore): void {
    // ...
    $event = new FraudAlertTriggered($this->id, $this->clientId);
    // ... ← commentaire vide — event créé mais non publié
}
// Pas de releaseEvents() ni de $domainEvents[]

// Redis sans TTL — données jamais expirées
public function set(string $key, string $value): void {
    $this->redis->set($key, $value); // ← pas de TTL → fuite mémoire Redis
}

// Strategy Pattern définie... mais non utilisée dans le handler
private function calculateRiskScore(Transaction $transaction): int {
    // Implémenter la stratégie de scoring des risques
    // ... ← stub vide — fatal error à l'exécution
}

// Contrôleur sans validation, JWT, rate limiting
public function submit(Request $request): JsonResponse {
    $data = json_decode($request->getContent(), true); // ← pas de null-check
    $command = new SubmitTransactionCommand(
        $data['transaction_id'], // ← injection directe sans validation
        new Money($data['amount'], $data['currency']),
        $data['client_id']
    );
    // ... ← 0 JWT, 0 rate limit, 0 security headers
}
```

### Auto-évaluation du modèle

llama3.3:70b conclut lui-même sa réponse par :

> *"Il est important de noter que ce code n'est pas complet et nécessite probablement des modifications pour être fonctionnel. De plus, les tests ne sont pas exhaustifs et devraient être complétés."*

C'est rare et honnête — mais confirme que le modèle était conscient de produire un squelette, pas une implémentation complète.

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| `submit()` → APPROVED avant scoring | Critique | La machine à états est cassée : PENDING → APPROVED → score() re-change en BLOCKED ou REVIEW_REQUIRED. Mais si `score()` vérifie `status !== 'PENDING' && status !== 'APPROVED'`, ça fonctionne — architecturalement discutable mais pas fatal |
| Domain Events jamais collectés | Élevé | Pas de `$domainEvents[]`, pas de `releaseEvents()` — les events sont instanciés dans le vide |
| `calculateRiskScore()` stub | Élevé | Corps `// ...` → PHP fatal error à l'exécution |
| Redis sans TTL | Élevé | `set($key, $value)` sans expiration → fuite mémoire Redis, pas de TTL par RiskLevel |
| Validation Controller absente | Élevé | `$data['transaction_id']` sans null-check → PHP warning si champ manquant |
| Integration test mauvais mock | Moyen | Handler attend `Tracer` mais test passe `MessageBusInterface` → type error |
| `Money` accepte `amount = 0` | Faible | `if ($amount < 0)` au lieu de `<= 0` — montant nul autorisé |
| Span sans `finally` | Faible | `$span->end()` après le flow normal — span perdu si exception levée |

### Verdict

llama3.3:70b est le **résultat le plus surprenant du benchmark** : 70 milliards de paramètres, mais score inférieur à devstral-small-2 (15B) sur cette tâche. Le modèle connaît les patterns (DDD, SOLID, OTel) et structure correctement les fichiers — mais ne les implémente pas jusqu'au bout.

**Explication** : llama3.3:70b est un modèle généraliste optimisé pour le raisonnement et la conversation. devstral-small-2 a été fine-tuné spécifiquement sur des dépôts GitHub réels (SWE-bench 65.8%) — c'est la spécialisation qui fait la différence, pas la taille.

**Usage optimal** : architecture système (K8s, microservices), revue OWASP conceptuelle, documentation technique, explication de patterns. Ne pas utiliser pour la génération de code production directement.

---

## Comparaison finale — Round 1 (5 modèles)

| Critère | codestral:22b | devstral-small-2 | phi4-reasoning:plus | gemma4:31b | llama3.3:70b |
|---|---|---|---|---|---|
| Origine | Mistral 🇫🇷 | Mistral 🇫🇷 | Microsoft 🇺🇸 | Google 🇺🇸 | Meta 🇺🇸 |
| Taille disque | 14 Go | 15 Go | 9 Go | 20 Go | 43 Go |
| RAM chargé | ~30 Go | ~30 Go | ~20 Go | ~47 Go | **102 Go** |
| Durée | 39s | 292s | 663s | 201s | 284s |
| Lignes | ~50 | ~1 200 | ~1 070 | ~460 | ~560 |
| **Score** | **C+ (2/6)** | **A- (6/6)** | **B (3✅+3⚠)** | **B+ (4✅+1⚠+1❌)** | **C (4⚠+2❌)** |
| DDD | ✅ | ✅ | ✅ | ✅ | ⚠ |
| SOLID | ✅ | ✅ | ✅ | ✅ | ⚠ |
| Sécurité | ❌ | ✅ | ⚠ | ❌ | ❌ |
| Performance | ⚠ | ✅ | ⚠ | ✅ | ❌ |
| Tests | ❌ | ✅ | ⚠ | ⚠ | ⚠ |
| Observabilité | ❌ | ✅ | ✅ | ✅ | ⚠ |
| `releaseEvents()` correct | N/A | ✅ | ❌ | ✅ | ❌ |
| OTel réel | ❌ | ❌ | ❌ | ✅ | ⚠ |
| Timeout 50ms réel | ❌ | ✅ | ❌ | ✅ | ❌ |
| Bugs critiques | 2 | 1 | 3 | 2 | 3 |
| Usage | Tâches ciblées | Missions autonomes | Architecture + DDD | Perf + Observabilité | Revue + Docs |

### Classement final

```
A-  devstral-small-2    ██████████████████████████  6/6 behaviors (15 Go)
B+  gemma4:31b          ████████████████████░░░░░░  4/6 + perf/OTel réels (20 Go)
B   phi4-reasoning:plus ████████████████░░░░░░░░░░  3/6 + chain-of-thought (9 Go)
C+  codestral:22b       ████████░░░░░░░░░░░░░░░░░░  2/6 — Domain uniquement (14 Go)
C   llama3.3:70b        ████████░░░░░░░░░░░░░░░░░░  0/6 complets — squelettes (43 Go)
```

**Enseignement clé** : la spécialisation SWE (fine-tuning sur code réel) bat la taille brute des paramètres. devstral-small-2 à 15B écrase llama3.3:70b à 70B sur une mission de développement.

---

## Modèle 6 — qwen3.6:27b (Alibaba 🇨🇳 ⚠ — filtré sandbox-guard.sh)

| Paramètre | Valeur |
|---|---|
| Origine | Alibaba 🇨🇳 — sortie filtrée via `sandbox-guard.sh` |
| Taille | ~17 Go sur disque / 42 Go en RAM (100% GPU) |
| Spécialité | Coding pur, raisonnement structuré |
| Durée de réponse | **557 secondes (9m17s)** |
| Lignes produites | **~700 lignes de code + notes DevSecOps** |
| Filtre sandbox | Actif — aucun contenu sensible détecté |

### Scorecard

| Behavior | Score | Détail |
|---|---|---|
| Architecture Clean + DDD | ✅ | `TransactionId` VO (UUID validation), `TransactionStatus` VO, `DomainEvent` base class avec `occurredOn`, `releaseEvents()` vide correctement, `TransactionSubmitted` émis au constructeur, tous les events correctement enregistrés |
| SOLID | ✅ | Strategy Pattern (ML + Heuristic), DIP interfaces, `readonly` DTOs, `#[AsMessageHandler]`, `bumpVersion()` optimistic lock explicite |
| Sécurité Zero-Trust | ✅ | `#[IsGranted('SCOPE', 'transactions:write')]` + JWT via Symfony Firewall ✅, `#[RateLimit(limit: 1000, interval: 'minute')]` ✅, payload 10KB → 413 ✅, RFC 9457 ✅, `SET NX EX` anti-stampede ✅, Idempotency-Key ✅ |
| Performance | ✅ | `timeout: 0.05` HttpClient ✅, circuit breaker avec reset 30s ✅, `TTL_MAP` const par RiskLevel ✅, cursor pagination `WHERE created_at > :cursor` ✅, `hrtime(true)` nanoseconde ✅, `SET NX EX` atomique ✅ |
| Tests TDD/BDD | ⚠ | Domain tests complets : `TransactionTest` (invariants, machine à états, double apply) + `RiskScoreTest` (4 niveaux + equals) + `MoneyTest` ✅ — Integration test `SubmitTransactionCommandHandlerTest` : structure présente mais corps commenté |
| Observabilité | ✅ | `$span->recordException($e)` ✅ (unique dans le stack), `SpanStatus::error()` ✅, logs structurés complets dans `finally` ✅, `hrtime` nanoseconde → ms ✅, alerte PromQL documentée : `transaction_scoring_duration_ms{quantile="0.99"} > 100` ✅ |

**Score global : A- (5/6 complets — tests partiels)**

### Innovations uniques vs les autres modèles

qwen3.6:27b introduit des patterns absents des 5 autres modèles :

```php
// TransactionId et TransactionStatus comme Value Objects — niveau DDD avancé
final readonly class TransactionId {
    public function __construct(public string $value) {
        if (!\Symfony\Component\Uid\Uuid::isValid($this->value))
            throw new \DomainException('Invalid UUID');
    }
}

final readonly class TransactionStatus {
    public function __construct(public string $value) {
        $valid = ['PENDING', 'APPROVED', 'REVIEW_REQUIRED', 'BLOCKED'];
        if (!\in_array($this->value, $valid, true))
            throw new \DomainException('Invalid status transition.');
    }
}

// DomainEvent base class avec timestamp — Event Sourcing ready
#[\Attribute(\Attribute::TARGET_CLASS)]
final readonly class DomainEvent {
    public function __construct(public \DateTimeImmutable $occurredOn = new \DateTimeImmutable()) {}
}

// Précision nanoseconde pour les métriques
$startMicro = \hrtime(true);
$latency = (\hrtime(true) - $startMicro) / 1_000_000; // → ms

// recordException + SpanStatus sur les erreurs — OTel complet
$span->recordException($e);
$span->setStatus(\OpenTelemetry\API\Trace\SpanStatus::error($e->getMessage()));

// SET NX EX — protection anti-stampede atomique Redis
$this->redis->set($key, $value, ['EX' => $ttl, 'NX' => true]);

// Circuit breaker avec fenêtre temporelle
private bool $isClosed = true;
private \DateTimeImmutable $lastFailure = new \DateTimeImmutable('-1 minute');
if (!$this->isClosed && (time() - $this->lastFailure->getTimestamp()) < 30) {
    return $this->fallback->score($transaction);
}

// Alerte Prometheus documentée par le modèle lui-même
// transaction_scoring_duration_ms{quantile="0.99"} > 100

// Index composite annoté directement sur le Repository
#[ORM\Entity, ORM\Table(name: 'transactions', indexes: [
    new ORM\Index(columns: ['client_id', 'created_at'], name: 'idx_txn_client_created')
])]
```

### Bugs détectés

| Bug | Sévérité | Description |
|---|---|---|
| `releaseEvents()` type de retour incorrect | Élevé | Déclaré `: DomainEvent` (scalaire) mais retourne `$this->events` (array) — fatal type error en PHP strict |
| `$riskScore` indéfini dans `finally` | Élevé | Si exception avant `$this->strategy->score()`, `$riskScore->value()` dans le finally → PHP fatal error (variable non initialisée, `?? 0` ne sauve pas) |
| `$riskScore->value()` méthode inexistante | Moyen | `RiskScore` a `public int $value` (propriété), pas `value()` (méthode) — appel `->value()` dans le finally → fatal error |
| `use App\Domain\Transaction\*` invalide | Moyen | PHP ne supporte pas les wildcard imports `use Namespace\*` — fatal parse error |
| `TransactionId::fromString()` inexistant | Moyen | Contrôleur appelle `TransactionId::fromString()` — méthode non définie dans la classe |
| `\Psr\Metrics\MetricsRegistryInterface` inexistant | Faible | Ce PSR n'existe pas — classe non trouvée à l'exécution |
| `$bus->dispatch($query)->getMessage()` | Faible | L'API Messenger retourne une `Envelope` — devrait être `->last(HandledStamp::class)->getResult()` |

### Verdict

qwen3.6:27b produit l'implémentation **architecturalement la plus riche** du benchmark — le seul modèle à introduire `TransactionId`/`TransactionStatus` comme Value Objects distincts, une `DomainEvent` base class, `hrtime` nanoseconde, et `recordException` OTel. Le DevSecOps inclut même une alerte PromQL documentée.

La sécurité est couverte via attributs Symfony (`#[IsGranted]`, `#[RateLimit]`) — approche idiomatique et correcte. Les bugs sont principalement des erreurs de type PHP (wildcard import, `value()` vs `->value`) qui n'affectent pas la cohérence architecturale.

**⚠ Rappel protocole** : ce code est passé par `sandbox-guard.sh` — aucun contenu sensible détecté. Validation humaine avant tout usage en production, comme pour tout modèle Alibaba.

**Usage optimal** : conception architecturale avancée DDD/CQRS, code de référence pour patterns complexes, supervision humaine requise sur les détails PHP avant exécution.

---

## Classement final — Round 1 complet (6 modèles)

| Critère | codestral:22b | devstral-small-2 | phi4-reasoning | gemma4:31b | llama3.3:70b | qwen3.6:27b |
|---|---|---|---|---|---|---|
| Origine | Mistral 🇫🇷 | Mistral 🇫🇷 | Microsoft 🇺🇸 | Google 🇺🇸 | Meta 🇺🇸 | Alibaba 🇨🇳⚠ |
| Taille disque | 14 Go | 15 Go | 9 Go | 20 Go | 43 Go | 17 Go |
| RAM chargé | ~30 Go | ~30 Go | ~20 Go | 47 Go | **102 Go** | 42 Go |
| Durée | 39s | 292s | 663s | 201s | 284s | 557s |
| Lignes | ~50 | ~1 200 | ~1 070 | ~460 | ~560 | ~700 |
| **Score** | **C+ (2/6)** | **A- (6/6)** | **B (3+3⚠)** | **B+ (4+1⚠+1❌)** | **C (4⚠+2❌)** | **A- (5+1⚠)** |
| DDD | ✅ | ✅ | ✅ | ✅ | ⚠ | ✅ |
| SOLID | ✅ | ✅ | ✅ | ✅ | ⚠ | ✅ |
| Sécurité | ❌ | ✅ | ⚠ | ❌ | ❌ | ✅ |
| Performance | ⚠ | ✅ | ⚠ | ✅ | ❌ | ✅ |
| Tests | ❌ | ✅ | ⚠ | ⚠ | ⚠ | ⚠ |
| Observabilité | ❌ | ✅ | ✅ | ✅ | ⚠ | ✅ |
| `releaseEvents()` correct | N/A | ✅ | ❌ | ✅ | ❌ | ✅ (type bug) |
| OTel réel | ❌ | ❌ | ❌ | ✅ | ⚠ | ✅ |
| Timeout 50ms | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ |
| Anti-stampede cache | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| `recordException` OTel | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Bugs critiques | 2 | 1 | 3 | 2 | 3 | 3 |

### Classement final

```
A-  devstral-small-2    ██████████████████████████  6/6 — seul à couvrir 100% (15 Go)
A-  qwen3.6:27b ⚠      █████████████████████░░░░░  5/6 — architecture la plus avancée (17 Go)
B+  gemma4:31b          ████████████████████░░░░░░  4/6 — OTel réel + perf (20 Go)
B   phi4-reasoning:plus ████████████████░░░░░░░░░░  3/6 — CoT visible, DDD fort (9 Go)
C+  codestral:22b       ████████░░░░░░░░░░░░░░░░░░  2/6 — Domain uniquement (14 Go)
C   llama3.3:70b        ████████░░░░░░░░░░░░░░░░░░  0/6 complets — squelettes (43 Go)
```

### Enseignements clés du Round 1

1. **La spécialisation bat la taille** — devstral-small-2 (15B) > llama3.3:70b (70B). Le fine-tuning SWE-bench fait la différence.

2. **La sécurité est le comportement le plus discriminant** — seuls devstral et qwen l'implémentent complètement. Les 4 autres oublient JWT, rate limiting, ou security headers.

3. **qwen3.6:27b est une surprise** — architecture DDD la plus avancée (VO imbriqués, DomainEvent base), malgré l'obligation du filtre sandbox.

4. **gemma4:31b = meilleure observabilité** — seul à importer les vraies classes OTel/Prometheus. Idéal pour du code proche de la production sur cette couche.

5. **phi4-reasoning:plus = meilleur outil de réflexion** — le `<think>` visible est un avantage pour la revue d'architecture, pas pour la génération directe.

---

*Benchmark conduit par Zied Jlassi — DevSecOps — MacBook Pro M5 Max 128 Go*  
*Stack : Ollama local · Symfony 7 · PHP 8.3 · Redis 7 · PostgreSQL 16 · RabbitMQ · OpenTelemetry*  
*Méthodologie : isolation RAM garantie — un seul modèle en mémoire par test · sortie qwen filtrée sandbox-guard.sh*

---

*Benchmark conduit par Zied Jlassi — DevSecOps — MacBook Pro M5 Max 128 Go*  
*Stack : Ollama local · Symfony 7 · PHP 8.3 · Redis 7 · PostgreSQL 16 · RabbitMQ · OpenTelemetry*  
*Méthodologie : isolation RAM garantie — un seul modèle en mémoire par test*
