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

provider "azurerm" {
  features {}
}

locals {
  resource_group_name = var.vcluster.requirements["resource-group"]
  location            = var.vcluster.requirements["location"]

  vcluster_name      = var.vcluster.instance.metadata.name
  vcluster_namespace = var.vcluster.instance.metadata.namespace

  vm_name           = "${var.vcluster.name}-${random_id.vm_suffix.hex}"
  private_subnet_id = var.vcluster.nodeEnvironment.outputs["private_subnet_id"]
  instance_type     = var.vcluster.requirements["instance-type"]
  bucket_name       = var.vcluster.name
}

resource "random_id" "vm_suffix" {
  byte_length = 4
}

resource "azurerm_network_interface" "private_vm" {
  name                = "${local.vm_name}-nic"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.private_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

# The node is joined via cloud-init user data
# We don't need the private key
resource "tls_private_key" "vm_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "private_vm" {
  name                = local.vm_name
  resource_group_name = local.resource_group_name
  location            = local.location
  size                = local.instance_type
  admin_username      = "azureuser"

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.private_vm.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm_ssh.public_key_openssh
  }

  user_data = base64encode(var.vcluster.userData)

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 100
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    vcluster  = local.vcluster_name
    namespace = local.vcluster_namespace
  }
}
