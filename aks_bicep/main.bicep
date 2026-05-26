targetScope = 'subscription'

param location string = 'eastus'
param resourceGroupName string = 'aks-bicep-rainer-rg'
param managedCluserName string = 'aks-prod-bicep-rainer'
param deployerObjectId string      // az ad signed-in-user show --query id -o tsv
param deployerPrincipalType string = 'User'

@secure()
param adminUsername string         // prompted at deploy time — no default

@secure()
param sshRSAPublicKey string       // prompted at deploy time — no default

@description('Increment (002, 003 …) if a soft-deleted vault with the same name blocks reuse. enablePurgeProtection prevents purging before the retention window expires, so a name change is the only immediate workaround.')
param kvSuffix string = '001'

// Key Vault names: max 24 chars, globally unique, alphanumeric + hyphens only
// Result: kv-aks-prod-bicep-001 = 21 chars
var kvName = 'kv-${take(managedCluserName, 14)}-${kvSuffix}'
var kvResourceGroupName = '${resourceGroupName}-kv'


// ─── Resource Groups ──────────────────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

resource rgKv 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: kvResourceGroupName
  location: location
}

// ─── Key Vault Module ─────────────────────────────────────────────────────────
module kvModule 'keyvault.bicep' = {
  name: 'kvDeployment'
  scope: rgKv
  params: {
    location: location
    kvName: kvName
    deployerObjectId: deployerObjectId
    deployerPrincipalType: deployerPrincipalType
    adminUsername: adminUsername
    sshRSAPublicKey: sshRSAPublicKey
  }
}

// ─── AKS Module ───────────────────────────────────────────────────────────────
// Why no getSecret() here:
// getSecret() is for reading from a KV that PRE-EXISTS before this deployment.
// ARM resolves existing-resource references at planning time — before any module
// runs — so kv.getSecret() on a KV created in the same deployment always fails
// at 'create' (what-if passes because it simulates the will-exist state).
// adminUsername and sshRSAPublicKey are already @secure() params flowing into
// this template, so passing them directly is both correct and safe.
// The KV still stores them for ESO and manual access in later steps.
module aksModule 'aks.bicep' = {
  name: 'aksDeployment'
  scope: rg
  dependsOn: [kvModule]
  params: {
    location: location
    resourceGroupName: resourceGroupName
    managedCluserName: managedCluserName
    adminUsername: adminUsername
    sshRSAPublicKey: sshRSAPublicKey
  }
}

// ─── Outputs kvModule ─────────────────────────────────────────────────────────
output kvName string = kvModule.outputs.kvName
output kvUri string = kvModule.outputs.kvUri
// FIX: was kvModule.keyVault.id — modules only expose outputs, not internal resources
output kvResourceId string = kvModule.outputs.kvResourceId

// ─── Outputs aksModule ────────────────────────────────────────────────────────
output clusterName string = aksModule.outputs.clusterName
output clusterFqdn string = aksModule.outputs.clusterFqdn
output oidcIssuerUrl string = aksModule.outputs.oidcIssuerUrl
output nodeResourceGroup string = aksModule.outputs.nodeResourceGroup
output controlPlaneManagedIdentityPrincipalId string = aksModule.outputs.controlPlaneManagedIdentityPrincipalId
output kubeletIdentityClientId string = aksModule.outputs.kubeletIdentityClientId
output kubernetesVersion string = aksModule.outputs.kubernetesVersion
output agentPoolProfiles array = aksModule.outputs.agentPoolProfiles

// ─── Outputs Resource Group ───────────────────────────────────────────────────
output resourceGroupId string = rg.id
