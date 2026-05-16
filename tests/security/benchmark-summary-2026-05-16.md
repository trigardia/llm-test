# 🔐 Security Benchmark LLM — OWASP Top 10:2025
**2026-05-16** · MacBook Pro M5 Max 128 Go · 7 modèles · 32 samples · PHP/Python/JS/Java/Bash/TypeScript

---

## 🏆 Classement final

| # | Modèle | Tests | Moy./20 | Plancher | Vitesse | CI GitLab | Origine |
|---|--------|-------|---------|----------|---------|-----------|---------|
| 🥇 | **`gemma4:31b`** | 33/32 | **19.94** | ✅ 18 | 54s | ✅ Principal | Google 🇺🇸 |
| 🥈 | **`codestral:22b`** | 33/32 | **18.88** | ⚠️ 16 | ⚡ 38s | ✅ Fast-path | Mistral 🇫🇷 |
| 🥉 | **`qwen3.6:27b`** | 33/32 | **18.73** | ✅ 18 | 75s | ⚠️ Sandbox | Alibaba 🇨🇳 |
| 4 | `llama3.3:70b` | 33/32 | **18.42** | ✅ 18 | 103s | ⚠️ Lent | Meta 🇺🇸 |
| 5 | `foundation-sec-reasoning` | 31/32 | **18.39** | ⚠️ 16 | ⚡ 35s | ✅ Léger | Sec-specific |
| 6 | `devstral-small-2` | 33/32 | **18.00** | ✅ 18 | 40s | ✅ Stable | Mistral 🇫🇷 |
| ❌ | ~~`phi4-reasoning:plus`~~ | 14/32 | ~19 | ⚠️ 15 | 🐢 618s | ❌ Exclu | Microsoft 🇺🇸 |

---

## 🎯 Recommandation GitLab CI

| Usage | Modèle | Pourquoi |
|-------|--------|---------|
| **Audit MR/PR** | `gemma4:31b` | Meilleur score, jamais sous 18, 32/32 complets |
| **Pre-commit hook** | `codestral:22b` | Le plus rapide (38s), 20/20 sur Top 10 OWASP |

---

## ⚠️ Anomalies détectées (score < 18)

| Modèle | Sample | Score | Cause probable |
|--------|--------|-------|----------------|
| `codestral:22b` | A06-vulnerable-components.php | ⚠️ 16 | Détection partielle CVE/SBOM |
| `codestral:22b` | A09-logging-failures.php | ⚠️ 16 | Sous-détection fuites PII |
| `foundation-sec-reasoning` | A06-vulnerable-components.php | ⚠️ 16 | Détection partielle CVE/SBOM |
| `phi4-reasoning:plus` | A04-insecure-design.php | ⚠️ 15 | Auto-scoring instable (boucle `<think>`) |

---

## 📌 Notes

- `qwen3.6:27b` — sortie obligatoirement filtrée via `sandbox-guard.sh` (règle CLAUDE.md, origine Alibaba 🇨🇳)
- `phi4-reasoning:plus` — exclu du CI : modèle de raisonnement étendu, 618s/sample, scoring instable. Usage recommandé : architecture, SOLID, Java (hors pipeline automatisé)
- Référence complète : `tests/security/benchmark-comparative-2026-05-16.md`
- Fix sandbox-guard : `scripts/security-test.sh` — séparation check/capture pour `qwen3.6:27b`
