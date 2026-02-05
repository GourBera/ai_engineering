from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("example").getOrCreate()
data = [(1, "foo"), (2, "bar")]
df = spark.createDataFrame(data, ["id", "value"]) 
df.show()
spark.stop()