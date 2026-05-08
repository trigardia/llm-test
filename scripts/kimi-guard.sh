#!/usr/bin/env bash
# kimi-guard.sh — Validation obligatoire des sorties Kimi K2.6
# Usage : OLLAMA_HOST=127.0.0.1:11435 ollama run kimi-k2.6 "question" | ./scripts/kimi-guard.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ─── Patterns dangereux à bloquer ───────────────────────────────────────────
BLOCKED_PATTERNS=(
  "rm -rf"
  "curl.*\|.*bash"
  "wget.*\|.*bash"
  "eval.*\$("
  "base64.*decode"
  "/etc/passwd"
  "/etc/shadow"
  "/etc/hosts"
  "ssh-keygen"
  "chmod 777"
  "chmod \+s"
  "> /dev/null 2>&1 &"
  "nohup"
  "__import__.*os"
  "subprocess\.call"
  "os\.system"
  "\.\./\.\."
  "/root/"
  "/Users/[^/]*/\.\."
)

# ─── Lecture de l'entrée ─────────────────────────────────────────────────────
INPUT=$(cat)

if [[ -z "$INPUT" ]]; then
  echo -e "${YELLOW}⚠️  KIMI GUARD: Sortie vide.${RESET}" >&2
  exit 0
fi

echo -e "${YELLOW}━━━ KIMI GUARD — Analyse en cours ━━━━━━━━━━━━━━━━━━━${RESET}" >&2

# ─── Vérification des patterns dangereux ─────────────────────────────────────
BLOCKED=0
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$INPUT" | grep -qiE "$pattern"; then
    echo -e "${RED}❌ BLOQUÉ — Pattern dangereux détecté : '$pattern'${RESET}" >&2
    BLOCKED=1
  fi
done

if [[ $BLOCKED -eq 1 ]]; then
  echo -e "${RED}━━━ SORTIE BLOQUÉE — Valider manuellement avant tout usage ━━━${RESET}" >&2
  exit 1
fi

# ─── Vérification accès fichiers hors dossier de travail ─────────────────────
WORK_DIR=$(pwd)
if echo "$INPUT" | grep -qE "(\/Users\/[^/]+\/(?!$(basename $WORK_DIR))|\/etc\/|\/var\/|\/tmp\/|\/root\/)"; then
  echo -e "${RED}❌ BLOQUÉ — Référence à un chemin hors du dossier de travail : $WORK_DIR${RESET}" >&2
  exit 1
fi

# ─── Sortie validée ──────────────────────────────────────────────────────────
echo -e "${GREEN}✅ KIMI GUARD: Aucun pattern dangereux détecté${RESET}" >&2
echo -e "${YELLOW}⚠️  Validation humaine obligatoire avant commit ou exécution${RESET}" >&2
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2

# Afficher la sortie
echo "$INPUT"
