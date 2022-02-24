bin/bash!
export REGION=us-central1
export ZONE=us-central1-a
export PROJECT_NAME=$(gcloud config get-value project)
export PROJECT_ID=$PROJECT_NAME
export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
export PROD_CLUSTER=prod-cluster
export DEV_CLUSTER=dev-cluster
export PREPROD_CLUSTER=preprod-cluster
export REPO_NAME=source-to-prod-demo
export KMS_KEY_PROJECT_ID=$PROJECT_ID
export KMS_KEYRING_NAME=my-binauthz-keyring
export KMS_KEY_NAME=my-binauthz-key
export KMS_KEY_LOCATION=global
export KMS_KEY_PURPOSE=asymmetric-signing
export KMS_KEY_ALGORITHM=ec-sign-p256-sha256
export KMS_PROTECTION_LEVEL=software
export KMS_KEY_VERSION=1
export DEPLOYER_PROJECT_ID=$PROJECT_ID
export DEPLOYER_PROJECT_NUMBER="$(gcloud projects describe "${DEPLOYER_PROJECT_ID}" --format="value(projectNumber)")"
export ATTESTOR_PROJECT_ID=$PROJECT_ID
export ATTESTOR_PROJECT_NUMBER="$(gcloud projects describe "${ATTESTOR_PROJECT_ID}" --format="value(projectNumber)")"
export ATTESTOR_NAME=clouddeploy_demo
export SHORT_SHA=\${SHORT_SHA}

gcloud config set compute/region $REGION //sets the default region used for regional services

gcloud config set compute/zone $ZONE //sets the default Zone for Zonale services.
