#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
TARGET="$(pwd)/bumfuzzle.yml"

if [[ $# -gt 0 ]]; then
  printf 'Usage: bumfuzzle init\n'
  exit 1
fi

if [[ -f "$TARGET" ]]; then
  printf '[FAIL] bumfuzzle.yml already exists in %s - refusing to overwrite\n' "$(pwd)"
  printf 'Use the wizard'"'"'s "Reset" action if you want to replace it with the template.\n'
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  printf '[FAIL] template not found: %s\n' "$TEMPLATE"
  exit 1
fi

cp "$TEMPLATE" "$TARGET"
printf 'Created %s\n' "$TARGET"
printf 'Run `bumfuzzle wizard` to configure it, or `bumfuzzle run` to check it as-is.\n'
