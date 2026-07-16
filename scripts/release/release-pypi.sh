#!/usr/bin/env bash
# Atomic step: build and publish the current VERSION to PyPI.
# Safe to run standalone to retry just this step after a partial release.
# Requires twine credentials to already be configured locally (~/.pypirc or
# TWINE_USERNAME/TWINE_PASSWORD).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

VERSION="$(current_version)"
require_tag_matches_head "$VERSION"
pypi_version_exists "$VERSION" && fail "PyPI already serves bumfuzzle==$VERSION"

echo "==> Building and publishing bumfuzzle==$VERSION to PyPI"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
(cd "$ROOT" && python3 -m build --outdir "$BUILD_DIR")
twine upload "$BUILD_DIR"/*
echo "==> PyPI serves bumfuzzle==$VERSION"
