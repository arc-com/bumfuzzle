#!/usr/bin/env bash
# target-exists.sh — confirms TARGET (default .bumfuzzle/config.yml) exists.
# Second gate in scripts/prerequisites.sh, after yq-installed.sh: every
# remaining prerequisite script reads TARGET's content, so a missing file
# must stop the run before they do.
set -euo pipefail

SCRIPT_NAME="target-exists.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: target-exists.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that TARGET exists. Prints [FAIL:structural]/[PASS] to stdout;
exits 0 if TARGET exists, 1 if it doesn't, 2 on a usage error.
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
      printf 'target-exists.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'target-exists.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_log INFO "checking $TARGET exists"
if [[ ! -f "$TARGET" ]]; then
  _log ERROR "$TARGET not found"
  printf '[FAIL:structural] %s not found\n' "$TARGET"
  exit 1
fi

_log INFO "$TARGET is present"
printf '[PASS] %s is present\n' "$TARGET"
exit 0
