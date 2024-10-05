# Atomic Kubernetes Cluster(s) via GitOps

This is an example repository that demonstrates how to use GitOps to create GKE (Google Kubernetes Engine) clusters on demand, register them to a Fleet, and bootstrap them with FluxCD.

Once the newly created Fleet clusters are bootstrapped with FluxCD, they will automatically begin to synchronize all GKE cluster platform configurations and application tenant configurations.

## 📖 Table of contents

- [Atomic Kubernetes Cluster(s) via GitOps](#atomic-kubernetes-clusters-via-gitops)
  - [📖 Table of contents](#-table-of-contents)
  - [📁 Directories](#-directories)
  - [🖥️ Technology Stack](#️-technology-stack)
  - [🛠️ Requirements](#️-requirements)
  - [🚀 Getting Started](#-getting-started)
  - [🧪 Test](#-test)
  - [🔎 Troubleshooting](#-troubleshooting)
    - [Handshake failure](#handshake-failure)
    - [Connection failures](#connection-failures)
  - [📄 License](#-license)

## 📁 Directories

This Git repository contains the following directories.

```bash
📁 apps             # Example of a application operators configuration
📁 hack             # Directory for scripts
📁 kubernetes       # Example of a platform operators configuration
├─📁 clusters       # FluxCD cluster installation
├─📁 namespaces     # Platform tooling and configuration
└─📁 tenants        # Teams onboarded as tenants
```

## 🖥️ Technology Stack

The below showcases the collection of open-source solutions currently implemented in the cluster. Each of these components has been documented, and their deployment is managed using FluxCD, which adheres to GitOps principles.

|                                                                                                                                       | Name                                                                            | Description                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| <img width="32" src="https://raw.githubusercontent.com/cncf/artwork/master/projects/kubernetes/icon/color/kubernetes-icon-color.svg"> | [Kubernetes](https://kubernetes.io/)                                            | An open-source system for automating deployment, scaling, and management of containerized applications                                                           |
| <img width="32" src="https://raw.githubusercontent.com/cncf/artwork/master/projects/flux/icon/color/flux-icon-color.svg">             | [FluxCD](https://fluxcd.io/)                                                    | GitOps tool for deploying applications to Kubernetes                                                                                                             |
| NA                                                                                                                                    | [Config Connector](https://github.com/GoogleCloudPlatform/k8s-config-connector) | Manage GCP GCP resources declaratively using Kubernetes-style configuration                                                                                      |
| NA                                                                                                                                    | [Gateway API](https://gateway-api.sigs.k8s.io/guides/)                          | Kubernetes service networking through expressive, extensible, and role-oriented interfaces that are implemented by many vendors and have broad industry support. |

## 🛠️ Requirements

- Google Cloud Account with permission to create GKE clusters
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) CLI installed and configured
- [gcloud](https://cloud.google.com/sdk/docs/install)  CLI installed and configured
- [flux](https://fluxcd.io/flux/installation/#install-the-flux-cli) CLI tools
- [sops](https://github.com/getsops/sops) CLI installed and configured
- YAML editing skills

## 🚀 Getting Started

Before you begin, check that all GCP project references are updated in the repository to your corrosponding GCP project ID.

Additionally, worth noting that once you have completed the following steps the `GITHUB_TOKEN` will be stored in a SOPS encrypted kubernetes [secret](./kubernetes/namespaces/base/flux-system/addons/notifications/github/secret.enc.yaml).

1. Fork and clone this repository

```bash
git clone https://github.com/<user/org>/k8s-gitops-atomic-clusters.git
```

2. Create a new GCP project

3. Create the following secrets inside your GitHub repository:

```bash
GCP_PROJECT_NUMBER
GCP_PROJECT_ID
FLUX_GITHUB_PAT
```

**Note:** *The project number, project ID, and Flux PAT are used in the GitHub workflows to bootstrap new clusters automatically - You will need to create a GitHub Fine-grained PAT*

4. Navigate to the cloned directory and run the setup script - In the script there will be some variables you **MUST** change to match your desired configuration.

```bash
export GITHUB_TOKEN=<YOUR GITHUB TOKEN>

cd k8s-gitops-atomic-clusters
./hack/bootstrap.sh
```

**Note:** *Change the exported variables to the appropriate values; Additional values can be adapted in the [bootstrap.sh](./hack/bootstrap.sh) script.*

5. Follow the on-screen instructions to set up your GKE cluster

## 🧪 Test

```bash
curl https://team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog
```

Or with canary header:

```bash
curl -H "env: canary" https://team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog
```

## 🔎 Troubleshooting

### Handshake failure

```bash
curl: (35) LibreSSL/3.3.6: error:1404B410:SSL routines:ST_CONNECT:sslv3 alert handshake failure
```

Check that certificate exists and is available:

```bash
gcloud compute ssl-certificates describe alpha-tenant-cert
```

You should see certificate payload and status `ACTIVE`. If the status is `PROVISIONING` like below, you may need to wait a few minutes for certificate to become available

```yaml
kind: compute#sslCertificate
managed:
  domainStatus:
    team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog: PROVISIONING
  domains:
  - team-alpha.endpoints.${GCP_PROJECT_ID}.cloud.goog
  status: PROVISIONING
name: alpha-tenant-cert
type: MANAGED
```

### Connection failures

Check that all resources are synced by Flux in all clusters:

```bash
flux get all -A
```

In `cluster-01` and `cluster-02` check that each `ServiceExport` has corresponding `ServiceImport`, it may take sometime for `ServiceImport` to get created by MCS.

```bash
kubectl get serviceexport -n demo
kubectl get serviceimport -n demo
```

## 📄 License

This repository is [Apache 2.0 licensed](./LICENSE)
