from kafka.admin import KafkaAdminClient

def list_topics(bootstrap_servers):
    admin = KafkaAdminClient(
        bootstrap_servers=bootstrap_servers,
        client_id="topic_lister"
    )

    try:
        topics = admin.list_topics()
        print("Topics in Kafka cluster:")
        for t in sorted(topics):
            print(" -", t)
    except Exception as e:
        print("Error listing topics:", e)
    finally:
        admin.close()

if __name__ == "__main__":
    list_topics([
        # External bootstrap address reported by Strimzi
        "192.168.139.2:30515",
        # Broker NodePort address (for direct broker connections)
        "192.168.139.2:30417"
    ])
