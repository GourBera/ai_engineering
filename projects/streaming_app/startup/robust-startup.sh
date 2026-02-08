#!/usr/bin/env bash
set -euo pipefail

# robust-startup.sh
# Comprehensive startup script for Kubernetes services (Redis, Kafka, Spark)
# Handles reboots, service recovery, and port-forwarding automatically
# Usage: ./robust-startup.sh [start|stop|restart|status|check]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-/tmp/streaming_app}"
mkdir -p "$LOG_DIR"

# Configuration
REDIS_NS="redis"
KAFKA_NS="kafka"
SPARK_NS="spark"
REDIS_SVC="redis-master"
KAFKA_SVC="my-kafka-kafka-bootstrap"
SPARK_SVC="spark-master"

# Ports
REDIS_PORT="6379"
KAFKA_PORT="9092"
SPARK_UI_PORT="8080"
SPARK_MASTER_PORT="7077"

# Logging
LOG_FILE="$LOG_DIR/robust-startup.log"
ERROR_LOG="$LOG_DIR/robust-startup.errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

# Check if OrbStack is running
check_orbstack() {
    log "Checking OrbStack status..."
    
    if ! pgrep -f "OrbStack" > /dev/null; then
        error "OrbStack is not running. Please start OrbStack first."
        return 1
    fi
    
    # Check if Kubernetes is enabled in OrbStack
    if ! kubectl cluster-info > /dev/null 2>&1; then
        warn "Kubernetes cluster not responding. Attempting to restart..."
        # Try to restart OrbStack Kubernetes
        if command -v orb > /dev/null 2>&1; then
            orb kubernetes restart || {
                error "Failed to restart OrbStack Kubernetes. Please restart OrbStack manually."
                return 1
            }
            sleep 10
        else
            error "OrbStack CLI not found. Please restart OrbStack manually."
            return 1
        fi
    fi
    
    log "✓ OrbStack and Kubernetes are running"
    return 0
}

# Wait for Kubernetes cluster to be ready
wait_for_kubernetes() {
    log "Waiting for Kubernetes cluster to be ready..."
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if kubectl get nodes > /dev/null 2>&1 && kubectl get pods --all-namespaces > /dev/null 2>&1; then
            log "✓ Kubernetes cluster is ready"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts: Waiting for Kubernetes..."
        sleep 5
        ((attempt++))
    done
    
    error "Kubernetes cluster did not become ready within ${max_attempts} attempts"
    return 1
}

# Check and create namespaces if needed
ensure_namespaces() {
    log "Ensuring required namespaces exist..."
    
    for ns in "$REDIS_NS" "$KAFKA_NS" "$SPARK_NS"; do
        if ! kubectl get namespace "$ns" > /dev/null 2>&1; then
            warn "Namespace $ns does not exist. Creating it..."
            kubectl create namespace "$ns" || {
                error "Failed to create namespace $ns"
                return 1
            }
        fi
    done
    
    log "✓ All required namespaces exist"
}

# Check if services are deployed and ready
check_service_deployment() {
    local ns=$1
    local svc=$2
    local deployment=$3
    
    log "Checking service $svc in namespace $ns..."
    
    # Check if deployment/statefulset exists
    if ! kubectl get "$deployment" -n "$ns" > /dev/null 2>&1; then
        warn "Deployment $deployment not found in namespace $ns"
        return 1
    fi
    
    # Check if pods are ready
    local ready_pods
    ready_pods=$(kubectl get "$deployment" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$ready_pods" = "0" ] || [ -z "$ready_pods" ]; then
        # Try to get ready pods from statefulset
        ready_pods=$(kubectl get "$deployment" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$ready_pods" = "0" ] || [ -z "$ready_pods" ]; then
            warn "No ready pods for $deployment in namespace $ns"
            return 1
        fi
    fi
    
    # Check if service exists
    if ! kubectl get service "$svc" -n "$ns" > /dev/null 2>&1; then
        warn "Service $svc not found in namespace $ns"
        return 1
    fi
    
    log "✓ Service $svc is ready in namespace $ns"
    return 0
}

# Deploy services if they don't exist
deploy_services() {
    log "Checking and deploying required services..."
    
    # Check Redis (it's a StatefulSet)
    if ! check_service_deployment "$REDIS_NS" "$REDIS_SVC" "statefulset/redis-master"; then
        warn "Redis service needs deployment. Please ensure Redis is properly deployed."
        info "You can deploy Redis using Helm: helm repo add bitnami https://charts.bitnami.com/bitnami && helm install redis bitnami/redis --namespace $REDIS_NS"
    fi
    
    # Check Kafka (Strimzi deployment - check for the pod directly)
    if ! kubectl get pods -n "$KAFKA_NS" -l strimzi.io/kind=Kafka > /dev/null 2>&1; then
        warn "Kafka service needs deployment. Please ensure Kafka is properly deployed."
        info "You can deploy Kafka using Strimzi: kubectl create -f https://strimzi.io/install/latest?namespace=$KAFKA_NS -n $KAFKA_NS"
    else
        # Check if the external bootstrap service exists
        if ! kubectl get service "$KAFKA_SVC" -n "$KAFKA_NS" > /dev/null 2>&1; then
            warn "Kafka external bootstrap service $KAFKA_SVC not found"
        else
            log "✓ Kafka service is ready in namespace $KAFKA_NS"
        fi
    fi
    
    # Check Spark Master
    if ! kubectl get pods -n "$SPARK_NS" -l app=spark-master > /dev/null 2>&1; then
        log "Deploying Spark Master..."
        deploy_spark_master || warn "Spark Master deployment failed"
    else
        log "✓ Spark Master is already deployed in namespace $SPARK_NS"
    fi
}

# Deploy Spark Master if it doesn't exist
deploy_spark_master() {
    local spark_yaml
    spark_yaml=$(cat << 'SPARKEOF'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-master
  namespace: spark
  labels:
    app: spark-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: spark-master
  template:
    metadata:
      labels:
        app: spark-master
    spec:
      containers:
      - name: spark-master
        image: docker.io/apache/spark:4.0.0
        command:
        - /opt/spark/bin/spark-class
        - org.apache.spark.deploy.master.Master
        - --host
        - "0.0.0.0"
        - --port
        - "7077"
        - --webui-port
        - "8080"
        ports:
        - containerPort: 7077
          name: master
        - containerPort: 8080
          name: webui
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1
            memory: 2Gi
        env:
        - name: SPARK_NO_DAEMONIZE
          value: "false"
---
apiVersion: v1
kind: Service
metadata:
  name: spark-master-svc
  namespace: spark
  labels:
    app: spark-master
spec:
  selector:
    app: spark-master
  ports:
  - port: 7077
    name: master
    targetPort: 7077
  - port: 8080
    name: webui
    targetPort: 8080
  type: ClusterIP
SPARKEOF
)
    
    if echo "$spark_yaml" | kubectl apply -f - 2>/dev/null; then
        log "✓ Spark Master deployment created"
        
        # Wait for pod to be ready
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            local ready_pods
            ready_pods=$(kubectl get deployment spark-master -n "$SPARK_NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            
            if [ "$ready_pods" = "1" ]; then
                log "✓ Spark Master pod is ready"
                return 0
            fi
            
            info "Attempt $attempt/$max_attempts: Waiting for Spark Master pod to be ready..."
            sleep 2
            ((attempt++))
        done
        
        warn "Spark Master pod did not become ready within ${max_attempts} attempts"
        return 1
    else
        error "Failed to deploy Spark Master"
        return 1
    fi
}

# Kill existing port-forwards for a service
kill_existing_portforward() {
    local svc=$1
    local port=$2
    
    local pids
    pids=$(pgrep -af "kubectl port-forward" | grep "svc/${svc} ${port}:${port}" | awk '{print $1}' || true)
    
    if [ -n "$pids" ]; then
        log "Killing existing port-forwards for $svc:$port (PIDs: $pids)"
        echo "$pids" | xargs -r kill -9 2>/dev/null || true
        sleep 2
    fi
}

# Start port-forward for a service
start_portforward() {
    local ns=$1
    local svc=$2
    local port=$3
    local log_file=$4
    
    log "Starting port-forward for $svc:$port -> localhost:$port"
    
    # Check if port is already in use by something else
    if nc -z localhost "$port" 2>/dev/null; then
        # Check if it's our port-forward (use ps for full command)
        local existing_pf
        existing_pf=$(ps -ef | grep "kubectl port-forward" | grep -v grep | grep -E "(svc/${svc}|${svc})" | grep "${port}:${port}" | grep "$ns" || true)
        if [ -n "$existing_pf" ]; then
            log "✓ Found existing port-forward for $ns/$svc on port $port: $existing_pf"
            return 0
        else
            warn "Port $port is already in use by another process. Checking what it is..."
            lsof -i ":$port" || true
            return 1
        fi
    fi
    
    # Kill any existing port-forwards for this service
    kill_existing_portforward "$svc" "$port"
    
    # Start new port-forward
    nohup kubectl port-forward -n "$ns" "svc/$svc" "${port}:${port}" > "$log_file" 2>&1 &
    local pf_pid=$!
    
    # Wait a moment and check if it's still running
    sleep 3
    if ! ps -p "$pf_pid" > /dev/null 2>&1; then
        error "Port-forward for $svc:$port failed to start"
        if [ -f "$log_file" ]; then
            error "Port-forward log: $(tail -n 10 "$log_file")"
        fi
        return 1
    fi
    
    log "✓ Port-forward for $svc:$port started (PID: $pf_pid)"
    
    # Wait for port to be ready
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z localhost "$port" 2>/dev/null; then
            log "✓ Port $port is ready and accessible"
            return 0
        fi
        
        info "Attempt $attempt/$max_attempts: Waiting for port $port to be ready..."
        sleep 1
        ((attempt++))
    done
    
    error "Port $port did not become ready within ${max_attempts} attempts"
    return 1
}

# Set environment variables
set_environment() {
    log "Setting environment variables..."
    
    # Get Redis password with better error handling
    REDIS_PASSWORD=""
    if kubectl get secret redis -n "$REDIS_NS" > /dev/null 2>&1; then
        # Try to get password from the standard redis secret
        REDIS_PASSWORD=$(kubectl get secret redis -n "$REDIS_NS" -o jsonpath='{.data.redis-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        # If that fails, try getting it from redis-password field in data
        if [ -z "$REDIS_PASSWORD" ]; then
            REDIS_PASSWORD=$(kubectl get secret redis -n "$REDIS_NS" -o json 2>/dev/null | grep -o '"redis-password":"[^"]*"' | cut -d'"' -f4 | base64 -d 2>/dev/null || echo "")
        fi
        
        if [ -n "$REDIS_PASSWORD" ]; then
            log "✓ Retrieved Redis password from Kubernetes secret"
        else
            warn "Could not decode Redis password from secret, checking if Redis requires password..."
            # Test if Redis is accessible without password
            if nc -z localhost "$REDIS_PORT" 2>/dev/null; then
                # Try connecting without password
                if command -v redis-cli > /dev/null 2>&1; then
                    if redis-cli -h localhost -p "$REDIS_PORT" PING 2>/dev/null | grep -q "PONG"; then
                        warn "Redis is accessible without password (no auth required)"
                        REDIS_PASSWORD=""
                    fi
                fi
            fi
        fi
    else
        warn "Redis secret not found in namespace $REDIS_NS, will attempt connection without password"
    fi
    
    export REDIS_PASSWORD
    export REDIS_HOST="localhost"
    export REDIS_PORT="$REDIS_PORT"
    log "✓ Redis environment variables set"
    
    # Set Kafka environment
    export KAFKA_BOOTSTRAP_SERVERS="localhost:$KAFKA_PORT"
    export KAFKA_BOOTSTRAP="localhost:$KAFKA_PORT"
    log "✓ Kafka environment variables set"
    
    # Set Spark environment
    export SPARK_MASTER_URL="spark://localhost:$SPARK_MASTER_PORT"
    export SPARK_UI_URL="http://localhost:$SPARK_UI_PORT"
    log "✓ Spark environment variables set"
    
    # Create environment file for Python scripts
    cat > "$PROJECT_ROOT/.env" << EOF
# Auto-generated environment variables - $(date)
# This file is sourced by Python scripts to access streaming services

REDIS_HOST=localhost
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD

KAFKA_BOOTSTRAP_SERVERS=localhost:$KAFKA_PORT
KAFKA_BOOTSTRAP=localhost:$KAFKA_PORT

SPARK_MASTER_URL=spark://localhost:$SPARK_MASTER_PORT
SPARK_UI_URL=http://localhost:$SPARK_UI_PORT
EOF
    
    chmod 600 "$PROJECT_ROOT/.env"  # Protect password file
    log "✓ Environment file created at $PROJECT_ROOT/.env"
    
    # Also create a Python-friendly config file
    cat > "$PROJECT_ROOT/src/service_config.py" << 'EOF'
"""
Auto-generated service configuration
Load this module to access service connection details
"""
import os
from pathlib import Path

# Load from .env file if it exists
_env_file = Path(__file__).parent.parent / '.env'
if _env_file.exists():
    with open(_env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                os.environ.setdefault(key.strip(), value.strip())

# Redis configuration
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
REDIS_PASSWORD = os.environ.get('REDIS_PASSWORD', None) or None  # Convert empty string to None

# Kafka configuration
KAFKA_BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9092')
KAFKA_BOOTSTRAP = os.environ.get('KAFKA_BOOTSTRAP', 'localhost:9092')

# Spark configuration
SPARK_MASTER_URL = os.environ.get('SPARK_MASTER_URL', 'spark://localhost:7077')
SPARK_UI_URL = os.environ.get('SPARK_UI_URL', 'http://localhost:8080')

def get_redis_connection_params():
    """Get Redis connection parameters as a dict"""
    params = {
        'host': REDIS_HOST,
        'port': REDIS_PORT,
        'db': 0,
        'decode_responses': True
    }
    if REDIS_PASSWORD:
        params['password'] = REDIS_PASSWORD
    return params

def get_kafka_config():
    """Get Kafka configuration as a dict"""
    return {
        'bootstrap_servers': KAFKA_BOOTSTRAP_SERVERS.split(',')
    }

if __name__ == '__main__':
    print("Service Configuration:")
    print(f"  Redis: {REDIS_HOST}:{REDIS_PORT} (password: {'set' if REDIS_PASSWORD else 'none'})")
    print(f"  Kafka: {KAFKA_BOOTSTRAP_SERVERS}")
    print(f"  Spark: {SPARK_MASTER_URL}")
EOF
    
    log "✓ Python config module created at $PROJECT_ROOT/src/service_config.py"
}

# Start all services
start_services() {
    log "Starting all services..."
    
    # Check OrbStack and Kubernetes
    check_orbstack || exit 1
    wait_for_kubernetes || exit 1
    
    # Ensure namespaces exist
    ensure_namespaces
    
    # Check and deploy services
    deploy_services
    
    # Start port-forwards
    start_portforward "$REDIS_NS" "$REDIS_SVC" "$REDIS_PORT" "$LOG_DIR/redis-portforward.log"
    start_portforward "$KAFKA_NS" "$KAFKA_SVC" "$KAFKA_PORT" "$LOG_DIR/kafka-portforward.log"
    
    # Start Spark port-forwards (should exist after deploy_services)
    start_portforward "$SPARK_NS" "spark-master-svc" "$SPARK_UI_PORT" "$LOG_DIR/spark-ui-portforward.log" || warn "Spark UI port-forward failed"
    start_portforward "$SPARK_NS" "spark-master-svc" "$SPARK_MASTER_PORT" "$LOG_DIR/spark-master-portforward.log" || warn "Spark Master port-forward failed"
    
    # Set environment variables
    set_environment
    
    log "✓ All services started successfully!"
    echo ""
    echo "=== Service Access Information ==="
    echo "Redis: localhost:$REDIS_PORT (password: \${REDIS_PASSWORD})"
    echo "Kafka: localhost:$KAFKA_PORT"
    echo "Spark UI: http://localhost:$SPARK_UI_PORT"
    echo "Spark Master: spark://localhost:$SPARK_MASTER_PORT"
    echo ""
    echo "Environment file: $PROJECT_ROOT/.env"
    echo "Logs directory: $LOG_DIR"
    echo ""
}

# Stop all services
stop_services() {
    log "Stopping all services..."
    
    kill_existing_portforward "$REDIS_SVC" "$REDIS_PORT"
    kill_existing_portforward "$KAFKA_SVC" "$KAFKA_PORT"
    kill_existing_portforward "spark-master-svc" "$SPARK_UI_PORT"
    kill_existing_portforward "spark-master-svc" "$SPARK_MASTER_PORT"
    
    log "✓ All services stopped"
}

# Check service status
check_status() {
    log "Checking service status..."
    
    echo ""
    echo "=== Kubernetes Cluster Status ==="
    if kubectl cluster-info > /dev/null 2>&1; then
        echo "✓ Kubernetes cluster is running"
    else
        echo "✗ Kubernetes cluster is not accessible"
    fi
    
    echo ""
    echo "=== Port-forward Status ==="
    
    # Check Redis
    if ps -ef | grep "kubectl port-forward" | grep -v grep | grep "svc/${REDIS_SVC} ${REDIS_PORT}:${REDIS_PORT}" > /dev/null; then
        echo "✓ Redis port-forward is running (localhost:$REDIS_PORT)"
    else
        echo "✗ Redis port-forward is not running"
    fi
    
    # Check Kafka
    if ps -ef | grep "kubectl port-forward" | grep -v grep | grep "svc/${KAFKA_SVC} ${KAFKA_PORT}:${KAFKA_PORT}" > /dev/null; then
        echo "✓ Kafka port-forward is running (localhost:$KAFKA_PORT)"
    else
        echo "✗ Kafka port-forward is not running"
    fi
    
    # Check Spark
    if ps -ef | grep "kubectl port-forward" | grep -v grep | grep "spark-master-svc.*$SPARK_UI_PORT" > /dev/null; then
        echo "✓ Spark UI port-forward is running (localhost:$SPARK_UI_PORT)"
    else
        echo "✗ Spark UI port-forward is not running"
    fi
    
    echo ""
    echo "=== Service Connectivity ==="
    
    # Test Redis
    if nc -z localhost "$REDIS_PORT" 2>/dev/null; then
        echo "✓ Redis is accessible on port $REDIS_PORT"
    else
        echo "✗ Redis is not accessible on port $REDIS_PORT"
    fi
    
    # Test Kafka
    if nc -z localhost "$KAFKA_PORT" 2>/dev/null; then
        echo "✓ Kafka is accessible on port $KAFKA_PORT"
    else
        echo "✗ Kafka is not accessible on port $KAFKA_PORT"
    fi
    
    # Test Spark UI
    if nc -z localhost "$SPARK_UI_PORT" 2>/dev/null; then
        echo "✓ Spark UI is accessible on port $SPARK_UI_PORT"
    else
        echo "✗ Spark UI is not accessible on port $SPARK_UI_PORT"
    fi
}

# Main command handling
cmd=${1:-start}

case "$cmd" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        stop_services
        sleep 3
        start_services
        ;;
    status)
        check_status
        ;;
    check)
        check_orbstack
        wait_for_kubernetes
        check_status
        ;;
    *)
        echo "Usage: $0 [start|stop|restart|status|check]"
        echo ""
        echo "Commands:"
        echo "  start   - Start all services (Redis, Kafka, Spark)"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  status  - Check service status"
        echo "  check   - Quick health check of cluster and services"
        exit 2
        ;;
esac

exit 0
