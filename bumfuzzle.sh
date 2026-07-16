#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  target="$(readlink "$SOURCE")"
  SOURCE="$(cd "$(dirname "$SOURCE")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
done
export BUMFUZZLE_ROOT="$(cd "$(dirname "$SOURCE")" && pwd)"

BUMFUZZLE_VERSION="$(cat "$BUMFUZZLE_ROOT/VERSION" 2>/dev/null || printf 'unknown')"

usage() {
  printf 'bumfuzzle v%s\n\n' "$BUMFUZZLE_VERSION"
  printf 'Usage: bumfuzzle <command> [options]\n\n'
  printf 'Commands:\n'
  printf '  wizard               Start the browser-based config wizard\n'
  printf '  kickstart            Scaffold a new project in the current directory\n'
  printf '    --config <file>      Config override (default: bumfuzzle-template.yml)\n'
  printf '    --dry-run            Print steps without executing\n'
  printf '    --only <steps>       Run only these steps (comma-separated)\n'
  printf '    --skip <steps>       Skip these steps (comma-separated)\n'
  printf '  preflight            Validate bumfuzzle.yml in the current directory\n'
  printf '    -v, --verbose        Show passing checks\n'
  printf '\n'
}

cmd="${1:-}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  wizard)            exec "$BUMFUZZLE_ROOT/scripts/wizard.sh"    "$@" ;;
  kickstart)         exec "$BUMFUZZLE_ROOT/scripts/kickstart.sh" "$@" ;;
  preflight)         exec "$BUMFUZZLE_ROOT/scripts/preflight.sh" "$@" ;;
  ""|-h|--help|help) usage ;;
  *) printf 'bumfuzzle: unknown command: %s\n\n' "$cmd" >&2; usage >&2; exit 1 ;;
esac
