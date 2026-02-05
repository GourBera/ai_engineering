from confluent_kafka.admin import AdminClient

def list_topics(bootstrap_servers):
    conf = {"bootstrap.servers": bootstrap_servers}
    admin = AdminClient(conf)

    # Fetch metadata (topics + brokers)
    metadata = admin.list_topics(timeout=10)

    print("Topics in Kafka cluster:")
    for t in metadata.topics:
        print(" -", t)

if __name__ == "__main__":
    # Use the external bootstrap address from Strimzi status
    list_topics("192.168.139.2:30515")
