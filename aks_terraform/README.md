# AKS Production Deployment — Terraform

Terraform equivalent of the Bicep deployment described in the handoff document.
Targets the same resource configuration (Azure CNI Overlay, ephemeral OS disks,
maintenance windows, OIDC/workload identity, KV secrets CSI driver).

## File structure

```
.
├── providers.tf              # Provider versions + feature flags
├── backend.tf                # Partial backend config (filled via backend.conf)
├── backend.conf.example      # Template — copy to backend.conf (git-ignored)
├── main.tf                   # Root module: RGs + calls keyvault + aks modules
├── variables.tf              # All input variables with descriptions & defaults
├── outputs.tf                # Post-deploy outputs (cluster name, OIDC URL, etc.)
├── terraform.tfvars.example  # Copy to terraform.tfvars (git-ignored) and fill in
├── .gitignore                # Excludes tfvars, backend.conf, state files
├── modules/
│   ├── keyvault/             # Key Vault + RBAC + secrets (mirrors keyvault.bicep)
│   └── aks/                  # AKS cluster + node pools   (mirrors aks.bicep)
└── scripts/
    └── bootstrap-state.sh    # One-time: creates storage account for remote state
```

## First-time setup

### 1 — Bootstrap remote state (once per environment)

```bash
./scripts/bootstrap-state.sh
```

Copy the printed values into `backend.conf` (from `backend.conf.example`).

### 2 — Prepare credentials

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in subscription_id, deployer_object_id,
# admin_username, ssh_public_key
```

### 3 — Init

```bash
terraform init -backend-config=backend.conf
```

### 4 — Plan

```bash
terraform plan \
  -var="deployer_object_id=$(az ad signed-in-user show --query id -o tsv)"
```

### 5 — Apply

```bash
terraform apply \
  -var="deployer_object_id=$(az ad signed-in-user show --query id -o tsv)"
```

### 6 — Get kubeconfig

```bash
az aks get-credentials \
  --resource-group aks-tf-rainer-rg \
  --name aks-prod-tf-rainer \
  --overwrite-existing

kubectl get nodes -o wide
```

Or use the output:
```bash
terraform output kube_config_command | bash
```

## CI/CD (GitHub Actions / Azure DevOps)

- Set `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` as env vars.
- Set `ARM_USE_OIDC=true` (GitHub OIDC) or supply `ARM_CLIENT_SECRET`.
- Pass `deployer_object_id` as a pipeline secret variable.
- Uncomment `use_oidc = true` in `backend.conf`.

## Key differences from Bicep

| Bicep                          | Terraform                                              |
|-------------------------------|--------------------------------------------------------|
| `targetScope = 'subscription'` | Root module creates RGs directly                       |
| `kv.getSecret()`              | Sensitive variable passed through; also stored in KV  |
| `dependsOn` (explicit)         | `depends_on = [module.keyvault]` in root module        |
| Two `maintenanceConfigurations` | `maintenance_window_auto_upgrade` + `_node_os` blocks  |
| BCP139 / BCP180 compile errors | No equivalent; module boundaries are straightforward   |

## Teardown

```bash
terraform destroy
```

> **Note:** If `purge_protection_enabled = true` (default for production),
> you cannot redeploy with the same Key Vault name until the soft-delete
> retention window expires. Use a unique `key_vault_name` per environment
> or set `kv_purge_protection_enabled = false` in labs.

### Teardown bootstrap (blob storage for tfstate)

Clean teardown order: role assignment first, then container, then storage account, then resource group:

bash

```bash
# 1. Remove the role assignment
az role assignment delete \
  --role "Storage Blob Data Contributor" \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope /subscriptions/<suscriptionID>/resourceGroups/aks-tf-state-rg/providers/Microsoft.Storage/storageAccounts/akstfstate37ec108a

# 2. Delete the blob container
az storage container delete \
  --name tfstate \
  --account-name akstfstate37ec108a \
  --auth-mode login

# 3. Delete the storage account
az storage account delete \
  --name akstfstate37ec108a \
  --resource-group aks-tf-state-rg \
  --yes

# 4. Delete the resource group
az group delete \
  --name aks-tf-state-rg \
  --yes --no-wait
```

Steps 2 and 3 are actually redundant — deleting the resource group in step 4 would take everything with it. But going in order is good practice and avoids any soft-delete or lock surprises on the storage account.

One thing to confirm first — make sure you have no live Terraform state in that container that you still need. If there's a `terraform.tfstate` blob in there worth keeping, pull it down before step 2:

bash

```bash
az storage blob download \
  --container-name tfstate \
  --name terraform.tfstate \
  --file ./terraform.tfstate.backup \
  --account-name akstfstate37ec108a \
  --auth-mode login
```

### LOG

```
terraform init -backend-config=backend.conf
Initializing modules...
- aks in modules/aks
- keyvault in modules/keyvault
Initializing provider plugins found in the configuration...
- Finding hashicorp/azurerm versions matching "~> 4.0"...
- Installing hashicorp/azurerm v4.74.0...
- Installed hashicorp/azurerm v4.74.0 (signed by HashiCorp)

Initializing the backend...

Successfully configured the backend "azurerm"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins found in the state...

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

Errors:

```
│ Warning: Argument is deprecated
│
│   with module.keyvault.azurerm_key_vault.main,
│   on modules/keyvault/main.tf line 11, in resource "azurerm_key_vault" "main":
│   11:   enable_rbac_authorization     = true   # IAM roles instead of legacy access policies
│
│ This property has been renamed to `rbac_authorization_enabled` and will be removed in v5.0 of the provider
╵
╷
│ Error: Unsupported argument
│
│   on modules/aks/main.tf line 34, in resource "azurerm_kubernetes_cluster" "main":
│   34:       max_unavailable = "0"
│
│ An argument named "max_unavailable" is not expected here. <== either max_surge or max_unavailable
╵
╷
│ Error: Unsupported argument
│
│   on modules/aks/main.tf line 67, in resource "azurerm_kubernetes_cluster" "main":
│   67:   automatic_channel_upgrade = "patch"
│
│ An argument named "automatic_channel_upgrade" is not expected here. <== change in provider 4.x
|   => now automatic_upgrade_channel
╵
╷
│ Error: Unsupported argument
│
│   on modules/aks/main.tf line 68, in resource "azurerm_kubernetes_cluster" "main":
│   68:   node_os_channel_upgrade   = "NodeImage"
│
│ An argument named "node_os_channel_upgrade" is not expected here.
|  => node_os_channel_upgrade property has been renamed to node_os_upgrade_channel 
```

Finally it worked:

```
Releasing state lock. This may take a few moments...

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

cluster_fqdn = "aks-prod-tf-rainer-dns-xpz13wjl.hcp.eastus.azmk8s.io"
cluster_name = "aks-prod-tf-rainer"
control_plane_managed_identity_principal_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
kubelet_identity_client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
kubelet_identity_object_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
kubernetes_version = "1.34.7"
kv_name = "kv-aks-prod-tf-ra-001"
kv_resource_id = "/subscriptions/<subscritionID>/resourceGroups/aks-tf-rainer-rg-kv/providers/Microsoft.KeyVault/vaults/kv-aks-prod-tf-ra-001"
kv_uri = "https://kv-aks-prod-tf-ra-001.vault.azure.net/"
node_resource_group = "MC_aks-tf-rainer-rg_aks-prod-tf-rainer_eastus"
oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/<userID>/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/"
resource_group_id = "/subscriptions/<subscritionID>/resourceGroups/aks-tf-rainer-rg"
```

