#!/usr/bin/env bash
# Config-lint catches structural and non-structural problems in bumfuzzle.yml.
# Each case writes a config inline and asserts on preflight's output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$(mktemp -d)/bumfuzzle"
(cd "$ROOT" && go build -o "$BIN" ./cmd/bumfuzzle)

WORK="$(mktemp -d)"
cd "$WORK"

# expect <rc> <pattern...>: run preflight on ./bumfuzzle.yml and assert the
# exit code plus one grep pattern per remaining argument.
expect() {
  local want_rc="$1"; shift
  local rc=0 out
  out="$("$BIN" preflight 2>&1)" || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    echo "FAIL: expected exit $want_rc, got $rc for:" >&2
    cat bumfuzzle.yml >&2
    echo "--- output:" >&2; echo "$out" >&2
    exit 1
  fi
  local p
  for p in "$@"; do
    if ! grep -q "$p" <<< "$out"; then
      echo "FAIL: missing pattern '$p' in output:" >&2
      echo "$out" >&2
      exit 1
    fi
  done
}

# unparseable YAML → hard-stop
printf 'rules: [\n' > bumfuzzle.yml
expect 1 'bumfuzzle.yml is not parseable YAML' '\[hard-stop\] aborting preflight'

# duplicate id (error, rules still evaluated)
cat > bumfuzzle.yml <<'EOF'
scripts:
  - id: dup
    name: "a"
    command: "true"
  - id: dup
    name: "b"
    command: "false"
EOF
expect 1 "duplicate id 'dup' in scripts:"

# unknown script reference (structural → rules not evaluated)
cat > bumfuzzle.yml <<'EOF'
rules:
  - type: script_reusable
    name: "r1"
    script: ghost
EOF
expect 1 "rule references unknown script 'ghost'" 'rules were not evaluated'

# rules entry with neither group nor type (structural)
cat > bumfuzzle.yml <<'EOF'
rules:
  - description: "orphan"
EOF
expect 1 "rules entry at .rules\[0\] has neither 'group' nor 'type'"

# missing name (error)
cat > bumfuzzle.yml <<'EOF'
rules:
  - type: script_clean
    command: "true"
EOF
expect 1 'rule at .rules\[0\] is missing required field: name'

# required/undeclared args (errors)
cat > bumfuzzle.yml <<'EOF'
scripts:
  - id: s1
    name: "S1"
    command: "true"
    args:
      - key: NEEDED
        required: true
rules:
  - type: script_reusable
    name: "r1"
    script: s1
    args:
      EXTRA: x
EOF
expect 1 "rule 'r1' is missing required arg 'NEEDED' of script 's1'" \
         "rule 'r1' passes arg 'EXTRA' not declared by script 's1'"

# bash syntax errors (error)
cat > bumfuzzle.yml <<'EOF'
scripts:
  - id: broken
    name: "broken"
    command: "if then fi ((("
EOF
expect 1 "script 'broken' has bash syntax errors"

echo "OK $(basename "$0")"
