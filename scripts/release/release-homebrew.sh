#!/usr/bin/env bash
# Atomic step: release the Homebrew channel for VERSION - bump the canonical
# Formula/bumfuzzle.rb (kept in the sibling arc-com/homebrew-tools repo, which
# customers tap directly as arc-com/tools - there is no separate public tap),
# commit, and push. Safe to run standalone to retry after a partial release.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_homebrew_tools_dir
FORMULA="$HOMEBREW_TOOLS_DIR/Formula/bumfuzzle.rb"

VERSION="$(current_version)"
require_tag_matches_head "$VERSION"
require_on_main_synced "$HOMEBREW_TOOLS_DIR"
require_clean_worktree "$HOMEBREW_TOOLS_DIR"

URL="https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz"
if grep -q "url \"$URL\"" "$FORMULA"; then
  echo "==> $FORMULA already points at v$VERSION"
  exit 0
fi

echo "==> Computing release tarball sha256 for v$VERSION"
SHA256="$(tarball_sha256 "$VERSION")"

echo "==> Updating $FORMULA to v$VERSION"
sed -i '' "s|^  url \".*\"|  url \"$URL\"|" "$FORMULA"
sed -i '' "s|^  sha256 \".*\"|  sha256 \"$SHA256\"|" "$FORMULA"
git -C "$HOMEBREW_TOOLS_DIR" add Formula/bumfuzzle.rb
git -C "$HOMEBREW_TOOLS_DIR" commit -m "$(cat <<EOF
chore(formula): bump to v$VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git -C "$HOMEBREW_TOOLS_DIR" push origin main
echo "==> $FORMULA bumped to v$VERSION and pushed - arc-com/tools now serves it"
