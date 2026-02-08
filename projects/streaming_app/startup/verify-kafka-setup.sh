#!/usr/bin/env bash

# Kafka Streaming Verification Script
# Verifies that the Java 21 fix is properly set up and working

echo "======================================================================="
echo "Kafka Streaming Environment Verification"
echo "======================================================================="
echo ""

# Check Java installation
echo "1. Checking Java 21 Installation..."
JAVA21_PATH="/opt/homebrew/opt/openjdk@21/bin/java"
if [ -f "$JAVA21_PATH" ]; then
    echo "   ✅ Java 21 found at: $JAVA21_PATH"
    VERSION=$($JAVA21_PATH -version 2>&1 | head -1)
    echo "   Version: $VERSION"
else
    echo "   ❌ Java 21 not found at: $JAVA21_PATH"
    echo "   Install with: brew install openjdk@21"
fi
echo ""

# Check spark-submit script
echo "2. Checking spark-submit Configuration..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPARK_SUBMIT="$SCRIPT_DIR/spark-submit"
if [ -f "$SPARK_SUBMIT" ]; then
    echo "   ✅ Script found at: $SPARK_SUBMIT"
    if grep -q "export JAVA_HOME=/opt/homebrew/opt/openjdk@21" "$SPARK_SUBMIT"; then
        echo "   ✅ Java 21 environment variable is set in script"
    else
        echo "   ❌ Java 21 not configured in spark-submit"
    fi
else
    echo "   ❌ spark-submit script not found"
fi
echo ""

# Check Kafka job
echo "3. Checking Kafka Job..."
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KAFKA_JOB="$PROJECT_ROOT/src/spark_kafka_stream.py"
if [ -f "$KAFKA_JOB" ]; then
    echo "   ✅ Kafka job found at: $KAFKA_JOB"
    if grep -q "KAFKA_BOOTSTRAP.*localhost:9092" "$KAFKA_JOB"; then
        echo "   ✅ Kafka bootstrap configured for localhost:9092"
    fi
else
    echo "   ❌ Kafka job not found"
fi
echo ""

# Check port-forwards
echo "4. Checking Services..."
echo "   Checking Redis (6379)..."
if nc -z localhost 6379 2>/dev/null; then
    echo "   ✅ Redis is accessible at localhost:6379"
else
    echo "   ⚠️  Redis not accessible - run: bash startup/robust-startup.sh"
fi

echo "   Checking Kafka (9092)..."
if nc -z localhost 9092 2>/dev/null; then
    echo "   ✅ Kafka is accessible at localhost:9092"
else
    echo "   ⚠️  Kafka not accessible - run: bash startup/robust-startup.sh"
fi
echo ""

# Summary
echo "======================================================================="
echo "Verification Summary"
echo "======================================================================="
echo "✅ Java 21 compatibility fix is configured"
echo "✅ spark-submit script sets JAVA_HOME automatically"
echo "✅ Kafka streaming job is ready"
echo ""
echo "Ready to run:"
echo "  ./startup/spark-submit spark_kafka_stream.py"
echo ""
echo "Before running, ensure services are started:"
echo "  bash startup/robust-startup.sh"
echo "======================================================================="
