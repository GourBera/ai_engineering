from kafka import KafkaProducer, KafkaConsumer
import time
from service_config import KAFKA_BOOTSTRAP_SERVERS

print(f"Connecting to Kafka at {KAFKA_BOOTSTRAP_SERVERS}...")

try:
    # Create producer
    producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS)
    print("✓ Successfully connected to Kafka (producer)")
    
    # Send a message
    producer.send('test-topic', b'Hello, Kafka from Python!')
    producer.flush()
    print("✓ Message sent to Kafka topic 'test-topic'")
    
    time.sleep(1)  # Wait for message to be available
    
    # Create consumer
    consumer = KafkaConsumer(
        'test-topic',
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        auto_offset_reset='earliest',
        consumer_timeout_ms=5000
    )
    print("✓ Successfully connected to Kafka (consumer)")
    
    # Read messages
    message_count = 0
    for msg in consumer:
        print(f"✓ Received from Kafka: {msg.value.decode('utf-8')}")
        message_count += 1
        if message_count >= 3:  # Read up to 3 messages
            break
    
    consumer.close()
    producer.close()
    print(f"\n✓ Successfully sent and received {message_count} message(s)")
    
except Exception as e:
    print(f"✗ Error connecting to Kafka: {e}")
    print("Make sure the services are started with ./startup/robust-startup.sh start")
