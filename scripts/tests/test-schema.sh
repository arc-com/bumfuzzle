#!/usr/bin/env bash
# Regression test for schema.yml's own contract, run standalone
# (scripts/tests/test-schema.sh) or before a release alongside test-release.sh.
#
# Exists because of a real incident: schema.yml once required every arg
# object to literally contain a "required" key, while index.html's
# generateYaml() (and scripts/rule-runner.sh's own `.required // false`
# reader) treat an absent "required" as false, same as every other optional
# boolean flag on the node (list, multi_select, ...). That mismatch meant
# any wizard-authored .bumfuzzle/config.yml with an optional arg failed schema
# validation and hard-stopped `bumfuzzle run` for every user who touched the
# wizard. Nothing in this repo's own dogfooded .bumfuzzle/config.yml or
# bumfuzzle-template.yml (both hand-authored with "required" always
# explicit) could ever have exercised that path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATE="$ROOT/scripts/prerequisites/validate-schema.sh"
FIXTURE_DIR="$ROOT/tmp/test-schema-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

assert_pass() {
  local name="$1" file="$2"
  "$VALIDATE" "$file" > /dev/null 2>&1 || fail "$name: expected $file to pass schema validation, it failed"
  echo "OK $name"
}

assert_fail() {
  local name="$1" file="$2"
  "$VALIDATE" "$file" > /dev/null 2>&1 && fail "$name: expected $file to fail schema validation, it passed"
  echo "OK $name"
}

# -- required omitted on an optional arg: must PASS (the regression) -----
cat > "$FIXTURE_DIR/omitted-required.yml" <<'EOF'
schema_version: 1
scripts:
  - id: test-optional-arg
    name: Test optional arg
    command: "true"
    args:
      - key: OPTIONAL_ARG
        label: Optional arg
        type: string
EOF
assert_pass "arg with required omitted" "$FIXTURE_DIR/omitted-required.yml"

# -- required explicit true/false: must still PASS (no regression) -------
cat > "$FIXTURE_DIR/explicit-required.yml" <<'EOF'
schema_version: 1
scripts:
  - id: test-explicit-arg
    name: Test explicit arg
    command: "true"
    args:
      - key: REQUIRED_ARG
        label: Required arg
        type: string
        required: true
      - key: OPTIONAL_ARG
        label: Optional arg
        type: string
        required: false
EOF
assert_pass "arg with required explicit true/false" "$FIXTURE_DIR/explicit-required.yml"

# -- arg missing a genuinely required field: must FAIL --------------------
cat > "$FIXTURE_DIR/missing-key.yml" <<'EOF'
scripts:
  - id: test-invalid-arg
    name: Test invalid arg
    command: "true"
    args:
      - label: Missing key
        type: string
EOF
assert_fail "arg missing key" "$FIXTURE_DIR/missing-key.yml"

echo "OK $(basename "$0")"
