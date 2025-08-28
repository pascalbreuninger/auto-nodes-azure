terraform {
  required_version = ">= 1.5"
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~>1.5"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

locals {
  resource_group_name = var.vcluster.requirements["resource-group"]
  location            = var.vcluster.requirements["location"]

  vcluster_name      = nonsensitive(var.vcluster.instance.metadata.name)
  vcluster_namespace = var.vcluster.instance.metadata.namespace

  vnet_name           = "${local.vcluster_name}-vnet"
  vnet_cidr           = "10.0.0.0/16"
  public_subnet_cidr  = "10.0.2.0/24"
  public_subnet_name  = "${local.vcluster_name}-public"
  private_subnet_cidr = "10.0.1.0/24"
  private_subnet_name = "${local.vcluster_name}-private"
  bucket_name         = var.vcluster.name
}

provider "azurerm" {
  features {}
}

# Networking
resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  address_space       = [local.vnet_cidr]
  location            = local.location
  resource_group_name = local.resource_group_name
}

resource "azurerm_subnet" "private" {
  name                 = local.private_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [local.private_subnet_cidr]
}

resource "azurerm_subnet" "public" {
  name                 = local.public_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name

  address_prefixes = [local.public_subnet_cidr]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "${local.vcluster_name}-public-ip"
  location            = local.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "main" {
  name                = "${local.vcluster_name}-nat-gateway"
  location            = local.location
  resource_group_name = local.resource_group_name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.public_ip.id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  nat_gateway_id = azurerm_nat_gateway.main.id
  subnet_id      = azurerm_subnet.private.id
}

# Security Groups
resource "azurerm_network_security_group" "public" {
  name                = "${local.vcluster_name}-nsg-public"
  location            = local.location
  resource_group_name = local.resource_group_name

  # Allow HTTP inbound
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS inbound
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH inbound
  security_rule {
    name                       = "AllowSSH"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_network_security_group" "private" {
  name                = "${local.vcluster_name}-nsg-private"
  location            = local.location
  resource_group_name = local.resource_group_name

  # Allow inbound traffic from public subnet
  security_rule {
    name                       = "AllowFromPublicSubnet"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = local.public_subnet_cidr
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic from internet
  security_rule {
    name                       = "DenyInternetInbound"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private.id
}
