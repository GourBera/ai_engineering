import redis
from service_config import get_redis_connection_params, REDIS_HOST, REDIS_PORT

print(f"Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}...")

# Connect to Redis using auto-loaded configuration
conn_params = get_redis_connection_params()
r = redis.Redis(**conn_params)

# Test the connection
try:
    r.ping()
    print("✓ Successfully connected to Redis")
    
    # Set and get a value
    r.set('foo', 'bar')
    val = r.get('foo')
    print(f"✓ Redis value for 'foo': {val}")
    
    # Set and get another value
    r.set('test_key', 'Hello from Python!')
    test_val = r.get('test_key')
    print(f"✓ Redis value for 'test_key': {test_val}")
    
except redis.exceptions.ConnectionError as e:
    print(f"✗ Failed to connect to Redis: {e}")
    print("Make sure the services are started with ./startup/robust-startup.sh start")
except redis.exceptions.AuthenticationError as e:
    print(f"✗ Redis authentication failed: {e}")
    print("Check the Redis password in .env file")
except Exception as e:
    print(f"✗ Unexpected error: {e}")
