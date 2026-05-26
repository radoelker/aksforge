// ─────────────────────────────────────────────────────────────────────────────
// main.bicep  —  subscription-scoped deployment
//
// Deployment order (Bicep resolves dependencies automatically):
//   1. Resource groups
//   2. VNet  (snet-aks-nodes, snet-private-endpoints)
//   3. ACR   (Premium, private endpoint)
//   4. AKS   (Azure CNI Overlay, networkPolicy:azure, custom VNet)
//   5. Cosmos DB (MongoDB API, private endpoint)
//   6. Redis (Premium P1, private endpoint)
//   7. Role assignments (AcrPull + KV Secrets User → kubelet identity)
//   8. KV secrets (cosmos + redis connection strings)
//
// BEFORE RUNNING: delete the existing AKS cluster (vnetSubnetId cannot be
// changed in-place).
//
//   az aks delete \
//     --name aks-prod-bicep-rainer \
//     --resource-group aks-bicep-rainer-rg \
//     --yes --no-wait
//
// DEPLOY:
//   az deployment sub create \
//     --location eastus \
//     --template-file aks_bicep/main.bicep \
//     --parameters \
//         location=eastus \
//         suffix=rainer \
//         adminUsername=azureuser \
//         kubernetesVersion=1.34.7 \
//         deployerObjectId=$(az ad signed-in-user show --query id -o tsv) \
//         sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)" \
//     > ./current_aks.json
// ─────────────────────────────────────────────────────────────────────────────

targetScope = 'subscription'

// ── Parameters ────────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = 'eastus'

@description('Short identifier appended to resource names.')
param suffix string = 'rainer'

@description('Object ID of the principal running this deployment (for KV role assignment).')
param deployerObjectId string

@description('SSH public key for AKS Linux nodes.')
@secure()
param sshRSAPublicKey string

@description('Admin username for AKS Linux nodes.')
param adminUsername string = 'azureuser'

@description('Kubernetes version to deploy.')
param kubernetesVersion string = '1.34.7'

// ── Derived names ─────────────────────────────────────────────────────────────

var clusterName = 'aks-prod-bicep-${suffix}'
var kvName      = 'kv-aks-prod-bicep-003'   // Existing KV — name unchanged.
// ACR name: alphanumeric, globally unique, 5–50 chars.
// uniqueString produces a deterministic 13-char hash of subscription + suffix.
var acrName     = 'acr${uniqueString(subscription().id, suffix)}'
var cosmosName  = 'cosmos-aks-prod-${suffix}'
var redisName   = 'redis-aks-prod-${suffix}'

// ── Resource Groups ───────────────────────────────────────────────────────────

resource rgCluster 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'aks-bicep-${suffix}-rg'
  location: location
}

resource rgKv 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'aks-bicep-${suffix}-rg-kv'
  location: location
}

resource rgData 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'aks-bicep-${suffix}-rg-data'
  location: location
}

// ── VNet ──────────────────────────────────────────────────────────────────────

module vnet 'modules/vnet.bicep' = {
  scope: rgCluster
  name: 'vnetDeployment'
  params: {
    location: location
    suffix: suffix
  }
}

// ── ACR ───────────────────────────────────────────────────────────────────────

module acr 'modules/acr.bicep' = {
  scope: rgCluster
  name: 'acrDeployment'
  params: {
    location: location
    acrName: acrName
    privateEndpointSubnetId: vnet.outputs.privateEndpointSubnetId
    vnetId: vnet.outputs.vnetId
  }
}

// ── AKS ───────────────────────────────────────────────────────────────────────

module aks 'modules/aks.bicep' = {
  scope: rgCluster
  name: 'aksDeployment'
  params: {
    location: location
    clusterName: clusterName
    aksNodeSubnetId: vnet.outputs.aksNodeSubnetId
    adminUsername: adminUsername
    sshRSAPublicKey: sshRSAPublicKey
    kubernetesVersion: kubernetesVersion
  }
}

// ── Cosmos DB ─────────────────────────────────────────────────────────────────

module cosmos 'modules/cosmos.bicep' = {
  scope: rgData
  name: 'cosmosDeployment'
  params: {
    location: location
    accountName: cosmosName
    privateEndpointSubnetId: vnet.outputs.privateEndpointSubnetId
    vnetId: vnet.outputs.vnetId
  }
}

// ── Redis ─────────────────────────────────────────────────────────────────────

module redis 'modules/redis.bicep' = {
  scope: rgData
  name: 'redisDeployment'
  params: {
    location: location
    redisName: redisName
    privateEndpointSubnetId: vnet.outputs.privateEndpointSubnetId
    vnetId: vnet.outputs.vnetId
  }
}

// ── Role assignment: kubelet identity → AcrPull on ACR ───────────────────────
// Inline resource declarations at subscription scope cannot target resources
// in specific RGs (BCP139), so these live in dedicated modules.

module acrPullRole 'modules/role-acr-pull.bicep' = {
  scope: rgCluster
  name: 'acrPullRoleDeployment'
  params: {
    acrName: acrName
    kubeletObjectId: aks.outputs.kubeletIdentityObjectId
  }
}

// ── Role assignment: kubelet identity → Key Vault Secrets User ───────────────

module kvSecretsUserRole 'modules/role-kv-secrets-user.bicep' = {
  scope: rgKv
  name: 'kvSecretsUserRoleDeployment'
  params: {
    kvName: kvName
    kubeletObjectId: aks.outputs.kubeletIdentityObjectId
  }
}

// ── KV Secrets ────────────────────────────────────────────────────────────────

module kvSecrets 'modules/kv-secrets.bicep' = {
  scope: rgKv
  name: 'kvSecretsDeployment'
  params: {
    kvName: kvName
    deployerObjectId: deployerObjectId
    cosmosConnectionString: cosmos.outputs.connectionString
    redisConnectionString: redis.outputs.connectionString
    adminUsername: adminUsername
    sshPublicKey: sshRSAPublicKey
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output clusterName string = clusterName
output clusterFqdn string = aks.outputs.clusterFqdn
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
output kubeletIdentityClientId string = aks.outputs.kubeletIdentityClientId
output acrLoginServer string = acr.outputs.acrLoginServer
output kvName string = kvName
// environment().suffixes.keyvaultDns = '.vault.azure.net' (no hardcoded URL)
output kvUri string = 'https://${kvName}${environment().suffixes.keyvaultDns}/'
output cosmosAccountName string = cosmos.outputs.cosmosAccountName
output redisHostName string = redis.outputs.redisHostName
output nodeResourceGroup string = aks.outputs.nodeResourceGroup
