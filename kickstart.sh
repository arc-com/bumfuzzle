#!/usr/bin/env bash
set -euo pipefail

# Resolve real script location even when called via symlink
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do SOURCE="$(readlink "$SOURCE")"; done
KICKSTART_REPO="$(cd "$(dirname "$SOURCE")" && pwd)"
KICKSTART_VERSION="$(cat "$KICKSTART_REPO/VERSION" 2>/dev/null || printf 'unknown')"

# ── Logging ───────────────────────────────────────────────────────────────────

DRY_RUN=false
log()  { printf '[kickstart] %s\n' "$*"; }
skip() { printf '[skip]    %s\n' "$*"; }
warn() { printf '[warn]    %s\n' "$*" >&2; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

NOT_SUPPORTED() { :; }

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

# ── Template helpers ──────────────────────────────────────────────────────────

subst() {
  sed "s|{{PROJECT_NAME}}|$PROJECT_NAME|g"
}

maybe_mkdir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    skip "directory exists: ${dir#"$PROJECT_DIR/"}"
  else
    log "mkdir ${dir#"$PROJECT_DIR/"}"
    run mkdir -p "$dir"
  fi
}

maybe_copy() {
  local src="$1" dest="$2"
  local label="${dest#"$PROJECT_DIR/"}"
  if [[ -e "$dest" ]]; then
    skip "$label exists"
    return
  fi
  log "write $label"
  if [[ "$DRY_RUN" == false ]]; then
    cp "$src" "$dest"
  fi
}

maybe_write_subst() {
  local src="$1" dest="$2"
  local label="${dest#"$PROJECT_DIR/"}"
  if [[ -e "$dest" ]]; then
    skip "$label exists"
    return
  fi
  log "write $label"
  if [[ "$DRY_RUN" == false ]]; then
    subst < "$src" > "$dest"
  fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
  printf 'kickstart v%s — scaffold a project in the current directory\n\n' "$KICKSTART_VERSION" >&2
  printf 'Usage: kickstart [options]\n\n' >&2
  printf 'Options:\n' >&2
  printf '  --config <file>                       Config override (default: settings.yml)\n' >&2
  printf '  --dry-run                             Print steps without executing\n' >&2
  printf '  --only <step[,step,...]>              Run only these steps\n' >&2
  printf '  --skip <step[,step,...]>              Skip these steps\n' >&2
  printf '\n' >&2
  printf 'Steps: git_init githooks directories gitignore env_files bumfuzzle_yml\n' >&2
  printf '       rules deploy_sh start_sh stop_sh vscode_settings claude_settings\n' >&2
  printf '       dependencies docker_compose readme initial_commit\n' >&2
  exit 1
}

# ── Arg parsing ───────────────────────────────────────────────────────────────

CONFIG_FILE=""
ONLY_STEPS=""
SKIP_STEPS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --only)    ONLY_STEPS="${2:-}"; shift 2 ;;
    --skip)    SKIP_STEPS="${2:-}"; shift 2 ;;
    *)         usage ;;
  esac
done

# ── Resolve project dir (always CWD) ─────────────────────────────────────────

PROJECT_DIR="$(pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# If bumfuzzle.yml exists, read project name from it
if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
  if command -v yq &>/dev/null; then
    _existing_name=$(yq '.project.name // ""' "$PROJECT_DIR/bumfuzzle.yml" 2>/dev/null || true)
    [[ -n "$_existing_name" && "$_existing_name" != "null" ]] && PROJECT_NAME="$_existing_name"
    log "read existing bumfuzzle.yml (name: $PROJECT_NAME)"
  fi
fi

# ── Config ────────────────────────────────────────────────────────────────────

[[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$KICKSTART_REPO/settings.yml"

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi

cfg() { yq "$1" "$CONFIG_FILE" 2>/dev/null; }

# ── Scaffold merge ────────────────────────────────────────────────────────────

_scaffold_merged=$(mktemp)

_build_scaffold_merged() {
  if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
    yq eval-all '. as $item ireduce ({}; . * $item)' "$KICKSTART_REPO/settings.yml" "$PROJECT_DIR/bumfuzzle.yml" > "$_scaffold_merged"
  else
    cp "$KICKSTART_REPO/settings.yml" "$_scaffold_merged"
  fi
}

_build_scaffold_merged

scaffold_enabled() {
  local _val
  _val=$(yq ".scaffold.${1}" "$_scaffold_merged" 2>/dev/null || echo "null")
  [[ -z "$_val" || "$_val" == "null" ]] && return 0
  [[ "$_val" == "true" ]]
}

artifact_enabled() {
  local _val
  _val=$(yq "(.artifacts.${1}.enabled) // \"false\"" "$_scaffold_merged" 2>/dev/null || echo "false")
  [[ "$_val" == "true" ]]
}

artifact_path() {
  yq ".artifacts.${1}.path" "$_scaffold_merged" 2>/dev/null
}

step_enabled() {
  local step="$1"
  if [[ -n "$ONLY_STEPS" ]]; then
    printf '%s' "$ONLY_STEPS" | tr ',' '\n' | grep -qx "$step" && return 0 || return 1
  fi
  if [[ -n "$SKIP_STEPS" ]]; then
    printf '%s' "$SKIP_STEPS" | tr ',' '\n' | grep -qx "$step" && return 1
  fi
  [[ "$(yq ".scaffold.steps.${step}" "$_scaffold_merged" 2>/dev/null)" != "false" ]]
}

# ── Header ────────────────────────────────────────────────────────────────────

printf '\n-- kickstart v%s (%s) %s\n' \
  "$KICKSTART_VERSION" "$PROJECT_NAME" \
  "$(printf '%0.s-' {1..40})"
[[ "$DRY_RUN" == true ]] && log "dry-run mode — no changes will be made"

# ── Source domains and run setup in sequence ──────────────────────────────────

. "$KICKSTART_REPO/domains/git.sh"
. "$KICKSTART_REPO/domains/hooks.sh"
. "$KICKSTART_REPO/domains/rules.sh"
. "$KICKSTART_REPO/domains/structure.sh"
. "$KICKSTART_REPO/domains/env.sh"
. "$KICKSTART_REPO/domains/preflight-config.sh"
. "$KICKSTART_REPO/domains/lifecycle.sh"
. "$KICKSTART_REPO/domains/editor.sh"
. "$KICKSTART_REPO/domains/dependencies.sh"
. "$KICKSTART_REPO/domains/docker.sh"
. "$KICKSTART_REPO/domains/config.sh"

preflight_config_setup
git_setup
hooks_setup
rules_setup
structure_setup
env_setup
lifecycle_setup
editor_setup
dependencies_setup
docker_setup

# ── Final steps (no domain equivalent) ───────────────────────────────────────

if step_enabled initial_commit; then
  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    skip "initial_commit: no git repo"
  else
    local_commit_count="$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || printf '0')"
    if [[ "$local_commit_count" -gt 0 ]]; then
      skip "initial_commit: repo already has commits"
    else
      local_msg="$(cfg '.initial_commit.message' 2>/dev/null)"
      [[ -z "$local_msg" || "$local_msg" == "null" ]] && local_msg="chore: scaffold {{PROJECT_NAME}}"
      local_msg="$(printf '%s' "$local_msg" | sed "s|{{PROJECT_NAME}}|$PROJECT_NAME|g")"
      log "git add -A && git commit --no-verify"
      if [[ "$DRY_RUN" == false ]]; then
        git -C "$PROJECT_DIR" add -A
        git -C "$PROJECT_DIR" commit --no-verify -m "$local_msg"
      fi
    fi
  fi
fi

printf '%s\n' '-----------------------------------------------------------------------'
log "done — $PROJECT_NAME scaffolded at $PROJECT_DIR"
printf '%s\n' '-----------------------------------------------------------------------'
