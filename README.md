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

2. Navigate to the cloned directory and run the setup script

```bash
export PROJECT_ID=<YOUR PROJECT ID>
export GITHUB_TOKEN=<YOUR GITHUB TOKEN>
export GITHUB_USER=<YOUR GITHUB USER>

cd k8s-gitops-atomic-clusters
./hack/bootstrap.sh
```

**Note:** *Change the exported variables to the appropriate values; Additional values can be adapted in the [bootstrap.sh](./hack/bootstrap.sh) script.*

3. Follow the on-screen instructions to set up your GKE cluster

## 📄 License

This repository is [Apache 2.0 licensed](./LICENSE)
