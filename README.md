# Data Pipeline

## Setup

There are multiple methods that can be used to setup the environment, however, the first option below is preferred due to providing an interactive experience and simple UI.


### Cloud - Automatic (Preferred)

Click [this link](https://console.cloud.google.com/cloudshell/open?cloudshell_image=gcr.io/graphite-cloud-shell-images/terraform:latest&cloudshell_git_repo=https://github.com/diggerdric/data_pipeline_acc.git&cloudshell_git_branch=master&cloudshell_working_dir=./&open_in_editor=./main.tf&cloudshell_tutorial=./README.md) to open a Cloud Shell in GCP with this repo.

### Cloud - Manual

In the Cloud Console in GCP, enter the following code and then click "Open in Editor" when prompted:

```bash
cloudshell_open --repo_url "https://github.com/diggerdric/data_pipeline_acc" --dir "./" --page "editor" --tutorial "./README.md" --open_in_editor "./main.tf" --git_branch "master"
```
### Local

Install Terraform and then clone this repo locally.

## Deployment

### Configuring GCP

In addition to a GCP account, you'll need to create a **GCP Project** to follow this guide.

Create or select the project you'd like to use throughout this guide below.

<walkthrough-project-billing-setup></walkthrough-project-billing-setup>

You can set the project id to use for the rest of this guide with the following command:

```bash
export GOOGLE_CLOUD_PROJECT={{project-id}}
```


### Configuring Terraform

Run the following steps to deploy the code:

```bash
terraform init
```

```bash
terraform apply -var 'project={{project-id}}'
```

To confirm the confgurations set in the main.tf file, a prompt appears asking to "*Enter a value*", simply type `yes`.


### Duration
The deployment process should take around five minutes to complete. Maybe a good time for a coffee?

## Ingest Pipeline

### Ingest Data

Run the following code to setup the project ID so it doesn't have to be re-entered every time. Replace `<PROJECT-ID>` with the ID of the project you just deployed to:

```bash
gcloud config set project {{project-id}}
```

Run the following code to push data to the Pub Sub queue:

```
gcloud pubsub topics publish ingest-topic --message '{
 "mobileNum": "1234567890",
 "url": "www.google.com",
 "SessionStartTime": "2020-02-26 00:00:00",
 "SessionEndTime": "2020-02-27 00:00:00",
 "bytesIn": "1024",
 "bytesOut": "1024"
}'
```

### Verify Data

Run the following code to check the data has been stored in the data lake (BigQuery):

```
bq query --use_legacy_sql=false 'SELECT * FROM `{{project-id}}.data_lake.subscriber_browsing` LIMIT 10'
```

## Reporting Pipeline

### Trigger Pipeline

Rather than wait until midnight, run this command to trigger the scheduler immediately:

```bash
gcloud scheduler jobs run scheduled-report 
```

### View Reports

Find the bucket that the reports are saved to. It should be of the format: `gs://daily_reports_{{project-id}}`

```bash
gsutil ls gs:// 
```


Show all files in the bucket. There should be two reports: "report001...csv" and "report002...csv".

```bash
gsutil ls -r gs://daily_reports_{{project-id}}
```


Check the contents of the first report file.

```bash
gsutil cat gs://daily_reports_{{project-id}}/report001_<TIMESTAMP>.csv
```


Check the contents of the second report file.

```bash
gsutil cat gs://daily_reports_{{project-id}}/report002_<TIMESTAMP>.csv
```

## The End

Thank You! Have a great day!

