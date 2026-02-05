from pyspark.sql import SparkSession

def main():
    spark = SparkSession.builder.appName("PySparkApp").getOrCreate()
    data = [(1, "Alice"), (2, "Bob"), (3, "Charlie")]
    df = spark.createDataFrame(data, ["id", "name"])
    df.show()
    spark.stop()

if __name__ == "__main__":
    main()
