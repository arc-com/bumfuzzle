#!/usr/bin/env bash
# Atomic step: release the Homebrew channel for VERSION - bump the formula
# in homebrew-tools, then sync the tap to it. Safe to run standalone to
# retry the whole channel after a partial release.
#
# Delegates to the two finer sub-steps below, each of which is also safe to
# run standalone on its own to retry just that half:
#   release-homebrew-formula.sh - bump homebrew-tools' formula to VERSION
#   release-homebrew-tap.sh     - push the current formula to the tap
#
# --sync-tap: skip the formula bump and just re-push homebrew-tools'
# already-correct formula to the tap for the current VERSION, without
# cutting a new release. Use it to correct tap drift without republishing
# to npm/PyPI.
set -euo pipefail
RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--sync-tap" ]]; then
  "$RELEASE_DIR/release-homebrew-tap.sh"
  exit 0
fi

"$RELEASE_DIR/release-homebrew-formula.sh"
"$RELEASE_DIR/release-homebrew-tap.sh"
