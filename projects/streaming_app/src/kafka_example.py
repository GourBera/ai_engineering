import os
from kafka import KafkaProducer, KafkaConsumer
import time

# Use KAFKA_BOOTSTRAP env var if provided, otherwise default to localhost:9092
bootstrap = os.environ.get('KAFKA_BOOTSTRAP', 'localhost:9092')
print(f"Using Kafka bootstrap servers: {bootstrap}")

producer = KafkaProducer(bootstrap_servers=bootstrap)
producer.send('test-topic', b'Hello, Kafka!')
producer.flush()
print('Message sent to Kafka!')

time.sleep(1)  # Wait for message to be available

consumer = KafkaConsumer('test-topic', bootstrap_servers=bootstrap, auto_offset_reset='earliest', consumer_timeout_ms=2000)
for msg in consumer:
    print('Received from Kafka:', msg.value)
    break
consumer.close()
