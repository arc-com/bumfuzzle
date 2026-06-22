#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d ".git" ]]; then
  echo "Error: not a git repository"
  exit 1
fi

if [[ ! -d ".githooks" ]]; then
  echo "Error: .githooks not found"
  exit 1
fi

installed=0
failed=0

for SOURCE in .githooks/*; do
  [[ -f "$SOURCE" ]] || continue
  HOOK_NAME="$(basename "$SOURCE")"
  HOOK=".git/hooks/$HOOK_NAME"

  if [[ -e "$HOOK" && "${1:-}" != "--force" ]]; then
    echo "Error: $HOOK already exists; rerun with --force to overwrite it"
    failed=$((failed + 1))
    continue
  fi

  cp "$SOURCE" "$HOOK"
  chmod +x "$HOOK"
  echo "→ $HOOK_NAME hook installed at $HOOK"
  installed=$((installed + 1))
done

[[ $failed -gt 0 ]] && exit 1
echo "→ $installed hook(s) installed"
