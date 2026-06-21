#!/usr/bin/env bash
# wizard.sh — browser-based project scaffolding wizard (wraps kickstart.sh)
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do SOURCE="$(readlink "$SOURCE")"; done
KICKSTART_REPO="$(cd "$(dirname "$SOURCE")" && pwd)"
KICKSTART_SH="$KICKSTART_REPO/kickstart.sh"
SETTINGS="$KICKSTART_REPO/settings.yml"
WIZARD_HTML="$KICKSTART_REPO/templates/wizard/index.html"
WIZARD_VERSION="$(cat "$KICKSTART_REPO/VERSION" 2>/dev/null || printf 'unknown')"

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi
if [[ ! -f "$WIZARD_HTML" ]]; then
  printf 'Error: wizard template not found: %s\n' "$WIZARD_HTML" >&2; exit 1
fi

PROJECT_DIR="$(pwd)"

# ── Detect purpose from manifests ─────────────────────────────────────────────

WIZ_PURPOSE="bare"
_n_pm=$(yq '.project.package_managers | length' "$SETTINGS")
_conflict=0
for _i in $(seq 0 $((_n_pm - 1))); do
  _manifest=$(yq ".project.package_managers[$_i].manifest" "$SETTINGS")
  _purpose=$(yq  ".project.package_managers[$_i].purpose"  "$SETTINGS")
  if [[ -f "$PROJECT_DIR/$_manifest" ]]; then
    if   [[ "$WIZ_PURPOSE" == "bare"         ]]; then WIZ_PURPOSE="$_purpose"
    elif [[ "$WIZ_PURPOSE" != "$_purpose"    ]]; then _conflict=1; break
    fi
  fi
done
[[ "$_conflict" -eq 1 ]] && WIZ_PURPOSE="bare" || true

# ── Build CONFIG JSON ──────────────────────────────────────────────────────────

SETTINGS_JSON=$(yq -o=json '.' "$SETTINGS")
CURRENT_JSON=$(yq -o=json '.' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || printf '{}')
PROJECT_DIR_NAME="$(basename "$PROJECT_DIR")"

CONFIG_JSON=$(printf '{"settings":%s,"current":%s,"meta":{"projectDir":"%s","projectDirName":"%s","detectedPurpose":"%s","version":"%s"}}' \
  "$SETTINGS_JSON" "$CURRENT_JSON" \
  "$PROJECT_DIR" "$PROJECT_DIR_NAME" "$WIZ_PURPOSE" "$WIZARD_VERSION")

WIZARD_DIR="$(dirname "$WIZARD_HTML")"
WIZARD_CONFIG_JS="$WIZARD_DIR/config.js"

# ── Write config.js alongside the source HTML (same-origin for file://) ───────

printf 'window.__CONFIG = %s;\n' "$CONFIG_JSON" > "$WIZARD_CONFIG_JS"
trap 'rm -f "$WIZARD_CONFIG_JS"' EXIT

# ── Open in browser ───────────────────────────────────────────────────────────

printf '\n  bumfuzzle wizard v%s\n' "$WIZARD_VERSION"
printf '  %s\n\n' "$(printf '%.0s─' {1..48})"
printf '  Opening wizard in browser...\n'
printf '  Save bumfuzzle.yml to: %s\n\n' "$PROJECT_DIR"

open "file://$WIZARD_HTML"

# ── Poll for bumfuzzle.yml (mtime-based so existing file doesn't skip) ────────

_existing_mtime=0
if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
  _existing_mtime=$(stat -f "%m" "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || echo 0)
fi

_timeout=300
_elapsed=0
while true; do
  if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
    _current_mtime=$(stat -f "%m" "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || echo 0)
    [[ "$_current_mtime" -gt "$_existing_mtime" ]] && break
  fi
  sleep 1
  _elapsed=$((_elapsed + 1))
  if [[ $_elapsed -ge $_timeout ]]; then
    printf '\nError: timed out after 5 minutes waiting for bumfuzzle.yml\n' >&2
    exit 1
  fi
done

printf '  bumfuzzle.yml written.\n'
