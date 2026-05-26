# Deploy AKS with Key Vault via Bicep

Provisions a production-ready AKS cluster under a dedicated resource group,
with secrets managed in a separate Key Vault resource group. The deployment
spans subscription scope and is split across three Bicep files.

---

## File Structure

```
.
├── main.bicep          # Entry point — subscription scope orchestrator
├── keyvault.bicep      # Key Vault + secrets + RBAC (resource group scope)
└── aks.bicep           # AKS cluster, agent pool, and maintenance windows (resource group scope)
```

---

## File Purposes

### `main.bicep`
Runs at `targetScope = 'subscription'`. Responsible for:
- Creating two resource groups (`aks-bicep-rainer-rg` and `aks-bicep-rainer-rg-kv`)
- Calling `keyvault.bicep` as a module scoped to the KV resource group
- Calling `aks.bicep` as a module scoped to the AKS resource group
- Passing secrets from Key Vault into AKS via `kv.getSecret()`
- Surfacing all deployment outputs

### `keyvault.bicep`
Runs at resource group scope. Responsible for:
- Creating the Key Vault with soft-delete (9 days), purge protection, and RBAC authorisation
- Storing two secrets: `aks-admin-username` and `aks-ssh-public-key`
- Assigning the deployer the **Key Vault Secrets Officer** role so secrets can be written and read during deployment

### `aks.bicep`
Runs at resource group scope. Responsible for:
- Creating the managed cluster (`SystemAssigned` identity, free tier, Kubernetes 1.34)
- Network profile: Azure CNI overlay, pod CIDR `10.244.0.0/16`, service CIDR `10.0.0.0/16`
- Agent pool: 2–5 nodes, `Standard_D4pds_v5`, ephemeral OS disk, availability zones 1–2–3, autoscaler enabled
- Auto-upgrade maintenance window: weekly Sunday, 8 h, patch channel
- Node OS upgrade maintenance window: weekly Sunday, 8 h, NodeImage channel
- Security: OIDC issuer, workload identity, image cleaner enabled

---

## Information Flow

```
main.bicep  (subscription)
│
│  @secure() params entered at CLI prompt
│  ┌─────────────────────────────────────┐
│  │ adminUsername, sshRSAPublicKey      │
│  └──────────────┬──────────────────────┘
│                 │
├── kvModule ─────▼──────────────────────────────────────────────────────┐
│   keyvault.bicep                                                        │
│   Creates Key Vault → stores secrets → assigns Secrets Officer to       │
│   deployerObjectId                                                      │
└── aksModule ───────────────────────────────────────────────────────────┘
    aks.bicep
    Receives secrets via kv.getSecret() — values never appear in logs
    Creates cluster → agent pool → maintenance windows
```

> `kv.getSecret()` is the only mechanism that passes a Key Vault secret
> directly into a module parameter without exposing it in the deployment
> history. It requires the target parameter to carry `@secure()`.

---

## Parameters

| Parameter | Where set | Description |
|---|---|---|
| `location` | default `eastus` | Azure region for all resources |
| `resourceGroupName` | default `aks-bicep-rainer-rg` | AKS resource group name |
| `managedCluserName` | default `aks-prod-bicep-rainer` | AKS cluster name |
| `deployerObjectId` | CLI / pipeline | Object ID of the deploying user or SP |
| `deployerPrincipalType` | default `User` | `User` locally, `ServicePrincipal` in pipelines |
| `adminUsername` | prompted (secure) | Linux admin user on cluster nodes |
| `sshRSAPublicKey` | prompted (secure) | SSH public key for node access |

---

## Prerequisites

```bash
# Install or update Bicep
az bicep install && az bicep upgrade

# Log in and set the target subscription
az login
az account set --subscription <subscription-id>

# Retrieve your object ID (needed for Key Vault RBAC)
az ad signed-in-user show --query id -o tsv
```

---

## Deploy

```bash
# Local developer (principalType defaults to 'User')
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters deployerObjectId=$(az ad signed-in-user show --query id -o tsv) \
               adminUsername='azureuser' \
               sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)"

# CI/CD pipeline (service principal)
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters deployerObjectId=$SP_OBJECT_ID \
               deployerPrincipalType='ServicePrincipal' \
               adminUsername='azureuser' \
               sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

Validate without deploying:
```bash
az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters deployerObjectId=<oid> adminUsername='azureuser' \
               sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

---

## Outputs

The following values are emitted by `main.bicep` at the end of a successful deployment.

| Output | Description |
|---|---|
| `kvName` | Key Vault name |
| `kvUri` | Key Vault URI (`https://<name>.vault.azure.net/`) |
| `clusterFqdn` | API server DNS — use in kubeconfig and pipelines |
| `oidcIssuerUrl` | OIDC issuer URL — required for workload identity federation |
| `nodeResourceGroup` | Auto-created `MC_` resource group containing nodes and load balancer |
| `controlPlaneManagedIdentityPrincipalId` | Principal ID for RBAC assignments (e.g. AcrPull) |
| `resourceGroupId` | Full resource ID of the AKS resource group |

### Query outputs after deployment

```bash
# Show all outputs from the last deployment
az deployment sub show \
  --name main \
  --query properties.outputs \
  -o table
```

### Additional post-deploy queries

The load balancer public IP and node VMs are created inside the `MC_` resource
group after the cluster is running — they are not available as deployment outputs.

```bash
# Outbound public IP (egress)
az network public-ip list \
  --resource-group MC_aks-bicep-rainer-rg_aks-prod-bicep-rainer_eastus \
  --query "[].{name:name, ip:ipAddress}" \
  -o table

# Merge kubeconfig and verify cluster access
az aks get-credentials \
  --resource-group aks-bicep-rainer-rg \
  --name aks-prod-bicep-rainer

kubectl get nodes -o wide

# Confirm OIDC issuer (required before creating federated credentials)
az aks show \
  --resource-group aks-bicep-rainer-rg \
  --name aks-prod-bicep-rainer \
  --query oidcIssuerProfile.issuerUrl \
  -o tsv
```

---

## Tear Down

```bash
# Remove AKS resource group (MC_ group is deleted automatically)
az group delete --name aks-bicep-rainer-rg --yes

# Key Vault resource group — note: purge protection means the vault
# enters a soft-deleted state and cannot be permanently removed
# until the retention window (9 days) expires.
az group delete --name aks-bicep-rainer-rg-kv --yes

# Purge the vault immediately if retention window is not yet elapsed
# (only possible if enablePurgeProtection was set to false)
az keyvault purge --name kv-aks-prod-bicep-r-prod --location eastus
```
