#!/usr/bin/env bash
# install.sh — install bumfuzzle globally on this machine
#
# EXCEPTION: this script is the sole file in the repo permitted to write outside
# $PROJECT_DIR. It installs symlinks into $HOME/.local/bin by design.
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

mkdir -p "$BIN_DIR"

link_tool() {
  local name="$1" src="$2"
  local dest="$BIN_DIR/$name"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    printf '[skip]   %s already up to date\n' "$dest"
  else
    ln -sf "$src" "$dest"
    chmod +x "$src"
    printf '[link]   %s -> %s\n' "$dest" "$src"
  fi
}

printf '\nbumfuzzle v%s — global install\n\n' "$VERSION"

link_tool bumfuzzle "$REPO/scripts/bumfuzzle.sh"
link_tool bf "$REPO/scripts/bumfuzzle.sh"

printf '\n'

if ! printf '%s' "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  printf '[warn]   %s is not on your PATH\n' "$BIN_DIR"
  printf '         Add this to your shell profile:\n\n'
  printf '           export PATH="%s:$PATH"\n\n' "$BIN_DIR"
else
  printf '[ok]     %s is on your PATH\n' "$BIN_DIR"
fi

printf '\nDone. Run: bumfuzzle --help (or bf --help)\n\n'
