#!/usr/bin/env bash
# Verifies the Homebrew formula in the sibling arc-com/homebrew-tools repo
# points at the current VERSION with the correct sha256, without installing
# anything - no Docker required. Doesn't prove `brew install` actually works
# end to end; see test-release-brew-deep.sh for that.
set -euo pipefail
source "$(cd "$(dirname "$0")/release" && pwd)/lib.sh"

VERSION="$(current_version)"
require_homebrew_tools_dir
FORMULA="$HOMEBREW_TOOLS_DIR/Formula/bumfuzzle.rb"
URL="https://github.com/$REPO/archive/refs/tags/v$VERSION.tar.gz"

echo "==> Computing release tarball sha256 for v$VERSION"
SHA256="$(tarball_sha256 "$VERSION")"

grep -q "url \"$URL\"" "$FORMULA" || fail "$FORMULA does not point at v$VERSION (url mismatch)"
grep -q "sha256 \"$SHA256\"" "$FORMULA" || fail "$FORMULA does not have the correct sha256 for v$VERSION"

echo "OK Homebrew formula (shallow) points at v$VERSION"
