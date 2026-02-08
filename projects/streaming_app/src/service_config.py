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
