data "azurerm_client_config" "current" {}

# ── Key Vault ─────────────────────────────────────────────────────────────────
resource "azurerm_key_vault" "main" {
  name                = var.kv_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  #enable_rbac_authorization     = true   # IAM roles instead of legacy access policies -  deprecated
  rbac_authorization_enabled   = true   # Starting with version v5.0 of the provider
  soft_delete_retention_days    = 7      # 7 is the minimum; raise to 90 for production
  purge_protection_enabled      = false  # Must stay false in dev/course environments.
                                         # Once set to true it cannot be unset — the vault
                                         # becomes locked for the full retention period and
                                         # blocks redeployment under the same name.
                                         # Set to true only for long-lived production vaults.
  public_network_access_enabled = true   # Lock down to a private endpoint in hardened envs
}

# ── Secrets ───────────────────────────────────────────────────────────────────
# depends_on ensures the role assignment exists before Terraform tries to write
# secrets — without it the first apply often races and fails with 403 Forbidden.
resource "azurerm_key_vault_secret" "admin_username" {
  name         = "aks-admin-username"
  value        = var.admin_username
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer]
}

resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "aks-ssh-public-key"
  value        = var.ssh_rsa_public_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer]
}

# ── RBAC: deployer gets Key Vault Secrets Officer on this vault ───────────────
# Secrets Officer = create/read/update/delete secrets (not keys or certs)
resource "azurerm_role_assignment" "deployer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployer_object_id
  principal_type       = var.deployer_principal_type
}
