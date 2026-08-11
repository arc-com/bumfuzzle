#!/usr/bin/env bash
# Bumps VERSION locally: runs the static test suite (scripts/tests/run-all.sh),
# bumps VERSION, commits, and tags. Stops there by default - nothing is
# pushed and nothing is published. Pass --publish to also push main + the
# tag and run each atomic scripts/release/release-*.sh step (GitHub release,
# npm, PyPI, Homebrew - the last of which writes to the sibling
# arc-com/homebrew-tools repo, outside this project root) in parallel. Does
# not verify the channels itself - run scripts/tests/test-release.sh
# afterward for that. No GitHub Actions workflow is involved in publishing.
#
# --publish is opt-in and separate from the local bump on purpose: the
# publish steps push to a real remote and write to external registries and
# a sibling repo, which must never happen as a side effect of a plain
# version bump.
#
# The static test suite is a hard gate: nothing below it (version bump, tag,
# push, publish) runs unless it passes. Exists because v1.7.6 shipped
# bumfuzzle-template.yml with a rule value its own arg-type validator
# rejected - a structural bug in the default template that nothing gated on
# before release.
#
# The four publish steps only depend on the tag already existing - not on
# each other - so they run concurrently as background jobs. A failure in one
# doesn't stop the others: each job's exit status is collected after all
# finish, and every failing step is reported together (cumulative fail), not
# just the first one hit.
#
# Each release-*.sh step is also safe to run standalone (e.g. to retry one
# channel after a partial failure, or to publish after a prior local-only
# run) - it re-checks its own preconditions.
set -euo pipefail

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/release" && pwd)"
source "$RELEASE_DIR/lib.sh"

usage() {
  printf 'Usage: %s <new-version> [--publish]\n  e.g. %s 1.2.3\n  e.g. %s 1.2.3 --publish\n' \
    "$(basename "$0")" "$(basename "$0")" "$(basename "$0")"
}

PUBLISH=0
NEW_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -*) usage >&2; exit 1 ;;
    *)
      [[ -z "$NEW_VERSION" ]] || { usage >&2; exit 1; }
      NEW_VERSION="$arg"
      ;;
  esac
done
[[ -n "$NEW_VERSION" ]] || { usage >&2; exit 1; }
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be X.Y.Z"

require_on_main_synced
require_clean_worktree
require_version_advances "$NEW_VERSION" "$(current_version)"
require_version_unreleased "$NEW_VERSION"

echo "==> Running static test suite (scripts/tests/run-all.sh)"
"$ROOT/scripts/tests/run-all.sh" || fail "static test suite failed - fix it before releasing (see output above)"

echo "==> Bumping VERSION to $NEW_VERSION"
printf '%s\n' "$NEW_VERSION" > "$ROOT/VERSION"
"$ROOT/scripts/sync-package-version.sh"
git -C "$ROOT" add VERSION package.json
git -C "$ROOT" commit -m "$(cat <<EOF
chore(release): v$NEW_VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git -C "$ROOT" tag "v$NEW_VERSION"

if [[ "$PUBLISH" -ne 1 ]]; then
  echo "==> VERSION bumped, committed, and tagged locally as v$NEW_VERSION. Nothing pushed, nothing published."
  echo "==> Re-run with --publish to push main + the tag and publish to GitHub, npm, PyPI, and Homebrew:"
  echo "      $(basename "$0") $NEW_VERSION --publish"
  exit 0
fi

git -C "$ROOT" push origin main
git -C "$ROOT" push origin "v$NEW_VERSION"

echo "==> Publishing to GitHub, npm, PyPI, and Homebrew in parallel"
PUBLISH_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$PUBLISH_LOG_DIR"' EXIT

PUBLISH_STEPS=(release-github release-npm release-pypi release-homebrew)
PUBLISH_PIDS=()

for step in "${PUBLISH_STEPS[@]}"; do
  "$RELEASE_DIR/$step.sh" > "$PUBLISH_LOG_DIR/$step.log" 2>&1 &
  PUBLISH_PIDS+=("$!")
done

PUBLISH_FAILED=()
for i in "${!PUBLISH_STEPS[@]}"; do
  step="${PUBLISH_STEPS[$i]}"
  if wait "${PUBLISH_PIDS[$i]}"; then
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
echo "      scripts/tests/test-release.sh"
