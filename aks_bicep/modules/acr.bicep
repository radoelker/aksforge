// ─────────────────────────────────────────────────────────────────────────────
// modules/acr.bicep
//
// Azure Container Registry — Premium SKU required for private endpoints.
// Public network access disabled; AKS pulls images via the private endpoint.
// Managed Identity (AcrPull role) is assigned in main.bicep after AKS is
// provisioned so the kubelet object ID is available.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param acrName string
param privateEndpointSubnetId string
param vnetId string

// ── Registry ─────────────────────────────────────────────────────────────────

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium' // Private endpoints require Premium SKU.
  }
  properties: {
    adminUserEnabled: false // Authentication via Managed Identity only.
    publicNetworkAccess: 'Disabled'
    zoneRedundancy: 'Enabled' // Zone-redundant storage for the registry.
    // Allow trusted Azure services (e.g. AKS, ACR Tasks) to bypass the
    // private-only restriction without opening the public endpoint.
    networkRuleBypassOptions: 'AzureServices'
  }
}

// ── Private Endpoint ─────────────────────────────────────────────────────────

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${acrName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${acrName}-conn'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry' // ACR sub-resource group ID.
          ]
        }
      }
    ]
  }
}

// ── Private DNS Zone ──────────────────────────────────────────────────────────

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

resource acrDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: 'link-vnet-acr'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// Binds the private endpoint NIC IP to the DNS zone so ACR hostnames resolve
// to private IPs inside the VNet.
resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azurecr-io'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
