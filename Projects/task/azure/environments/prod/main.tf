terraform {
  required_version = ">=1.1"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.0"
    }
  }
  backend "azurerm" {
    storage_account_name = var.storage_account_name
    container_name = var.container_name
    resource_group_name = var.storage-rsg
    key = "prod.tfstate"
  }
}

provider "azurerm" {
  features {}
}
module "resource" {
  source = "../../modules/resource"
  rsg = var.rsg
  location = var.location
}

module "webapp" {
  source = "../../modules/webapp"
  resource_group_name = module.resource.name
  location = var.location
  web_app = var.web_app
  service_plan = var.service_plan
}