// ─────────────────────────────────────────────────────────────────────────────
// modules/role-kv-secrets-user.bicep
//
// Assigns Key Vault Secrets Officer to the AKS kubelet identity.
// Officer = get/list/set/delete secrets. Superset of Secrets User (read-only)
// but required because External Secrets Operator also needs to write the
// synced secret versions back. Can be downgraded to Secrets User
// (4633458b-17de-408a-b874-0445c86b69e0) after confirming ESO only needs read.
// ─────────────────────────────────────────────────────────────────────────────

param kvName string
param kubeletObjectId string

var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

resource kvSecretsOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, kubeletObjectId, kvSecretsOfficerRoleId)
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/${kvSecretsOfficerRoleId}'
    principalId: kubeletObjectId
    principalType: 'ServicePrincipal'
  }
}
