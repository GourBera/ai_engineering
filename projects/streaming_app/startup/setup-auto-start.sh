#!/usr/bin/env bash
set -euo pipefail

# setup-auto-start.sh
# Installation script to configure auto-start of streaming services
# This script will:
# 1. Make all scripts executable
# 2. Install LaunchAgent for auto-start on system reboot
# 3. Provide instructions for manual setup if needed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.streaming.services.plist"
PLIST_SRC="$SCRIPT_DIR/$PLIST_NAME"
PLIST_DST="$LAUNCH_AGENTS_DIR/$PLIST_NAME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Streaming Services Auto-Start Setup                    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if OrbStack is installed
if ! command -v orb > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Warning: OrbStack CLI not found${NC}"
    echo "  Please make sure OrbStack is installed and running"
fi

# Check if kubectl is available
if ! command -v kubectl > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: kubectl not found${NC}"
    echo "  Please install kubectl or ensure OrbStack Kubernetes is enabled"
    exit 1
fi

echo -e "${GREEN}Step 1: Making scripts executable...${NC}"
chmod +x "$SCRIPT_DIR/auto-start-services.sh"
chmod +x "$SCRIPT_DIR/robust-startup.sh"
chmod +x "$SCRIPT_DIR/health-monitor.sh"
echo -e "${GREEN}✓ Scripts are now executable${NC}"
echo ""

# Update the plist file with current user's home directory
echo -e "${GREEN}Step 2: Updating LaunchAgent configuration...${NC}"
CURRENT_USER=$(whoami)
CURRENT_HOME="$HOME"

# Create a temporary plist with updated paths
cat "$PLIST_SRC" | \
    sed "s|/Users/gourbera|$CURRENT_HOME|g" > "$PLIST_SRC.tmp"

mv "$PLIST_SRC.tmp" "$PLIST_SRC"
echo -e "${GREEN}✓ LaunchAgent configuration updated for user: $CURRENT_USER${NC}"
echo ""

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$LAUNCH_AGENTS_DIR"

# Check if LaunchAgent is already installed
if [ -f "$PLIST_DST" ]; then
    echo -e "${YELLOW}⚠ LaunchAgent already installed${NC}"
    read -p "Do you want to reinstall it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Unloading existing LaunchAgent...${NC}"
        launchctl unload "$PLIST_DST" 2>/dev/null || true
        rm -f "$PLIST_DST"
    else
        echo -e "${YELLOW}Skipping LaunchAgent installation${NC}"
        echo ""
        exit 0
    fi
fi

echo -e "${GREEN}Step 3: Installing LaunchAgent...${NC}"
cp "$PLIST_SRC" "$PLIST_DST"
echo -e "${GREEN}✓ LaunchAgent installed to: $PLIST_DST${NC}"
echo ""

echo -e "${GREEN}Step 4: Loading LaunchAgent...${NC}"
launchctl load "$PLIST_DST"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ LaunchAgent loaded successfully${NC}"
else
    echo -e "${RED}✗ Failed to load LaunchAgent${NC}"
    echo -e "${YELLOW}You may need to load it manually with:${NC}"
    echo -e "  launchctl load $PLIST_DST"
fi
echo ""

echo -e "${GREEN}Step 5: Creating log directory...${NC}"
mkdir -p /tmp/streaming_app
echo -e "${GREEN}✓ Log directory created: /tmp/streaming_app${NC}"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo ""
echo -e "${BLUE}What happens now:${NC}"
echo "  • Services will start automatically when you log in"
echo "  • Port-forwards will be established for Redis, Kafka, and Spark"
echo "  • Environment variables will be saved to .env file"
echo "  • Python scripts can use service_config.py to access services"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  • Start services now:    $SCRIPT_DIR/robust-startup.sh start"
echo "  • Stop services:         $SCRIPT_DIR/robust-startup.sh stop"
echo "  • Check status:          $SCRIPT_DIR/robust-startup.sh status"
echo "  • Health check:          $SCRIPT_DIR/health-monitor.sh check"
echo "  • View logs:             tail -f /tmp/streaming_app/*.log"
echo ""
echo -e "${BLUE}To uninstall:${NC}"
echo "  1. launchctl unload $PLIST_DST"
echo "  2. rm $PLIST_DST"
echo ""
echo -e "${YELLOW}Note: Make sure OrbStack is running and Kubernetes is enabled${NC}"
echo ""

# Ask if user wants to start services now
read -p "Do you want to start the services now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Starting services...${NC}"
    "$SCRIPT_DIR/robust-startup.sh" start
    echo ""
    echo -e "${GREEN}Done! Services should be accessible from Python code now.${NC}"
else
    echo -e "${YELLOW}Services not started. Run manually with:${NC}"
    echo "  $SCRIPT_DIR/robust-startup.sh start"
fi
