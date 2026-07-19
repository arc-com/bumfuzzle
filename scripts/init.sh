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

PKG_JSON="$(pwd)/package.json"
if [[ -f "$PKG_JSON" ]]; then
  if jq -e '.scripts.bf' "$PKG_JSON" > /dev/null 2>&1; then
    printf 'package.json already has a "bf" script - leaving it as-is\n'
  else
    _tmp="$(mktemp)"
    jq '.scripts = ((.scripts // {}) + {"bf": "bf run"})' "$PKG_JSON" > "$_tmp"
    mv "$_tmp" "$PKG_JSON"
    printf 'Added "bf": "bf run" to package.json scripts\n'
  fi
fi

printf 'Run `bumfuzzle wizard` to configure it, or `bumfuzzle run` to check it as-is.\n'
