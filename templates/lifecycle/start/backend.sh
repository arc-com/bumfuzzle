#!/usr/bin/env bash
# start.sh — start all services in a stack for local development
set -euo pipefail
cd "$(dirname "$0")/.."

STACK="${1:-app}"
ENV_FILE=".env.local"
COMPOSE_FILE="docker-compose.${STACK}.yml"

[[ -f "$ENV_FILE" ]]     || { echo "Error: $ENV_FILE not found"; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Error: $COMPOSE_FILE not found (stack: $STACK)"; exit 1; }

echo "→ start  env: local  stack: $STACK"
APP_ENV=local docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d
