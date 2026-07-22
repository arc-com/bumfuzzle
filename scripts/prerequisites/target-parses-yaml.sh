#!/usr/bin/env bash
# target-parses-yaml.sh — confirms TARGET (default .bumfuzzle/config.yml)
# parses as valid YAML. Third gate in scripts/prerequisites.sh, after
# yq-installed.sh and target-exists.sh: every remaining prerequisite script
# queries TARGET's content with yq, which silently returns nothing on
# unparseable input rather than failing loudly — so this must catch that
# case before they run.
set -euo pipefail

SCRIPT_NAME="target-parses-yaml.sh"
VERBOSE=false
_log() {
  local _level="$1" _msg="$2"
  [[ "$_level" == "DEBUG" && "$VERBOSE" != true ]] && return 0
  printf '[%s][%s] - %s\n' "$SCRIPT_NAME" "$_level" "$_msg" >&2
}

usage() {
  cat <<'EOF'
Usage: target-parses-yaml.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that TARGET parses as valid YAML (via yq). Prints
[FAIL:structural]/[PASS] to stdout; exits 0 if TARGET parses, 1 if it
doesn't, 2 on a usage error.
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
      printf 'target-parses-yaml.sh: unknown flag: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$_TARGET_SET" == true ]]; then
        printf 'target-parses-yaml.sh: unexpected extra argument: %s\n\n' "$1" >&2
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

_log INFO "checking $TARGET parses as YAML"
if ! yq '.' "$TARGET" > /dev/null 2>&1; then
  _log INFO "$TARGET is not parseable YAML"
  printf '[FAIL:structural] %s is not parseable YAML\n' "$TARGET"
  exit 1
fi

_log INFO "$TARGET parses as YAML"
printf '[PASS] %s parses as YAML\n' "$TARGET"
exit 0
