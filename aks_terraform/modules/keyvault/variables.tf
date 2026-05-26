variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "kv_name" {
  type = string
}

variable "deployer_object_id" {
  description = "Object ID of the principal that will manage secrets"
  type        = string
}

variable "deployer_principal_type" {
  type    = string
  default = "User"
}

variable "admin_username" {
  type      = string
  sensitive = true
}

variable "ssh_rsa_public_key" {
  type      = string
  sensitive = true
}
