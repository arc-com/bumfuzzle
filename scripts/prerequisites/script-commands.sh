#!/usr/bin/env bash
# script-commands.sh — checks embedded shell commands in TARGET (default
# .bumfuzzle/config.yml): every scripts[].command and script_clean
# rules[].command must be non-empty and syntactically valid bash, and no
# two scripts should share byte-identical commands (a likely copy-paste
# that should probably be one script referenced twice instead).
set -euo pipefail

SCRIPT_NAME="script-commands.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: script-commands.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks embedded shell commands in TARGET for syntax errors and duplicates.
Prints [FAIL:structural]/[FAIL:error]/[FAIL:warn]/[PASS] lines to stdout;
exits 0 if no structural or error findings (warnings alone still exit 0),
1 if there are, 2 on a usage error.
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
      printf 'script-commands.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'script-commands.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

is_blank() { [[ -z "${1// }" || "${1:-}" == "null" ]]; }

_FINDINGS_STRUCTURAL=0
_FINDINGS_ERROR=0
_FINDINGS_WARN=0
_report_structural() {
  printf '[FAIL:structural] %s\n' "$1"
  _FINDINGS_STRUCTURAL=$((_FINDINGS_STRUCTURAL + 1))
  _log DEBUG "structural finding: $1"
}
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_report_warn() {
  printf '[FAIL:warn] %s\n' "$1"
  _FINDINGS_WARN=$((_FINDINGS_WARN + 1))
  _log DEBUG "warn finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }
_lint_sha256() { command -v sha256sum &>/dev/null && sha256sum "$@" || shasum -a 256 "$@"; }

_check() {
  local _sid _cmd _sha _seen=""
  while IFS= read -r _sid; do
    [[ -z "$_sid" ]] && continue
    _cmd=$(_lint_yq "\"$_sid\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .command // \"\"")
    if is_blank "$_cmd"; then
      _report_structural "script '$_sid' has no command"
      continue
    fi
    if ! printf '%s\n' "$_cmd" | bash -n 2>/dev/null; then
      _report_error "script '$_sid' has bash syntax errors"
    fi
    _sha=$(printf '%s' "$_cmd" | _lint_sha256 | awk '{print $1}')
    local _prev
    _prev=$(printf '%s\n' "$_seen" | grep "^$_sha " | head -1 | awk '{print $2}' || true)
    if [[ -n "$_prev" ]]; then
      _report_warn "scripts '$_prev' and '$_sid' have identical commands"
    else
      _seen="${_seen}${_sha} ${_sid}"$'\n'
    fi
  done < <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u)

  local _rc_count _ri _rcmd _rname
  _rc_count=$(_lint_yq '[.rules | .. | select(type == "!!map") | select(.type == "script_clean")] | length')
  is_blank "$_rc_count" && _rc_count=0
  if [[ "$_rc_count" -gt 0 ]]; then
    for _ri in $(seq 0 $((_rc_count - 1))); do
      _rcmd=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_clean\")] | .[$_ri].command // \"\"")
      is_blank "$_rcmd" && continue # missing command is reported by rule-fields.sh
      if ! printf '%s\n' "$_rcmd" | bash -n 2>/dev/null; then
        _rname=$(_lint_yq "[.rules | .. | select(type == \"!!map\") | select(.type == \"script_clean\")] | .[$_ri].name // \"?\"")
        _report_error "script_clean rule '$_rname' has bash syntax errors"
      fi
    done
  fi
}

_log INFO "checking embedded command bash syntax and duplicate script commands in $TARGET"
_check

if [[ "$_FINDINGS_STRUCTURAL" -gt 0 || "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf '[PASS] all embedded commands in %s are syntactically valid\n' "$TARGET"
if [[ "$_FINDINGS_WARN" -gt 0 ]]; then
  _log INFO "$_FINDINGS_WARN warning(s)"
fi
exit 0
