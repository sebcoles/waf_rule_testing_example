# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = ">= 2.26"
  features {}
}

# Create Azure Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.rg_name}-rg"
  location = var.rg_location
}

resource "azurerm_app_service_plan" "asp" {
  name                = "${var.rg_name}-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true

  sku {
    tier = var.app_svc_plan_sku_tier
    size = var.app_svc_plan_sku_size
  }
}

resource "azurerm_app_service" "apsvc" {
  name                = "apsvc"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.asp.id

  site_config {
    /* Provision voting App from https://github.com/Azure-Samples/azure-voting-app-redis */
    linux_fx_version = "COMPOSE|${filebase64("../app/docker-compose.yaml")}"
    /* 
    App Service access limited to FrontDoor Only
    Following are Internal Azure IPs for Frontend Backend and Azure Services from docs here
    https://docs.microsoft.com/en-us/azure/frontdoor/front-door-faq#how-do-i-lock-down-the-access-to-my-backend-to-only-azure-front-door
    */

    ip_restriction = [
      {
        ip_address                = "147.243.0.0/16",
        virtual_network_subnet_id = null
        subnet_id                 = null
        name                      = "allowfrontdooripv4"
        description               = "allowfrontdooripv4"
        priority                  = 300
        action                    = "Allow"
        service_tag               = null
        headers                   = []
        }, {
        ip_address                = "2a01:111:2050::/44",
        virtual_network_subnet_id = null
        subnet_id                 = null
        name                      = "allowfrontdooripv6"
        description               = "allowfrontdooripv6"
        priority                  = 350
        action                    = "Allow"
        service_tag               = null
        headers                   = []
        }, {
        ip_address                = "168.63.129.16/32",
        virtual_network_subnet_id = null
        subnet_id                 = null
        name                      = "azureinfrasvcstart"
        description               = "azureinfrasvcstart"
        priority                  = 400
        action                    = "Allow"
        service_tag               = null
        headers                   = []
        }, {
        ip_address                = "169.254.169.254/32",
        virtual_network_subnet_id = null
        subnet_id                 = null
        name                      = "azureinfrasvcend "
        description               = "azureinfrasvcend"
        priority                  = 450
        action                    = "Allow"
        service_tag               = null
        headers                   = []
    }]
  }

  app_settings = {
    "DOCKER_REGISTRY_SERVER_URL" = "https://mcr.microsoft.com",
  }
}

resource "azurerm_frontdoor_firewall_policy" "demowafpolicy" {
  name                              = "wafpolicy"
  resource_group_name               = azurerm_resource_group.rg.name
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403
  custom_block_response_body        = "YmxvY2tlZCBieSBmcm9udGRvb3I="

  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.0"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.0"
  }

}

/* Bug/Limitation name of the front door resoure (cvetestfd) has has to be same frontend_endpoint name
https://github.com/terraform-providers/terraform-provider-azurerm/issues/4495
*/
resource "azurerm_frontdoor" "cvetestfd" {
  name                = "cvetestfd"
  resource_group_name = azurerm_resource_group.rg.name

  routing_rule {
    name               = "votingDemoRoutingRule1"
    accepted_protocols = ["Https"]
    patterns_to_match  = ["/*"]
    frontend_endpoints = ["cvetestfd"]
    forwarding_configuration {
      forwarding_protocol                   = "HttpsOnly"
      backend_pool_name                     = "votingDemoBackend"
      cache_enabled                         = true
      cache_query_parameter_strip_directive = "StripNone"
      cache_use_dynamic_compression         = true
    }

  }

  backend_pool_load_balancing {
    name = "votingDemoLoadBalancingSettings1"

  }

  backend_pool_health_probe {
    name     = "votingDemoHealthProbeSetting1"
    protocol = "Https"
  }

  backend_pool {
    name = "votingDemoBackend"
    backend {
      host_header = "${azurerm_app_service.apsvc.name}.azurewebsites.net"
      address     = "${azurerm_app_service.apsvc.name}.azurewebsites.net"
      http_port   = 80
      https_port  = 443
    }

    load_balancing_name = "votingDemoLoadBalancingSettings1"
    health_probe_name   = "votingDemoHealthProbeSetting1"
  }

  backend_pool_settings {
    enforce_backend_pools_certificate_name_check = false
  }

  frontend_endpoint {
    name                                    = "cvetestfd" //bug 4495 "cvetestfd"
    host_name                               = "cvetestfd.azurefd.net"
    session_affinity_enabled                = false
    session_affinity_ttl_seconds            = 0
    web_application_firewall_policy_link_id = azurerm_frontdoor_firewall_policy.demowafpolicy.id
  }

}

resource "azurerm_frontdoor_custom_https_configuration" "example_custom_https_0" {
  frontend_endpoint_id              = azurerm_frontdoor.cvetestfd.frontend_endpoints["cvetestfd"]
  custom_https_provisioning_enabled = false
}