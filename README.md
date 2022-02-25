![image](https://user-images.githubusercontent.com/11318604/136972232-5aae8d2e-4d53-4022-9c60-407d488ba806.png)
# cloud-deploy-basic-demo
Commit to deploying on GKE using Cloud Build, BinAuth, Aritfact Registry and Cloud Deploy

This is a basic overview demo showing deploying a static website to GKE and exposing it with LoadBalancer to a Dev cluster and promoting it to a Prod Cluster.

The demo uses us-central1 as the region as Cloud deploy is in preview and is available in that region.

All of the YAMLS in the directory and readme are for example pruposes only you will need to add your project details etc to them.

## Enable the APIS
```
gcloud services enable \
clouddeploy.googleapis.com \
cloudbuild.googleapis.com \
storage-component.googleapis.com \
container.googleapis.com \
artifactregistry.googleapis.com \
cloudresourcemanager.googleapis.com \
cloudkms.googleapis.com \
binaryauthorization.googleapis.com \
sourcerepo.googleapis.com
```

## Define Variables
* export REGION=us-central1
* export ZONE=us-central1-a
* export PROJECT_NAME=_Your_Project_ID_
* export PROJECT_ID=$PROJECT_NAME
* export PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
* export PROD_CLUSTER=prod-cluster
* export DEV_CLUSTER=dev-cluster
* export PREPROD_CLUSTER=preprod-cluster
* export REPO_NAME=source-to-prod-demo
* export SHORT_SHA=\${SHORT_SHA}
* export CSR_REPO_NAME=sstp-container-event
* export NEW_REPO=https://source.developers.google.com/p/$PROJECT_ID/r/$CSR_REPO_NAME

## Clone the repo: Note: This only works on a public repo

This will be the main working directory for this build out.
Create a new repo on Cloud Source Repositories.
```
gcloud source repos create $CSR_REPO_NAME
git clone https://github.com/untitledteamuk/cloud-deploy-basic-demo && cd cloud-deploy-basic-demo
```
Push to your new repo on Cloud Source Repositories
```
git config credential.helper gcloud.sh
git remote add google $NEW_REPO
Git push --all google
```

Delete the current folder and pull the content from your new repo.
```
cd .. && rm -rf sstp-container-event
git clone $NEW_REPO && cd sstp-container-event
```

## Create the GKE Clusters:

```
gcloud compute networks create default //optional if you have the default vpc
gcloud container clusters create $DEV_CLUSTER --project=$PROJECT_NAME --region=$REGION --enable-binauthz
gcloud container clusters create $PREPROD_CLUSTER --project=$PROJECT_NAME --region=$REGION --enable-binauthz
gcloud container clusters create $PROD_CLUSTER --project=$PROJECT_NAME --region=$REGION --enable-binauthz
```
## Prepare Cloud Deploy:
### Check the yaml for Deploy 
Check and replace the yaml variables with your environment details.

#### skaffold.yaml:
```
cat skaffold.yaml

apiVersion: skaffold/v2beta12
kind: Config
build:
  artifacts:
  - image: skaffold-example
deploy:
  kubectl:
    manifests:
      - k8s-* //any yaml file prepended with k8s- will be deployed in GKE.
```

#### k8s-pod.yaml:
```
cat k8s-pod.yaml.template | envsubst > k8s-pod.yaml

apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    department: engineering
    app: nginx
spec:
  containers:
  - name: nginx
    image: $REGION-docker.pkg.dev/$PROJECT_NAME/$REPO_NAME/nginx:123 //we'll build this later
    imagePullPolicy: Always
    ports:
    - containerPort: 80
```

#### k8s-service.yaml:
```
cat k8s-service.yaml 

apiVersion: v1
kind: Service
metadata:
  name: my-nginx-service
spec:
  selector:
    app: nginx
    department: engineering
  type: LoadBalancer // this creates a HTTP LB for the deployment.
  ports:
  - port: 80
    targetPort: 80
```

#### clouddeploy.yaml:
```
cat clouddeploy.yaml.template  | envsubst > clouddeploy.yaml

apiVersion: deploy.cloud.google.com/v1beta1
kind: DeliveryPipeline
metadata:
 name: my-nginx-app-1
description: main application pipeline
serialPipeline:
 stages:
 - targetId: qsdev
   profiles: []
 - targetId: qspreprod
   profiles: []
 - targetId: qsprod
   profiles: []
---

apiVersion: deploy.cloud.google.com/v1beta1
kind: Target
metadata:
 name: qsdev
description: development cluster
gke:
 cluster: projects/$PROJECT_NAME/locations/$REGION/clusters/$DEV_CLUSTER
---

apiVersion: deploy.cloud.google.com/v1beta1
kind: Target
metadata:
 name: qspreprod
description: pre production cluster
requireApproval: true
gke:
 cluster: projects/$PROJECT_NAME/locations/$REGION/clusters/$PREPROD_CLUSTER
 ---

apiVersion: deploy.cloud.google.com/v1beta1
kind: Target
metadata:
 name: qsprod
description: production cluster
requireApproval: true
gke:
 cluster: projects/$PROJECT_NAME/locations/$REGION/clusters/$PROD_CLUSTER

```
#### Create the release:
```
gcloud beta deploy apply --file clouddeploy.yaml --region=$REGION --project=$PROJECT_NAME
```

We will leave this for now and work on Artifact registry and Cloud Build, their is no artifact to deploy yet so it would fail.

## Artifact Registry
Pre create repo, this is different from GCR where we couldn't do this.
#### Create the Repo
```
gcloud artifacts repositories create $REPO_NAME --repository-format=docker \
--location=$REGION --description="Docker repository"
```
We are going to be using Cloud build for build and push and the SA halready has permissions to access AR.

## BinAuth
#### Generate policy yaml.

You can create your own admission policy using the command below however a templated one is provided for the dmeo.

```
gcloud container binauthz policy export > admissionpolicy.yaml
```
#### edit admissionpolicy.yaml:
```
cat admissionpolicy.yaml.template | envsubst > admissionpolicy.yaml && cat admissionpolicy.yaml 

admissionWhitelistPatterns:
- namePattern: gcr.io/google_containers/*
- namePattern: gcr.io/google-containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gke.gcr.io/*
- namePattern: gcr.io/stackdriver-agents/*
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
  requireAttestationsBy:
  - projects/$PROJECT_ID/attestors/built-by-cloud-build
globalPolicyEvaluationMode: ENABLE
name: projects/$PROJECT_ID/policy
```
Cloud Build generates and signs attestations at build time. With Binary Authorization you can use the built-by-cloud-build attestor to verify the attestations and only deploy images built by Cloud Build. The built-by-cloud-build attestor is created the first time you run a build in a project.

```
gcloud builds submit --pack ^--^image=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/hello--env=GOOGLE_ENTRYPOINT='java -jar target/myjar.jar',GOOGLE_RUNTIME_VERSION='3.1.301'
```

Get the GKE Cluster credentials and apply the admission policy to each cluster.
```
gcloud container clusters get-credentials $DEV_CLUSTER --region $REGION --project $PROJECT_ID
gcloud container binauthz policy import admissionpolicy.yaml

gcloud container clusters get-credentials $PREPROD_CLUSTER --region $REGION --project $PROJECT_ID
gcloud container binauthz policy import admissionpolicy.yaml

gcloud container clusters get-credentials $PROD_CLUSTER --region $REGION --project $PROJECT_ID
gcloud container binauthz policy import admissionpolicy.yaml

```

## CloudBuild
### Set the permissions:
Give the Cloud Build SA the relevant perissions:

#### Add Cloud Deploy and actAs role to Cloud Build Service Account
```
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com   \
--role roles/clouddeploy.admin

gcloud projects add-iam-policy-binding $PROJECT_ID \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com   \
--role roles/iam.serviceAccountUser
```
#### Add GKE role to Cloud Build Service Account
```
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com   \
--role roles/container.admin
```
#### Add logging role to Cloud Build Service Account
```
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com   \
--role roles/logging.admin
```
#### Add editor role to Default Compute Engine Service Account
```
gcloud projects add-iam-policy-binding $PROJECT_ID \
--member serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com   \
--role roles/editor
```

### Build the demo container steps in CloudBuild:
There is already a Dockerfile and index.html file in the root of the working directory we will use.
#### Dockerfile.yaml:
```
cd ..

cat Dockerfile
FROM nginx:mainline-alpine
RUN rm -frv /usr/share/nginx/html/*
COPY index.html ./usr/share/nginx/html/
```
#### index.html:
```
cat index.html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx cloud deploy test!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to cloud deploy COMMIT_ID</h1>
<p>Woohoo a live demo works. binauth enabled</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```
#### cloudbuild.yaml:
```
cat cloudbuild.yaml.template | envsubst > cloudbuild.yaml && cat cloudbuild.yaml
```
Example output do not copy
```
steps:
# Get the short Commit ID from github.
- name: "gcr.io/cloud-builders/git"
  entrypoint: bash
  args:
  - '-c'
  - |
        SHORT_SHA=$(git rev-parse --short HEAD) 
# Add the Commit ID to the Dockerfile and the static page.
- name: "ubuntu"
  entrypoint: bash
  args:
  - '-c'
  - |
        sed -i 's/123/'"${SHORT_SHA}"'/g' k8s-pod.yaml  
        sed -i 's/COMMIT_ID/'"${SHORT_SHA}"'/g' index.html 
        cat k8s-pod.yaml

# build the container image
- name: "gcr.io/cloud-builders/docker"
  args: ["build", "-t", "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/nginx:${SHORT_SHA}", "."]

# push container image
- name: "gcr.io/cloud-builders/docker"
  args: ["push", "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/nginx:${SHORT_SHA}"]
# Get image digest for attesting BinAuth only works on image digest.
- name: "gcr.io/cloud-builders/gke-deploy"
  entrypoint: bash  
  args:
  - '-c'
  - |
       gke-deploy prepare --filename k8s-pod.yaml --image $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/nginx:${SHORT_SHA} --version ${SHORT_SHA}
       cp output/expanded/aggregated-resources.yaml k8s-pod.yaml

# deploy container image to GKE
- name: "gcr.io/cloud-builders/gcloud"
  entrypoint: 'bash'
  args:
  - '-c'
  - |
       gcloud beta deploy apply --file clouddeploy.yaml --region=$REGION --project=$PROJECT_ID
       gcloud beta deploy releases create nginx-release-${SHORT_SHA} --project=$PROJECT_ID --region=$REGION --delivery-pipeline=my-nginx-app-1

images:
- “$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/nginx:${SHORT_SHA}”
options:
  requestedVerifyOption: VERIFIED

```

#### Create a Cloud Build trgger:
That looks like, only with your repo not mine.

![4pTswGeZWcJichu](https://user-images.githubusercontent.com/11318604/155621109-4264c592-de14-4089-813f-13f28fa7da3e.png)
![5VqHkh9aTpuojZ9](https://user-images.githubusercontent.com/11318604/155621206-bfa20d00-33e4-411b-ad56-de8e8920f816.png)



#### push to git:

```
git add *
git commit -m 'something here'
git push
```
now watch cloud build, hopefully everything succeds. Go to Cloud deploy and look at the pipeline everything should deploy to the dev cluster at which point you can promote and approve to prod.

To show Bin auth working, do:

```
gcloud container clusters get-credentials $DEV_CLUSTER --region $REGION --project $PROJECT_ID
kubectl run ubuntu-test --image=ubuntu
Error from server (VIOLATES_POLICY): admission webhook "imagepolicywebhook.image-policy.k8s.io" denied the request: Image ubuntu denied by Binary Authorization default admission rule. 

```

