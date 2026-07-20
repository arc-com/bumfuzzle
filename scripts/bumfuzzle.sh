#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  target="$(readlink "$SOURCE")"
  SOURCE="$(cd "$(dirname "$SOURCE")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
done
export BUMFUZZLE_ROOT="$(cd "$(dirname "$SOURCE")/.." && pwd)"

BUMFUZZLE_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"

usage() {
  printf 'bumfuzzle v%s\n\n' "$BUMFUZZLE_VERSION"
  printf 'Usage: bumfuzzle <command> [options]\n\n'
  printf 'Commands:\n'
  printf '  init                 Create .bumfuzzle/config.yml in the current project from the template\n'
  printf '  wizard               Start the browser-based config wizard\n'
  printf '  run                  Run every enabled check in .bumfuzzle/config.yml\n'
  printf '    -v, --verbose        Show passing checks\n'
  printf '  validate-schema      Check a config'"'"'s severity/on_missing/type values against schema.yml\n'
  printf '    [file]               Defaults to .bumfuzzle/config.yml in the current directory\n'
  printf '  lint-config          Check a config'"'"'s structure: duplicate ids, dangling references, required fields\n'
  printf '    [file]               Defaults to .bumfuzzle/config.yml in the current directory\n'
  printf '    -v, --verbose        Show DEBUG-level detail on stderr\n'
  printf '\n'
}

cmd="${1:-}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  init)               exec "$BUMFUZZLE_ROOT/scripts/init.sh"             "$@" ;;
  wizard)             exec "$BUMFUZZLE_ROOT/scripts/wizard.sh"           "$@" ;;
  run)                exec "$BUMFUZZLE_ROOT/scripts/run.sh"              "$@" ;;
  validate-schema)    exec "$BUMFUZZLE_ROOT/scripts/validate-schema.sh"  "$@" ;;
  lint-config)        exec "$BUMFUZZLE_ROOT/scripts/lint-config.sh"      "$@" ;;
  ""|-h|--help|help) usage ;;
  *) printf 'bumfuzzle: unknown command: %s\n\n' "$cmd" >&2; usage >&2; exit 1 ;;
esac
