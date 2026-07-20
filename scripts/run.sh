#!/usr/bin/env bash
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

RUN_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"
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
      printf 'Usage: bumfuzzle run [--verbose|-v]\n'
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
    printf '[run.sh][DEBUG] - [PASS] %s\n' "$1"
  fi
}

fail() {
  local _sev="${2:-error}"
  local _details="${3:-}"
  case "$_sev" in
    warn)
      _flush_header
      printf '[run.sh][WARN] - [WARN] %s\n' "$1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      WARNINGS+=("$1")
      ;;
    hard-stop)
      _flush_header
      printf '[run.sh][ERROR] - [FAIL] %s\n' "$1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      printf '[run.sh][ERROR] - [HARD-STOP] aborting run\n'
      exit 1
      ;;
    *)
      _flush_header
      printf '[run.sh][ERROR] - [FAIL] %s\n' "$1"
      [[ -n "$_details" ]] && printf '%s\n' "$_details"
      ERRORS+=("$1")
      ;;
  esac
}

section '-- Prerequisites --------------------------------------------------------'

if ! command -v yq &>/dev/null; then
  _flush_header
  printf '[run.sh][ERROR] - [FAIL] yq is not installed - required to parse %s\n' "$PREFLIGHT_FILE"
  exit 1
fi

if [[ ! -f "$PREFLIGHT_FILE" ]]; then
  TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
  if [[ ! -f "$TEMPLATE" ]]; then
    _flush_header
    printf '[run.sh][ERROR] - [FAIL] %s not found and template missing - cannot run validation\n' "$PREFLIGHT_FILE"
    exit 1
  fi
  cp "$TEMPLATE" "$PREFLIGHT_FILE"
  _flush_header
  printf '[run.sh][INFO] - %s not found - scaffolded from template\n' "$PREFLIGHT_FILE"
fi

pass "yq is installed"
pass "$PREFLIGHT_FILE is present"
pass "run v$RUN_VERSION"

# PREFLIGHT_FILE becomes absolute below so checks work regardless of any cwd
# change; PREFLIGHT_FILE_DISPLAY keeps the plain relative name for messages,
# so [PASS]/[FAIL] lines never leak this machine's absolute path.
PREFLIGHT_FILE_DISPLAY="$PREFLIGHT_FILE"
PREFLIGHT_FILE="$(pwd)/$PREFLIGHT_FILE"

. "$BUMFUZZLE_ROOT/scripts/eval-rules.sh"

# config lint runs as part of Prerequisites (see eval-rules.sh): it validates
# bumfuzzle.yml's own structure and is exempt from the enabled-rules gating
# that applies to user-defined rules — it always runs.
config_lint_check

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
