#!/usr/bin/env bash
# Cuts a release end to end: bumps VERSION, tags, waits for npm/PyPI to
# publish via .github/workflows/release.yml, then bumps both Homebrew
# formula copies directly (no PR - GitHub Actions isn't permitted to open
# PRs in this org, and the formula bump used to silently land in the wrong
# repo). Finishes by re-verifying all three channels against VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="arc-com/bumfuzzle"
TAP_REPO="arc-com/homebrew-bumfuzzle"

usage() { printf 'Usage: %s <new-version>\n  e.g. %s 1.2.3\n' "$(basename "$0")" "$(basename "$0")"; }

[[ $# -eq 1 ]] || { usage >&2; exit 1; }
NEW_VERSION="$1"
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must be X.Y.Z" >&2; exit 1; }

cd "$ROOT"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$CURRENT_BRANCH" == "main" ]] || { echo "error: must be on main (currently on $CURRENT_BRANCH)" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean" >&2; exit 1; }

git fetch origin main --quiet
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || { echo "error: local main is not in sync with origin/main (pull or push first)" >&2; exit 1; }

echo "==> Bumping VERSION to $NEW_VERSION"
printf '%s\n' "$NEW_VERSION" > VERSION
git add VERSION
git commit -m "$(cat <<EOF
chore(release): v$NEW_VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git tag "v$NEW_VERSION"
git push origin main
git push origin "v$NEW_VERSION"

echo "==> Waiting for the Release workflow to pick up v$NEW_VERSION"
RUN_ID=""
for _ in $(seq 1 12); do
  RUN_ID="$(gh run list --repo "$REPO" --workflow=release.yml --limit 5 \
    --json databaseId,headBranch -q ".[] | select(.headBranch == \"v$NEW_VERSION\") | .databaseId" 2>/dev/null | head -1 || true)"
  [[ -n "$RUN_ID" ]] && break
  sleep 5
done
[[ -n "$RUN_ID" ]] || { echo "error: could not find the triggered Release run for v$NEW_VERSION" >&2; exit 1; }

echo "==> Watching run $RUN_ID (verify, github-release, npm-publish, pypi-publish)"
gh run watch "$RUN_ID" --repo "$REPO" --exit-status \
  || { echo "error: Release workflow failed - see: gh run view $RUN_ID --repo $REPO" >&2; exit 1; }

echo "==> Computing release tarball sha256"
URL="https://github.com/$REPO/archive/refs/tags/v$NEW_VERSION.tar.gz"
TARBALL_DIR="$(mktemp -d)"
curl -sL "$URL" -o "$TARBALL_DIR/bumfuzzle-src.tar.gz"
SHA256="$(shasum -a 256 "$TARBALL_DIR/bumfuzzle-src.tar.gz" | cut -d' ' -f1)"
rm -rf "$TARBALL_DIR"

update_formula() {
  sed -i '' "s|^  url \".*\"|  url \"$URL\"|" "$1"
  sed -i '' "s|^  sha256 \".*\"|  sha256 \"$SHA256\"|" "$1"
}

echo "==> Updating Formula/bumfuzzle.rb in $REPO"
update_formula "$ROOT/Formula/bumfuzzle.rb"
git add Formula/bumfuzzle.rb
git commit -m "$(cat <<EOF
chore(formula): bump to v$NEW_VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git push origin main

echo "==> Updating the Homebrew tap ($TAP_REPO) directly - no PR"
TAP_WORK="$(mktemp -d)"
trap 'rm -rf "$TAP_WORK"' EXIT
git clone --quiet "git@github.com:$TAP_REPO.git" "$TAP_WORK"
update_formula "$TAP_WORK/Formula/bumfuzzle.rb"
git -C "$TAP_WORK" add Formula/bumfuzzle.rb
git -C "$TAP_WORK" commit -m "$(cat <<EOF
chore(formula): bump to v$NEW_VERSION

Co-Authored-By: Alan <noreply@archicode.ai>
EOF
)"
git -C "$TAP_WORK" push origin main

echo "==> Verifying all channels now serve v$NEW_VERSION"
"$ROOT/tests/release/test_release.sh"

echo "==> Release v$NEW_VERSION shipped and verified."
