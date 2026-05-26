// ─────────────────────────────────────────────────────────────────────────────
// modules/redis.bicep
//
// Azure Cache for Redis — Premium P1 SKU.
// Premium is required for private endpoint support.
// Public network access disabled; backend pods connect via the private
// endpoint resolved through the private DNS zone.
//
// Connection string format written to Key Vault:
//   <hostname>:6380,password=<primaryKey>,ssl=True,abortConnect=False
// This is the StackExchange.Redis / ioredis-compatible format.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param redisName string
param privateEndpointSubnetId string
param vnetId string

// ── Redis Cache ───────────────────────────────────────────────────────────────

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: redisName
  location: location
  properties: {
    sku: {
      name: 'Premium'
      family: 'P'
      capacity: 1 // P1: 6 GB, ~12 000 ops/sec. Scale up to P2/P3 as needed.
    }
    enableNonSslPort: false // TLS-only; port 6380.
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    redisConfiguration: {
      // Keep default eviction policy (volatile-lru). Override here if needed.
    }
  }
}

// ── Private Endpoint ─────────────────────────────────────────────────────────

resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: 'pe-${redisName}'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${redisName}-conn'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: [
            'redisCache' // Sub-resource for Azure Cache for Redis.
          ]
        }
      }
    ]
  }
}

// ── Private DNS Zone ──────────────────────────────────────────────────────────

resource redisDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
}

resource redisDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: redisDnsZone
  name: 'link-vnet-redis'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource redisDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: redisPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-redis-cache-windows-net'
        properties: {
          privateDnsZoneId: redisDnsZone.id
        }
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output redisId string = redis.id
output redisHostName string = redis.properties.hostName

// Redis connection string — written to Key Vault by main.bicep.
// Same security note as cosmos.bicep: value exists in ARM deployment record.
@secure()
output connectionString string = '${redis.properties.hostName}:6380,password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
