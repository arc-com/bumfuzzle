#!/usr/bin/env bash
# deploy.sh — run the dev server, build, or start in production mode
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-dev}"

case "$MODE" in
  dev)
    scripts/preflight.sh
    pnpm dev
    ;;
  build)
    scripts/preflight.sh
    pnpm build
    ;;
  prod)
    scripts/preflight.sh --env prod
    pnpm start
    ;;
  *)
    echo "usage: scripts/deploy.sh [dev|build|prod]" >&2
    exit 1
    ;;
esac
