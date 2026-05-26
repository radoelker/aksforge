// ─────────────────────────────────────────────────────────────────────────────
// main.bicepparam
//
// Static parameters — safe to commit to Git.
// Sensitive parameters (deployerObjectId, sshRSAPublicKey) are passed via
// CLI at deploy time and never stored here.
//
// Usage:
//   az deployment sub create \
//     --location eastus \
//     --template-file aks_bicep/main.bicep \
//     --parameters aks_bicep/main.bicepparam \
//     --parameters \
//         deployerObjectId=$(az ad signed-in-user show --query id -o tsv) \
//         sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)"
// ─────────────────────────────────────────────────────────────────────────────

using 'main.bicep'

param location         = 'eastus'
param suffix           = 'rainer'
param adminUsername    = 'azureuser'
param kubernetesVersion = '1.34.7'

// deployerObjectId  → pass via CLI: --parameters deployerObjectId=$(az ad signed-in-user show --query id -o tsv)
// sshRSAPublicKey   → pass via CLI: --parameters sshRSAPublicKey="$(cat ~/.ssh/id_rsa.pub)"
