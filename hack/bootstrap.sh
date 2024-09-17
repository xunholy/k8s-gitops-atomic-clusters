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

if [ -z "$GITHUB_USER" ] || \
   [ -z "$GITHUB_TOKEN" ]; then
  echo "Error required env variables are not set" && exit 1
fi

# Management GKE cluster configuration
export CLUSTER_NAME=cluster-00
export CLUSTER_REGION=us-west1
# FluxCD configuration
export DEFUALT_GITHUB_BRANCH=main
export DEFUALT_GITHUB_REPO=k8s-gitops-atomic-clusters
# GCP Tooling Service Accounts
export KCC_SERVICE_ACCOUNT_NAME=kcc-sa
export SOPS_SERVICE_ACCOUNT_NAME=sops-sa
export DEMO_NAME="gitops-gke"

gcloud auth login
gcloud auth application-default login
gcloud config set project $PROJECT_ID

gcloud services enable \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  cloudresourcemanager.googleapis.com \
  cloudkms.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  containerregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudkms.googleapis.com \
  gkeconnect.googleapis.com \
  gkehub.googleapis.com \
  iam.googleapis.com \
  mesh.googleapis.com \
  multiclusterservicediscovery.googleapis.com \
  multiclusteringress.googleapis.com \
  trafficdirector.googleapis.com \
  anthos.googleapis.com \
  dns.googleapis.com

# Setup a KCC service account with appropriate permissions.
gcloud iam service-accounts create ${KCC_SERVICE_ACCOUNT_NAME}

# TODO: This is not the best practice, but for the sake of the demo, we will give the service account owner access.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/owner"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/editor"

# Setup a SOPS service account with appropriate permissions. This is used for encrypting secrets.
gcloud iam service-accounts create ${SOPS_SERVICE_ACCOUNT_NAME}

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/editor"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

gcloud kms keyrings create sops --location global
gcloud kms keys create sops-key --location global --keyring sops --purpose encryption
gcloud kms keys list --location global --keyring sops

# Setup the Management GKE cluster
gcloud container clusters create-auto $CLUSTER_NAME \
    --region $CLUSTER_REGION \
    --project $PROJECT_ID \
    --release-channel rapid

# Setup WLI for FluxCD and KCC
gcloud iam service-accounts add-iam-policy-binding \
 ${SOPS_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[flux-system/kustomize-controller]" \
  --role="roles/iam.workloadIdentityUser"

gcloud iam service-accounts add-iam-policy-binding \
  ${KCC_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[cnrm-system/cnrm-controller-manager]" \
  --role="roles/iam.workloadIdentityUser"

# Add a one-time Github token to the cluster
kubectl create secret generic github-token \
  --namespace=flux-system \
  --from-literal=token=$GITHUB_TOKEN \
  --dry-run=client -oyaml \
  > kubernetes/namespaces/base/flux-system/addons/notifications/github/secret.enc.yaml

sops --encrypt --in-place kubernetes/namespaces/base/flux-system/addons/notifications/github/secret.enc.yaml

# Bootstrap FluxCD
flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --owner="$GITHUB_USER" \
  --repository="$DEFUALT_GITHUB_REPO" \
  --path=kubernetes/clusters/$CLUSTER_NAME \
  --branch="$DEFUALT_GITHUB_BRANCH" \
  --personal=true \
  --private=false

# Create public IP for XLB
gcloud compute addresses create static-mci-ip --global --project $PROJECT_ID
export STATIC_MCI_IP=`gcloud compute addresses describe static-mci-ip --project $PROJECT_ID --global --format="value(address)"`
echo -e "GCLB_IP is $STATIC_MCI_IP"

gcloud compute addresses create team-alpha-tenant-api --global --project $PROJECT_ID
export ALPHA_IP=`gcloud compute addresses describe team-alpha-tenant-api --project $PROJECT_ID --global --format="value(address)"`
echo -e "GCLB_IP is $ALPHA_IP"

gcloud compute addresses create team-bravo-tenant-api --global --project $PROJECT_ID
export BRAVO_IP=`gcloud compute addresses describe team-bravo-tenant-api --project $PROJECT_ID --global --format="value(address)"`
echo -e "GCLB_IP is $BRAVO_IP"


# Create Service Endpoint
cat <<EOF > demo-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "$DEMO_NAME.endpoints.${PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "$DEMO_NAME.endpoints.${PROJECT_ID}.cloud.goog"
  target: "${STATIC_MCI_IP}"
EOF
gcloud endpoints services deploy demo-openapi.yaml --project $PROJECT_ID

cat <<EOF > alpha-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "team-alpha.endpoints.${PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "team-alpha.endpoints.${PROJECT_ID}.cloud.goog"
  target: "${ALPHA_IP}"
EOF

gcloud endpoints services deploy alpha-openapi.yaml --project $PROJECT_ID

cat <<EOF > bravo-openapi.yaml
swagger: "2.0"
info:
  description: "Cloud Endpoints DNS"
  title: "Cloud Endpoints DNS"
  version: "1.0.0"
paths: {}
host: "team-bravo.endpoints.${PROJECT_ID}.cloud.goog"
x-google-endpoints:
- name: "team-bravo.endpoints.${PROJECT_ID}.cloud.goog"
  target: "${BRAVO_IP}"
EOF

gcloud endpoints services deploy bravo-openapi.yaml --project $PROJECT_ID

# Create Certificate
gcloud compute ssl-certificates create whereamicert \
  --project $PROJECT_ID \
  --domains=$DEMO_NAME.endpoints.$PROJECT_ID.cloud.goog \
  --global

gcloud compute ssl-certificates create alpha-tenant-cert \
      --project $PROJECT_ID \
      --domains="team-alpha.endpoints.$PROJECT_ID.cloud.goog" \
      --global

gcloud compute ssl-certificates create bravo-tenant-cert \
      --project $PROJECT_ID \
      --domains="team-bravo.endpoints.$PROJECT_ID.cloud.goog" \
      --global

# Step 3 -> https://cloud.google.com/kubernetes-engine/docs/how-to/multi-cluster-services
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[gke-mcs/gke-mcs-importer]" \
    --role "roles/compute.networkViewer"
