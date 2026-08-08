#!/usr/bin/env bash
# fingerprint.sh — tracks whether the inputs that drive `bumfuzzle run`'s
# prerequisites phase (TARGET, schema.yml, and every bumfuzzle-template*.yml
# under BUMFUZZLE_ROOT) have changed since the last clean prerequisites run,
# so run.sh's config_lint_check can be skipped when nothing did. Stores the
# fingerprint under TARGET's sibling meta.json, key "fingerprint".
#
#   check [TARGET]   — read-only: compares the current fingerprint against
#                       what's stored. Prints [FRESH] or [STALE] <reason>.
#                       Exits 0 if fresh, 1 if stale.
#   update [TARGET]  — mutative: recomputes and persists the current
#                       fingerprint. Idempotent — no write happens, and
#                       [SKIP] is printed instead, when the stored value
#                       already matches. --dry-run prints what would be
#                       written ([DRY-RUN]) without writing it.
# Bare invocation defaults to check, the side-effect-free subcommand.
set -euo pipefail

SCRIPT_NAME="fingerprint.sh"
BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$BUMFUZZLE_ROOT/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: fingerprint.sh [check|update] [-h|--help] [-v|--verbose] [--dry-run] [TARGET]

  check          (default) compares the current fingerprint against the one
                 stored in TARGET's sibling meta.json. Exits 0 if fresh,
                 1 if stale.
  update         recomputes and persists the current fingerprint into
                 TARGET's sibling meta.json. No-ops if already up to date.
  TARGET         path to the bumfuzzle config (default: .bumfuzzle/config.yml)
  --dry-run      update only: print what would be written, without writing
  -v, --verbose  show DEBUG-level detail on stderr

The fingerprint covers three inputs, any one of which invalidates it:
TARGET's own content, schema.yml, and every bumfuzzle-template*.yml under
BUMFUZZLE_ROOT (sorted, so more than one catalog file is supported without
a code change) — all three can change what a prerequisites run would find.

Exits 2 on a usage error.
EOF
}

# _fp_combine FILE... — order-independent combined hash over one or more
# files: each file's own "hash  path" line (so a rename is detected, not
# just a content change) is sorted, then hashed again as one unit.
_fp_combine() {
  local _files=("$@")
  [[ ${#_files[@]} -eq 0 ]] && { printf '%s' ""; return 0; }
  _sha256 "${_files[@]}" | LC_ALL=C sort | _sha256 | awk '{print $1}'
}

# _fp_compute TARGET — sets _FP_CONFIG, _FP_SCHEMA, _FP_TEMPLATES.
_fp_compute() {
  local _target="$1"
  _FP_CONFIG=$(_fp_combine "$_target")
  _FP_SCHEMA=$(_fp_combine "$BUMFUZZLE_ROOT/schema.yml")
  local _templates=()
  while IFS= read -r _t; do
    [[ -z "$_t" ]] && continue
    _templates+=("$_t")
  done < <(find "$BUMFUZZLE_ROOT" -maxdepth 1 -name 'bumfuzzle-template*.yml' | LC_ALL=C sort)
  _FP_TEMPLATES=$(_fp_combine "${_templates[@]}")
}

_meta_path() { printf '%s/meta.json' "$(dirname "$1")"; }

_print_command_reference() {
  printf 'Commands: check [TARGET] (default, read-only) | update [TARGET] [--dry-run] (writes meta.json)\n'
}

# -r/--unwrapScalar defaults to true for YAML input but false for yq's
# auto-detected JSON input, so meta.json's string values print quoted
# without it - explicit here since a quoted vs bare hash would otherwise
# never compare equal to the freshly computed one.
_read_stored() {
  local _meta="$1"
  _STORED_CONFIG="" _STORED_SCHEMA="" _STORED_TEMPLATES=""
  [[ -f "$_meta" ]] || return 0
  _STORED_CONFIG=$(yq -r '.fingerprint.config // ""' "$_meta" 2>/dev/null || true)
  _STORED_SCHEMA=$(yq -r '.fingerprint.schema // ""' "$_meta" 2>/dev/null || true)
  _STORED_TEMPLATES=$(yq -r '.fingerprint.templates // ""' "$_meta" 2>/dev/null || true)
}

_cmd_check() {
  local _target="$1"
  local _meta; _meta=$(_meta_path "$_target")
  _print_command_reference

  _log DEBUG "Checking fingerprint"
  _fp_compute "$_target"
  _log DEBUG "Computed fingerprint (config=$_FP_CONFIG schema=$_FP_SCHEMA templates=$_FP_TEMPLATES)"

  if [[ ! -f "$_meta" ]]; then
    _log DEBUG "No stored fingerprint - $(basename "$_meta") not found"
    printf '[STALE] No stored fingerprint at %s\n' "$_meta"
    exit 1
  fi

  _read_stored "$_meta"

  # fragments stay lowercase internally (they only ever appear mid-sentence,
  # comma-joined) and are capitalized once, below, at their sole point of
  # external use - so a Plain log line built from this never starts lowercase.
  local _reason=""
  [[ "$_STORED_CONFIG"    == "$_FP_CONFIG"    ]] || _reason="${_reason:+$_reason, }config changed"
  [[ "$_STORED_SCHEMA"    == "$_FP_SCHEMA"    ]] || _reason="${_reason:+$_reason, }schema.yml changed"
  [[ "$_STORED_TEMPLATES" == "$_FP_TEMPLATES" ]] || _reason="${_reason:+$_reason, }template catalog changed"

  if [[ -n "$_reason" ]]; then
    _reason="$(printf '%s' "$_reason" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    _log DEBUG "Fingerprint stale: $_reason"
    printf '[STALE] %s\n' "$_reason"
    exit 1
  fi

  _log DEBUG "Fingerprint fresh - nothing tracked has changed"
  printf '[FRESH] Nothing tracked has changed since the last clean prerequisites run\n'
  exit 0
}

# Writing meta.json is not gated behind a confirmation prompt (unlike other
# mutative actions per this project's script conventions): it is freely
# regenerable derived cache, never user-authored data, so there is nothing
# irreversible or consequential about overwriting it - and this runs on
# every `bumfuzzle run`, where a prompt would defeat the feature's own point.
_cmd_update() {
  local _target="$1"
  local _meta; _meta=$(_meta_path "$_target")

  _log DEBUG "Updating fingerprint"
  _fp_compute "$_target"
  _read_stored "$_meta"

  if [[ "$_STORED_CONFIG" == "$_FP_CONFIG" && "$_STORED_SCHEMA" == "$_FP_SCHEMA" && "$_STORED_TEMPLATES" == "$_FP_TEMPLATES" ]]; then
    _log DEBUG "Fingerprint already up to date - skipped"
    printf '[SKIP] %s already up to date\n' "$_meta"
    exit 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    _log DEBUG "Dry run - would write fingerprint to $(basename "$_meta")"
    printf '[DRY-RUN] would write fingerprint to %s (config=%s schema=%s templates=%s)\n' \
      "$_meta" "$_FP_CONFIG" "$_FP_SCHEMA" "$_FP_TEMPLATES"
    exit 0
  fi

  mkdir -p "$(dirname "$_meta")"
  [[ -f "$_meta" ]] || printf '{}\n' > "$_meta"
  yq -o=json -i \
    ".fingerprint.config = \"$_FP_CONFIG\" | .fingerprint.schema = \"$_FP_SCHEMA\" | .fingerprint.templates = \"$_FP_TEMPLATES\"" \
    "$_meta"
  _log DEBUG "Fingerprint written to $(basename "$_meta")"
  printf '[UPDATED] %s\n' "$_meta"
  exit 0
}

CMD="check"
if [[ $# -gt 0 && ( "$1" == "check" || "$1" == "update" ) ]]; then
  CMD="$1"
  shift
fi

DRY_RUN=false
TARGET=""
_target_set=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -*)
      printf '%s: unknown flag: %s\n\n' "$SCRIPT_NAME" "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_target_set" == true ]]; then
        printf '%s: unexpected extra argument: %s\n\n' "$SCRIPT_NAME" "$1" >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      _target_set=true
      shift
      ;;
  esac
done

TARGET="${TARGET:-.bumfuzzle/config.yml}"

if [[ "$DRY_RUN" == true && "$CMD" != "update" ]]; then
  printf '%s: --dry-run only applies to update\n\n' "$SCRIPT_NAME" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$TARGET" ]]; then
  printf '%s: TARGET not found: %s\n\n' "$SCRIPT_NAME" "$TARGET" >&2
  usage >&2
  exit 2
fi

_log DEBUG "Target: $TARGET, command: $CMD"

case "$CMD" in
  check)  _cmd_check "$TARGET" ;;
  update) _cmd_update "$TARGET" ;;
esac
