output "web_app_name" {
  value       = azurerm_linux_web_app.web_app.name
  description = "Name of the deployed web app"
}

output "default_hostname" {
  value       = azurerm_linux_web_app.web_app.default_hostname
  description = "URL the web app is reachable on"
}

output "service_plan_id" {
  value       = azurerm_service_plan.service_plan.id
  description = "ID of the App Service plan"
}
