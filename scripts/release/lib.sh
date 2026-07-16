# Shared helpers for the atomic release-*.sh scripts and the release.sh
# orchestrator. Meant to be sourced, not executed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="arc-com/bumfuzzle"
TAP_REPO="arc-com/homebrew-bumfuzzle"

# Formula/bumfuzzle.rb lives in the sibling arc-com/homebrew-tools repo, not
# in this repo - extracted so other project formulas can live alongside it.
HOMEBREW_TOOLS_DIR="$(cd "$ROOT/../homebrew-tools" 2> /dev/null && pwd || true)"

fail() { echo "error: $*" >&2; exit 1; }

current_version() { cat "$ROOT/VERSION"; }

require_homebrew_tools_dir() {
  [[ -n "$HOMEBREW_TOOLS_DIR" && -d "$HOMEBREW_TOOLS_DIR/.git" ]] \
    || fail "expected a sibling checkout of arc-com/homebrew-tools at $ROOT/../homebrew-tools
  git clone git@github.com:arc-com/homebrew-tools.git $ROOT/../homebrew-tools"
}

require_clean_worktree() {
  local dir="${1:-$ROOT}" status
  status="$(git -C "$dir" status --porcelain)"
  [[ -z "$status" ]] || fail "$dir is not clean - commit, stash, or discard first:
$status"
}

require_on_main_synced() {
  local dir="${1:-$ROOT}" branch
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == "main" ]] || fail "$dir must be on main (currently on $branch)"
  git -C "$dir" fetch origin main --quiet
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$(git -C "$dir" rev-parse origin/main)" ]] \
    || fail "$dir local main is not in sync with origin/main (pull or push first)"
}

require_tag_matches_head() {
  local version="$1" tag="v$1"
  git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" > /dev/null \
    || fail "tag $tag does not exist locally"
  [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse "refs/tags/$tag")" ]] \
    || fail "HEAD is not at tag $tag"
}

tag_exists_local() { git -C "$ROOT" rev-parse -q --verify "refs/tags/v$1" > /dev/null; }
tag_exists_remote() { [[ -n "$(git -C "$ROOT" ls-remote --tags origin "refs/tags/v$1")" ]]; }

gh_release_exists() { gh release view "v$1" --repo "$REPO" > /dev/null 2>&1; }

npm_version_exists() {
  local live
  live="$(npm view bumfuzzle@"$1" version 2>/dev/null || true)"
  [[ "$live" == "$1" ]]
}

pypi_version_exists() {
  curl -sf "https://pypi.org/pypi/bumfuzzle/$1/json" > /dev/null 2>&1
}

# Fails loudly if version $1 is already live anywhere, or already tagged.
# This is what makes shipping the same version twice impossible.
require_version_unreleased() {
  local v="$1"
  tag_exists_local "$v" && fail "tag v$v already exists locally"
  tag_exists_remote "$v" && fail "tag v$v already exists on origin"
  gh_release_exists "$v" && fail "GitHub release v$v already exists"
  npm_version_exists "$v" && fail "npm already serves bumfuzzle@$v"
  pypi_version_exists "$v" && fail "PyPI already serves bumfuzzle==$v"
  return 0
}

require_version_advances() {
  local new="$1" current="$2"
  [[ "$new" != "$current" ]] || fail "new version ($new) matches current VERSION ($current)"
  local highest
  highest="$(printf '%s\n%s\n' "$new" "$current" | sort -V | tail -1)"
  [[ "$highest" == "$new" ]] || fail "new version ($new) is not greater than current VERSION ($current)"
}

tarball_sha256() {
  local version="$1" url work sha
  url="https://github.com/$REPO/archive/refs/tags/v$version.tar.gz"
  work="$(mktemp -d)"
  curl -sL "$url" -o "$work/src.tar.gz"
  sha="$(shasum -a 256 "$work/src.tar.gz" | cut -d' ' -f1)"
  rm -rf "$work"
  printf '%s' "$sha"
}
