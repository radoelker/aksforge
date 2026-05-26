// No targetScope — runs at resource group scope, called as a module from main.bicep

param location string
param kvName string
param deployerObjectId string   // object ID of the person/SP running the deployment
                                // az ad signed-in-user show --query id -o tsv
@allowed(['User', 'ServicePrincipal', 'Group'])
param deployerPrincipalType string = 'User'

@secure()
param adminUsername string

@secure()
param sshRSAPublicKey string

// ─── Key Vault ────────────────────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true     // IAM roles instead of legacy access policies
    enableSoftDelete: true
    softDeleteRetentionInDays: 7      // 7 is the lab/dev minimum
    // FIX: was true — with purge protection on, a deleted vault is unreachable for
    // the full retention period. During a course/dev cycle you will redeploy often;
    // a soft-deleted vault with the same name blocks every subsequent deployment.
    // Set to true when promoting to a long-lived production environment.
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'    // lock down to a private endpoint in hardened envs
    networkAcls: {
      defaultAction: 'Allow'          // tighten to 'Deny' + add IP rules for production
      bypass: 'AzureServices'
    }
  }
}

// ─── Secrets ──────────────────────────────────────────────────────────────────
resource secretAdminUsername 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'aks-admin-username'
  properties: {
    value: adminUsername
    attributes: { enabled: true }
  }
}

resource secretSshPublicKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'aks-ssh-public-key'
  properties: {
    value: sshRSAPublicKey
    attributes: { enabled: true }
  }
}

// ─── RBAC: give the deployer rights to manage secrets ─────────────────────────
// Key Vault Secrets Officer = create/read/update/delete secrets (not keys or certs)
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource roleAssignmentDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deployerObjectId, kvSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficerRoleId)
    principalId: deployerObjectId
    principalType: deployerPrincipalType
  }
}

// ─── Outputs ──────────────────────────────────────────────────────────────────
output kvName string = keyVault.name
output kvUri string = keyVault.properties.vaultUri
output kvResourceId string = keyVault.id
