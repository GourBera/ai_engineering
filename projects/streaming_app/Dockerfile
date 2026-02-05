FROM apache/spark-py:3.5.6

COPY spark_kafka_stream.py /opt/spark/work-dir/
# Tag it for Docker Hub or your registry
docker build -t docker.io/<your-dockerhub-username>/spark-kafka-job:3.5.6 .

# Push to registry
docker push docker.io/<your-dockerhub-username>/spark-kafka-job:3.5.6
