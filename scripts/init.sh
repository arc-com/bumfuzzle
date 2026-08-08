#!/usr/bin/env bash
# init.sh — bootstraps a project for bumfuzzle: creates .bumfuzzle/config.yml
# from the template, wires a "bf" script into package.json if present, and
# syncs the bumfuzzle skill into .claude/ if present. An aggregate: each
# primitive lives in its own atomic script under scripts/init/, called here
# by path - scaffold-config.sh, wire-package-script.sh, and (unchanged)
# scripts/sync-skill.sh.
set -euo pipefail

BUMFUZZLE_ROOT="${BUMFUZZLE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INIT_DIR="$BUMFUZZLE_ROOT/scripts/init"

SCRIPT_NAME="init.sh"
source "$INIT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: init.sh [-h|--help] [-v|--verbose] [--dry-run] [--prettify]

Bootstraps the current directory for bumfuzzle: creates
.bumfuzzle/config.yml from the template, adds a "bf" script to
package.json if one is present and doesn't already have it, and syncs the
bumfuzzle skill into .claude/ if present. Fails if .bumfuzzle/config.yml
already exists.

  -v, --verbose  show DEBUG-level detail on stderr
  --dry-run      print what would change, without writing anything
  --prettify     wrap phase headers and the closing hint in decorated
                 banners (plain log lines only otherwise)

Exits 0 on success, 1 on failure, 2 on a usage error.
EOF
}

parse_init_args "$@"

_init_args=()
[[ "$VERBOSE" == true ]] && _init_args+=(--verbose)
[[ "$DRY_RUN" == true ]] && _init_args+=(--dry-run)

_log INFO "Starting init"

[[ "$PRETTIFY" == true ]] && printf '\n%s\n' "$(_section_line Config)"
"$INIT_DIR/scaffold-config.sh" ${_init_args[@]+"${_init_args[@]}"}

[[ "$PRETTIFY" == true ]] && printf '\n%s\n' "$(_section_line "Package Script")"
"$INIT_DIR/wire-package-script.sh" ${_init_args[@]+"${_init_args[@]}"}

[[ "$PRETTIFY" == true ]] && printf '\n%s\n' "$(_section_line "Skill Sync")"
_sync_args=(--target-dir "$(pwd)")
[[ "$VERBOSE" == true ]] && _sync_args+=(--verbose)
[[ "$DRY_RUN" == true ]] && _sync_args+=(--dry-run)
[[ "$PRETTIFY" == true ]] && _sync_args+=(--prettify)
"$BUMFUZZLE_ROOT/scripts/sync-skill.sh" "${_sync_args[@]}"

_log INFO "Init finished"

[[ "$PRETTIFY" == true ]] && printf '\n%s\n' "$(_banner_line)"
printf 'Run `bf wizard` to configure it, or `bf run` to check it as-is.\n'
[[ "$PRETTIFY" == true ]] && printf '%s\n' "$(_banner_line)"
exit 0
