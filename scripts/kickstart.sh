#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
KICKSTART_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"

# ── Logging ───────────────────────────────────────────────────────────────────

DRY_RUN=false
log()  { printf '[kickstart] %s\n' "$*"; }
skip() { printf '[skip]      %s\n' "$*"; }
warn() { printf '[warn]      %s\n' "$*" >&2; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]   %s\n' "$*"
  else
    "$@"
  fi
}

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

# ── Scaffold helpers ──────────────────────────────────────────────────────────

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

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
  printf 'bumfuzzle kickstart v%s — scaffold a project in the current directory\n\n' "$KICKSTART_VERSION" >&2
  printf 'Usage: bumfuzzle kickstart [options]\n\n' >&2
  printf 'Options:\n' >&2
  printf '  --config <file>            Config override (default: bumfuzzle-template.yml)\n' >&2
  printf '  --dry-run                  Print steps without executing\n' >&2
  printf '  --only <step[,step,...]>   Run only these steps\n' >&2
  printf '  --skip <step[,step,...]>   Skip these steps\n' >&2
  printf '\n' >&2
  printf 'Steps (see scaffold.steps in bumfuzzle.yml for enabled/disabled defaults):\n' >&2
  printf '  git_init gitignore githooks directories env_files\n' >&2
  printf '  vscode_settings claude_settings dependencies docker_compose\n' >&2
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

# ── Config ────────────────────────────────────────────────────────────────────

[[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"

if ! command -v yq &>/dev/null; then
  printf 'Error: yq is required\n' >&2; exit 1
fi

step_enabled() {
  local step="$1" cfg_enabled="$2"
  if [[ -n "$ONLY_STEPS" ]]; then
    printf '%s' "$ONLY_STEPS" | tr ',' '\n' | grep -qx "$step" && return 0 || return 1
  fi
  if [[ -n "$SKIP_STEPS" ]]; then
    printf '%s' "$SKIP_STEPS" | tr ',' '\n' | grep -qx "$step" && return 1
  fi
  [[ "$cfg_enabled" == "true" ]]
}

# ── Header ────────────────────────────────────────────────────────────────────

printf '\n-- kickstart v%s (%s) %s\n' \
  "$KICKSTART_VERSION" "$PROJECT_NAME" \
  "$(printf '%0.s-' {1..40})"
[[ "$DRY_RUN" == true ]] && log "dry-run mode — no changes will be made"

# bumfuzzle.yml itself is always created first (never overwritten) so every
# later step has scaffold.steps to read from. In --dry-run against a fresh
# project it's never actually written, so steps are read from CONFIG_FILE
# instead — otherwise dry-run on a new project would have no steps to preview.
maybe_copy "$CONFIG_FILE" "$PROJECT_DIR/bumfuzzle.yml"
STEPS_SOURCE="$PROJECT_DIR/bumfuzzle.yml"
[[ -f "$STEPS_SOURCE" ]] || STEPS_SOURCE="$CONFIG_FILE"

# ── Step implementations ──────────────────────────────────────────────────────

step_git_init() {
  if [[ -d "$PROJECT_DIR/.git" ]]; then
    skip "git repository already initialized"
  else
    log "git init"
    run git -C "$PROJECT_DIR" init -q
  fi
}

step_gitignore() {
  local dest="$PROJECT_DIR/.gitignore"
  if [[ -e "$dest" ]]; then
    skip ".gitignore exists"
    return
  fi
  log "write .gitignore"
  if [[ "$DRY_RUN" == false ]]; then
    cat > "$dest" <<'EOF'
.DS_Store
tmp/
.env
.env.*
EOF
  fi
}

# Renders one require_approval call per hooks.approval_gates entry in
# STEPS_SOURCE, substituted for the __APPROVAL_GATES__ marker line in the
# pre-commit template. Baked in once at copy time (see maybe_render_pre_commit)
# since kickstart never rewrites files it already deployed.
render_approval_gates() {
  local line label env_var pattern
  yq '.hooks.approval_gates[] | .label + "\t" + .env_var + "\t" + .pattern' "$STEPS_SOURCE" 2>/dev/null |
    while IFS=$'\t' read -r label env_var pattern; do
      is_blank "$label" && continue
      printf 'require_approval %q %q %q\n' "$label" "$env_var" "$pattern"
    done
}

maybe_render_pre_commit() {
  local src="$1" dest="$2"
  local label="${dest#"$PROJECT_DIR/"}"
  if [[ -e "$dest" ]]; then
    skip "$label exists"
    return
  fi
  log "write $label"
  if [[ "$DRY_RUN" == false ]]; then
    local line
    : > "$dest"
    while IFS= read -r line; do
      if [[ "$line" == "# __APPROVAL_GATES__" ]]; then
        render_approval_gates >> "$dest"
      else
        printf '%s\n' "$line" >> "$dest"
      fi
    done < "$src"
  fi
}

# Deploys the pre-commit/commit-msg hooks and the reinstaller script into the
# target project, then installs them into .git/hooks/ directly (rather than
# shelling out to the just-copied scripts/hooks.sh) so a rerun against
# already-installed hooks is a normal idempotent skip, not a --force error.
step_githooks() {
  maybe_mkdir "$PROJECT_DIR/.githooks"

  local f name
  for f in "$BUMFUZZLE_ROOT/scripts/hooks/templates/pre-commit" "$BUMFUZZLE_ROOT/scripts/hooks/commit-msg"; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    if [[ "$name" == "pre-commit" ]]; then
      maybe_render_pre_commit "$f" "$PROJECT_DIR/.githooks/$name"
    else
      maybe_copy "$f" "$PROJECT_DIR/.githooks/$name"
    fi
    [[ "$DRY_RUN" == false ]] && chmod +x "$PROJECT_DIR/.githooks/$name"
  done

  maybe_mkdir "$PROJECT_DIR/scripts"
  maybe_copy "$BUMFUZZLE_ROOT/scripts/hooks/hooks.sh" "$PROJECT_DIR/scripts/hooks.sh"
  [[ "$DRY_RUN" == false && -f "$PROJECT_DIR/scripts/hooks.sh" ]] && chmod +x "$PROJECT_DIR/scripts/hooks.sh"

  if [[ ! -d "$PROJECT_DIR/.git" ]]; then
    warn "not a git repository yet — hooks copied to .githooks/ but not installed into .git/hooks/"
    return
  fi

  for f in "$PROJECT_DIR"/.githooks/*; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    if [[ -e "$PROJECT_DIR/.git/hooks/$name" ]]; then
      skip ".git/hooks/$name already installed"
    else
      log "install .git/hooks/$name"
      if [[ "$DRY_RUN" == false ]]; then
        cp "$f" "$PROJECT_DIR/.git/hooks/$name"
        chmod +x "$PROJECT_DIR/.git/hooks/$name"
      fi
    fi
  done
}

step_directories() {
  local dirs d
  dirs=$(yq '.scaffold.steps[] | select(.id == "directories") | .args.DIRS[]' "$STEPS_SOURCE" 2>/dev/null || true)
  while IFS= read -r d; do
    is_blank "$d" && continue
    maybe_mkdir "$PROJECT_DIR/$d"
  done <<< "$dirs"
}

step_env_files() {
  local envs e dest
  envs=$(yq '.scaffold.steps[] | select(.id == "env_files") | .args.ENVIRONMENTS[]' "$STEPS_SOURCE" 2>/dev/null || true)
  while IFS= read -r e; do
    is_blank "$e" && continue
    dest="$PROJECT_DIR/.env.$e"
    if [[ -e "$dest" ]]; then
      skip ".env.$e exists"
    else
      log "write .env.$e"
      [[ "$DRY_RUN" == false ]] && : > "$dest"
    fi
  done <<< "$envs"
}

step_not_implemented() {
  skip "$1 — not yet implemented"
}

run_step() {
  local id="$1"
  case "$id" in
    git_init)       step_git_init ;;
    gitignore)      step_gitignore ;;
    githooks)       step_githooks ;;
    directories)    step_directories ;;
    env_files)      step_env_files ;;
    vscode_settings|claude_settings|dependencies|docker_compose)
      step_not_implemented "$id" ;;
    *) warn "unknown scaffold step '$id' — skipping" ;;
  esac
}

# ── Run steps from scaffold.steps in the project's bumfuzzle.yml ─────────────

step_count=$(yq '.scaffold.steps | length' "$STEPS_SOURCE" 2>/dev/null || echo 0)
is_blank "$step_count" && step_count=0

if [[ "$step_count" -eq 0 ]]; then
  warn "no scaffold.steps defined in bumfuzzle.yml — nothing to scaffold"
else
  for i in $(seq 0 $((step_count - 1))); do
    id=$(yq ".scaffold.steps[$i].id // \"\"" "$STEPS_SOURCE" 2>/dev/null || true)
    enabled=$(yq ".scaffold.steps[$i].enabled | tostring" "$STEPS_SOURCE" 2>/dev/null || echo null)
    is_blank "$id" && continue
    if step_enabled "$id" "$enabled"; then
      run_step "$id"
    else
      skip "$id (disabled)"
    fi
  done
fi

printf '%s\n' '-----------------------------------------------------------------------'
log "done — $PROJECT_NAME scaffolded at $PROJECT_DIR"
printf '%s\n' '-----------------------------------------------------------------------'
