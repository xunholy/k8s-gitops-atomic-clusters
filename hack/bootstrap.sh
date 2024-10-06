#!/bin/bash

# This file is to bootstrap the initial management GKE cluster which will be called cluster-00.
# Additionally it will setup tooling such as SOPS GCP KMS encryption.
# https://cloud.google.com/config-connector/docs/how-to/advanced-install
# https://github.com/getsops/sops#23encrypting-using-gcp-kms
# https://fluxcd.io/flux/guides/mozilla-sops/#google-cloud

set -eou pipefail

if ! command -v sops &> /dev/null; then
    echo "sops must be installed" && exit 1
fi

if ! command -v flux &> /dev/null; then
    echo "flux must be installed." && exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error required env variables are not set" && exit 1
fi

# Management GCP project configuration
export GCP_PROJECT_ID=atomic-gke-clusters
export GCP_PROJECT_NUMBER=1090173588460

# Management GKE cluster configuration
export CLUSTER_NAME=cluster-00
export CLUSTER_REGION=australia-southeast1

# FluxCD configuration
export DEFAULT_GITHUB_BRANCH=main
export DEFAULT_GITHUB_OWNER=xunholy
export DEFAULT_GITHUB_REPO=k8s-gitops-atomic-clusters

# GCP Tooling Service Accounts
export KCC_SERVICE_ACCOUNT_NAME=kcc-sa
export SOPS_SERVICE_ACCOUNT_NAME=sops-sa
export DEMO_NAME="gitops-gke"

if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo "Already authenticated"
else
    echo "Not authenticated. Running gcloud auth login..."
    gcloud auth login --update-adc
fi

gcloud config set project $GCP_PROJECT_ID

# Enable required services if not already enabled
required_services=(
  servicemanagement.googleapis.com
  servicecontrol.googleapis.com
  cloudresourcemanager.googleapis.com
  cloudkms.googleapis.com
  compute.googleapis.com
  container.googleapis.com
  containerregistry.googleapis.com
  cloudbuild.googleapis.com
  gkeconnect.googleapis.com
  gkehub.googleapis.com
  iam.googleapis.com
  mesh.googleapis.com
  multiclusterservicediscovery.googleapis.com
  multiclusteringress.googleapis.com
  trafficdirector.googleapis.com
  anthos.googleapis.com
  dns.googleapis.com
)

for service in "${required_services[@]}"; do
  if ! gcloud services list --enabled --filter="config.name=$service" --format="value(config.name)" | grep -q "$service"; then
    gcloud services enable "$service"
  else
    echo "$service is already enabled"
  fi
done

# Check and create KCC service account if it doesn't exist
if ! gcloud iam service-accounts list --filter="email:${KCC_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" | grep -q ${KCC_SERVICE_ACCOUNT_NAME}; then
  gcloud iam service-accounts create ${KCC_SERVICE_ACCOUNT_NAME}
  gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
    --member="serviceAccount:${KCC_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/editor"
else
  echo "KCC service account already exists"
fi

# Check and create SOPS service account if it doesn't exist
if ! gcloud iam service-accounts list --filter="email:${SOPS_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" | grep -q ${SOPS_SERVICE_ACCOUNT_NAME}; then
  gcloud iam service-accounts create ${SOPS_SERVICE_ACCOUNT_NAME}
  gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
    --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

  # TODO: Determine if this is needed - try without it.
  # gcloud projects add-iam-policy-binding ${GCP_PROJECT_ID} \
  #   --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  #   --role="roles/editor"
else
  echo "SOPS service account already exists"
fi


# Check and create KMS keyring if it doesn't exist
if ! gcloud kms keyrings list --location global --format="value(name)" | grep -q "sops"; then
  gcloud kms keyrings create sops --location global
fi

# Check and create KMS key if it doesn't exist
if ! gcloud kms keys list --location global --keyring sops --format="value(name)" | grep -q "sops-key"; then
  gcloud kms keys create sops-key --location global --keyring sops --purpose encryption
  gcloud kms keys list --location global --keyring sops
fi


# Setup the Management GKE cluster only if it doesn't exist
if ! gcloud container clusters list --region=$CLUSTER_REGION --filter="name=$CLUSTER_NAME" --format="value(name)" | grep -q "$CLUSTER_NAME"; then
  gcloud container clusters create-auto $CLUSTER_NAME \
    --region $CLUSTER_REGION \
    --project $GCP_PROJECT_ID \
    --release-channel rapid
else
  echo "Cluster $CLUSTER_NAME already exists"
fi

# Setup Workload Identity for FluxCD and KCC
# Bind FluxCD's kustomize-controller to the SOPS service account if not already bound
if ! gcloud iam service-accounts get-iam-policy ${SOPS_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
  --flatten="bindings[].members" \
  --filter="bindings.members=serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[flux-system/kustomize-controller]" \
  --format="value(bindings.role)" | grep -q "roles/iam.workloadIdentityUser"; then
  gcloud iam service-accounts add-iam-policy-binding \
    ${SOPS_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[flux-system/kustomize-controller]" \
    --role="roles/iam.workloadIdentityUser"
else
    echo "Workload identity binding for kustomize-controller already exists"
fi

# Bind KCC's controller-manager to the KCC service account if not already bound
if ! gcloud iam service-accounts get-iam-policy ${KCC_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
  --flatten="bindings[].members" \
  --filter="bindings.members=serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
  --format="value(bindings.role)" | grep -q "roles/iam.workloadIdentityUser"; then
  gcloud iam service-accounts add-iam-policy-binding \
    ${KCC_SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${GCP_PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
    --role="roles/iam.workloadIdentityUser"
else
    echo "Workload identity binding for cnrm-controller-manager already exists"
fi

# Add a one-time Github token to the cluster
if ! kubectl get secret github-token --namespace=flux-system &> /dev/null; then
  echo "Creating SOPS keys"
  kubectl create secret generic github-token \
    --namespace=flux-system \
    --from-literal=token=$GITHUB_TOKEN \
    --dry-run=client -oyaml \
    > kubernetes/namespaces/base/flux-system/addons/notifications/github/secret.enc.yaml

  sops --encrypt --in-place kubernetes/namespaces/base/flux-system/addons/notifications/github/secret.enc.yaml
else
  echo "Github token secret already exists"
fi

# Create the namespace if it doesn't already exist
kubectl get namespace flux-system >/dev/null 2>&1 || kubectl create namespace flux-system

# Always create or update the ConfigMap
kubectl create configmap cluster-config -n flux-system \
  --from-literal=GCP_PROJECT_ID=$GCP_PROJECT_ID \
  --from-literal=GCP_PROJECT_NUMBER=$GCP_PROJECT_NUMBER \
  --from-literal=GKE_CLUSTER_NAME=$CLUSTER_NAME \
  --from-literal=GKE_LOCATION=$CLUSTER_REGION \
  --from-literal=REPO_OWNER=$DEFAULT_GITHUB_OWNER \
  --from-literal=REPO_NAME=$DEFAULT_GITHUB_REPO \
  --dry-run=client -o yaml | kubectl apply -f -

# Bootstrap FluxCD - This is generally already an idempotent command
flux bootstrap github \
  --owner="$DEFAULT_GITHUB_OWNER" \
  --repository="$DEFAULT_GITHUB_REPO" \
  --path=kubernetes/clusters/$CLUSTER_NAME \
  --branch="$DEFAULT_GITHUB_BRANCH" \
  --personal=true \
  --private=false \
  --timeout=10m0s

# Create public IP for XLB
gcloud compute addresses create team-alpha-tenant-api --global --project $GCP_PROJECT_ID
export ALPHA_IP=`gcloud compute addresses describe team-alpha-tenant-api --project $GCP_PROJECT_ID --global --format="value(address)"`
echo -e "GCLB_IP is $ALPHA_IP"

cat <<EOF > alpha-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog"
  target: "${ALPHA_IP}"
EOF
gcloud endpoints services deploy alpha-openapi.yaml --project $GCP_PROJECT_ID

# Create Certificate
gcloud compute ssl-certificates create whereamicert \
  --project $GCP_PROJECT_ID \
  --domains=$DEMO_NAME.endpoints.$GCP_PROJECT_ID.cloud.goog \
  --global

gcloud compute ssl-certificates create alpha-tenant-cert \
      --project $GCP_PROJECT_ID \
      --domains="team-alpha.endpoints.$GCP_PROJECT_ID.cloud.goog" \
      --global
