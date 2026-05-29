# Kubernetes Infrastructure

This directory contains all Kubernetes manifests and Helm values for the Expensy platform running on AKS. Infrastructure components are installed via [`scripts/bootstrap-cluster.sh`](../scripts/bootstrap-cluster.sh). Application manifests are managed by ArgoCD.

---

## Bootstrap Script

### Prerequisites

- `az` CLI logged in with Owner/Contributor on the subscription
- `kubectl`, `helm`, and `kubelogin` installed
- Bicep IaC (Step 1) already applied — AKS cluster, ACR, Key Vault, Cosmos DB, and Redis must exist

### Usage

```bash
chmod +x scripts/bootstrap-cluster.sh
export SUBSCRIPTION_ID="daf9c53c-7096-4293-9bb1-f7ad8263db1a"
./scripts/bootstrap-cluster.sh
```

The script runs idempotently (`helm upgrade --install`, `kubectl apply`). It is safe to re-run after failures. Before running the ARC section, populate `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`, and `GITHUB_CONFIG_URL` at the top of the script.

### What the script does (in order)

| Step | Action |
|------|--------|
| 1 | Fetches AKS credentials and converts kubeconfig for Workload Identity via `kubelogin` |
| 2 | Resolves the cluster OIDC issuer URL for federated credential bindings |
| 3 | Applies namespaces (`staging`, `production`, `argocd`, etc.) and creates ARC namespaces |
| 4 | Applies NetworkPolicies (default-deny, same-namespace, ingress-controller, monitoring-scrape) |
| 5 | Adds all required Helm repositories and runs `helm repo update` |
| 6 | Creates the `mi-eso-keyvault` managed identity, assigns Key Vault Secrets User role, installs ESO, creates FederatedIdentityCredential, applies ClusterSecretStore |
| 7 | Installs cert-manager and applies Let's Encrypt ClusterIssuers (staging + prod) |
| 8 | Installs NGINX Ingress Controller and prints the assigned public IP |
| 9 | Installs KEDA |
| 10 | Installs KEDA HTTP Add-on |
| 11 | Installs ArgoCD and stores the initial admin password in Key Vault |
| 12 | Installs Argo Rollouts |
| 13 | Installs kube-prometheus-stack — fetches or prompts for Grafana admin password |
| 14 | Installs Loki (single-binary) and Grafana Alloy (DaemonSet) |
| 15 | Installs ARC controller + runner scale set (skipped if GitHub App secret is absent) |
| 16 | Installs SonarQube — fetches or prompts for admin password and monitoring passcode |

> After the script completes, apply ExternalSecrets manually:
> ```bash
> kubectl apply -f k8s/infrastructure/external-secrets/
> ```
> Then apply the ArgoCD App-of-Apps to hand off application deployment to GitOps:
> ```bash
> kubectl apply -f k8s/infrastructure/argocd/apps-of-apps.yaml
> ```

---

## Directory Structure

```
k8s/
├── apps/
│   ├── backend/
│   │   ├── base/
│   │   ├── production/
│   │   └── staging/
│   └── frontend/
│       ├── base/
│       ├── production/
│       └── staging/
└── infrastructure/
    ├── alloy/
    ├── arc/
    ├── argo-rollouts/
    ├── argocd/
    │   └── apps/
    ├── cert-manager/
    ├── external-secrets/
    ├── keda/
    ├── keda-http-addon/
    ├── kube-prometheus-stack/
    ├── loki/
    ├── monitoring/
    ├── namespaces/
    ├── network-policies/
    ├── nginx-ingress/
    └── sonarqube/
```

---

## `apps/`

Application manifests managed by ArgoCD. Each app follows a base/overlay Kustomize pattern.

### `apps/backend/base/`
Shared backend resources: `Service` (port 8706) and `PodDisruptionBudget`. Referenced by both staging and production overlays.

### `apps/backend/staging/`
Staging overlay: `Deployment`, `Kustomization` (image tag), `Ingress` (sslip.io, letsencrypt-staging), `InterceptorRoute`, and `ScaledObject` (KEDA, min 1 / max 5 replicas). Synced from the `staging` branch.

### `apps/backend/production/`
Production overlay: `Rollout` (Argo Rollouts canary, 20/60/100%), `service-canary`, `AnalysisTemplate` (Prometheus-gated error rate + p99 latency), `Ingress` (ironlabs.online, letsencrypt-prod), `InterceptorRoute`, and `ScaledObject` (min 2 / max 20 replicas). Synced from `main`.

### `apps/frontend/base/`
Shared frontend resources: `Service` (port 3000) and `PodDisruptionBudget`.

### `apps/frontend/staging/`
Staging overlay: `Deployment`, `Kustomization`, `Ingress`, `InterceptorRoute`, and `ScaledObject`. `NEXT_PUBLIC_API_URL` baked into the image at build time pointing to the staging backend.

### `apps/frontend/production/`
Production overlay: `Rollout` (canary), `service-canary`, `Ingress`, `InterceptorRoute`, and `ScaledObject`. `NEXT_PUBLIC_API_URL` points to the production backend domain.

---

## `infrastructure/`

Helm values and manifests for all cluster infrastructure. Applied by `bootstrap-cluster.sh` or manually.

### `infrastructure/namespaces/`
Declares all application and infrastructure namespaces: `staging`, `production`, `argocd`, `monitoring`, `keda`, `cert-manager`, `ingress-nginx`, `external-secrets`, `argo-rollouts`, `sonarqube`.

### `infrastructure/network-policies/`
Enforced by Azure CNI network policy. Five policies: default-deny all ingress in `staging`/`production`; allow intra-namespace; allow NGINX ingress controller; allow monitoring scrape (ports 3000, 8706, 8080, 9090); allow KEDA interceptor; allow Argo Rollouts → Prometheus.

### `infrastructure/external-secrets/`
`ClusterSecretStore` (Workload Identity → Key Vault) and `ExternalSecret` manifests for `cosmos-secret` and `redis-secret` in both `staging` and `production`. Applied manually — not managed by ArgoCD.

### `infrastructure/cert-manager/`
Helm values and `ClusterIssuer` manifests for Let's Encrypt staging and production ACME issuers. TLS certificates are provisioned automatically for all `Ingress` resources.

### `infrastructure/nginx-ingress/`
Helm values for the NGINX Ingress Controller. Exposes a single public IP (`20.85.194.20`) for all ingress traffic across staging and production.

### `infrastructure/keda/`
Helm values for KEDA core. Configured to run on the spot node pool.

### `infrastructure/keda-http-addon/`
Helm values for KEDA HTTP Add-on (v0.14). Provides `InterceptorRoute` + `ScaledObject` HTTP-based autoscaling. All `Ingress` resources must reside in the `keda` namespace for traffic interception to work.

### `infrastructure/argocd/`
Helm values for ArgoCD. Contains `apps-of-apps.yaml` (the root Application) and `apps/` (one Application manifest per service/environment). ArgoCD auto-syncs staging from the `staging` branch and production from `main`.

### `infrastructure/argo-rollouts/`
Helm values for Argo Rollouts. Enables canary deployments with Prometheus-gated `AnalysisTemplate` steps for production.

### `infrastructure/kube-prometheus-stack/`
Helm values for Prometheus, Grafana, and Alertmanager. Prometheus scrapes all namespaces. Alertmanager sends email via GMX SMTP with the password sourced from Key Vault via `smtp_auth_password_file`.

### `infrastructure/loki/`
Helm values for Loki (single-binary mode, filesystem storage, 20Gi PVC). Exposed via gateway for Alloy log push and Grafana datasource queries.

### `infrastructure/alloy/`
Helm values and `alloy-config.yaml` ConfigMap for Grafana Alloy. Runs as a DaemonSet on all nodes including spot. Scrapes pod logs from all namespaces and ships to the Loki gateway.

### `infrastructure/monitoring/`
Post-install wiring: `ServiceMonitor` resources for backend and frontend (Prometheus scraping), Grafana dashboard ConfigMaps (application and infrastructure dashboards), and additional NetworkPolicy for Argo Rollouts → Prometheus access.

### `infrastructure/arc/`
Helm values for Actions Runner Controller (ARC) and the runner scale set. Runners are scheduled on the spot node pool. Requires a GitHub App secret (`arc-github-app-secret`) in `arc-runners` before install.

### `infrastructure/sonarqube/`
Helm values for SonarQube. Admin password and monitoring passcode sourced from Key Vault at install time. CI integration stubbed in workflows — enabled in Step 12.
