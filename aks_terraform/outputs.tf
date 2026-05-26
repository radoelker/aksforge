# ── Key Vault outputs ─────────────────────────────────────────────────────────
output "kv_name" {
  description = "Key Vault name"
  value       = module.keyvault.kv_name
}

output "kv_uri" {
  description = "Key Vault URI"
  value       = module.keyvault.kv_uri
}

output "kv_resource_id" {
  description = "Key Vault resource ID"
  value       = module.keyvault.kv_resource_id
}

# ── AKS outputs ───────────────────────────────────────────────────────────────
output "cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "cluster_fqdn" {
  description = "AKS public API server FQDN"
  value       = module.aks.cluster_fqdn
}

# cluster_private_fqdn intentionally omitted — the property is absent entirely
# on public clusters (enablePrivateCluster = false). Unlike Bicep's ?? operator,
# Terraform would return null cleanly, but the output is meaningless here.

output "oidc_issuer_url" {
  description = "OIDC issuer URL — needed for workload identity federation"
  value       = module.aks.oidc_issuer_url
}

output "node_resource_group" {
  description = "Auto-created MC_ resource group holding nodes and load balancers"
  value       = module.aks.node_resource_group
}

output "control_plane_managed_identity_principal_id" {
  description = "System-assigned identity of the control plane — use for role assignments"
  value       = module.aks.control_plane_managed_identity_principal_id
}

output "kubelet_identity_client_id" {
  description = "Kubelet managed identity client ID — needed for workload identity pod annotations"
  value       = module.aks.kubelet_identity_client_id
}

output "kubelet_identity_object_id" {
  description = "Kubelet managed identity object ID — use for AcrPull RBAC assignment"
  value       = module.aks.kubelet_identity_object_id
}

output "kubernetes_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.aks.kubernetes_version
}

output "resource_group_id" {
  description = "Resource group ID for the AKS cluster"
  value       = azurerm_resource_group.cluster.id
}
