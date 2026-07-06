#!/usr/bin/env bash
# hooks.approval_gates in bumfuzzle.yml controls exactly which require_approval
# calls get rendered into the deployed pre-commit hook, not just the default
# four -- a custom list should replace them entirely, not merge with them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

CONFIG="$(mktemp)"
cat > "$CONFIG" <<'EOF'
scaffold:
  steps:
    - id: githooks
      enabled: true

hooks:
  approval_gates:
    - label: "Notebooks"
      env_var: NOTEBOOK_APPROVED
      pattern: '(^|/)[^/]+\.ipynb$'
    - label: "Markdown"
      env_var: DOCS_APPROVED
      pattern: '(^|/)[^/]+\.md$'
EOF

WORK="$(mktemp -d)"
(cd "$WORK" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" --config "$CONFIG" > /dev/null 2>&1)

HOOK="$WORK/.githooks/pre-commit"
[[ -f "$HOOK" ]] || { echo "FAIL: pre-commit hook not deployed" >&2; exit 1; }

grep -q "require_approval Notebooks NOTEBOOK_APPROVED" "$HOOK" || { echo "FAIL: custom Notebooks gate missing" >&2; cat "$HOOK" >&2; exit 1; }
grep -q "require_approval Markdown DOCS_APPROVED" "$HOOK" || { echo "FAIL: retained Markdown gate missing" >&2; cat "$HOOK" >&2; exit 1; }
grep -q "CONFIG_APPROVED" "$HOOK" && { echo "FAIL: dropped Config/YAML gate still present" >&2; cat "$HOOK" >&2; exit 1; }
grep -q "ENV_APPROVED" "$HOOK" && { echo "FAIL: dropped dotenv gate still present" >&2; cat "$HOOK" >&2; exit 1; }
grep -q "SCRIPT_APPROVED" "$HOOK" && { echo "FAIL: dropped Scripts gate still present" >&2; cat "$HOOK" >&2; exit 1; }
grep -q "__APPROVAL_GATES__" "$HOOK" && { echo "FAIL: marker line was not substituted" >&2; cat "$HOOK" >&2; exit 1; }

# rerun with the default template against the same project -- kickstart never
# rewrites a hook it already deployed, so the custom gates must survive.
(cd "$WORK" && BUMFUZZLE_ROOT="$ROOT" "$ROOT/scripts/kickstart.sh" > /dev/null 2>&1)
grep -q "require_approval Notebooks NOTEBOOK_APPROVED" "$HOOK" || { echo "FAIL: rerun with default config overwrote the custom gate list" >&2; cat "$HOOK" >&2; exit 1; }

rm -f "$CONFIG"
echo "OK $(basename "$0")"
