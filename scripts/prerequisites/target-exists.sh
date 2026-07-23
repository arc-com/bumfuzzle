#!/usr/bin/env bash
# target-exists.sh — confirms TARGET (default .bumfuzzle/config.yml) exists.
# Second gate in scripts/prerequisites.sh, after yq-installed.sh: every
# remaining prerequisite script reads TARGET's content, so a missing file
# must stop the run before they do.
set -euo pipefail

SCRIPT_NAME="target-exists.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: target-exists.sh [-h|--help] [-v|--verbose] [TARGET]

  TARGET         path to the bumfuzzle config to check (default: .bumfuzzle/config.yml)
  -v, --verbose  show DEBUG-level detail on stderr

Checks that TARGET exists. Prints [FAIL:structural]/[PASS] to stdout;
exits 0 if TARGET exists, 1 if it doesn't, 2 on a usage error.
EOF
}

parse_target_args "$@"

_log DEBUG "Target: $TARGET"
_log INFO "Checking target exists"
if [[ ! -f "$TARGET" ]]; then
  _log ERROR "Target not found: $TARGET"
  printf '[FAIL:structural] %s not found\n' "$TARGET"
  exit 1
fi

_log INFO "Target is present"
printf '[PASS] %s is present\n' "$TARGET"
exit 0
