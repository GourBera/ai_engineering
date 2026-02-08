#!/usr/bin/env bash
# auto-start-services.sh
# Auto-start script for streaming services (can be added to login items)
# Usage: ./auto-start-services.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/streaming_app/auto-start.log"

echo "$(date): Starting streaming services auto-start..." >> "$LOG_FILE"

# Start the robust startup script
"$SCRIPT_DIR/robust-startup.sh" start >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "$(date): Services started successfully" >> "$LOG_FILE"
    # Optional: Send notification
    if command -v osascript > /dev/null 2>&1; then
        osascript -e 'display notification "Streaming services (Redis, Kafka) are ready!" with title "Services Started"'
    fi
else
    echo "$(date): Failed to start services" >> "$LOG_FILE"
    if command -v osascript > /dev/null 2>&1; then
        osascript -e 'display notification "Failed to start streaming services" with title "Error" subtitle "Check logs for details"'
    fi
fi
