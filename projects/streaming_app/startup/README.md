# Streaming Services Auto-Start System

This directory contains scripts to automatically start and manage streaming services (Redis, Kafka, Spark) on macOS with OrbStack Kubernetes.

## 🚀 Quick Start

Run the setup script to configure auto-start:

```bash
cd /Users/gourbera/ai_engineering/projects/streaming_app/startup
./setup-auto-start.sh
```

This will:
- Make all scripts executable
- Install a LaunchAgent for auto-start on system reboot
- Configure environment variables
- Start the services

## 📁 Files Overview

### Main Scripts

- **`setup-auto-start.sh`** - Installation script (run this first)
- **`robust-startup.sh`** - Main service management script
- **`auto-start-services.sh`** - Wrapper script called by LaunchAgent
- **`health-monitor.sh`** - Health monitoring and auto-recovery
- **`com.streaming.services.plist`** - macOS LaunchAgent configuration

### How It Works

1. **LaunchAgent**: Starts services automatically on login
2. **Port-Forwarding**: Creates localhost access to Kubernetes services
3. **Environment File**: Generates `.env` and `service_config.py` for Python
4. **Health Monitoring**: Continuously checks and restarts failed services

## 🛠️ Manual Commands

### Start Services
```bash
./robust-startup.sh start
```

### Stop Services
```bash
./robust-startup.sh stop
```

### Check Status
```bash
./robust-startup.sh status
```

### Health Check
```bash
./health-monitor.sh check
```

### Run Health Monitor (continuous)
```bash
./health-monitor.sh monitor
```

## 🐍 Using Services from Python

After services are started, Python scripts can access them in two ways:

### Method 1: Using service_config.py (Recommended)
```python
from service_config import get_redis_connection_params, KAFKA_BOOTSTRAP_SERVERS
import redis
from kafka import KafkaProducer

# Redis
r = redis.Redis(**get_redis_connection_params())
r.set('key', 'value')

# Kafka
producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS)
producer.send('topic', b'message')
```

### Method 2: Reading .env file manually
```python
from dotenv import load_dotenv
import os

load_dotenv()  # Loads from .env file
redis_host = os.getenv('REDIS_HOST')
redis_password = os.getenv('REDIS_PASSWORD')
```

## 🔧 Configuration

### Service Ports

- **Redis**: localhost:6379
- **Kafka**: localhost:9092
- **Spark UI**: http://localhost:8080
- **Spark Master**: spark://localhost:7077

### Environment Variables

Generated in `.env` file:
```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=<auto-retrieved>
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
SPARK_MASTER_URL=spark://localhost:7077
```

## 📋 Logs

All logs are stored in `/tmp/streaming_app/`:
- `auto-start.log` - Auto-start script logs
- `robust-startup.log` - Main startup logs
- `robust-startup.errors.log` - Error logs
- `health-monitor.log` - Health check logs
- `redis-portforward.log` - Redis port-forward logs
- `kafka-portforward.log` - Kafka port-forward logs
- `launchagent-stdout.log` - LaunchAgent output
- `launchagent-stderr.log` - LaunchAgent errors

View logs:
```bash
tail -f /tmp/streaming_app/*.log
```

## 🔄 Auto-Start After Reboot

The LaunchAgent ensures services start automatically:

1. System boots up
2. User logs in
3. LaunchAgent triggers `auto-start-services.sh`
4. Services are started and port-forwards established
5. Python scripts can access services immediately

### Managing LaunchAgent

```bash
# Check if loaded
launchctl list | grep com.streaming.services

# Manually load
launchctl load ~/Library/LaunchAgents/com.streaming.services.plist

# Manually unload
launchctl unload ~/Library/LaunchAgents/com.streaming.services.plist

# Remove completely
launchctl unload ~/Library/LaunchAgents/com.streaming.services.plist
rm ~/Library/LaunchAgents/com.streaming.services.plist
```

## 🩺 Troubleshooting

### Services Not Starting

1. **Check OrbStack is running**:
   ```bash
   orb --version
   kubectl cluster-info
   ```

2. **Check LaunchAgent status**:
   ```bash
   launchctl list | grep streaming
   ```

3. **View error logs**:
   ```bash
   cat /tmp/streaming_app/launchagent-stderr.log
   cat /tmp/streaming_app/robust-startup.errors.log
   ```

### Redis Authentication Issues

If Redis password retrieval fails:

1. **Check Redis secret**:
   ```bash
   kubectl get secret redis -n redis
   kubectl get secret redis -n redis -o yaml
   ```

2. **Manually set password in .env**:
   Edit `.env` file and set `REDIS_PASSWORD`

3. **Test Redis connection**:
   ```bash
   redis-cli -h localhost -p 6379 -a <password> PING
   ```

### Port Already in Use

If port-forward fails due to port conflict:

1. **Find process using port**:
   ```bash
   lsof -i :6379  # Redis
   lsof -i :9092  # Kafka
   ```

2. **Kill existing port-forward**:
   ```bash
   pkill -f "kubectl port-forward.*6379"
   ```

3. **Restart services**:
   ```bash
   ./robust-startup.sh restart
   ```

### Python Module Not Found

If Python can't find `service_config`:

1. **Verify file exists**:
   ```bash
   ls -la ../src/service_config.py
   ```

2. **Run from correct directory**:
   ```bash
   cd /Users/gourbera/ai_engineering/projects/streaming_app/src
   python redis_example.py
   ```

## 🎯 Features

✅ **Automatic Startup**: Services start on system reboot  
✅ **Password Management**: Automatically retrieves Redis password  
✅ **Health Monitoring**: Detects and recovers from failures  
✅ **Python Integration**: Easy access from Python code  
✅ **Comprehensive Logging**: All activities logged for debugging  
✅ **Status Notifications**: macOS notifications for service events  
✅ **Port-Forward Management**: Handles existing connections gracefully  

## 📝 Notes

- Requires **OrbStack** with Kubernetes enabled
- Requires **kubectl** command-line tool
- Services must be deployed in Kubernetes first
- Works only on **macOS** (uses LaunchAgent)
- Port-forwards are user-specific (not system-wide)

## 🆘 Support

For issues or questions:
1. Check logs in `/tmp/streaming_app/`
2. Run status check: `./robust-startup.sh status`
3. Run health check: `./health-monitor.sh check`
4. Verify OrbStack is running: `orb status`
