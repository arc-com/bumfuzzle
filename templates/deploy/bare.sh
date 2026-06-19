#!/usr/bin/env bash
# deploy.sh — placeholder deployment script (customize for your project)
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/preflight.sh
echo "deploy not configured — edit scripts/deploy.sh" >&2
exit 1
