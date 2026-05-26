#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-state.sh
#
# Creates the Azure Storage Account that holds Terraform remote state.
# Run ONCE before the first `terraform init`.
#
# Usage:
#   chmod +x scripts/bootstrap-state.sh
#   ./scripts/bootstrap-state.sh
#
# The script prints the storage account name at the end — copy it into
# your backend.conf (see backend.conf.example).
# ---------------------------------------------------------------------------

set -euo pipefail
#set -x trace

# ── Configuration — edit these if needed ───────────────────────────────────
STATE_RG="aks-tf-state-rg"
STATE_LOCATION="eastus"
CONTAINER_NAME="tfstate"
# Storage account names must be globally unique, 3-24 chars, lowercase alnum.
# Generate a short, lowercase hex suffix without relying on a pipe that can
# fail under `set -o pipefail`.
STORAGE_ACCOUNT_NAME="akstfstate$(printf '%08x' "$(( (RANDOM << 16) ^ $$ ^ $(date +%s) ))")"

# ── Colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── Prerequisites ───────────────────────────────────────────────────────────
command -v az >/dev/null 2>&1 || { echo "az CLI not found. Install from https://aka.ms/installazurecli"; exit 1; }

info "Checking Azure login status..."
az account show >/dev/null 2>&1 || { echo "Not logged in. Run: az login"; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
info "Subscription: ${SUBSCRIPTION_ID}"

# ── Resource group ──────────────────────────────────────────────────────────
info "Creating resource group: ${STATE_RG}"
az group create \
  --name "${STATE_RG}" \
  --location "${STATE_LOCATION}" \
  --tags "managed-by=terraform" "purpose=tf-state" \
  --output none

# ── Storage account ─────────────────────────────────────────────────────────
info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
az storage account create \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${STATE_RG}" \
  --location "${STATE_LOCATION}" \
  --sku Standard_ZRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --tags "managed-by=terraform" "purpose=tf-state" \
  --output none

# ── Enable versioning for state file protection ─────────────────────────────
info "Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${STATE_RG}" \
  --enable-versioning true \
  --output none

# ── Blob container ──────────────────────────────────────────────────────────
info "Creating blob container: ${CONTAINER_NAME}"
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --auth-mode login \
  --output none

# ── Role assignment — current user gets Storage Blob Data Contributor ───────
CURRENT_USER=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -n "${CURRENT_USER}" ]]; then
  info "Granting Storage Blob Data Contributor to current user..."
  az role assignment create \
    --role "Storage Blob Data Contributor" \
    --assignee "${CURRENT_USER}" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${STATE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}" \
    --output none
else
  warning "Could not determine current user; grant Storage Blob Data Contributor manually."
fi

# ── Output ──────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Bootstrap complete. Copy these values into backend.conf:"
echo "================================================================"
echo ""
echo "resource_group_name  = \"${STATE_RG}\""
echo "storage_account_name = \"${STORAGE_ACCOUNT_NAME}\""
echo "container_name       = \"${CONTAINER_NAME}\""
echo "key                  = \"aks-prod.terraform.tfstate\""
echo ""
echo "Then run:"
echo "  cp backend.conf.example backend.conf"
echo "  # Edit backend.conf with the values above"
echo "  terraform init -backend-config=backend.conf"
echo "================================================================"
