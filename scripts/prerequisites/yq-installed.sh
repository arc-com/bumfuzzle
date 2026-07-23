#!/usr/bin/env bash
# yq-installed.sh — confirms yq is on PATH. First gate in
# scripts/prerequisites.sh: every other prerequisite script shells out to yq
# against TARGET, so if yq isn't installed none of them can produce a
# meaningful result.
set -euo pipefail

SCRIPT_NAME="yq-installed.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: yq-installed.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         unused; accepted so every prerequisite script shares one CLI shape
  -v, --verbose  show DEBUG-level detail on stderr

Checks that yq is on PATH. Prints [FAIL:structural]/[PASS] to stdout;
exits 0 if yq is installed, 1 if it isn't, 2 on a usage error.
EOF
}

parse_target_args "$@"

_log INFO "Checking yq is installed"
if ! command -v yq &>/dev/null; then
  _log ERROR "Yq is not installed"
  printf '[FAIL:structural] yq is not installed - required to parse %s\n' "$TARGET"
  exit 1
fi

_log INFO "Yq is installed"
printf '[PASS] yq is installed\n'
exit 0
