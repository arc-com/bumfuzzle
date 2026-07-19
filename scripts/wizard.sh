#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
RUN_SH="$BUMFUZZLE_ROOT/scripts/run.sh"
SETTINGS="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
SCHEMA="$BUMFUZZLE_ROOT/schema.yml"
BUMFUZZLE_HTML="$BUMFUZZLE_ROOT/index.html"
BUMFUZZLE_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
PORT=7373

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi
if ! command -v python3 &>/dev/null; then
  printf 'Error: python3 is required\n' >&2; exit 1
fi
if [[ ! -f "$BUMFUZZLE_HTML" ]]; then
  printf 'Error: bumfuzzle template not found: %s\n' "$BUMFUZZLE_HTML" >&2; exit 1
fi
if [[ ! -f "$SCHEMA" ]]; then
  printf 'Error: bumfuzzle schema not found: %s\n' "$SCHEMA" >&2; exit 1
fi
if lsof -i ":$PORT" -sTCP:LISTEN -t &>/dev/null 2>&1; then
  printf 'Error: port %d is already in use\n' "$PORT" >&2; exit 1
fi

PROJECT_DIR="$(pwd)"
PROJECT_DIR_NAME="$(basename "$PROJECT_DIR")"

if [[ ! -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
  printf 'Error: bumfuzzle.yml not found in %s\n' "$PROJECT_DIR" >&2
  printf 'Run `bumfuzzle init` to create it, then re-run `bumfuzzle wizard`.\n' >&2
  exit 1
fi

# ── Build CONFIG JSON ──────────────────────────────────────────────────────────

CURRENT_JSON=$(yq -o=json '.' "$PROJECT_DIR/bumfuzzle.yml")
SCHEMA_JSON=$(yq -o=json '.' "$SCHEMA")

META_JSON=$(printf '{"projectDir":"%s","projectDirName":"%s","version":"%s"}' \
  "$PROJECT_DIR" "$PROJECT_DIR_NAME" "$BUMFUZZLE_VERSION")

CONFIG_JSON=$(printf '{"current":%s,"meta":%s,"schema":%s}' \
  "$CURRENT_JSON" "$META_JSON" "$SCHEMA_JSON")

SERVER_PY="$BUMFUZZLE_ROOT/scripts/bumfuzzle_server.py"

# ── Export env vars for Python server ─────────────────────────────────────────

export BUMFUZZLE_PORT="$PORT"
export BUMFUZZLE_PROJECT_DIR="$PROJECT_DIR"
export BUMFUZZLE_RUN_SH="$RUN_SH"
export BUMFUZZLE_HTML
export BUMFUZZLE_CONFIG_JSON="$CONFIG_JSON"
export BUMFUZZLE_SETTINGS="$SETTINGS"

# ── Start server ──────────────────────────────────────────────────────────────

printf '\n  bumfuzzle v%s\n' "$BUMFUZZLE_VERSION"
printf '  %s\n\n' "$(printf '%.0s─' {1..48})"
printf '  Project: %s\n' "$PROJECT_DIR"
printf '  Serving: http://localhost:%d\n' "$PORT"
printf '  Press Ctrl+C to exit.\n\n'

( sleep 0.5; open "http://localhost:$PORT" ) &

# ── Replace this process with the server so the two can never become detached ──

exec python3 "$SERVER_PY"
