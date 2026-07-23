#!/usr/bin/env bash
# Regression test for the package.json script-injection (scripts/init.sh)
# and .bumfuzzle/config.yml auto-scaffold (scripts/run.sh) behavior. Run standalone
# (scripts/tests/test-init-run.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT="$ROOT/scripts/init.sh"
RUN="$ROOT/scripts/run.sh"
FIXTURE_DIR="$ROOT/tmp/test-init-run-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

rm -rf "$FIXTURE_DIR"
mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# -- init: no package.json in the project -> .bumfuzzle/config.yml only ----
d="$FIXTURE_DIR/no-pkg"
mkdir -p "$d"
out=$(cd "$d" && "$INIT" 2>&1) || fail "init (no package.json) exited non-zero: $out"
[[ -f "$d/.bumfuzzle/config.yml" ]] || fail "init (no package.json): .bumfuzzle/config.yml was not created"
grep -q 'Added "bf"' <<< "$out" && fail "init (no package.json): unexpectedly reported adding a script"
echo "OK init: no package.json present"

# -- init: package.json with no bf script -> script is injected ------------
d="$FIXTURE_DIR/pkg-no-bf"
mkdir -p "$d"
printf '{"name":"demo","scripts":{"test":"echo hi"}}' > "$d/package.json"
out=$(cd "$d" && "$INIT" 2>&1) || fail "init (pkg, no bf script) exited non-zero: $out"
grep -q 'Added "bf": "bf run" to package.json scripts' <<< "$out" \
  || fail "init (pkg, no bf script): expected 'Added' notice, got: $out"
[[ "$(jq -r '.scripts.bf' "$d/package.json")" == "bf run" ]] \
  || fail "init (pkg, no bf script): scripts.bf was not set to 'bf run'"
[[ "$(jq -r '.scripts.test' "$d/package.json")" == "echo hi" ]] \
  || fail "init (pkg, no bf script): pre-existing 'test' script was disturbed"
echo "OK init: package.json without a bf script"

# -- init: package.json with an existing bf script -> left untouched -------
d="$FIXTURE_DIR/pkg-existing-bf"
mkdir -p "$d"
printf '{"name":"demo","scripts":{"bf":"custom bf command"}}' > "$d/package.json"
out=$(cd "$d" && "$INIT" 2>&1) || fail "init (pkg, existing bf script) exited non-zero: $out"
grep -q 'package.json already has a "bf" script - leaving it as-is' <<< "$out" \
  || fail "init (pkg, existing bf script): expected 'leaving it as-is' notice, got: $out"
[[ "$(jq -r '.scripts.bf' "$d/package.json")" == "custom bf command" ]] \
  || fail "init (pkg, existing bf script): pre-existing bf script was overwritten"
echo "OK init: package.json with an existing bf script"

# -- init: .bumfuzzle/config.yml already present -> refuses to overwrite (no regression) --
d="$FIXTURE_DIR/no-pkg" # reuse the dir from the first case; .bumfuzzle/config.yml already exists there
(cd "$d" && "$INIT") > /dev/null 2>&1 && fail "init (.bumfuzzle/config.yml exists): expected non-zero exit, got success"
echo "OK init: refuses to overwrite an existing .bumfuzzle/config.yml"

# -- run: no .bumfuzzle/config.yml -> auto-scaffolds from template and continues ---
d="$FIXTURE_DIR/run-no-config"
mkdir -p "$d"
out=$(cd "$d" && "$RUN" 2>&1) || fail "run (no .bumfuzzle/config.yml) exited non-zero: $out"
[[ -f "$d/.bumfuzzle/config.yml" ]] || fail "run (no .bumfuzzle/config.yml): .bumfuzzle/config.yml was not scaffolded"
grep -q '\[INFO\] - Config not found - scaffolded from template: \.bumfuzzle/config\.yml' <<< "$out" \
  || fail "run (no .bumfuzzle/config.yml): expected scaffold notice, got: $out"
echo "OK run: auto-scaffolds .bumfuzzle/config.yml when missing"

# -- run: .bumfuzzle/config.yml already present -> no scaffold notice (no regression) --
d="$FIXTURE_DIR/run-existing-config"
mkdir -p "$d/.bumfuzzle"
cp "$ROOT/bumfuzzle-template.yml" "$d/.bumfuzzle/config.yml"
out=$(cd "$d" && "$RUN" 2>&1) || fail "run (existing .bumfuzzle/config.yml) exited non-zero: $out"
grep -q '\[INFO\].*scaffolded from template' <<< "$out" \
  && fail "run (existing .bumfuzzle/config.yml): unexpectedly reported scaffolding, got: $out"
echo "OK run: uses an existing .bumfuzzle/config.yml as-is"

echo "OK $(basename "$0")"
