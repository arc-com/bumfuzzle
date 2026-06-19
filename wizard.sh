#!/usr/bin/env bash
# wizard.sh — interactive project scaffolding wizard (wraps kickoff.sh)
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do SOURCE="$(readlink "$SOURCE")"; done
KICKOFF_REPO="$(cd "$(dirname "$SOURCE")" && pwd)"
KICKOFF_SH="$KICKOFF_REPO/kickoff.sh"
SETTINGS="$KICKOFF_REPO/settings.yml"
WIZARD_VERSION="$(cat "$KICKOFF_REPO/VERSION" 2>/dev/null || printf 'unknown')"

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

ask() {
  local prompt="$1" default="$2" choices="$3"
  local display="$prompt"
  [[ -n "$choices" ]] && display="$display ($(printf '%s' "$choices" | tr '|' '/'))"
  [[ -n "$default" ]] && display="$display [$default]"
  printf '  %s: ' "$display"
  IFS= read -r _reply </dev/tty
  [[ -z "$_reply" ]] && _reply="$default"
  if [[ -n "$choices" ]] && ! printf '%s' "$choices" | tr '|' '\n' | grep -qx "$_reply"; then
    printf '  → invalid, using default: %s\n' "$default"
    _reply="$default"
  fi
}

cfg_wizard() { yq "$1" "$SETTINGS" 2>/dev/null || true; }

# ── Header ────────────────────────────────────────────────────────────────────

printf '\n  kickoff wizard v%s\n' "$WIZARD_VERSION"
printf '  %s\n\n' "$(printf '%.0s─' {1..48})"

# ── Project directory ─────────────────────────────────────────────────────────

PROJECT_DIR="${1:-}"
if [[ -z "$PROJECT_DIR" ]]; then
  printf '  Project directory: '
  IFS= read -r PROJECT_DIR </dev/tty
fi
[[ -z "$PROJECT_DIR" ]] && { printf 'Error: project directory is required\n' >&2; exit 1; }

# Expand to absolute path (directory may not exist yet)
if [[ ! -d "$PROJECT_DIR" ]]; then
  mkdir -p "$PROJECT_DIR"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ── Collect answers from wizard.questions in kickoff.settings.yml ─────────────

WIZ_PURPOSE="bare"
WIZ_NAME=""
WIZ_DOCKER="y"
WIZ_VSCODE="y"
WIZ_CLAUDE="y"

n=$(cfg_wizard '.wizard.questions | length')
for i in $(seq 0 $((n - 1))); do
  key=$(cfg_wizard ".wizard.questions[$i].key")
  prompt=$(cfg_wizard ".wizard.questions[$i].prompt")
  default=$(cfg_wizard ".wizard.questions[$i].default // \"\"")
  choices=$(cfg_wizard ".wizard.questions[$i].choices // [] | join(\"|\")" || echo "")
  only_types=$(cfg_wizard ".wizard.questions[$i].only_types // [] | join(\"|\")" || echo "")

  # Skip envs question (removed from Phase 5)
  [[ "$key" == "envs" ]] && continue

  if [[ -n "$only_types" && "$only_types" != "null" ]]; then
    if ! printf '%s' "$only_types" | tr '|' '\n' | grep -qx "$WIZ_PURPOSE"; then
      continue
    fi
  fi

  ask "$prompt" "$default" "$choices"

  case "$key" in
    type)   WIZ_PURPOSE="$_reply" ;;
    name)   WIZ_NAME="$_reply" ;;
    docker) WIZ_DOCKER="$_reply" ;;
    vscode) WIZ_VSCODE="$_reply" ;;
    claude) WIZ_CLAUDE="$_reply" ;;
  esac
done

[[ -z "$WIZ_NAME" ]] && WIZ_NAME="$(basename "$PROJECT_DIR")"

# ── Confirm ───────────────────────────────────────────────────────────────────

printf '\n  Summary:\n'
printf '    directory: %s\n' "$PROJECT_DIR"
printf '    purpose:   %s\n' "$WIZ_PURPOSE"
printf '    name:      %s\n' "$WIZ_NAME"
[[ "$WIZ_PURPOSE" == "backend" ]] && printf '    docker:    %s\n' "$WIZ_DOCKER"
printf '    vscode:    %s\n' "$WIZ_VSCODE"
printf '    claude:    %s\n' "$WIZ_CLAUDE"
printf '\n  Proceed? [Y/n]: '
IFS= read -r _confirm </dev/tty
[[ "$_confirm" == "n" || "$_confirm" == "N" ]] && { printf '\nAborted.\n'; exit 0; }

# ── Write seed bumfuzzle.yml ──────────────────────────────────────────────────

_bumfuzzle_path="$PROJECT_DIR/bumfuzzle.yml"
if [[ ! -f "$_bumfuzzle_path" ]]; then
  {
    printf 'project:\n'
    printf '  name: %s\n' "$WIZ_NAME"
    printf 'purpose: %s\n' "$WIZ_PURPOSE"
    printf 'scaffold:\n'
    printf '  docker:\n'
    if [[ "$WIZ_DOCKER" == "n" || "$WIZ_DOCKER" == "N" ]]; then
      printf '    server: false\n'
      printf '    etl: false\n'
      printf '    shared_infra: false\n'
    fi
    printf '  editor:\n'
    [[ "$WIZ_VSCODE" == "n" || "$WIZ_VSCODE" == "N" ]] && printf '    vscode: false\n' || true
    [[ "$WIZ_CLAUDE" == "n" || "$WIZ_CLAUDE" == "N" ]] && printf '    claude: false\n' || true
  } > "$_bumfuzzle_path"
  printf '[kickoff] write bumfuzzle.yml\n'
fi

# ── Run kickoff ───────────────────────────────────────────────────────────────

(cd "$PROJECT_DIR" && "$KICKOFF_SH")
