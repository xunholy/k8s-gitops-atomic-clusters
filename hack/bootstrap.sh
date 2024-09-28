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

if [ -z "$GITHUB_USER" ] || [ -z "$GITHUB_TOKEN" ]; then
  echo "Error required env variables are not set" && exit 1
fi

# Management GKE cluster configuration
export CLUSTER_NAME=cluster-00
export CLUSTER_REGION=australia-southeast1
# FluxCD configuration
export DEFAULT_GITHUB_BRANCH=main
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

gcloud config set project $PROJECT_ID

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
if ! gcloud iam service-accounts list --filter="email:${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" | grep -q ${KCC_SERVICE_ACCOUNT_NAME}; then
  gcloud iam service-accounts create ${KCC_SERVICE_ACCOUNT_NAME}
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/editor"
else
  echo "KCC service account already exists"
fi

# Check and create SOPS service account if it doesn't exist
if ! gcloud iam service-accounts list --filter="email:${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" | grep -q ${SOPS_SERVICE_ACCOUNT_NAME}; then
  gcloud iam service-accounts create ${SOPS_SERVICE_ACCOUNT_NAME}
  gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

  # TODO: Determine if this is needed - try without it.
  # gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  #   --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
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
    --project $PROJECT_ID \
    --release-channel rapid
else
  echo "Cluster $CLUSTER_NAME already exists"
fi

# Setup Workload Identity for FluxCD and KCC
# Bind FluxCD's kustomize-controller to the SOPS service account if not already bound
if ! gcloud iam service-accounts get-iam-policy ${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --flatten="bindings[].members" \
  --filter="bindings.members=serviceAccount:${PROJECT_ID}.svc.id.goog[flux-system/kustomize-controller]" \
  --format="value(bindings.role)" | grep -q "roles/iam.workloadIdentityUser"; then
  gcloud iam service-accounts add-iam-policy-binding \
    ${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[flux-system/kustomize-controller]" \
    --role="roles/iam.workloadIdentityUser"
else
    echo "Workload identity binding for kustomize-controller already exists"
fi

# Bind KCC's controller-manager to the KCC service account if not already bound
if ! gcloud iam service-accounts get-iam-policy ${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --flatten="bindings[].members" \
  --filter="bindings.members=serviceAccount:${PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
  --format="value(bindings.role)" | grep -q "roles/iam.workloadIdentityUser"; then
  gcloud iam service-accounts add-iam-policy-binding \
    ${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
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

# Bootstrap FluxCD - This is generally already an idempotent command
flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --owner="$GITHUB_USER" \
  --repository="$DEFAULT_GITHUB_REPO" \
  --path=kubernetes/clusters/$CLUSTER_NAME \
  --branch="$DEFAULT_GITHUB_BRANCH" \
  --personal=true \
  --private=false

# # Create public IP for XLB
# gcloud compute addresses create static-mci-ip --global --project $PROJECT_ID
# export STATIC_MCI_IP=`gcloud compute addresses describe static-mci-ip --project $PROJECT_ID --global --format="value(address)"`
# echo -e "GCLB_IP is $STATIC_MCI_IP"

# gcloud compute addresses create team-alpha-tenant-api --global --project $PROJECT_ID
# export ALPHA_IP=`gcloud compute addresses describe team-alpha-tenant-api --project $PROJECT_ID --global --format="value(address)"`
# echo -e "GCLB_IP is $ALPHA_IP"

# gcloud compute addresses create team-bravo-tenant-api --global --project $PROJECT_ID
# export BRAVO_IP=`gcloud compute addresses describe team-bravo-tenant-api --project $PROJECT_ID --global --format="value(address)"`
# echo -e "GCLB_IP is $BRAVO_IP"

# # Create Service Endpoint
# cat <<EOF > demo-openapi.yaml
# swagger: "2.0"
# info:
#   description: "Cloud Endpoints DNS"
#   title: "Cloud Endpoints DNS"
#   version: "1.0.0"
# paths: {}
# host: "$DEMO_NAME.endpoints.${PROJECT_ID}.cloud.goog"
# x-google-endpoints:
# - name: "$DEMO_NAME.endpoints.${PROJECT_ID}.cloud.goog"
#   target: "${STATIC_MCI_IP}"
# EOF
# gcloud endpoints services deploy demo-openapi.yaml --project $PROJECT_ID

# cat <<EOF > alpha-openapi.yaml
# swagger: "2.0"
# info:
#   description: "Cloud Endpoints DNS"
#   title: "Cloud Endpoints DNS"
#   version: "1.0.0"
# paths: {}
# host: "team-alpha.endpoints.${PROJECT_ID}.cloud.goog"
# x-google-endpoints:
# - name: "team-alpha.endpoints.${PROJECT_ID}.cloud.goog"
#   target: "${ALPHA_IP}"
# EOF

# gcloud endpoints services deploy alpha-openapi.yaml --project $PROJECT_ID

# cat <<EOF > bravo-openapi.yaml
# swagger: "2.0"
# info:
#   description: "Cloud Endpoints DNS"
#   title: "Cloud Endpoints DNS"
#   version: "1.0.0"
# paths: {}
# host: "team-bravo.endpoints.${PROJECT_ID}.cloud.goog"
# x-google-endpoints:
# - name: "team-bravo.endpoints.${PROJECT_ID}.cloud.goog"
#   target: "${BRAVO_IP}"
# EOF

# gcloud endpoints services deploy bravo-openapi.yaml --project $PROJECT_ID

# # Create Certificate
# gcloud compute ssl-certificates create whereamicert \
#   --project $PROJECT_ID \
#   --domains=$DEMO_NAME.endpoints.$PROJECT_ID.cloud.goog \
#   --global

# gcloud compute ssl-certificates create alpha-tenant-cert \
#       --project $PROJECT_ID \
#       --domains="team-alpha.endpoints.$PROJECT_ID.cloud.goog" \
#       --global

# gcloud compute ssl-certificates create bravo-tenant-cert \
#       --project $PROJECT_ID \
#       --domains="team-bravo.endpoints.$PROJECT_ID.cloud.goog" \
#       --global

# # Step 3 -> https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services
# gcloud projects add-iam-policy-binding $PROJECT_ID \
#     --member "serviceAccount:$PROJECT_ID.svc.id.goog[gke-mcs/gke-mcs-importer]" \
#     --role "roles/compute.networkViewer"
