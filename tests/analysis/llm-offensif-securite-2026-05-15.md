Synthèse complète — 5 recherches web parallèles (2026-05-15)
Sources : CrowdStrike, Talos, Picus, BlackHat/DEF CON 2025, GitHub, ArXiv, PortSwigger, Rapid7, Microsoft Security Blog.

---
État de l'art : LLMs offensifs & détection malware (mai 2026)

---
1. Ce que les hackers utilisent vraiment — consensus communauté

LLMs légitimes détournés (communauté offensive)

┌──────┬───────────────────────────┬─────────────────────────────────────────────────────────────┬────────────────────┐
│ Rang │          Modèle           │              Pourquoi les hackers le préfèrent              │ Disponible local ? │
├──────┼───────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────┤
│ 🥇   │ Claude Sonnet 4.6         │ Meilleur coding (82.1% SWE-bench), meilleur pentest général │ ❌ cloud           │
├──────┼───────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────┤
│ 🥈   │ foundation-sec-8b (Cisco) │ Seul LLM sécurité dédié open source, entraîné sur CVE/OWASP │ ✅ Ollama         │
├──────┼───────────────────────────┼─────────────────────────────────────────────────────────────┼────────────────────┤
│ 🥉   │ llama3.3:70b              │ Raisonnement fort, peu de filtres, local                    │ ✅ déjà installé   │
└──────┴───────────────────────────┴─────────────────────────────────────────────────────────────┴────────────────────┘

▎ Constat réel : les pentesters sérieux utilisent des LLMs généraux forts (Claude, GPT), pas des
▎ modèles "hacking spécialisés" qui restent limités. L'avantage vient du workflow agentic, pas du modèle.

---
2. Dark web / underground — menaces réelles identifiées (threat intel)

Ce que les rapports CrowdStrike, Talos, Picus ont documenté en 2026 :

┌─────────────┬──────────────────────────────────────────────┬───────────────────────────┐
│    Outil    │            Capacités documentées             │          Statut           │
├─────────────┼──────────────────────────────────────────────┼───────────────────────────┤
│ WormGPT     │ Phishing, génération exploit, zéro guardrail │ Actif, payant dark web    │
├─────────────┼──────────────────────────────────────────────┼───────────────────────────┤
│ FraudGPT    │ Malware payloads, code malveillant ciblé     │ Actif, underground forums │
├─────────────┼──────────────────────────────────────────────┼───────────────────────────┤
│ WolfGPT     │ Social engineering, manipulation             │ Actif                     │
├─────────────┼──────────────────────────────────────────────┼───────────────────────────┤
│ XXXGPT      │ Code malveillant, création malware           │ Actif                     │
├─────────────┼──────────────────────────────────────────────┼───────────────────────────┤
│ React2Shell │ Malware créé entièrement via LLM             │ Confirmé février 2026     │
└─────────────┴──────────────────────────────────────────────┴───────────────────────────┘

▎ Ce que ça signifie pour ta défense : ces outils produisent du code obfusqué, des shells inversés,
▎ et des payloads polymorphiques. Le sandbox-guard.sh (13 couches) et les SAST couvrent déjà ces patterns.

Vecteurs d'attaque dominants en 2026 (BlackHat/DEF CON 2025) :
- Prompt injection indirecte dans les systèmes agentiques
- Attaques MCP (tool poisoning, cross-server privilege escalation)
- RAG poisoning (empoisonnement bases de connaissances)
- LoRA fine-tuning malveillant
- Supply chain : LiteLLM backdooré sur PyPI (mars 2026, confirmé)
- Guardrails contournables à 64.1% par transfert inter-modèles

---
3. Agents de pentest autonomes — état de l'art

┌───────────────────────────┬──────────────┬───────────────────────┬─────────────────────────────────────┐
│           Agent           │ Stars GitHub │       Autonomie       │             Score réel              │
├───────────────────────────┼──────────────┼───────────────────────┼─────────────────────────────────────┤
│ PentAGI                   │ 14 700 ⭐    │ Pleine (multi-agents) │ End-to-end, Kali Linux containerisé │
├───────────────────────────┼──────────────┼───────────────────────┼─────────────────────────────────────┤
│ Excalibur (PentestGPT v2) │ —            │ Haute                 │ 91% CTF, 4/5 hosts AD compromis     │
├───────────────────────────┼──────────────┼───────────────────────┼─────────────────────────────────────┤
│ PentestGPT v1.0           │ 6 500 ⭐     │ Semi (copilote)       │ Mature, sorti déc. 2025             │
├───────────────────────────┼──────────────┼───────────────────────┼─────────────────────────────────────┤
│ XBOW                      │ —            │ Haute                 │ #1 HackerOne leaderboard US         │
├───────────────────────────┼──────────────┼───────────────────────┼─────────────────────────────────────┤
│ BlacksmithAI              │ —            │ Pleine                │ Lancé mars 2026, multi-agent        │
└───────────────────────────┴──────────────┴───────────────────────┴─────────────────────────────────────┘

Intégrations outils existants :
- Burp Suite : plugin AI natif (10K crédits gratuits/utilisateur Pro)
- Metasploit : MCP server msfmcpd (2026) — 8 outils, lecture seule pour l'instant
- Nuclei v10.4.3 : AI/LLM attack surface mapping + génération templates automatique

Benchmark de réalité :
  Pentest autonome réel         : 31% (humain encore nécessaire)
  Human-assisted + agent        : 64%
  CVE exploité en < 24h         : 28.3% de tous les CVE publiés
  MTTE (mean time to exploit)   : 2.3 ans (2018) → 20 heures (2026)
  Multi-agent vs single-agent   : +4.3x performance

---
4. Meilleurs outils de détection malware & code bizarre

Catégorie A — Reverse engineering / analyse binaire (LOCAL)

┌────────────────┬──────────────┬──────────────────────────────────────┬──────────────────────────────────────────┐
│     Outil      │     Base     │                  IA                  │                  Usage                   │
├────────────────┼──────────────┼──────────────────────────────────────┼──────────────────────────────────────────┤
│ GhidraMCP      │ Ghidra       │ 244+ outils MCP → n'importe quel LLM │ RE complet, renommage, P-code, debug     │
├────────────────┼──────────────┼──────────────────────────────────────┼──────────────────────────────────────────┤
│ Decyx          │ Ghidra       │ Claude API                           │ Fonction/variable renaming, explications │
├────────────────┼──────────────┼──────────────────────────────────────┼──────────────────────────────────────────┤
│ LLM4Decompile  │ Open source  │ LLM dédié décompilation              │ Binaires Linux x86_64 → C source         │
├────────────────┼──────────────┼──────────────────────────────────────┼──────────────────────────────────────────┤
│ ReverserAI     │ Binary Ninja │ LLM local (offline)                  │ Nommage sémantique, pas de cloud         │
├────────────────┼──────────────┼──────────────────────────────────────┼──────────────────────────────────────────┤
│ Cuckoo Sandbox │ Sandbox      │ ML comportemental                    │ Analyse dynamique locale                 │
└────────────────┴──────────────┴──────────────────────────────────────┴──────────────────────────────────────────┘

  GitHub :
  - GhidraMCP      : github.com/bethington/ghidra-mcp
  - Decyx          : github.com/philsajdak/decyx
  - LLM4Decompile  : github.com/albertan017/LLM4Decompile
  - ReverserAI     : github.com/mrphrazer/reverser_ai

Catégorie B — Détection code suspect dans dépôts (SAST)

┌───────────────┬────────────────────┬───────────┬─────────────────────────┬────────────────────────────────────────────┐
│     Outil     │    Open source     │ GitLab CI │      Langages toi       │                 Point fort                 │
├───────────────┼────────────────────┼───────────┼─────────────────────────┼────────────────────────────────────────────┤
│ Semgrep       │ ✅ + cloud         │ ✅ natif  │ PHP/JS/Java/Python/Bash │ 8x vrais positifs, 50% moins faux positifs │
├───────────────┼────────────────────┼───────────┼─────────────────────────┼────────────────────────────────────────────┤
│ GitLab AppSec │ ❌ (inclus GitLab) │ ✅ natif  │ Tous                    │ Intégration parfaite pipeline              │
├───────────────┼────────────────────┼───────────┼─────────────────────────┼────────────────────────────────────────────┤
│ SonarQube     │ ✅ community       │ ✅ natif  │ Tous                    │ Classique, fiable, qualité code            │
├───────────────┼────────────────────┼───────────┼─────────────────────────┼────────────────────────────────────────────┤
│ CodeQL        │ ✅                 │ ⚠️ API    │ Java/Python/JS fort     │ Sémantique profonde                        │
├───────────────┼────────────────────┼───────────┼─────────────────────────┼────────────────────────────────────────────┤
│ Snyk          │ ❌ SaaS            │ ✅        │ Tous                    │ Claude intégré, supply chain               │
└───────────────┴────────────────────┴───────────┴─────────────────────────┴────────────────────────────────────────────┘

Catégorie C — Threat intelligence / cloud

┌────────────────────────────┬────────────┬───────────────────────────────────────────────────────────────┐
│           Outil            │   Usage    │                         Particularité                         │
├────────────────────────────┼────────────┼───────────────────────────────────────────────────────────────┤
│ VirusTotal VTAI            │ API agent  │ Google Gemini intégré, analyse code packages                  │
├────────────────────────────┼────────────┼───────────────────────────────────────────────────────────────┤
│ Joe Sandbox AI             │ Cloud      │ Meilleure analyse comportementale malware                     │
├────────────────────────────┼────────────┼───────────────────────────────────────────────────────────────┤
│ ReversingLabs Spectra      │ Enterprise │ Détecte malware dans les modèles ML eux-mêmes                 │
├────────────────────────────┼────────────┼───────────────────────────────────────────────────────────────┤
│ Microsoft Backdoor Scanner │ Open       │ Détecte backdoors dans LLMs open-weight (Phi-4, Llama, Gemma) │
└────────────────────────────┴────────────┴───────────────────────────────────────────────────────────────┘

Détection patterns malveillants — ce qui fonctionne :

  Obfuscation / shellcode       → YARA + Semgrep (règles custom)
  Backdoor dans modèles ML      → Microsoft Backdoor Scanner
  Malware dans supply chain     → Snyk SCA + AquilaX
  Code à haute entropie         → sandbox-guard.sh couche 11 ✅
  Comportement dynamique        → Cuckoo Sandbox local
  Décompilation binaire         → GhidraMCP + LLM4Decompile
  CVE / OWASP review            → foundation-sec-8b

---
5. Recommandations pour ton pipeline DevSecOps GitLab CI

┌─────────────────────────────────────────────────────┐
│  PIPELINE GITLAB CI — STACK SÉCURITÉ OPTIMALE 2026  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Commit → Semgrep (SAST open source)                │
│        → GitLab AppSec (natif, DAST + secrets)      │
│        → SonarQube (qualité + vulnérabilités)       │
│                                                     │
│  Review IA → foundation-sec-8b (CVE/OWASP)          │
│           → llama3.3:70b (raisonnement global)      │
│                                                     │
│  Supply chain → Snyk SCA                            │
│  Binaires     → GhidraMCP + LLM4Decompile           │
│  Threat intel → VirusTotal VTAI API                 │
│                                                     │
└─────────────────────────────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROCÉDURE D'INSTALLATION SÉCURISÉE — foundation-sec-reasoning
(vérifiée le 2026-05-15 — téléchargement effectué)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Modèle retenu  : fdtn-ai/Foundation-Sec-8B-Reasoning-Q8_0-GGUF
  Date de sortie : 2026-01-28 (le plus récent de la gamme)
  Taille         : 8.5 Go (Q8_0 — qualité maximale pour M5 Max 128 GB)
  Licence        : Cisco Research License (non commerciale)
  Source unique  : https://huggingface.co/fdtn-ai  ← organisation officielle Cisco

  ⚠️  PAS dans le registry Ollama officiel (issue #10585 ouverte)
  ⚠️  Les ports communautaires (FenkoHQ, axonvertex) ne sont PAS vérifiés Cisco
  ✅  Seule chaîne de confiance : blogs.cisco.com → huggingface.co/fdtn-ai → GGUF

  Gamme complète fdtn-ai (toutes variantes officielles) :
  ┌─────────────────────────────────────────────┬────────────┬──────────────┐
  │ Modèle HuggingFace                          │ Date       │ Usage        │
  ├─────────────────────────────────────────────┼────────────┼──────────────┤
  │ fdtn-ai/Foundation-Sec-8B-Reasoning         │ 2026-01-28 │ Raisonnement │  ← RETENU
  │ fdtn-ai/Foundation-Sec-8B-Reasoning-Q8_0    │ 2026-01-28 │ GGUF Q8_0    │  ← TÉLÉCHARGÉ
  │ fdtn-ai/Foundation-Sec-8B-Reasoning-Q4_K_M  │ 2026-01-28 │ GGUF Q4      │
  │ fdtn-ai/Foundation-Sec-1.1-8B-Instruct      │ 2025-11-20 │ Ctx 64K      │
  │ fdtn-ai/Foundation-Sec-8B-Instruct          │ 2025-08-26 │ Ancienne     │
  │ fdtn-ai/Foundation-Sec-8B                   │ 2025-08-26 │ Base brute   │
  └─────────────────────────────────────────────┴────────────┴──────────────┘

  Procédure complète (reproduire via make foundation-sec-pull) :

    # 1. Installer huggingface-hub (CLI officielle)
    pip3 install huggingface-hub --break-system-packages

    # 2. Vérifier les fichiers disponibles (dry-run)
    hf download fdtn-ai/Foundation-Sec-8B-Reasoning-Q8_0-GGUF --dry-run
    # → confirme : foundation-sec-8b-reasoning-q8_0.gguf  8.5G

    # 3. Télécharger depuis la source officielle uniquement
    mkdir -p ~/models/foundation-sec-reasoning
    hf download fdtn-ai/Foundation-Sec-8B-Reasoning-Q8_0-GGUF \
      --local-dir ~/models/foundation-sec-reasoning

    # 4. Créer le modèle dans Ollama via Modelfile
    cat > /tmp/Modelfile-foundation-sec << 'EOF'
    FROM ~/models/foundation-sec-reasoning/foundation-sec-8b-reasoning-q8_0.gguf
    PARAMETER temperature 0.1
    PARAMETER num_ctx 8192
    EOF
    ollama create foundation-sec-reasoning -f /tmp/Modelfile-foundation-sec

    # 5. Vérifier l'installation
    ollama list | grep foundation-sec
    ollama run foundation-sec-reasoning "List OWASP Top 10 2025 categories"

  Usage dans le pipeline CI :
    cat fichier.php | ollama run foundation-sec-reasoning "Analyse OWASP Top 10"

  Commande make :
    make foundation-sec-pull   ← procédure complète automatisée

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ajouté dans security-test.sh (2026-05-15) :
  - ALL_MODELS : foundation-sec-reasoning en tête (modèle spécialisé sécurité)
  - model_size() : 9 Go
  - Confiance : ✅ Cisco US — pas de sandbox-guard requis

---
Modèles exclus (règles CLAUDE.md) :

  ❌ DeepSeek              — exclu explicitement
  ❌ GLM-4.5 (Zhipu AI)   — cloud chinois
  ❌ Qwen3-235B cloud      — API Alibaba
  ⚠️ metatron-qwen         — base Qwen/Alibaba → sandbox-guard.sh obligatoire si utilisé
