from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("hello-spark").getOrCreate()

data = [("Alice", 1), ("Bob", 2)]
df = spark.createDataFrame(data, ["name", "value"])

df.show()

spark.stop()
