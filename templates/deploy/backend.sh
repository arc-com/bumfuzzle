#!/usr/bin/env bash
# deploy.sh — build and deploy a stack to the target environment
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v yq &>/dev/null; then
  echo "Error: yq is not installed"
  exit 1
fi

case "$#" in
  1) STACK="$1"; ENV="" ;;
  2) ENV="$1"; STACK="$2" ;;
  *)
    echo "Usage: scripts/deploy.sh [env] <stack>"
    echo "  env:   local | test | prod"
    echo "  stack: <stack-name>"
    exit 1
    ;;
esac

if [[ -z "$ENV" && -n "${APP_ENV:-}" ]]; then
  ENV="$APP_ENV"
elif [[ -z "$ENV" && -f ".app-env" ]]; then
  ENV="$(tr -d '[:space:]' < .app-env)"
fi

[[ -z "$ENV" ]] && { echo "Error: environment not specified (pass as arg, set APP_ENV, or create .app-env)"; exit 1; }

ENV_FILE=".env.$ENV"
COMPOSE_FILE="docker-compose.$STACK.yml"

[[ -f "$ENV_FILE" ]]     || { echo "Error: $ENV_FILE not found"; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Error: $COMPOSE_FILE not found"; exit 1; }

export APP_ENV="$ENV"

"$(dirname "$0")/preflight.sh" --env "$ENV" --stack "$STACK" || {
  echo "Error: validation failed — deploy aborted"
  exit 1
}

echo "→ env: $ENV  |  stack: $STACK"
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up --build -d
