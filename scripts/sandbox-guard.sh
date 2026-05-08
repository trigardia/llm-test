#!/usr/bin/env bash
# sandbox-guard.sh — Validation obligatoire des sorties qwen2.5-coder:32b (sandbox)
# Usage : OLLAMA_HOST=127.0.0.1:11435 ollama run qwen2.5-coder:32b "question" | ./scripts/sandbox-guard.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ─── Patterns dangereux (ERE compatible macOS grep) ──────────────────────────
BLOCKED_PATTERNS=(
  "rm -rf"
  "curl.*bash"
  "wget.*bash"
  "base64.*decode"
  "/etc/passwd"
  "/etc/shadow"
  "/etc/hosts"
  "ssh-keygen"
  "chmod 777"
  "nohup"
  "os\.system"
  "/root/"
)

# ─── Lecture de l'entrée ─────────────────────────────────────────────────────
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
  echo -e "${YELLOW}⚠️  SANDBOX GUARD: Sortie vide.${RESET}" >&2
  exit 0
fi

echo -e "${YELLOW}━━━ SANDBOX GUARD — Analyse en cours ━━━━━━━━━━━━━━━━━━${RESET}" >&2

# ─── Vérification des patterns dangereux ─────────────────────────────────────
BLOCKED=0
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$INPUT" | grep -qi "$pattern" 2>/dev/null; then
    echo -e "${RED}❌ BLOQUÉ — Pattern dangereux : '$pattern'${RESET}" >&2
    BLOCKED=1
  fi
done

if [[ $BLOCKED -eq 1 ]]; then
  echo -e "${RED}━━━ SORTIE BLOQUÉE — Valider manuellement avant tout usage ━━━${RESET}" >&2
  exit 1
fi

# ─── Vérification chemins hors dossier de travail ────────────────────────────
WORK_DIR=$(pwd)
WORK_BASE=$(basename "$WORK_DIR")
if echo "$INPUT" | grep -qE "/etc/|/var/|/tmp/|/root/" 2>/dev/null; then
  echo -e "${RED}❌ BLOQUÉ — Référence chemin système détectée${RESET}" >&2
  exit 1
fi

# ─── Sortie validée ──────────────────────────────────────────────────────────
echo -e "${GREEN}✅ SANDBOX GUARD: Aucun pattern dangereux détecté${RESET}" >&2
echo -e "${YELLOW}⚠️  Validation humaine obligatoire avant commit ou exécution${RESET}" >&2
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2

echo "$INPUT"
