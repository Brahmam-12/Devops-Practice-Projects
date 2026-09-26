# Here we need to create app registartion manually

terraform {
  required_version = ">=1.5"
  required_providers {
    azuread = {
        version = ">=2.0"
        source = "hashicorp/azuread"
    }
    azurerm = {
        version = ">=4.0"
        source = "hashicorp/azurerm"
    }
    azuredevops = {
        version = ">=1.0"
        source = "microsoft/azuredevops"
    }
  }
}

provider "azuread" {
    tenant_id = var.tenant_id
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
provider "azuredevops" {
  org_service_url = ""
  personal_access_token = ""
}

data "azuredevops_project" "netflix"{
    name = var.project_name
}


resource "azuread_application" "netflix-app" {
    display_name = var.app_name
}

resource "azuread_service_principal" "service-principal" {
    client_id = azuread_application.netflix-app.client_id
}

resource "azuread_application_password" "app-pass"{
    application_id = azuread_application.netflix-app.id
    end_date = var.password_expiry
}

resource "azurerm_role_assignment" "role_assignment" {
    principal_id = azuread_service_principal.service-principal.object_id
    role_definition_name = "Contributor"
    scope = "/subscriptions/${var.subscription_id}"
}

resource "azuredevops_serviceendpoint_azurerm" "service" {
    project_id = data.azuredevops_project.netflix.id
    azurerm_spn_tenantid = var.tenant_id
    azurerm_subscription_id = var.subscription_id
    azurerm_subscription_name = var.subscription_name
    service_endpoint_name = var.service_name
    credentials {
      serviceprincipalid = azuread_service_principal.service-principal.client_id
      serviceprincipalkey = azuread_application_password.app-pass.value
    }
}