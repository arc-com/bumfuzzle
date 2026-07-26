#!/usr/bin/env bash
# Regression test for the file-or-folder-exists shared script defined in
# bumfuzzle-template.yml, run standalone (scripts/tests/test-file-or-folder-exists.sh)
# or before a release alongside test-release.sh. Never wired into
# rule-runner.sh or CI's `bumfuzzle run` step, and excluded from the npm/PyPI
# packages (see package.json's "files" and pyproject.toml's
# exclude-package-data) - it is a repo-dev-only check, never shipped or run
# against a customer's project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="$ROOT/bumfuzzle-template.yml"
SCRIPT_ARGS="$ROOT/scripts/prerequisites/script-args.sh"
FIXTURE_DIR="$ROOT/tmp/test-file-or-folder-exists-fixtures"

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$FIXTURE_DIR"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# same recursive lookup rule-runner.sh itself uses to resolve a script_reusable
# rule's command, so this test can never drift from how the command is
# actually invoked in production.
SCRIPT_CMD=$(yq '.scripts | .. | select(type == "!!map") | select(has("id") and .id == "file-or-folder-exists") | .command' "$TEMPLATE")
[[ -n "$SCRIPT_CMD" ]] || fail "could not extract file-or-folder-exists command from $TEMPLATE"

# runs the extracted command against FILE_PATH (newline-separated for
# multiple entries) inside a fresh fixture dir populated by SETUP_CMD first.
# a subprocess (bash -c), not eval, so the script's own exit 1 paths never
# abort this test runner.
run_check() {
  local file_path="$1" setup_cmd="$2" case_dir
  case_dir="$(mktemp -d "$FIXTURE_DIR/case-XXXXXX")"
  ( cd "$case_dir" && eval "$setup_cmd" && FILE_PATH="$file_path" bash -c "$SCRIPT_CMD" ) > /dev/null 2>&1
}

assert_pass() {
  local name="$1" file_path="$2" setup_cmd="$3"
  run_check "$file_path" "$setup_cmd" || fail "$name: expected pass, got fail"
  echo "OK $name"
}

assert_fail() {
  local name="$1" file_path="$2" setup_cmd="$3"
  run_check "$file_path" "$setup_cmd" && fail "$name: expected fail, got pass"
  echo "OK $name"
}

# -- multi-segment paths are matched exactly, never confused with a
#    same-named file living at a different path ---------------------------
assert_fail "multi-segment path does not match a same-named file elsewhere" \
  "a/b/c/README.md" "mkdir -p e && touch e/README.md"
assert_pass "multi-segment path matches when present at that exact path" \
  "a/b/c/README.md" "mkdir -p a/b/c && touch a/b/c/README.md"

# -- a bare filename (no slash at all) is root-anchored: it only matches at
#    the project root, never by basename search elsewhere in the tree -------
assert_fail "bare filename does not match a same-named file nested elsewhere" \
  "README.md" "mkdir -p anyfolder && touch anyfolder/README.md"
assert_pass "bare filename matches when present at the root" \
  "README.md" "touch README.md"

# -- file vs folder discrimination -----------------------------------------
assert_fail "bare file required does not match a same-named folder" \
  "hello" "mkdir -p hello"
assert_pass "bare file required matches a same-named file" \
  "hello" "touch hello"
assert_fail "trailing-slash folder required does not match a same-named file" \
  "hello/" "touch hello"
assert_pass "trailing-slash folder required matches a same-named folder" \
  "hello/" "mkdir -p hello"

# -- case-insensitive matching, deterministic on every OS, not dependent on
#    the host filesystem's own case sensitivity -----------------------------
assert_pass "folder match is case-insensitive" \
  "hello/" "mkdir -p HELLO"
assert_pass "bare file match is case-insensitive" \
  "hello" "touch HELLO"

# -- similar-but-different basenames never accidentally satisfy the check --
assert_fail "similar basename does not satisfy the check" \
  "hello" "touch hello2"

# -- multiple FILE_PATH entries in one call ---------------------------------
assert_pass "multiple entries all present passes" \
  "$(printf 'a\nb/\nc/d.txt')" "touch a && mkdir -p b c && touch c/d.txt"
assert_fail "multiple entries with one missing fails" \
  "$(printf 'a\nb/\nc/d.txt')" "touch a && mkdir -p b"

# -- no glob syntax is accepted; this is an exact-location existence check,
#    never a search ----------------------------------------------------------
assert_fail "glob wildcard is rejected as an invalid character, never searched" \
  "**/README.md" "mkdir -p deep/nested && touch deep/nested/README.md"

# -- FILE_PATH's required: true is enforced on script_reusable rules,
#    omitting it is a schema-lint error; providing it is not -----------------
cat > "$FIXTURE_DIR/required-arg-missing.yml" <<'EOF'
schema_version: 1
scripts:
  - id: file-or-folder-exists
    name: "File or folder exists"
    command: "true"
    args:
      - key: FILE_PATH
        label: File or folder path
        required: true
        type: path
rules:
  - type: script_reusable
    name: "Test rule missing FILE_PATH"
    script: file-or-folder-exists
    args: {}
EOF
"$SCRIPT_ARGS" "$FIXTURE_DIR/required-arg-missing.yml" > /dev/null 2>&1 \
  && fail "required arg: omitting FILE_PATH (required: true) should be flagged, was not"
echo "OK required arg: omitting FILE_PATH (required: true) is flagged"

cat > "$FIXTURE_DIR/required-arg-present.yml" <<'EOF'
schema_version: 1
scripts:
  - id: file-or-folder-exists
    name: "File or folder exists"
    command: "true"
    args:
      - key: FILE_PATH
        label: File or folder path
        required: true
        type: path
rules:
  - type: script_reusable
    name: "Test rule with FILE_PATH"
    script: file-or-folder-exists
    args:
      FILE_PATH: README.md
EOF
"$SCRIPT_ARGS" "$FIXTURE_DIR/required-arg-present.yml" > /dev/null 2>&1 \
  || fail "required arg: providing FILE_PATH should not be flagged, was"
echo "OK required arg: providing FILE_PATH is not flagged"

echo "OK $(basename "$0")"
