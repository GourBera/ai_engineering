#!/usr/bin/env bash
set -euo pipefail

# health-monitor.sh
# Monitors service health and automatically restarts port-forwards if they fail
# Can be run as a background daemon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-/tmp/streaming_app}"
mkdir -p "$LOG_DIR"

HEALTH_LOG="$LOG_DIR/health-monitor.log"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"  # Check every 60 seconds by default

# Service configuration
REDIS_PORT="6379"
KAFKA_PORT="9092"
SPARK_UI_PORT="8080"
SPARK_MASTER_PORT="7077"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$HEALTH_LOG"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$HEALTH_LOG"
}

check_port() {
    local port=$1
    nc -z localhost "$port" 2>/dev/null
}

check_redis() {
    if ! check_port "$REDIS_PORT"; then
        error "Redis port $REDIS_PORT is not accessible"
        return 1
    fi
    
    # Try to ping Redis if redis-cli is available
    if command -v redis-cli > /dev/null 2>&1; then
        local password=$(grep "^REDIS_PASSWORD=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
        if [ -n "$password" ]; then
            if ! redis-cli -h localhost -p "$REDIS_PORT" -a "$password" PING 2>/dev/null | grep -q "PONG"; then
                error "Redis is not responding to PING"
                return 1
            fi
        else
            if ! redis-cli -h localhost -p "$REDIS_PORT" PING 2>/dev/null | grep -q "PONG"; then
                error "Redis is not responding to PING"
                return 1
            fi
        fi
    fi
    
    return 0
}

check_kafka() {
    if ! check_port "$KAFKA_PORT"; then
        error "Kafka port $KAFKA_PORT is not accessible"
        return 1
    fi
    return 0
}

check_spark() {
    # Spark is optional, so we don't fail if it's not running
    if ! check_port "$SPARK_UI_PORT"; then
        log "Spark UI port $SPARK_UI_PORT is not accessible (optional)"
        return 1
    fi
    return 0
}

restart_service() {
    local service=$1
    log "Attempting to restart $service..."
    
    # Use the robust-startup script to restart
    "$SCRIPT_DIR/robust-startup.sh" restart >> "$HEALTH_LOG" 2>&1
    
    if [ $? -eq 0 ]; then
        log "✓ Service restart successful"
        # Send notification if osascript is available
        if command -v osascript > /dev/null 2>&1; then
            osascript -e "display notification \"$service was restarted due to health check failure\" with title \"Service Recovery\"" 2>/dev/null || true
        fi
        return 0
    else
        error "Failed to restart services"
        if command -v osascript > /dev/null 2>&1; then
            osascript -e "display notification \"Failed to restart $service\" with title \"Service Recovery Failed\"" 2>/dev/null || true
        fi
        return 1
    fi
}

health_check() {
    local redis_ok=true
    local kafka_ok=true
    local any_failed=false
    
    # Check Redis
    if ! check_redis; then
        redis_ok=false
        any_failed=true
        log "✗ Redis health check failed"
    else
        log "✓ Redis is healthy"
    fi
    
    # Check Kafka
    if ! check_kafka; then
        kafka_ok=false
        any_failed=true
        log "✗ Kafka health check failed"
    else
        log "✓ Kafka is healthy"
    fi
    
    # Check Spark (optional)
    if check_spark; then
        log "✓ Spark is healthy"
    fi
    
    # If any critical service failed, attempt restart
    if [ "$any_failed" = true ]; then
        error "Health check failed, attempting service recovery..."
        restart_service "streaming services"
    fi
}

monitor_loop() {
    log "Starting health monitor (check interval: ${CHECK_INTERVAL}s)"
    log "Press Ctrl+C to stop"
    
    while true; do
        health_check
        sleep "$CHECK_INTERVAL"
    done
}

# Handle command line arguments
case "${1:-monitor}" in
    monitor)
        monitor_loop
        ;;
    check)
        health_check
        ;;
    *)
        echo "Usage: $0 [monitor|check]"
        echo ""
        echo "Commands:"
        echo "  monitor - Run continuous health monitoring (default)"
        echo "  check   - Perform a single health check"
        exit 1
        ;;
esac
