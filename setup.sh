export REGION=us-central1
export ZONE=us-central1-a
export PROJECT_NAME=$(gcloud config get-value project)
export PROJECT_ID=$PROJECT_NAME
export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
export PROD_CLUSTER=prod-cluster
export DEV_CLUSTER=dev-cluster
export PREPROD_CLUSTER=preprod-cluster
export REPO_NAME=source-to-prod-demo
export SHORT_SHA=\${SHORT_SHA}
export CSR_REPO_NAME=sstp-container-event
export NEW_REPO=https://source.developers.google.com/p/$PROJECT_ID/r/$CSR_REPO_NAME


gcloud config set compute/region $REGION //sets the default region used for regional services

gcloud config set compute/zone $ZONE //sets the default Zone for Zonal services.
