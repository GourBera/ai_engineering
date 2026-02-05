#!/usr/bin/env bash
# Simple wrapper to run Redis with auto port-forward
set -euo pipefail

# Check if port-forward is running
if ! nc -z localhost 6379 2>/dev/null; then
  echo "Starting Redis port-forward..."
  cd "$(dirname "$0")"
  ./startup/redis-start.sh start
else
  echo "Redis already running on localhost:6379"
fi

# Get password and run the command
REDIS_PASSWORD=$(kubectl get secret redis -n redis -o jsonpath='{.data.redis-password}' | base64 --decode)
cd "$(dirname "$0")"

# Run the provided command or default to redis_example.py
if [ $# -eq 0 ]; then
  REDIS_HOST=localhost REDIS_PORT=6379 REDIS_PASSWORD="$REDIS_PASSWORD" poetry run python ./src/redis_example.py
else
  REDIS_HOST=localhost REDIS_PORT=6379 REDIS_PASSWORD="$REDIS_PASSWORD" "$@"
fi
