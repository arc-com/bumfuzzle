#!/usr/bin/env bash
# wire-package-script.sh — adds "bf": "bf run" to package.json's scripts in
# the current directory, if package.json exists and has no "bf" script yet.
# Single job: scripts/init.sh calls this for the package-script phase;
# scaffold-config.sh handles config creation separately. No-op (exit 0) if
# there is no package.json, or it already has a "bf" script - both are
# genuinely idempotent "nothing to do" cases, unlike scaffold-config.sh's
# already-exists case (see that script's header comment).
set -euo pipefail

SCRIPT_NAME="wire-package-script.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PKG_JSON="$(pwd)/package.json"

usage() {
  cat <<'EOF'
Usage: wire-package-script.sh [-h|--help] [-v|--verbose] [--dry-run] [--prettify]

Adds "bf": "bf run" to package.json's scripts in the current directory, if
package.json exists and has no "bf" script yet. No-op if there is no
package.json, or it already has one.

  -v, --verbose  show DEBUG-level detail on stderr
  --dry-run      print what would change, without writing
  --prettify     accepted for a CLI shape consistent with init.sh; has no
                 effect here (this script never emits a Banner or Section)

Exits 0 on success (including no-op), 1 on failure, 2 on a usage error.
EOF
}

parse_init_args "$@"

_log DEBUG "Package.json: $PKG_JSON"

if [[ ! -f "$PKG_JSON" ]]; then
  _log INFO "No package.json - skipped"
  exit 0
fi
_log DEBUG "Package.json is present"

if jq -e '.scripts.bf' "$PKG_JSON" > /dev/null 2>&1; then
  _log INFO "Already has a bf script - skipped"
  printf 'package.json already has a "bf" script - leaving it as-is\n'
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  _log INFO "Dry run - would add bf script to package.json"
  printf 'Dry run, would add "bf": "bf run" to package.json scripts\n'
  exit 0
fi

_tmp="$(init_tmp_file)"
jq '.scripts = ((.scripts // {}) + {"bf": "bf run"})' "$PKG_JSON" > "$_tmp"
mv "$_tmp" "$PKG_JSON"
_log INFO "Added bf script to package.json"
printf 'Added "bf": "bf run" to package.json scripts\n'
exit 0
