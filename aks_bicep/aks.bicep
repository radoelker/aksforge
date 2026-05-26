// No targetScope here — defaults to 'resourceGroup', which is correct

param location string
param resourceGroupName string
param managedCluserName string
@secure()
param adminUsername string
@secure()
param sshRSAPublicKey string


// ─── AKS Managed Cluster ──────────────────────────────────────────────────────
resource managedCluserName_resource 'Microsoft.ContainerService/managedClusters@2026-01-02-preview' = {
  name: managedCluserName
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
      // ── System pool (fixed VMs — never spot) ──────────────────────────────
      // Runs kube-system, ArgoCD, ingress, monitoring. Must not be evictable.
      {
        name: 'agentpool'
        count: 2
        vmSize: 'Standard_D4pds_v5'
        osDiskSizeGB: 150
        osDiskType: 'Ephemeral'
        kubeletDiskType: 'OS'
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        availabilityZones: [ '1', '2', '3' ]
        maxCount: 5
        minCount: 2
        enableAutoScaling: true
        scaleDownMode: 'Delete'
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
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: sshRSAPublicKey
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: { enabled: false }
      azurepolicy: { enabled: false }
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
        managedOutboundIPs: { count: 1 }
        backendPoolType: 'nodeIPConfiguration'
      }
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      outboundType: 'loadBalancer'
      podCidrs: [ '10.244.0.0/16' ]
      serviceCidrs: [ '10.0.0.0/16' ]
      ipFamilies: [ 'IPv4' ]
      advancedNetworking: {
        enabled: false
        observability: { enabled: false }
        security: {
          enabled: false
          advancedNetworkPolicies: 'None'
        }
        performance: { accelerationMode: 'None' }
      }
      podLinkLocalAccess: 'IMDS'
    }
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
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
      workloadIdentity: { enabled: true }
    }
    storageProfile: {
      diskCSIDriver: { enabled: true }
      fileCSIDriver: { enabled: true }
      snapshotController: { enabled: true }
    }
    oidcIssuerProfile: { enabled: true }
    nodeProvisioningProfile: {
      mode: 'Manual'
      defaultNodePools: 'Auto'
    }
    bootstrapProfile: {
      artifactSource: 'Direct'
    }
  }
}

// ─── User Node Pool ───────────────────────────────────────────────────────────
// Purpose  : application workloads (frontend, backend) + ARC CI runners
// Regular  : on-demand VMs — subscription LowPriorityCores quota is 3, not
//            enough for one D4pds_v5 spot node (4 vCPU). To switch to spot,
//            add scaleSetPriority: 'Spot' + spotMaxPrice: -1 after requesting
//            a quota increase of ≥ 16 lowPriorityCores.
// Taint    : kubernetes.azure.com/scalesetpriority=spot:NoSchedule is kept so
//            k8s manifests written for the spot architecture work unchanged.
// Stateful : Prometheus, Loki, SonarQube, PostgreSQL pinned to system pool
//            via nodeSelector — must never run here.
resource managedCluserName_userpool 'Microsoft.ContainerService/managedClusters/agentPools@2026-01-02-preview' = {
  parent: managedCluserName_resource
  name: 'userpool'
  properties: {
    count: 1
    vmSize: 'Standard_D4pds_v5'
    osDiskSizeGB: 150
    osDiskType: 'Ephemeral'
    kubeletDiskType: 'OS'
    maxPods: 110
    type: 'VirtualMachineScaleSets'
    availabilityZones: [ '1', '2', '3' ]
    maxCount: 10
    minCount: 1
    enableAutoScaling: true
    scaleDownMode: 'Delete'
    scaleSetPriority: 'Spot'
    spotMaxPrice: -1  
    nodeTaints: [
      'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
    ]
    powerState: { code: 'Running' }
    orchestratorVersion: '1.34.7'
    enableNodePublicIP: false
    mode: 'User'
    osType: 'Linux'
    osSKU: 'Ubuntu'
    // upgradeStrategy + upgradeSettings omitted — causes API errors on this pool;
    // add back with maxSurge: '10%' + maxUnavailable: '0' if AKS accepts them.
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

// ─── Outputs ──────────────────────────────────────────────────────────────────
output clusterName string = managedCluserName_resource.name

output clusterFqdn string = managedCluserName_resource.properties.fqdn
// e.g. aks-prod-bicep-rainer-dns.hcp.eastus.azmk8s.io

// clusterPrivateFqdn output removed — privateFQDN property is absent entirely
// on public clusters (not just null), so ?? fallback doesn't save it from
// a DeploymentOutputEvaluationFailed error. Re-add only if switching to private.

output nodeResourceGroup string = managedCluserName_resource.properties.nodeResourceGroup
// The auto-created MC_ resource group holding nodes, load balancers, public IPs

output oidcIssuerUrl string = managedCluserName_resource.properties.oidcIssuerProfile.issuerURL
// Needed for workload identity federation

output kubeletIdentityObjectId string = managedCluserName_resource.properties.identityProfile.kubeletidentity.objectId
// Useful for RBAC role assignments (e.g. AcrPull)

output kubeletIdentityClientId string = managedCluserName_resource.properties.identityProfile.kubeletidentity.clientId
// Needed for workload identity and pod annotations

output controlPlaneManagedIdentityPrincipalId string = managedCluserName_resource.identity.principalId
// Use this to assign roles to the cluster's system-assigned identity

output kubernetesVersion string = managedCluserName_resource.properties.kubernetesVersion

output agentPoolProfiles array = managedCluserName_resource.properties.agentPoolProfiles
// Returns node count, VM size, provisioning state etc.
