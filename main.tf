##############
# Enable APIs
##############

resource "google_project_service" "api_dataflow" {
  project = var.project
  service = "dataflow.googleapis.com"
}

resource "google_project_service" "api_functions" {
  project = var.project
  service = "cloudfunctions.googleapis.com"
}

resource "google_project_service" "api_scheduler" {
  project = var.project
  service = "cloudscheduler.googleapis.com"
}

##############
# Ingest Pipeline
##############

resource "google_pubsub_topic" "ingest_streaming" {
  name    = "ingest-topic"
  project = var.project
}

resource "google_pubsub_subscription" "ingest" {
  name    = "ingest-subscription"
  topic   = google_pubsub_topic.ingest_streaming.name
  project = var.project

  message_retention_duration = "1200s"
  retain_acked_messages      = true
  ack_deadline_seconds       = 20
}

resource "google_bigquery_dataset" "datalake" {
  project                     = var.project
  dataset_id                  = "data_lake"
  friendly_name               = "data lake"
  description                 = "This stores the ingested data"
  location                    = "US"
  default_table_expiration_ms = 3600000
}

resource "google_bigquery_table" "subscriber_stats" {
  dataset_id = google_bigquery_dataset.datalake.dataset_id
  table_id   = "subscriber_browsing"
  project = var.project

  schema = <<EOF
[
  {
    "description": "Number of Mobile Subscriber",
    "mode": "REQUIRED",
    "name": "mobileNum",
    "type": "STRING"
  },
  {
    "description": "URL Accessed over the phone",
    "mode": "NULLABLE",
    "name": "url",
    "type": "STRING"
  },
  {
    "description": "Session Start Time yyyy-MM-dd HH:mm:ss",
    "mode": "NULLABLE",
    "name": "SessionStartTime",
    "type": "DATETIME"
  },
  {
    "description": "Session End Time yyyy-MM-dd HH:mm:ss",
    "mode": "NULLABLE",
    "name": "SessionEndTime",
    "type": "DATETIME"
  },
  {
    "description": "Bytes Downloaded",
    "mode": "NULLABLE",
    "name": "bytesIn",
    "type": "INT64"
  },
  {
    "description": "Bytes Uploaded",
    "mode": "NULLABLE",
    "name": "bytesOut",
    "type": "INT64"
  }
]
EOF

  depends_on = [google_bigquery_dataset.datalake] 
}

resource "google_storage_bucket" "dataflow_temp" {
  project            = var.project
  name               = "dataflow-temp_${var.project}"
  location           = "US"
  force_destroy      = true
  bucket_policy_only = true
}

resource "google_dataflow_job" "stream_to_bigquery" {
  name    = "pubsub-bigquery"
  project = var.project
  zone    = "us-central1-a" # change this later

  template_gcs_path = "gs://dataflow-templates-us-central1/latest/PubSub_Subscription_to_BigQuery"
  temp_gcs_location = "gs://${google_storage_bucket.dataflow_temp.name}/temp"
  
  parameters = {
    inputSubscription = "projects/${var.project}/subscriptions/${google_pubsub_subscription.ingest.name}"
    outputTableSpec = "${var.project}:${google_bigquery_dataset.datalake.dataset_id}.${google_bigquery_table.subscriber_stats.table_id}"
  }

  depends_on = [google_project_service.api_dataflow, google_bigquery_dataset.datalake, google_storage_bucket.dataflow_temp, google_pubsub_subscription.ingest] 
}


##############
# Reporting Pipeline
##############

resource "google_storage_bucket" "reports" {
  project = var.project
  name               = "daily_reports_${var.project}"
  location           = "US"
  force_destroy      = true
  bucket_policy_only = true
}

resource "google_storage_bucket" "function_code" {
  name    = "function-code_${var.project}"
  project = var.project
}

data "archive_file" "function_dist" {
  type        = "zip"
  source_dir  = "./cloud_function"
  output_path = "./reports_function.zip"
  depends_on  = [google_storage_bucket.function_code] 
}

resource "google_storage_bucket_object" "function_archive" {
  name       = "reports_function.zip"
  bucket     = google_storage_bucket.function_code.name
  source     = data.archive_file.function_dist.output_path
  depends_on = [google_storage_bucket.function_code]        
}

resource "google_cloudfunctions_function" "create_reports" {
  name        = "create-reports"
  description = "Creates the CSV reports and saves to a bucket"
  runtime     = "python37"
  project     = var.project
  region      = var.region

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.function_code.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  entry_point           = "run_func"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.report_topic.name
  } 

  environment_variables = {
    BUCKETNAME = google_storage_bucket.reports.name
  } 

  depends_on = [google_project_service.api_functions, google_storage_bucket_object.function_archive, google_storage_bucket.reports]        
}

resource "google_pubsub_topic" "report_topic" {
  name    = "report-topic"
  project = var.project
}

resource "google_app_engine_application" "app" {
  project     = var.project
  location_id = "us-central" # change this later
  # description = "To prevent Cloud Scheduler error message"
}

resource "google_cloud_scheduler_job" "job-report" {
  name        = "scheduled-report"
  description = "Run reports at midnight"
  schedule    = "0 0 * * *"
  time_zone   = "Australia/Melbourne"
  project     = var.project
  region      = var.region

  pubsub_target {
    topic_name = google_pubsub_topic.report_topic.id
    data       = base64encode("test")
  }
  depends_on = [google_project_service.api_scheduler, google_app_engine_application.app, google_pubsub_topic.report_topic] 
}