#!/usr/bin/env bash
# stop.sh — stop all services in a stack
set -euo pipefail
cd "$(dirname "$0")/.."

STACK="${1:-app}"
ENV_FILE=".env.local"
COMPOSE_FILE="docker-compose.${STACK}.yml"

[[ -f "$COMPOSE_FILE" ]] || { echo "Error: $COMPOSE_FILE not found (stack: $STACK)"; exit 1; }

echo "→ stop  stack: $STACK"
APP_ENV=local docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" down
