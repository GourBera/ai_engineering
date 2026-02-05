#!/usr/bin/env bash
set -euo pipefail
# Foreground port-forward for Kafka bootstrap (suitable for launchd)

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
ENV_FILE="$ROOT/.env"

echo "Ensuring $ENV_FILE contains KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092"
mkdir -p "$ROOT"
echo "KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092" > "$ENV_FILE"

echo "Checking if localhost:9092 is already open..."
if nc -z 127.0.0.1 9092 >/dev/null 2>&1; then
  echo "127.0.0.1:9092 already open — exiting (port-forward likely running)"
  exit 0
fi

echo "Starting kubectl port-forward to svc/my-kafka-kafka-bootstrap -> localhost:9092"
# exec so the launched process is the port-forward process (launchd will supervise it)
exec kubectl port-forward -n kafka svc/my-kafka-kafka-bootstrap 9092:9092
