variable "subscription_id" {
  description = "Azure subscription ID (required by AzureRM provider v4)"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the main resource group (AKS cluster + networking)"
  type        = string
  default     = "aks-tf-rainer-rg"
}

variable "managed_cluster_name" {
  description = "AKS managed cluster name"
  type        = string
  default     = "aks-prod-tf-rainer"
}

variable "deployer_object_id" {
  description = "Object ID of the principal running the deployment. Get it with: az ad signed-in-user show --query id -o tsv"
  type        = string
}

variable "deployer_principal_type" {
  description = "Principal type for the Key Vault Secrets Officer role assignment"
  type        = string
  default     = "User"

  validation {
    condition     = contains(["User", "ServicePrincipal", "Group"], var.deployer_principal_type)
    error_message = "Must be User, ServicePrincipal, or Group."
  }
}

variable "admin_username" {
  description = "Linux admin username for AKS nodes"
  type        = string
  sensitive   = true
}

variable "ssh_rsa_public_key" {
  description = "SSH RSA public key for AKS node access (cat ~/.ssh/id_rsa.pub)"
  type        = string
  sensitive   = true
}

variable "kv_suffix" {
  description = <<-EOT
    Short suffix appended to the Key Vault name.
    Increment (002, 003 …) whenever a soft-deleted vault with the same name
    blocks a fresh deployment — enablePurgeProtection = false prevents the
    vault being purged before the 7-day retention window expires.
  EOT
  type        = string
  default     = "001"
}
