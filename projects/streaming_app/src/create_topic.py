from confluent_kafka.admin import AdminClient, NewTopic

def create_topic(bootstrap_servers, topic_name):
    conf = {"bootstrap.servers": bootstrap_servers}
    admin = AdminClient(conf)

    new_topic = NewTopic(topic_name, num_partitions=1, replication_factor=1)
    fs = admin.create_topics([new_topic])

    for topic, f in fs.items():
        try:
            f.result()
            print(f"Topic '{topic}' created")
        except Exception as e:
            print(f"Failed to create topic {topic}: {e}")

if __name__ == "__main__":
    create_topic("192.168.139.2:30515", "my_first_topic")
