<div align="center">

# Expensy

A full-stack expense tracking application — containerised, GitOps-deployed, and production-hardened on Azure Kubernetes Service.

[![CI Frontend](https://github.com/radoelker/aksforge/actions/workflows/ci-frontend.yml/badge.svg)](https://github.com/radoelker/aksforge/actions/workflows/ci-frontend.yml)
[![CI Backend](https://github.com/radoelker/aksforge/actions/workflows/ci-backend.yml/badge.svg)](https://github.com/radoelker/aksforge/actions/workflows/ci-backend.yml)

**Production** → [frontend.prod.azure.ironlabs.online](https://frontend.prod.azure.ironlabs.online)  
**Staging** → [frontend.staging.20.85.194.20.sslip.io](https://frontend.staging.20.85.194.20.sslip.io)

</div>

---

## Overview

Expensy is a monorepo containing a **Next.js frontend** and an **Express/TypeScript backend**, deployed to Azure Kubernetes Service via a fully automated GitOps pipeline. Every production deployment is a Prometheus-gated canary rollout — no manual promotion required.

---

## Stack

### Application
| Layer | Technology |
|---|---|
| Frontend | Next.js 16, TypeScript, Tailwind CSS v3 |
| Backend | Express, TypeScript, Node.js 20 |
| Database | Azure Cosmos DB (MongoDB API v7.0) |
| Cache | Azure Cache for Redis (Premium, TLS) |
| Runtime | Distroless ARM64 containers (`nodejs20-debian12:nonroot`) |

### Infrastructure
| Concern | Technology |
|---|---|
| Cloud | Azure (eastus) |
| IaC | Bicep |
| Kubernetes | AKS 1.34.7 — ARM64, CNI Overlay, NetworkPolicy enforced |
| Container Registry | Azure Container Registry (Premium) |
| Secrets | Azure Key Vault + External Secrets Operator (Workload Identity) |
| TLS | cert-manager + Let's Encrypt |
| Ingress | NGINX Ingress Controller (single public IP) |

### CI/CD
| Concern | Technology |
|---|---|
| CI | GitHub Actions — lint + unit test on every PR |
| CD | GitHub Actions — build, scan (Trivy), push, deploy |
| GitOps | ArgoCD — App-of-Apps, auto-sync |
| Canary | Argo Rollouts — 20% → 60% → 100% with analysis gates |
| Autoscaling | KEDA HTTP Add-on — concurrency-based, scales to zero on staging |
| Image builds | `docker buildx` multi-arch (`amd64` + `arm64`) |

### Observability
| Concern | Technology |
|---|---|
| Metrics | Prometheus (kube-prometheus-stack) + custom `prom-client` metrics |
| Logs | Loki (single-binary) + Grafana Alloy (DaemonSet) |
| Dashboards | Grafana — application and infrastructure dashboards |
| Alerting | Alertmanager — email via GMX SMTP, rules for error rate, p99 latency, pod restarts |

---

## Repository Structure

```
/
├── expensy_frontend/          # Next.js application
├── expensy_backend/           # Express + TypeScript API
├── aks_bicep/                 # Azure infrastructure (Bicep) — active
├── aks_terraform/             # Azure infrastructure (Terraform) — reference only
├── aks_current/               # AKS state read-out tooling
├── k8s/                       # Kubernetes manifests + Helm values
│   ├── apps/                  # Application manifests (Kustomize overlays)
│   └── infrastructure/        # Helm values + cluster infrastructure manifests
├── scripts/
│   └── bootstrap-cluster.sh   # One-shot cluster bootstrap (Step 2)
└── .github/
    └── workflows/             # GitHub Actions CI/CD pipelines
```

---

## CI/CD Pipeline

```
dev/<name>  ──push──►  CI (lint + test)
dev/<name>  ──PR──►    staging   ← CI runs on PR
staging     ──merge──► CD staging → ArgoCD auto-sync → staging namespace
staging     ──PR──►    main      ← CI runs on PR
main        ──merge──► CD production → ArgoCD → Argo Rollouts canary
```

**Protected branches:** `staging` and `main` require a passing CI run before merge.

**Canary gates** — each production deploy progresses through:

| Step | Traffic | Pause | Gate |
|---|---|---|---|
| 1 | 20% canary | 5 min | error rate < 25% AND p99 < 2s |
| 2 | 60% canary | 5 min | same |
| 3 | 100% | — | full promotion |

Gates query live Prometheus metrics. A failed gate aborts the rollout and returns all traffic to the stable revision automatically.

---

## Branching & Image Tags

| Branch | Tags pushed |
|---|---|
| `staging` | `:<git-sha>` + `:staging-latest` |
| `main` | `:<git-sha>` + `:latest` |

---

## Getting Started

### Prerequisites
- Azure subscription with Owner/Contributor
- `az`, `kubectl`, `helm`, `kubelogin` installed
- Docker with `buildx` for local image builds

### 1 — Provision Azure infrastructure
```bash
cd aks_bicep
# See aks_bicep/README.md for full instructions
az deployment sub create ...
```

### 2 — Bootstrap the AKS cluster
```bash
export SUBSCRIPTION_ID="<subscriptionID>"
chmod +x scripts/bootstrap-cluster.sh
./scripts/bootstrap-cluster.sh
```

### 3 — Apply ExternalSecrets and ArgoCD App-of-Apps
```bash
kubectl apply -f k8s/infrastructure/external-secrets/
kubectl apply -f k8s/infrastructure/argocd/apps-of-apps.yaml
```

After step 3, ArgoCD takes over — all further deployments happen via git push.

---

## Access Cluster Services

```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093

# SonarQube
kubectl port-forward svc/sonarqube-sonarqube -n sonarqube 9000:9000
```

---

## Further Reading

| Document | Description |
|---|---|
| [Application](./APP_README.md) | Frontend and backend app architecture, local development, environment variables |
| [CI/CD Workflows](./.github/workflows/README_WORKFLOWS.md) | All GitHub Actions workflows explained |
| [Kubernetes & Bootstrap](./k8s/k8s-README.md) | `bootstrap-cluster.sh` walkthrough and full `k8s/` directory reference |
| [Azure Bicep IaC](./aks_bicep/README.md) | Bicep modules, resource groups, and deployment instructions |
| [Terraform IaC](./aks_terraform/README.md) | Alternative Terraform setup (reference only) |
| [AKS State Read-out](./aks_current/README.md) | Tools for reading and documenting existing AKS cluster state |
| [Scaling Considerations](./SCALING.md) | KEDA autoscaling config, spot node pool behaviour, scale-to-zero |

---

## Key Operational Notes

- **ACR public access** is temporarily enabled for GitHub-hosted runners. Disable after switching to ARC runners (Step 16): `az acr update --name acr2poiclyh4krxy --public-network-enabled false`
- **Ingresses** must reside in the `keda` namespace — required by KEDA HTTP Add-on 0.14
- **`NEXT_PUBLIC_API_URL`** is baked into the frontend image at build time — it cannot be overridden at runtime
- **Cosmos DB** requires `retryWrites: false` in the Mongoose connection string
- **Multi-arch builds** require `NODE_OPTIONS=--jitless` to prevent QEMU SEGFAULT on ARM64 emulation
