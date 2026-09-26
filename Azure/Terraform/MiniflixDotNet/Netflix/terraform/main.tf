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