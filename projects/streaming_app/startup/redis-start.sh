#!/usr/bin/env bash
set -euo pipefail

# redis-start.sh (moved)
# Usage: ./redis-start.sh [start|stop|status]

REDIS_NS=${REDIS_NS:-redis}
REDIS_SECRET=${REDIS_SECRET:-redis}
REDIS_SVC=${REDIS_SVC:-redis-master}
LOCAL_PORT=${LOCAL_PORT:-6379}
TMP_LOG=${TMP_LOG:-/tmp/redis-start.log}
PID_FILE=${PID_FILE:-/tmp/redis-start.pid}

cmd=${1:-start}

find_portforward() {
  pgrep -af "kubectl port-forward" | grep "svc/${REDIS_SVC} ${LOCAL_PORT}:${LOCAL_PORT}" || true
}

start() {
  # Get Redis password from Kubernetes secret
  echo "Decoding Redis password from secret '${REDIS_SECRET}' in ns '${REDIS_NS}'..."
  REDIS_PASSWORD=$(kubectl get secret "$REDIS_SECRET" -n "$REDIS_NS" -o jsonpath='{.data.redis-password}' | base64 --decode)
  export REDIS_PASSWORD

  EXISTING_PF=$(find_portforward)
  if [ -n "$EXISTING_PF" ]; then
    echo "Found existing port-forward for Redis:"
    echo "$EXISTING_PF"
  else
    echo "Starting port-forward to localhost:${LOCAL_PORT} (log: ${TMP_LOG})"
    nohup kubectl port-forward -n "$REDIS_NS" svc/$REDIS_SVC ${LOCAL_PORT}:${LOCAL_PORT} > "$TMP_LOG" 2>&1 &
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

  # wait for local port
  echo "Waiting for Redis on localhost:${LOCAL_PORT}..."
  for i in {1..15}; do
    if nc -z localhost ${LOCAL_PORT} 2>/dev/null; then
      echo "Port ${LOCAL_PORT} open"
      break
    fi
    sleep 1
  done

  echo "Running Redis test (using poetry)"
  REDIS_HOST=localhost REDIS_PORT=${LOCAL_PORT} REDIS_PASSWORD=${REDIS_PASSWORD} poetry run python ./src/redis_example.py || {
    echo "Redis test failed" >&2
    exit 1
  }
  echo "Redis test succeeded"
}

stop() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    echo "Killing port-forward pid $pid"
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
  else
    echo "No pid file ($PID_FILE). Searching for any matching port-forward..."
    pids=$(pgrep -af "kubectl port-forward" | grep "svc/${REDIS_SVC} ${LOCAL_PORT}:${LOCAL_PORT}" | awk '{print $1}' || true)
    if [ -n "$pids" ]; then
      echo "Killing: $pids"
      echo $pids | xargs -r kill
    else
      echo "No port-forward processes found"
    fi
  fi
}

status() {
  echo "Redis namespace: $REDIS_NS, service: $REDIS_SVC, local port: $LOCAL_PORT"
  find_portforward || echo "no port-forward running for redis"
}

case "$cmd" in
  start) start ;; 
  stop) stop ;; 
  status) status ;; 
  *) echo "Usage: $0 [start|stop|status]"; exit 2 ;;
esac

exit 0
