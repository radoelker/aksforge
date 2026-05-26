// ─────────────────────────────────────────────────────────────────────────────
// modules/cosmos.bicep
//
// Azure Cosmos DB for MongoDB API.
// Public network access disabled; backend pods reach Cosmos via private
// endpoint resolved through the private DNS zone.
//
// THROUGHPUT MODEL: Standard provisioned (not serverless).
//   - Supports zone redundancy and SLA guarantees required for production.
//   - Databases/collections set throughput individually (app layer, not here).
//   - To switch to serverless: replace capabilities with EnableServerless,
//     remove isZoneRedundant, remove EnableAutoscale from capabilities.
//
// OPEN DECISION C: Before migrating backend to Cosmos DB, audit aggregation
//   pipelines, transactions, and index types for MongoDB API compatibility.
//   Cosmos DB for MongoDB API v7.0 has the highest compatibility with
//   native MongoDB but some operators remain unsupported.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param accountName string
param privateEndpointSubnetId string
param vnetId string

// ── Cosmos Account ────────────────────────────────────────────────────────────

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: accountName
  location: location
  kind: 'MongoDB'
  properties: {
    apiProperties: {
      serverVersion: '7.0' // Highest Cosmos DB for MongoDB API compatibility.
    }
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false // Zone-redundant writes for production durability.
      }
    ]
    capabilities: [
      {
        name: 'EnableMongo'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session' // Best balance of consistency / perf.
    }
    publicNetworkAccess: 'Disabled'
    enableAutomaticFailover: false // Single-region; no geo-failover configured.
    // Continuous backup: point-in-time restore up to 7 days.
    // Upgrade to Continuous30Days if longer retention is needed.
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: {
        tier: 'Continuous7Days'
      }
    }
    // Disallow requests using keys (require RBAC / connection string only).
    disableKeyBasedMetadataWriteAccess: false
    // Minimum TLS version.
    minimalTlsVersion: 'Tls12'
  }
}

// ── Private Endpoint ─────────────────────────────────────────────────────────

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${accountName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${accountName}-conn'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'MongoDB' // Sub-resource for Cosmos DB MongoDB API.
          ]
        }
      }
    ]
  }
}

// ── Private DNS Zone ──────────────────────────────────────────────────────────

resource cosmosDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.mongo.cosmos.azure.com'
  location: 'global'
}

resource cosmosDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: cosmosDnsZone
  name: 'link-vnet-cosmos'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource cosmosDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: cosmosPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-mongo-cosmos-azure-com'
        properties: {
          privateDnsZoneId: cosmosDnsZone.id
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name

// Primary MongoDB connection string — written to Key Vault by main.bicep.
// Marked @secure() so the value is redacted in deployment logs and terminal.
// Note: the value still exists in the ARM deployment record; ensure RBAC on
// the subscription restricts who can read deployment history.
@secure()
output connectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
