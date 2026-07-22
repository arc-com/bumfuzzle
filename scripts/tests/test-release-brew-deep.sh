#!/usr/bin/env bash
# Installs the current VERSION from the Homebrew tap inside a disposable
# linux/amd64 container and runs bumfuzzle/bf --help, proving `brew install`
# actually works end to end. Requires Docker; see test-release-brew-shallow.sh
# for a no-Docker formula-correctness check.
set -euo pipefail
source "$(cd "$(dirname "$0")/../release" && pwd)/lib.sh"

VERSION="$(current_version)"
HOMEBREW_TAP="arc-com/tools"

assert_help() {
  local label="$1" output="$2"
  grep -q "^bumfuzzle v${VERSION}\$" <<< "$output" || {
    echo "FAIL: $label --help did not report bumfuzzle v$VERSION" >&2
    echo "$output" >&2
    exit 1
  }
}

command -v docker > /dev/null 2>&1 || fail "docker is required to verify the Homebrew tap (not installed)"
docker info > /dev/null 2>&1 || fail "docker daemon is not running (start Docker Desktop and retry)"

# linux/amd64 is explicit: homebrew/brew has no native arm64 image, and Docker
# transparently emulates it on Apple Silicon.
brew_output="$(docker run --rm --platform linux/amd64 homebrew/brew:latest bash -c "
  set -e
  brew update >/dev/null 2>&1
  brew tap $HOMEBREW_TAP >/dev/null 2>&1
  brew trust $HOMEBREW_TAP >/dev/null 2>&1
  brew install bumfuzzle >/dev/null 2>&1
  bumfuzzle --help
  bf --help
" 2>&1)" || fail "brew tap/install/help failed: $brew_output"
assert_help "brew bumfuzzle" "$brew_output"

echo "OK Homebrew tap (deep) serves v$VERSION"
