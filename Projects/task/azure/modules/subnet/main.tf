resource "azurerm_subnet" "subnet" {
 for_each = var.subnets
 resource_group_name = var.rsg
 virtual_network_name = var.vnet_name
 name = each.value.name
}