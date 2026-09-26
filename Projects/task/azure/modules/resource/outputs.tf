# Anything another module needs from this one has to be published here.
# Without an output block, azurerm_resource_group.rsg is invisible outside this folder.
output "name" {
  value       = azurerm_resource_group.rsg.name
  description = "Resource group name, consumed by the other modules"
}

output "location" {
  value       = azurerm_resource_group.rsg.location
  description = "Resource group region, so child modules don't re-declare it"
}

output "id" {
  value       = azurerm_resource_group.rsg.id
  description = "Full resource ID of the resource group"
}
