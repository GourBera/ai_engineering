Create configuration for docker-compose:

mkdir -p ./dags ./logs ./plugins ./config
echo -e "AIRFLOW_UID=$(id -u)" > .env

Get the docker compose file 
curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/docker-compose.yaml'

docker-compose up flower  

Initialize the database
docker compose up airflow-init


Cleaning-up the environment
docker compose down --volumes --remove-orphans

docker ps

Reference: https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html#docker-compose-env-variables




    airflow-scheduler - The scheduler monitors all tasks and Dags, then triggers the task instances once their dependencies are complete.

    airflow-dag-processor - The Dag processor parses Dag files.

    airflow-api-server - The api server is available at http://localhost:8080.

    airflow-worker - The worker that executes the tasks given by the scheduler.

    airflow-triggerer - The triggerer runs an event loop for deferrable tasks.

    airflow-init - The initialization service.

    postgres - The database.

    redis - The redis - broker that forwards messages from scheduler to worker.

