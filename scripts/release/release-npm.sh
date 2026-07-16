#!/usr/bin/env bash
# Atomic step: publish the current VERSION to npm.
# Safe to run standalone to retry just this step after a partial release.
# Requires npm publish credentials to already be configured locally (~/.npmrc).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

VERSION="$(current_version)"
require_tag_matches_head "$VERSION"
npm_version_exists "$VERSION" && fail "npm already serves bumfuzzle@$VERSION"

echo "==> Publishing bumfuzzle@$VERSION to npm"
(cd "$ROOT" && npm publish --access public)
echo "==> npm serves bumfuzzle@$VERSION"
