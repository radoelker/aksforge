# ── AKS Managed Cluster ───────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.managed_cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.managed_cluster_name}-dns"
  kubernetes_version  = "1.34.7"
  node_resource_group = "MC_${var.resource_group_name}_${var.managed_cluster_name}_${var.location}"

  sku_tier     = "Free"
  support_plan = "KubernetesOfficial"

  identity {
    type = "SystemAssigned"
  }

  # ── System node pool (fixed VMs — never spot) ───────────────────────────────
  # Runs kube-system, ArgoCD, ingress, monitoring. Must not be evictable.
  default_node_pool {
    name                 = "agentpool"
    vm_size              = "Standard_D4pds_v5"   # ARM64 Ampere Altra
    node_count           = 2
    min_count            = 2
    max_count            = 5
    auto_scaling_enabled = true
    os_disk_size_gb      = 150
    os_disk_type         = "Ephemeral"
    max_pods             = 110
    type                 = "VirtualMachineScaleSets"
    zones                = ["1", "2", "3"]

    upgrade_settings {
      # either or the other, only for only for priority = spot none are possible
      max_surge       = "10%"
      #max_unavailable = "0"
    }
  }

  linux_profile {
    admin_username = var.admin_username
    ssh_key {
      key_data = var.ssh_rsa_public_key
    }
  }

  # ── Networking ───────────────────────────────────────────────────────────────
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "azure"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.0.0.0/16"
    dns_service_ip      = "10.0.0.10"
    ip_versions         = ["IPv4"]
  }

  # ── Security ─────────────────────────────────────────────────────────────────
  oidc_issuer_enabled       = true   # Required for workload identity
  workload_identity_enabled = true

  role_based_access_control_enabled = true
  local_account_disabled            = false

  # ── Auto-upgrade optional─────────────────────────────────────────────────────────────
  # they make trouble - not resolvable -> comment out
  # automatic_channel_upgrade = "patch" # being replaced by automatic_upgrade_channel in 4.x versions of the provider.
  automatic_upgrade_channel = "patch"
  #node_os_channel_upgrade   = "NodeImage"  # changed in 4.x
  node_os_upgrade_channel   = "NodeImage"

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 8
    day_of_week = "Sunday"
    utc_offset  = "+00:00"
    start_time  = "00:00"
    start_date  = "2026-05-19T00:00:00Z"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 8
    day_of_week = "Sunday"
    utc_offset  = "+00:00"
    start_time  = "00:00"
    start_date  = "2026-05-19T00:00:00Z"
  }

  # ── Cluster autoscaler ───────────────────────────────────────────────────────
  auto_scaler_profile {
    balance_similar_node_groups      = false
    expander                         = "random"
    max_graceful_termination_sec     = "600"
    max_node_provisioning_time       = "15m"
    max_unready_nodes                = 3
    max_unready_percentage           = 45
    new_pod_scale_up_delay           = "0s"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scale_down_unneeded              = "10m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = "0.5"
    scan_interval                    = "10s"
    skip_nodes_with_local_storage    = false
    skip_nodes_with_system_pods      = true
    empty_bulk_delete_max            = "10"
  }

  # ── Storage CSI drivers ──────────────────────────────────────────────────────
  storage_profile {
    disk_driver_enabled         = true
    file_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  # ── Image cleaner ────────────────────────────────────────────────────────────
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 168   # weekly
}

# ── User node pool ────────────────────────────────────────────────────────────
# Purpose  : application workloads (frontend, backend) + ARC CI runners
# Regular  : on-demand VMs — subscription LowPriorityCores quota is 3, not
#            enough for one D4pds_v5 spot node (4 vCPU). To switch to spot,
#            uncomment priority + eviction_policy + spot_max_price and request
#            a quota increase of ≥ 16 lowPriorityCores.
# Taint    : kubernetes.azure.com/scalesetpriority=spot:NoSchedule is kept so
#            k8s manifests written for the spot architecture work unchanged —
#            app pods already carry the matching toleration.
# Stateful : Prometheus, Loki, SonarQube, PostgreSQL must stay on the system
#            pool via nodeSelector — never here.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "userpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D4pds_v5"
  node_count            = 1
  min_count             = 1
  max_count             = 10
  auto_scaling_enabled  = true
  os_disk_size_gb       = 150
  os_disk_type          = "Ephemeral"
  max_pods              = 110
  zones                 = ["1", "2", "3"]
  mode                  = "User"
  orchestrator_version  = "1.34.7"
  os_type               = "Linux"
  os_sku                = "Ubuntu"
  node_public_ip_enabled = false

  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]

  # To enable spot: uncomment the three lines below and request quota increase
  # priority        = "Spot"
  # eviction_policy = "Delete"
  # spot_max_price  = -1

  # upgrade_settings omitted — caused API errors on this pool configuration;
  # add back with max_surge = "10%" once confirmed supported by the API version.
}
