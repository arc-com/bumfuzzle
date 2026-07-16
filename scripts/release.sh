#!/usr/bin/env bash
# Cuts a release end to end, entirely locally: bumps VERSION, tags, then runs
# each atomic scripts/release/release-*.sh step (GitHub release, npm, PyPI,
# Homebrew), then re-verifies all four channels against VERSION. No GitHub
# Actions workflow is involved in publishing.
#
# Each release-*.sh step is also safe to run standalone (e.g. to retry one
# channel after a partial failure) - it re-checks its own preconditions.
#
# --sync-tap: re-push homebrew-tools' already-correct Formula/bumfuzzle.rb to
# the Homebrew tap for the current VERSION, without cutting a new release.
# Use it to correct tap drift without republishing to npm/PyPI.
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/release" && pwd)"
source "$RELEASE_DIR/lib.sh"

usage() {
  printf 'Usage: %s <new-version>\n  e.g. %s 1.2.3\n' "$(basename "$0")" "$(basename "$0")"
  printf '       %s --sync-tap\n  Re-push the current VERSION formula to the tap without a new release\n' "$(basename "$0")"
}

if [[ "${1:-}" == "--sync-tap" ]]; then
  "$RELEASE_DIR/release-homebrew.sh" --sync-tap
  "$ROOT/tests/release/test_release.sh"
  exit 0
fi

[[ $# -eq 1 ]] || { usage >&2; exit 1; }
NEW_VERSION="$1"
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be X.Y.Z"

require_on_main_synced
require_clean_worktree
require_version_advances "$NEW_VERSION" "$(current_version)"
require_version_unreleased "$NEW_VERSION"

echo "==> Bumping VERSION to $NEW_VERSION"
printf '%s\n' "$NEW_VERSION" > "$ROOT/VERSION"
git -C "$ROOT" add VERSION
git -C "$ROOT" commit -m "$(cat <<EOF
chore(release): v$NEW_VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git -C "$ROOT" tag "v$NEW_VERSION"
git -C "$ROOT" push origin main
git -C "$ROOT" push origin "v$NEW_VERSION"

"$RELEASE_DIR/release-github.sh"
"$RELEASE_DIR/release-npm.sh"
"$RELEASE_DIR/release-pypi.sh"
"$RELEASE_DIR/release-homebrew.sh"

echo "==> Verifying all channels now serve v$NEW_VERSION"
"$ROOT/tests/release/test_release.sh"

echo "==> Release v$NEW_VERSION shipped and verified."
