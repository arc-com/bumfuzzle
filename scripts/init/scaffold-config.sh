#!/usr/bin/env bash
# scaffold-config.sh — creates .bumfuzzle/config.yml in the current
# directory from bumfuzzle-template.yml. Single job: scripts/init.sh calls
# this for the config-creation phase; wire-package-script.sh handles the
# package.json phase separately.
#
# Deliberately not idempotent in the usual "skip and exit 0" sense: an
# existing .bumfuzzle/config.yml is a hard stop (exit 1), not a skip,
# because it may already be user-customized, and treating "already there"
# as success risks masking that init was run against the wrong directory.
# scripts/tests/test-init-run.sh asserts this exact contract.
set -euo pipefail

SCRIPT_NAME="scaffold-config.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TEMPLATE="$BUMFUZZLE_ROOT/bumfuzzle-template.yml"
TARGET="$(pwd)/.bumfuzzle/config.yml"

usage() {
  cat <<'EOF'
Usage: scaffold-config.sh [-h|--help] [-v|--verbose] [--dry-run]

Creates .bumfuzzle/config.yml in the current directory from
bumfuzzle-template.yml. Fails if .bumfuzzle/config.yml already exists
(does not overwrite).

  -v, --verbose  show DEBUG-level detail on stderr
  --dry-run      print what would be created, without creating it

Exits 0 on success, 1 on failure, 2 on a usage error.
EOF
}

parse_init_args "$@"

_log DEBUG "Target: $TARGET"
if [[ -f "$TARGET" ]]; then
  _log ERROR "Config already exists"
  printf '[FAIL] .bumfuzzle/config.yml already exists in %s - refusing to overwrite\n' "$(pwd)"
  printf 'Use the wizard'"'"'s "Reset" action if you want to replace it with the template.\n'
  exit 1
fi
_log DEBUG "Config does not exist yet - proceeding"

_log DEBUG "Template: $TEMPLATE"
if [[ ! -f "$TEMPLATE" ]]; then
  _log ERROR "Template not found"
  printf '[FAIL] template not found: %s\n' "$TEMPLATE"
  exit 1
fi
_log DEBUG "Template is present"

if [[ "$DRY_RUN" == true ]]; then
  _log INFO "Dry run - would create config from template"
  printf 'Dry run, would create .bumfuzzle/config.yml from template\n'
  exit 0
fi

mkdir -p "$(pwd)/.bumfuzzle"
cp "$TEMPLATE" "$TARGET"
_log INFO "Created config"
_log DEBUG "Wrote: $TARGET"
printf 'Created %s\n' "$TARGET"
exit 0
