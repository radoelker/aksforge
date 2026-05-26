targetScope = 'subscription'

// ─── Parameters ───────────────────────────────────────────────────────────────
param subscriptionId string = '<subscriptionID>'
param location string = 'eastus'
param resourceGroupName string = 'aks-bicep-rainer-rg'
param managedCluserName string = 'aks-prod-bicep-rainer'

// ─── Resource Group ───────────────────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

// ─── AKS Managed Cluster ──────────────────────────────────────────────────────
resource managedCluserName_resource 'Microsoft.ContainerService/managedClusters@2026-01-02-preview' = {
  name: managedCluserName
  scope: rg
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  kind: 'Base'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.34.7'
    dnsPrefix: '${managedCluserName}-dns'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 2
        vmSize: 'Standard_D4pds_v5'
        osDiskSizeGB: 150
        osDiskType: 'Ephemeral'
        kubeletDiskType: 'OS'
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        maxCount: 5
        minCount: 2
        enableAutoScaling: true
        scaleDownMode: 'Delete'
        // Spot instances: uncomment the two lines below to allow spot VMs.
        // scaleSetPriority: 'Spot'   // 'Regular' (default) or 'Spot'
        // spotMaxPrice: -1           // -1 = current on-demand price as cap; or set a fixed max e.g. 0.5
        powerState: {
          code: 'Running'
        }
        orchestratorVersion: '1.34.7'
        enableNodePublicIP: false
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        upgradeStrategy: 'Rolling'
        upgradeSettings: {
          maxSurge: '10%'
          maxUnavailable: '0'
        }
        enableFIPS: false
        securityProfile: {
          sshAccess: 'LocalUser'
          enableVTPM: false
          enableSecureBoot: false
        }
      }
    ]
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa ...= rdoelker@DESKTOP-12345K'
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: false
      }
      azurepolicy: {
        enabled: false
      }
    }
    nodeResourceGroup: 'MC_${resourceGroupName}_${managedCluserName}_${location}'
    enableRBAC: true
    supportPlan: 'KubernetesOfficial'
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'none'
      networkDataplane: 'azure'
      loadBalancerSku: 'Standard'
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
        backendPoolType: 'nodeIPConfiguration'
      }
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      outboundType: 'loadBalancer'
      podCidrs: [
        '10.244.0.0/16'
      ]
      serviceCidrs: [
        '10.0.0.0/16'
      ]
      ipFamilies: [
        'IPv4'
      ]
      advancedNetworking: {
        enabled: false
        observability: {
          enabled: false
        }
        security: {
          enabled: false
          advancedNetworkPolicies: 'None'
        }
        performance: {
          accelerationMode: 'None'
        }
      }
      podLinkLocalAccess: 'IMDS'
    }
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
    // identityProfile is intentionally omitted:
    // AKS auto-creates the kubelet managed identity in the MC_ node resource group.
    // Hardcoding clientId/objectId here would bind the template to a specific prior deployment.
    autoScalerProfile: {
      'balance-similar-node-groups': 'false'
      'daemonset-eviction-for-empty-nodes': false
      'daemonset-eviction-for-occupied-nodes': true
      expander: 'random'
      'ignore-daemonsets-utilization': false
      'max-empty-bulk-delete': '10'
      'max-graceful-termination-sec': '600'
      'max-node-provision-time': '15m'
      'max-total-unready-percentage': '45'
      'new-pod-scale-up-delay': '0s'
      'ok-total-unready-count': '3'
      'scale-down-delay-after-add': '10m'
      'scale-down-delay-after-delete': '10s'
      'scale-down-delay-after-failure': '3m'
      'scale-down-unneeded-time': '10m'
      'scale-down-unready-time': '20m'
      'scale-down-utilization-threshold': '0.5'
      'scan-interval': '10s'
      'skip-nodes-with-local-storage': 'false'
      'skip-nodes-with-system-pods': 'true'
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    disableLocalAccounts: false
    securityProfile: {
      imageCleaner: {
        enabled: true
        intervalHours: 168
      }
      workloadIdentity: {
        enabled: true
      }
    }
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    nodeProvisioningProfile: {
      mode: 'Manual'
      defaultNodePools: 'Auto'
    }
    bootstrapProfile: {
      artifactSource: 'Direct'
    }
  }
}

// ─── Agent Pool ───────────────────────────────────────────────────────────────
resource managedCluserName_agentpool 'Microsoft.ContainerService/managedClusters/agentPools@2026-01-02-preview' = {
  parent: managedCluserName_resource
  name: 'agentpool'
  properties: {
    count: 2
    vmSize: 'Standard_D4pds_v5'
    osDiskSizeGB: 150
    osDiskType: 'Ephemeral'
    kubeletDiskType: 'OS'
    maxPods: 110
    type: 'VirtualMachineScaleSets'
    availabilityZones: [
      '1'
      '2'
      '3'
    ]
    maxCount: 5
    minCount: 2
    enableAutoScaling: true
    scaleDownMode: 'Delete'
    // Spot instances: uncomment the two lines below to allow spot VMs.
    // scaleSetPriority: 'Spot'   // 'Regular' (default) or 'Spot'
    // spotMaxPrice: -1           // -1 = current on-demand price as cap; or set a fixed max e.g. 0.5
    powerState: {
      code: 'Running'
    }
    orchestratorVersion: '1.34.7'
    enableNodePublicIP: false
    mode: 'System'
    osType: 'Linux'
    osSKU: 'Ubuntu'
    upgradeStrategy: 'Rolling'
    upgradeSettings: {
      maxSurge: '10%'
      maxUnavailable: '0'
    }
    enableFIPS: false
    securityProfile: {
      sshAccess: 'LocalUser'
      enableVTPM: false
      enableSecureBoot: false
    }
  }
}

// ─── Auto Upgrade Maintenance Window ─────────────────────────────────────────
resource managedCluserName_aksManagedAutoUpgradeSchedule 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2026-01-02-preview' = {
  parent: managedCluserName_resource
  name: 'aksManagedAutoUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Sunday'
        }
      }
      durationHours: 8
      utcOffset: '+00:00'
      startDate: '2026-05-19'
      startTime: '00:00'
    }
  }
}

// ─── Node OS Upgrade Maintenance Window ───────────────────────────────────────
resource managedCluserName_aksManagedNodeOSUpgradeSchedule 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2026-01-02-preview' = {
  parent: managedCluserName_resource
  name: 'aksManagedNodeOSUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Sunday'
        }
      }
      durationHours: 8
      utcOffset: '+00:00'
      startDate: '2026-05-19'
      startTime: '00:00'
    }
  }
}
