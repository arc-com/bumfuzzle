#!/usr/bin/env bash
# Regression test for the folder-exists shared script defined in
# bumfuzzle-template.yml, run standalone (scripts/tests/test-folder-exists.sh)
# or before a release alongside test-release.sh. Never wired into
# rule-runner.sh or CI's `bumfuzzle run` step, and excluded from the npm/PyPI
# packages (see package.json's "files" and pyproject.toml's
# exclude-package-data) - it is a repo-dev-only check, never shipped or run
# against a customer's project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="$ROOT/bumfuzzle-template.yml"
SCRIPT_ARGS="$ROOT/scripts/prerequisites/script-args.sh"
FIXTURE_DIR="$ROOT/tmp/test-folder-exists-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# same recursive lookup rule-runner.sh itself uses to resolve a script_reusable
# rule's command, so this test can never drift from how the command is
# actually invoked in production.
SCRIPT_CMD=$(yq '.scripts | .. | select(type == "!!map") | select(has("id") and .id == "folder-exists") | .command' "$TEMPLATE")
[[ -n "$SCRIPT_CMD" ]] || fail "could not extract folder-exists command from $TEMPLATE"

# runs the extracted command against FOLDER_PATH (newline-separated for
# multiple entries) inside a fresh fixture dir populated by SETUP_CMD first.
# a subprocess (bash -c), not eval, so the script's own exit 1 paths never
# abort this test runner.
run_check() {
  local folder_path="$1" setup_cmd="$2" case_dir
  case_dir="$(mktemp -d "$FIXTURE_DIR/case-XXXXXX")"
  ( cd "$case_dir" && eval "$setup_cmd" && FOLDER_PATH="$folder_path" bash -c "$SCRIPT_CMD" ) > /dev/null 2>&1
}

assert_pass() {
  local name="$1" folder_path="$2" setup_cmd="$3"
  run_check "$folder_path" "$setup_cmd" || fail "$name: expected pass, got fail"
  echo "OK $name"
}

assert_fail() {
  local name="$1" folder_path="$2" setup_cmd="$3"
  run_check "$folder_path" "$setup_cmd" && fail "$name: expected fail, got pass"
  echo "OK $name"
}

# -- file vs folder discrimination -------------------------------------------
assert_fail "required folder does not match a same-named file" \
  "hello/" "touch hello"
assert_pass "required folder matches a same-named folder" \
  "hello/" "mkdir -p hello"

# -- case-insensitive matching, deterministic on every OS, not dependent on
#    the host filesystem's own case sensitivity -----------------------------
assert_pass "folder match is case-insensitive" \
  "hello/" "mkdir -p HELLO"

# -- multiple entries in one call --------------------------------------------
assert_pass "multiple entries all present passes" \
  "$(printf 'b/\nc/')" "mkdir -p b c"
assert_fail "multiple entries with one missing fails" \
  "$(printf 'b/\nc/')" "mkdir -p b"

# -- FOLDER_PATH's required: true is enforced on script_reusable rules,
#    omitting it is a schema-lint error; providing it is not -----------------
cat > "$FIXTURE_DIR/required-arg-missing.yml" <<'EOF'
schema_version: 2
scripts:
  - id: folder-exists
    name: "Folder(s) exists"
    command: "true"
    args:
      - key: FOLDER_PATH
        label: Folder path(s)
        required: true
        type: path-folder
rules:
  - type: script_reusable
    name: "Test rule missing FOLDER_PATH"
    script: folder-exists
    args: {}
EOF
"$SCRIPT_ARGS" "$FIXTURE_DIR/required-arg-missing.yml" > /dev/null 2>&1 \
  && fail "required arg: omitting FOLDER_PATH (required: true) should be flagged, was not"
echo "OK required arg: omitting FOLDER_PATH (required: true) is flagged"

cat > "$FIXTURE_DIR/required-arg-present.yml" <<'EOF'
schema_version: 2
scripts:
  - id: folder-exists
    name: "Folder(s) exists"
    command: "true"
    args:
      - key: FOLDER_PATH
        label: Folder path(s)
        required: true
        type: path-folder
rules:
  - type: script_reusable
    name: "Test rule with FOLDER_PATH"
    script: folder-exists
    args:
      FOLDER_PATH: ./scripts/
EOF
"$SCRIPT_ARGS" "$FIXTURE_DIR/required-arg-present.yml" > /dev/null 2>&1 \
  || fail "required arg: providing FOLDER_PATH should not be flagged, was"
echo "OK required arg: providing FOLDER_PATH is not flagged"

echo "OK $(basename "$0")"
