#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
TARGET="$(pwd)/.bumfuzzle/config.yml"

SCRIPT_NAME="init.sh"
_log() { printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$1" "$2" >&2; }

if [[ $# -gt 0 ]]; then
  _log ERROR "unexpected argument(s): $*"
  printf 'Usage: bumfuzzle init\n'
  exit 1
fi

if [[ -f "$TARGET" ]]; then
  _log ERROR ".bumfuzzle/config.yml already exists in $(pwd)"
  printf '[FAIL] .bumfuzzle/config.yml already exists in %s - refusing to overwrite\n' "$(pwd)"
  printf 'Use the wizard'"'"'s "Reset" action if you want to replace it with the template.\n'
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  _log ERROR "template not found: $TEMPLATE"
  printf '[FAIL] template not found: %s\n' "$TEMPLATE"
  exit 1
fi

mkdir -p "$(pwd)/.bumfuzzle"
cp "$TEMPLATE" "$TARGET"
_log INFO "created $TARGET"
printf 'Created %s\n' "$TARGET"

PKG_JSON="$(pwd)/package.json"
if [[ -f "$PKG_JSON" ]]; then
  if jq -e '.scripts.bf' "$PKG_JSON" > /dev/null 2>&1; then
    _log INFO "package.json already has a \"bf\" script - leaving it as-is"
    printf 'package.json already has a "bf" script - leaving it as-is\n'
  else
    _tmp="$(mktemp)"
    jq '.scripts = ((.scripts // {}) + {"bf": "bf run"})' "$PKG_JSON" > "$_tmp"
    mv "$_tmp" "$PKG_JSON"
    _log INFO "added \"bf\": \"bf run\" to package.json scripts"
    printf 'Added "bf": "bf run" to package.json scripts\n'
  fi
fi

"$BUMFUZZLE_ROOT/scripts/sync-skill.sh" --target-dir "$(pwd)"

printf 'Run `bumfuzzle wizard` to configure it, or `bumfuzzle run` to check it as-is.\n'
