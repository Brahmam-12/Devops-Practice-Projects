resource "azurerm_resource_group" "rsg" {
  name = var.resource_group_name
  location = var.location
}

resource "azurerm_service_plan" "asp" {
  resource_group_name = azurerm_resource_group.rsg.name
  location = "Canada Central"
  sku_name = "B1"
  os_type = "Linux"
  name = var.app_service_plan
}

resource "azurerm_linux_web_app" "webapp" {
  name = var.web_app_name
  location = "Canada Central"
  service_plan_id = azurerm_service_plan.asp.id
  resource_group_name = azurerm_resource_group.rsg.name
  site_config {
    always_on = false
  }
}