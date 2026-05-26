variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "managed_cluster_name" {
  type = string
}

variable "admin_username" {
  type      = string
  sensitive = true
}

variable "ssh_rsa_public_key" {
  type      = string
  sensitive = true
}
