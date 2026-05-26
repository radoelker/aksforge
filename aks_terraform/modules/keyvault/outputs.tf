output "kv_name" {
  value = azurerm_key_vault.main.name
}

output "kv_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "kv_resource_id" {
  value = azurerm_key_vault.main.id
}
