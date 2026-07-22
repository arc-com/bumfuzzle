#!/usr/bin/env bash
# no-redundant-enabled-false.sh — checks that no rule in TARGET (default
# .bumfuzzle/config.yml) writes `enabled: false`. rule-runner.sh treats a
# missing enabled key identically to enabled: false (both mean disabled —
# see rule-runner.sh's `if [[ "$_enabled" != "true" ]]`), and the wizard
# itself never writes the literal false form (toggling a rule off deletes
# the key rather than setting it). A hand-edited `enabled: false` is
# redundant — omit the key instead.
set -euo pipefail

SCRIPT_NAME="no-redundant-enabled-false.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: no-redundant-enabled-false.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that no rule in TARGET writes the literal `enabled: false` — a
missing enabled key already means disabled, so the explicit false form is
redundant. Prints [FAIL:warn]/[PASS] lines to stdout; exits 0 if none
found, 1 if any are, 2 on a usage error.
EOF
}

TARGET=""
_TARGET_SET=false
_SHOW_HELP=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      _SHOW_HELP=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -*)
      printf 'no-redundant-enabled-false.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'no-redundant-enabled-false.sh: unexpected extra argument: %s\n\n' "$1" >&2
        usage >&2
        exit 2
      fi
      TARGET="$1"
      _TARGET_SET=true
      shift
      ;;
  esac
done

if [[ "$_SHOW_HELP" == true ]]; then
  usage
  exit 0
fi

TARGET="${TARGET:-.bumfuzzle/config.yml}"

_FINDINGS_WARN=0
_report_warn() {
  printf '[FAIL:warn] %s\n' "$1"
  _FINDINGS_WARN=$((_FINDINGS_WARN + 1))
  _log DEBUG "warn finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

_check() {
  local _n
  while IFS= read -r _n; do
    [[ -z "$_n" ]] && continue
    _report_warn "rule '$_n' writes enabled: false — omit the key instead, absence means the same thing"
  done < <(_lint_yq '.rules | .. | select(type == "!!map") | select(has("enabled")) | select(.enabled == false) | .name // "unnamed"')
}

_log INFO "checking for redundant enabled: false in $TARGET"
_check

if [[ "$_FINDINGS_WARN" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] no redundant enabled: false in %s\n' "$TARGET"
exit 0
