#!/usr/bin/env bash
# Atomic step: push homebrew-tools' current Formula/bumfuzzle.rb to the
# Homebrew tap wholesale (never patches fields into the tap's separately
# cloned copy, so the tap can't drift from homebrew-tools in any field other
# than by this exact command).
#
# Safe to run standalone at any time to correct tap drift - e.g. the formula
# bump landed in homebrew-tools but this push failed last time (network,
# permissions), or the formula was hand-edited in homebrew-tools without a
# VERSION bump - without touching npm/PyPI/GitHub or cutting a new release.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_homebrew_tools_dir
FORMULA="$HOMEBREW_TOOLS_DIR/Formula/bumfuzzle.rb"

VERSION="$(current_version)"
URL="https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz"
grep -q "url \"$URL\"" "$FORMULA" \
  || fail "$FORMULA does not point at v$VERSION - run release-homebrew-formula.sh first"

echo "==> Syncing Homebrew tap ($TAP_REPO) to homebrew-tools' Formula/bumfuzzle.rb (v$VERSION)"
TAP_WORK="$(mktemp -d)"
trap 'rm -rf "$TAP_WORK"' EXIT
git clone --quiet "git@github.com:$TAP_REPO.git" "$TAP_WORK"

if diff -q "$FORMULA" "$TAP_WORK/Formula/bumfuzzle.rb" &> /dev/null; then
  echo "==> Tap is already in sync"
else
  cp "$FORMULA" "$TAP_WORK/Formula/bumfuzzle.rb"
  git -C "$TAP_WORK" add Formula/bumfuzzle.rb
  git -C "$TAP_WORK" commit -m "$(cat <<EOF
chore(formula): sync tap to v$VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
  git -C "$TAP_WORK" push origin main
fi
echo "==> Homebrew tap serves v$VERSION"
