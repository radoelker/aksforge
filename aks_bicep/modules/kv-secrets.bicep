// ─────────────────────────────────────────────────────────────────────────────
// modules/kv-secrets.bicep
//
// Writes all runtime secrets into the existing Key Vault.
// Scoped to the KV resource group (aks-bicep-<suffix>-rg-kv).
//
// Secrets written:
//   cosmos-mongodb-connection-string  → consumed by ExternalSecret in backend ns
//   redis-connection-string           → consumed by ExternalSecret in backend ns
//   aks-admin-username                → informational / break-glass
//   aks-ssh-public-key                → informational / break-glass
//
// The deployer principal receives Key Vault Secrets Officer for this deployment
// so secrets can be written. The kubelet identity receives Key Vault Secrets
// User (read-only) — assigned in main.bicep.
// ─────────────────────────────────────────────────────────────────────────────

param kvName string
param deployerObjectId string

@secure()
param cosmosConnectionString string

@secure()
param redisConnectionString string

param adminUsername string

@secure()
param sshPublicKey string

// ── Role definition IDs (built-in, subscription-scoped) ──────────────────────

// Key Vault Secrets Officer: can set/get/list/delete secrets. Not certificates.
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

// ── Existing Key Vault ────────────────────────────────────────────────────────

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

// ── Deployer role assignment ──────────────────────────────────────────────────
// Ensures this deployment can write secrets regardless of prior state.
// Idempotent: guid() produces the same name on every run.

resource deployerSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, deployerObjectId, kvSecretsOfficerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      kvSecretsOfficerRoleId
    )
    principalId: deployerObjectId
    principalType: 'User'
  }
}

// ── Secrets ───────────────────────────────────────────────────────────────────
// dependsOn role assignment to avoid a race condition where the secret write
// arrives before RBAC propagation completes.

resource cosmosSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'cosmos-mongodb-connection-string'
  properties: {
    value: cosmosConnectionString
    attributes: {
      enabled: true
    }
  }
  dependsOn: [deployerSecretsOfficer]
}

resource redisSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'redis-connection-string'
  properties: {
    value: redisConnectionString
    attributes: {
      enabled: true
    }
  }
  dependsOn: [deployerSecretsOfficer]
}

resource adminUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'aks-admin-username'
  properties: {
    value: adminUsername
    attributes: {
      enabled: true
    }
  }
  dependsOn: [deployerSecretsOfficer]
}

resource sshPublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'aks-ssh-public-key'
  properties: {
    value: sshPublicKey
    attributes: {
      enabled: true
    }
  }
  dependsOn: [deployerSecretsOfficer]
}
