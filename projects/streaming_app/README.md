brew install helm
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update


kubectl create namespace redis
kubectl create namespace kafka
kubectl create namespace spark
kubectl get ns
kubectl get namespaces


helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update


Install Redis
helm install redis bitnami/redis \
  --namespace redis \
  --set architecture=standalone

kubectl get pods -n redis -w


NAME: redis
LAST DEPLOYED: Tue Feb  3 22:13:23 2026
NAMESPACE: redis
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
CHART NAME: redis
CHART VERSION: 24.1.3
APP VERSION: 8.4.0

⚠ WARNING: Since August 28th, 2025, only a limited subset of images/charts are available for free.
    Subscribe to Bitnami Secure Images to receive continued support and security updates.
    More info at https://bitnami.com and https://github.com/bitnami/containers/issues/83267

** Please be patient while the chart is being deployed **

Redis&reg; can be accessed via port 6379 on the following DNS name from within your cluster:

    redis-master.redis.svc.cluster.local



To get your password run:

    export REDIS_PASSWORD=$(kubectl get secret --namespace redis redis -o jsonpath="{.data.redis-password}" | base64 -d)

To connect to your Redis&reg; server:

1. Run a Redis&reg; pod that you can use as a client:

   kubectl run --namespace redis redis-client --restart='Never'  --env REDIS_PASSWORD=$REDIS_PASSWORD  --image registry-1.docker.io/bitnami/redis:latest --command -- sleep infinity

   Use the following command to attach to the pod:

   kubectl exec --tty -i redis-client \
   --namespace redis -- bash

2. Connect using the Redis&reg; CLI:
   REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h redis-master

To connect to your database from outside the cluster execute the following commands:

    kubectl port-forward --namespace redis svc/redis-master 6379:6379 &
    REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379



Install Kafka (KRaft mode, no Zookeeper)

kubectl apply -n kafka -f "https://strimzi.io/install/latest?namespace=kafka"
kubectl apply -f kafka-cr.yaml
kubectl apply -f kafka-nodepool.yaml
kubectl apply -f kafka-external.yaml

kubectl get svc -n kafka | grep my-kafka

kubectl port-forward svc/my-kafka-kafka-bootstrap 9092:9092 -n kafka
kubectl get kafka my-kafka -n kafka -o=jsonpath='{.status.listeners[?(@.name=="external")].bootstrapServers}{"\n"}'


kubectl get pods -n kafka -w

kubectl exec -n kafka -it my-kafka-default-0 -- bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
kafka-topics.sh --create --topic test --bootstrap-server localhost:9092


brew install apache-spark
spark-submit --version
kubectl create namespace spark
kubectl apply -f spark-rbac.yaml

spark-submit \
  --master k8s://https://127.0.0.1:6443 \
  --deploy-mode cluster \
  --name pyspark-test \
  --conf spark.executor.instances=2 \
  --conf spark.kubernetes.namespace=spark \
  --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
  --conf spark.kubernetes.container.image=apache/spark:3.5.0 \
  local:/Users/gourbera/Developer/projects/streaming_app/spark-job.py

kubectl get pods -n spark




helm repo add spark-operator https://kubeflow.github.io/spark-operator
helm repo update

helm install spark-operator spark-operator/spark-operator \
  --namespace spark-operator \
  --create-namespace \
  --wait



kubectl apply -f spark-pi.yaml

## Listing topics (Poetry)

- **Command run:**

  ```bash
  cd projects/streaming_app
  poetry install --no-root --no-interaction
  poetry run python src/list_topics.py
  ```

- **Observed output:**

  ```text
  kafka.errors.NoBrokersAvailable: NoBrokersAvailable
  ```

- **Notes / Troubleshooting:**
  - The script `src/list_topics.py` expects reachable Kafka bootstrap servers. See [projects/streaming_app/src/list_topics.py](projects/streaming_app/src/list_topics.py#L1-L40).
  - If your cluster is running in Kubernetes (Strimzi), either ensure the external bootstrap address is reachable from your host, or port-forward the bootstrap service into localhost and update the bootstrap address. Example:

    ```bash
    kubectl port-forward svc/my-kafka-kafka-bootstrap 9092:9092 -n kafka
    ```

    Then re-run the script with `127.0.0.1:9092` in the bootstrap list or keep the existing addresses if they resolve to the forwarded port.
  - Alternatively, exec into a pod inside the `kafka` namespace and run `kafka-topics.sh --list` there to verify topics.


### Permanent Kafka/Redis Port-Forward (macOS LaunchAgent)

When you run `startup/kafka-start.sh` or `startup/redis-start.sh`, the script will:

- Copy the corresponding LaunchAgent plist to `~/Library/LaunchAgents/`.
- Load it with `launchctl` so the port-forward runs automatically on login and after restart.
- The port-forward will be supervised by launchd and will restart if it fails.

**Kafka:**
```bash
cd projects/streaming_app/startup
./kafka-start.sh start
```

**Redis:**
```bash
cd projects/streaming_app/startup
./redis-start.sh start
```

**To check status:**
```bash
launchctl list | grep streaming_app
tail -f /tmp/streaming_app.kafka.log
tail -f /tmp/streaming_app.redis.log
```

**To unload (disable):**
```bash
launchctl unload ~/Library/LaunchAgents/com.streaming_app.kafka.plist
launchctl unload ~/Library/LaunchAgents/com.streaming_app.redis.plist
```

**Python scripts:** `src/list_topics.py` and others will always work after restart, as the port-forward and `.env` are kept active by launchd.


