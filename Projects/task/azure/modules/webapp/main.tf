resource "azurerm_service_plan" "service_plan" {
  name                = var.service_plan
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name
}

resource "azurerm_linux_web_app" "web_app" {
  name                = var.web_app
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.service_plan.id

  site_config {
    always_on = false
  }
}
