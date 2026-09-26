terraform {
  required_version = ">=1.1"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.0"
    }
  }
  backend "azurerm" {
  }
}

provider "azurerm" {
  features {}
}

module "resource" {
  source = "../../modules/resource"

  rsg      = var.rsg
  location = var.location
}

module "webapp" {
  source = "../../modules/webapp"

  # This is the answer to "how does the module get the RG name":
  # it comes from the other module's output, not from a hardcoded string.
  # It also tells Terraform to create the RG before the app service plan.
  resource_group_name = module.resource.name
  location            = module.resource.location

  service_plan = var.service_plan
  web_app      = var.web_app
}
