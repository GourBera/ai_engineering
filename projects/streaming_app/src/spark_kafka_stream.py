from pyspark.sql import SparkSession

# Update this to match your Kafka internal bootstrap service in Kubernetes:
KAFKA_BOOTSTRAP = "my-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092"
TOPIC = "my_first_topic"

def main():
    spark = (
        SparkSession.builder
        .appName("KafkaSparkOnK8s")
        .getOrCreate()
    )

    # Read from Kafka as a streaming source
    kafka_df = (
        spark.readStream
             .format("kafka")
             .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP)
             .option("subscribe", TOPIC)
             .option("startingOffsets", "earliest")
             .load()
    )

    # Convert key and value from bytes to strings
    processed_df = kafka_df.selectExpr(
        "CAST(key AS STRING)", "CAST(value AS STRING)"
    )

    # Write output to console
    query = (
        processed_df.writeStream
                    .format("console")
                    .option("checkpointLocation", "/tmp/spark_kafka_checkpoint")
                    .start()
    )

    query.awaitTermination()

if __name__ == "__main__":
    main()
