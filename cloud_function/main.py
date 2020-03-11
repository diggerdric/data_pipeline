from google.cloud import bigquery
from google.cloud import storage
import datetime
import os


def run_func(event, context):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
         event (dict): Event payload.
         context (google.cloud.functions.Context): Metadata for the event.
    """
    timestamp = datetime.datetime.today().strftime('%Y-%m-%dT%H-%M-%S')
    
    # report 1
    query = """select 
mobileNum, url, sum(bytesIn) as totalBytesIn, sum(bytesOut) as totalBytesOut
from `{0}.data_lake.subscriber_browsing`
where url is not null
group by 1, 2""".format(os.environ.get('GCP_PROJECT'))
    outputBucket = os.environ.get('BUCKETNAME')
    outputFileName = 'report001_{0}.csv'.format(timestamp)
    export_to_gcs(query, outputBucket, outputFileName)
    
    # report 2
    query = """select 
mobileNum, url, sum(timestamp_diff(cast(SessionEndTime as timestamp), cast(SessionStartTime as timestamp), second)) as totalSessionTimeSeconds
from `{0}.data_lake.subscriber_browsing`
where url is not null
group by 1, 2""".format(os.environ.get('GCP_PROJECT'))
    outputBucket = os.environ.get('BUCKETNAME')
    outputFileName = 'report002_{0}.csv'.format(timestamp)
    export_to_gcs(query, outputBucket, outputFileName)


def export_to_gcs(query, bucketName, fileName):
   bq_client = bigquery.Client()
   query_job = bq_client.query(query)
   # Wait for query to finish and save to df
   rows_df = query_job.result().to_dataframe() 
   storage_client = storage.Client()
   bucket = storage_client.get_bucket(bucketName)
   blob = bucket.blob(fileName)
   blob.upload_from_string(rows_df.to_csv(sep=',',index=False, encoding='utf-8')
                           ,content_type='application/octet-stream')