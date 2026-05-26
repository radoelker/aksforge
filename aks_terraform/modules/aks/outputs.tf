output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "cluster_fqdn" {
  description = "Public API server FQDN"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

# cluster_private_fqdn omitted — the attribute is null on public clusters
# (enablePrivateCluster = false). Terraform returns null cleanly but the
# value is meaningless; include it only if switching to a private cluster.

output "node_resource_group" {
  description = "Auto-created MC_ resource group holding nodes, LBs, public IPs"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL — required for workload identity federation"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID — use for AcrPull RBAC"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "kubelet_identity_client_id" {
  description = "Kubelet managed identity client ID — use for workload identity pod annotations"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].client_id
}

output "control_plane_managed_identity_principal_id" {
  description = "System-assigned identity principal ID of the control plane"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "kubernetes_version" {
  value = azurerm_kubernetes_cluster.main.kubernetes_version
}
