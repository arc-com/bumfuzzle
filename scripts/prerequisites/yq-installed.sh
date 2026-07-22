#!/usr/bin/env bash
# yq-installed.sh — confirms yq is on PATH. First gate in
# scripts/prerequisites.sh: every other prerequisite script shells out to yq
# against TARGET, so if yq isn't installed none of them can produce a
# meaningful result.
set -euo pipefail

SCRIPT_NAME="yq-installed.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: yq-installed.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         unused; accepted so every prerequisite script shares one CLI shape
  -v, --verbose  show DEBUG-level detail on stderr

Checks that yq is on PATH. Prints [FAIL:structural]/[PASS] to stdout;
exits 0 if yq is installed, 1 if it isn't, 2 on a usage error.
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
      printf 'yq-installed.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'yq-installed.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_log INFO "checking yq is installed"
if ! command -v yq &>/dev/null; then
  _log ERROR "yq is not installed"
  printf '[FAIL:structural] yq is not installed - required to parse %s\n' "$TARGET"
  exit 1
fi

_log INFO "yq is installed"
printf '[PASS] yq is installed\n'
exit 0
