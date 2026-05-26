// ─────────────────────────────────────────────────────────────────────────────
// modules/aks.bicep
//
// AKS cluster with:
//   - Azure CNI Overlay (node IPs from VNet, pod IPs from overlay CIDR)
//   - networkPolicy: azure  (enables NetworkPolicy enforcement — was 'none')
//   - System node pool: Standard_D4pds_v5 ARM64, fixed, zones 1/2/3
//   - User node pool:   Standard_D4pds_v5 ARM64, spot, zones 1/2/3
//   - OIDC issuer + Workload Identity enabled (GitHub Actions OIDC, ESO)
//   - Patch auto-upgrade channel
//
// NOTE: All Docker images and Helm charts must support linux/arm64.
//       Build images with: docker buildx build --platform linux/amd64,linux/arm64
// ─────────────────────────────────────────────────────────────────────────────

param location string
param clusterName string
param aksNodeSubnetId string
param adminUsername string

@secure()
param sshRSAPublicKey string

// Pin to the version confirmed working. Patch upgrades handled automatically
// via upgradeChannel: patch.
param kubernetesVersion string = '1.34.7'

// ── Cluster ───────────────────────────────────────────────────────────────────

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  identity: {
    // SystemAssigned gives the control plane a Managed Identity automatically.
    // The kubelet identity (for ACR pull, Key Vault) is a separate identity
    // that AKS provisions alongside the cluster.
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'

    agentPoolProfiles: [
      {
        // ── System pool ─────────────────────────────────────────────────────
        // Fixed (non-spot) nodes for system workloads: CoreDNS, kube-proxy,
        // NGINX Ingress, ArgoCD, Prometheus, Loki, SonarQube.
        name: 'agentpool'
        count: 2
        minCount: 2
        maxCount: 5
        enableAutoScaling: true
        vmSize: 'Standard_D4pds_v5' // ARM64 (Ampere Altra), 4 vCPU, 16 GB RAM.
        osType: 'Linux'
        osSKU: 'Ubuntu'
        osDiskType: 'Ephemeral' // Faster I/O, no persistent OS disk cost.
        osDiskSizeGB: 150
        mode: 'System'
        availabilityZones: ['1', '2', '3']
        vnetSubnetID: aksNodeSubnetId
        maxPods: 110
        upgradeSettings: {
          maxSurge: '10%'
        }
      }
      {
        // ── User / spot pool ────────────────────────────────────────────────
        // Spot nodes for application workloads and ARC self-hosted runners.
        // Taint: kubernetes.azure.com/scalesetpriority=spot:NoSchedule
        // App pods must declare the matching toleration and nodeSelector.
        // Stateful workloads (Prometheus PVC, Loki, SonarQube) must NOT
        // run here — pin them to agentpool via nodeSelector.
        name: 'userpool'
        count: 0 // Starts at 0; KEDA and Cluster Autoscaler scale as needed.
        minCount: 0
        maxCount: 10
        enableAutoScaling: true
        vmSize: 'Standard_D4pds_v5'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        osDiskType: 'Ephemeral'
        osDiskSizeGB: 150
        mode: 'User'
        availabilityZones: ['1', '2', '3']
        vnetSubnetID: aksNodeSubnetId
        maxPods: 110
        scaleSetPriority: 'Spot'
        scaleSetEvictionPolicy: 'Delete'
        // -1 = pay at most the on-demand price (never exceeds it).
        spotMaxPrice: json('-1')
        nodeTaints: [
          'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
        ]
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay' // Pods use overlay CIDR, not VNet IPs.
      // 'azure' enables Azure Network Policy; enforces NetworkPolicy manifests.
      // This replaces the previous 'none' setting — manifests were silently
      // ignored before; they are now enforced.
      networkPolicy: 'azure'
      podCidr: '10.244.0.0/16' // Overlay pod CIDR, unchanged from original.
      serviceCidr: '10.0.0.0/16' // Kubernetes service CIDR, unchanged.
      dnsServiceIP: '10.0.0.10' // Must be within serviceCidr.
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer' // Nodes NAT outbound via Azure LB.
    }

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

    // OIDC issuer: required for GitHub Actions federated identity (no stored
    // credentials in CI) and for Workload Identity on pods.
    oidcIssuerProfile: {
      enabled: true
    }

    // Workload Identity: allows pods to obtain short-lived tokens via OIDC.
    // Used by External Secrets Operator to authenticate to Key Vault.
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // Patch channel: AKS auto-applies patch upgrades (e.g. 1.34.7 → 1.34.8)
    // during the maintenance windows defined below.
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

// ── Maintenance Windows ───────────────────────────────────────────────────────

// Kubernetes control plane / node image upgrades: Sunday night low-traffic.
resource maintenanceAutoUpgrade 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-02-01' = {
  parent: aks
  name: 'aksManagedAutoUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          dayOfWeek: 'Sunday'
          intervalWeeks: 1
        }
      }
      durationHours: 4
      startTime: '01:00'
      utcOffset: '+00:00'
    }
  }
}

// Node OS (kernel / package) upgrades: Tuesday night.
resource maintenanceNodeOS 'Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-02-01' = {
  parent: aks
  name: 'aksManagedNodeOSUpgradeSchedule'
  properties: {
    maintenanceWindow: {
      schedule: {
        weekly: {
          dayOfWeek: 'Tuesday'
          intervalWeeks: 1
        }
      }
      durationHours: 4
      startTime: '01:00'
      utcOffset: '+00:00'
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────

output clusterName string = aks.name
output clusterFqdn string = aks.properties.fqdn
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
// kubeletidentity (lowercase) is the key AKS uses in identityProfile.
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output kubeletIdentityClientId string = aks.properties.identityProfile.kubeletidentity.clientId
output controlPlanePrincipalId string = aks.identity.principalId
output nodeResourceGroup string = aks.properties.nodeResourceGroup
