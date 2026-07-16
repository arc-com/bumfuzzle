#!/usr/bin/env bash
# Atomic step: create the GitHub Release for the tag matching VERSION.
# Safe to run standalone to retry just this step after a partial release.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

VERSION="$(current_version)"
require_tag_matches_head "$VERSION"
gh_release_exists "$VERSION" && fail "GitHub release v$VERSION already exists"

echo "==> Creating GitHub release v$VERSION"
gh release create "v$VERSION" --repo "$REPO" --title "v$VERSION" --generate-notes
echo "==> GitHub release v$VERSION created"
