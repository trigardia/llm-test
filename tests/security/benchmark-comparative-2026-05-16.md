# Security Benchmark LLM — Analyse comparative OWASP 2025
**Date** : 2026-05-16 | **Machine** : MacBook Pro M5 Max — 128 Go RAM
**Référence** : OWASP Top 10:2025 + OWASP LLM Top 10:2025
**Objectif** : Sélection LLM pour pipeline GitLab CI DevSecOps (aux côtés de Trivy)
**Samples** : 32 fichiers (A01–A10 + AXX avancés) · PHP, Python, JS, Java, Bash, TypeScript

---

## Classement par moyenne — modèles CI éligibles

| # | Modèle | Tests | Moy./20 | Meilleur | Plancher | Tps moy. | CI eligible | Origine |
|---|--------|-------|---------|----------|----------|----------|-------------|---------|
| 🥇 | `gemma4:31b` | 33/32 | **19.94** | 20/20 | ✅ 18 | 54s | ✅ Oui | Google 🇺🇸 |
| 🥈 | `codestral:22b` | 33/32 | **18.88** | 20/20 | ⚠️ 16 | 38s | ✅ Oui (fast) | Mistral 🇫🇷 |
| 🥉 | `qwen3.6:27b` ⚠️ | 33/32 | **18.73** | 20/20 | ✅ 18 | 75s | ⚠️ Sandbox | Alibaba 🇨🇳 |
| 4 | `llama3.3:70b` | 33/32 | **18.42** | 20/20 | ✅ 18 | 103s | ⚠️ Lent | Meta 🇺🇸 |
| 5 | `foundation-sec-reasoning` | 31/32 | **18.39** | 20/20 | ⚠️ 16 | 35s | ✅ Oui (fast) | Security-specific |
| 6 | `devstral-small-2` | 33/32 | **18.00** | 18/20 | ✅ 18 | 40s | ✅ Oui | Mistral 🇫🇷 |
| — | `phi4-reasoning:plus` ❌ | 29/32 | ~18.8* | 20/20 | ⚠️ 15 | **~300s** | ❌ Non | Microsoft 🇺🇸 |

> ⚠️ `qwen3.6:27b` — sortie obligatoirement filtrée via `sandbox-guard.sh` (règle CLAUDE.md)
> ❌ `phi4-reasoning:plus` — **exclu du CI** : modèle de raisonnement étendu (~300s/sample, scoring instable 15-20). Conçu pour architecture/SOLID/Java, pas pour le scanning sécu répétitif. Le bloc `<think>` interne ne peut pas être supprimé et génère des scores incohérents selon les samples.

---

## Scores détaillés — Modèle × Sample

| Modèle | Sample | Score |
|--------|--------|-------|
| `foundation-sec-reasoning` | A01-broken-access-control.php | 18/20 |
| `foundation-sec-reasoning` | A02-cryptographic-failures.php | 18/20 |
| `foundation-sec-reasoning` | A03-injection.php | 18/20 |
| `foundation-sec-reasoning` | A04-insecure-design.php | 18/20 |
| `foundation-sec-reasoning` | A05-security-misconfiguration.php | 18/20 |
| `foundation-sec-reasoning` | A06-vulnerable-components.php | ⚠️ 16/20 |
| `foundation-sec-reasoning` | A07-auth-failures.php | 18/20 |
| `foundation-sec-reasoning` | A08-integrity-failures.php | 18/20 |
| `foundation-sec-reasoning` | A09-logging-failures.php | 18/20 |
| `foundation-sec-reasoning` | A10-ssrf.php | 18/20 |
| `foundation-sec-reasoning` | AXX-advanced-php-attacks.php | 20/20 |
| `foundation-sec-reasoning` | AXX-api-bola.js | 18/20 |
| `foundation-sec-reasoning` | AXX-bash-shell-vulnerabilities.sh | 18/20 |
| `foundation-sec-reasoning` | AXX-docker-misconfig.py | 18/20 |
| `foundation-sec-reasoning` | AXX-domain-defense-ics.php | 18/20 |
| `foundation-sec-reasoning` | AXX-domain-education.php | 18/20 |
| `foundation-sec-reasoning` | AXX-domain-finance.php | 18/20 |
| `foundation-sec-reasoning` | AXX-domain-healthcare.php | 18/20 |
| `foundation-sec-reasoning` | AXX-domain-llm-ai.py | 18/20 |
| `foundation-sec-reasoning` | AXX-graphql-api.js | 18/20 |
| `foundation-sec-reasoning` | AXX-java-vulnerabilities.java | 20/20 |
| `foundation-sec-reasoning` | AXX-jwt-vulnerabilities.js | 18/20 |
| `foundation-sec-reasoning` | AXX-ldap-xpath-injection.php | 20/20 |
| `foundation-sec-reasoning` | AXX-mobile-android.java | 20/20 |
| `foundation-sec-reasoning` | AXX-nodejs-vulnerabilities.js | 18/20 |
| `foundation-sec-reasoning` | AXX-nosql-injection.js | 20/20 |
| `foundation-sec-reasoning` | AXX-oauth2-oidc.js | 18/20 |
| `foundation-sec-reasoning` | AXX-php-deserialization.php | 20/20 |
| `foundation-sec-reasoning` | AXX-python-vulnerabilities.py | 18/20 |
| `foundation-sec-reasoning` | AXX-ssl-tls-misconfig.py | 18/20 |
| `foundation-sec-reasoning` | AXX-ssti-twig.php | N/A |
| `foundation-sec-reasoning` | AXX-xxe-parser.php | 20/20 |
| `phi4-reasoning:plus` | A01-broken-access-control.php | 20/20 |
| `phi4-reasoning:plus` | A02-cryptographic-failures.php | 20/20 |
| `phi4-reasoning:plus` | A03-injection.php | 20/20 |
| `phi4-reasoning:plus` | A04-insecure-design.php | 20/20 |
| `phi4-reasoning:plus` | A05-security-misconfiguration.php | 20/20 |
| `phi4-reasoning:plus` | A06-vulnerable-components.php | 20/20 |
| `phi4-reasoning:plus` | A07-auth-failures.php | 20/20 |
| `phi4-reasoning:plus` | A08-integrity-failures.php | 20/20 |
| `phi4-reasoning:plus` | A09-logging-failures.php | 20/20 |
| `phi4-reasoning:plus` | A10-ssrf.php | 20/20 |
| `phi4-reasoning:plus` | AXX-advanced-php-attacks.php | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-bash-shell-vulnerabilities.sh | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-domain-defense-ics.php | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-domain-education.php | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-domain-finance.php | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-domain-healthcare.php | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-domain-llm-ai.py | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-java-vulnerabilities.java | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-nestjs-typescript.ts | 20/20 |
| `phi4-reasoning:plus` | AXX-nodejs-vulnerabilities.js | N/A (run incomplet) |
| `phi4-reasoning:plus` | AXX-python-vulnerabilities.py | N/A (run incomplet) |
| `codestral:22b` | A01-broken-access-control.php | 20/20 |
| `codestral:22b` | A02-cryptographic-failures.php | 20/20 |
| `codestral:22b` | A03-injection.php | 20/20 |
| `codestral:22b` | A04-insecure-design.php | 20/20 |
| `codestral:22b` | A05-security-misconfiguration.php | 20/20 |
| `codestral:22b` | A06-vulnerable-components.php | ⚠️ 16/20 |
| `codestral:22b` | A07-auth-failures.php | 20/20 |
| `codestral:22b` | A08-integrity-failures.php | 20/20 |
| `codestral:22b` | A09-logging-failures.php | ⚠️ 16/20 |
| `codestral:22b` | A10-ssrf.php | 20/20 |
| `codestral:22b` | AXX-advanced-php-attacks.php | 18/20 |
| `codestral:22b` | AXX-api-bola.js | 18/20 |
| `codestral:22b` | AXX-bash-shell-vulnerabilities.sh | 18/20 |
| `codestral:22b` | AXX-docker-misconfig.py | 18/20 |
| `codestral:22b` | AXX-domain-defense-ics.php | 20/20 |
| `codestral:22b` | AXX-domain-education.php | 20/20 |
| `codestral:22b` | AXX-domain-finance.php | 20/20 |
| `codestral:22b` | AXX-domain-healthcare.php | 18/20 |
| `codestral:22b` | AXX-domain-llm-ai.py | 18/20 |
| `codestral:22b` | AXX-graphql-api.js | 19/20 |
| `codestral:22b` | AXX-java-vulnerabilities.java | 18/20 |
| `codestral:22b` | AXX-jwt-vulnerabilities.js | 20/20 |
| `codestral:22b` | AXX-ldap-xpath-injection.php | 18/20 |
| `codestral:22b` | AXX-mobile-android.java | 18/20 |
| `codestral:22b` | AXX-nestjs-typescript.ts | 18/20 |
| `codestral:22b` | AXX-nodejs-vulnerabilities.js | 18/20 |
| `codestral:22b` | AXX-nosql-injection.js | 20/20 |
| `codestral:22b` | AXX-oauth2-oidc.js | 18/20 |
| `codestral:22b` | AXX-php-deserialization.php | 20/20 |
| `codestral:22b` | AXX-python-vulnerabilities.py | 18/20 |
| `codestral:22b` | AXX-ssl-tls-misconfig.py | 18/20 |
| `codestral:22b` | AXX-ssti-twig.php | 20/20 |
| `codestral:22b` | AXX-xxe-parser.php | 20/20 |
| `devstral-small-2` | A01-broken-access-control.php | 18/20 |
| `devstral-small-2` | A02-cryptographic-failures.php | 18/20 |
| `devstral-small-2` | A03-injection.php | 18/20 |
| `devstral-small-2` | A04-insecure-design.php | 18/20 |
| `devstral-small-2` | A05-security-misconfiguration.php | 18/20 |
| `devstral-small-2` | A06-vulnerable-components.php | 18/20 |
| `devstral-small-2` | A07-auth-failures.php | 18/20 |
| `devstral-small-2` | A08-integrity-failures.php | 18/20 |
| `devstral-small-2` | A09-logging-failures.php | 18/20 |
| `devstral-small-2` | A10-ssrf.php | 18/20 |
| `devstral-small-2` | AXX-advanced-php-attacks.php | 18/20 |
| `devstral-small-2` | AXX-api-bola.js | 18/20 |
| `devstral-small-2` | AXX-bash-shell-vulnerabilities.sh | 18/20 |
| `devstral-small-2` | AXX-docker-misconfig.py | 18/20 |
| `devstral-small-2` | AXX-domain-defense-ics.php | 18/20 |
| `devstral-small-2` | AXX-domain-education.php | 18/20 |
| `devstral-small-2` | AXX-domain-finance.php | 18/20 |
| `devstral-small-2` | AXX-domain-healthcare.php | 18/20 |
| `devstral-small-2` | AXX-domain-llm-ai.py | 18/20 |
| `devstral-small-2` | AXX-graphql-api.js | 18/20 |
| `devstral-small-2` | AXX-java-vulnerabilities.java | 18/20 |
| `devstral-small-2` | AXX-jwt-vulnerabilities.js | 18/20 |
| `devstral-small-2` | AXX-ldap-xpath-injection.php | 18/20 |
| `devstral-small-2` | AXX-mobile-android.java | 18/20 |
| `devstral-small-2` | AXX-nestjs-typescript.ts | 18/20 |
| `devstral-small-2` | AXX-nodejs-vulnerabilities.js | 18/20 |
| `devstral-small-2` | AXX-nosql-injection.js | 18/20 |
| `devstral-small-2` | AXX-oauth2-oidc.js | 18/20 |
| `devstral-small-2` | AXX-php-deserialization.php | 18/20 |
| `devstral-small-2` | AXX-python-vulnerabilities.py | 18/20 |
| `devstral-small-2` | AXX-ssl-tls-misconfig.py | 18/20 |
| `devstral-small-2` | AXX-ssti-twig.php | 18/20 |
| `devstral-small-2` | AXX-xxe-parser.php | 18/20 |
| `gemma4:31b` | A01-broken-access-control.php | 20/20 |
| `gemma4:31b` | A02-cryptographic-failures.php | 20/20 |
| `gemma4:31b` | A03-injection.php | 20/20 |
| `gemma4:31b` | A04-insecure-design.php | 20/20 |
| `gemma4:31b` | A05-security-misconfiguration.php | 20/20 |
| `gemma4:31b` | A06-vulnerable-components.php | 20/20 |
| `gemma4:31b` | A07-auth-failures.php | 20/20 |
| `gemma4:31b` | A08-integrity-failures.php | 20/20 |
| `gemma4:31b` | A09-logging-failures.php | 20/20 |
| `gemma4:31b` | A10-ssrf.php | 20/20 |
| `gemma4:31b` | AXX-advanced-php-attacks.php | 20/20 |
| `gemma4:31b` | AXX-api-bola.js | 20/20 |
| `gemma4:31b` | AXX-bash-shell-vulnerabilities.sh | 20/20 |
| `gemma4:31b` | AXX-docker-misconfig.py | 20/20 |
| `gemma4:31b` | AXX-domain-defense-ics.php | 20/20 |
| `gemma4:31b` | AXX-domain-education.php | 20/20 |
| `gemma4:31b` | AXX-domain-finance.php | 20/20 |
| `gemma4:31b` | AXX-domain-healthcare.php | 20/20 |
| `gemma4:31b` | AXX-domain-llm-ai.py | 20/20 |
| `gemma4:31b` | AXX-graphql-api.js | ⚠️ 18/20 |
| `gemma4:31b` | AXX-java-vulnerabilities.java | 20/20 |
| `gemma4:31b` | AXX-jwt-vulnerabilities.js | 20/20 |
| `gemma4:31b` | AXX-ldap-xpath-injection.php | 20/20 |
| `gemma4:31b` | AXX-mobile-android.java | 20/20 |
| `gemma4:31b` | AXX-nestjs-typescript.ts | 20/20 |
| `gemma4:31b` | AXX-nodejs-vulnerabilities.js | 20/20 |
| `gemma4:31b` | AXX-nosql-injection.js | 20/20 |
| `gemma4:31b` | AXX-oauth2-oidc.js | 20/20 |
| `gemma4:31b` | AXX-php-deserialization.php | 20/20 |
| `gemma4:31b` | AXX-python-vulnerabilities.py | 20/20 |
| `gemma4:31b` | AXX-ssl-tls-misconfig.py | 20/20 |
| `gemma4:31b` | AXX-ssti-twig.php | 20/20 |
| `gemma4:31b` | AXX-xxe-parser.php | 20/20 |
| `llama3.3:70b` | A01-broken-access-control.php | 18/20 |
| `llama3.3:70b` | A02-cryptographic-failures.php | 18/20 |
| `llama3.3:70b` | A03-injection.php | 18/20 |
| `llama3.3:70b` | A04-insecure-design.php | 18/20 |
| `llama3.3:70b` | A05-security-misconfiguration.php | 18/20 |
| `llama3.3:70b` | A06-vulnerable-components.php | 18/20 |
| `llama3.3:70b` | A07-auth-failures.php | 18/20 |
| `llama3.3:70b` | A08-integrity-failures.php | 18/20 |
| `llama3.3:70b` | A09-logging-failures.php | 18/20 |
| `llama3.3:70b` | A10-ssrf.php | 18/20 |
| `llama3.3:70b` | AXX-advanced-php-attacks.php | 18/20 |
| `llama3.3:70b` | AXX-api-bola.js | 18/20 |
| `llama3.3:70b` | AXX-bash-shell-vulnerabilities.sh | 20/20 |
| `llama3.3:70b` | AXX-docker-misconfig.py | 18/20 |
| `llama3.3:70b` | AXX-domain-defense-ics.php | 20/20 |
| `llama3.3:70b` | AXX-domain-education.php | 18/20 |
| `llama3.3:70b` | AXX-domain-finance.php | 18/20 |
| `llama3.3:70b` | AXX-domain-healthcare.php | 18/20 |
| `llama3.3:70b` | AXX-domain-llm-ai.py | 18/20 |
| `llama3.3:70b` | AXX-graphql-api.js | 18/20 |
| `llama3.3:70b` | AXX-java-vulnerabilities.java | 20/20 |
| `llama3.3:70b` | AXX-jwt-vulnerabilities.js | 20/20 |
| `llama3.3:70b` | AXX-ldap-xpath-injection.php | 18/20 |
| `llama3.3:70b` | AXX-mobile-android.java | 18/20 |
| `llama3.3:70b` | AXX-nestjs-typescript.ts | 18/20 |
| `llama3.3:70b` | AXX-nodejs-vulnerabilities.js | 18/20 |
| `llama3.3:70b` | AXX-nosql-injection.js | 20/20 |
| `llama3.3:70b` | AXX-oauth2-oidc.js | 18/20 |
| `llama3.3:70b` | AXX-php-deserialization.php | 18/20 |
| `llama3.3:70b` | AXX-python-vulnerabilities.py | 20/20 |
| `llama3.3:70b` | AXX-ssl-tls-misconfig.py | 18/20 |
| `llama3.3:70b` | AXX-ssti-twig.php | 18/20 |
| `llama3.3:70b` | AXX-xxe-parser.php | 20/20 |
| `qwen3.6:27b` ⚠️ | A01-broken-access-control.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A02-cryptographic-failures.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A03-injection.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A04-insecure-design.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A05-security-misconfiguration.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A06-vulnerable-components.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A07-auth-failures.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A08-integrity-failures.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A09-logging-failures.php | 18/20 |
| `qwen3.6:27b` ⚠️ | A10-ssrf.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-advanced-php-attacks.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-api-bola.js | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-bash-shell-vulnerabilities.sh | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-docker-misconfig.py | 20/20 |
| `qwen3.6:27b` ⚠️ | AXX-domain-defense-ics.php | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-domain-education.php | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-domain-finance.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-domain-healthcare.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-domain-llm-ai.py | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-graphql-api.js | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-java-vulnerabilities.java | 20/20 |
| `qwen3.6:27b` ⚠️ | AXX-jwt-vulnerabilities.js | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-ldap-xpath-injection.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-mobile-android.java | 20/20 |
| `qwen3.6:27b` ⚠️ | AXX-nestjs-typescript.ts | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-nodejs-vulnerabilities.js | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-nosql-injection.js | 18/20 |
| `qwen3.6:27b` ⚠️ | AXX-oauth2-oidc.js | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-php-deserialization.php | 20/20 |
| `qwen3.6:27b` ⚠️ | AXX-python-vulnerabilities.py | 20/20 |
| `qwen3.6:27b` ⚠️ | AXX-ssl-tls-misconfig.py | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-ssti-twig.php | 19/20 |
| `qwen3.6:27b` ⚠️ | AXX-xxe-parser.php | 20/20 |

---

## Anomalies détectées (score < 18)

| Modèle | Sample | Score | Cause probable |
|--------|--------|-------|----------------|
| `foundation-sec-reasoning` | A06-vulnerable-components.php | ⚠️ 16/20 | Détection partielle des CVE SBOM |
| `foundation-sec-reasoning` | AXX-ssti-twig.php | N/A | Score non extractible |
| `codestral:22b` | A06-vulnerable-components.php | ⚠️ 16/20 | Détection partielle des CVE SBOM |
| `codestral:22b` | A09-logging-failures.php | ⚠️ 16/20 | Sous-détection des fuites PII dans les logs |

---

## Recommandation GitLab CI

1. **`gemma4:31b`** — audit complet, 32/32 samples, plancher 18 → **choix principal**
2. **`codestral:22b`** — ultra-rapide (36s), bon pour pre-commit hook → **choix CI fast-path**
3. **`llama3.3:70b`** — pour l'architecture et la revue OWASP manuelle → **hors CI**
