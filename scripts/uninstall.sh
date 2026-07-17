#!/usr/bin/env bash
# uninstall.sh — remove the global bumfuzzle install created by install.sh
#
# EXCEPTION: this script is the sole file in the repo (alongside install.sh)
# permitted to write outside $PROJECT_DIR. It removes symlinks from
# $HOME/.local/bin by design.
# All other scripts must write only within the active project directory.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  target="$(readlink "$SOURCE")"
  SOURCE="$(cd "$(dirname "$SOURCE")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
done
REPO="$(cd "$(dirname "$SOURCE")/.." && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
VERSION="$(cat "$REPO/VERSION" 2>/dev/null || printf 'unknown')"

unlink_tool() {
  local name="$1" src="$2"
  local dest="$BIN_DIR/$name"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    rm "$dest"
    printf '[remove] %s\n' "$dest"
  elif [[ -e "$dest" || -L "$dest" ]]; then
    printf '[skip]   %s does not point to this repo, leaving it alone\n' "$dest"
  else
    printf '[skip]   %s not installed\n' "$dest"
  fi
}

printf '\nbumfuzzle v%s — global uninstall\n\n' "$VERSION"

unlink_tool bumfuzzle "$REPO/scripts/bumfuzzle.sh"
unlink_tool bf "$REPO/scripts/bumfuzzle.sh"

printf '\nDone.\n\n'
