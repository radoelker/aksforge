# ---------------------------------------------------------------------------
# Remote state backend — partial configuration.
#
# The storage account is created ONCE by scripts/bootstrap-state.sh before
# the first `terraform init`.  Supply the actual values via:
#
#   terraform init -backend-config=backend.conf
#
# or via environment variables:
#   ARM_RESOURCE_GROUP_NAME, ARM_STORAGE_ACCOUNT_NAME, ARM_CONTAINER_NAME, ARM_KEY
#
# For CI/CD (GitHub Actions / Azure DevOps) use use_oidc = true and set
# ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID as env vars.
# ---------------------------------------------------------------------------
terraform {
  backend "azurerm" {}
}
