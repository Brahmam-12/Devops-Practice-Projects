resource "azurerm_resource_group" "rsg" {
    name = var.resource_group_name
    location = var.location
}

resource "azurerm_service_plan" "asp" {
  name = var.app_service_plan
  location = "Canada Central"
  resource_group_name = azurerm_resource_group.rsg.name
  os_type = "Linux"
  sku_name = "B1"
}

resource "azurerm_linux_web_app" "web_app" {
  name = var.webapp_name
  location = "Canada Central"
  resource_group_name = azurerm_resource_group.rsg.name
  service_plan_id = azurerm_service_plan.asp.id
  site_config {
    always_on = false
  }
}

# One container registry shared by all three environments. Each env has its own
# state file, so this is created only where create_acr = true (dev.tfvars) and
# skipped in qa/prod — otherwise we would end up with three identical registries.
resource "azurerm_container_registry" "acr" {
  count = var.create_acr ? 1 : 0

  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rsg.name
  location            = "Canada Central"
  sku                 = "Basic"
  admin_enabled       = false
}

output "acr_login_server" {
  value = var.create_acr ? azurerm_container_registry.acr[0].login_server : null
}