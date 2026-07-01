#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_DIR="$(pwd)"
CONFIG_FILE="${1:-$BUMFUZZLE_ROOT/bumfuzzle-template.yml}"

# Temporary: only copies the template config so `preflight` has something to
# validate against. Full scaffolding (git hooks, dirs, env files, etc.) is
# tracked in the Roadmap and replaces this.
if [[ -f "$PROJECT_DIR/bumfuzzle.yml" ]]; then
  printf '[kickstart] bumfuzzle.yml already exists — skipping\n'
else
  printf '[kickstart] writing bumfuzzle.yml\n'
  cp "$CONFIG_FILE" "$PROJECT_DIR/bumfuzzle.yml"
fi

exit 0

# BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# KICKSTART_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
#
# # ── Logging ───────────────────────────────────────────────────────────────────
#
# DRY_RUN=false
# log()  { printf '[kickstart] %s\n' "$*"; }
# skip() { printf '[skip]    %s\n' "$*"; }
# warn() { printf '[warn]    %s\n' "$*" >&2; }
#
# run() {
#   if [[ "$DRY_RUN" == true ]]; then
#     printf '[dry-run] %s\n' "$*"
#   else
#     "$@"
#   fi
# }
#
# NOT_SUPPORTED() { :; }
#
# is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }
#
# # ── Template helpers ──────────────────────────────────────────────────────────
#
# subst() {
#   sed "s|{{PROJECT_NAME}}|$PROJECT_NAME|g"
# }
#
# maybe_mkdir() {
#   local dir="$1"
#   if [[ -d "$dir" ]]; then
#     skip "directory exists: ${dir#"$PROJECT_DIR/"}"
#   else
#     log "mkdir ${dir#"$PROJECT_DIR/"}"
#     run mkdir -p "$dir"
#   fi
# }
#
# maybe_copy() {
#   local src="$1" dest="$2"
#   local label="${dest#"$PROJECT_DIR/"}"
#   if [[ -e "$dest" ]]; then
#     skip "$label exists"
#     return
#   fi
#   log "write $label"
#   if [[ "$DRY_RUN" == false ]]; then
#     cp "$src" "$dest"
#   fi
# }
#
# maybe_write_subst() {
#   local src="$1" dest="$2"
#   local label="${dest#"$PROJECT_DIR/"}"
#   if [[ -e "$dest" ]]; then
#     skip "$label exists"
#     return
#   fi
#   log "write $label"
#   if [[ "$DRY_RUN" == false ]]; then
#     subst < "$src" > "$dest"
#   fi
# }
#
# # ── Usage ─────────────────────────────────────────────────────────────────────
#
# usage() {
#   printf 'bumfuzzle kickstart v%s — scaffold a project in the current directory\n\n' "$KICKSTART_VERSION" >&2
#   printf 'Usage: bumfuzzle kickstart [options]\n\n' >&2
#   printf 'Options:\n' >&2
#   printf '  --config <file>                       Config override (default: bumfuzzle-template.yml)\n' >&2
#   printf '  --dry-run                             Print steps without executing\n' >&2
#   printf '  --only <step[,step,...]>              Run only these steps\n' >&2
#   printf '  --skip <step[,step,...]>              Skip these steps\n' >&2
#   printf '\n' >&2
#   printf 'Steps: git_init githooks directories gitignore env_files bumfuzzle_yml\n' >&2
#   printf '       rules vscode_settings claude_settings\n' >&2
#   printf '       dependencies docker_compose readme\n' >&2
#   exit 1
# }
#
# # ── Arg parsing ───────────────────────────────────────────────────────────────
#
# CONFIG_FILE=""
# ONLY_STEPS=""
# SKIP_STEPS=""
#
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --config)  CONFIG_FILE="${2:-}"; shift 2 ;;
#     --dry-run) DRY_RUN=true; shift ;;
#     --only)    ONLY_STEPS="${2:-}"; shift 2 ;;
#     --skip)    SKIP_STEPS="${2:-}"; shift 2 ;;
#     *)         usage ;;
#   esac
# done
#
# # ── Resolve project dir (always CWD) ─────────────────────────────────────────
#
# PROJECT_DIR="$(pwd)"
# PROJECT_NAME="$(basename "$PROJECT_DIR")"
#
# # ── Config ────────────────────────────────────────────────────────────────────
#
# [[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
#
# if ! command -v yq &>/dev/null; then
#   printf 'Error: yq is required\n' >&2; exit 1
# fi
#
# step_enabled() {
#   local step="$1"
#   if [[ -n "$ONLY_STEPS" ]]; then
#     printf '%s' "$ONLY_STEPS" | tr ',' '\n' | grep -qx "$step" && return 0 || return 1
#   fi
#   if [[ -n "$SKIP_STEPS" ]]; then
#     printf '%s' "$SKIP_STEPS" | tr ',' '\n' | grep -qx "$step" && return 1
#   fi
#   return 0
# }
#
# # ── Header ────────────────────────────────────────────────────────────────────
#
# printf '\n-- kickstart v%s (%s) %s\n' \
#   "$KICKSTART_VERSION" "$PROJECT_NAME" \
#   "$(printf '%0.s-' {1..40})"
# [[ "$DRY_RUN" == true ]] && log "dry-run mode — no changes will be made"
#
# # ── Setup ─────────────────────────────────────────────────────────────────────
# # domain setup disabled — pending reimplementation
# # . "$BUMFUZZLE_ROOT/domains/git.sh"
# # . "$BUMFUZZLE_ROOT/domains/hooks.sh"
# # . "$BUMFUZZLE_ROOT/domains/rules.sh"
# # . "$BUMFUZZLE_ROOT/domains/structure.sh"
# # . "$BUMFUZZLE_ROOT/domains/env.sh"
# # . "$BUMFUZZLE_ROOT/domains/editor.sh"
# # . "$BUMFUZZLE_ROOT/domains/dependencies.sh"
# # . "$BUMFUZZLE_ROOT/domains/docker.sh"
# # . "$BUMFUZZLE_ROOT/domains/config.sh"
#
# if step_enabled bumfuzzle_yml; then
#   maybe_copy "$CONFIG_FILE" "$PROJECT_DIR/bumfuzzle.yml"
# fi
# # git_setup
# # hooks_setup
# # rules_setup
# # structure_setup
# # env_setup
# # editor_setup
# # dependencies_setup
# # docker_setup
#
# printf '%s\n' '-----------------------------------------------------------------------'
# log "done — $PROJECT_NAME scaffolded at $PROJECT_DIR"
# printf '%s\n' '-----------------------------------------------------------------------'
