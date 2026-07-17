#!/usr/bin/env bash
# Cuts a release end to end, entirely locally: bumps VERSION, tags, then runs
# each atomic scripts/release/release-*.sh step (GitHub release, npm, PyPI,
# Homebrew) in parallel. Does not verify the channels itself - run
# tests/release/test_release.sh afterward for that. No GitHub Actions
# workflow is involved in publishing.
#
# The four publish steps only depend on the tag already existing - not on
# each other - so they run concurrently as background jobs. A failure in one
# doesn't stop the others: each job's exit status is collected after all
# finish, and every failing step is reported together (cumulative fail), not
# just the first one hit.
#
# Each release-*.sh step is also safe to run standalone (e.g. to retry one
# channel after a partial failure) - it re-checks its own preconditions.
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/release" && pwd)"
source "$RELEASE_DIR/lib.sh"

usage() {
  printf 'Usage: %s <new-version>\n  e.g. %s 1.2.3\n' "$(basename "$0")" "$(basename "$0")"
}

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

echo "==> Publishing to GitHub, npm, PyPI, and Homebrew in parallel"
PUBLISH_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$PUBLISH_LOG_DIR"' EXIT

PUBLISH_STEPS=(release-github release-npm release-pypi release-homebrew)
declare -A PUBLISH_PIDS

for step in "${PUBLISH_STEPS[@]}"; do
  "$RELEASE_DIR/$step.sh" > "$PUBLISH_LOG_DIR/$step.log" 2>&1 &
  PUBLISH_PIDS[$step]=$!
done

PUBLISH_FAILED=()
for step in "${PUBLISH_STEPS[@]}"; do
  if wait "${PUBLISH_PIDS[$step]}"; then
    echo "==> $step succeeded"
  else
    PUBLISH_FAILED+=("$step")
    echo "==> $step FAILED"
  fi
  printf -- '---- %s output ----\n' "$step"
  cat "$PUBLISH_LOG_DIR/$step.log"
done

[[ ${#PUBLISH_FAILED[@]} -eq 0 ]] || fail "publish steps failed: ${PUBLISH_FAILED[*]} (each is safe to re-run standalone)"

echo "==> Release v$NEW_VERSION published to all four channels."
echo "==> Next step: verify it. Run:"
echo "      tests/release/test_release.sh"
