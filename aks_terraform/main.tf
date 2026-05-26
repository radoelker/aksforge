locals {
  kv_resource_group_name = "${var.resource_group_name}-kv"
  # KV names: max 24 chars, globally unique, alphanumeric + hyphens only
  # Result: kv-aks-prod-bicep-001 = 21 chars
  kv_name = "kv-${substr(var.managed_cluster_name, 0, 14)}-${var.kv_suffix}"
}

# ── Resource Groups ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "cluster" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_resource_group" "keyvault" {
  name     = local.kv_resource_group_name
  location = var.location
}

# ── Key Vault Module ───────────────────────────────────────────────────────────
module "keyvault" {
  source = "./modules/keyvault"

  location                = var.location
  resource_group_name     = azurerm_resource_group.keyvault.name
  kv_name                 = local.kv_name
  deployer_object_id      = var.deployer_object_id
  deployer_principal_type = var.deployer_principal_type
  admin_username          = var.admin_username
  ssh_rsa_public_key      = var.ssh_rsa_public_key
}

# ── AKS Module ─────────────────────────────────────────────────────────────────
# depends_on is explicit: ESO Managed Identity RBAC (added in a later step)
# will be assigned against the KV, so AKS must wait for the KV to be ready.
# Secrets are passed directly as variables — no round-trip getSecret() needed
# because the values are already in memory as sensitive TF variables.
module "aks" {
  source = "./modules/aks"

  location             = var.location
  resource_group_name  = azurerm_resource_group.cluster.name
  managed_cluster_name = var.managed_cluster_name
  admin_username       = var.admin_username
  ssh_rsa_public_key   = var.ssh_rsa_public_key

  depends_on = [module.keyvault]
}
