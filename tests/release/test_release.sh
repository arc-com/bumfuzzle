#!/usr/bin/env bash
# Smoke-tests the three live distribution channels against VERSION, so a
# workflow that reports green (e.g. npm-publish silently 403'ing while other
# jobs pass) can't mask a customer-facing release that never actually shipped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"

fail() { echo "FAIL: $*" >&2; exit 1; }

NPM_WORK=""
PYPI_WORK=""
cleanup() {
  [[ -n "$NPM_WORK" ]] && rm -rf "$NPM_WORK"
  [[ -n "$PYPI_WORK" ]] && rm -rf "$PYPI_WORK"
}
trap cleanup EXIT

assert_help() {
  local label="$1" output="$2"
  grep -q "^bumfuzzle v${VERSION}\$" <<< "$output" || {
    echo "FAIL: $label --help did not report bumfuzzle v$VERSION" >&2
    echo "$output" >&2
    exit 1
  }
}

# -- npm ----------------------------------------------------------------
npm_live="$(npm view bumfuzzle version 2>&1)" || fail "npm view bumfuzzle failed: $npm_live"
[[ "$npm_live" == "$VERSION" ]] || fail "npm registry serves v$npm_live, VERSION is v$VERSION"

NPM_WORK="$(mktemp -d)"
(cd "$NPM_WORK" && npm init -y > /dev/null 2>&1 && npm install --no-audit --no-fund "bumfuzzle@$VERSION" > /dev/null 2>&1) \
  || fail "npm install bumfuzzle@$VERSION failed"
assert_help "npm bumfuzzle" "$("$NPM_WORK/node_modules/.bin/bumfuzzle" --help 2>&1)"
assert_help "npm bf" "$("$NPM_WORK/node_modules/.bin/bf" --help 2>&1)"
echo "OK npm serves v$VERSION"

# -- PyPI -----------------------------------------------------------------
# Checks the version-specific endpoint, not the aggregate .../bumfuzzle/json
# one - the aggregate "latest" metadata can lag behind a fresh upload by a
# short window even after pip can already install the version fine.
curl -sf "https://pypi.org/pypi/bumfuzzle/$VERSION/json" > /dev/null \
  || fail "PyPI does not yet serve bumfuzzle==$VERSION"

PYPI_WORK="$(mktemp -d)"
python3 -m venv "$PYPI_WORK/venv"
"$PYPI_WORK/venv/bin/pip" install --quiet "bumfuzzle==$VERSION" || fail "pip install bumfuzzle==$VERSION failed"
assert_help "pip bumfuzzle" "$("$PYPI_WORK/venv/bin/bumfuzzle" --help 2>&1)"
assert_help "pip bf" "$("$PYPI_WORK/venv/bin/bf" --help 2>&1)"
echo "OK PyPI serves v$VERSION"

# -- Homebrew ---------------------------------------------------------------
# Deep check (test-release-brew-deep.sh) is not run here - it requires
# Docker, which isn't guaranteed to be available. Run it manually when
# Docker is up.
"$(dirname "$0")/test-release-brew-shallow.sh"

echo "OK $(basename "$0")"
