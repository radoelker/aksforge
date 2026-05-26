// ─────────────────────────────────────────────────────────────────────────────
// modules/vnet.bicep
//
// Creates the virtual network that owns all subnets.
// AKS nodes are placed in snet-aks-nodes (Azure CNI Overlay — node IPs from
// here, pod IPs from overlay 10.244.0.0/16).
// All private endpoints (ACR, Cosmos DB, Redis) land in snet-private-endpoints.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param suffix string

var vnetName = 'vnet-aks-prod-${suffix}'

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        // AKS node pool NICs receive IPs from this range.
        // /22 = 1 024 addresses, sufficient for node count + Azure CNI overhead.
        name: 'snet-aks-nodes'
        properties: {
          addressPrefix: '10.1.0.0/22'
          // Must be Disabled to allow private endpoints in this subnet if needed.
          // Node subnet itself does not host PEs but set consistently.
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        // All private endpoints (ACR, Cosmos DB, Redis) land here.
        // /24 = 256 addresses; each PE consumes 1 IP.
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.1.4.0/24'
          // Required: NSG and UDR policies must be disabled on PE subnets.
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output vnetId string = vnet.id
output vnetName string = vnet.name
output aksNodeSubnetId string = '${vnet.id}/subnets/snet-aks-nodes'
output privateEndpointSubnetId string = '${vnet.id}/subnets/snet-private-endpoints'
