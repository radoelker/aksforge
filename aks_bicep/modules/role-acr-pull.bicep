// ─────────────────────────────────────────────────────────────────────────────
// modules/role-acr-pull.bicep
// ─────────────────────────────────────────────────────────────────────────────

param acrName string
param kubeletObjectId string

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, kubeletObjectId, acrPullRoleId)
  properties: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/${acrPullRoleId}'
    principalId: kubeletObjectId
    principalType: 'ServicePrincipal'
  }
}
