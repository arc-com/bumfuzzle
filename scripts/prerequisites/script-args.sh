#!/usr/bin/env bash
# script-args.sh — checks every script_reusable rule in TARGET (default
# .bumfuzzle/config.yml) against the args its referenced script declares:
# every required arg must be passed, and no passed arg may be undeclared.
set -euo pipefail

SCRIPT_NAME="script-args.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: script-args.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks every script_reusable rule's args against its script's declared
args. Prints [FAIL:error]/[PASS] lines to stdout; exits 0 if none found, 1
if any are, 2 on a usage error.
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
      printf 'script-args.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'script-args.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_FINDINGS_ERROR=0
_report_error() {
  printf '[FAIL:error] %s\n' "$1"
  _FINDINGS_ERROR=$((_FINDINGS_ERROR + 1))
  _log DEBUG "error finding: $1"
}
_lint_yq() { yq "$1" "$TARGET" 2>/dev/null || true; }

_check() {
  local _rule_lines _sid
  # every script_reusable rule as "script|name|ARG1,ARG2" lines
  _rule_lines=$(_lint_yq '.rules | .. | select(type == "!!map") | select(.type == "script_reusable") | (.script // "") + "|" + (.name // "unnamed") + "|" + ((.args // {}) | keys | join(","))')

  while IFS= read -r _sid; do
    [[ -z "$_sid" ]] && continue
    local _script_args _declared="" _required=""
    _script_args=$(_lint_yq "\"$_sid\" as \$sid | .scripts | .. | select(type == \"!!map\") | select(has(\"id\") and .id == \$sid) | .args[] | (.key // \"?\") + \" \" + ((.required // false) | tostring)")
    local _al _ak _areq
    while IFS= read -r _al; do
      [[ -z "$_al" ]] && continue
      _ak="${_al%% *}"
      _areq="${_al##* }"
      _declared="$_declared $_ak"
      [[ "$_areq" == "true" ]] && _required="$_required $_ak"
    done <<< "$_script_args"

    local _rs _rn _rkeys _req _rk
    while IFS='|' read -r _rs _rn _rkeys; do
      [[ "$_rs" == "$_sid" ]] || continue
      for _req in $_required; do
        case ",$_rkeys," in
          *",$_req,"*) ;;
          *) _report_error "rule '$_rn' is missing required arg '$_req' of script '$_sid'" ;;
        esac
      done
      for _rk in ${_rkeys//,/ }; do
        case " $_declared " in
          *" $_rk "*) ;;
          *) _report_error "rule '$_rn' passes arg '$_rk' not declared by script '$_sid'" ;;
        esac
      done
    done <<< "$_rule_lines"
  done < <(_lint_yq '.scripts | .. | select(type == "!!map") | select(has("id")) | .id' | sort -u)
}

_log INFO "checking script_reusable arg declarations against script args in $TARGET"
_check

if [[ "$_FINDINGS_ERROR" -gt 0 ]]; then
  exit 1
fi
printf "[PASS] all script_reusable args in %s match their script's declared args\n" "$TARGET"
exit 0
