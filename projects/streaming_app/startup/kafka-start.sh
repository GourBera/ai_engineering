#!/usr/bin/env bash
set -euo pipefail

# kafka-start.sh (moved)
# Usage: ./kafka-start.sh [start|stop|status]

KAFKA_NS=${KAFKA_NS:-kafka}
KAFKA_SVC=${KAFKA_SVC:-my-kafka-kafka-external-bootstrap}
LOCAL_PORT=${LOCAL_PORT:-9094}
TMP_LOG=${TMP_LOG:-/tmp/kafka-start.log}
PID_FILE=${PID_FILE:-/tmp/kafka-start.pid}

cmd=${1:-start}

find_portforward() {
  pgrep -af "kubectl port-forward" | grep "svc/${KAFKA_SVC} ${LOCAL_PORT}:${LOCAL_PORT}" || true
}

start() {
  # Install and load LaunchAgent for permanent port-forward
  PLIST_SRC="$(dirname "$0")/com.streaming_app.kafka.plist"
  PLIST_DEST="$HOME/Library/LaunchAgents/com.streaming_app.kafka.plist"
  if [ -f "$PLIST_SRC" ]; then
    echo "Copying $PLIST_SRC to $PLIST_DEST"
    cp "$PLIST_SRC" "$PLIST_DEST"
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    launchctl load "$PLIST_DEST"
    echo "Loaded LaunchAgent: $PLIST_DEST"
  else
    echo "WARNING: $PLIST_SRC not found, running legacy background port-forward."
    EXISTING_PF=$(find_portforward)
    if [ -n "$EXISTING_PF" ]; then
      echo "Found existing port-forward for Kafka:"
      echo "$EXISTING_PF"
    else
      echo "Starting port-forward to localhost:${LOCAL_PORT} (log: ${TMP_LOG})"
      nohup kubectl port-forward -n "$KAFKA_NS" svc/$KAFKA_SVC ${LOCAL_PORT}:${LOCAL_PORT} > "$TMP_LOG" 2>&1 &
      PF_PID=$!
      echo $PF_PID > "$PID_FILE"
      sleep 1
      if ! ps -p "$PF_PID" > /dev/null 2>&1; then
        echo "Port-forward failed, see $TMP_LOG" >&2
        tail -n 50 "$TMP_LOG" || true
        exit 1
      fi
      echo "Port-forward started (pid $PF_PID)"
    fi
  fi

  # wait for local port
  echo "Waiting for Kafka on localhost:${LOCAL_PORT}..."
  for i in {1..20}; do
    if nc -z localhost ${LOCAL_PORT} 2>/dev/null; then
      echo "Port ${LOCAL_PORT} open"
      break
    fi
    sleep 1
  done

  echo "Running Kafka test (using poetry, bootstrap=localhost:${LOCAL_PORT})"
  KAFKA_BOOTSTRAP=localhost:${LOCAL_PORT} poetry run python ./src/kafka_example.py || {
    echo "Kafka test failed" >&2
    exit 1
  }
  echo "Kafka test succeeded"
}

stop() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    echo "Killing port-forward pid $pid"
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
  else
    echo "No pid file ($PID_FILE). Searching for any matching port-forward..."
    pids=$(pgrep -af "kubectl port-forward" | grep "svc/${KAFKA_SVC} ${LOCAL_PORT}:${LOCAL_PORT}" | awk '{print $1}' || true)
    if [ -n "$pids" ]; then
      echo "Killing: $pids"
      echo $pids | xargs -r kill
    else
      echo "No port-forward processes found"
    fi
  fi
}

status() {
  echo "Kafka namespace: $KAFKA_NS, service: $KAFKA_SVC, local port: $LOCAL_PORT"
  find_portforward || echo "no port-forward running for kafka"
}

case "$cmd" in
  start) start ;; 
  stop) stop ;; 
  status) status ;; 
  *) echo "Usage: $0 [start|stop|status]"; exit 2 ;;
esac

exit 0
