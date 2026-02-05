#!/usr/bin/env bash
set -euo pipefail
# Startup helper: port-forward Kafka bootstrap service to localhost:9092
# Writes a .env file with KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
NAMESPACE="kafka"

echo "Using namespace: $NAMESPACE"

# preferred service name (Strimzi default)
SERVICE_NAME="my-kafka-kafka-bootstrap"

echo "Starting port-forward for $SERVICE_NAME in namespace $NAMESPACE -> localhost:9092"
kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" 9092:9092 >/dev/null 2>&1 &
PF_PID=$!
echo $PF_PID > "$ROOT/.kafka_pf.pid"

echo "Waiting for localhost:9092 to become available..."
for i in $(seq 1 30); do
  if nc -z 127.0.0.1 9092 >/dev/null 2>&1; then
    echo "Port 9092 is open"
    break
  fi
  sleep 1
done

if ! nc -z 127.0.0.1 9092 >/dev/null 2>&1; then
  echo "ERROR: Kafka bootstrap not reachable on localhost:9092" >&2
  echo "Killing port-forward PID $PF_PID" || true
  kill "$PF_PID" >/dev/null 2>&1 || true
  exit 1
fi

echo "KAFKA_BOOTSTRAP_SERVERS=127.0.0.1:9092" > "$ROOT/.env"
echo "Wrote $ROOT/.env"
echo "Startup complete. To stop port-forward: kill \$(cat $ROOT/.kafka_pf.pid)"
#!/usr/bin/env bash
set -euo pipefail

# startup.sh (moved)
# - obtains Redis password from Kubernetes secret
# - starts port-forwarding for Redis and Kafka
# - runs redis_example.py and kafka_example.py via Poetry
# - cleans up port-forwards

REDIS_NS=redis
REDIS_SECRET_NAME=redis
REDIS_SVC=redis-master
REDIS_LOCAL_PORT=6379
REDIS_PORT=6379

KAFKA_NS=kafka
KAFKA_SVC=my-kafka-kafka-bootstrap
KAFKA_LOCAL_PORT=9092
KAFKA_PORT=9092

TMP_DIR="/tmp/streaming_app_startup"
mkdir -p "$TMP_DIR"
REDIS_PF_LOG="$TMP_DIR/redis-pf.log"
KAFKA_PF_LOG="$TMP_DIR/kafka-pf.log"
REDIS_PF_PID="$TMP_DIR/redis_pf.pid"
KAFKA_PF_PID="$TMP_DIR/kafka_pf.pid"

echo "Decoding Redis password from secret '$REDIS_SECRET_NAME' in namespace '$REDIS_NS'..."
REDIS_PASSWORD=$(kubectl get secret "$REDIS_SECRET_NAME" -n "$REDIS_NS" -o jsonpath='{.data.redis-password}' | base64 --decode) || {
  echo "Failed to read Redis password from secret" >&2
  exit 1
}
export REDIS_PASSWORD
echo "Exported REDIS_PASSWORD (hidden)"

# Start port-forwards in background
echo "Starting port-forward for Redis service $REDIS_SVC ($REDIS_LOCAL_PORT:$REDIS_PORT)"
nohup kubectl port-forward -n "$REDIS_NS" svc/$REDIS_SVC $REDIS_LOCAL_PORT:$REDIS_PORT > "$REDIS_PF_LOG" 2>&1 &
echo $! > "$REDIS_PF_PID"

sleep 1

echo "Starting port-forward for Kafka service $KAFKA_SVC ($KAFKA_LOCAL_PORT:$KAFKA_PORT)"
nohup kubectl port-forward -n "$KAFKA_NS" svc/$KAFKA_SVC $KAFKA_LOCAL_PORT:$KAFKA_PORT > "$KAFKA_PF_LOG" 2>&1 &
echo $! > "$KAFKA_PF_PID"

# Ensure background processes are running
sleep 2
if ps -p $(cat "$REDIS_PF_PID") > /dev/null 2>&1; then
  echo "Redis port-forward started (pid $(cat $REDIS_PF_PID))"
else
  echo "Redis port-forward failed; see $REDIS_PF_LOG" >&2
  tail -n 50 "$REDIS_PF_LOG" || true
  exit 1
fi

if ps -p $(cat "$KAFKA_PF_PID") > /dev/null 2>&1; then
  echo "Kafka port-forward started (pid $(cat $KAFKA_PF_PID))"
else
  echo "Kafka port-forward failed; see $KAFKA_PF_LOG" >&2
  tail -n 50 "$KAFKA_PF_LOG" || true
  # continue, maybe Kafka not required
fi

# Ensure REDIS_PASSWORD is in environment for the test
export REDIS_HOST=localhost
export REDIS_PORT=$REDIS_LOCAL_PORT

# Run connectivity tests
echo "Running Redis test..."
poetry run python ./src/redis_example.py || {
  echo "Redis test failed (see above)" >&2
  # continue to try Kafka
}

echo "Running Kafka test..."
poetry run python ./src/kafka_example.py || {
  echo "Kafka test failed (see above)" >&2
}

# Cleanup: kill port-forward processes
echo "Cleaning up port-forward processes..."
if [ -f "$REDIS_PF_PID" ]; then
  kill $(cat "$REDIS_PF_PID") 2>/dev/null || true
  rm -f "$REDIS_PF_PID"
fi
if [ -f "$KAFKA_PF_PID" ]; then
  kill $(cat "$KAFKA_PF_PID") 2>/dev/null || true
  rm -f "$KAFKA_PF_PID"
fi

echo "Startup script finished. Logs saved in $TMP_DIR:"
echo "  $REDIS_PF_LOG"
echo "  $KAFKA_PF_LOG"

exit 0
