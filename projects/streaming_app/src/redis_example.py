import os
import redis

# Config from environment
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', 6379))
REDIS_PASSWORD = os.environ.get('REDIS_PASSWORD')

# Connect to Redis (adjust host/port/password if needed)
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, db=0)
r.set('foo', 'bar')
val = r.get('foo')
print('Redis value for foo:', val)
