#!/usr/bin/env bash
# target-parses-yaml.sh — confirms TARGET (default .bumfuzzle/config.yml)
# parses as valid YAML. Third gate in scripts/prerequisites.sh, after
# yq-installed.sh and target-exists.sh: every remaining prerequisite script
# queries TARGET's content with yq, which silently returns nothing on
# unparseable input rather than failing loudly — so this must catch that
# case before they run.
set -euo pipefail

SCRIPT_NAME="target-parses-yaml.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

parse_target_args "$@"

_log DEBUG "Target: $TARGET"
_log INFO "Checking target parses as YAML"
if ! yq '.' "$TARGET" > /dev/null 2>&1; then
  _log INFO "Target is not parseable YAML"
  printf '[FAIL:structural] %s is not parseable YAML\n' "$TARGET"
  exit 1
fi

_log INFO "Target parses as YAML"
printf '[PASS] %s parses as YAML\n' "$TARGET"
exit 0
