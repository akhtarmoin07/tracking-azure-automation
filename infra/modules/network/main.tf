resource "azurerm_virtual_network" "avd" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}
resource "azurerm_subnet" "hosts" {
  name                 = "session-hosts"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.host_subnet_cidr]
}
resource "azurerm_subnet" "endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.avd.name
  address_prefixes     = [var.endpoint_subnet_cidr]
}
resource "azurerm_network_security_group" "hosts" {
  name                = "nsg-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  security_rule {
    name                       = "DenyInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "hosts" {
  subnet_id                 = azurerm_subnet.hosts.id
  network_security_group_id = azurerm_network_security_group.hosts.id
}
# Explicit outbound connectivity. AVD uses reverse connect; no public host IP/RDP.
# Production: route via the corporate firewall and validate the documented AVD URL list.
resource "azurerm_public_ip" "egress" {
  name                = "pip-egress-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway" "egress" {
  name                = "nat-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Standard"
  tags                = var.tags
}
resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.egress.id
}
resource "azurerm_subnet_nat_gateway_association" "hosts" {
  subnet_id      = azurerm_subnet.hosts.id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}
resource "azurerm_private_dns_zone" "files" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}
resource "azurerm_private_dns_zone_virtual_network_link" "files" {
  name                  = "link-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.files.name
  virtual_network_id    = azurerm_virtual_network.avd.id
  registration_enabled  = false
  tags                  = var.tags
}
