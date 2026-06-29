#!/usr/bin/env bash
set -euo pipefail

# Resolve real script location before cd changes CWD
_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_SELF="$_SCRIPT_DIR/$(basename "$0")"
while [[ -L "$_SELF" ]]; do
  _LINK="$(readlink "$_SELF")"
  if [[ "$_LINK" = /* ]]; then _SELF="$_LINK"
  else _SELF="$(cd "$(dirname "$_SELF")" && cd "$(dirname "$_LINK")" && pwd)/$(basename "$_LINK")"
  fi
done
PREFLIGHT_REPO="$(cd "$(dirname "$_SELF")" && pwd)"

# cd to the project root: one level up if called from a scripts/ dir (client project),
# or stay in place if called directly from the repo root (self-validation)
if [[ "$(basename "$_SCRIPT_DIR")" == "scripts" ]]; then
  cd "$_SCRIPT_DIR/.."
elif [[ "$_SCRIPT_DIR" == "$PREFLIGHT_REPO" ]]; then
  cd "$_SCRIPT_DIR"
fi

PREFLIGHT_VERSION="$(cat "$PREFLIGHT_REPO/VERSION" 2>/dev/null || printf 'unknown')"
PREFLIGHT_FILE="bumfuzzle.yml"
ERRORS=()
WARNINGS=()
VERBOSE=false
_PENDING_HEADER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Usage: ./preflight.sh [--verbose|-v]"
      exit 1
      ;;
  esac
done

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

section() { _PENDING_HEADER="$1"; }

_flush_header() {
  if [[ -n "$_PENDING_HEADER" ]]; then
    printf '\n%s\n' "$_PENDING_HEADER"
    _PENDING_HEADER=""
  fi
}

pass() {
  if [[ "$VERBOSE" == true ]]; then
    _flush_header
    printf '[PASS] %s\n' "$1"
  fi
}

fail() {
  local _sev="${2:-error}"
  case "$_sev" in
    skip) return ;;
    warn)
      _flush_header
      printf '[WARN] %s\n' "$1"
      WARNINGS+=("$1")
      ;;
    hard-stop)
      _flush_header
      printf '[FAIL] %s\n' "$1"
      printf '[hard-stop] aborting preflight\n'
      exit 1
      ;;
    *)
      _flush_header
      printf '[FAIL] %s\n' "$1"
      ERRORS+=("$1")
      ;;
  esac
}

section '-- Prerequisites --------------------------------------------------------'

if ! command -v yq &>/dev/null; then
  _flush_header
  printf '[FAIL] yq is not installed - required to parse %s\n' "$PREFLIGHT_FILE"
  exit 1
fi

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  _flush_header
  printf '[FAIL] %s not found - cannot run validation\n' "$PREFLIGHT_FILE"
  exit 1
fi

pass "yq is installed"
pass "$PREFLIGHT_FILE is present"
pass "preflight v$PREFLIGHT_VERSION"

RULES_FILE="$PREFLIGHT_REPO/bumfuzzle-template.yml"
if [[ ! -f "$RULES_FILE" ]]; then
  printf '[FAIL] bumfuzzle-template.yml not found at %s\n' "$RULES_FILE"
  exit 1
fi
_project_preflight="$(pwd)/$PREFLIGHT_FILE"
_merged=$(mktemp)
yq eval-all '. as $item ireduce ({}; . * $item)' "$RULES_FILE" "$_project_preflight" > "$_merged"
pass "config merged"
PREFLIGHT_FILE="$_merged"

. "$PREFLIGHT_REPO/eval-rules.sh"

user_rules_check

printf '%s\n' '-----------------------------------------------------------------------'
if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  printf '  All checks passed\n'
  printf '%s\n' '-----------------------------------------------------------------------'
  exit 0
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf '  %d check(s) failed:\n' "${#ERRORS[@]}"
  for e in "${ERRORS[@]}"; do
    printf '    - %s\n' "$e"
  done
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  printf '  %d warning(s):\n' "${#WARNINGS[@]}"
  for w in "${WARNINGS[@]}"; do
    printf '    - %s\n' "$w"
  done
fi

printf '%s\n' '-----------------------------------------------------------------------'
[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
