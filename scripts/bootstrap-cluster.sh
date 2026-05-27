#!/usr/bin/env bash
# =============================================================================
# bootstrap-cluster.sh — Step 2: AKS Cluster Bootstrap
# =============================================================================
# Installs all cluster infrastructure in the order defined in the handoff doc.
# Run this from the repo root after Step 1 IaC is complete.
#
# Prerequisites:
#   - az CLI logged in with Owner/Contributor on the subscription
#   - kubectl, helm, kubelogin installed
#   - helm repos added (this script adds them)
#   - Current directory: repo root
#
# Usage:
#   chmod +x scripts/bootstrap-cluster.sh
#   export SUBSCRIPTION_ID="subscriptionID"
#   ./scripts/bootstrap-cluster.sh
#
# Helm uses server-side apply (default since Helm 3.13+).
# AKS runs a controller called admissionsenforcer that automatically injects 
# namespaceSelector fields into every ValidatingWebhookConfiguration on the cluster.
# --force-conflicts tells the server-side apply engine "if another field manager owns a field I take ownership from it"
# This affects: cert-manager, KEDA, ArgoCD, Argo Rollouts, kube-prometheus-stack
#
# The components that don't register webhook configs are external-secrets (uses CRD validation only)
# and loki, alloy, ingress-nginx, sonarqube, and arc. 

# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Configuration — update these if your deployment suffix or names differ
# ---------------------------------------------------------------------------
RESOURCE_GROUP="aks-bicep-rainer-rg"
CLUSTER_NAME="aks-prod-bicep-rainer"
KV_RESOURCE_GROUP="aks-bicep-rainer-rg-kv"
KV_NAME="kv-aks-prod-bicep-003"
LOCATION="eastus"

# Managed identity to create for ESO (dedicated, separate from kubelet identity)
ESO_MI_NAME="mi-eso-keyvault"
ESO_MI_RG="${RESOURCE_GROUP}"

# GitHub ARC (fill in before running ARC section)
GITHUB_CONFIG_URL="https://github.com/YOUR_ORG/YOUR_REPO"
GITHUB_APP_ID=""
GITHUB_APP_INSTALLATION_ID=""
# GitHub App private key path (downloaded from GitHub App settings)
GITHUB_APP_PRIVATE_KEY_PATH="${HOME}/.secrets/github-app-private-key.pem"

# ---------------------------------------------------------------------------
# 1. Resolve kubeconfig
# ---------------------------------------------------------------------------
echo "==> [1/15] Getting AKS credentials..."
az account set --subscription "${SUBSCRIPTION_ID}"
az aks get-credentials \
  --name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --overwrite-existing

# Convert to workload-identity-compatible kubeconfig
kubelogin convert-kubeconfig -l azurecli

echo "Cluster nodes:"
kubectl get nodes -o wide

# ---------------------------------------------------------------------------
# 2. Fetch cluster details needed downstream
# ---------------------------------------------------------------------------
echo "==> [2/15] Fetching cluster identity details..."

OIDC_ISSUER=$(az aks show \
  --name "${CLUSTER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)
echo "  OIDC issuer: ${OIDC_ISSUER}"

# ---------------------------------------------------------------------------
# 3. Namespaces
# ---------------------------------------------------------------------------
echo "==> [3/15] Applying namespaces..."
kubectl apply -f k8s/infrastructure/namespaces/namespaces.yaml

# ARC namespaces (not in the main namespaces.yaml — ARC manages its own)
kubectl create namespace arc-systems  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace arc-runners  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# 4. NetworkPolicies
# ---------------------------------------------------------------------------
echo "==> [4/15] Applying NetworkPolicies..."
kubectl apply -f k8s/infrastructure/network-policies/01-default-deny.yaml
kubectl apply -f k8s/infrastructure/network-policies/02-allow-same-namespace.yaml
kubectl apply -f k8s/infrastructure/network-policies/03-allow-ingress-controller.yaml
kubectl apply -f k8s/infrastructure/network-policies/04-allow-monitoring-scrape.yaml

# ---------------------------------------------------------------------------
# 5. Add Helm repositories
# ---------------------------------------------------------------------------
echo "==> [5/15] Adding Helm repositories..."
helm repo add external-secrets  https://charts.external-secrets.io
helm repo add jetstack           https://charts.jetstack.io
helm repo add ingress-nginx      https://kubernetes.github.io/ingress-nginx
helm repo add kedacore           https://kedacore.github.io/charts
helm repo add argo               https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana            https://grafana.github.io/helm-charts
helm repo add sonarqube          https://SonarSource.github.io/helm-chart-sonarqube
helm repo update
echo "  Helm repos updated."

# ---------------------------------------------------------------------------
# 6. External Secrets Operator — create dedicated MI, federate, install ESO
# ---------------------------------------------------------------------------
echo "==> [6/15] Setting up ESO Workload Identity..."

# 6a. Create a dedicated user-assigned managed identity for ESO.
#     Separate from the kubelet identity — follows least-privilege principle.
echo "  Creating ESO managed identity: ${ESO_MI_NAME}..."
az identity create \
  --name "${ESO_MI_NAME}" \
  --resource-group "${ESO_MI_RG}" \
  --location "${LOCATION}" \
  --output none

ESO_MI_CLIENT_ID=$(az identity show \
  --name "${ESO_MI_NAME}" \
  --resource-group "${ESO_MI_RG}" \
  --query "clientId" -o tsv)

ESO_MI_PRINCIPAL_ID=$(az identity show \
  --name "${ESO_MI_NAME}" \
  --resource-group "${ESO_MI_RG}" \
  --query "principalId" -o tsv)

ESO_MI_RESOURCE_ID=$(az identity show \
  --name "${ESO_MI_NAME}" \
  --resource-group "${ESO_MI_RG}" \
  --query "id" -o tsv)

echo "  ESO MI client ID: ${ESO_MI_CLIENT_ID}"

# 6b. Assign Key Vault Secrets User role to the ESO MI.
#     (Secrets User = read-only; sufficient for ESO sync.)
KV_RESOURCE_ID=$(az keyvault show \
  --name "${KV_NAME}" \
  --resource-group "${KV_RESOURCE_GROUP}" \
  --query "id" -o tsv)

az role assignment create \
  --assignee-object-id "${ESO_MI_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope "${KV_RESOURCE_ID}" \
  --output none
echo "  Key Vault Secrets User role assigned to ESO MI."

# 6c. Install ESO Helm chart (before creating the FederatedCredential so the
#     ServiceAccount exists in the cluster for the federation binding).
echo "  Installing External Secrets Operator..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 2.5.0 \
  --values k8s/infrastructure/external-secrets/values.yaml \
  --set "serviceAccount.annotations.azure\.workload\.identity/client-id=${ESO_MI_CLIENT_ID}" \
  --wait --timeout 10m

# 6d. Create the FederatedIdentityCredential.
#     Binds the cluster's OIDC issuer + the ESO ServiceAccount to the ESO MI.
echo "  Creating FederatedIdentityCredential for ESO ServiceAccount..."
az identity federated-credential create \
  --name "eso-federated-cred" \
  --identity-name "${ESO_MI_NAME}" \
  --resource-group "${ESO_MI_RG}" \
  --issuer "${OIDC_ISSUER}" \
  --subject "system:serviceaccount:external-secrets:external-secrets-sa" \
  --audience api://AzureADTokenExchange \
  --output none
echo "  FederatedIdentityCredential created."

# 6e. Apply ClusterSecretStore.
echo "  Applying ClusterSecretStore..."
kubectl apply -f k8s/infrastructure/external-secrets/cluster-secret-store.yaml

# Give ESO a moment to reconcile and verify the store is Ready.
echo "  Waiting for ClusterSecretStore to become Ready (up to 60s)..."
kubectl wait clustersecretstore azure-kv-cluster-store \
  --for=condition=Ready --timeout=60s || \
  echo "  WARNING: ClusterSecretStore not Ready yet — check ESO logs."

# ---------------------------------------------------------------------------
# 7. cert-manager
# ---------------------------------------------------------------------------
echo "==> [7/15] Installing cert-manager..."
# conflics on ValidatingWebhookConfiguration/cert-manager-webhook
#kubectl delete validatingwebhookconfiguration cert-manager-webhook \
#  --ignore-not-found=true

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.2 \
  --values k8s/infrastructure/cert-manager/values.yaml \
  --wait --timeout 5m \
  --force-conflicts

#verifying 
#echo "  Waiting for cert-manager-webhook deployment to be ready..."
#kubectl rollout status deployment/cert-manager-webhook \
#  -n cert-manager \
#  --timeout=240s

# Apply ClusterIssuers once cert-manager webhook is ready.
echo "  Applying ClusterIssuers (Let's Encrypt prod + staging)..."
kubectl apply -f k8s/infrastructure/cert-manager/cluster-issuer.yaml

# ---------------------------------------------------------------------------
# 8. NGINX Ingress Controller
# ---------------------------------------------------------------------------
echo "==> [8/15] Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.15.1 \
  --values k8s/infrastructure/nginx-ingress/values.yaml \
  --wait --timeout 5m

# Print the assigned public IP — needed for DNS A-record in Step 6.
echo ""
echo "  *** NGINX public IP (create DNS A-record for this in Step 6) ***"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' && echo ""

# ---------------------------------------------------------------------------
# 9. KEDA
# ---------------------------------------------------------------------------
echo "==> [9/15] Installing KEDA..."
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --version 2.19.0 \
  --values k8s/infrastructure/keda/values.yaml \
  --wait --timeout 5m \
  --force-conflicts

# ---------------------------------------------------------------------------
# 10. KEDA HTTP Add-on
# ---------------------------------------------------------------------------
echo "==> [10/15] Installing KEDA HTTP Add-on..."
helm upgrade --install keda-add-ons-http kedacore/keda-add-ons-http \
  --namespace keda \
  --version 0.14.1 \
  --values k8s/infrastructure/keda-http-addon/values.yaml \
  --wait --timeout 5m \
  --force-conflicts

# ---------------------------------------------------------------------------
# 11. ArgoCD
# ---------------------------------------------------------------------------
echo "==> [11/15] Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 9.5.15 \
  --values k8s/infrastructure/argocd/values.yaml \
  --wait --timeout 10m \
  --force-conflicts

#echo "  ArgoCD initial admin password:"
#kubectl -n argocd get secret argocd-initial-admin-secret \
#  -o jsonpath='{.data.password}' | base64 -d && echo ""
#echo "  (Store this in Key Vault manually: az keyvault secret set ...)"

ARGOCD_INITIAL_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d)

az keyvault secret set \
  --name "argocd-admin-password" \
  --vault-name "${KV_NAME}" \
  --value "${ARGOCD_INITIAL_PASS}" \
  --output none

echo "  ArgoCD initial admin password stored in Key Vault as 'argocd-admin-password'."

# ---------------------------------------------------------------------------
# 12. Argo Rollouts
# ---------------------------------------------------------------------------
echo "==> [12/15] Installing Argo Rollouts..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
  --namespace argo-rollouts \
  --create-namespace \
  --version 2.40.9 \
  --values k8s/infrastructure/argo-rollouts/values.yaml \
  --wait --timeout 5m \
  --force-conflicts

# ---------------------------------------------------------------------------
# 13. kube-prometheus-stack
# ---------------------------------------------------------------------------
echo "==> [13/15] Installing kube-prometheus-stack..."
# Fetch Grafana admin password from Key Vault if available, else prompt.
GRAFANA_ADMIN_PASS=$(az keyvault secret show \
  --name "grafana-admin-password" \
  --vault-name "${KV_NAME}" \
  --query "value" -o tsv 2>/dev/null || true)

if [[ -z "${GRAFANA_ADMIN_PASS}" ]]; then
  echo "  grafana-admin-password not found in Key Vault."
  read -r -s -p "  Enter Grafana admin password: " GRAFANA_ADMIN_PASS
  echo ""
  # Store for next time.
  az keyvault secret set \
    --name "grafana-admin-password" \
    --vault-name "${KV_NAME}" \
    --value "${GRAFANA_ADMIN_PASS}" \
    --output none
fi

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 85.3.3 \
  --values k8s/infrastructure/kube-prometheus-stack/values.yaml \
  --set "grafana.adminPassword=${GRAFANA_ADMIN_PASS}" \
  --wait --timeout 10m \
  --force-conflicts

# ---------------------------------------------------------------------------
# 14. Loki
# ---------------------------------------------------------------------------
echo "==> [14/15a] Installing Loki..."
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --version 7.0.0 \
  --values k8s/infrastructure/loki/values.yaml \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
# 15. Alloy
# ---------------------------------------------------------------------------
echo "==> [14/15b] Installing Grafana Alloy..."
# Apply ConfigMap first so the DaemonSet finds it on startup.
kubectl apply -f k8s/infrastructure/alloy/alloy-config.yaml

helm upgrade --install alloy grafana/alloy \
  --namespace monitoring \
  --version 1.8.2 \
  --values k8s/infrastructure/alloy/values.yaml \
  --wait --timeout 5m

# ---------------------------------------------------------------------------
# 15c. Actions Runner Controller
# ---------------------------------------------------------------------------
echo "==> [15c] Installing Actions Runner Controller (ARC)..."

# Install ARC controller.
# on artefacthub.io the latest version actions-runner-controller/actions-runner-controller is 0.23.7 (27 Nov, 2023)
helm upgrade --install arc \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --namespace arc-systems \
  --version 0.14.2 \
  --values k8s/infrastructure/arc/controller-values.yaml \
  --wait --timeout 5m

# Create the GitHub App secret in arc-runners namespace.
# Read private key from local file (generated when you created the GitHub App).
if [[ -f "${GITHUB_APP_PRIVATE_KEY_PATH}" ]]; then
  kubectl create secret generic arc-github-app-secret \
    --namespace arc-runners \
    --from-literal="github_app_id=${GITHUB_APP_ID}" \
    --from-literal="github_app_installation_id=${GITHUB_APP_INSTALLATION_ID}" \
    --from-file="github_app_private_key=${GITHUB_APP_PRIVATE_KEY_PATH}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "  ARC GitHub App secret created."
else
  echo "  WARNING: ${GITHUB_APP_PRIVATE_KEY_PATH} not found — skip ARC runner install."
  echo "  Create the secret manually, then run the runner scale set install."
fi

# Install runner scale set (only if GitHub App secret exists).
if kubectl get secret arc-github-app-secret -n arc-runners &>/dev/null; then
  helm upgrade --install arc-runner-set \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
    --namespace arc-runners \
    --version 0.23.7 \
    --values k8s/infrastructure/arc/runner-scale-set-values.yaml \
    --set "githubConfigUrl=${GITHUB_CONFIG_URL}" \
    --wait --timeout 5m
fi

# ---------------------------------------------------------------------------
# 15d. SonarQube
# ---------------------------------------------------------------------------
echo "==> [15d] Installing SonarQube..."
SONAR_ADMIN_PASS=$(az keyvault secret show \
  --name "sonarqube-admin-password" \
  --vault-name "${KV_NAME}" \
  --query "value" -o tsv 2>/dev/null || true)

if [[ -z "${SONAR_ADMIN_PASS}" ]]; then
  echo "  sonarqube-admin-password not found in Key Vault."
  read -r -s -p "  Enter SonarQube admin password: " SONAR_ADMIN_PASS
  echo ""
  az keyvault secret set \
    --name "sonarqube-admin-password" \
    --vault-name "${KV_NAME}" \
    --value "${SONAR_ADMIN_PASS}" \
    --output none
fi
  
SONAR_MONITORING_PASSCODE=$(az keyvault secret show \
  --name "sonarqube-monitoring-passcode" \
  --vault-name "${KV_NAME}" \
  --query "value" -o tsv 2>/dev/null || true)

if [[ -z "${SONAR_MONITORING_PASSCODE}" ]]; then
  read -r -s -p "  Enter SonarQube monitoring passcode: " SONAR_MONITORING_PASSCODE
  echo ""
  az keyvault secret set \
    --name "sonarqube-monitoring-passcode" \
    --vault-name "${KV_NAME}" \
    --value "${SONAR_MONITORING_PASSCODE}" \
    --output none
fi

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube \
  --version 2026.3.0 \
  --values k8s/infrastructure/sonarqube/values.yaml \
  --set "account.adminPassword=${SONAR_ADMIN_PASS}" \
  --set "monitoringPasscode=${SONAR_MONITORING_PASSCODE}" \
  --wait --timeout 15m

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "  Bootstrap complete. Summary:"
echo "======================================================================"
echo ""
echo "  Namespaces:          $(kubectl get ns -o name | wc -l) total"
echo "  Nodes:"
kubectl get nodes --no-headers | awk '{print "    "$1, $2, $5}'
echo ""
echo "  NGINX public IP (for DNS A-record in Step 6):"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='  {.status.loadBalancer.ingress[0].ip}' 2>/dev/null && echo ""
echo ""
echo "  ArgoCD:    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Grafana:   kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
echo "  SonarQube: kubectl port-forward svc/sonarqube-sonarqube -n sonarqube 9000:9000"
echo ""
echo "  Next step → Step 3: wire ExternalSecrets for cosmos-secret and redis-secret."
echo "======================================================================"
